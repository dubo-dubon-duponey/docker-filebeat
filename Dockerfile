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
ARG         BEATS_VERSION=f940c36884d3749901a9c99bea5463a6030cdd9c

WORKDIR     /go/src/github.com/elastic/beats
RUN         git clone https://github.com/elastic/beats.git .
RUN         git checkout $BEATS_VERSION

WORKDIR     /go/src/github.com/elastic/beats/filebeat
RUN         arch=${TARGETPLATFORM#*/} && \
            env GOOS=linux GOARCH=${arch%/*} make

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

# Get relevant bits from builder
COPY        --from=builder /etc/ssl/certs                             /etc/ssl/certs
COPY        --from=builder /go/src/github.com/elastic/beats/filebeat/filebeat /bin/filebeat

# Get relevant local files into cwd
COPY        runtime .

# Set links
RUN         mkdir $CONFIG && mkdir $CERTS && \
            chown $BUILD_UID:$BUILD_GID $CONFIG && chown $BUILD_UID:$BUILD_GID $CERTS && chown -R $BUILD_UID:$BUILD_GID . && \
            ln -sf /dev/stdout access.log && \
            ln -sf /dev/stderr error.log

# Create user
RUN         addgroup --system --gid $BUILD_GID $BUILD_GROUP && \
            adduser --system --disabled-login --no-create-home --home /nonexistent --shell /bin/false \
                --gecos "in dockerfile user" \
                --ingroup $BUILD_GROUP \
                --uid $BUILD_UID \
                $BUILD_USER

USER        $BUILD_USER

ENV         OVERWRITE_CONFIG=""

ENV         ELASTICSEARCH_HOSTS="[\"192.168.1.8:9200\"]"
ENV         KIBANA_HOST="192.168.1.8:5601"
ENV         ELASTICSEARCH_USERNAME=""
ENV         ELASTICSEARCH_PASSWORD=""
ENV         MODULES="coredns"

VOLUME      $CONFIG
VOLUME      $CERTS

ENTRYPOINT  ["./entrypoint.sh"]
