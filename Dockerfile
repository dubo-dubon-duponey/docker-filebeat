##########################
# Building image
##########################
FROM        --platform=$BUILDPLATFORM golang:1.13-buster                                                  AS builder

# Install dependencies and tools
ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
RUN         apt-get update                                                                                > /dev/null
RUN         apt-get install -y --no-install-recommends \
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

# Create stuff for the package
RUN         apt-get install -y --no-install-recommends virtualenv=15.1.0+ds-2                             > /dev/null
RUN         make update

# From x-pack... licensing!
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

LABEL       dockerfile.copyright="Dubo Dubon Duponey <dubo-dubon-duponey@jsboot.space>"

ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"

WORKDIR     /dubo-dubon-duponey

# Build time variable
ARG         BUILD_USER=dubo-dubon-duponey
ARG         BUILD_UID=1000
ARG         BUILD_GROUP=$BUILD_USER
ARG         BUILD_GID=$BUILD_UID

ARG         CONFIG=/config
ARG         CERTS=/certs
ARG         DATA=/data

# Get relevant bits from builder
COPY        --from=builder /etc/ssl/certs                                             /etc/ssl/certs
COPY        --from=builder /go/src/github.com/elastic/beats/filebeat/filebeat         /bin/filebeat
COPY        --from=builder /go/src/github.com/elastic/beats/x-pack/filebeat/build     config

# Get relevant local files into cwd
COPY        runtime .

# Set links
RUN         mkdir $CONFIG && mkdir $DATA && mkdir $CERTS && \
            chown $BUILD_UID:$BUILD_GID $CONFIG && chown $BUILD_UID:$BUILD_GID $DATA && chown $BUILD_UID:$BUILD_GID $CERTS && chown -R $BUILD_UID:$BUILD_GID . && \
            chown -R root:root config && \
            ln -sf /dev/stdout out.log && \
            ln -sf /dev/stderr err.log

# Create user
RUN         addgroup --system --gid $BUILD_GID $BUILD_GROUP && \
            adduser --system --disabled-login --no-create-home --home /nonexistent --shell /bin/false \
                --gecos "in dockerfile user" \
                --ingroup $BUILD_GROUP \
                --uid $BUILD_UID \
                $BUILD_USER

USER        $BUILD_USER

ENV         OVERWRITE_CONFIG=""

ENV         KIBANA_HOST="192.168.1.8:5601"
ENV         ELASTICSEARCH_HOSTS="[\"192.168.1.8:9200\"]"
ENV         ELASTICSEARCH_USERNAME=""
ENV         ELASTICSEARCH_PASSWORD=""
ENV         MODULES="coredns"

VOLUME      $CONFIG
VOLUME      $DATA
VOLUME      $CERTS

ENTRYPOINT  ["./entrypoint.sh"]
# env ELASTIC_CONTAINER=true
