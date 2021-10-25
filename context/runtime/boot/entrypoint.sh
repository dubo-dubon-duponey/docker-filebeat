#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable /tmp

[ "${MDNS_NSS_ENABLED:-}" != true ] || mdns::resolver::start

KIBANA_HOST="${KIBANA_HOST:-}"
KIBANA_USERNAME="${KIBANA_USERNAME:-}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-}"
ELASTICSEARCH_HOSTS="${ELASTICSEARCH_HOSTS:-}"
ELASTICSEARCH_USERNAME="${ELASTICSEARCH_USERNAME:-}"
ELASTICSEARCH_PASSWORD="${ELASTICSEARCH_PASSWORD:-}"

# XXX hook up TLS client here.

LOG_LEVEL="$(printf "%s" "${LOG_LEVEL:-info}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^(warn)$/warning/')"

# Configure command line arguments
# XXX it's unclear why most logs go to stdout naturally, while SOME (duplicate, apparently) go to path.logs - either way...
args=(-c /config/filebeat/main.yml)
args+=(--path.data /tmp --path.config /config --path.home /config --path.logs /dev/stdout)
args+=(-e "-strict.perms=false")
args+=(-E logging.level="$LOG_LEVEL")

# Initial setup
# XXX uber dirty - repeat until elastic / kibana is up
# Also, this is... questionable...
n=0
while true; do
  if filebeat setup "${args[@]}" "$@"; then
    break
  fi
  n=$((n + 1))
  printf >&2 "Failed to contact elastic or kibana. Will wait and retry. This is try number %s\n" "$n"
  sleep 5
done

# Run once configured
exec filebeat run "${args[@]}" "$@"
