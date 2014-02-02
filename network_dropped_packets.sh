#!/bin/bash
#
# Nagios NRPE plugin to monitor the % of dropped packets for the given
# network cards using RX & TX values. The Check result return UNKNOWN for
# first run.
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

# Settings
MINIMUM_PACKET_DIFFERENCE='10000'
KEEP_TRACK_FILE='/tmp/._monitor_dropped_packets_1855_'
MEASURE_UNIT='1000000'    # per million

# Exit status veriables
ST_OK='0'
ST_WR='1'
ST_CR='2'
ST_UK='3'

# Constants
YES='0'
NO='1'
# Delimiters:
D_DIFF_DEVICES=';'
D_DEVICE_AND_DATA='-'
D_DATA_SETS=':'


print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}


print_help() {
    echo ""
    echo "$PROGNAME is a custom Nagios plugin to monitor the % of "
    echo " dropped packets for the given network cards"
    echo ""
    echo "Usage: $PROGNAME -d [<network devices>] [-w <integer>] [-c <integer>]"
    echo ""
    echo "Options:"
    echo "  -d/--devices)"
    echo "     network device names separated by comma. For eg: eth0,eth1"
    echo "     Default value: eth0"
    echo "  -w/--warning)"
    echo "     Defines the no of dropped/error packets per million to raise "
    echo "     warning. Default value: 100"
    echo "  -c/--critical)"
    echo "     Defines the no of dropped/error packets per million to raise "
    echo "     critical alert. Default value: 500"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -d eth0,bond1 -w 50 -c 200"
}


while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit $ST_UK
            ;;
        --version|-v)
            print_version
            exit $ST_UK
            ;;
        --devices|-d)
            devices=$2
            shift
            ;;
        --warning|-w)
            warning=$2
            shift
            ;;
        --critical|-c)
            critical=$2
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo ""
            print_help
            exit $ST_UK
            ;;
        esac
    shift
done


# Set Defaults for $devices variable
if echo $devices | grep "^\s*$" >/dev/null ; then
    devices='eth0'
fi
# Set Defaults for $warning variable
if echo $warning | grep "^\s*$" >/dev/null ; then
    warning='100'
fi
# Set Defaults for $critical variable
if echo $critical | grep "^\s*$" >/dev/null ; then
    critical='500'
fi


get_packet_details() {
    # Get (total, errors, dropped) packet details for device $network_device
    /sbin/ifconfig $network_device 2>/dev/null | \
        awk '/(RX|TX) packets/ {print $2" "$3" "$4}' | \
        sed -e 's/packets://' -e 's/errors://' -e 's/dropped://' | \
        tr '\n' "${D_DATA_SETS}" | sed 's/'"${D_DATA_SETS}"'$//'
}


retrive_current_status() {
    current_status=""
    for network_device in $(echo $devices | tr ',' ' '); do
        packet_details="$(get_packet_details)"
        if [ "X${packet_details}" = "X" ]; then
            continue
        fi
        if echo ${current_status} | grep -v "^\s*$" >/dev/null ; then
            current_status="${current_status};"
        fi
        current_status="${current_status}${network_device}-${packet_details}"
    done
}


formatted_device_status() {
    # Print formatted $current_status
    TEMP_MESSAGE_FILE="/tmp/._mdp_temp_message_$RANDOM"
    echo '' > ${TEMP_MESSAGE_FILE}

    echo ${current_status} | tr "${D_DIFF_DEVICES}" '\n' | while read device_details; do
        status_msg=`cat ${TEMP_MESSAGE_FILE} | sed 's/^ *//g' | sed 's/ *$//g'`

        network_device=$(echo ${device_details} | cut -d "${D_DEVICE_AND_DATA}" -f 1)
        device_data=$(echo ${device_details} | cut -d "${D_DEVICE_AND_DATA}" -f 2)
        device_status=$(
            echo ${device_data} | tr "${D_DATA_SETS}" '\n' | while read data; do
                total_packets=$(echo $data | cut -d " " -f 1)
                error_packets=$(echo $data | cut -d " " -f 2)
                dropped_packets=$(echo $data | cut -d " " -f 3)
                echo "p:$total_packets,e:$error_packets,d:$dropped_packets"
            done | tr '\n' "${D_DIFF_DEVICES}" | sed -e 's/;$//' -e 's/;/; /g'
        )
        if echo ${status_msg} | grep -v "^\s*$" >/dev/null ; then
            status_msg="${status_msg}; "
        fi
        status_msg="${status_msg}${network_device}(${device_status})"
        echo "${status_msg}" > ${TEMP_MESSAGE_FILE}
    done
    status_msg=`cat ${TEMP_MESSAGE_FILE} | sed 's/^ *//g' | sed 's/ *$//g'`
    rm -f ${TEMP_MESSAGE_FILE} || true
    echo ${status_msg}
}


