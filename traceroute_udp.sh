#!/bin/bash
#
# Nagios NRPE plugin for traceroute checks (max hop + delay)
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

# nagios exit status variables
ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

## Global variables
hop_count="0"
last_hop_delay="*"
avg_hop_delay="0"
star_hop_count="0"
exit_status="${ST_OK}"
reason_for_failure=""


print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    echo "$PROGNAME is a custom Nagios plugin to restart any init service"
    echo "and ensure it is listening to the given TCP/UDP port."
    echo ""
    echo "Usage: $PROGNAME -s <service name> [-p <port no> -t <udp/tcp>]"
    echo ""
    echo "Options:"
    echo "  -H/--hostname)"
    echo "     Hostname for which MTR check needs to be executed (Mandatory)"
    echo "  -t/--timeout)"
    echo "     Timeout for traceroute command. Default: 10 (in sec)"
    echo "  -m/--maxhops)"
    echo "     maxhops to try in traceroute command. Default: 50"
    echo "  -w/--warning)"
    echo "     hop count warning level. Default: 15"
    echo "  -c/--critical)"
    echo "     hop count critical level. Default: 30"
    echo "  -a/--averagedelaywarning)"
    echo "     Average delay warning level. Default: 200 (in ms)"
    echo "  -A/--averagedelaycritical)"
    echo "     Average delay critical level. Default: 1000 (in ms)"
    echo "  -d/--lasthopdelaywarning)"
    echo "     Last hop delay warning level. Default: 300 (in ms)"
    echo "  -D/--lasthopdelaycritical)"
    echo "     Last hop delay critical level. Default: 2000 (in ms)"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -H example.com -w 10 -c 20 -D 1000"
}

## Set defaults for optional arguments ##
timeout="1"
maxhops="50"
warning="15"
critical="30"
averagedelaywarning="200"
averagedelaycritical="1000"
lasthopdelaywarning="300"
lasthopdelaycritical="2000"

## parse arguments passed ##
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
        --hostname|-H)
            hostname=$2
            shift
            ;;
        --timeout|-t)
            timeout=$2
            shift
            ;;
        --maxhops|-m)
            maxhops=$2
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
        --averagedelaywarning|-a)
            averagedelaywarning=$2
            shift
            ;;
        --averagedelaycritical|-A)
            averagedelaycritical=$2
            shift
            ;;
        --lasthopdelaywarning|-d)
            lasthopdelaywarning=$2
            shift
            ;;
        --lasthopdelaycritical|-D)
            lasthopdelaycritical=$2
            shift
            ;;
        *)
            echo "Unknown argument: '$1'"
            echo ""
            print_help
            exit $ST_UK
            ;;
        esac
    shift
done


######################### Validate arguments passed ##########################
if echo ${hostname} | grep -v -e "^[a-zA-Z][a-zA-Z0-9\.-]*$" \
    -e "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$" >/dev/null
then
    echo "Invalid value: '${hostname}' for option -H/--hostname. Possible" \
         " values: A valid FQDN or IPv4 address"
    exit $ST_UK
fi
if echo ${timeout} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${timeout}' for option -t/--timeout. Possible" \
         " value: Positive integer"
    exit $ST_UK
fi
if echo ${maxhops} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${maxhops}' for option -m/--maxhops. Possible" \
         " value: Positive integer"
    exit $ST_UK
fi
if echo ${warning} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${warning}' for option -w/--warning. Possible" \
         " value: Positive integer"
    exit $ST_UK
fi
if echo ${critical} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${critical}' for option -c/--critical. Possible" \
         " value: Positive integer"
    exit $ST_UK
fi
if echo ${averagedelaywarning} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${averagedelaywarning}' for option " \
         "-a/--averagedelaywarning. Possible value: Positive integer"
    exit $ST_UK
fi
if echo ${averagedelaycritical} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${averagedelaycritical}' for option " \
         "-A/--averagedelaycritical. Possible value: Positive integer"
    exit $ST_UK
fi
if echo ${lasthopdelaywarning} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${lasthopdelaywarning}' for option " \
         "-d/--lasthopdelaywarning. Possible value: Positive integer"
    exit $ST_UK
fi
if echo ${lasthopdelaycritical} | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    echo "Invalid value: '${lasthopdelaycritical}' for option " \
         "-D/--lasthopdelaycritical. Possible value: Positive integer"
    exit $ST_UK
fi
##############################################################################


traceroute_command="traceroute -w ${timeout} -q 1 -m ${maxhops} -U ${hostname}"
TEMP_FILE="/tmp/._traceroute_${PROGNAME}_${hostname}_${RANDOM}.tmp"

check_exit_status() {
    if [ $? -ne 0 ]; then
            echo "CRITICAL - '${traceroute_command}' command failed"
            rm -f $TEMP_FILE || true
            exit $ST_CR
    fi
}


execute_check() {
    ${traceroute_command} > ${TEMP_FILE}
    check_exit_status
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
    echo $round_of_variable
}


