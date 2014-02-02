#!/bin/bash
#
# Nagios NRPE plugin to check status weather the given ports are
# listening to TCP/UDP connections
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
    echo "$PROGNAME is a custom Nagios plugin to check port status"
    echo "using netstat command."
    echo ""
    echo "Usage: $PROGNAME -p <port numbers separated by comma>"
    echo ""
    echo "Options:"
    echo "  -p/--ports)"
    echo "     Check if the server is listening to given port numbers"
    echo "     Multiple port numbers can be given separated by comma"
    echo "  -t/--connectiontype)"
    echo "     Port type on which service listens. Possible values: tcp, udp"
    echo "     Default: check both"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -p 80,8080,8880"
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
        --ports|-p)
            ports=$2
            shift
            ;;
        --connectiontype|-t)
            connectiontype=$2
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

######## Validate arguments passed ########
if echo $ports | grep "^$" >/dev/null; then
    echo "Mandatory option -p/--ports not specified"
    echo "Use -h/--help option to get more details"
    exit $ST_UK
fi
if echo ${ports} | grep -v -e "^$" -e "^[0-9,]*$" | grep -v grep \
        | grep -v ${PROGNAME} >/dev/null; then
    echo "Invalid value: '${ports}' for option -p/--ports. Possible values:" \
         "integer separated by comma "
    exit $ST_UK
fi
if echo ${connectiontype} | grep -v -e "^tcp,udp$" -e "^tcp$" -e "^udp$" \
        >/dev/null; then
    echo "Invalid value: '${connectiontype}' for option -t/--connectiontype." \
         "Possible values: tcp, udp, {tcp,udp}. Default: tcp,udp"
    exit $ST_UK
fi
###########################################


## Set port type filter ##
if [ "X${connectiontype}" = 'Xtcp' ]; then
    type_filter='t'
elif [ "X${connectiontype}" = 'Xudp' ]; then
    type_filter='u'
elif [ "X${connectiontype}" = 'Xtcp,udp' ]; then
    type_filter='tu'
else
    type_filter='tu'
fi

exit_status="${ST_OK}"
message=''
for port_no in $(echo $ports | tr ',' ' ') ; do
    if echo ${message} | grep -v "^$" >/dev/null; then
        message="${message}; "
    fi
    netstat -ln${type_filter} | tr -s " " | cut -d " " -f 4 | grep ":$port_no$" >/dev/null
    if [ $? -ne 0 ]; then
        message="${message}Port: $port_no - NOT LISTENING"
        exit_status="${ST_CR}"
    else
        message="${message}Port: $port_no - LISTEN"
    fi
done


if [ $exit_status -eq $ST_OK ]; then
    echo "OK - ${message}"
    exit $ST_OK
elif [ $exit_status -eq $ST_WR ]; then
    echo "WARNING - ${message}"
    exit $ST_WR
elif [ $exit_status -eq $ST_CR ]; then
    echo "CRITICAL - ${message}"
    exit $ST_CR
else
    echo "UNKNOWN - $message"
    exit $ST_UK
fi