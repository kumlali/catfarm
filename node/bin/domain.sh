#!/bin/bash
# ------------------------------------------------------------------------------
# WARNING: This file might be overriden while deployment.
# ------------------------------------------------------------------------------
# Manages all the Tomcat instances(servers) on all the machines(nodes).
#
# Note: A domain might have multiple nodes(machines) and each node might have
# multiple Tomcat instances.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Returns "true" if the given node is on the current machine and "false" 
# otherwise.
#
# Parameters:
#   $1: node name (required)
# ------------------------------------------------------------------------------
isNodeOnThisMachine () {

  node=$1
  if [[ "${node}" = "" ]] ; then 
    log "node parameter must be entered."
    return 1
  fi

  case ${node} in
    ${NODE_NAME}*) echo "true"
                        ;;
                     *) echo "false"
                        ;;
  esac

}


# ------------------------------------------------------------------------------
# Executes given command and its argument(if exists) on given node. Node can 
# be on the current host or the remote host.
#
# Parameters:
#   $1: node name (required)
#   $2: command (required)
#   $3: argument
# ------------------------------------------------------------------------------
executeOnNode () {

  node=${1}
  command=${2}
  arg=${3}

  if [[ "${node}" = "" || "${command}" = "" ]] ; then
    log "At least node and command parameters must be entered."
    return 1
  fi

  if [[ `isNodeOnThisMachine ${node}` = "true" ]] ; then
    ${CONF_APP_HOME}/bin/node.sh $command $arg
  else
    ssh ${node} ${CONF_APP_HOME}/bin/node.sh $command $arg
  fi

}