formatted_error_status() {
    formatted_message=''
    TEMP_FORMATTED_MESSAGE="/tmp/._mdp_formatted_message_$RANDOM"
    echo ${errors_pm} | tr "${D_DIFF_DEVICES}" "\n" | while read error_details; do
        network_device=$(echo ${error_details} | cut -d "${D_DEVICE_AND_DATA}" -f 1)
        error_data=$(echo ${error_details} | cut -d "${D_DEVICE_AND_DATA}" -f 2)
        dropped_data=$(
            echo ${dropped_pm} | tr "${D_DIFF_DEVICES}" "\n" | while read dropped_details; do
                d_network_device=$(echo ${dropped_details} | cut -d "${D_DEVICE_AND_DATA}" -f 1)
                if echo ${d_network_device} | grep "^${network_device}$" >/dev/null; then
                    dropped_data=$(echo ${dropped_details} | cut -d "${D_DEVICE_AND_DATA}" -f 2)
                    echo ${dropped_data}
                    break
                fi
            done
        )
        if echo ${formatted_message} | grep -v "^\s*$" >/dev/null; then
            formatted_message="${formatted_message}; "
        fi
        if echo "${error_data}" | grep "[!0-9]" >/dev/null; then
            error_data="${error_data}/M"
        fi
        if echo "${dropped_data}" | grep "[!0-9]" >/dev/null; then
            dropped_data="${dropped_data}/M"
        fi
        formatted_message="${formatted_message}${network_device}-(Errors:${error_data}, Dropped:${dropped_data})"
        echo ${formatted_message} > ${TEMP_FORMATTED_MESSAGE}
    done
    formatted_message=$(tail -n 1 ${TEMP_FORMATTED_MESSAGE} | sed 's/^ *//g' | sed 's/ *$//g')
    rm -f ${TEMP_FORMATTED_MESSAGE}
    echo ${formatted_message}
}


get_data_totals() {
    TEMP_CURRENT_TOTAL="/tmp/._mdp_current_total_$RANDOM"
    echo '' > ${TEMP_CURRENT_TOTAL}
    echo ${data_set} | tr "${D_DATA_SETS}" "\n" | while read data; do
        data_total=$(cat ${TEMP_CURRENT_TOTAL} | sed 's/^ *//g' | sed 's/ *$//g')
        if echo ${data_total} | grep "^\s*$" >/dev/null; then
            total_packets=$(echo $data | cut -d " " -f 1)
            error_packets=$(echo $data | cut -d " " -f 2)
            dropped_packets=$(echo $data | cut -d " " -f 3)
        else
            total_packets=$(expr $(echo $data | cut -d " " -f 1) + $(echo $data_total | cut -d":" -f 1) )
            error_packets=$(expr $(echo $data | cut -d " " -f 2) + $(echo $data_total | cut -d":" -f 2) )
            dropped_packets=$(expr $(echo $data | cut -d " " -f 3) + $(echo $data_total | cut -d":" -f 3) )
        fi
        echo "$total_packets:$error_packets:$dropped_packets" > ${TEMP_CURRENT_TOTAL}
    done
    data_total=$(cat ${TEMP_CURRENT_TOTAL} | sed 's/^ *//g' | sed 's/ *$//g')
    rm -f ${TEMP_CURRENT_TOTAL}
    echo ${data_total}
}


