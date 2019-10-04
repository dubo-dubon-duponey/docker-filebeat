#!/usr/bin/env bash

OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}

MODULES="${MODULES:-}"
KIBANA_HOST="${KIBANA_HOST:-}"
ELASTICSEARCH_HOSTS="${ELASTICSEARCH_HOSTS:-}"

config::setup(){
  # If no config, try to have the default one, and fail if this fails
  if [ ! -e /config/filebeat.yaml ] || [ "$OVERWRITE_CONFIG" ]; then
    [ ! -e /config/filebeat.yaml ] || >&2 printf "Overwriting configuration file.\n"
    cp -R config/* /config/ 2>/dev/null || {
      >&2 printf "Failed to create default config file. Permissions issue likely.\n"
      exit 1
    }
  fi
}

config::setup

args+=(-c /config/filebeat.yaml --path.data /data --path.home /config )

for i in ${MODULES}; do
  filebeat modules enable "${args[@]}" "$i"
done


# Initial setup
# XXX uber dirty - repeat until elastic is up
n=0
while true; do
  if filebeat setup "${args[@]}" -E setup.kibana.host="$KIBANA_HOST" -E output.elasticsearch.hosts="$ELASTICSEARCH_HOSTS"; then
    break
  fi
  n=$((n + 1))
  >&2 printf "Failed to contact elastic. Will wait and retry. This is the %s-th-try\n" "$n"
  sleep 5
done

# Actual run
exec filebeat run "${args[@]}" -e -strict.perms=false -E output.elasticsearch.hosts="$ELASTICSEARCH_HOSTS" "$@"
