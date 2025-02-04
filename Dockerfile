### Build Journalctl
FROM docker.io/library/debian:bookworm@sha256:4abf773f2a570e6873259c4e3ba16de6c6268fb571fd46ec80be7c67822823b3 AS build-journalctl
# renovate: datasource=github-tags depName=systemd/systemd
ARG SYSTEMD_VERSION=v257.2

ENV DEBIAN_FRONTEND=noninteractive
RUN set -e \
 && apt-get update \
 && apt-get install --yes --mark-auto git python3-venv \
            gcc g++ libc6-dev gperf pkg-config libbpf-dev libmount-dev libcap-dev libzstd-dev \
 && cd /tmp \
 && git clone --depth 1 --branch ${SYSTEMD_VERSION} https://github.com/systemd/systemd.git \
 && cd systemd \
 && export PATH=${PATH}:/root/.local/bin \
 && python3 -m venv venv && . ./venv/bin/activate \
 && pip install -r .github/workflows/requirements.txt --require-hashes \
 && pip install jinja2 \
 && meson setup -Dmode=release -Dlink-journalctl-shared=false -Dstandalone-binaries=true \
                -Dzstd=enabled \
                --buildtype release --prefer-static build \
 && ninja -C build journalctl \
 && mv build/journalctl /bin/journalctl \
 && apt-get autopurge --yes \
 && apt-get clean --yes \
 && cd / \
 && rm -rf /tmp/systemd

### Build otelcol-k8s-custom
FROM docker.io/library/golang:1.23.5@sha256:8c10f21bec412f08f73aa7b97ca5ac5f28a39d8a88030ad8a339fd0a781d72b4 AS build-otelcol
# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG OTELCOL_VERSION=0.118.0

ENV DEBIAN_FRONTEND=noninteractive

COPY manifest-${OTELCOL_VERSION}.yaml /tmp/manifest.yaml

WORKDIR /tmp
RUN set -e \
 && go install go.opentelemetry.io/collector/cmd/builder@v${OTELCOL_VERSION%.*} \
 && builder --config manifest.yaml \
 && rm -r otelcol-distribution* 

 ### Build image
FROM docker.io/library/debian:bookworm-slim@sha256:40b107342c492725bc7aacbe93a49945445191ae364184a6d24fedb28172f6f7
ARG USER_UID=10001

COPY --from=build-journalctl /bin/journalctl /bin/journalctl

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /

USER ${USER_UID}

ENTRYPOINT ["/otelcol-k8s-custom"]
