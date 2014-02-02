#!/bin/bash
#
# Nagios NRPE plugin to monitor unusual activities in system processes by
# greping strings and alerting based on the number of counts
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
    echo "$PROGNAME is a custom Nagios plugin to monitor unusual activities"
    echo "in system processes by greping strings and alerting based on the"
    echo "number of counts"
    echo ""
    echo "Options:"
    echo "  -m/--mandatory)"
    echo "     Comma separated string values which must be present in the"
    echo "     process listing. Typically | grep '<value>' | will be done"
    echo "  -o/--optional)"
    echo "     Comma separated string values in which at least one string must"
    echo "     be present in the process listing"
    echo "  -i/--casesensitive)"
    echo "     Strings will be considered case insensitive if this argument"
    echo "     is passed. Default: case sensitive"
    echo "  -w/--warning)"
    echo "     Warning level for no of matching processes found"
    echo "     Default: 1"
    echo "  -c/--critical)"
    echo "     Critical level for no of matching processes found"
    echo "     Default: 5"
    echo "  -t/--greptype)"
    echo "     Possible values: less/more. Default: less"
    echo "     less: less matching processes is better. ok < warning < critical"
    echo "     more: more matching processes is better. critical < warning < ok"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -m postgres -o 'INSERT waiting,ALTER TABLE waiting'"
}

## Set defaults for optional arguments
mandatory=''
optional=''
casesensitive=''
warning='1'
critical='5'
greptype='less'


exit_formalities() {
    if [ "X$1" != "X" ]; then
        echo "$1"
    fi
    if [ "X${TEMP_FILE}" != "X" ]; then
        rm -f "${TEMP_FILE}" || true
    fi
    exit "$2"
}


message=''
while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit_formalities "${message}" "${ST_UK}"
            ;;
        --version|-v)
            print_version
            exit_formalities "${message}" "${ST_UK}"
            ;;
        --mandatory|-m)
            mandatory="$2"
            shift
            ;;
        --optional|-o)
            optional="$2"
            shift
            ;;
        --casesensitive|-i)
            casesensitive="-i "
            ;;
        --warning|-w)
            warning="$2"
            shift
            ;;
        --critical|-c)
            critical="$2"
            shift
            ;;
        --greptype|-t)
            greptype="$2"
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

######## Validate arguments passed ########
if echo "${mandatory}" | grep "^\s*$" >/dev/null; then
    mandatory=''
    if echo "${optional}" | grep "^\s*$" >/dev/null; then
        message="At least one argument among --mandatory/--optional should be specified. Use option -h for more details"
        exit_formalities "${message}" "${ST_UK}"
    fi
elif echo "${mandatory}" | grep -v "^[a-zA-Z0-9 ,]*$" >/dev/null; then
    message="Invalid value: '${mandatory}' for option -m/--mandatory. Possible values: Alphabets and letters separated by comma"
        exit_formalities "${message}" "${ST_UK}"
elif echo "${optional}" | grep -v "^[a-zA-Z0-9 ,]*$" >/dev/null; then
    message="Invalid value: '${optional}' for option -o/--optional. Possible values: Alphabets and letters separated by comma"
        exit_formalities "${message}" "${ST_UK}"
elif echo "${warning}" | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    message="Invalid value: '${warning}' for option -w/--warning. Possible value: Positive integer"
    exit_formalities "${message}" "${ST_UK}"
elif echo "${critical}" | grep -v -e "^[0-9][0-9]*$" >/dev/null; then
    message="Invalid value: '${critical}' for option -c/--critical. Possible value: Positive integer"
    exit_formalities "${message}" "${ST_UK}"
elif echo "${greptype}" | grep -v -e 'less' -e 'more' >/dev/null; then
    message="Invalid value: '${greptype}' for option -t/--greptype. Possible value: less,more"
    exit_formalities "${message}" "${ST_UK}"
fi
if [ "X${greptype}" = "Xless" ]; then
    if [ ${warning} -gt ${critical} ]; then
        message="Parameter Error: warning: '${warning}' must be greater than critical: '${critical}'"
        exit_formalities "${message}" "${ST_UK}"
    fi
elif [ "X${greptype}" = "Xmore" ]; then
    if [ ${warning} -lt ${critical} ]; then
        message="Parameter Error: warning: '${warning}' must be less than critical: '${critical}'"
        exit_formalities "${message}" "${ST_UK}"
    fi
fi
###########################################


form_command() {
    unix_command='ps aux'
    grep_case="grep ${casesensitive}"
    if echo "${mandatory}" | grep -v "^\s*$" >/dev/null; then
        temp="$(echo "${mandatory}" | sed "s/[[:space:]]*,[,[:space:]]*/,/g" | sed 's/^,//' | sed 's/,$//')"
        temp="$(echo "${temp}" | sed "s/,/' | ${grep_case} '/g")"
        unix_command="${unix_command} | ${grep_case} '${temp}'"
    fi
    if echo "${optional}" | grep -v "^\s*$" >/dev/null; then
        temp="$(echo "${optional}" | sed "s/[[:space:]]*,[,[:space:]]*/,/g" | sed 's/^,//' | sed 's/,$//')"
        temp="$(echo "${temp}" | sed "s/,/' -e '/g")"
        unix_command="${unix_command} | ${grep_case} -e '${temp}'"
    fi
    echo "${unix_command} | grep -v 'grep' | grep -v '${PROGNAME}' | wc -l"
}

check_exit_status() {
    if [ $? -ne 0 ]; then
            echo "CRITICAL - Command: '${$1}' failed"
            exit ${ST_CR}
    fi
}


execute_check() {
    execute_command="$(form_command)"
    no_of_process="$(bash -c "${execute_command}")"
    check_exit_status "${execute_command}"
    echo "${no_of_process}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}


##############################################################################
############################ EXECUTE THE TEST ################################
##############################################################################

no_of_process="$(execute_check)"

if [ "X${greptype}" = "Xless" ]; then
    num_test='-ge'
    sign='>='
elif [ "X${greptype}" = "Xmore" ]; then
    num_test='-le'
    sign='<='
else
    message="Script Error: Invalid value(${greptype}) for variable greptype"
    exit_formalities "${message}" "${ST_UK}"
fi

if [ ${no_of_process} ${num_test} ${critical} ]; then
    message="CRITICAL - No of matching process: ${no_of_process} (${no_of_process} ${sign} ${critical} CR)"
    exit_formalities "${message}" "${ST_CR}"
elif [ ${no_of_process} ${num_test} ${warning} ]; then
    message="WARNING - No of matching process: ${no_of_process} (${no_of_process} ${sign} ${warning} WR)"
    exit_formalities "${message}" "${ST_WR}"
else
    message="OK - No of matching process: ${no_of_process}"
    exit_formalities "${message}" "${ST_OK}"
fi
