ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-07-01@sha256:f1c46316c38cc1ca54fd53b54b73797b35ba65ee727beea1a5ed08d0ad7e8ccf
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-07-01@sha256:9f5b20d392e1a1082799b3befddca68cee2636c72c502aa7652d160896f85b36
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-07-01@sha256:f1e25694fe933c7970773cb323975bb5c995fa91d0c1a148f4f1c131cbc5872c

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ENV           GIT_REPO=github.com/elastic/beats
ENV           GIT_VERSION=7.13.4
ENV           GIT_COMMIT=1907c246c8b0d23ae4027699c44bf3fbef57f4a4

ENV           WITH_BUILD_SOURCE=./filebeat
ENV           WITH_BUILD_OUTPUT=filebeat
# XXX date created here should be the commit date of the git repo
ENV           WITH_LDFLAGS="-X github.com/elastic/beats/libbeat/version.buildTime=$DATE_CREATED -X github.com/elastic/beats/libbeat/version.commit=$GIT_COMMIT"
# XXX CGO / avahi?

RUN           git clone --recurse-submodules git://"$GIT_REPO" .
RUN           git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

#######################
# Main builder
#######################
# XXX --platform=$BUILDPLATFORM  not a x-build yet
FROM          fetcher-main                                                                                              AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; apt-get install -qq --no-install-recommends python3-venv=3.9.2-3

# Install mage et al - careful here, we are looking for build tools running on the host platform, not to cross-build (yet)
# hadolint ignore=DL3003,SC2164
RUN           cd filebeat; make update
# beats-dashboards?

# Important cases being handled:
# - cannot compile statically with PIE but on amd64 and arm64
# - cannot compile fully statically with NETCGO
RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

# From x-pack... licensing?
WORKDIR       /source/x-pack/filebeat

RUN           make

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
# Builder assembly, XXX should be auditor
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder

COPY          --from=builder-main   /dist           /dist

COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

# Bring in stuff from main
COPY          --from=builder --chown=$BUILD_UID:root /dist /

ENV           KIBANA_HOST="https://kibana.local"
ENV           KIBANA_USERNAME=""
ENV           KIBANA_PASSWORD=""
ENV           ELASTICSEARCH_HOSTS="[https://elastic.local:4443]"
ENV           ELASTICSEARCH_USERNAME=""
ENV           ELASTICSEARCH_PASSWORD=""
ENV           MODULES="system coredns"

# Default volumes for data
VOLUME        /data

# Filebeat write its registry / state
VOLUME        /tmp

ENV           HEALTHCHECK_URL="https://elastic.local:4443/_cluster/health"
HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
