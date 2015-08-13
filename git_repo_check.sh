#!/bin/sh
#
# Nagios NRPE plugin to ensure a repository does not contain local changes
#

ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"
branch="master"

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
    echo "  -b/--branch)"
    echo "     Git branch name. default: master"
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
        --branch|-b)
            branch=$2
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

if [ ! -r "${location}" ]; then
    echo "CRITICAL - location '${location}' does not exists"
    exit "${ST_CR}"
fi

cd "${location}"
git_status="$(git status)"
if [ $? -ne 0 ]; then
    echo "CRITICAL - 'git status' command failed at '${location}'"
    exit "${ST_CR}"
fi

branch_status=""
if echo "${git_status}" | grep "On branch ${branch}$" >/dev/null; then
    branch_status="ok"
elif echo "${git_status}" | grep "HEAD detached at ${branch}$" >/dev/null; then
    branch_status="ok"
fi

if [ "X${branch_status}" != "Xok" ]; then
    echo "CRITICAL - git repo is not on branch/tag '${branch}' at '${location}'"
    exit "${ST_CR}"
fi

if [ $(echo "${git_status}" | wc -l) -gt 4 ]; then
    echo "CRITICAL - git repo contains local changes at '${location}'"
    exit "${ST_CR}"
fi

echo "OK: git repo looks good at '${location}'"
