#!/bin/sh
#
# Custom NRPE plugin for monitoring approximate replication lag between master
# and slave postgres servers. The check should be deployed in both master and
# slave with high frequency
#

ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

## Global variables
psql="$(which psql || echo '/opt/PostgreSQL/9.1/bin/psql')"
user=postgres
host="127.0.0.1"
ADD_DATA_TIMEOUT='59'

print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}


print_help() {
    echo ""
    echo "$PROGNAME is a custom Nagios plugin to monitor replication lag"
    echo " between master and slave postgres DBs. It should be deployed in"
    echo " both master and slave"
    echo ""
    echo "Usage: $PROGNAME -d [<database>] [-w <integer>] [-c <integer>]"
    echo ""
    echo "Options:"
    echo "  -d/--database)"
    echo "     Database to be use for this test. Mandatory option"
    echo "  -w/--warning)"
    echo "     Replication delay warning level. Integer (no. of seconds)"
    echo "     Default value: 100"
    echo "  -c/--critical)"
    echo "     Replication delay critical level. Integer (no. of seconds)"
    echo "     Default value: 500"
    echo "  -t/--timeout)"
    echo "     Add data in master db for given seconds. (Applicable only for"
    echo "     master db). Default value: 59"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -d my_db -w 50 -c 200"
}


get_wcdiff() {
    if [ ! -z "$warning" -a ! -z "$critical" ]
    then
        wclvls=1
        if [ ${warning} -gt ${critical} ]
        then
            wcdiff=1
        fi
    elif [ ! -z "$warning" -a -z "$critical" ]
    then
        wcdiff=2
    elif [ -z "$warning" -a ! -z "$critical" ]
    then
        wcdiff=3
    fi
}


val_wcdiff() {
    if [ "$wcdiff" = 1 ]
    then
        echo "Please adjust your warning/critical thresholds. The warning " \
             "must be lower than the critical level."
        exit $ST_UK
    elif [ "$wcdiff" = 2 ]
    then
        echo "Please also set a critical value when you want to use " \
             "warning/critical thresholds!"
        exit $ST_UK
    elif [ "$wcdiff" = 3 ]
    then
        echo "Please also set a warning value when you want to use " \
             "warning/critical thresholds!"
        exit $ST_UK
    fi
}


do_check_slave() {
    query_last_monitor_time="SELECT extract(epoch from last_monitor_time) FROM repl_monitor ORDER BY last_monitor_time DESC LIMIT 1"
    last_monitor_time=$($psql -h $host -U $user -d $database -A -t -c "$query_last_monitor_time")
    # Truncating decimal places
    last_monitor_time=$( printf "%.0f" $last_monitor_time)
    current_epoch=$(date +%s)
    # Calculating the time_lag between master and slave
    time_lag=`expr $current_epoch - $last_monitor_time`
    perf_data="time_lag=$time_lag"
    output="Time lag:$time_lag Current time:$current_epoch Last monitor time:$last_monitor_time"
}


do_output() {
## Check if the time_lag is greater than warning
if [ $(echo "$time_lag >= $warning"|bc) -eq 1 ]
then
    ## Check if time_lag is greater than critical
    if [ $(echo "$time_lag >= $critical"|bc) -eq 1 ]
    then
        echo "CRITICAL - $output | $perf_data"
        exit $ST_CR
    else
        echo "WARNING - $output | $perf_data"
        exit $ST_WR
    fi
else
    echo "OK - $output | $perf_data"
    exit $ST_OK
fi
}

## Set defaults:
timeout="${ADD_DATA_TIMEOUT}"
warning='100'
critical='500'


while test -n "$1"; do
    case "$1" in
        -help|-h)
            print_help
            exit $ST_UK
            ;;
        --database|-d)
            database=$2
            shift
            ;;
        --warning|-w)
            warning=$2
            shift
            ;;
        --critical|-c)
            critical=$2
            shift
            ;;
        --timeout|-t)
            timeout=$2
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_help
            exit $ST_UK
            ;;
        esac
    shift
done


is_slave=$($psql -h $host -U postgres -A -t -c "select pg_last_xlog_receive_location()" |grep ^[A-Z0-9a-z] -c)
if [ "$is_slave" = "0" ]; then
    # Master Postgres DB
    # Create replication table if it does not exists
    create_table_query="CREATE TABLE IF NOT EXISTS repl_monitor (last_monitor_time TIMESTAMP WITHOUT TIME ZONE NOT NULL)"
    is_table=$($psql -h $host -U $user -d $database -A -t -c "$create_table_query")

    start_timestamp=$(date +%s)
    current_timestamp=$(date +%s)
    delay=$(expr ${current_timestamp} - ${start_timestamp})
    while [ ${delay} -le ${timeout} ]; do
        $psql -h $host -U $user -d $database -A -t -c "DELETE FROM repl_monitor; INSERT INTO repl_monitor VALUES (now());"
        sleep 1
        current_timestamp=$(date +%s)
        delay=$(expr ${current_timestamp} - ${start_timestamp})
    done
    echo "Value inserted successfully in db"
    exit ${ST_OK}
else
    # Slave Postgres DB
    get_wcdiff
    val_wcdiff
    do_check_slave
    do_output
fi
