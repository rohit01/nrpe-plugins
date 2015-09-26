#!/usr/bin/env bash
#
# NRPE plugin to check status of freeswitch
# Valid commands: 'show channels count', 'status'
#
# Actual fs_cli commands being run to perform checks:
# show channels count: /usr/local/freeswitch/bin/fs_cli -q -x "show channels count" -t 2000
# show calls count: /usr/local/freeswitch/bin/fs_cli -q -x "show calls count" -t 2000
# zombie_calls: /usr/local/freeswitch/bin/fs_cli -q -x "show channels" -t 2000
# status: /usr/local/freeswitch/bin/fs_cli -q -x "status" -t 2000
# pri_metrics: /usr/local/freeswitch/bin/fs_cli -q -x "ftdm list" -t 2000
#              /usr/local/freeswitch/bin/fs_cli -q -x "ftdm core calls" -t 2000
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

## Global static variables
ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3
LAST_CALLS_COUNT_FILE="/tmp/._last_calls_count_${PROGNAME}"

## Global variables & default settings
fs_command="$1"
message=""
fscli_output=""
warning="300"
critical="400"


print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    print_version
    echo ""
    echo "$PROGNAME is a custom NRPE plugin to check freeswitch status"
    echo "using fs_cli command."
    echo "Freeswitch status check commands defined in this module are:"
    echo "'show channels count', 'show calls count', 'status', 'pri_metrics', "
    echo "'pri_status', 'calls_count', 'zombie_calls'"
    echo ""
    echo "Usage: $PROGNAME 'show channels count' [-w 80] [-c 90]"
    echo ""
    echo "Options:"
    echo "  -w/--warning)"
    echo "     Defines a warning level. Not applicable for 'status' command"
    echo "     Command: "
    echo "        'show channels count': No of channels in use. Default: 300"
    echo "        'show calls count': No of calls in use. Default: 300"
    echo "        'pri_metrics': No of calls per pri line. Default: 300"
    echo "        'calls_count': Zero calls for x duration. Default: 300 secs"
    echo "        'zombie_calls': Number of zombie calls in percent"
    echo "  -c/--critical)"
    echo "     Defines a critical level. Not applicable for 'status' command"
    echo "     Command: "
    echo "        'show channels count': No of channels in use. Default: 400"
    echo "        'show calls count': No of calls in use. Default: 400"
    echo "        'pri_metrics': No of calls per pri line. Default: 400"
    echo "        'calls_count': Zero calls for x duration. Default: 400 secs"
    echo "        'zombie_calls': Number of zombie calls (in percent)"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME 'status'"
    echo "   $PROGNAME 'show channels count' -w 500 -c 650"
    echo "   $PROGNAME 'show calls count' -w 500 -c 650"
    echo "   $PROGNAME 'pri_metrics' -w 600 -c 900"
    echo "   $PROGNAME 'zombie_calls' -w 25 -c 50"
}

exit_formalities() {
    echo "$1"
    exit "$2"
}

check_exit_status() {
    if [ $? -ne 0 ]; then
        message="CRITICAL - Freeswitch not responding!"
        exit_formalities "${message}" "${ST_CR}"
    fi
}

check_timeout() {
    if echo "${fscli_output}" | grep 'Request timed out'; then
        message="CRITICAL - Freeswitch - Request timed out!"
        exit_formalities "${message}" "${ST_CR}"
    fi
}

execute_check() {
    fscli_output="$(/usr/local/freeswitch/bin/fs_cli -q -x "$fs_command" -t 2000)"
    check_exit_status
    check_timeout
}

pri_utilization_alert() {
    span_details="${1}"
    call_details="${2}"
    echo "${span_details}" | grep "^span: " | cut -d" " -f 2 | while read span_no
    do
        live_calls_count="$(echo "${call_details}" | grep " ${span_no}:" | wc -l)"
        if [ "${live_calls_count}" -ge "${critical}" ]; then
            echo "CR:span${span_no}:${live_calls_count}calls"
        elif [ "${live_calls_count}" -ge "${warning}" ]; then
            echo "WR:span${span_no}:${live_calls_count}calls"
        fi
    done | tr '\n' ' ' | sed 's/ *$//'
}

