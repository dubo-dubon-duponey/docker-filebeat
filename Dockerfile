##########################
# Builder custom
# Custom steps required to build this specific image
##########################
FROM          --platform=$BUILDPLATFORM dubodubonduponey/base:builder                                   AS builder

# Beats v7.3.2
# ARG           BEATS_VERSION=5b046c5a97fe1e312f22d40a1f05365621aad621
# Beats v7.4.0
ARG           BEATS_VERSION=f940c36884d3749901a9c99bea5463a6030cdd9c

WORKDIR       $GOPATH/src/github.com/elastic/beats
RUN           git clone https://github.com/elastic/beats.git .
RUN           git checkout $BEATS_VERSION

# Healthcheck
COPY          http-client.go cmd/http-client/http-client.go

# Install mage et al
RUN           cd filebeat && make update

# Build healthcheck
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" -o dist/http-client ./cmd/http-client

# Build filebeat
RUN           arch="${TARGETPLATFORM#*/}"; \
              now=$(date -u '+%Y-%m-%dT%H:%M:%SZ'); \
              commit=$(git rev-parse HEAD); \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w -X github.com/elastic/beats/libbeat/version.buildTime=$now -X github.com/elastic/beats/libbeat/version.commit=$commit" -o dist/filebeat ./filebeat

# From x-pack... licensing?
WORKDIR       $GOPATH/src/github.com/elastic/beats/x-pack/filebeat

RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" make

RUN           make update

# XXX coredns plugin is broken right now, fix it
RUN           sed -i'' -e "s,%{timestamp} ,,g" build/package/module/coredns/log/ingest/pipeline-plaintext.json
RUN           sed -i'' -e "s,%{timestamp} ,,g" build/package/module/coredns/log/ingest/pipeline-json.json
RUN           sed -i'' -e 's,"ignore_failure" : true,"if": "ctx.timestamp != null",g' build/package/module/coredns/log/ingest/pipeline-entry.json
RUN           sed -i'' -e 's,8d890080-413c-11e9-8548-ab7fbe04f038,filebeat-*,g' build/kibana/7/dashboard/Coredns-Overview-Dashboard.json
RUN           sed -i'' -e 's/{\\"params\\": {}, \\"type\\": \\"count\\", \\"enabled\\": true, \\"id\\": \\"1\\", \\"schema\\": \\"metric\\"}/{\\"params\\": {\\"field\\": \\"coredns.id\\", \\"customLabel\\": \\"Unique Queries\\"}, \\"type\\": \\"cardinality\\", \\"enabled\\": true, \\"id\\": \\"1\\", \\"schema\\": \\"metric\\"}/g' build/kibana/7/dashboard/Coredns-Overview-Dashboard.json

# Move them to final destination
RUN           mv build/package/* build && rmdir build/package && mkdir -p /dist/config && mv build/* /dist/config

WORKDIR       /dist/bin
RUN           cp "$GOPATH"/src/github.com/elastic/beats/dist/filebeat     .
RUN           cp "$GOPATH"/src/github.com/elastic/beats/dist/http-client  .
RUN           chmod 555 ./*

#######################
# Running image
#######################
FROM          dubodubonduponey/base:runtime

# Get relevant bits from builder
COPY          --from=builder --chown=$BUILD_UID:0 /dist .

# Fix permissions
RUN           find /config -type d -exec chmod -R 770 {} \; && find /config -type f -exec chmod -R 660 {} \;

ENV           KIBANA_HOST="192.168.1.8:5601"
ENV           ELASTICSEARCH_HOSTS="[192.168.1.8:9200]"
ENV           ELASTICSEARCH_USERNAME=""
ENV           ELASTICSEARCH_PASSWORD=""
ENV           HEALTHCHECK_URL="http://192.168.1.8:9200"
ENV           MODULES="system coredns"

# Default volumes for data and certs, since these are expected to be writable
VOLUME        /config
VOLUME        /data
VOLUME        /certs

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-client || exit 1
