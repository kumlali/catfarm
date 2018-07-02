#!/bin/bash
# ------------------------------------------------------------------------------
# WARNING: This file might be overriden while deployment.
# ------------------------------------------------------------------------------
# Manages all the Tomcat servers(instances) on the current machine(node).
#
# Note: Domain might have multiple nodes and each node might have multiple
# Tomcat instances.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Executes given command and its argument(if exists) for the given instance.
#
# Parameters:
#   $1: instance (required)
#   $2: command (required)
#   $3: argument
# ------------------------------------------------------------------------------
executeOnInstance () {

  # Validation for the arguments is already handled by instance.sh
  local instance=${1}
  local command=${2}
  local arg=${3}

  ${CONF_APP_HOME}/bin/instance.sh $instance $command $arg

}


# ------------------------------------------------------------------------------
# Executes given command and its argument(if exists) for an instance, and after
# it completes, does the same thing for the next one. Repeats these steps for
# all the instances of the node.
#
# Parameters:
#   $1: command (required)
#   $2: argument
# ------------------------------------------------------------------------------
executeOnInstances () {

  # Validation for the arguments is already handled by executeOnInstance
  local command=${1}
  local arg=${2}

  for instance in "${INSTANCES[@]}"
  do
    executeOnInstance $instance $command $arg
  done

}


# ------------------------------------------------------------------------------
# Executes given command and its argument(if exists) for all the instances
# of the node parallelly, waits till all the executions are completed, either
# successfully or unsuccessfully.
#
# Parameters:
#   $1: command (required)
#   $2: argument
# ------------------------------------------------------------------------------
executeOnInstancesParallelly () {

  # Validation for the arguments is already handled by executeOnInstance
  local command=${1}
  local arg=${2}

  local pids=""
  for instance in "${INSTANCES[@]}"
  do
    (executeOnInstance $instance $command $arg) &
    pids="$pids $!"
  done

  waitAll $pids

}


# ------------------------------------------------------------------------------
# Returns "true" if instance is running and "false" otherwise.
#
# Parameters:
#   $1: instance name (required)
# ------------------------------------------------------------------------------
isInstanceAlive () {

  # Validation for the arguments is already handled by executeOnInstance
  local instance=$1

  executeOnInstance $instance "is-alive"

}


# ------------------------------------------------------------------------------
# Returns "true" if at least one instance on the node is running, returns
# "false" otherwise.
# ------------------------------------------------------------------------------
isNodeAlive () {

  result="false"
  for instance in "${INSTANCES[@]}"
  do
    if [[ `isInstanceAlive ${instance}` = "true" ]] ; then
      result="true"
      break
    fi
  done

  echo $result

}


# ------------------------------------------------------------------------------
# Moves latest deployment artifacts('app.zip', 'node.zip' and 'instance.zip') in 
# ${CONF_APP_HOME}/deploy/latest to ${CONF_APP_HOME}/deploy/previous directory.
# ------------------------------------------------------------------------------
archive () {

  local latest_dir="${CONF_APP_HOME}/deploy/latest"
  local previous_dir="${CONF_APP_HOME}/deploy/previous"

  log "Archiving latest deployment artifacts('app.zip', 'node.zip' and 'instance.zip') under '${latest_dir}' to '${previous_dir}' ..."

  if [ ! -d ${latest_dir} ]; then
    log "'${latest_dir}' directory does not exist. Archiving has been canceled."
    exit 1
  fi

  rm -rf ${previous_dir}
  mv -v ${latest_dir} ${previous_dir}
  mkdir -p ${latest_dir}

  log "Deployment artifacts under '${latest_dir}' have been archived to '${previous_dir}' directory."

}


# ------------------------------------------------------------------------------
# Moves previous deployment artifacts('app.zip', 'node.zip' and 'instance.zip')
# in ${CONF_APP_HOME}/deploy/previous to ${CONF_APP_HOME}/deploy/latest
# directory.
# ------------------------------------------------------------------------------
restore () {

  local latest_dir="${CONF_APP_HOME}/deploy/latest"
  local previous_dir="${CONF_APP_HOME}/deploy/previous"

  log "Restoring archived deployment artifacts('app.zip', 'node.zip' and 'instance.zip') under '${previous_dir}' to '${latest_dir}' ..."

  if [ ! -d ${previous_dir} ]; then
    log "${previous_dir} directory does not exist. Restoring has been canceled."
    exit 1
  fi

  rm -rf ${latest_dir}
  mv -v ${previous_dir} ${latest_dir}
  mkdir -p ${previous_dir}

  log "Archived deployment artifacts under '${previous_dir}' have been restored to '${latest_dir}' directory."

}


# ------------------------------------------------------------------------------
# Deploys 'node.zip' to the node, then deploys 'app.zip' and 'instance.zip' to 
# all the instances of the node parallelly.
#
# 'node.zip' contains applications' configuration files, farm configuration,
# keystore, truststore and management scripts.
#
# 'app.zip' contains applications(*.war files).
#
# 'instance.zip' contains Tomcat configuration.
#
# All the instances must be stopped before deployment.
# ------------------------------------------------------------------------------
deploy () {

  if [[ `isNodeAlive` = "true" ]] ; then
    log "At least one instance on the node is running. Deployment has been canceled."
    exit 1
  fi

  # Deploy node components
  local node_pack=${CONF_APP_HOME}/deploy/latest/node.zip
  if [ ! -f "${node_pack}" ]; then
    log "${node_pack} does not exist. Deployment has been canceled."
    exit 1
  else
    unzip -o ${CONF_APP_HOME}/deploy/latest/node.zip -x "bin/*" -d ${CONF_APP_HOME}
  fi
  log "Node components in ${node_pack} have been deployed.\
       \n\nPlease note that ${CONF_APP_HOME}/bin has not been overriden. If you\
       \nneed to upgrade scripts by overriding them with the ones in 'bin' \
       \ndirectory of 'node.zip', please issue following command:\
       \n\n'unzip -o ${CONF_APP_HOME}/deploy/latest/node.zip bin/* -d ${CONF_APP_HOME}'
       \n"

  # Deploy instance components
  executeOnInstancesParallelly "deploy"

}


