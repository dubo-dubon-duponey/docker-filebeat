ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

##########################
# Builder custom
##########################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder

RUN           apt-get update -qq; apt-get install -qq -y python3-venv=3.7.3-1

# Beats v7.5.2
#ARG           BEATS_VERSION=a9c141434cd6b25d7a74a9c770be6b70643dc767
# Beats v7.7.1
ARG           BEATS_VERSION=932b273e8940575e15f10390882be205bad29e1f

WORKDIR       $GOPATH/src/github.com/elastic/beats
RUN           git clone https://github.com/elastic/beats.git .
RUN           git checkout $BEATS_VERSION

# Install mage et al
WORKDIR       $GOPATH/src/github.com/elastic/beats/filebeat
RUN           make update

# Build filebeat
WORKDIR       $GOPATH/src/github.com/elastic/beats
# hadolint ignore=DL4006
RUN           set -eu; \
              arch="${TARGETPLATFORM#*/}"; \
              commit="$(git describe --dirty --always)"; \
              now="$(date +%Y-%m-%dT%T%z | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w -X github.com/elastic/beats/libbeat/version.buildTime=$now -X github.com/elastic/beats/libbeat/version.commit=$commit" -o /dist/boot/bin/filebeat ./filebeat

# From x-pack... licensing?
WORKDIR       $GOPATH/src/github.com/elastic/beats/x-pack/filebeat

RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" make

RUN           make update

# XXX coredns plugin is broken right now, fix it
RUN           sed -i'' -e "s,%{timestamp} ,,g" build/package/module/coredns/log/ingest/pipeline-plaintext.yml
RUN           sed -i'' -e "s,%{timestamp} ,,g" build/package/module/coredns/log/ingest/pipeline-json.yml
RUN           sed -i'' -e 's,ignore_failure: true,if: ctx.timestamp != null,g' build/package/module/coredns/log/ingest/pipeline-entry.yml
# XXX apparently that part was fixed with 7.5.0
# RUN           sed -i'' -e 's,8d890080-413c-11e9-8548-ab7fbe04f038,filebeat-*,g' build/kibana/7/dashboard/Coredns-Overview-Dashboard.json
# RUN           sed -i'' -e 's/{\\"params\\": {}, \\"type\\": \\"count\\", \\"enabled\\": true, \\"id\\": \\"1\\", \\"schema\\": \\"metric\\"}/{\\"params\\": {\\"field\\": \\"coredns.id\\", \\"customLabel\\": \\"Unique Queries\\"}, \\"type\\": \\"cardinality\\", \\"enabled\\": true, \\"id\\": \\"1\\", \\"schema\\": \\"metric\\"}/g' build/kibana/7/dashboard/Coredns-Overview-Dashboard.json

# Move them to final destination
RUN           mv build/package/* build && rmdir build/package && mkdir -p /dist/config && mv build/* /dist/config
# Fix permissions
RUN           find /dist/config -type d -exec chmod -R 777 {} \; && find /dist/config -type f -exec chmod -R 666 {} \;

# Enable modules
# RUN           for i in /dist/config/modules.d/*; do mv "$i" "${i%.*}"; done
RUN           for i in coredns elasticsearch kibana system; do mv "/dist/config/modules.d/$i.yml.disabled" "/dist/config/modules.d/$i.yml"; done

COPY          --from=builder-healthcheck /dist/boot/bin           /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

# Get relevant bits from builder
COPY          --from=builder --chown=$BUILD_UID:root /dist .

ENV           KIBANA_HOST="192.168.1.8:5601"
ENV           ELASTICSEARCH_HOSTS="[192.168.1.8:9200]"
ENV           ELASTICSEARCH_USERNAME=""
ENV           ELASTICSEARCH_PASSWORD=""
ENV           MODULES="system coredns"

# Default volumes for data and certs, since these are expected to be writable
# VOLUME        /config
VOLUME        /data
VOLUME        /certs

# TODO have a better parametric default for this
ENV           HEALTHCHECK_URL="http://192.168.1.8:9200"

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