parse_collected_date() {
    # Initialize variables
    hop_count="0"
    last_hop_delay="*"
    avg_hop_delay="0"
    star_hop_count="0"
    # Find meaningful data
    temp_delay_sum="0"
    temp_ifs=${IFS}
    IFS='N'
    for i in $(cat ${TEMP_FILE} | tr -s " " | sed "s/^ *\(.*\) *$/\1/" \
               | grep "^[0-9].*$" | tr "[:upper:]" "[:lower:]" | tr '\n' 'N');
    do
        hop_count=$(expr ${hop_count} + 1)
        last_hop_delay=$(echo $i | cut -d" " -f 4 | grep -v "^\s*$" || echo '*')
        if [ "X${last_hop_delay}" != "X*" ]; then
            temp_delay_sum=$(bc <<EOF
                scale=4
                ${temp_delay_sum} + ${last_hop_delay}
EOF
                )
        else
            star_hop_count="$(expr ${star_hop_count} + 1)"
        fi
    done
    IFS=${temp_ifs}
    if [ "X${hop_count}" = "X${star_hop_count}" ]; then
        avg_hop_delay="*"
    else
        avg_hop_delay=$(bc <<EOF
                        scale=2
                        ${temp_delay_sum} / (${hop_count} - ${star_hop_count})
EOF
                        )
        avg_hop_delay="$(round_of_variable=${avg_hop_delay}; round_of)"
    fi
    if [ "X${last_hop_delay}" != "X*" ]; then
        last_hop_delay="$(round_of_variable=${last_hop_delay}; round_of)"
    fi
}


calc_exit_status() {
    # Hop count
    if [ ${hop_count} -ge ${critical} ]; then
        reason_for_failure="${reason_for_failure}Hop Count >= ${critical}(CR); "
        exit_status="${ST_CR}"
    elif [ ${hop_count} -ge ${warning} ]; then
        reason_for_failure="${reason_for_failure}Hop Count >= ${warning}(WR); "
        if [ "X${exit_status}" = "X${ST_OK}" ] || \
                [ "X${exit_status}" = "X${ST_UK}" ]; then
            exit_status="${ST_WR}"
        fi
    fi
    # Last hop delay
    if [ "X${last_hop_delay}" = "X*" ]; then
        reason_for_failure="${reason_for_failure}Packet LOST(CR); "
        exit_status="${ST_CR}"
    elif [ ${last_hop_delay} -ge ${lasthopdelaycritical} ]; then
        reason_for_failure="${reason_for_failure}Last hop delay >= ${lasthopdelaycritical}(CR); "
        exit_status="${ST_CR}"
    elif [ ${last_hop_delay} -ge ${lasthopdelaywarning} ]; then
        reason_for_failure="${reason_for_failure}Last hop delay >= ${lasthopdelaywarning}(WR); "
        if [ "X${exit_status}" = "X${ST_OK}" ] || \
                [ "X${exit_status}" = "X${ST_UK}" ]; then
            exit_status="${ST_WR}"
        fi
    fi
    # Agerage hop delay
    if [ "X${avg_hop_delay}" = "X" ]; then
        true
    elif [ "X${avg_hop_delay}" = "X*" ]; then
        exit_status="${ST_CR}"
    elif [ ${avg_hop_delay} -ge ${averagedelaycritical} ]; then
        reason_for_failure="${reason_for_failure}Avg. hop delay >= ${averagedelaycritical}(CR); "
        exit_status="${ST_CR}"
    elif [ ${avg_hop_delay} -ge ${averagedelaywarning} ]; then
        reason_for_failure="${reason_for_failure}Avg. hop delay >= ${averagedelaywarning}(WR); "
        if [ "X${exit_status}" = "X${ST_OK}" ] || \
                [ "X${exit_status}" = "X${ST_UK}" ]; then
            exit_status="${ST_WR}"
        fi
    fi
    reason_for_failure="$(echo "${reason_for_failure}" | sed 's/^ *\(.*\); *$/\1/')"
}


formatted_current_status() {
    message="Hop count: ${hop_count}; * hops: ${star_hop_count}"
    if [ "X${last_hop_delay}" != "X*" ]; then
        message="${message}; Last hop delay: ${last_hop_delay} ms"
    fi
    if [ "X${avg_hop_delay}" != "X*" ]; then
        message="${message}; Avg hop delay: ${avg_hop_delay} ms"
    fi
    echo "${message}"
}


##############################################################################
############################ EXECUTE THE TEST ################################
##############################################################################

execute_check
parse_collected_date
calc_exit_status
rm -f ${TEMP_FILE} || true

if [ "X${reason_for_failure}" != "X" ]; then
    reason_for_failure=". Reason: ${reason_for_failure}"
fi

if [ "X${exit_status}" = "X${ST_OK}" ]; then
    message="OK - "
elif [ "X${exit_status}" = "X${ST_WR}" ]; then
    message="WARNING - "
elif [ "X${exit_status}" = "X${ST_CR}" ]; then
    message="CRITICAL - "
else
    message="UNKNOWN - "
fi

message="${message}$(formatted_current_status)${reason_for_failure}"
echo "${message}"
exit "${exit_status}"
