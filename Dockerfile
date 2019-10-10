##########################
# Building image
##########################
FROM        --platform=$BUILDPLATFORM golang:1.13-buster                                                  AS builder

# Install dependencies and tools
ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
RUN         apt-get update                                                                                > /dev/null
RUN         apt-get install -y --no-install-recommends \
                virtualenv=15.1.0+ds-2 \
                make=4.2.1-1.2 \
                git=1:2.20.1-2 \
                ca-certificates=20190110                                                                  > /dev/null
RUN         update-ca-certificates

WORKDIR     /build

ARG         TARGETPLATFORM

# Beats v7.4.0
# ARG         BEATS_VERSION=f940c36884d3749901a9c99bea5463a6030cdd9c
# Beats v7.3.2
ARG         BEATS_VERSION=5b046c5a97fe1e312f22d40a1f05365621aad621

WORKDIR     /go/src/github.com/elastic/beats
RUN         git clone https://github.com/elastic/beats.git .
RUN         git checkout $BEATS_VERSION

WORKDIR     /go/src/github.com/elastic/beats/filebeat
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make
RUN         make update

# From x-pack... licensing?
WORKDIR     /go/src/github.com/elastic/beats/x-pack/filebeat
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make
RUN         make update
RUN         mv build/package/* build/ && rmdir build/package

# XXX coredns plugin is broken right now, fix it
RUN         sed -i'' -e "s,%{timestamp} ,,g" build/module/coredns/log/ingest/pipeline-plaintext.json
RUN         sed -i'' -e "s,%{timestamp} ,,g" build/module/coredns/log/ingest/pipeline-json.json
RUN         sed -i'' -e 's,"ignore_failure" : true,"if": "ctx.timestamp != null",g' build/module/coredns/log/ingest/pipeline-entry.json
RUN         sed -i'' -e 's,8d890080-413c-11e9-8548-ab7fbe04f038,filebeat-*,g' build/kibana/7/dashboard/Coredns-Overview-Dashboard.json
RUN         sed -i'' -e 's/{\\"params\\": {}, \\"type\\": \\"count\\", \\"enabled\\": true, \\"id\\": \\"1\\", \\"schema\\": \\"metric\\"}/{\\"params\\": {\\"field\\": \\"coredns.id\\", \\"customLabel\\": \\"Unique Queries\\"}, \\"type\\": \\"cardinality\\", \\"enabled\\": true, \\"id\\": \\"1\\", \\"schema\\": \\"metric\\"}/g' build/kibana/7/dashboard/Coredns-Overview-Dashboard.json

#######################
# Running image
#######################
FROM        debian:buster-slim
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

# Build args
ARG         BUILD_UID=1000

# Labels build args
ARG         BUILD_CREATED="1976-04-14T17:00:00-07:00"
ARG         BUILD_URL="https://github.com/dubodubonduponey/nonexistent"
ARG         BUILD_DOCUMENTATION="https://github.com/dubodubonduponey/nonexistent"
ARG         BUILD_SOURCE="https://github.com/dubodubonduponey/nonexistent"
ARG         BUILD_VERSION="unknown"
ARG         BUILD_REVISION="unknown"
ARG         BUILD_VENDOR="dubodubonduponey"
ARG         BUILD_LICENSES="MIT"
ARG         BUILD_REF_NAME="dubodubonduponey/nonexistent"
ARG         BUILD_TITLE="A DBDBDP image"
ARG         BUILD_DESCRIPTION="So image. Much DBDBDP. Such description."

LABEL       org.opencontainers.image.created="$BUILD_CREATED"
LABEL       org.opencontainers.image.authors="Dubo Dubon Duponey <dubo-dubon-duponey@farcloser.world>"
LABEL       org.opencontainers.image.url="$BUILD_URL"
LABEL       org.opencontainers.image.documentation="$BUILD_DOCUMENTATION"
LABEL       org.opencontainers.image.source="$BUILD_SOURCE"
LABEL       org.opencontainers.image.version="$BUILD_VERSION"
LABEL       org.opencontainers.image.revision="$BUILD_REVISION"
LABEL       org.opencontainers.image.vendor="$BUILD_VENDOR"
LABEL       org.opencontainers.image.licenses="$BUILD_LICENSES"
LABEL       org.opencontainers.image.ref.name="$BUILD_REF_NAME"
LABEL       org.opencontainers.image.title="$BUILD_TITLE"
LABEL       org.opencontainers.image.description="$BUILD_DESCRIPTION"

# Get universal relevant files
COPY        runtime  /
COPY        --from=builder /etc/ssl/certs                             /etc/ssl/certs

# Create a restriced user account (no shell, no home, disabled)
# Setup directories and permissions
# The user can access the files as the owner, and root can access as the group (that way, --user root still works without caps).
# Write is granted, although that doesn't really matter in term of security
RUN         adduser --system --no-create-home --home /nonexistent --gecos "in dockerfile user" \
                --uid $BUILD_UID \
                dubo-dubon-duponey \
              && chmod 550 entrypoint.sh \
              && chown $BUILD_UID:root entrypoint.sh \
              && mkdir -p /config \
              && mkdir -p /data \
              && mkdir -p /certs \
              && chown -R $BUILD_UID:root /config \
              && chown -R $BUILD_UID:root /data \
              && chown -R $BUILD_UID:root /certs \
              && find /config -type d -exec chmod -R 770 {} \; \
              && find /config -type f -exec chmod -R 660 {} \; \
              && find /data -type d -exec chmod -R 770 {} \; \
              && find /data -type f -exec chmod -R 660 {} \; \
              && find /certs -type d -exec chmod -R 770 {} \; \
              && find /certs -type f -exec chmod -R 660 {} \;

# Default volumes for data and certs, since these are expected to be writable
VOLUME      /data
VOLUME      /certs

# Downgrade to system user
USER        dubo-dubon-duponey

ENTRYPOINT  ["/entrypoint.sh"]

##########################################
# Image specifics
##########################################

# Get relevant bits from builder
COPY        --from=builder /go/src/github.com/elastic/beats/filebeat/filebeat       /bin/filebeat
COPY        --from=builder /go/src/github.com/elastic/beats/x-pack/filebeat/build   config

ENV         KIBANA_HOST="192.168.1.8:5601"
ENV         ELASTICSEARCH_HOSTS="[192.168.1.8:9200]"
ENV         ELASTICSEARCH_USERNAME=""
ENV         ELASTICSEARCH_PASSWORD=""
ENV         MODULES="system coredns"