# ------------------------------------------------------------------------------
# Restarts an instance, and after it completes, does the same thing for the next
# one. Repeats these steps for all the instances of the node.
# ------------------------------------------------------------------------------
restart () {

  executeOnInstances "restart"

}


# ------------------------------------------------------------------------------
# Stops and starts all the instances on the node one by one. It does 
# not stop next instance before the current one starts successfully.
#
# Here are the steps:
# - Stop instance1
# - Start instance1
# - Verify whether instance1 is running successfully
# - Repeat these steps for instance2, instance3, ...
# ------------------------------------------------------------------------------
restartHA () {

  executeOnInstances "restart-verify"

}


# ------------------------------------------------------------------------------
# Restarts and verifies all the instances on the node parallelly.
# ------------------------------------------------------------------------------
restartVerify () {

  executeOnInstancesParallelly "restart-verify"

}


start () {

  executeOnInstancesParallelly "start"

}


startVerify () {

  executeOnInstancesParallelly "start-verify"

}


# ------------------------------------------------------------------------------
# Stops all the instances on the node parallelly. If it does not complete in 
# ${CONF_SHUTDOWN_TIMEOUT_SECONDS} seconds, the processes are killed.
# ------------------------------------------------------------------------------
stop () {

  executeOnInstancesParallelly "stop"

}


status () {

  executeOnInstances "status"

}


usage () {

  log "\n----------------------------------------------------------------\
  \nUsage \
  \n---------------------------------------------------------------- \
  \n\n./node.sh <command> \
  \n\nCommands: \
  \n\n  archive       : Moves latest deployment artifacts('app.zip', 'node.zip' and \
  \n                  'instance.zip') under deployment directory(latest) to archive . \
  \n\n  deploy        : Deploys 'node.zip' to the node, then deploys 'app.zip' and \
  \n                  'instance.zip' to all the instances of the node parallelly. \
  \n\n  is-alive      : Returns 'true' if at least one instance on the node is running, \
  \n                  returns 'false' otherwise. \
  \n\n  restart       : Restarts all the instances of the node parallelly. \
  \n\n  restart-ha    : Stops and starts all the instances on the node one by one. \
  \n                  It does not stop next instance before the current one starts \
  \n                  successfully. \
  \n\n  restart-verify: Restarts all the instances of the node parallelly. It blocks \
  \n                  until all the instances start successfully or one of them \
  \n                  fails to start. \
  \n\n  restore       : Moves archived deployment artifacts('app.zip', 'node.zip' and \
  \n                  'instance.zip') under 'previous' directory to deployment \
  \n                  directory (latest). To deploy them, you need to execute 'deploy' \
  \n                  command. \
  \n\n  start         : Starts all the instances on the node parallelly. It neither \
  \n                  blocks nor checks for failures while the instances are starting up. \
  \n\n  start-verify  : Starts all the instances of the node parallelly. It blocks until \
  \n                  all the instances start successfully or one of them fails to start. \
  \n\n  status        : Logs status of each instance on the node (running or not). \
  \n\n  stop          : Stops all the instances on the node parallelly. If it does not \
  \n                  complete in ${CONF_SHUTDOWN_TIMEOUT_SECONDS} seconds, the processes are killed. \
  \n\n\nExamples: \
  \n\n  ./node.sh start-verify\
  \n  ./node.sh stop \
  \n  ./node.sh restart-ha \
  \n  ./node.sh deploy"

}


# ------------------------------------------------------------------------------
# Makes initialization.
# ------------------------------------------------------------------------------
# Parameters:
#   $1: command (required)
# ------------------------------------------------------------------------------
initialize () {

  set -e

  local absolute_path_of_this_file=${0}
  local dir_of_this_file=`dirname $absolute_path_of_this_file`
  local base_sh="${dir_of_this_file}/base.sh"
  if [ ! -f "${base_sh}" ]; then
    echo "'${base_sh}' file does not exist."
    exit 1
  fi

  . ${base_sh}

  local command=${1}
  if [[ "${command}" = "" ]] ; then
    log "A command must be entered."
    usage
    exit 1
  fi

  INSTANCES=($(getInstances "${NODE_NAME}"))
  if [[ "${INSTANCES}" = "" ]] ; then
    log "No instance definition found for '${NODE_NAME}' node in 'farm.conf'."
    exit 1
  fi

  if [[ "$command" = "archive" ]] ; then
    archive
  elif [[ "$command" = "deploy" ]] ; then
    deploy
  elif [[ "$command" = "is-alive" ]] ; then
    isNodeAlive
  elif [[ "$command" = "restart" ]] ; then
    restart
  elif [[ "$command" = "restart-ha" ]] ; then
    restartHA
  elif [[ "$command" = "restart-verify" ]] ; then
    restartVerify
  elif [[ "$command" = "restore" ]] ; then
    restore
  elif [[ "$command" = "start" ]] ; then
    start
  elif [[ "$command" = "start-verify" ]] ; then
    startVerify
  elif [[ "$command" = "status" ]] ; then
    status
  elif [[ "$command" = "stop" ]] ; then
    stop
  else
    log "Unknown command: $command"
    usage
    exit 1
  fi

}


# ------------------------------------------------------------------------------
# The script starts here.
# ------------------------------------------------------------------------------
initialize $1