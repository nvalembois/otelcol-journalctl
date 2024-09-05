### Build Journalctl
FROM docker.io/library/debian:bookworm@sha256:b8084b1a576c5504a031936e1132574f4ce1d6cc7130bbcc25a28f074539ae6b AS build-journalctl
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
FROM docker.io/library/golang:1.23.0@sha256:1a6db32ea47a4910759d5bcbabeb8a8b42658e311bd8348ea4763735447c636c AS build-otelcol
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
FROM docker.io/library/debian:bookworm-slim@sha256:a629e796d77a7b2ff82186ed15d01a493801c020eed5ce6adaa2704356f15a1c
ARG USER_UID=10001

COPY --from=build-journalctl /bin/journalctl /bin/journalctl

USER ${USER_UID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /

ENTRYPOINT ["/otelcol-k8s-custom"]
