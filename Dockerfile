ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

##########################
# Builder custom
##########################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder

RUN           apt-get update -qq; apt-get install -qq -y --no-install-recommends python3-venv=3.7.3-1

# Beats v7.5.2
#ARG           GIT_VERSION=a9c141434cd6b25d7a74a9c770be6b70643dc767
# Beats v7.7.1
#ARG           GIT_VERSION=932b273e8940575e15f10390882be205bad29e1f
# 7.8.1
#ARG           GIT_VERSION=94f7632be5d56a7928595da79f4b829ffe123744
# 7.10.0
ARG           GIT_VERSION=1428d58cf2ed945441fb2ed03961cafa9e4ad3eb
ARG           GIT_REPO=github.com/elastic/beats

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# Install mage et al
WORKDIR       $GOPATH/src/$GIT_REPO/filebeat
RUN           make update

# Build filebeat
WORKDIR       $GOPATH/src/$GIT_REPO

# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w -X github.com/elastic/beats/libbeat/version.buildTime=$DATE_CREATED -X github.com/elastic/beats/libbeat/version.commit=$BUILD_VERSION" \
                -o /dist/boot/bin/filebeat ./filebeat

# From x-pack... licensing?
WORKDIR       $GOPATH/src/$GIT_REPO/x-pack/filebeat

# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" make

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
ENV           KIBANA_USERNAME=""
ENV           KIBANA_PASSWORD=""
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
