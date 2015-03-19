#!/usr/bin/env bash
#
# NRPE plugin to check status of freeswitch
# Valid commands: 'show channels count', 'status'
#
# Actual fs_cli commands being run to perform checks:
# show channels count: /usr/local/freeswitch/bin/fs_cli -b -q -x "show channels count" -t 2000
# status: /usr/local/freeswitch/bin/fs_cli -b -q -x "status" -t 2000
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

## Global static variables
ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

## Global variables & default settings
fs_command="$1"
message=""
fscli_output=""
warning="400"
critical="500"


print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    print_version
    echo ""
    echo "$PROGNAME is a custom NRPE plugin to check freeswitch status"
    echo "using fs_cli command."
    echo "Freeswitch status check commands defined in this module are:"
    echo "'show channels count', 'status'"
    echo ""
    echo "Usage: $PROGNAME 'show channels count' [-w 80] [-c 90]"
    echo ""
    echo "Options:"
    echo "  -w/--warning)"
    echo "     Defines a warning level. Not applicable for 'status' command"
    echo "     Command: "
    echo "        'show channels count': No of channels in use. Default: 400"
    echo "  -c/--critical)"
    echo "     Defines a critical level. Not applicable for 'status' command"
    echo "     Command: "
    echo "        'show channels count': No of channels in use. Default: 500"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME 'status'"
    echo "   $PROGNAME 'show channels count' -w 500 -c 650"
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
    /usr/local/freeswitch/bin/fs_cli -b -q -x "$fs_command" -t 2000
    check_exit_status
    check_timeout
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
    echo "'show channels count' & 'status'"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
elif [ "X${fs_command}" != "Xstatus" ] && [ "X${fs_command}" != "Xshow channels count" ]; then
    echo "Invalid command - '${fs_command}'. Valid commands are: "
    echo "'show channels count' & 'status'"
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
    fscli_output="$(execute_check)"
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

elif [ "X${fs_command}" == "Xshow channels count" ]; then
    ## Execute test for fs command - show channels count
    fscli_output="$(execute_check)"
    channels="$(echo "${fscli_output}" | tail -n 1 | tr -s ' ' | cut -d' ' -f 1 | sed 's/^ *//g' | sed 's/ *$//g')"
    perf_data="channels=${channels};${warning};${critical}"
    if [ "${channels}" -ge "${critical}" ]; then
        message="CRITICAL - No of Channels in use: ${channels} | ${perf_data}"
        exit_formalities "${message}" "${ST_CR}"
    elif [ "${channels}" -ge "${warning}" ]; then
        message="WARNING - No of Channels in use: ${channels} | ${perf_data}"
        exit_formalities "${message}" "${ST_WR}"
    else
        message="Ok - No of Channels in use: ${channels} | ${perf_data}"
        exit_formalities "${message}" "${ST_OK}"
    fi
fi
