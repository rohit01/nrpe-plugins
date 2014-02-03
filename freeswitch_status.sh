#!/bin/bash
#
# Nagios NRPE plugin to check status of freeswitch
# Valid commands: 'show channels count', 'status', 'g729_info', 'vqa show license'
#


ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    print_version
    echo ""
    echo "$PROGNAME is a custom Nagios plugin to check freeswitch status"
    echo "using fs_cli command."
    echo "Freeswitch status check commands defined in this module are:"
    echo "'show channels count', 'status', 'g729_info' & 'vqa show license'"
    echo ""
    echo "Usage: $PROGNAME 'show channels count' [-w 80] [-c 90]"
    echo ""
    echo "Options:"
    echo "  -w/--warning)"
    echo "     Defines a warning level. Not applicable for 'status' command"
    echo "     Command: "
    echo "        'show channels count': No of channels in use. Default: 500"
    echo "        'g729_info': Percentage of max permitted G729 in use. Default: 70"
    echo "        'vqa show license': Percentage of Licensed Ports in use. Default: 70"
    echo "  -c/--critical)"
    echo "     Defines a critical level. Not applicable for 'status' command"
    echo "     Command: "
    echo "        'show channels count': No of channels in use. Default: 650"
    echo "        'g729_info': Percentage of max permitted G729 in use. Default: 85"
    echo "        'vqa show license': Percentage of Licensed Ports in use. Default: 85"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME 'status'"
    echo "   $PROGNAME 'show channels count' -w 500 -c 650"
    echo "   $PROGNAME 'g729_info' -w 70 -c 85"
    echo "   $PROGNAME 'vqa show license' -w 70 -c 85"
}

exit_formalities() {
    echo "$1"
    if [ "X${TEMP_FILE}" != "X" ]; then
        rm -f "${TEMP_FILE}" || true
    fi
    exit "$2"
}

message=''
fs_command=$1
if echo $fs_command | grep "^$" >/dev/null; then
    echo "Status check command not specified. Valid commands are: "
    echo "'show channels count', 'status', 'g729_info' & 'vqa show license'"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
fi
case "$fs_command" in
    --help|-h)
        print_help
        exit_formalities "${message}" "${ST_UK}"
        ;;
    --version|-v)
        print_version $PROGNAME $VERSION
        exit_formalities "${message}" "${ST_UK}"
        ;;
esac
shift

while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit_formalities "${message}" "${ST_UK}"
            ;;
        --version|-v)
            print_version $PROGNAME $VERSION
            exit_formalities "${message}" "${ST_UK}"
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
            exit_formalities "${message}" "${ST_UK}"
            ;;
        esac
    shift
done

# Set Defaults for $warning variable
if (echo $warning | grep -v "^$" >/dev/null) && echo $fs_command | grep "status" >/dev/null; then
    message="-w/--warning option is invalid for command: '$fs_command'"
    exit_formalities "${message}" "${ST_UK}"
elif (echo $warning | grep "^$" >/dev/null) && echo $fs_command | grep "show channels count" >/dev/null; then
    warning=500
elif (echo $warning | grep "^$" >/dev/null) && echo $fs_command | grep "g729_info" >/dev/null; then
    warning=70
elif (echo $warning | grep "^$" >/dev/null) && echo $fs_command | grep "vqa show license" >/dev/null; then
    warning=70
fi
# Set Defaults for $critical variable
if (echo $critical | grep -v "^$" >/dev/null) && echo $fs_command | grep "status" >/dev/null; then
    message="-c/--critical option is invalid for command: '$fs_command'"
    exit_formalities "${message}" "${ST_UK}"
elif (echo $critical | grep "^$" >/dev/null) && echo $fs_command | grep "show channels count" >/dev/null; then
    critical=650
elif (echo $critical | grep "^$" >/dev/null) && echo $fs_command | grep "g729_info" >/dev/null; then
    critical=85
elif (echo $critical | grep "^$" >/dev/null) && echo $fs_command | grep "vqa show license" >/dev/null; then
    critical=85
fi


TEMP_FILE="/tmp/._fs_status_$RANDOM"

check_exit_status() {
    if [ $? -ne 0 ]; then
            message="CRITICAL - Freeswitch not responding!"
            exit_formalities "${message}" "${ST_CR}"
    fi
}

