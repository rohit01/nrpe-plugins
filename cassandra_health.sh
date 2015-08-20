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
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -t 'status'"
}

exit_formalities() {
    echo "$1"
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


## Get option arguments
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
    echo "Mandatory argument 'checktype' not provided"
    echo "Use -h/--help option to get more details"
    exit_formalities "${message}" "${ST_UK}"
elif [ "X${checktype}" != "Xstatus" ] && 
        [ "X${checktype}" != "Xtoken" ]; then
    echo "Invalid value for checktype - '${checktype}'. Valid values are: "
    echo "'status', 'token'"
    echo "Use -h/--help option to get more details"
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
    tokens_up="$(echo "${node_ring}" | grep -c ' Up ')"
    tokens_down="$(echo "${node_ring}" | grep -c ' Down ')"
    total_tokens="$(expr ${tokens_up} + ${tokens_down})"
    message="tokens_up:${tokens_up} tokens_down:${tokens_down} total_tokens:${total_tokens}"
    exit_formalities "${message}" "${ST_OK}"
fi
