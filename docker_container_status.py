#!/usr/bin/env python
#
# NRPE plugin to monitor running docker containers. Requires: docker-py
# Author: Rohit Gupta - @rohit01
#

import docker
import os
import sys
import optparse
import datetime


__version__ = 0.1
VERSION = "Version: %s, Author: Rohit Gupta - @rohit01" % __version__
DESCRIPTION = "NRPE plugin to monitor running docker containers. Requires:" \
    " docker-py"
OPTIONS = {
    "image_name": "Docker image name",
}
USAGE = "%s [options]"  % os.path.basename(__file__)

# NRPE exit status variables
ST_OK = 0
ST_WR = 1
ST_CR = 2
ST_UK = 3


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


def validate_arguments(arguments):
    for keyname in arguments.keys():
        if arguments[keyname] is None:
            print "Mandatory argument missing: --%s" % keyname
            sys.exit(ST_UK)


def get_container_ids(arguments):
    dclient = docker.Client()
    container_list = dclient.containers()
    container_ids = []
    for container_details in container_list:
        image_prefix = "%s:" % arguments['image_name']
        if container_details['Image'].startswith(image_prefix):
            container_ids.append(container_details['Id'])
    return container_ids


def print_container_summary(container_ids):
    dclient = docker.Client()
    container_time_info = {}
    for cid in container_ids:
        details = dclient.inspect_container(cid)
        iso_time = details['Created'].split('.')[0]
        create_time = datetime.datetime.strptime(iso_time, "%Y-%m-%dT%H:%M:%S")
        container_time_info[cid] = create_time
    no_of_containers = len(container_time_info)
    last_create_time = None
    for ctime in container_time_info.values():
        if not last_create_time:
            last_create_time = ctime
        elif ctime > last_create_time:
            last_create_time = ctime
    if no_of_containers <= 0:
        print "CRITICAL: No running containers | containers=0"
        sys.exit(ST_CR)
    elif no_of_containers == 1:
        relative_time = pretty_date(last_create_time)
        print "OK: %s running container, started: %s | containers=%s" \
            % (no_of_containers, relative_time, no_of_containers)
    else:
        relative_time = pretty_date(last_create_time)
        print "OK: %s running containers, newest one started: %s | " \
            "containers=%s" % (no_of_containers, relative_time, no_of_containers)


def pretty_date(time_object=False):
    """
    Get a datetime object or a int() Epoch timestamp and return a
    pretty string like 'an hour ago', 'Yesterday', '3 months ago',
    'just now', etc
    """
    now = datetime.datetime.utcnow()
    if type(time_object) is int:
        diff = now - datetime.datetime.fromtimestamp(time_object)
    elif isinstance(time_object, datetime.datetime):
        diff = now - time_object
    elif not time_object:
        return ''
    second_diff = diff.seconds
    day_diff = diff.days
    if day_diff < 0:
        return ''
    if day_diff == 0:
        if second_diff < 10:
            return "just now"
        if second_diff < 60:
            return str(second_diff) + " seconds ago"
        if second_diff < 120:
            return "a minute ago"
        if second_diff < 3600:
            return str(second_diff / 60) + " minutes ago"
        if second_diff < 7200:
            return "an hour ago"
        if second_diff < 86400:
            return str(second_diff / 3600) + " hours ago"
    if day_diff == 1:
        return "Yesterday"
    if day_diff < 7:
        return str(day_diff) + " days ago"
    if day_diff < 31:
        return str(day_diff / 7) + " weeks ago"
    if day_diff < 365:
        return str(day_diff / 30) + " months ago"
    return str(day_diff / 365) + " years ago"


def run():
    arguments = parse_options(OPTIONS, DESCRIPTION, USAGE, VERSION)
    validate_arguments(arguments)
    try:
        container_ids = get_container_ids(arguments)
        print_container_summary(container_ids)
    except Exception as e:
        print "Exception occured: %s" % e.message
        sys.exit(ST_CR)


if __name__ == '__main__':
    run()