get_pri_perf_data() {
    span_details="${1}"
    call_details="${2}"
    echo "${span_details}" | grep "^span: " | cut -d" " -f 2 | while read span_no
    do
        live_calls_count="$(echo "${call_details}" | grep " ${span_no}:" | wc -l)"
        echo "span${span_no}=${live_calls_count}"
    done | tr '\n' ' ' | sed 's/ *$//'
}

get_pri_status_summary() {
    span_details="${1}"
    wan_status="${2}"
    total_spans="$(echo "${span_details}" | grep "^span: " | wc -l)"
    pok_count="$(echo "${span_details}" | grep "^physical_status: ok" | wc -l)"
    sup_count="$(echo "${span_details}" | grep "^signaling_status: UP" | wc -l)"
    (
        echo "physical_ok:${pok_count}/${total_spans} signal_up:${sup_count}/${total_spans}. Details:"
        echo "${span_details}" | grep "^span: " | while read span_line
        do
            span_no="$(echo "${span_line}" | cut -d" " -f 2)"
            connect_status="$(echo "${wan_status}" | grep "^wanpipe${span_no} " | cut -d"|" -f 4 | sed 's/^\s*//' | sed 's/\s*$//')"
            if [ "X${connect_status}" == "X" ]; then
                connect_status="NotFound"
            fi
            physical_status="$(echo "${span_details}" | grep -A 3 "^${span_line}$" | grep "^physical_status: " | sed 's/^physical_status: //')"
            signaling_status="$(echo "${span_details}" | grep -A 3 "^${span_line}$" | grep "^signaling_status: " | sed 's/^signaling_status: //')"
            if [ "X${connect_status}" != "XNotFound" ] && [ "X${physical_status}" == "Xok" ] && [ "X${connect_status}" != "XConnected" ]; then
                echo "CRITICAL:span-${span_no}:${physical_status}:${signaling_status}:${connect_status}"
            elif [ "X${connect_status}" != "XNotFound" ] && [ "X${physical_status}" != "Xok" ] && [ "X${connect_status}" == "XConnected" ]; then
                echo "CRITICAL:span-${span_no}:${physical_status}:${signaling_status}:${connect_status}"
            elif [ "X${physical_status}" == "Xok" ] && [ "X${signaling_status}" != "XUP" ]; then
                echo "CRITICAL:span-${span_no}:${physical_status}:${signaling_status}:${connect_status}"
            elif [ "X${physical_status}" != "Xok" ] && [ "X${signaling_status}" == "XUP" ]; then
                echo "CRITICAL:span-${span_no}:${physical_status}:${signaling_status}:${connect_status}"
            else
                echo "OK:span-${span_no}:${physical_status}:${signaling_status}:${connect_status}"
            fi
        done
        echo "| physical_ok=${pok_count};${total_spans} signal_up=${sup_count};${total_spans}"
    ) | tr '\n' ' ' | sed 's/ *$//'
}

calls_count_alert_summary() {
    no_of_calls="${1}"
    time_now="$(date +%s)"
    if ((${no_of_calls} > 0)); then
        echo "${time_now} ${no_of_calls}" > "${LAST_CALLS_COUNT_FILE}"
        echo "OK - Total calls: ${no_of_calls}"
        exit "${ST_OK}"
    else
        last_status="$(cat "${LAST_CALLS_COUNT_FILE}" 2>/dev/null || echo '')"
        if [ "X${last_status}" == "X" ]; then
            last_zero_time="$(date +%s)"
        else
            if (($(echo "${last_status}" | cut -d" " -f 2) == 0)); then
                last_zero_time="$(echo "${last_status}" | cut -d" " -f 1)"
            else
                last_zero_time="$(date +%s)"
            fi
        fi
        echo "${last_zero_time} ${no_of_calls}" > "${LAST_CALLS_COUNT_FILE}"
        # Calculate alert and print summary
        time_diff="$((${time_now} - ${last_zero_time}))"
        if ((${time_diff} >= ${critical})); then
            echo "CRITICAL - Zero calls since last ${time_diff} seconds (${time_diff} > ${critical})"
            exit "${ST_CR}"
        elif ((${time_diff} >= ${warning})); then
            echo "WARNING - Zero calls since last ${time_diff} seconds (${time_diff} > ${warning})"
            exit "${ST_WR}"
        else
            echo "OK - Zero calls since last ${time_diff} seconds (${time_diff} <= ${warning})"
            exit "${ST_OK}"
        fi
    fi
}

