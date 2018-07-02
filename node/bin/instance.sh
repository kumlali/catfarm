#!/bin/bash
# ------------------------------------------------------------------------------
# WARNING: This file might be overriden while deployment.
# ------------------------------------------------------------------------------
# Manages single Tomcat server(instance). 
#
# Note: Domain might have multiple nodes and each node might have multiple 
# Tomcat instances.
# ------------------------------------------------------------------------------



# ------------------------------------------------------------------------------
# Moves the instance's log files to ${CONF_APP_HOME}/logs/archive/${INSTANCE_NAME}/YYYYMMDD/HHMM 
# directory, if it is not running.
# ------------------------------------------------------------------------------
archiveLogs () {
  
  if [[ `isAlive` = "true" ]]; then
    log "The instance is running. Logs cannot be archived while the instance is running."
    exit 1
  fi

  local current_date=`date +"%Y%m%d"`
  local current_time=`date +"%H%M"`
  local archive_dir=${CONF_APP_HOME}/logs/archive/${INSTANCE_NAME}/${current_date}/${current_time}
  mkdir -m 755 -p ${archive_dir}

  local instance_logs_dir=${INSTANCE_HOME}/logs
  if [ ! -d ${instance_logs_dir} ]; then
    log "'${instance_logs_dir}' directory does not exist. Installation of '${INSTANCE_HOME}' might not be completed."
    exit 1
  fi

  local file_count=$(ls -1 ${instance_logs_dir}/* 2>/dev/null | wc -l)
  if [ ${file_count} != 0 ]; then
    log "Archiving log files under '${instance_logs_dir}' to '${archive_dir}' ..."

    # Move all the files (not directories) under ${INSTANCE_HOME}/logs to archive
    # directory.
    find ${instance_logs_dir}/* -maxdepth 1 -type f -exec mv {} ${archive_dir} \; 2>/dev/null

    # Grant 755 to archived log files. This is especially necessary for 
    # heap dump (*.hprof) files.
    chmod -R 755 ${archive_dir}

    log "Log files under '${instance_logs_dir}' have been archived to '${archive_dir}'."

  fi

}


# ------------------------------------------------------------------------------
# Returns process id of the instance.
# ------------------------------------------------------------------------------
getProcessId () {

  local process_id=`ps -eF | grep instanceName=${INSTANCE_NAME} | grep -vw grep | awk '{print $2}'`
  echo "$process_id"

}


exportTomcatVariables () {

  # ----------------------------------------------------------------------
  # Extract instance id from instance name
  # ----------------------------------------------------------------------
  # Instance id is a number. By combining application name with instance id, we
  # produce instance name. Therefore, instance names become unique, as well as
  # instance ids. We can obtain instance id from instance name:
  #
  #   INSTANCE_NAME -> CONF_APP_NAME & INSTANCE_ID (e.g. myapp1 -> myapp & 1)
  #
  local instance_id=`echo ${INSTANCE_NAME} | sed -e "s/${CONF_APP_NAME}//g"`

  # ----------------------------------------------------------------------
  # Generate http, https and shutdown ports of Tomcat
  # ----------------------------------------------------------------------
  # Three ports are used for each instance: http, https and shutdown.
  # Port numbers are generated automatically by using $CONF_BASE_PORT and
  # instance id(extracted from instance name).
  #
  # For example, if CONF_APP_NAME is myapp and CONCONF_BASE_PORT is 8000 then;
  #  - instance myapp1's http port is 8001, shutdown port is 8002, https port is 8003.
  #  - instance myapp2's http port is 8004, shutdown port is 8005, https port is 8006.
  #  - ...
  local http_port=`expr $CONF_BASE_PORT + $instance_id \* 3 - 2`
  local shutdown_port=`expr $CONF_BASE_PORT + $instance_id \* 3 - 1`
  local https_port=`expr $CONF_BASE_PORT + $instance_id \* 3`

  # ----------------------------------------------------------------------
  # Set JAVA_OPTS by adding JVM vendor specific arguments to it. JAVA_OPTS
  # is used while starting and stopping the instance.
  # ----------------------------------------------------------------------
  # from catalina.sh:
  #
  #   JAVA_OPTS       (Optional) Java runtime options used when any command
  #                   is executed.
  #                   Include here and not in CATALINA_OPTS all options, that
  #                   should be used by Tomcat and also by the stop process,
  #                   the version command etc.
  #                   Most options should go into CATALINA_OPTS. 
  #
  #   CATALINA_OPTS   (Optional) Java runtime options used when the "start",
  #                   "run" or "debug" command is executed.
  #                   Include here and not in JAVA_OPTS all options, that should
  #                   only be used by Tomcat itself, not by the stop process,
  #                   the version command etc.
  #                   Examples are heap size, GC logging, JMX ports etc.
  #
  JAVA_OPTS="$JAVA_OPTS \
    -server \
    -showversion \
    -Djava.awt.headless=true \
    -Dhttps.protocols=TLSv1.1,TLSv1.2 \
    -DhttpPort=${http_port} \
    -DhttpsPort=${https_port} \
    -DshutdownPort=${shutdown_port} \
    -Djavax.net.ssl.trustStore=${CONF_JVM_PARAM_TRUST_STORE} \
    -Djavax.net.ssl.trustStorePassword=${CONF_JVM_PARAM_TRUST_STORE_PASS} \
    -Djavax.net.ssl.keyStore=${CONF_JVM_PARAM_KEY_STORE} \
    -Djavax.net.ssl.keyStorePassword=${CONF_JVM_PARAM_KEY_STORE_PASS}"

  # Java vendor specific definitions

  local java_vendor=`getJavaVendor`
  case "${java_vendor}" in

    *HotSpot*) # Oracle/Sun/HP
      JAVA_OPTS="$JAVA_OPTS \
        -XX:+HeapDumpOnOutOfMemoryError \
        -XX:HeapDumpPath=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.java_pid.hprof \
        -XX:ErrorFile=${INSTANCE_HOME}/logs/${INSTANCE_NAME}/hs_err_pid.log \
        -XX:-UseSplitVerifier \
        -verbose:gc -Xloggc:${INSTANCE_HOME}/logs/${INSTANCE_NAME}.gc.log \
        -Djava.security.egd=file:/dev/./urandom"
        ;;

    *IBM*) # IBM
      JAVA_OPTS="$JAVA_OPTS -verbose:gc \
        -Xverbosegclog:${INSTANCE_HOME}/logs/verbosegc.%Y%m%d.%H%M%S.%pid.txt,20,10000"
          
      # Set the directory under which javadump/javacore/thread dump file 
      # is created. These parameters are unique to IBM JVM and does not work
      # on other JVMs.
      export IBM_HEAPDUMP="TRUE"
      export IBM_HEAPDUMP_OUTOFMEMORY="TRUE"
      export IBM_HEAPDUMPDIR="${INSTANCE_HOME}/logs"
      export IBM_JAVADUMP_OUTOFMEMORY="TRUE"
      export IBM_JAVACOREDIR="${INSTANCE_HOME}/logs"
      export IBM_COREDIR="${INSTANCE_HOME}/logs"
      ;;

    *OpenJDK*) # OpenJDK
      JAVA_OPTS="$JAVA_OPTS \
        -XX:+HeapDumpOnOutOfMemoryError \
        -XX:HeapDumpPath=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.java_pid.hprof \
        -XX:ErrorFile=${INSTANCE_HOME}/logs/${INSTANCE_NAME}/hs_err_pid.log \
        -XX:-UseSplitVerifier \
        -verbose:gc -Xloggc:${INSTANCE_HOME}/logs/${INSTANCE_NAME}.gc.log \
        -Djava.security.egd=file:/dev/./urandom"
        ;;

    *)
      log "Unsupported Java vendor is detected: ${java_vendor}. Supported vendors are: HotSpot, IBM, OpenJDK."
      exit 1
      ;;
  esac

  # ----------------------------------------------------------------------
  # Set CATALINA_OPTS. It is "only" used while starting the instance.
  # ----------------------------------------------------------------------
  CATALINA_OPTS="${CATALINA_OPTS} -DinstanceName=${INSTANCE_NAME} \
    ${CONF_JVM_PARAM_MEMORY} \
    ${CONF_JVM_PARAM_THREAD} \
    ${CONF_JVM_PARAM_APP_ARGS}"

  # ----------------------------------------------------------------------
  # Set CATALINA_PID that is required while server shutdown.
  # ----------------------------------------------------------------------
  CATALINA_PID="${INSTANCE_HOME}/logs/${INSTANCE_NAME}.pid"

  # ----------------------------------------------------------------------
  # Set CLASSPATH
  #
  # Because CLASSPATH variable is unset in catalina.sh, setting and
  # exporting it before starting Tomcat does not work. Tomcat suggests 
  # us to set CLASSPATH variable in setenv.sh, if necessary. Please read
  # comments in catalina.sh and see setenv.sh.
  # ----------------------------------------------------------------------
  # CLASSPATH="${CLASSPATH}:${CONF_APP_HOME}/conf/CLASSPATH"

  export JAVA_HOME JAVA_OPTS CATALINA_OPTS CATALINA_PID CONF_APP_HOME

}


printEnvironmentVariables () {

  echo "----------------------------------------------------------------"
  echo "Configuration"
  echo "----------------------------------------------------------------"
  echo "CATALINA_OPTS                :"
  printArguments "${CATALINA_OPTS}"
  echo "CONF_APP_CLASSPATH           : ${CONF_APP_CLASSPATH}"
  echo "CONF_APP_NAME                : ${CONF_APP_NAME}"
  echo "CONF_APP_HOME                : ${CONF_APP_HOME}"
  echo "CONF_BASE_PORT               : ${CONF_BASE_PORT}"
  echo "CONF_DOMAIN_NAME             : ${CONF_DOMAIN_NAME}"
  echo "CONF_JAVA_HOME               : ${CONF_JAVA_HOME}"
  echo "CONF_JVM_PARAM_APP_ARGS      : ${CONF_JVM_PARAM_APP_ARGS}"
  echo "CONF_JVM_PARAM_MEMORY        : ${CONF_JVM_PARAM_MEMORY}"
  echo "CONF_JVM_PARAM_THREAD        : ${CONF_JVM_PARAM_THREAD}"
  echo "CONF_JVM_PARAM_KEY_STORE     : ${CONF_JVM_PARAM_KEY_STORE}"
  echo "CONF_JVM_PARAM_TRUST_STORE   : ${CONF_JVM_PARAM_TRUST_STORE}"
  echo "CONF_NODE_INSTANCES          :"
  printNodeAndInstances
  echo "CONF_SHUTDOWN_TIMEOUT_SECONDS: ${CONF_SHUTDOWN_TIMEOUT_SECONDS}"
  echo "CONF_STARTUP_FAILURE_MSG     : ${CONF_STARTUP_FAILURE_MSG}"
  echo "CONF_STARTUP_TIMEOUT_SECONDS : ${CONF_STARTUP_TIMEOUT_SECONDS}"
  echo "CONF_WAIT_INTERVAL_SECONDS   : ${CONF_WAIT_INTERVAL_SECONDS}"
  echo "CONF_SERIAL_DOMAIN_OPERATI...: ${CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS}"
  echo "INSTANCE_HOME                : ${INSTANCE_HOME}"
  echo "INSTANCE_NAME                : ${INSTANCE_NAME}"
  echo "JAVA_HOME                    : ${JAVA_HOME}"
  echo "JAVA_OPTS                    :"
  printArguments "${JAVA_OPTS}"
  echo "NODE_NAME                    : ${NODE_NAME}"
  echo "PATH                         : ${PATH}"

}


# ------------------------------------------------------------------------------
# Returns 'true' if the instance is running and 'false' otherwise.
# ------------------------------------------------------------------------------
isAlive () {

  if [[ `getProcessId` != "" ]]; then
    echo "true"
  else
    echo "false"
  fi 

}


# ------------------------------------------------------------------------------
# Logs status of the instance (running or not).
# ------------------------------------------------------------------------------
status () {

  log "${INSTANCE_NAME} - Running: `isAlive`"

}


# ------------------------------------------------------------------------------
# Deletes the instance's log files if it is not running.
# ------------------------------------------------------------------------------
deleteLogs () {

  if [[ `isAlive` = "true" ]]; then
    log "The instance is running. Logs cannot be deleted while it is running."
    exit 1
  fi

  rm -v ${INSTANCE_HOME}/logs/*.* 2>/dev/null

}


# ------------------------------------------------------------------------------
# Archives the instance's logs, then starts it.
#
# It neither blocks nor checks for failures while the instance is starting up.
# ------------------------------------------------------------------------------
start () {

  if [[ `isAlive` = "true" ]]; then
    log "The instance is already running. This step (starting instance) will be skipped."
    exit 1
  fi

  if [ ! -d ${INSTANCE_HOME} ]; then
    log "The instance does not exist at '${INSTANCE_HOME}' directory. \
         \nYou can create it by issuing './instance.sh ${INSTANCE_NAME} create' command."
    exit 1
  else
    archiveLogs
  fi

  local startOut=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.start.out

  # We need to export some varibles before starting and stopping Tomcat.
  exportTomcatVariables

  printEnvironmentVariables > $startOut

  ${INSTANCE_HOME}/bin/catalina.sh start >> $startOut 2>&1

  log "The instance is starting..."

  # wait till catalina.out is created
  while [ ! -f ${INSTANCE_HOME}/logs/catalina.out ]
  do
    sleep 1
  done

}


# ------------------------------------------------------------------------------
# Fails with error message and exits if it finds out CONF_STARTUP_FAILURE_MSG 
# message in instance's log file.
# ------------------------------------------------------------------------------
failOnError () {

  local log_file=${INSTANCE_HOME}/logs/catalina.out
  local error_lines=$(sed -n '/'"${CONF_STARTUP_FAILURE_MSG}"'/,$p' ${log_file} | head -100)
  if [ -n "${error_lines}" ]; then
    log "\n----------------------------------------------------------------------\
         \nERROR\
         \n----------------------------------------------------------------------\
         \n${error_lines}"
    stop
    exit 1
  fi

}


# ------------------------------------------------------------------------------
# Archives the instance's logs, then starts it. It blocks until the instance 
# has been started successfully or an error occurs:
#  * if there is CONF_STARTUP_FAILURE_MSG in log file OR
#  * if CONF_STARTUP_TIMEOUT_SECONDS is exceeded.
# ------------------------------------------------------------------------------
startVerify () {

  start

  local log_file=${INSTANCE_HOME}/logs/catalina.out  
  if [ ! -e "${log_file}" ]; then
    log "\n----------------------------------------------------------------------\
         \nERROR\
         \n----------------------------------------------------------------------\
         \nStarting operation is canceled since '${log_file}' does not exist.\
         \n\nFor more information please have a look at '${INSTANCE_NAME}.start.out'."
    exit 1
  fi

  local elapsed_time=0
  
  while [ $(grep -c "${CONF_STARTUP_SUCCESS_MSG}" ${log_file}) = 0 ] && \
        [ ${elapsed_time} -lt ${CONF_STARTUP_TIMEOUT_SECONDS} ] ; do
    sleep ${CONF_WAIT_INTERVAL_SECONDS}
    local elapsed_time=$(expr ${elapsed_time} + ${CONF_WAIT_INTERVAL_SECONDS})
    log "The instance has been starting for $elapsed_time seconds. Please wait..."
    failOnError
  done

  if [ ${elapsed_time} -ge ${CONF_STARTUP_TIMEOUT_SECONDS} ] ; then
    log "\n----------------------------------------------------------------------\
         \nERROR\
         \n----------------------------------------------------------------------\
         \nStarting operation is canceled since expected startup time\
         \n(${CONF_STARTUP_TIMEOUT_SECONDS} sec) has been exceeded.\
         \n\nPlease check the logs."
    stop
    exit 1
  else
    log "The instance has been started."
  fi

}


# ------------------------------------------------------------------------------
# Stops the instance. Process is killed if it does not stop in 
# CONF_SHUTDOWN_TIMEOUT_SECONDS seconds.
# ------------------------------------------------------------------------------ 
stop () {
  
  if [[ `isAlive` = "false" ]]; then
    log "The instance is not running. This step (stopping the instance) will be skipped."
    return 0
  fi

  # We need to export some varibles before starting and stopping Tomcat.
  exportTomcatVariables

  log "The instance is stopping..."
  ${INSTANCE_HOME}/bin/catalina.sh stop ${CONF_SHUTDOWN_TIMEOUT_SECONDS} -force > ${INSTANCE_HOME}/logs/${INSTANCE_NAME}.stop.out 2>&1
  
  if [[ `isAlive` = "true" ]]; then    
    log "Because the instance could not be stopped in ${CONF_SHUTDOWN_TIMEOUT_SECONDS} seconds, its process will be killed."
    local process_id=$(getProcessId)
    if [[ $process_id != "" ]]; then
      kill -9 $process_id
    fi  
    log "The instance has been stopped by killing process $process_id."
  else
    log "The instance has been stopped."
  fi
 
}


# ------------------------------------------------------------------------------
# Stops and then starts the instance.
# ------------------------------------------------------------------------------
restart () {

  stop
  start

}


# ------------------------------------------------------------------------------
# Stops and then starts the instance. It blocks until the instance has been 
# started successfully or an error occurs:
#  * if CONF_STARTUP_FAILURE_MSG is found in log file OR
#  * if CONF_STARTUP_TIMEOUT_SECONDS is exceeded.
# ------------------------------------------------------------------------------
restartVerify () {

  stop
  startVerify

}


# ------------------------------------------------------------------------------
# Opens the instance's catalina.out log file with 'less' command.
# ------------------------------------------------------------------------------
showLog () {

  less ${INSTANCE_HOME}/logs/catalina.out

}


# ------------------------------------------------------------------------------
# Follows instance's catalina.out log file. Ctrl+C can be used to exit.
# ------------------------------------------------------------------------------
tailLog () {
  
  tail -f ${INSTANCE_HOME}/logs/catalina.out
  
}


# ------------------------------------------------------------------------------
# Takes thread dump from instance's JVM.
# ------------------------------------------------------------------------------
takeThreadDump () {
  
  local process_id=`getProcessId`
  if [[ $process_id != "" ]]; then
    kill -3 $process_id
    log "Thread dump file has been created in '${INSTANCE_HOME}/logs' directory."
  else
    echo "Thread dump could not be generated as the instance is not running."
  fi  

}


# ------------------------------------------------------------------------------
# Starts to record memory usage data of the instance to 
# ${INSTANCE_HOME}/logs/${INSTANCE_NAME}.memusage.out
#  
# When IBM JDK is used, Garbage Collection and Memory Visualizer (GCMV) can
# load these data to view and analyze the native memory usage. For more
# information please see https://goo.gl/Mw63D9.
# ------------------------------------------------------------------------------
startMemUsageRecording () {

  local process_id=`getProcessId`
  logFile=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.memusage.out

  nohup ${CONF_APP_HOME}/bin/memusage.sh $process_id memUsageId=$process_id >> $logFile 2>&1 &

  log "Recording of memory usage data has been started. See $logFile file."

}


# ------------------------------------------------------------------------------
# Stops to record memory usage data of the instance.
# ------------------------------------------------------------------------------
stopMemUsageRecording () {

  local process_id=`getProcessId`
  logFile=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.memusage.out

  local mem_usage_process_id=`ps -eF | grep memUsageId=${process_id} | grep -vw grep | awk '{print $2}'`
  kill -9 $mem_usage_process_id

  log "Recording of memory usage data has been stopped. See $logFile file."

}


# ------------------------------------------------------------------------------
# Deploys 'instance.zip' and 'app.zip', if the instance is not running.
#
# 'app.zip' contains applications(*.war files) while 'instance.zip' contains
# Tomcat configuration.
# 
# Normally, there is no need to stop Tomcat while deploying the applications. 
# However, OutOfMemoryError errors would occur after several deployments.
# Because there will be no interruption when at least two instances are running,
# it should not be a problem stopping one of them while deployment.
#
# Following steps are performed:
# - For each application in 'app.zip', it deletes 'app_name' (e.g. myapp01) 
#   directory under 'webapps' directory then copies application's war file 
#   to 'webapps'.
# - Deletes cached files under 'work' directory (some applications need this)
# - Extracts ${CONF_APP_HOME}/deploy/latest/instance.zip to instance's home 
#   directory.
# ------------------------------------------------------------------------------
deploy () {

  if [[ `isAlive` = "true" ]]; then
    log "Deployment cannot be done while the instance is running."
    exit 1
  fi

  local app_pack=${CONF_APP_HOME}/deploy/latest/app.zip
  if [ ! -f "${app_pack}" ]; then
    log "${app_pack} does not exist. Deployment has been canceled."
    exit 1
  fi


  # Undeploy and deploy all the applications

  log "Starting to deploy applications in '${app_pack}'..."

  # Handle each *.war file in 'app.zip independently'
  for i in `unzip -Z -1 ${app_pack} | grep .war`
  do
    app_file=${i}
    app_file_name="${app_file%.*}"
    app_file_ext="${app_file##*.}"

    log "Starting to deploy '${app_file}' ..."

    # Remove application's extracted directory from previous deployment if exists
    local deploy_dir=${INSTANCE_HOME}/webapps/${app_file_name}
    if [ -d "${deploy_dir}" ]; then
      rm -rf ${deploy_dir}
    fi

    # Deploy application's war file. It overrides the old one if exists.
    unzip -oj "${app_pack}" "${app_file}" -d "${INSTANCE_HOME}/webapps"

    log "'${app_file}' has been deployed."

    # Delete cached files and directories
    local cache_dir=${INSTANCE_HOME}/work/Catalina/localhost/${app_file_name}
    log "Starting to delete cached files and directories under '${cache_dir}'. Some applications need this..."
    if [ -d "${cache_dir}" ]; then
      rm -rf ${cache_dir}
    fi
    log "Cached files and directories under '${cache_dir}' have been deleted."
  done
  log "Applications in '${app_pack}' have been deployed."


  # Override old instance configuration files with new ones.

  local instance_pack=${CONF_APP_HOME}/deploy/latest/instance.zip
  if [ ! -f "${instance_pack}" ]; then
    log "'${instance_pack}' does not exist. Deployment has been canceled."
    exit 1
  else
    log "Starting to deploy '${instance_pack}' ..."

    unzip -o ${instance_pack} -d ${INSTANCE_HOME}

    # If ${INSTANCE_HOME}/bin/setenv.sh file exists, make sure its permission is 755
    chmod 755 ${INSTANCE_HOME}/bin/setenv.sh 2>/dev/null

    log "'${instance_pack}' has been deployed."
  fi

}


# ------------------------------------------------------------------------------
# Creates (but does not start) an instance on the current node, if it does not 
# already exist on any nodes and its name conforms to ${CONF_APP_NAME}<number> 
# pattern. (e.g. myapp01, myapp17, etc.)
#
# WARNING: After the instance has been created, its name must be added to 
#          'farm.conf' file on all the nodes. Instance components must be 
#          deployed before starting the instance, as well.
# ------------------------------------------------------------------------------
create () {

  if [[ ${INSTANCE_NAME} == ${CONF_APP_NAME}* ]]; then # INSTANCE_NAME starts with CONF_APP_NAME
    suffix="${INSTANCE_NAME#*${CONF_APP_NAME}}"
    if [ -z "${suffix##*[!0-9]*}" ]; then # suffix is NOT numeric
      log "Invalid instance name: ${INSTANCE_NAME} \
           \nInstance name must conform to: ${CONF_APP_NAME}<number> (e.g. ${CONF_APP_NAME}1, ${CONF_APP_NAME}2, ...)"
      exit 1
    fi
  fi

  if [ -d ${INSTANCE_HOME} ]; then
    log "Home directory of '${INSTANCE_NAME}' instance already exists: '${INSTANCE_HOME}'"
    exit 1
  fi

  local node_of_instance=`getNodeOfInstance ${INSTANCE_NAME}`
  if [[ "${node_of_instance}" != "" && "${node_of_instance}" != "${NODE_NAME}" ]] ; then
    log "'${INSTANCE_NAME}' instance is not attached to this host('${NODE_NAME}')\
         \nin 'farm.conf'. It is attached to node '${node_of_instance}' instead. \
         \n\nHint: You should either update 'farm.conf' or issue command './instance.sh ${INSTANCE_NAME} ${command}' on node '${node_of_instance}'."
    exit 1
  fi

  local template_dir=${CONF_APP_HOME}/instances/template
  if [ ! -d ${template_dir} ] || [ -z "$(ls -A ${template_dir})" ]; then # directory does not exist or is empty
    log "The instance can not be created as there is no Tomcat template at \
         \n'${template_dir}' directory. Please extract Tomcat tar.gz \
         \npackage(e.g. apache-tomcat-7.0.34.tar.gz) to '${template_dir}.'"
    exit 1
  fi

  if [ ! -d "${JAVA_HOME}" ]; then
    log "'${JAVA_HOME}' directory does not exist. Please fix JAVA_HOME"
    log "environment variable."
    exit 1
  fi

  log "The instance is being created..."

  # Copy template directory to ${INSTANCE_HOME}
  cp -r ${template_dir} ${INSTANCE_HOME}

  # If not exist, create a symbolic link in logs directory that references to 
  # instance's logs directory.
  if [ ! -L ${CONF_APP_HOME}/logs/${INSTANCE_NAME} ]; then 
    mkdir -p ${CONF_APP_HOME}/logs    
    ln -s ${INSTANCE_HOME}/logs ${CONF_APP_HOME}/logs/${INSTANCE_NAME}
  fi

  log "The instance has been created, but not started. Before starting it up, please;\
       \n - add '${INSTANCE_NAME}' to '${NODE_NAME}' in 'CONF_NODE_INSTANCES' variable of 'farm.conf' on all the nodes,\
       \n - deploy 'app.zip' and 'instance.zip' by executing './instance.sh ${INSTANCE_NAME} deploy' command."

}


# ------------------------------------------------------------------------------
# Deletes the instance on the current node, if it exists and does not run.
#
# It also deletes the symbolic link in 'logs' directory which references to the
# instance's log directory.
# ------------------------------------------------------------------------------
delete () {

  if [[ `isAlive` = "true" ]]; then
    log "The instance cannot be deleted while it is running."
    exit 1
  fi

  log "The instance is being deleted..."

  if [ -d ${INSTANCE_HOME} ]; then
    rm -rf ${INSTANCE_HOME}
    log "The instance's home ('${INSTANCE_HOME}') has been deleted."
  else
    log "Home directory of the instance does not exist: '${INSTANCE_HOME}'"
  fi

  # If exists, delete the symbolic link in 'logs' directory that references to 
  # instance's 'logs' directory.
  if [ -L ${CONF_APP_HOME}/logs/${INSTANCE_NAME} ]; then 
    rm ${CONF_APP_HOME}/logs/${INSTANCE_NAME}
    log "'${CONF_APP_HOME}/logs/${INSTANCE_NAME}' symbolic link has been deleted."
  else
    log "'${CONF_APP_HOME}/logs/${INSTANCE_NAME}' symbolic link does not exist."
  fi

  log "\n\nThe instance has been deleted. Please remove '${INSTANCE_NAME}' from\
       \n'${NODE_NAME}' in 'CONF_NODE_INSTANCES' variable of 'farm.conf'\
       \non all the nodes."

}


usage () {

  log "\n----------------------------------------------------------------\
  \nUsage \
  \n---------------------------------------------------------------- \
  \n\n./instance.sh <instance_name> <command> \
  \n\nCommands: \
  \n\n  archive-logs            : Archives the instance's log files if it is not running. \
  \n\n  create                  : Creates (but does not start) an instance on the current node, \
  \n                            if it does not already exist on any nodes and its name conforms to \
  \n                            ${CONF_APP_NAME}<number> pattern. (e.g. myapp01, myapp17, etc.) \
  \n\n  delete                  : Deletes the instance on the current node, if it exists and does not run. \
  \n\n  delete-logs             : Deletes the instance's log files if it is not running. \
  \n\n  deploy                  : Deploys 'instance.zip' and 'app.zip', if the instance is not running. \
  \n\n  take-thread-dump        : Takes thread dump from instance's JVM. \
  \n\n  is-alive                : Returns 'true' if the instance is running and 'false' otherwise. \
  \n\n  restart                 : Stops and then starts the instance. \
  \n\n  restart-verify          : Stops and then starts the instance. It blocks until the instance \
  \n                            has been started successfully or an error occurs. \
  \n\n  show-log                : Opens the instance's 'catalina.out' log file with 'less' command. \
  \n\n  start                   : Archives the instance's logs, then starts it. It neither blocks nor \
  \n                            checks for failures while the instance is starting up. \
  \n\n  start-memusage-recording: Starts to record memory usage data of the instance. \
  \n\n  start-verify            : Archives the instance's logs, then starts it. It blocks until \
  \n                            the instance has been started successfully or an error occurs. \
  \n\n  status                  : Logs status of the instance (running or not). \
  \n\n  stop                    : Stops the instance. Process is killed if it does not stop in \
  \n                            ${CONF_SHUTDOWN_TIMEOUT_SECONDS} seconds. \
  \n\n  stop-memusage-recording : Stops to record memory usage data of the instance. \
  \n\n  tail-log                : Follows the instance's 'catalina.out' log file. Ctrl+C can be \
  \n                            used to exit. \
  \n\nExamples:  \
  \n\n  ./instance.sh ${CONF_APP_NAME}1 start-verify \
  \n  ./instance.sh ${CONF_APP_NAME}1 stop \
  \n  ./instance.sh ${CONF_APP_NAME}1 deploy \
  \n  ./instance.sh ${CONF_APP_NAME}1 restart"

}


# ------------------------------------------------------------------------------
# Makes initialization.
# ------------------------------------------------------------------------------
# Parameters:
#   $1: instance name (required)
#   $2: command (required)
# ------------------------------------------------------------------------------
initialize () {

  local absolute_path_of_this_file=${0}
  local dir_of_this_file=`dirname $absolute_path_of_this_file`
  local base_sh="${dir_of_this_file}/base.sh"
  if [ ! -f "${base_sh}" ]; then
    echo "'${base_sh}' file does not exist."
    exit 1
  fi

  . ${base_sh}

  INSTANCE_NAME=${1}
  local command=${2}

  if [[ "$INSTANCE_NAME" = "" || "$command" = "" ]] ; then
    log "Instance name and command must be entered."
    usage
    exit 1
  fi

  INSTANCE_HOME=${CONF_APP_HOME}/instances/${INSTANCE_NAME}

  # Set locale to English/United State UTF-8. If this setting is OK for
  # the application, then there is no need to use JVM arguments such as
  # -Duser.language=en.
  export LC_ALL=en_US.UTF-8

  # Set permissions of directories and files created by Tomcat process.
  # Grant 755 to directories and 644 to files.
  umask 022


  if [[ ${command} != "create" ]] ; then

    local nodeOfInstance=`getNodeOfInstance ${INSTANCE_NAME}`
    if [[ "${nodeOfInstance}" = "" ]] ; then
      log "'${INSTANCE_NAME}' instance does not defined in 'farm.conf'."
      exit 1
    fi

    if [[ "${nodeOfInstance}" != "${NODE_NAME}" ]] ; then
      log "'${INSTANCE_NAME}' instance is not attached to this host('${NODE_NAME}')\
           \nin 'farm.conf'. It is attached to '${nodeOfInstance}' node instead. \
           \n'./instance.sh ${INSTANCE_NAME} ${command}' command can only be executed on '${nodeOfInstance}' node."
      exit 1
    fi

    if [ ! -d ${INSTANCE_HOME} ]; then
      log "Although instance '${INSTANCE_NAME}' definition exists in configuration\
           \nfile('farm.conf'), its home directory('${INSTANCE_HOME}') does not\
           \nexist. \
           \n\nYou can create it by issuing the './instance.sh ${INSTANCE_NAME} create' command."
      exit 1
    fi

  fi

  if [[ "$command" = "archive-logs" ]] ; then
    archiveLogs
  elif [[ "$command" = "create" ]] ; then
    create
  elif [[ "$command" = "delete" ]] ; then
    delete
  elif [[ "$command" = "delete-logs" ]] ; then
    deleteLogs
  elif [[ "$command" = "deploy" ]] ; then
    deploy
  elif [[ "$command" = "is-alive" ]] ; then
    isAlive
  elif [[ "$command" = "restart" ]] ; then
    restart
  elif [[ "$command" = "restart-verify" ]] ; then
    restartVerify
  elif [[ "$command" = "show-log" ]] ; then
    showLog
  elif [[ "$command" = "start" ]] ; then
    start
  elif [[ "$command" = "start-memusage-recording" ]] ; then
    startMemUsageRecording
  elif [[ "$command" = "start-verify" ]] ; then
    startVerify
  elif [[ "$command" = "status" ]] ; then
    status
  elif [[ "$command" = "stop" ]] ; then
    stop
  elif [[ "$command" = "stop-memusage-recording" ]] ; then
    stopMemUsageRecording
  elif [[ "$command" = "tail-log" ]] ; then
    tailLog
  elif [[ "$command" = "take-thread-dump" ]] ; then
    takeThreadDump
  else
    log "Unknown command: $command"
    usage
    exit 1
  fi

}


# ------------------------------------------------------------------------------
# The script starts here.
# ------------------------------------------------------------------------------
initialize $1 $2