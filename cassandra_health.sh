#!/usr/bin/env bash
#
# NRPE plugin to check status of cassandra
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

## Global static variables
ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

## Defaults
warning=80
critical=50


print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    print_version
    echo ""
    echo "$PROGNAME is a custom NRPE plugin to check cassandra status"
    echo "using nodetool command."
    echo ""
    echo "Usage: $PROGNAME -t 'show channels count' [-w 80] [-c 90]"
    echo ""
    echo "Options:"
    echo "  -t/--checktype)"
    echo "     Type of check to perform. Valid examples: status & token"
    echo "  -w/--warning)"
    echo "     token: warning is percent of tokens up. Default: 80"
    echo "  -c/--critical)"
    echo "     token: critical is percent of tokens up. Default: 50"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -t 'status' [-w 80 -c 50]"
}

exit_formalities() {
    if [ "X$1" != "X" ]; then
        echo "$1"
    fi
    exit "$2"
}

check_exit_status() {
    if [ $? -ne 0 ]; then
        message="CRITICAL - Cassandra not responding!"
        exit_formalities "${message}" "${ST_CR}"
    fi
}

execute_nodetool() {
    echo "$(nodetool ${1})"
    check_exit_status
}

formatted_status_message() {
    node_version="${1}"
    node_info="${2}"
    version="$(echo "$node_version" | grep -i "^ReleaseVersion" | cut -d":" -f 2 | xargs)"
    uptime="$(echo "$node_info" | grep -i "^Uptime " | cut -d":" -f 2 | xargs)"
    load="$(echo "$node_info" | grep -i "^Load " | cut -d":" -f 2 | xargs | sed 's/ //g')"
    heap_mem="$(echo "$node_info" | grep -i "^Heap Memory " | cut -d":" -f 2 | xargs | sed 's/ //g')"
    off_heap_mem="$(echo "$node_info" | grep -i "^Off Heap Memory " | cut -d":" -f 2 | xargs | sed 's/ //g')"
    gossip="$(echo "$node_info" | grep -i "^Gossip " | cut -d":" -f 2 | xargs)"
    thrift="$(echo "$node_info" | grep -i "^Thrift " | cut -d":" -f 2 | xargs)"
    native_transport="$(echo "$node_info" | grep -i "^Native Transport " | cut -d":" -f 2 | xargs)"
    if [ "X${gossip}" = "Xtrue" ]; then
        gossip="active"
    else
        gossip="inactive"
    fi
    if [ "X${thrift}" = "Xtrue" ]; then
        thrift="active"
    else
        thrift="inactive"
    fi
    if [ "X${native_transport}" = "Xtrue" ]; then
        native_transport="active"
    else
        native_transport="inactive"
    fi
    echo "Version:${version} uptime:${uptime} load:${load} heap_mem:${heap_mem}mb off_heap_mem:${off_heap_mem}mb gossip:${gossip} thrift:${thrift} native_transport:${native_transport} | load=${load} heap_mem:${heap_mem}MB off_heap_mem:${off_heap_mem}mb"
}

calc_tokens_health() {
    node_ring="$1"
    tokens_up="$(echo "${node_ring}" | grep -c ' Up ')"
    tokens_down="$(echo "${node_ring}" | grep -c ' Down ')"
    total_tokens="$((${tokens_up} + ${tokens_down}))"
    percent_tokens_up="$((${tokens_up} * 100 / ${total_tokens}))"
    warning_count="$((${warning} * ${total_tokens} / 100))"
    critical_count="$((${critical} * ${total_tokens} / 100))"
    perf_info="tokens_up=${tokens_up};${warning_count};${critical_count} tokens_down=${tokens_down} total_tokens=${total_tokens}"
    if [ "${percent_tokens_up}" -le "${critical}" ]; then
        echo "CRITICAL - Tokens up: ${tokens_up}/${total_tokens} (${percent_tokens_up}%) | ${perf_info}"
        exit "${ST_CR}"
    elif [ "${percent_tokens_up}" -le "${warning}" ]; then
        echo "WARNING - Tokens up: ${tokens_up}/${total_tokens} (${percent_tokens_up}%) | ${perf_info}"
        exit "${ST_WR}"
    else
        echo "OK - Tokens up: ${tokens_up}/${total_tokens} (${percent_tokens_up}%) | ${perf_info}"
        exit "${ST_OK}"
    fi
}

#### GET OPTION ARGUMENTS #####################################################
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
            warning="$2"
            shift
            ;;
        --critical|-c)
            critical="$2"
            shift
            ;;
        --checktype|-t)
            checktype="$2"
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

#### VALIDATION ###############################################################
if [ "X${checktype}" == "X" ]; then
    echo "ERROR: Mandatory argument '--checktype' not provided"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
elif [ "X${checktype}" != "Xstatus" ] && 
        [ "X${checktype}" != "Xtoken" ]; then
    echo "ERROR: Invalid value for checktype - '${checktype}'. Valid values are: "
    echo "'status', 'token'"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
fi
if [ ${warning} -lt ${critical} ]; then
    echo "ERROR: Value for --warning (${warning}%) must be greater than --critical (${critical}%)"
    exit_formalities "${message}" "${ST_UK}"
fi

#### EXECUTE CHECK ############################################################
if [ "X${checktype}" == "Xstatus" ]; then
    node_version="$(execute_nodetool version)"
    node_info="$(execute_nodetool info)"
    ## Print message and exit
    message="$(formatted_status_message "${node_version}" "${node_info}")"
    exit_formalities "${message}" "${ST_OK}"

elif [ "X${checktype}" == "Xtoken" ]; then
    node_ring="$(execute_nodetool ring)"
    message="$(calc_tokens_health "${node_ring}")"
    exit_formalities "${message}" "$?"
fi