#### EXECUTE CHECK ############################################################
## Get fs_cli command (1st argument)
fs_command=$1
case "${fs_command}" in
    --help|-h)
        print_help
        exit_formalities "${message}" "${ST_UK}"
        ;;
    --version|-v)
        print_version $PROGNAME $VERSION
        exit_formalities "${message}" "${ST_UK}"
        ;;
esac
if [ "X${fs_command}" == "X" ]; then
    echo "Status check command not specified. Valid commands are: "
    echo "'show channels count', 'show calls count', 'pri_metrics', 'status',"
    echo " 'pri_status', 'zombie_calls' & 'calls_count'"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
elif [ "X${fs_command}" != "Xstatus" ] && \
        [ "X${fs_command}" != "Xshow channels count" ] && \
        [ "X${fs_command}" != "Xshow calls count" ] && \
        [ "X${fs_command}" != "Xpri_status" ] && \
        [ "X${fs_command}" != "Xcalls_count" ] && \
        [ "X${fs_command}" != "Xzombie_calls" ] && \
        [ "X${fs_command}" != "Xpri_metrics" ]; then
    echo "Invalid command - '${fs_command}'. Valid commands are: "
    echo "'show channels count', 'show calls count', 'pri_metrics', "
    echo "'pri_status', 'calls_count', 'zombie_calls' & 'status'"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
fi

## Get warning and critical settings
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

if [ "X${fs_command}" == "Xstatus" ]; then
    ## Execute test for fs command - status
    execute_check
    ## Calculate uptime
    uptime="$(echo "${fscli_output}" | head -n 1)"
    uptime="${uptime/UP /}"
    uptime="${uptime/ years, /y}"
    uptime="${uptime/ year, /y}"
    uptime="${uptime/ days, /d }"
    uptime="${uptime/ day, /d }"
    uptime="${uptime/ hours, /h}"
    uptime="${uptime/ hour, /h}"
    uptime="${uptime/ minutes, /m}"
    uptime="${uptime/ minute, /m}"
    uptime="${uptime/ seconds, */s}"
    uptime="${uptime/ second, */s}"
    ## Calculate version
    version="$(echo "${fscli_output}" | awk 'NR==2 {print}')"
    version="${version/FreeSWITCH \(Version /}"
    version="${version/ git */}"
    ## Calculate git commit id
    git_commit="$(echo "${fscli_output}" | awk 'NR==2 {print}')"
    git_commit="${git_commit/FreeSWITCH \(Version * git /}"
    git_commit="${git_commit/ */}"
    ## Print message and exit
    message="OK - FS version: ${version}, git ID: ${git_commit}, Uptime: ${uptime}"
    exit_formalities "${message}" "${ST_OK}"

elif [ "X${fs_command}" == "Xshow channels count" ] || [ "X${fs_command}" == "Xshow calls count" ]; then
    ## Execute test for fs command - show channels count
    execute_check
    channels="$(echo "${fscli_output}" | tail -n 1 | tr -s ' ' | cut -d' ' -f 1 | sed 's/^ *//g' | sed 's/ *$//g')"
    perf_data="channels=${channels};${warning};${critical}"
    if [ "X${fs_command}" == "Xshow channels count" ]; then
        check_type="channels"
    else
        check_type="calls"
    fi
    if [ "${channels}" -ge "${critical}" ]; then
        message="CRITICAL - No of ${check_type} in use: ${channels} | ${perf_data}"
        exit_formalities "${message}" "${ST_CR}"
    elif [ "${channels}" -ge "${warning}" ]; then
        message="WARNING - No of ${check_type} in use: ${channels} | ${perf_data}"
        exit_formalities "${message}" "${ST_WR}"
    else
        message="Ok - No of ${check_type} in use: ${channels} | ${perf_data}"
        exit_formalities "${message}" "${ST_OK}"
    fi

