#!/usr/bin/env bash

# Generic config management
config::writable(){
  local folder="$1"
  [ -w "$folder" ] || {
    >&2 printf "%s is not writable. Check your mount permissions.\n" "$folder"
    exit 1
  }
}

# Ensure the certs and data folders are writable
config::writable /certs
config::writable /data

# Specific to this image
MODULES="${MODULES:-}"
KIBANA_HOST="${KIBANA_HOST:-}"
ELASTICSEARCH_HOSTS="${ELASTICSEARCH_HOSTS:-}"

# Configure command line arguments
# XXX it's unclear why most logs go to stdout naturally, while SOME (duplicate, apparently) go to path.logs - either way...
args+=(-c /config/filebeat.yml --path.data /data --path.config /config --path.home /config --path.logs /dev/stdout)
args+=(-e "-strict.perms=false" -E "output.elasticsearch.hosts=$ELASTICSEARCH_HOSTS")

# Enable modules
for i in ${MODULES}; do
  filebeat modules enable "${args[@]}" "$i"
done

# Initial setup
# XXX uber dirty - repeat until elastic is up
n=0
while true; do
  if filebeat setup "${args[@]}" -E setup.kibana.host="$KIBANA_HOST"; then
    break
  fi
  n=$((n + 1))
  >&2 printf "Failed to contact elastic. Will wait and retry. This is try number %s\n" "$n"
  sleep 5
done

# Run once configured
exec filebeat run "${args[@]}" "$@"
