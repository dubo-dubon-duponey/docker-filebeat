#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Specific to this image
# MODULES="${MODULES:-}"
KIBANA_HOST="${KIBANA_HOST:-}"
KIBANA_USERNAME="${KIBANA_USERNAME:-}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-}"
ELASTICSEARCH_HOSTS="${ELASTICSEARCH_HOSTS:-}"

# Ensure the certs folder is writable
[ -w "/certs" ] || {
  >&2 printf "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

# Ensure the data folder is writable
[ -w "/data" ] || {
  >&2 printf "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Configure command line arguments
# XXX it's unclear why most logs go to stdout naturally, while SOME (duplicate, apparently) go to path.logs - either way...
args+=(-c /config/filebeat.yml --path.data /data --path.config /config --path.home /config --path.logs /dev/stdout)
args+=(-e "-strict.perms=false" -E "output.elasticsearch.hosts=$ELASTICSEARCH_HOSTS")

sargs=(-E "setup.kibana.host=$KIBANA_HOST")
[ ! "$KIBANA_USERNAME" ] || sargs+=(-E "setup.kibana.username=$KIBANA_USERNAME")
[ ! "$KIBANA_PASSWORD" ] || sargs+=(-E "setup.kibana.password=$KIBANA_PASSWORD")

# Enable modules
# XXX Removing support for now - just too annoying to have /config writable
#for i in ${MODULES}; do
#  filebeat modules enable "${args[@]}" "$i"
#done

# Initial setup
# XXX uber dirty - repeat until elastic / kibana is up
# Also, this is... questionable...
n=0
while true; do
  if filebeat setup "${args[@]}" "${sargs[@]}"; then
    break
  fi
  n=$((n + 1))
  >&2 printf "Failed to contact elastic or kibana. Will wait and retry. This is try number %s\n" "$n"
  sleep 5
done

# Run once configured
exec filebeat run "${args[@]}" "$@"
