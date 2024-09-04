### Build Journalctl
FROM docker.io/library/debian:bookworm@sha256:aadf411dc9ed5199bc7dab48b3e6ce18f8bbee4f170127f5ff1b75cd8035eb36 AS build-journalctl
# renovate: datasource=github-tags depName=systemd/systemd
ARG SYSTEMD_VERSION=v256.5

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

### Build custom-manifest.yaml
FROM docker.io/library/python:3.12.5-alpine3.20@sha256:aeff64320ffb81056a2afae9d627875c5ba7d303fb40d6c0a43ee49d8f82641c AS build-manifest
# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG TARGET_VERSION=0.108.0

ADD manifest.yaml merge.py /
ADD https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-releases/v${TARGET_VERSION}/distributions/otelcol-k8s/manifest.yaml /otelcol-k8s-manifest.yaml
ADD https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-releases/v${TARGET_VERSION}/distributions/otelcol-contrib/manifest.yaml /otelcol-contrib-manifest.yaml

WORKDIR /
RUN set -e && \
  pip install pyyaml && \
  python merge.py > custom-manifest.yaml

### Build otelcol-k8s-custom
FROM docker.io/library/golang:1.23.0@sha256:613a108a4a4b1dfb6923305db791a19d088f77632317cfc3446825c54fb862cd AS build-otelcol
# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG TARGET_VERSION=0.108.0

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=build-manifest /custom-manifest.yaml /tmp/custom-manifest.yaml

WORKDIR /tmp
RUN set -e \
 && go install go.opentelemetry.io/collector/cmd/builder@v${TARGET_VERSION} \
 && builder --config custom-manifest.yaml \
 && rm -r otelcol-distribution* 

 ### Build image
FROM docker.io/library/debian:bookworm-slim@sha256:2ccc7e39b0a6f504d252f807da1fc4b5bcd838e83e4dec3e2f57b2a4a64e7214
ARG USER_UID=10001

COPY --from=build-journalctl /bin/journalctl /bin/journalctl

USER ${USER_UID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /

ENTRYPOINT ["/otelcol-k8s-custom"]
