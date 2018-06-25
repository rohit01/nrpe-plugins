#!/usr/bin/env bash
#
# NRPE plugin to check kafka lag for new consumer groups
#

AUTHOR="Rohit Gupta - @rohit01"
PROGNAME=`basename $0`
VERSION="1.0"

## Global static variables
ST_OK=0
ST_WR=1
ST_CR=2
ST_UK=3
DEFAULT_KAFKA_HOME="/usr/local/kafka"
KAFKA_HOME="${DEFAULT_KAFKA_HOME}"
if [ -f /etc/default/kafka ]; then
    home="$(grep 'export KAFKA_HOME=' /etc/default/kafka | cut -d"=" -f 2 | sed 's/"//g')"
    if [ "${home}" != "" ]; then
        KAFKA_HOME="${home}"
    fi
fi

## Global Defaults
warning=50000
critical=150000
brokers=""
zookeeper=""
ctype="new"

print_version() {
    echo "$PROGNAME - version: $VERSION, author: $AUTHOR"
}

print_help() {
    echo "$PROGNAME is a NRPE plugin to check kafka lag for new consumer groups"
    echo ""
    echo "Usage: $PROGNAME -b <kafka brokers> -g <consumer group> -w <threshold> -c <threshold>"
    echo ""
    echo "Options:"
    echo "  -b/--brokers)"
    echo "    Kafka brokers server string (for new consumers). For eg: kafka1.local:9092,kafka2.local:9092"
    echo "  -z/--zookeeper)"
    echo "    Zookeeper string (for old consumers). For eg: zk1.local:2181,zk2.local:2181"
    echo "  -t/--topic)"
    echo "    Kafka topic (applicable only for old consumers)"
    echo "  -T/--ctype)"
    echo "    Kafka consumer type. Possible values: old & new. default: new"
    echo "  -g/--group)"
    echo "    Kafka consumer group name"
    echo "  -w/--warning)"
    echo "    Message lag for warning alert"
    echo "  -c/--critical)"
    echo "    Message lag for critical alert"
    echo "  -h/--help)"
    echo "     Print this help message & exit"
    echo "  -v/--version)"
    echo "     Print version of this script & exit"
    echo ""
    echo "Examples:"
    echo "   $PROGNAME -b kafka1:9092 -g my-group -w 50000 -c 80000"
}

#### Get command line arguments ###############################################
while test -n "$1"; do
    case "$1" in
        --brokers|-b)
            brokers=$2
            shift
            ;;
        --zookeeper|-z)
            zookeeper=$2
            shift
            ;;
        --ctype|-T)
            ctype=$2
            shift
            ;;
        --topic|-t)
            topic=$2
            shift
            ;;
        --group|-g)
            group=$2
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
        --help|-h)
            print_help
            exit "${ST_UK}"
            ;;
        --version|-v)
            print_version
            exit "${ST_UK}"
            ;;
        *)
            echo "Unknown argument: $1"
            echo ""
            print_help
            exit "${ST_UK}"
            ;;
        esac
    shift
done

#### Argument validations #####################################################
if [ "${ctype}" == "" ]; then
    echo "Argument Error: -t/--ctype missing"
    exit "${ST_UK}"
elif [ "${ctype}" != "old" ] && [ "${ctype}" != "new" ]; then
    echo "Invalid value '${ctype}' for argument -t/--ctype. Possible values are old & new"
    exit "${ST_UK}"
elif [ "${brokers}" == "" ] && [ "${ctype}" == "new" ]; then
    echo "Argument Error: -b/--brokers missing. Kafka consumer type is configured as 'new'"
    exit "${ST_UK}"
elif [ "${zookeeper}" == "" ] && [ "${ctype}" == "old" ]; then
    echo "Argument Error: -z/--zookeeper missing. Kafka consumer type is configured as 'old'"
    exit "${ST_UK}"
elif [ "${topic}" == "" ] && [ "${ctype}" == "old" ]; then
    echo "Argument Error: -t/--topic missing. Kafka consumer type is configured as 'old'"
    exit "${ST_UK}"
elif [ "${group}" == "" ]; then
    echo "Argument Error: -g/--group missing"
    exit "${ST_UK}"
elif [ "${warning}" == "" ]; then
    echo "Argument Error: -w/--warning missing"
    exit "${ST_UK}"
elif [ "${critical}" == "" ]; then
    echo "Argument Error: -c/--critical missing"
    exit "${ST_UK}"
elif echo "${warning}" | grep -v "^[0-9]*$"; then
    echo "Argument Error: -w/--warning must be a number, given: ${warning}"
    exit "${ST_UK}"
elif echo "${critical}" | grep -v "^[0-9]*$"; then
    echo "Argument Error: -c/--critical must be a number, given: ${critical}"
    exit "${ST_UK}"
