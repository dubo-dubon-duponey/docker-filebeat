ARG           BUILDER_BASE=dubodubonduponey/base@sha256:b51f084380bc1bd2b665840317b6f19ccc844ee2fc7e700bf8633d95deba2819
ARG           RUNTIME_BASE=dubodubonduponey/base@sha256:d28e8eed3e87e8dc5afdd56367d3cf2da12a0003d064b5c62405afbe4725ee99

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           BUILD_TARGET=./cmd/http
ARG           BUILD_OUTPUT=http-health
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

##########################
# Builder custom
##########################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-main

RUN           apt-get update -qq; apt-get install -qq -y --no-install-recommends python3-venv=3.7.3-1

# This is 2.3.0
ARG           GIT_REPO=github.com/elastic/beats
ARG           GIT_VERSION=9b2fecb327a29fe8d0477074d8a2e42a3fabbc4b
ARG           BUILD_TARGET=./filebeat
ARG           BUILD_OUTPUT=filebeat
ARG           BUILD_FLAGS="-s -w -X github.com/elastic/beats/libbeat/version.buildTime=$DATE_CREATED -X github.com/elastic/beats/libbeat/version.commit=$BUILD_VERSION"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone https://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# Install mage et al
WORKDIR       $GOPATH/src/$GIT_REPO/filebeat
RUN           make update

# Build filebeat
WORKDIR       $GOPATH/src/$GIT_REPO
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

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



#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-main /dist /dist

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

# Bring in stuff from main
COPY          --from=builder --chown=$BUILD_UID:root /dist .

ENV           KIBANA_HOST="https://kibana.local"
ENV           KIBANA_USERNAME=""
ENV           KIBANA_PASSWORD=""
ENV           ELASTICSEARCH_HOSTS="[https://elastic.local:4443]"
ENV           ELASTICSEARCH_USERNAME=""
ENV           ELASTICSEARCH_PASSWORD=""
ENV           MODULES="system coredns"

# Default volumes for data
VOLUME        /data

ENV           HEALTHCHECK_URL="https://elastic.local:4443/_cluster/health"
HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