check_timeout() {
    if grep 'Request timed out' $TEMP_FILE; then
            message="CRITICAL - Freeswitch - Request timed out!"
            exit_formalities "${message}" "${ST_CR}"
    fi
}

execute_check() {
    /usr/local/freeswitch/bin/fs_cli -b -q -x "$fs_command" -t 2000 > $TEMP_FILE
    check_exit_status
    check_timeout
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

calc_permitted_channels_warning() {
bc <<EOF
    scale=4
    $permitted_channels * $warning / 100
EOF
}

calc_permitted_channels_critical() {
bc <<EOF
    scale=4
    $permitted_channels * $critical / 100
EOF
}

calc_l_ports_warning() {
bc <<EOF
    scale=4
    $l_ports * $warning / 100
EOF
}

calc_l_ports_critical() {
bc <<EOF
    scale=4
    $l_ports * $critical / 100
EOF
}


if echo $fs_command | grep 'status' >/dev/null
then
    execute_check
    fsUptime=`grep "UP" < $TEMP_FILE`
    # Parse the UP time in short format
    fsUptime=${fsUptime/UP /}
    fsUptime=${fsUptime/ years, /y}
    fsUptime=${fsUptime/ year, /y}
    fsUptime=${fsUptime/ days, /d }
    fsUptime=${fsUptime/ day, /d }
    fsUptime=${fsUptime/ hours, /.}
    fsUptime=${fsUptime/ hour, /.}
    fsUptime=${fsUptime/ minutes, /.}
    fsUptime=${fsUptime/ minute, /.}
    fsUptime=${fsUptime/ seconds, /.}
    fsUptime=${fsUptime/ second, /.}
    fsUptime=${fsUptime/ milliseconds, /}
    fsUptime=${fsUptime/ millisecond, /}
    fsUptime=${fsUptime/ microseconds/s}
    fsUptime=${fsUptime/ microsecond/s}
    fsMaxChannels=`grep "max" < $TEMP_FILE`
    fsMaxChannels=${fsMaxChannels/ session(s) max/}
    message="Max session: $fsMaxChannels, Up Time: $fsUptime"
    exit_formalities "${message}" "${ST_OK}"

elif echo $fs_command | grep 'show channels count' >/dev/null
then
    execute_check
    channels=$(tail -n 2 $TEMP_FILE | head -n 1 | tr -s ' ' | cut -d" " -f 1 | sed 's/^ *//g' | sed 's/ *$//g')
    if [ $channels -lt $warning ]; then
        message="Ok - No of Channels in use: $channels"
        exit_formalities "${message}" "${ST_OK}"
    elif [ $channels -gt $warning ] && [ $channels -lt $critical ]; then
        message="WARNING - No of Channels in use: $channels"
        exit_formalities "${message}" "${ST_WR}"
    else
        message="CRITICAL - No of Channels in use: $channels"
        exit_formalities "${message}" "${ST_CR}"
    fi

elif echo $fs_command | grep 'g729_info' >/dev/null
then
    execute_check
    EXIT_STATUS_FILE='/tmp/fs_exit_status_$RANDOM'
    echo $ST_OK > $EXIT_STATUS_FILE
    TEMP_MESSAGE_FILE='/tmp/fs_temp_message_$RANDOM'
    echo '' > $TEMP_MESSAGE_FILE
    cat $TEMP_FILE | grep -v "^\s*$" | while read line
    do
        exit_status=`cat $EXIT_STATUS_FILE | sed 's/^ *//g' | sed 's/ *$//g'`
        message=`cat $TEMP_MESSAGE_FILE | sed 's/^ *//g' | sed 's/ *$//g'`
        if echo $line | grep 'Permitted' >/dev/null
        then
            permitted_channels=$(echo $line | cut -d ":" -f 2 | sed 's/^ *//g' | sed 's/ *$//g')
        elif echo $line | grep 'Encoders' >/dev/null
        then
            encoders=$(echo $line | cut -d ":" -f 2 | sed 's/^ *//g' | sed 's/ *$//g')
        elif echo $line | grep 'Decoders' >/dev/null
        then
            decoders=$(echo $line | cut -d ":" -f 2 | sed 's/^ *//g' | sed 's/ *$//g')
            if echo ${message} | grep -v "^$" >/dev/null; then
                message="${message}; "
            fi
            message="${message}Permitted: $permitted_channels, Encoders: $encoders, Decoders: $decoders"
            warning=`calc_permitted_channels_warning`
            critical=`calc_permitted_channels_critical`
            # Round off all variables
            round_of_variable=${warning}
            warning=`round_of`
            round_of_variable=${critical}
            critical=`round_of`
            round_of_variable=${encoders}
            encoders=`round_of`
            round_of_variable=${decoders}
            decoders=`round_of`
            # recalculate exit levels
            if [ $encoders -ge $critical ]; then
                echo $ST_CR > $EXIT_STATUS_FILE
            elif [ $encoders -ge $warning ] && [ $exit_status -eq 0 ]; then
                echo $ST_WR > $EXIT_STATUS_FILE
            fi
            if [ $decoders -ge $critical ]; then
                echo $ST_CR > $EXIT_STATUS_FILE
            elif [ $decoders -ge $warning ] && [ $exit_status -eq 0 ]; then
                echo $ST_WR > $EXIT_STATUS_FILE
            fi
            echo "$message" > $TEMP_MESSAGE_FILE
        fi
    done
    exit_status=`cat $EXIT_STATUS_FILE | sed 's/^ *//g' | sed 's/ *$//g'`
    message=`cat $TEMP_MESSAGE_FILE | sed 's/^ *//g' | sed 's/ *$//g'`
    rm -f $EXIT_STATUS_FILE || true
    rm -f $TEMP_MESSAGE_FILE || true
    if [ $exit_status -eq $ST_OK ]; then
        message="OK - ${message}"
        exit_formalities "${message}" "${ST_OK}"
    elif [ $exit_status -eq $ST_WR ]; then
        message="WARNING - ${message}"
        exit_formalities "${message}" "${ST_WR}"
    elif [ $exit_status -eq $ST_CR ]; then
        message="CRITICAL - ${message}"
        exit_formalities "${message}" "${ST_CR}"
    else
        exit_formalities "${message}" "${ST_UK}"
    fi

elif echo $fs_command | grep 'vqa show license' >/dev/null
then
    execute_check
    l_ports=$(cat $TEMP_FILE  | tr -s " " | grep 'Licensed Ports' | cut -d":" -f2 | sed 's/^ *//g' | sed 's/ *$//g')
    a_ports=$(cat $TEMP_FILE  | tr -s " " | grep 'Available Ports' | cut -d":" -f2 | sed 's/^ *//g' | sed 's/ *$//g')
    used_ports=`expr $l_ports - $a_ports`
    message="[VQA] Licensed Ports: $l_ports, Available Ports: $a_ports, Used Ports: $used_ports"
    warning=`calc_l_ports_warning`
    critical=`calc_l_ports_critical`
    # Round off all variables
    round_of_variable=${warning}
    warning=`round_of`
    round_of_variable=${critical}
    critical=`round_of`
    if [ $used_ports -lt $warning ]; then
        message="OK - $message"
        exit_formalities "${message}" "${ST_OK}"
    elif [ $used_ports -ge $warning ] && [ $used_ports -lt $critical ]; then
        message="WARNING - $message"
        exit_formalities "${message}" "${ST_WR}"
    elif [ $used_ports -ge $critical ]; then
        message="CRITICAL - $message"
        exit_formalities "${message}" "${ST_CR}"
    else
        exit_formalities "${message}" "${ST_UK}"
    fi

else
    message="Invalid command: '$fs_command'. Valid commands are: 'show channels count', 'status', 'g729_info' & 'vqa show license'"
    exit_formalities "${message}" "${ST_WR}"
fi

exit_formalities "${message}" "${ST_OK}"

# Actual commands being run to get data:
# /usr/local/freeswitch/bin/fs_cli -b -q -x "show channels count" -t 2000
# /usr/local/freeswitch/bin/fs_cli -b -q -x "status" -t 2000
# /usr/local/freeswitch/bin/fs_cli -b -q -x "g729_info" -t 2000
# /usr/local/freeswitch/bin/fs_cli -b -q -x "vqa show license" -t 2000
#