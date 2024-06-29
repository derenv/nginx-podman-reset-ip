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

# Move to script directory
SCRIPT_DIR="$(dirname $0)"
cd "${SCRIPT_DIR:?}" || exit 1

## Load & Check Variables in config ##
if [ -f "${SCRIPT_DIR:?}/config.conf" ]; then
  source "${SCRIPT_DIR:?}/config.conf"

  if [[ ! -v DATA_DIR ]]; then
    printf "variable DATA_DIR not set!\n"; exit 1
  fi
  if [[ ! -v WEBSITE_URL ]]; then
    printf "variable WEBSITE_URL not set!\n"; exit 1
  fi
  if [[ ! -v PROXY_CONFIG_FILE ]]; then
    printf "variable PROXY_CONFIG_FILE not set!\n"; exit 1
  fi
  if [[ ! -v DOCKER_IP_RANGE ]]; then
    printf "variable DOCKER_IP_RANGE not set!\n"; exit 1
  fi

  printf "config file present and defines required variables..\n"
else
  printf "config file missing!\n"; exit 1
fi
##

## Check container running ##
if [[ "$(podman ps | grep nginx)" == "" ]]; then
  printf "NGinx container not running..\n"; exit 1
else
  printf "NGinx container running..\n"
fi

## Check AIO http response ##
printf "Checking URL HTTP response..\n"
RESPONSE=$(curl -s -o /dev/null -I -w "%{http_code}" "https://${WEBSITE_URL:?}/")

# Respond to status, depending on HTTP response
#https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/504
#https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/502
if [[ "${RESPONSE:?}" == "502" ]] || [[ "${RESPONSE:?}" == "504" ]]; then
  printf "HTTP Response \'%s\' indicates new IP required!\n" "${RESPONSE:?}"

  ## Get new IP address from docker ##
  # Reset DOCKER_HOST value to empty, rootfull docker is then used
  DOCKER_HOST=""
  #DOCKER_HOST="unix:///run/user/1000/docker.sock" # use rootless docker socket

  # Get docker network configs
  CONTAINERS=$(docker network inspect nextcloud-aio -f json | jq '.[].Containers')

  # Check containers are present in docker
  CONTAINER_COUNT=$(printf "%s" "${CONTAINERS:?}" | jq 'length')
  if [[ "${CONTAINER_COUNT:?}" -eq 0 ]]; then
    printf "No containers present in Docker..\n"; exit 1
  else
    printf "Containers present: \'%s\'\n" "${CONTAINER_COUNT:?}"
  fi

  # Check the AIO's Apache container exists
  APACHE_CONTAINER=$(printf "%s" "${CONTAINERS:?}" | grep -e "\"Name\": \"nextcloud-aio-apache\"" -A3)
  if [[ "$?" -ne 0 ]]; then
    printf "No nextcloud AIO apache container present..\n"; exit 1
  else
    printf "Apache container present!\n"
  fi

  # Store "IPv4Address" value in variable
  IFS="\"" read -a ip_array <<< $(printf "%s" "${APACHE_CONTAINER:?}" | grep -e "IPv4Address")
  NEW_IP="${ip_array[3]::-3}"

  ## Output new IP ##
  printf "New IP: \'%s\'\n" "${NEW_IP:?}"

  ## Modify NGINX configuration ##
  # Modify NGINX conf file (for actual routing) using sed
  sed "s/$DOCKER_IP_RANGE/$NEW_IP\"\;/" -i "${DATA_DIR:?}/nginx/proxy_host/${PROXY_CONFIG_FILE:?}"

  # Update sqlite database (for webapp) using python script
  if python3 "${SCRIPT_DIR:?}/set_ip.py" "${DATA_DIR:?}/database.sqlite" "${NEW_IP:?}" "[\"${WEBSITE_URL:?}\"]"; then
    printf "Database updated successfully..\n"
  else
    printf "Something's gone very wrong, exit code from python script: \'%s\'\n" "$?"; exit 1
  fi
  ##


  ## Restart NGINX container ##
  #### USE SYSTEMD
  printf "Restarting NGinx container using systemd service..\n"
  systemctl --user restart nginx-container.service

  # Wait 10 seconds to give podman time to restart the container..
  sleep 10s

  # Re-set DOCKER_HOST to use podman
  DOCKER_HOST="unix:///run/user/1000/podman/podman.sock"

  # Check nginx container status using health check
  # (NOTE: Podman puts a carriage return ('\r') at the end for some reason, windows style? hence trim command)
  CONTAINER_STATUS=$(podman exec -it nginx /bin/check-health | tr -d '\r')
  if [[ "${CONTAINER_STATUS:?}" == "OK" ]]; then
    printf "Container healthy..\n"
  else
    printf "Something's gone very wrong, container health check failed: \'%s\'\n" "${CONTAINER_STATUS:?}"; exit 1
  fi
  ##
#https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/200
#https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/302
elif [[ "${RESPONSE:?}" == "200" ]] || [[ "${RESPONSE:?}" == "302" ]]; then
  printf "HTTP Response \'%s\' indicates no update required..\n" "${RESPONSE:?}"
else
  printf "Something\'s gone very wrong, unhandled HTTP response code: \'%s\'\n" "${RESPONSE:?}"; exit 1
fi

exit 0
