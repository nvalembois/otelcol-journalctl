### Build Journalctl
FROM docker.io/library/debian:bookworm@sha256:321341744acb788e251ebd374aecc1a42d60ce65da7bd4ee9207ff6be6686a62 AS build-journalctl
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
FROM docker.io/library/golang:1.23.4@sha256:585103a29aa6d4c98bbb45d2446e1fdf41441698bbdf707d1801f5708e479f04 AS build-otelcol
# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG OTELCOL_VERSION=0.117.0

ENV DEBIAN_FRONTEND=noninteractive

COPY manifest-${OTELCOL_VERSION}.yaml /tmp/manifest.yaml

WORKDIR /tmp
RUN set -e \
 && go install go.opentelemetry.io/collector/cmd/builder@v${OTELCOL_VERSION%.*} \
 && builder --config manifest.yaml \
 && rm -r otelcol-distribution* 

 ### Build image
FROM docker.io/library/debian:bookworm-slim@sha256:f70dc8d6a8b6a06824c92471a1a258030836b26b043881358b967bf73de7c5ab
ARG USER_UID=10001

COPY --from=build-journalctl /bin/journalctl /bin/journalctl

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /

USER ${USER_UID}

ENTRYPOINT ["/otelcol-k8s-custom"]