# ------------------------------------------------------------------------------
# Executes given command and its argument(if exists) on all the nodes. After the
# command is executed on a node, it is executed on the next node in delaySec
# seconds.
#
# Parameters:
#   $1: command (required)
#   $2: argument
#   $3: delaySec
# ------------------------------------------------------------------------------
executeOnNodes () {

  # Validation for the arguments is already handled by executeOnNode
  local command=${1}
  local arg=${2}
  local delaySec=${3}

  # If only one node exists, no need to loop and wait for 
  # next(unexisting) node.
  if [[ ${#NODES[@]} = "1" ]]; then
    executeOnNode ${NODES[0]} $command $arg
  else
    for (( i = 0; i < ${#NODES[@]} ; i++ ))
    do
      executeOnNode ${NODES[i]} $command $arg
      result=$?
      if [[ $result = "0" ]]; then
        log "'${command}' command has been executed on node '${NODES[i]}'."
        if [[ $delaySec != "" ]]; then
          if [[ `expr ${i} + 1` < ${#NODES[@]} ]]; then # next node exists
            log "'${command}' command will be executed on the next node in '${delaySec}' seconds..."
            sleep $delaySec
          fi
        fi
      else
        return 1
      fi
    done
  fi

}


# ------------------------------------------------------------------------------
# Executes given command and its argument(if exists) on all the nodes
# parallelly, waits till all the executions are completed, either
# successfully or unsuccessfully.
#
# Parameters:
#   $1: command (required)
#   $2: argument
# ------------------------------------------------------------------------------
executeOnNodesParallelly () {

  # Validation for the arguments is already handled by executeOnNode
  local command=${1}
  local arg=${2}

  local pids=""
  for (( i = 0; i < ${#NODES[@]} ; i++ ))
  do
    ( executeOnNode ${NODES[i]} $command $arg ) &
    pids="$pids $!"
  done 

  waitAll $pids

}


# ------------------------------------------------------------------------------
# Returns "true" if at least one instance on the given node is running, returns
# "false" otherwise.
# ------------------------------------------------------------------------------
isNodeAlive () {

  # Validation for the arguments is already handled by executeOnNode
  node=${1}

  echo `executeOnNode ${node} "is-alive"`

}


# ------------------------------------------------------------------------------
# Returns "true" if at least one node is alive, returns "false" otherwise.
# A node is supposed to be alive if at least one instance of it is running.
# ------------------------------------------------------------------------------
isDomainAlive () {

  result="false"
  for (( i = 0; i < ${#NODES[@]} ; i++ ))
  do
    node=${NODES[i]}
    if [[ `executeOnNode ${node} "is-alive"` = "true" ]] ; then
      result="true"
      break
    fi
  done

  echo $result

}


# ------------------------------------------------------------------------------
# Issues 'start' command for all the instances on all the nodes parallelly and 
# completes immediately. It does not check if instances start up successfully.
# 
# WARNING: Because execution is handled parallelly, some instances can be
# running while some others are not.
# ------------------------------------------------------------------------------
start () {

  executeOnNodesParallelly "start"

}


# ------------------------------------------------------------------------------
# Starts all the instances on all the nodes parallelly. It blocks until all the 
# instances start successfully or one of them fails to start.
# 
# WARNING: Because execution is handled parallelly, some instances can be
# running while some others are not.
# ------------------------------------------------------------------------------
startVerify () {

  executeOnNodesParallelly "start-verify"

}


# ------------------------------------------------------------------------------
# Stops all the instances on all the nodes parallelly.
# ------------------------------------------------------------------------------
stop () {

  executeOnNodesParallelly "stop"

}


# ------------------------------------------------------------------------------
# Stops and starts all the instances on all the nodes parallelly. It neither
# blocks nor checks for failures while the instances are starting up.
# ------------------------------------------------------------------------------
restart () {

  executeOnNodesParallelly "restart"

}


# ------------------------------------------------------------------------------
# Stops, starts and verifies all the instances on all the nodes parallelly.
# It blocks until all the instances start successfully or one of them fails 
# to start.
# ------------------------------------------------------------------------------
restartVerify () {

  executeOnNodesParallelly "restart-verify"

}


# ------------------------------------------------------------------------------
# Stops, starts and verifies all the instances on a node parallelly then passes
# to the next node for the same operation. It does pass to the next node before
# all the instances of the current node are not running.
#
# When the operation is completed on a node, it is started on the next one after
# CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS seconds have been elapsed.
# This behaviour allows load balancer to recognize the node is alive again
# before the next one is getting down.
#
# Here are the steps:
# - Stop node1 (Stop all the instaces on node1 parallelly)
# - Start node1 (Start all the instaces on node1 parallely)
# - Verify whether each instance is running successfully
# - Wait CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS
# - Repeat these steps for the next nodes
# ------------------------------------------------------------------------------
restartHA () {

  executeOnNodes "restart-verify" "" $CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS

}


# ------------------------------------------------------------------------------
# Deploys 'node.zip' to the node, then deploys 'app.zip' and 'instance.zip' to 
# all the instances of the node parallelly. These operations are executed on 
# the nodes parallelly.
# ------------------------------------------------------------------------------
deploy () {

  executeOnNodesParallelly "deploy"

}


# ------------------------------------------------------------------------------
# Deploys 'node.zip' to the node, then deploys 'app.zip' and 'instance.zip' to 
# all the instances of the node parallelly. Then, passes to the next node for 
# the same operation.
#
# When the deployment is completed on a node, it is started on the next one after
# CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS seconds have been elapsed.
# This behaviour allows load balancer to recognize the node is alive again,
# before the next one is getting down.
#
# Here are the steps:
# - Stop node1 (Stop all the instaces on node1 parallelly)
# - Deploy everyting (node components, configuration of each instance, 
#   applications to each instance etc.)
# - Start node1 (Start all the instaces on node1 parallely)
# - Verify whether each instance is running successfully
# - Wait CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS
# - Repeat these steps for the next nodes
# ------------------------------------------------------------------------------
deployHA () {

  # If only one node exists, no need to loop and wait for 
  # next(unexisting) node.
  if [[ ${#NODES[@]} = "1" ]]; then
    executeOnNode ${NODES[0]} stop
    executeOnNode ${NODES[0]} deploy
    executeOnNode ${NODES[0]} start-verify
  else
    for (( i = 0; i < ${#NODES[@]} ; i++ ))
    do
      local delaySec=${CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS}
      executeOnNode ${NODES[i]} stop
      executeOnNode ${NODES[i]} deploy
      executeOnNode ${NODES[i]} start-verify
      result=$?
      if [[ $result = "0" ]]; then
        log "Deployment has been completed on node '${NODES[i]}'"
        if [[ "$delaySec" != "" ]]; then
          if [[ `expr ${i} + 1` < ${#NODES[@]} ]]; then # next node exists
            log "Deployment will be started on the next node in $delaySec seconds..."
            sleep $delaySec
          fi
        fi
      else
        return 1
      fi
    done
  fi

}


# ------------------------------------------------------------------------------
# Moves latest deployment artifacts('app.zip', 'node.zip' and 'instance.zip') 
# under deployment directory(latest) to archive on all the nodes parallelly.
# ------------------------------------------------------------------------------
archive () {

  executeOnNodesParallelly "archive"

}


# ------------------------------------------------------------------------------
# Moves archived deployment artifacts('app.zip', 'node.zip' and 'instance.zip') 
# under 'previous' directory to deployment directory (latest) on all the nodes. 
# To deploy them, you need to execute 'deploy' command.
# ------------------------------------------------------------------------------
restore () {

  executeOnNodesParallelly "restore"

}


# ------------------------------------------------------------------------------
# Logs status of each instance on each node (running or not).
# ------------------------------------------------------------------------------
status () {

  log "-----------------------------------------------------"
  log "Status of ${CONF_DOMAIN_NAME}"
  log "-----------------------------------------------------"

  executeOnNodes "status"

}


usage () {

  log "\n----------------------------------------------------------------\
  \nUsage \
  \n---------------------------------------------------------------- \
  \n\n./domain.sh <command> \
  \n\nCommands: \
  \n\n  archive       : Moves latest deployment artifacts('app.zip', 'node.zip' and \
  \n                  'instance.zip') under deployment directory(latest) to archive \
  \n                  on all the nodes parallelly. \
  \n\n  deploy        : Deploys 'node.zip' to the node, then deploys 'app.zip' and \
  \n                  'instance.zip' to all the instances of the node parallelly. \
  \n                  These operations are executed on the nodes parallelly. \
  \n\n  deploy-ha     : Deploys 'node.zip' to the node, then deploys 'app.zip' and \
  \n                  'instance.zip' to all the instances of the node parallelly. \
  \n                  These operations are executed on all the nodes sequentially. \
  \n                  To achive this, it deploys applications and artifacts on a \
  \n                  node, waits for a while, then passes to the next node for \
  \n                  the same operation. Therefore, there will be no service\
  \n                  interruption. \
  \n\n  is-alive      : Returns 'true' if at least one instance on either node is \
  \n                  running, returns 'false' otherwise. \
  \n\n  restart       : Restarts all the instances on all the nodes parallelly. It \
  \n                  neither blocks nor checks for failures while the instances \
  \n                  are starting up.\
  \n\n  restart-ha    : Restarts and verifies all the instances on a node parallelly, \
  \n                  waits for a while, then passes to the next node for the same \
  \n                  operation. Therefore, there will be no service interruption. \
  \n\n  restart-verify: Restarts and verifies all the instances on all the nodes \
  \n                  parallelly. It blocks until all the instances start successfully \
  \n                  or one of them fails to start.\
  \n\n  restore       : Moves archived deployment artifacts('app.zip', 'node.zip' and \
  \n                  'instance.zip') under 'previous' directory to deployment \
  \n                  directory (latest) on all the nodes. To deploy them, you \
  \n                  need to execute 'deploy' command. \
  \n\n  start         : Starts all the instances on all the nodes parallelly. It neither \
  \n                  blocks nor checks for failures while the instances are starting up. \
  \n\n  start-verify  : Starts all the instances on all the nodes parallelly. It blocks \
  \n                  until all the instances start successfully or one of them fails \
  \n                  to start. \
  \n\n  status        : Logs status of each instance on each node (running or not). \
  \n\n  stop          : Stops all the instances on all the nodes parallelly. If it does \
  \n                  not complete in ${CONF_SHUTDOWN_TIMEOUT_SECONDS} seconds, the \
  \n                  processes are killed. \
  \n\n\nExamples: \
  \n\n  ./domain.sh start-verify\
  \n  ./domain.sh stop \
  \n  ./domain.sh restart-ha \
  \n  ./domain.sh deploy"

}


# ------------------------------------------------------------------------------
# Makes initialization.
# ------------------------------------------------------------------------------
# Parameters:
#   $1: command (required)
# ------------------------------------------------------------------------------
initialize () {

  local absolute_path_of_this_file=${0}
  local dir_of_this_file=`dirname $absolute_path_of_this_file`
  local base_sh="${dir_of_this_file}/base.sh"
  if [ ! -f "${base_sh}" ]; then
    log "'${base_sh}' file does not exist."
    exit 1
  fi

  . ${base_sh}

  local command=${1}
  if [[ "${command}" = "" ]] ; then
    log "A command must be entered."
    usage
    exit 1
  fi

  NODES=($(getNodes))
  if [[ "${NODES}" = "" ]] ; then
    log "No node definition found in 'CONF_NODE_INSTANCES' variable of 'farm.conf'."
    exit 1
  fi

  if [[ "$command" = "archive" ]] ; then
    archive
  elif [[ "$command" = "deploy" ]] ; then
    deploy
  elif [[ "$command" = "deploy-ha" ]] ; then
    deployHA
  elif [[ "$command" = "is-alive" ]] ; then
    isDomainAlive
  elif [[ "$command" = "restart" ]] ; then
    restart
  elif [[ "$command" = "restart-ha" ]] ; then
    restartHA
  elif [[ "$command" = "restart-verify" ]] ; then
    restartVerify
  elif [[ "$command" = "restore" ]] ; then
    restore
  elif [[ "$command" =  "start" ]] ; then
    start
  elif [[ "$command" =  "start-verify" ]] ; then
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