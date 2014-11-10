#!/usr/bin/env python
#
# Nagios custom NRPE plugin to check ELB health at regular intervals
# Author: Rohit Gupta - @rohit01
#

import boto
import boto.ec2
import boto.ec2.elb
import sys
import os
import logging
import optparse


__version__ = 0.1
VERSION = """Version: %s, Author: Rohit Gupta - @rohit01""" % __version__
DESCRIPTION = """Nagios plugin for monitor ELB instance health count"""
OPTIONS = {
    "aws_access_key"    : "AWS access key",
    "aws_secret_access" : "AWS secret key",
    "loadbalancer"      : "AWS Elastic Load Balancer name to be checked",
    "region"            : "AWS region name in which load balancer is hosted. Default: us-east-1",
    "warning"           : "Health warning level (in %). Default: 99",
    "critical"          : "Health critical level (in %). Default: 50",
    "warningcount"      : "Healthy instance count warning level. Default: 1",
    "criticalcount"     : "Healthy instance count critical level. Default: 0",
}
USAGE = "%s --aws_access_key=<value> --aws_secret_access=<value> " \
    "--loadbalancer=<value> [other options]"  % os.path.basename(__file__)

DEFAULTS = {
    "region"        : 'us-east-1',
    "warning"       : 99,
    "critical"      : 50,
    "warningcount"  : 1,
    "criticalcount" : 0,
}

# Global variables
ST_OK = 0
ST_WR = 1
ST_CR = 2
ST_UK = 3
exit_status = ST_OK
reason_for_alert_list = []
health_states = {}
DISPLAY_KEY_ORDER = ['Total', 'InService']
logger = logging.getLogger("ELB health check")
logger.setLevel(logging.WARNING)
# Logging in syslog (/var/log/syslog)
handler = logging.handlers.SysLogHandler(address='/dev/log')
logger.addHandler(handler)


def parse_options(options, description=None, usage=None, version=None,
        defaults=None):
    parser = optparse.OptionParser(description=description, usage=usage,
                                   version=version)
    for keyname, description in options.items():
        longopt = '--%s' % keyname
        parser.add_option(longopt, dest=keyname, help=description)
    option_args, _ = parser.parse_args()
    arguments = {}
    for keyname in options.keys():
        arguments[keyname] = eval("option_args.%s" % keyname)
    if defaults:
        for k, v in arguments.items():
            if (not v) and (k in defaults):
                arguments[k] = defaults[k]
    return arguments


def validate_arguments(arguments=None):
    # Validate Mandatory options
    for k, v in arguments.items():
        if (not v) and (k not in DEFAULTS):
            message = "Mandatory option --%s is missing. Use -h/--help for" \
                " details" % k
            exit_formalalities(message, ST_UK)
    # Integer arguments
    for key in 'warning', 'critical', 'warningcount', 'criticalcount':
        try:
            arguments[key] = int(arguments[key])
            if arguments[key] < 0:
                raise ValueError()
        except ValueError:
            message = "Option --%s invalid. Value %s must be a positive " \
                "integer" % (key, arguments[key])
            exit_formalalities(message, ST_UK)
    if arguments["warning"] < arguments["critical"]:
        message = "option --warning(%s) must be greater than --critical(%s)" \
             % (arguments["warning"], arguments["critical"])
        exit_formalalities(message, ST_UK)
    if arguments["warningcount"] < arguments["criticalcount"]:
        message = "option --warningcount(%s) must be greater than --criticalcount(%s)" \
             % (arguments["warningcount"], arguments["criticalcount"])
        exit_formalalities(message, ST_UK)


def exit_formalalities(message, exit_status):
    print message
    sys.exit(exit_status)


def get_elb_connection(region, aws_access_key, aws_secret_access):
    try:
        conn = boto.ec2.elb.connect_to_region(
            region_name=region,
            aws_access_key_id=aws_access_key, 
            aws_secret_access_key=aws_secret_access
        )
    except Exception as e:
        print e
        message = "Exception occured: %s" % e.message
        exit_formalalities(message, ST_CR)
    return conn


def fetch_load_balancer(arguments):
    conn = get_elb_connection(arguments['region'],arguments['aws_access_key'],
        arguments['aws_secret_access'])
    try:
        elb_list = conn.get_all_load_balancers(
            load_balancer_names=[arguments['loadbalancer']])
        return elb_list[0]
    except boto.exception.BotoServerError as e:
        message = "Exception occured while fetching AWS ELB: %s, region: %s." \
            " Message: %s" % (arguments['loadbalancer'], arguments['region'], e.message)
        exit_formalalities(message, ST_CR)


def calculate_exit_status(elb_object, arguments):
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
    if healthy_percentage <= arguments['critical']:
        exit_status = ST_CR
        message = 'InService count <= %s%% (CR)' % arguments['critical']
        reason_for_alert_list.append(message)
    elif healthy_percentage <= arguments['warning']:
        if exit_status == ST_OK or exit_status == ST_UK:
            exit_status = ST_WR
        message = 'InService count <= %s%% (WR)' % arguments['warning']
        reason_for_alert_list.append(message)
    if healthy_count <= arguments['criticalcount']:
        exit_status = ST_CR
        message = 'InService count <= %s(CR)' % arguments['criticalcount']
        reason_for_alert_list.append(message)
    elif healthy_count <= arguments['warningcount']:
        if exit_status == ST_OK or exit_status == ST_UK:
            exit_status = ST_WR
        message = 'InService count <= %s(WR)' % arguments['warningcount']
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


def calc_perf_data(arguments):
    inservice = health_states['InService']
    total = health_states['Total'] 
    if total == 0:
        inservice_percent = 0
    else:
        inservice_percent = float(inservice) * 100.0 / float(total)
    data = "inservice=%s%%;%s;%s" % (
        inservice_percent, arguments['warning'], arguments['critical']
    )
    return data


def run():
    try:
        arguments = parse_options(OPTIONS, DESCRIPTION, USAGE, VERSION, DEFAULTS)
        validate_arguments(arguments=arguments)
        elb_object = fetch_load_balancer(arguments)
        calculate_exit_status(elb_object, arguments)
        current_status = formatted_message()
        perf_data = calc_perf_data(arguments)
        if len(reason_for_alert_list) > 0:
            alert_reason = ', '.join(reason_for_alert_list)
            alert_reason = '. Reason: %s' % alert_reason
        else:
            alert_reason = ''
        # print final message & exit
        if exit_status == ST_OK:
            message = 'OK - ELB: %s. %s%s | %s' % (arguments['loadbalancer'],
                current_status, alert_reason, perf_data)
        elif exit_status == ST_WR:
            message = 'WARNING - ELB: %s. %s%s | %s' % (
                arguments['loadbalancer'], current_status, alert_reason,
                perf_data)
        elif exit_status == ST_CR:
            message = 'CRITICAL - ELB: %s. %s%s | %s' % (
                arguments['loadbalancer'], current_status, alert_reason,
                perf_data)
        else:
            message = 'UNKNOWN - ELB: %s. %s%s | %s' % (
                arguments['loadbalancer'], current_status, alert_reason,
                perf_data)
        exit_formalalities(message, exit_status=exit_status)
    except Exception as e:
        message = "Exception occured - %s" % e.message
        logger.critical("ELB health check: %s" % message)
        exit_formalalities(message, exit_status=ST_CR)


if __name__ == '__main__':
    logger.debug("ELB health check: Script started")
    run()
