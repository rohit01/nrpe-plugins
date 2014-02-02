#!/usr/bin/env python
#
# Nagios custom NRPE plugin to monitor active instances in ELB at regular
# intervals. Example usage:
# $ ./elb_health.py -a '<API_KEY>' -s '<API_SECRET>' -l <ELB_NAME>
#

import boto
import boto.ec2
import boto.ec2.elb
import sys
import os
from optparse import OptionParser


AUTHOR = "Rohit Gupta - @rohit01"
VERSION = "1.0"
OPTIONS = {
    'a': "apikey;AWS Credential - API key",
    's': "apisecret;AWS Credential - API Secret key",
    'l': "loadbalancer;AWS Elastic Load Balancer name to be checked."
         " Mandatory",
    'r': "region;AWS region name in which load balancer is hosted. Default:"
         " us-east-1",
    'w': "warning;Health warning level (in %). Default: 99",
    'c': "critical;Health critical level (in %). Default: 50",
    'W': "warningcount;Healthy instance count warning level. Default: 0",
    'C': "criticalcount;Healthy instance count critical level. Default: 0",
}
FLAG_OPTIONS = {
    'v': "version;Display version no. and Sample usage",
}

# Nagios exit status values
ST_OK = 0
ST_WR = 1
ST_CR = 2
ST_UK = 3

# Argument Global variables
apikey = None
apisecret = None
loadbalancer = None
region = 'us-east-1'
warning = 99
critical = 50
warningcount = 0
criticalcount = 0

# Global variables (Declare & Set default)
exit_status = ST_OK
reason_for_alert_list = []
health_states = {}
DISPLAY_KEY_ORDER = ['Total', 'InService']


def parse_options():
    parser = OptionParser()
    for option, description in OPTIONS.items():
        shortopt = '-%s' % (option)
        longopt = '--%s' % (description.split(';')[0])
        keyname = description.split(';')[0]
        help = ''
        if len(description.split(';')) > 1:
            help = description.split(';')[1]
        parser.add_option(shortopt, longopt, dest=keyname, help=help)
    for option, description in FLAG_OPTIONS.items():
        shortopt = '-%s' % (option)
        longopt = '--%s' % (description.split(';')[0])
        keyname = description.split(';')[0]
        help = ''
        if len(description.split(';')) > 1:
            help = description.split(';')[1]
        parser.add_option(shortopt, longopt, dest=keyname,
                          action="store_true", help=help)
    (options, args) = parser.parse_args()
    return options


def validate_and_use_arguments_passed(arguments=None):
    global loadbalancer
    global region
    global warning
    global critical
    global warningcount
    global criticalcount
    global apikey
    global apisecret
    if arguments is None:
        arguments = parse_options()
    if arguments.version is True:
        message_list = []
        message_list.append('Version: %s, Author: %s' % (VERSION, AUTHOR))
        message_list.append('Sample usage:')
        message_list.append("$ ./%s -a '<API_KEY>' -s '<API_SECRET>' -l"
            " <ELB_NAME>" % os.path.basename(__file__))
        message_list.append("OK - ELB: my_elb. Total: 3; InService: 3")
        exit_formalalities('\n'.join(message_list), ST_UK)
    # Set global variables
    if arguments.loadbalancer is not None:
        loadbalancer = arguments.loadbalancer
    if arguments.region is not None:
        region = arguments.region
    if arguments.warning is not None:
        warning = arguments.warning
    if arguments.critical is not None:
        critical = arguments.critical
    if arguments.warningcount is not None:
        warningcount = arguments.warningcount
    if arguments.criticalcount is not None:
        criticalcount = arguments.criticalcount
    if arguments.apikey is not None:
        apikey = arguments.apikey
    if arguments.apisecret is not None:
        apisecret = arguments.apisecret
    # Validate
    if apikey is None:
        message = 'Mandatory option -a/--apikey not specified'
        exit_formalalities(message, ST_UK)
    if apisecret is None:
        message = 'Mandatory option -s/--apisecret not specified'
        exit_formalalities(message, ST_UK)
    if loadbalancer is None:
        message = 'Mandatory option -l/--loadbalancer not specified'
        exit_formalalities(message, ST_UK)
    if region is None:
        message = 'Script Error: Default value for -r/--region not set'
        exit_formalalities(message, ST_UK)
    if warning is None:
        message = 'Script Error: Default value for -w/--warning not set'
        exit_formalalities(message, ST_UK)
    if critical is None:
        message = 'Script Error: Default value for -c/--critical not set'
        exit_formalalities(message, ST_UK)
    if warningcount is None:
        message = 'Script Error: Default value for -W/--warningcount not set'
        exit_formalalities(message, ST_UK)
    if criticalcount is None:
        message = 'Script Error: Default value for -C/--criticalcount not set'
        exit_formalalities(message, ST_UK)
    warning = convert_into_integer(warning, '-w/--warning')
    critical = convert_into_integer(critical, '-c/--critical')
    if warning < critical:
        message = 'warning: %s must be greater than critical: %s' % (warning,
                                                                     critical)
        exit_formalalities(message, ST_UK)
    warningcount = convert_into_integer(warningcount, '-W/--warningcount')
    criticalcount = convert_into_integer(criticalcount, '-C/--criticalcount')
    if warningcount < criticalcount:
        message = 'warningcount: %s must be greater than criticalcount: %s' \
                  % (warningcount, criticalcount)
        exit_formalalities(message, ST_UK)