elif [ "${warning}" -gt "${critical}" ]; then
    echo "Argument Error: value for warning (${warning}) must be less than or equal to critical (${critical})"
    exit "${ST_UK}"
fi

#### Function Definitions #####################################################
fetch_new_consumer_details() {
  # Argument: None
  # Returns:
  #   Kafka consumer details for the given consumer group

  "${KAFKA_HOME}/bin/kafka-consumer-groups.sh" \
    --new-consumer \
    --bootstrap-server "${brokers}" \
    --group "${group}" \
    --describe 2>/dev/null
}

fetch_old_consumer_details() {
  # Argument: None
  # Returns:
  #   Kafka consumer offset details for the given consumer group & topic

  if ! [ -f "${KAFKA_HOME}/bin/kafka-consumer-offset-checker.sh" ]; then
      KAFKA_HOME="${DEFAULT_KAFKA_HOME}"
  fi
  "${KAFKA_HOME}/bin/kafka-consumer-offset-checker.sh" \
    --group "${group}" \
    --topic "${topic}" \
    --zookeeper "${zookeeper}" 2>/dev/null
}

echo_details() {
    msg="${1}"
    if [ "${topic}" != "" ]; then
        msg="${msg}, topic '${topic}'"
    fi
    echo "${msg}, group '${group}'"
}

calculate_consumer_lag() {
  # Argument: consumer details
  #   <result from fetch_new_consumer_details or fetch_old_consumer_details function>
  # Returns:
  #   Sum of lag from all partitions

  expression=""
  if [ "${ctype}" == "new" ]; then
    expression="$(echo "$1" | grep -v -e "^TOPIC\s" -e "^Group\s" -e "is rebalancing" -e "^\s*$" | awk '{print $5}' | grep -v -e "^\s*$" -e "^\s*-[0-9]*\s*$" | tr "\n" "+" | sed 's/+$/\n/')"
  else
    expression="$(echo "$1" | grep -v -e "^TOPIC\s" -e "^Group\s" -e "is rebalancing" -e "^\s*$" | awk '{print $6}' | grep -v -e "^\s*$" -e "^\s*-[0-9]*\s*$" | tr "\n" "+" | sed 's/+$/\n/')"
  fi
  if [ "${expression}" == "" ]; then
    echo_details "WARNING- no numeric lag value found for lag calculation"
    exit "${ST_WR}"
  elif echo "${expression}" | grep -v "+"; then
    echo "${expression}"
  else
    echo "${expression}" | bc
  fi
}

#### EXECUTE CHECK ############################################################

if [ "${ctype}" == "new" ]; then
    c_details="$(fetch_new_consumer_details)"
    if [ $? != 0 ]; then
        echo_details "CRITICAL- kafka-consumer-groups.sh script returned non-zero exit status"
        exit "${ST_CR}"
    elif echo "${c_details}" | grep "^Error: Executing consumer group command failed due to Error reading field 'version': java.nio.BufferUnderflowException" >/dev/null; then
        echo_details "WARNING- fetch error. ${c_details}"
        exit "${ST_WR}"
    elif echo "${c_details}" | grep "^Error: " >/dev/null; then
        echo_details "CRITICAL- fetch error. ${c_details}"
        exit "${ST_CR}"
    fi
else
    c_details="$(fetch_old_consumer_details)"
    if [ $? != 0 ]; then
        echo_details "CRITICAL- kafka-consumer-offset-checker.sh script returned non-zero exit status"
        exit "${ST_CR}"
    elif echo "${c_details}" | grep "^Error: " >/dev/null; then
        echo_details "CRITICAL- fetch error. ${c_details}"
        exit "${ST_CR}"
    elif echo "${c_details}" | grep "^Exiting due to: Unable to connect to" >/dev/null; then
        echo_details "CRITICAL- fetch error. ${c_details}"
        exit "${ST_CR}"
    fi
fi

lag="$(calculate_consumer_lag "${c_details}")"
exit_status=$?
if ([ ${exit_status} == ${ST_CR} ] || [ ${exit_status} == ${ST_WR} ]) && [ "${lag}" != "" ]; then
    echo "${lag}"
    exit ${exit_status}
elif [ ${exit_status} != 0 ] || [ "${lag}" == "" ]; then
    echo_details "CRITICAL- error while calculating consumer lag"
    exit "${ST_CR}"
fi

if [ "${lag}" -ge "${critical}" ]; then
    echo_details "CRITICAL- kafka consumer lag is ${lag} (> ${critical})"
    exit "${ST_CR}"
elif [ "${lag}" -ge "${warning}" ]; then
    echo_details "WARNING- kafka consumer lag is ${lag} (> ${warning})"
    exit "${ST_WR}"
else
    echo_details "OK- kafka consumer lag is ${lag}"
    exit "${ST_OK}"
fi
