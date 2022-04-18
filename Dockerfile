ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2022-04-01@sha256:d73bb6ea84152c42e314bc9bff6388d0df6d01e277bd238ee0e6f8ade721856d
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2022-04-01@sha256:ca513bf0219f654afeb2d24aae233fef99cbcb01991aea64060f3414ac792b3f
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2022-04-01@sha256:6456b76dd2eedf34b4c5c997f9ad92901220dfdd405ec63419d0b54b6d85a777
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2022-04-01@sha256:323f3e36da17d8638a07a656e2f17d5ee4dc2b17dfea7e2da36e1b2174cc5f18

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-filebeat

ARG           GIT_REPO=github.com/elastic/beats
#ARG           GIT_VERSION=7.13.4
#ARG           GIT_COMMIT=1907c246c8b0d23ae4027699c44bf3fbef57f4a4
#ARG           GIT_VERSION=v7.14.0
# XXX unfortunately busted and has been for some time, because of some BS around a dep (kardianos/service)
#XXXXARG           GIT_COMMIT=e127fc31fc6c00fdf8649808f9421d8f8c28b5db
#ARG           GIT_COMMIT=70cab1df99e3f05397e3ed69ba47608dc103a985

ARG           GIT_VERSION=v7.17.2
ARG           GIT_COMMIT=0e693268830769a77c9128b670888590f4d4f26d

#ARG           GIT_VERSION=v8.1.2
#ARG           GIT_COMMIT=f35c1c87a80571070e60753e9f007255ebc8655b

ENV           WITH_BUILD_SOURCE=./filebeat
ENV           WITH_BUILD_OUTPUT=filebeat
# XXX date created here should be the commit date of the git repo
ENV           WITH_LDFLAGS="-X github.com/elastic/beats/libbeat/version.buildTime=$DATE_CREATED -X github.com/elastic/beats/libbeat/version.commit=$GIT_COMMIT"
# XXX CGO / avahi?

# Damnit docker distribution
# XXX giving up on trying to make it work - too many module simply break, and since people do not vendor anymore, it's all about relying on google goproxy infra
#RUN           echo "exclude github.com/docker/distribution v2.8.0+incompatible" >> go.mod

RUN           git clone --recurse-submodules https://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

# hadolint ignore=DL3009
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; apt-get install -qq --no-install-recommends python3-venv=3.9.2-3

# Install mage - requires network as this stuff does go get
# hadolint ignore=DL3003,SC2164
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              cd filebeat; make update; command mage || { echo mage build fail; exit 1; }

#######################
# Main builder
#######################
# XXX --platform=$BUILDPLATFORM  not a x-build yet
FROM          fetcher-filebeat                                                                                              AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

# beats-dashboards?

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
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
FROM          $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

# XXX --platform=$BUILDPLATFORM
# We could stay on the arch though - and install the package for the targetarch instead

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq && apt-get install -qq --no-install-recommends \
                libnss-mdns=0.14.1-2 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

COPY          --from=builder-main   /dist           /dist

COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           cp /usr/sbin/avahi-daemon                 /dist/boot/bin
RUN           setcap 'cap_chown+ei cap_dac_override+ei' /dist/boot/bin/avahi-daemon

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

USER          root

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq \
              && apt-get install -qq --no-install-recommends \
                libnss-mdns=0.14.1-2 \
              && apt-get -qq autoremove       \
              && apt-get -qq clean            \
              && rm -rf /var/lib/apt/lists/*  \
              && rm -rf /tmp/*                \
              && rm -rf /var/tmp/*

RUN           ln -s "$XDG_STATE_HOME"/avahi-daemon /run

USER          dubo-dubon-duponey

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

ENV           MDNS_NSS_ENABLED=true

ENV           KIBANA_HOST="https://kibana.local"
ENV           KIBANA_USERNAME=""
ENV           KIBANA_PASSWORD=""
ENV           ELASTICSEARCH_HOSTS="[https://elastic.local:4443]"
ENV           ELASTICSEARCH_USERNAME=""
ENV           ELASTICSEARCH_PASSWORD=""
ENV           MODULES="system coredns"

# XXX not completely clear if the moe to ramdisks will negatively impact
# loggers UUID / registration?
# Default volumes for data
# VOLUME        /data

# Filebeat write its registry / state
VOLUME        /tmp

ENV           HEALTHCHECK_URL="https://elastic.local:443/_cluster/health"
HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
