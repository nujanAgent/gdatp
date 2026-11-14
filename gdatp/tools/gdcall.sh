#!/usr/bin/env bash
# Calls one of GDatp's editor tools on a phone (debug builds) and prints the answer's JSON.
#   gdatp/tools/gdcall.sh <serial> <tool> ['<json arguments>']
# The arguments reach the phone's shell inside single quotes, so they must not contain one.
serial=$1
tool=$2
args=${3:-"{}"}
export MSYS_NO_PATHCONV=1
adb -s "$serial" shell "am broadcast -n com.gd.atp/com.gd.atp.DebugCallReceiver --es tool $tool --es args '$args'" |
	sed -n 's/^Broadcast completed: result=[-0-9]*, data="\(.*\)"$/\1/p'