elif [ "X${fs_command}" == "Xpri_metrics" ]; then
    ## Execute PRI Metrics test
    fs_command="ftdm list"
    execute_check
    span_details="${fscli_output}"
    fs_command="ftdm core calls"
    execute_check
    call_details="${fscli_output}"

    pri_excess_utilization="$(pri_utilization_alert "${span_details}" "${call_details}")"
    # Calculete alert level
    if echo "${pri_excess_utilization}" | grep "CR:span" >/dev/null; then
        exit_status="${ST_CR}"
    elif echo "${pri_excess_utilization}" | grep "WR:span" >/dev/null; then
        exit_status="${ST_WR}"
    else
        exit_status="${ST_OK}"
    fi

    pri_perf_data="$(get_pri_perf_data "${span_details}" "${call_details}")"
    total_calls="$(echo "${call_details}" | grep -i "^Total calls: ")"
    total_calls="${total_calls/Total calls: /}"
    perf_data="${pri_perf_data} total_calls=${total_calls}"

    if [ "X${exit_status}" == "X${ST_CR}" ]; then
        message="CRITICAL - Total calls: ${total_calls}. High load on PRI- ${pri_excess_utilization} | ${perf_data}"
        exit_formalities "${message}" "${exit_status}"
    elif [ "X${exit_status}" == "X${ST_WR}" ]; then
        message="WARNING - Total calls: ${total_calls}. High load on PRI- ${pri_excess_utilization} | ${perf_data}"
        exit_formalities "${message}" "${exit_status}"
    else
        message="OK - Total calls: ${total_calls} | ${perf_data}"
        exit_formalities "${message}" "${exit_status}"
    fi

elif [ "X${fs_command}" == "Xpri_status" ]; then
    ## Execute PRI Status check
    fs_command="ftdm list"
    execute_check
    span_details="${fscli_output}"
    wan_status="$(cat /proc/net/wanrouter/status 2>/dev/null || echo "")"
    message="$(get_pri_status_summary "${span_details}" "${wan_status}")"
    if echo "${message}" | grep " CRITICAL:" >/dev/null; then
        exit_formalities "CRITICAL - ${message}" "${ST_CR}"
    else
        exit_formalities "OK - ${message}" "${ST_OK}"
    fi

elif [ "X${fs_command}" == "Xcalls_count" ]; then
    ## Execute calls count check
    fs_command="show calls count"
    execute_check
    no_of_calls="$(echo "${fscli_output}" | grep 'total' | cut -d" " -f 1)"
    message="$(calls_count_alert_summary "${no_of_calls}")"
    exit_status="$?"
    exit_formalities "${message}" "${exit_status}"

elif [ "X${fs_command}" == "Xzombie_calls" ]; then
    ## Execute check to find the number of zombie_calls
    fs_command="show channels"
    execute_check
    channels="$(echo "${fscli_output}" | head -n -2 | awk 'NR>=2')"
    time_now="$(date +%s)"
    channels_count="$(echo "${channels}" | wc -l)"
    zombie_count="$(echo "${channels}" | awk -F  "," '{if ($4 <= ('${time_now}' - 180) && $6 == "CS_CONSUME_MEDIA" && $25 == "ACTIVE") print}' | wc -l)"
    zombie_percent="$((zombie_count * 100 / channels_count))"
    perf_data="zombie=${zombie_percent}%;${warning}%;${critical}% zombiecount=${zombie_count} channels=${channels_count}"
    if [ "${zombie_percent}" -ge "${critical}" ]; then
        message="CRITICAL - Zombie calls: ${zombie_count} / ${channels_count} (${zombie_percent}%) | ${perf_data}"
        exit_formalities "${message}" "${ST_CR}"
    elif [ "${zombie_percent}" -ge "${warning}" ]; then
        message="WARNING - Zombie calls: ${zombie_count} / ${channels_count} (${zombie_percent}%) | ${perf_data}"
        exit_formalities "${message}" "${ST_WR}"
    else
        message="OK - Zombie calls: ${zombie_count} / ${channels_count} (${zombie_percent}%) | ${perf_data}"
        exit_formalities "${message}" "${ST_OK}"
    fi
fi
