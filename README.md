# What

Docker image for "FileBeat" agent.

This is based on [Filebeat](https://www.elastic.co/products/beats/filebeat).

Meant to collect docker containers logs on a single node (with a working coredns module).

## Image features

* multi-architecture:
  * [x] linux/amd64
  * [x] linux/386
  * [x] linux/arm64
  * [x] linux/arm/v7
  * [x] linux/arm/v6
  * [x] linux/ppc64le
  * [x] linux/s390x
* hardened:
  * [x] image runs read-only
  * [x] image runs with no capabilities (unless you want it on a privileged port)
  * [ ] ~~process runs as a non-root user, disabled login, no shell~~ runs as root (see below), unless you are running docker rootless or do some voodoo with userns
* lightweight
  * [x] based on our slim [Debian Bullseye](https://github.com/dubo-dubon-duponey/docker-debian)
  * [x] simple entrypoint script
  * [x] multi-stage build with no installed dependencies for the runtime image
* observable
  * [x] healthcheck
  * [x] log to stdout
  * [ ] ~~prometheus endpoint~~


## Run

```bash
docker run -d \
    --volume /var/lib/docker/containers:/var/lib/docker/containers:ro \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume /var/log/syslog:/var/log/syslog:ro \
    --volume /var/log/auth.log:/var/log/auth.log:ro \
    --env ELASTICSEARCH_HOSTS="[\"elastic:9200\"]" \
    --env KIBANA_HOST="kibana:5601" \
    --env HEALTHCHECK_DOMAIN="elastic" \
    --env HEALTHCHECK_PORT="9200" \
    --user root \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/filebeat
```

## Notes

### Custom configuration file

If you want to customize your FileBeat config, mount a volume into `/config` on the container and customize `/config/filebeat.yml`.

```bash
chown -R 1000:nogroup "[host_path_for_config]"

docker run -d \
    --volume [host_path_for_config]:/config/filebeat.yml \
    --volume /var/lib/docker/containers:/var/lib/docker/containers:ro \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume /var/log/syslog:/var/log/syslog:ro \
    --volume /var/log/auth.log:/var/log/auth.log:ro \
    --env ELASTICSEARCH_HOSTS="[\"elastic:9200\"]" \
    --env KIBANA_HOST="kibana:5601" \
    --env HEALTHCHECK_DOMAIN="elastic" \
    --env HEALTHCHECK_PORT="9200" \
    --user root \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/filebeat
```

Note that `/config` has to be writable in order for enabling modules to work.
If this is not acceptable, set the `MODULES=""` and make sure the modules you want are enabled otherwise.

### Networking

This container doesn't expose any port and only needs egress to the Kibana and Elastic hosts (and the networking mode is irrelevant).


### Configuration reference

The default setup uses a CoreDNS config file in `/config/filebeat.yml`.

This configuration enables "hints" on docker containers, and enables the `coredns` and `system` modules.

You can then simply "label" the appropriate container to hint to the right module to use.

For CoreDNS specifically, you should start your CoreDNS container with the following labels:

```
co.elastic.logs/enabled=true
co.elastic.logs/module=coredns
co.elastic.logs/fileset=log
```

 * the `/config` folder holds the configuration file and modules specific configuration
 * the `/data` folder is used to store FileBeat state

#### Runtime

You may specify the following environment variables at runtime:

 * `ELASTICSEARCH_HOSTS`
 * `KIBANA_HOST`
 * `ELASTICSEARCH_USERNAME`
 * `ELASTICSEARCH_PASSWORD`
 * `MODULES` (by default: `coredns system`)

Finally, any additional arguments provided when running the image will get fed to the `coredns` binary.

### On permissions

The in-container user needs to be able to read `/var/run/docker.sock` and 
`/var/lib/docker/containers` to be useful (optionally `/var/log/*` a well).

Unless you run docker rootless, that unfortunately means the container must run with `--user root` - or at least UID 0 - although no CAP are required.

## Moar?

See [DEVELOP.md](DEVELOP.md)
