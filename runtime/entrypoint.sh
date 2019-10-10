#!/usr/bin/env bash

# Generic config management
OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-}
OVERWRITE_DATA=${OVERWRITE_DATA:-}
OVERWRITE_CERTS=${OVERWRITE_CERTS:-}

config::writable(){
  local folder="$1"
  [ -w "$folder" ] || {
    >&2 printf "$folder is not writable. Check your mount permissions.\n"
    exit 1
  }
}

config::setup(){
  local folder="$1"
  local overwrite="$2"
  local f
  local localfolder
  localfolder="$(basename "$folder")"

  # Clean-up if we are to overwrite
  [ ! "$overwrite" ] || rm -Rf "${folder:?}"/*

  # If we have a local source
  if [ -e "$localfolder" ]; then
    # Copy any file in there over the destination if it doesn't exist
    for f in "$localfolder"/*; do
      if [ ! -e "/$f" ]; then
        >&2 printf "(Over-)writing file /$f.\n"
        cp -R "$f" "/$f" 2>/dev/null || {
          >&2 printf "Failed to create file. Permissions issue likely.\n"
          exit 1
        }
      fi
    done
  fi
}

config:writable /certs
config:writable /data
config::setup   /config  "$OVERWRITE_CONFIG"
config::setup   /data    "$OVERWRITE_DATA"
config::setup   /certs   "$OVERWRITE_CERTS"

# Filebeat
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
