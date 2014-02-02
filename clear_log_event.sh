#!/bin/bash
#
# Script to delete the oldest log file in a directory. To be used as a
# event for monitoring disk space. Can help automatically clean log files.
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}

print_help() {
    echo "$PROGNAME is a custom Nagios plugin to clear old log file contents"
    echo ""
    echo "Usage: $PROGNAME [-d /var/log/] [-s 5M]"
    echo ""
    echo "Options:"
    echo "  -d/--logdir)"
    echo "     Directory to search for old log files. Can be a Unix"
    echo "     regex as well. Default: /var/log/"
    echo ""
    echo "  -s/--minsize)"
    echo "     Minimum size of the log file targeted for deletion. Supported"
    echo "     suffix: k(KB), M(MB), G(GB). Default: 5M"
    echo ""
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
}

# Set Default
logdir='/var/log/'
minsize='5M'

# Parse Arguments
while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit $ST_UK
            ;;
        --version|-v)
            print_version $PROGNAME $VERSION
            exit $ST_UK
            ;;
        --logdir|-d)
            logdir=$2
            shift
            ;;
        --minsize/-s)
            minsize=$2
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


file_names=$(find ${logdir} -type f -size +${minsize} -name "*.log*" | while read f; do echo $f; done | tr '\n' " ")
if test "x${file_names}" != "x"
then
    ls -tr ${file_names} | while read log_file
    do
        echo "Clearing log file: $log_file, Size: $(du -sh $log_file | cut -f 1)"
        cat /dev/null > $log_file
        break                       # Clear only one log file
    done
fi

exit $ST_OK