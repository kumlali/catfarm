#!/bin/bash
# ------------------------------------------------------------------------------
# WARNING: This file might be overriden while deployment.
# ------------------------------------------------------------------------------


log () {

  printf "[${CONF_DOMAIN_NAME}:${NODE_NAME}:${INSTANCE_NAME}] $1\n" >&2

}


# ------------------------------------------------------------------------------
# Returns zero if all background processes are successfull and returns
# non-zero otherwise. wait command does not have this feature.
#
# Further info: https://goo.gl/8uwU1Y
# ------------------------------------------------------------------------------
waitAll () {

  ## Wait for children to exit and indicate whether all exited with 0 status.
  local errors=0
  while :; do
    for pid in "$@"; do
      shift
      if kill -0 "$pid" 2>/dev/null; then
        set -- "$@" "$pid"
      elif wait "$pid"; then
        doNothing=true
      else
        ((++errors))
      fi
    done
    (("$#" > 0)) || break
    sleep 1
  done

  ((errors == 0))
}


# ------------------------------------------------------------------------------
# Returns the value of given variable. It is usefull when the variable 
# name itself is dynamic. For example:
#
# ...
# node="machine1"
# memSize=$(getVarValue "CONF_${node}_MEMSIZE")
#
# node="machine2"
# memSize=$(getVarValue "CONF_${node}_MEMSIZE")
# ... 
#
# ------------------------------------------------------------------------------
getVarValue () {

  local varName=$1
  local varValue=$(eval echo \$$varName)
  echo $varValue

}


checkExistanceAndCopyFile () {

  local srcFile=$1
  local targetFile=$2
  
  if [ ! -e "${srcFile}" ]; then
    log "$srcFile file does not exist."
    exit 1
  fi
  
  cp -v ${srcFile} ${targetFile}

  log "${srcFile} file has been copied to ${targetFile}."
  
}


# ------------------------------------------------------------------------------
# Replaces a string with another in given file
#
# Parameters:
#   file: File to be updated
#   src: Source string
#   target: Target string
# ------------------------------------------------------------------------------
replaceEntry () {
  
  local file=$1
  local src=$2
  local target=$3

  sed "s/$src/$target/g" $file > $file.tmp
  mv -v $file.tmp $file

}


# ------------------------------------------------------------------------------
# Updates value of given key in configuration file.
#
# Parameters:
#   key
#   newValue
# ------------------------------------------------------------------------------
updateConfEntry () {

  local key=$1
  local newValue=$2

  sed "s/$key=.*/$key=$newValue/g" $CONF_FILE > $CONF_FILE.tmp
  mv -v $CONF_FILE.tmp $CONF_FILE

}


# ------------------------------------------------------------------------------
# Returns true if string contains substring and false otherwise.
#
# Parameters:
#   $1: string
#   $2: substring
# ------------------------------------------------------------------------------
isSubstringFoundInString () {
  
  case "$1" in
      *$2*) echo "true" ;;
       *) echo "false" ;;
  esac
  
}


# ------------------------------------------------------------------------------
# Splits a string into substrings by using a delimiter.
#
# Function result can directly be used in 'for ... in' loops:
#
#   itemList="i1,i2,i3"
#   items=$(split "$itemList" ",")
#   for item in $items
#   do
#     echo "item: $item"
#   done 
# 
# If items shall be directly read from the result, an array
# must be created by simply putting it between '(' and ')':
#
#   itemList="i1,i2,i3"
#   # extra parantheses
#   items=($(split "$itemList" ","))
#   echo "item1: ${items[0]}"
#   echo "item2: ${items[1]}"
#
# Parameters:
#   $1: str (*): String to split 
#   $2: delimiter (*): Delimiter 
# ------------------------------------------------------------------------------
split () {
  
  local str=$1
  local delimiter=$2
  
  echo $str | tr $delimiter " "
}


getJavaVersion () {
  ${JAVA_HOME}/bin/java -version 2>&1 | awk 'NR==1{ gsub(/"/,""); print substr($3,1,3)}'
}


getJavaVendor () {
  ${JAVA_HOME}/bin/java -version 2>&1 | awk 'NR==3{ gsub(/"/,""); print $1 " " $2 }'
}