round_of() {
    decimal_part=`echo ${round_of_variable} | awk -F \. '{print $2}'`
    if echo $decimal_part | grep "^$" >/dev/null; then
        decimal_part=0
    fi
    round_of_variable=`echo ${round_of_variable} | awk -F \. '{print $1}'`
    if [ "$decimal_part" -ge 5 ]
    then
        round_of_variable=`expr ${round_of_variable} + 1`
    fi
    echo ${round_of_variable}
}


calc_diff_per_unit() {
    if [ $total -eq 0 ]; then
        echo '0'
    else
        round_of_variable=$(bc <<EOF
            scale=1
            $difference * $MEASURE_UNIT / $total
EOF
        )
        echo "${round_of_variable}"
    fi
}


calculate_dropped_packets() {
    errors_pm=''
    dropped_pm=''
    exit_status=${ST_OK}
    save_current_data=${NO}
    TEMP_ERRORS_PM="/tmp/._mdp_errors_pm_$RANDOM"
    echo "${errors_pm}" > ${TEMP_ERRORS_PM}
    TEMP_DROPPED_PM="/tmp/._mdp_dropped_pm_$RANDOM"
    echo "${dropped_pm}" > ${TEMP_DROPPED_PM}
    TEMP_EXIT_STATUS="/tmp/._mdp_exit_status_$RANDOM"
    echo "${exit_status}" > ${TEMP_EXIT_STATUS}
    TEMP_SAVE_CURRENT_DATA="/tmp/._mdp_save_current_data_$RANDOM"
    echo "${save_current_data}" > ${TEMP_SAVE_CURRENT_DATA}

    echo ${current_status} | tr "${D_DIFF_DEVICES}" '\n' | while read device_details; do
        if echo ${errors_pm} | grep -v "^\s*$" >/dev/null; then
            errors_pm="${errors_pm};"
        fi
        if echo ${dropped_pm} | grep -v "^\s*$" >/dev/null; then
            dropped_pm="${dropped_pm};"
        fi
        network_device=$(echo ${device_details} | cut -d "${D_DEVICE_AND_DATA}" -f 1)
        device_data=$(echo ${device_details} | cut -d "${D_DEVICE_AND_DATA}" -f 2)

        TEMP_OLD_DEV_DATA="/tmp/._mdp_old_dev_data_$RANDOM"
        echo '' > ${TEMP_OLD_DEV_DATA}
        echo ${last_data_check} | tr "${D_DIFF_DEVICES}" '\n' | while read device_details; do
            old_network_device=$(echo ${device_details} | cut -d "${D_DEVICE_AND_DATA}" -f 1)
            if echo ${old_network_device} | grep "^${network_device}$" >/dev/null; then
                old_device_data=$(echo ${device_details} | cut -d "${D_DEVICE_AND_DATA}" -f 2)
                echo "${old_device_data}" > ${TEMP_OLD_DEV_DATA}
                break
            fi
        done
        old_device_data=$(cat ${TEMP_OLD_DEV_DATA} | sed 's/^ *//g' | sed 's/ *$//g')
        rm -f ${TEMP_OLD_DEV_DATA}
        if echo ${old_device_data} | grep "^\s*$" >/dev/null; then
            errors_pm="${errors_pm}${network_device}-X"
            dropped_pm="${dropped_pm}${network_device}-X"
            echo ${errors_pm} > ${TEMP_ERRORS_PM}
            echo ${dropped_pm} > ${TEMP_DROPPED_PM}
            save_current_data=${YES}
            echo "${save_current_data}" > ${TEMP_SAVE_CURRENT_DATA}
            continue
        fi

        current_data_totals=$(data_set=$(echo ${device_data}) && get_data_totals)
        old_data_totals=$(data_set=$(echo ${old_device_data}) && get_data_totals)
        # Parse data
        current_total=$(echo $current_data_totals | cut -d":" -f 1)
        old_total=$(echo $old_data_totals | cut -d":" -f 1)
        current_error=$(echo $current_data_totals | cut -d":" -f 2)
        old_error=$(echo $old_data_totals | cut -d":" -f 2)
        current_dropped=$(echo $current_data_totals | cut -d":" -f 3)
        old_dropped=$(echo $old_data_totals | cut -d":" -f 3)
        # Calculate
        packet_difference=$(expr $current_total - $old_total)
        error_difference=$(expr $current_error - $old_error)
        dropped_difference=$(expr $current_dropped - $old_dropped)
        total="${packet_difference}"
        error_per_unit="$(difference=${error_difference} && calc_diff_per_unit)"
        dropped_per_unit="$(difference=${dropped_difference} && calc_diff_per_unit)"
        errors_pm="${errors_pm}${network_device}-${error_per_unit}"
        dropped_pm="${dropped_pm}${network_device}-${dropped_per_unit}"
        # Determine exit status
        if [ ${error_per_unit} -ge ${critical} ] || \
               [ ${dropped_per_unit} -ge ${critical} ]; then
           exit_status=${ST_CR}
           echo "${exit_status}" > ${TEMP_EXIT_STATUS}
        elif [ ${exit_status} -eq ${ST_OK} ] && \
             (  [ ${error_per_unit} -ge ${warning} ] || \
                [ ${dropped_per_unit} -ge ${warning} ]); then
           exit_status=${ST_WR}
           echo "${exit_status}" > ${TEMP_EXIT_STATUS}
        fi
        # Compute $save_current_data boolean
        if [ ${packet_difference} -gt ${MINIMUM_PACKET_DIFFERENCE} ]; then
            save_current_data=${YES}
            echo "${save_current_data}" > ${TEMP_SAVE_CURRENT_DATA}
        fi
        echo "${errors_pm}" > ${TEMP_ERRORS_PM}
        echo "${dropped_pm}" > ${TEMP_DROPPED_PM}
    done
    errors_pm=$(tail -n 1 ${TEMP_ERRORS_PM} | sed 's/^ *//g' | sed 's/ *$//g')
    dropped_pm=$(tail -n 1 ${TEMP_DROPPED_PM} | sed 's/^ *//g' | sed 's/ *$//g')
    exit_status=$(tail -n 1 ${TEMP_EXIT_STATUS} | sed 's/^ *//g' | sed 's/ *$//g')
    save_current_data=$(tail -n 1 ${TEMP_SAVE_CURRENT_DATA} | sed 's/^ *//g' | sed 's/ *$//g')
    rm -f ${TEMP_ERRORS_PM}
    rm -f ${TEMP_DROPPED_PM}
    rm -f ${TEMP_EXIT_STATUS}
    rm -f ${TEMP_SAVE_CURRENT_DATA}
}


if [ ! -f $KEEP_TRACK_FILE ]; then
    retrive_current_status
    echo ${current_status} > ${KEEP_TRACK_FILE}
    status_msg=$(formatted_device_status)
    echo "UNKNOWN - Errors: UNKNOWN, Dropped: UNKNOWN. Current status- ${status_msg}"
    exit $ST_UK

else
    last_data_check=$(tail -n 1 ${KEEP_TRACK_FILE} | sed 's/^ *//g' | sed 's/ *$//g')
    retrive_current_status
    calculate_dropped_packets
    if [ $save_current_data -eq ${YES} ]; then
        echo ${current_status} > ${KEEP_TRACK_FILE}
    fi
    message=''
    if [ ${exit_status} -eq ${ST_OK} ]; then
        message="OK- "
    elif [ ${exit_status} -eq ${ST_WR} ]; then
        message="WARNING- "
    elif [ ${exit_status} -eq ${ST_CR} ]; then
        message="CRITICAL- "
    else
        message="UNKNOWN- "
    fi
    status_msg=$(formatted_device_status)
    message="${message}$(formatted_error_status). Current status- ${status_msg}"
    echo ${message}
    exit ${exit_status}
fi