def convert_into_integer(value, option_name):
    try:
        return int(value)
    except ValueError:
        message = "Invalid value: '%s' passed for option: %s. Value must be" \
                  " a integer" % (value, option_name)
        exit_formalalities(message, ST_UK)


def exit_formalalities(message, exit_status):
    print message
    sys.exit(exit_status)


def get_elb_connection(region_name):
    try:
        conn = boto.ec2.elb.connect_to_region(region_name=region_name,
                                              aws_access_key_id=apikey,
                                              aws_secret_access_key=apisecret)
    except Exception, e:
        print e
        message = "Exception occured in creating AWS ELB connection object"
        exit_formalalities(message, ST_CR)
    return conn


def fetch_load_balancer():
    conn = get_elb_connection(region)
    try:
        elb_list = conn.get_all_load_balancers(load_balancer_names=
                                               [loadbalancer])
        return elb_list[0]
    except boto.exception.BotoServerError:
        message = "Exception occured in fetching AWS ELB: '%s' details in" \
                  " region: '%s'" % (loadbalancer, region)
        exit_formalalities(message, ST_CR)


def calculate_exit_status(elb_object):
    global exit_status
    global health_states
    health_list = elb_object.get_instance_health()
    for instance_health in health_list:
        key = str(instance_health.state).strip()
        try:
            health_states[key] += 1
        except KeyError:
            health_states[key] = 1
    if 'InService' not in health_states:
        health_states['InService'] = 0
    total = len(health_list)
    health_states['Total'] = total
    healthy_count = health_states['InService']
    if total == 0:
        healthy_percentage = 0
    else:
        healthy_percentage = float(healthy_count) * 100.0 / float(total)
    if healthy_percentage <= critical:
        exit_status = ST_CR
        message = 'InService count <= %s%% (CR)' % critical
        reason_for_alert_list.append(message)
    elif healthy_percentage <= warning:
        if exit_status == ST_OK or exit_status == ST_UK:
            exit_status = ST_WR
        message = 'InService count <= %s%% (WR)' % warning
        reason_for_alert_list.append(message)
    if healthy_count <= criticalcount:
        exit_status = ST_CR
        message = 'InService count <= %s(CR)' % criticalcount
        reason_for_alert_list.append(message)
    elif healthy_count <= warningcount:
        if exit_status == ST_OK or exit_status == ST_UK:
            exit_status = ST_WR
        message = 'InService count <= %s(WR)' % warningcount
        reason_for_alert_list.append(message)


def formatted_message():
    message = ''
    key_checked = []
    for key in DISPLAY_KEY_ORDER + health_states.keys():
        if key in key_checked:
            continue
        key_checked.append(key)
        try:
            value = health_states[key]
        except KeyError:
            continue
        if message != '':
            message = '%s; ' % message
        unit_message = '%s: %s' % (key, value)
        message = "%s%s" % (message, unit_message)
    return message


if __name__ == '__main__':
    arguments = parse_options()
    validate_and_use_arguments_passed(arguments=arguments)
    elb_object = fetch_load_balancer()
    calculate_exit_status(elb_object)
    current_status = formatted_message()

    if len(reason_for_alert_list) > 0:
        alert_reason = ', '.join(reason_for_alert_list)
        alert_reason = '. Reason: %s' % alert_reason
    else:
        alert_reason = ''

    # print final message & exit
    if exit_status == ST_OK:
        message = 'OK - ELB: %s. %s%s' % (loadbalancer, current_status,
                                          alert_reason)
    elif exit_status == ST_WR:
        message = 'WARNING - ELB: %s. %s%s' % (loadbalancer, current_status,
                                               alert_reason)
    elif exit_status == ST_CR:
        message = 'CRITICAL - ELB: %s. %s%s' % (loadbalancer, current_status,
                                                alert_reason)
    else:
        message = 'UNKNOWN - ELB: %s. %s%s' % (loadbalancer, current_status,
                                               alert_reason)
    exit_formalalities(message, exit_status=exit_status)