# ------------------------------------------------------------------------------
# Parses CONF_NODE_INSTANCES defined in 'farm.conf' and returns a string 
# containing all the nodes seperated by a space. Returned string can be used in 
# 'for ... in' loops.
# 
# Example usage:
#
#   CONF_NODE_INSTANCES="node1:instance1,instance2,instance3;\
#                        node2:instance4,instance5,instance6;\
#                        node3:instance7,instance8,instance9"
#
#   myNodes=$(getNodes)
#   for item in $myNodes
#   do
#     echo "node: $item "
#   done 
# ------------------------------------------------------------------------------
getNodes () {

  local nodes=""

  local rows=$(split "$CONF_NODE_INSTANCES" ";")
  for row in ${rows}
  do
    local nodeInstances=($(split "${row}" ":"))
    local node=${nodeInstances[0]}
    nodes="${nodes} ${node}"
  done

  echo "${nodes}"

}


# ------------------------------------------------------------------------------
# Parses CONF_NODE_INSTANCES defined in 'farm.conf' and returns a string 
# containing all the instances of given node seperated by a space. Returned 
# string can be used in 'for ... in' loops.
# 
# Example usage:
#
#  ----- code snippet -----
#   CONF_NODE_INSTANCES="node1:instance1,instance2,instance3;\
#                        node2:instance4,instance5,instance6;\
#                        node3:instance7,instance8,instance9"
#
#   myInstances=$(getInstances node2)
#   for item in $myInstances
#   do
#     echo "instance: $item "
#   done 
#  ----- code snippet -----
#
# Parameters:
#   $1: node
# ------------------------------------------------------------------------------
getInstances () {

  local argNode=$1

  if [[ "${argNode}" = "" ]] ; then
    log "node parameter cannot be empty. Use 'getInstances <node_name>'"
    exit 1
  fi

  local instances=""

  local rows=$(split "$CONF_NODE_INSTANCES" ";")
  for row in $rows
  do
    local nodeAndInstances=($(split "$row" ":"))
    local node=${nodeAndInstances[0]}
    if [[ "${node}" = "${argNode}" ]] ; then
      instances=$(split "${nodeAndInstances[1]}" ",")
    fi
  done

  echo "${instances}"

}


getNodeOfInstance () {

  local argInstance=$1
  
  local nodes=($(getNodes))
  for node in "${nodes[@]}"
  do
    local instances=($(getInstances "${node}"))
    for instance in "${instances[@]}"
    do
      if [ "${instance}" = "${argInstance}" ] ; then 
        echo "${node}"
        return 0
      fi
    done
  done
  
  echo ""

}


# ------------------------------------------------------------------------------
# Trims extra spaces between arguments of given string and prints each of them 
# in to a new line.
# 
# Example usage:
#
#  ----- code snippet -----
#  JAVA_OPTS="$JAVA_OPTS \
#    -server \
#    -showversion \
#    -Djava.awt.headless=true"
#  
#  printArguments ${JAVA_OPTS}
#  ----- code snippet -----
#
#  Here is the result:
#
#   -server
#   -showversion
#   -Djava.awt.headless=true
#
# Parameters:
#   $1: str (a string having space separated items.)
# ------------------------------------------------------------------------------
printArguments () {

  local str=$1
  items=(`echo "$str" | xargs`)
  for item in "${items[@]}"
  do
    echo "    $item"
  done

}


printNodeAndInstances () {

  local rows=$(split "$CONF_NODE_INSTANCES" ";")
  for row in $rows
  do
    echo "    ${row}"
  done

}


initialize () {

  set -e

  local absolute_path_of_this_file=${0}
  local dir_of_this_file=`dirname $absolute_path_of_this_file`
  CONF_FILE=${dir_of_this_file}/../conf/farm.conf
  if [ ! -f "${CONF_FILE}" ]; then
    echo "${CONF_FILE} file does not exist."
    exit 1
  fi

  # Load configuration file
  # We need to have executable rights to source the configuration file
  chmod +x $CONF_FILE
  . $CONF_FILE
  chmod -x $CONF_FILE
  
  # Because each machine is a node, node name is actully host name.
  NODE_NAME=`hostname -s`

  export JAVA_HOME=$CONF_JAVA_HOME

}


# ------------------------------------------------------------------------------
# The script starts here.
# ------------------------------------------------------------------------------
initialize