#!/bin/bash

source ./functions.sh
source ./settings.sh

ping -c 1 ${SERVER_TO_PING} >/dev/null 2>&1 && die "Fatal! System is connected to the internet! Aborting."

