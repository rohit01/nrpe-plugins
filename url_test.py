#!/usr/bin/env python
#
# Nagios custom NRPE plugin to monitor a website at regular intervals using
# python requests library
#

import requests
import sys
import time
from optparse import OptionParser
from requests.exceptions import HTTPError

# Nagios exit status values
ST_OK = 0
ST_WR = 1
ST_CR = 2
ST_UK = 3
# Global variables
exit_status = ST_OK
reason_for_service_down_list = None
MAX_RETRIES = 1
exception_occured = False

OPTIONS = {
    'H': "hostnames;URLs separated by comma to be tested",
    't': "timeout;Timeout for http connection in seconds. Default: 5",
}


def retry_for_network_exceptions(function, max_retries=MAX_RETRIES):
    def handled_function(*args, **kwargs):
        global exception_occured
        global exit_status
        result = None
        for i in xrange(max_retries):
            try:
                result = function(*args, **kwargs)
                break
            except Exception:
                # Not sure about exact exception
                exception_occured = True
                if exit_status == ST_OK:
                    exit_status = ST_WR
                time.sleep(1)
        return result
    return handled_function


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
    (options, args) = parser.parse_args()
    return options


def exit_formalalities(message, exit_status):
    print message
    sys.exit(exit_status)


def test_url(name, url, timeout=None):
    global exit_status
    global reason_for_service_down_list
    message = None
    response = requests.get(url, timeout=timeout)
    if response is None:
        message = 'Exception occured: %s (%s)' % (url, name)
        exit_status = ST_CR
    elif response.status_code != 200:
        message = 'Response status code: %s for URL: %s (%s)' \
            % (response.status_code, url, name)
        exit_status = ST_CR
    elif response.ok is not True:
        message = 'Response not ok for URL: %s (%s)' % (url, name)
        exit_status = ST_CR
    else:
        try:
            response.raise_for_status()
        except HTTPError:
            message = 'HTTPError occured for URL: %s (%s)' % (url, name)
            exit_status = ST_CR
    if message is not None:
        if reason_for_service_down_list is None:
            reason_for_service_down_list = []
        reason_for_service_down_list.append(message)

######################################################
################## Execute the Test ##################
######################################################

if __name__ == '__main__':
    requests.get = retry_for_network_exceptions(requests.get)
    # Adding exception handling descriptor
    arguments_passed = parse_options()
    hostnames = arguments_passed.hostnames
    if hostnames is None:
        print 'UNKNOWN - Mandatory option check_type (-t) not passed'
        sys.exit(ST_UK)
    timeout = arguments_passed.timeout
    if timeout is None:
        timeout = 5.0
    else:
        try:
            timeout = float(timeout)
        except ValueError:
            print 'UNKNOWN - Invalid value passed for timeout'
            sys.exit(ST_UK)

    name_list = []
    for url in hostnames.split(','):
        url = url.strip()
        if url == '':
            continue
        name = url
        name = name.replace('http://', '')
        name = name.replace('https://', '')
        name = name.split('/')[0]
        name_list.append(name)
        test_url(name, url, timeout=timeout)
    if reason_for_service_down_list is not None:
        message = '; '.join(reason_for_service_down_list)
        message = 'CRITICAL - %s' % message
        exit_formalalities(message, exit_status=exit_status)

    if exception_occured is True:
        exception_message = '[EXCEPTIONS OCCURED]'
    else:
        exception_message = ''
    message = ''

    if exit_status == ST_OK:
        message = 'OK - %s%s tested successfully' % (exception_message,
                                                     ', '.join(name_list))
    elif exit_status == ST_WR:
        message = 'WARNING - %s%s tested successfully with warnings' \
                  % (exception_message, ', '.join(name_list))
    elif exit_status == ST_CR:
        message = 'CRITICAL - %s%s test Failed' % (exception_message,
                                                   ', '.join(name_list))
    else:
        message = 'UNKNOWN - %s%s test unknown result' % (exception_message,
                                                          ', '.join(name_list))

    exit_formalalities(message, exit_status=exit_status)
