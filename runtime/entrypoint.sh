#!/usr/bin/env bash

OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}

MODULES="${MODULES:-}"
KIBANA_HOST="${KIBANA_HOST:-}"
ELASTICSEARCH_HOSTS="${ELASTICSEARCH_HOSTS:-}"

config::setup(){
  # If no config, try to have the default one, and fail if this fails
  if [ ! -e /config/config.yaml ] || [ "$OVERWRITE_CONFIG" ]; then
    [ ! -e /config/config.yaml ] || >&2 printf "Overwriting configuration file.\n"
    cp config/* /config/ 2>/dev/null || {
      >&2 printf "Failed to create default config file. Permissions issue likely.\n"
      exit 1
    }
  fi
}

config::setup

# Initial setup
filebeat setup --modules "$MODULES" -E setup.kibana.host="$KIBANA_HOST" -E output.elasticsearch.hosts="$ELASTICSEARCH_HOSTS"

# Actual run
exec filebeat --modules "$MODULES" -e -strict.perms=false -E output.elasticsearch.hosts="$ELASTICSEARCH_HOSTS"
