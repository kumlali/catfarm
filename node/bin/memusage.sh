#!/bin/bash
# ------------------------------------------------------------------------------
# WARNING: This file might be overriden while deployment.
# ------------------------------------------------------------------------------
# Logs memory usage data of given PID.
#
# When IBM JDK is used, Garbage Collection and Memory Visualizer (GCMV) can
# load these data to view and analyze the native memory usage. For more
# information please see https://goo.gl/Mw63D9.
# ------------------------------------------------------------------------------

# The process id to monitor is the first and only argument.
PID=$1

# The interval between command invocations, in seconds.
INTERVAL=3

# Echo the date line to record the start of monitoring.
echo timestamp = `date +%s`

# Echo the interval frequency.
echo "ps interval = $INTERVAL"

# Run the system command at intervals.
while ([ -d /proc/$PID ]) do
  ps -p $PID -o pid,vsz,rss
  sleep $INTERVAL
done