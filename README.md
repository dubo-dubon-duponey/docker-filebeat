# What

A [Filebeat](https://www.elastic.co/products/beats/filebeat) container meant to collect docker logs (with a working coredns module).

## Image features

 * multi-architecture (linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6)
 * based on `debian:buster-slim`
 * no `cap` needed
 * ~~running as a non-root user~~ (unless you are running docker rootless)
 * lightweight (~40MB)

## Run

```bash
docker run -d \
    --volume /var/lib/docker/containers:/var/lib/docker/containers:ro \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume /var/log/syslog:/var/log/syslog:ro \
    --volume /var/log/auth.log:/var/log/auth.log:ro \
    --user root \
    --env ELASTICSEARCH_HOSTS="[\"elastic:9200\"]" \
    --env KIBANA_HOST="kibana:5601" \
    --cap-drop ALL \
    dubodubonduponey/filebeat:v1
```

## Notes

### Permissions

The in-container user needs to be able to read both `/var/run/docker.sock` and 
`/var/lib/docker/containers` to be useful.

Unless you run docker rootless, that unfortunately means the container must run with `--user root` (although no CAP are required).

### Configuration

A default Filebeat config file will be created in `/config/filebeat.yml` (if you didn't mount an existing file) along with other necessary filebeat module files.

This configuration enables "hints" on docker containers.

You can then simply "label" the appropriate container to hint to the right module to use.

For coredns specifically, you should start your coredns container with the following labels:

```
co.elastic.logs/enabled=true
co.elastic.logs/module=coredns
co.elastic.logs/fileset=log
```

### Advanced configuration

#### Runtime

Besides ELASTICSEARCH_HOSTS, KIBANA_HOST and MODULES, you may additionally use the following environment variables:

 * ELASTICSEARCH_USERNAME
 * ELASTICSEARCH_PASSWORD
 * MODULES (by default: "coredns system")

The following container paths may be mounted as volume if intend on modifying filebeat configuration or dataset.

 * /config: contains all configuration and module files for filebeat
 * /data: filebeat will store state in that location

Additionally, OVERWRITE_CONFIG controls whether an existing /config will be overwritten or not (default is not). Similarly, OVERWRITE_DATA.

Finally, any additional arguments when running the image will get fed to the `filebeat` binary.

#### Build time

You can also rebuild the image using the following arguments if you want to map the in-container user to a different UID (default 1000):

 * BUILD_UID
 * BUILD_GID
