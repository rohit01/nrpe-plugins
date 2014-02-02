#!/bin/sh
#
# Nagios NRPE plugin to check latest commit ID in a repository
#

ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"
exit_status="${ST_OK}"

print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    print_version
    echo ""
    echo "$PROGNAME is a custom Nagios plugin to extract latest commit id"
    echo "in a git repository"
    echo "Usage: $PROGNAME -l <location>"
    echo ""
    echo "Options:"
    echo "  -l/--location)"
    echo "     Git repository location (Mandatory). For Eg: /usr/src/my_repo/"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -l /usr/src/my_repo/"
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
        --location|-l)
            location=$2
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
if echo $location | grep "^$" >/dev/null; then
    echo "Mandatory option -l/--location not specified"
    echo "Use -h/--help option to get more details"
    exit $ST_UK
fi
if echo "${location}" | grep -v "/$" >/dev/null; then
    location="${location}/"
fi
if [ ! -d "${location}" ]; then
    echo "'${location}' directory not found. Invalid repository"
    exit $ST_UK
fi
if [ ! -d "${location}.git/" ]; then
    echo "'${location}' is not a valid git repository"
    exit $ST_UK
fi
###########################################

check_exit_status() {
    if [ $? -ne 0 ]; then
            echo "CRITICAL - git [log/status] command failed in" \
                 " location: '${location}'"
            exit "${ST_WR}"
    fi
}

get_latest_commit_id() {
    cd "${location}"
    commit_id="$(git log | head -n 1 | tr -s " " | cut -d " " -f 2)"
    check_exit_status
    branch=$(git status | head -n 1 | sed 's/^.*branch \(.*\)$/\1/')
    check_exit_status
    echo "${location} ${branch} ${commit_id}"
}


get_latest_commit_id
exit "${exit_status}"
