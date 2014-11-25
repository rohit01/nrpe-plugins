#!/usr/bin/env python
#
# Description: Utility for sending email notifications using Amazon SES
# Author: Rohit Gupta - @rohit01
#

import optparse
import jinja2
import time
import os
import sys
import boto.ses
import random
import logging
import logging.handlers


__version__ = 0.1
VERSION = """Version: %s, Author: Rohit Gupta - @rohit01""" % __version__
DESCRIPTION = """Utility for sending email notifications using Amazon SES
Note: This utility is does not handle exceptions generated due to invalid data
"""
OPTIONS = {
    # Credentials
    "aws_region": "Comma separated AWS region names for using SES service." \
        " Used for loadbalancer(random) and failover. Default: us-east-1",
    "aws_access_key_id": "AWS access key",
    "aws_secret_access_key": "AWS secret key",
    # Email Settings
    "notification_for": "Host or Service",
    "to": "To email address",
    "from_address": "From email address",
    "reply_to": "reply-to email address",
    # Shinken data
    "attempt_no": "Host/service check attempt number",
    "duration": "Duration of current state",
    "full_message": "Host/service check full output",
    "host_address": "Host address",
    "host_alias": "Host alias",
    "host_group": "Hostgroup name",
    "host_group_names": "Current host hostgroup names",
    "host_name": "Host Name",
    "host_private_address": "Host private ip, if configured",
    "last_check": "Last check epoc timestamp",
    "long_date_time": "Date time in long format",
    "max_attempt": "Max check attempt",
    "message": "First line of check output",
    "notification_type": "Notification type",
    "percent_changes": "Percent change indicating state change frequency",
    "scheduled_downtime": "A number indicating the  depth of current downtime",
    "service_name": "Service check name",
    "state": "Current state/status",
    "state_type": "Hard or Soft state",
}
USAGE = "%s [options]"  % os.path.basename(__file__)

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
# Logging in syslog (/var/log/syslog)
handler = logging.handlers.SysLogHandler(address='/dev/log')
logger.addHandler(handler)


def parse_options(options, description=None, usage=None, version=None):
    parser = optparse.OptionParser(description=description, usage=usage,
                                   version=version)
    for keyname, description in options.items():
        longopt = '--%s' % keyname
        parser.add_option(longopt, dest=keyname, help=description)
    option_args, _ = parser.parse_args()
    arguments = {}
    for keyname in options.keys():
        arguments[keyname] = eval("option_args.%s" % keyname)
    return arguments


def generate_subject_and_body(arguments):
    data = arguments.copy()
    # Remove credentials before rendering template
    data.pop('aws_region')
    data.pop('aws_access_key_id')
    data.pop('aws_secret_access_key')
    manipulate_data(data)
    # Load Template
    abs_path = os.path.abspath(__file__)
    abs_path_dir = os.path.sep.join(abs_path.split(os.path.sep)[:-1])
    template_file = "%s/templates/%s.j2" % (abs_path_dir, arguments.get('notification_for', None))
    with open(template_file, 'r') as f:
        # The first line is subject
        subject_template = f.readline().strip()
        # Rest is body
        body_template = f.read().strip()
    # Render Template
    template = jinja2.Template(subject_template)
    subject = template.render(**data)
    template = jinja2.Template(body_template)
    body = template.render(**data)
    return (subject, body)


def manipulate_data(data):
    if data.get("to", None):
        data["name"] = data["to"].split('@')[0].title()
    if data.get("last_check", None):
        data["last_check"] = int(time.time() - float(data["last_check"]))
    scheduled_downtime = data.get('scheduled_downtime', 0)
    if scheduled_downtime:
        data['scheduled_downtime'] = "Yes. %s seconds inside downtime window" \
                                     % scheduled_downtime
    else:
        data["scheduled_downtime"] = "No"
    if data.get("full_message", None):
        data["full_message"] = "%s\n%s" % (data["message"], data["full_message"])
    else:
        data["full_message"] = data["message"]
    if data.get("percent_changes", None):
        data["percent_changes"] = round(float(data["percent_changes"]), 2)
    for k, v in data.items():
        if k:
            data[k] = str(data[k]).strip()
        else:
            data[k] = '-'


def select_region(aws_region, blacklist = []):
    if not aws_region:
        aws_region = 'us-east-1'
    region_list = [i.strip() for i in aws_region.split(',') if i.strip()]
    if not region_list:
        region_list = ['us-east-1']
    for region in blacklist:
        try:
            while True:
                region_list.remove(region)
        except ValueError:
            pass
    if not region_list:
        return None
    return region_list[random.randint(0, len(region_list) - 1)]


def send_email(arguments, subject, body):
    aws_region = arguments.get('aws_region')
    failed_regions = []
    while True:
        selected_region = select_region(aws_region, blacklist=failed_regions)
        if not selected_region:
            raise Exception("Cannot send email. All regions failed")
        aws_access_key_id = arguments.get('aws_access_key_id', None)
        aws_secret_access_key = arguments.get('aws_secret_access_key', None)
        if (not aws_access_key_id) or (not aws_secret_access_key):
            raise Exception("AWS credentials not passed in arguments")
        from_address = arguments.get('from_address', None)
        if not from_address:
            raise Exception("Source email address not defined")
        to_addresses = [add for add in arguments.get('to', '').split(',') if add.strip()]
        if not to_addresses:
            raise Exception("No destination specified")
        reply_addresses = arguments.get('reply_to', None)
        if not reply_addresses:
            reply_addresses = None
        try:
            conn = boto.ses.connect_to_region(
                selected_region,
                aws_access_key_id=aws_access_key_id,
                aws_secret_access_key=aws_secret_access_key,
            )
            conn.send_email(from_address, subject, body, to_addresses, 
                            reply_addresses=reply_addresses)
        except Exception as e:
            logger.warning("AWS_SES_EMAIL: Email failed using region '%s',"
                " trying another AWS SES region. Exception: %s"
                % (selected_region, e.message))
            failed_regions.append(selected_region)
            continue
        break


def run():
    try:
        arguments = parse_options(OPTIONS, DESCRIPTION, USAGE, VERSION)
        subject, body = generate_subject_and_body(arguments)
        send_email(arguments, subject, body)
        logger.info("AWS_SES_EMAIL: Email sent to '%s'. Subject: %s"
                    % (arguments.get('to', '-'), subject))
    except Exception as e:
        logger.critical("AWS_SES_EMAIL: %s. Arguments passed: %s"
                        % (e.message, arguments))
        print e.message
        sys.exit(1)


if __name__ == '__main__':
    logger.debug("AWS_SES_EMAIL: Script started")
    run()
