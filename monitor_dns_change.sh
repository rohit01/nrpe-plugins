#!/bin/bash
#
# Nagios plugin to monitor the given DNS change & reload/restart running
# to counter dns cached locally. Noticed DNS cache problem in nginx.
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="Version 1.0,"

# Setings
LOCK_FILENAME='/tmp/._monitor_DNS_change_lock_1855_'
LOCK_TIMEOUT='30'                                               # 30 seconds
KEEP_TRACK_FILE='/tmp/._monitor_DNS_change_keep_track_1855_'
NO_OF_RETRY='10'
INIT_DIR='/etc/init.d/'
NOT_FOUND_TEXT='Not_Found'

# Exit status veriables
ST_OK='0'
ST_WR='1'
ST_CR='2'
ST_UK='3'

# Delimiters:
D_DIFF_DNS=';'
D_DNS_AND_IP=':'

print_version() {
    echo "$PROGNAME: $VERSION $AUTHOR"
}


print_help() {
    echo ""
    echo "$PROGNAME is a custom Nagios plugin to monitor DNS change &"
    echo "reload/restart nginx (or any other service) if DNS has changed"
    echo ""
    echo "Usage: $PROGNAME -d <dns> [-s <service> -a <action>]"
    echo ""
    echo "Options:"
    echo "  -d/--dns_names)"
    echo "     dns addresses separated by comma"
    echo "  -s/--services)"
    echo "     Services (separated by comma) to reload/restart in event of DNS "
    echo "     change. Default: nginx"
    echo "  -a/--action)"
    echo "     Init script argiments: start/stop/restart/reload."
    echo "     Default: reload"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -d example.com,eg.com -s nginx,apache -a reload"
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
        --dns_names|-d)
            dns_names=$2
            shift
            ;;
        --services|-s)
            services=$2
            shift
            ;;
        --action|-a)
            action=$2
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


# verify $dns_names variable
if echo $dns_names | grep "^\s*$" >/dev/null ; then
    echo "DNS names not passed. Used option '-d' to specify"
    exit $ST_UK
fi
# Set Defaults for $services variable
if echo $services | grep "^\s*$" >/dev/null ; then
    services='nginx'
fi
# Set Defaults for $action variable
if echo $action | grep "^\s*$" >/dev/null ; then
    action='reload'
fi


resolve_dns_to_ip() {
    mapping=''
    for dns in $(echo $dns_names | tr ',' ' '); do
        TEMP_ANSWER_FILE="/tmp/._monitor_DNS_change_temp_$RANDOM"
        /usr/bin/nslookup $dns > ${TEMP_ANSWER_FILE}
        if cat ${TEMP_ANSWER_FILE} | grep "NXDOMAIN" >/dev/null; then
            ip_address=${NOT_FOUND_TEXT}
        else
            ip_address=$(cat ${TEMP_ANSWER_FILE} | grep -i "Address" | \
                grep -v '[0-9]\.[0-9]\.[0-9]\.[0-9]#53' | \
                tail -n 1 | cut -d":" -f 2 | sed 's/^\s*//' | sed 's/\s*$//')
        fi
        rm -f ${TEMP_ANSWER_FILE} || true
        if echo ${mapping} | grep -v "^\s*$" >/dev/null; then
            mapping="${mapping}${D_DIFF_DNS}"
        fi
        mapping="${mapping}${dns}${D_DNS_AND_IP}${ip_address}"
    done
    echo ${mapping}
}


check_difference() {
    is_different=false
    for current_mapping in $(echo ${current_details} | tr ${D_DIFF_DNS} ' '); do
        current_dns=$(echo ${current_mapping} | cut -d "${D_DNS_AND_IP}" -f 1 )
        current_ip=$(echo ${current_mapping} | cut -d "${D_DNS_AND_IP}" -f 2 )
        old_mapping="${NOT_FOUND_TEXT}"
        for mapping in $(echo ${old_details} | tr ${D_DIFF_DNS} ' '); do
            old_dns=$(echo ${mapping} | cut -d "${D_DNS_AND_IP}" -f 1 )
            if echo ${old_dns} | grep "^${current_dns}$" >/dev/null; then
                old_mapping=${mapping}
                break
            fi
        done
        if echo "${old_mapping}" | grep "^${NOT_FOUND_TEXT}$" >/dev/null; then
            is_different=true
            break
        fi
        old_ip=$(echo ${old_mapping} | cut -d "${D_DNS_AND_IP}" -f 2 )
        if echo "${current_ip}" | grep -v "^${old_ip}$" >/dev/null; then
            is_different=true
            break
        fi
    done
    echo "${is_different}"
}


if [ -f $LOCK_FILENAME ]; then
    last_timestamp=$(tail -n 1 $LOCK_FILENAME)
    current_timestamp=$(date +%s)
    delay=$(expr $current_timestamp - $last_timestamp || echo ${LOCK_TIMEOUT}0 )
    if [ $delay -lt $LOCK_TIMEOUT ] && [ $delay -gt 0 ]; then
        echo "The script is already running !"
        exit $ST_UK
    fi
else
    date +%s > $LOCK_FILENAME
fi


current_details="$(resolve_dns_to_ip)"
if [ ! -f ${KEEP_TRACK_FILE} ]; then
    echo ${current_details} > ${KEEP_TRACK_FILE}
    echo "UNKNOWN - OLD dns details not found !"
    rm -f $LOCK_FILENAME || true
    exit $ST_UK
else
    old_details=$(cat ${KEEP_TRACK_FILE} | sed 's/^\s*//' | sed 's/\s*$//')
    is_different=$(check_difference)
    exit_status="${ST_OK}"
    if "${is_different}"; then
        exit_status="${ST_WR}"
        for service_name in $(echo ${services} | tr ',' ' '); do
            failed=false
            cmd="${INIT_DIR}${service_name} ${action}"
            $cmd || $cmd || $cmd || $cmd || $cmd || failed="true"
            if ${failed}; then
                exit_status="${ST_CR}"
            fi
            if echo ${failed_cmds} | grep -v "^\s*$" >/dev/null; then
                failed_cmds="${failed_cmds}, "
            fi
            failed_cmds="${failed_cmds}'${cmd}'"
        done
    fi
fi


rm -f $LOCK_FILENAME || true
if echo "${exit_status}" | grep "${ST_OK}" >/dev/null; then
    echo "OK - DNS has not changed"
elif echo "${exit_status}" | grep "${ST_WR}" >/dev/null; then
    echo ${current_details} > ${KEEP_TRACK_FILE}
    echo "WARNING - DNS Changed. Services reloaded/restarted"
elif echo "${exit_status}" | grep "${ST_CR}" >/dev/null; then
    echo "CRITICAL - Error in executing commands: ${failed_cmds}"
else
    exit_status=${ST_UK}
    echo "UNKNOWN - Unknown exit status !"
fi
exit ${exit_status}
