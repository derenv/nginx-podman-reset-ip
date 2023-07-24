#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2023 Deren Vural <derenv@live.co.uk>
# SPDX-FileCopyrightText: 2023 Oscar McCabe <oscarmccabe98@gmail.com>
# SPDX-License-Identifier: MIT

##
# Name:
# reset.sh
#
# Description:
# Script for automatically updating an nginx reverse proxy address to the changing nextcloud-aio-apache server ip
#
# Used where nginx is in a rootless podman container acting as a reverse proxy for nextcloud-aio (which only supports rootful docker setups!) so using internal or loopback ip doesn't work
#
# Authors:
# Deren Vural (@derenv)
# Oscar Mccabe (@oscarmccabe1998)
#
# Notes:
# https://stackoverflow.com/questions/38906626/curl-to-return-http-status-code-along-with-the-response
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash
# https://quickref.me/sed
# https://developers.redhat.com/blog/2019/04/18/monitoring-container-vitality-and-availability-with-podman#
# https://nginxproxymanager.com/advanced-config/#docker-healthcheck
##

## Load Variables ##
SCRIPT_DIR=$(dirname $0)
if [ -f $SCRIPT_DIR/config.conf ]; then
  source $SCRIPT_DIR/config.conf

  if [[ ! -v DATA_DIR ]]; then
    echo "variable DATA_DIR not set!"
    exit 1
  fi
  if [[ ! -v WEBSITE_URL ]]; then
    echo "variable WEBSITE_URL not set!"
    exit 1
  fi
  if [[ ! -v PROXY_CONFIG_FILE ]]; then
    echo "variable PROXY_CONFIG_FILE not set!"
    exit 1
  fi
  if [[ ! -v DOCKER_IP_RANGE ]]; then
    echo "variable DOCKER_IP_RANGE not set!"
    exit 1
  fi

  echo "config working.."
else
  echo "missing config file!"
  exit 1
fi
##

## Check AIO http response ##
RESPONSE=$(curl -s -o /dev/null -I -w "%{http_code}" https://$WEBSITE_URL/)

if [[ "$RESPONSE" == "502" ]]; then
  ## Get new IP address from docker ##
  # Save DOCKER_HOST value to variable and reset
  OLD_DOCKER_HOST=$DOCKER_HOST
  DOCKER_HOST=""

  # Get docker network configs
  NETWORKS=$(docker network inspect nextcloud-aio -f json)

  # Find nextcloud-aio-apache and store "IPv4Address" value in variable
  OLD_IFS="$IFS"
  IFS="\"" read -a array1 <<< $(echo $NETWORKS | jq '.[].Containers' | grep -e "\"Name\": \"nextcloud-aio-apache\"" -A3 | grep -e "IPv4Address")
  IFS="/" read -a array2 <<< "${array1[3]}"
  NEW_IP="${array2[0]}"
  IFS="$OLD_IFS"
  ##


  ## Modify NGINX configuration ##
  # Modify NGINX conf file (for actual routing) using sed
  sed "s/$DOCKER_IP_RANGE/$NEW_IP\"\;/" -i $DATA_DIR/nginx/proxy_host/$PROXY_CONFIG_FILE

  # Update sqlite database (for webapp) using python script
  if python3 $SCRIPT_DIR/set_ip.py $DATA_DIR/database.sqlite "$NEW_IP" "[\"$WEBSITE_URL\"]"; then
    echo "Database updated successfully.."
  else
    echo "Something's gone very wrong, exit code from python script: $?"
    exit 1
  fi
  ##


  ## Restart NGINX container ##
  # Re-set DOCKER_HOST
  DOCKER_HOST=$OLD_DOCKER_HOST

  # Throws this error: `Error: crun: executable file `/init` not found in $PATH: No such file or directory: OCI runtime attempted to invoke a command that was not found`, can ignore..
  podman restart nginx

  # Wait 5 seconds to give podman time to restart the container..
  sleep 10s

  # Check nginx container status using health check
  # (NOTE: Podman puts a carriage return ('\r') at the end for some reason, windows style? hence trim command)
  CONTAINER_STATUS=$(podman exec -it nginx /bin/check-health | tr -d '\r')
  if [[ "$CONTAINER_STATUS" == "OK" ]]; then
    echo "Container healthy.."
  else
    echo "Something's gone very wrong, container health check failed: $CONTAINER_STATUS"
    exit 1
  fi
  ##
elif [[ "$RESPONSE" == "200" ]] || [[ "$RESPONSE" == "302" ]]; then
  echo "No update required.."
else
  echo "Something's gone very wrong, unknown http response: $RESPONSE"
  exit 1
fi

exit 0
