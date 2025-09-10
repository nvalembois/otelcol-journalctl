### Build Journalctl
# FROM docker.io/library/debian:bookworm@sha256:35286826a88dc879b4f438b645ba574a55a14187b483d09213a024dc0c0a64ed AS build-journalctl
# # renovate: datasource=github-tags depName=systemd/systemd
# ARG SYSTEMD_VERSION=v257.4

# ENV DEBIAN_FRONTEND=noninteractive
# RUN set -e \
#  && apt-get update \
#  && apt-get install --yes --mark-auto git python3-venv \
#             gcc g++ libc6-dev gperf pkg-config libbpf-dev libmount-dev libcap-dev libzstd-dev \
#  && cd /tmp \
#  && git clone --depth 1 --branch ${SYSTEMD_VERSION} https://github.com/systemd/systemd.git \
#  && cd systemd \
#  && export PATH=${PATH}:/root/.local/bin \
#  && python3 -m venv venv && . ./venv/bin/activate \
#  && pip install -r .github/workflows/requirements.txt --require-hashes \
#  && pip install jinja2 \
#  && meson setup -Dmode=release -Dlink-journalctl-shared=false -Dstandalone-binaries=true \
#                 -Dzstd=enabled \
#                 --buildtype release --prefer-static build \
#  && ninja -C build journalctl \
#  && mv build/journalctl /bin/journalctl \
#  && apt-get autopurge --yes \
#  && apt-get clean --yes \
#  && cd / \
#  && rm -rf /tmp/systemd

### Build otelcol-k8s-custom
FROM docker.io/library/golang:1.25.1@sha256:1fd7d46f956287d1856b92add5cc5ab8b87c07a1ed766419bb603a8620746b4a AS build-otelcol
# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG OTELCOL_VERSION=0.135.0

ENV DEBIAN_FRONTEND=noninteractive

COPY manifest-${OTELCOL_VERSION}.yaml /tmp/manifest.yaml

WORKDIR /tmp
RUN set -e \
 && go install go.opentelemetry.io/collector/cmd/builder@v${OTELCOL_VERSION%.*} \
 && builder --config manifest.yaml \
 && rm -r otelcol-distribution* 

 ### Build image
# FROM docker.io/library/debian:bookworm-slim@sha256:12c396bd585df7ec21d5679bb6a83d4878bc4415ce926c9e5ea6426d23c60bdc as full
# ARG USER_UID=10001 

# COPY --from=build-journalctl /bin/journalctl /bin/journalctl

# COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
# COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /

# USER ${USER_UID}

# ENTRYPOINT ["/otelcol-k8s-custom"]

FROM scratch

ARG USER_UID=10001
ARG USER_GID=10001
USER ${USER_UID}:${USER_GID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol --chmod=755 /tmp/_build/otelcol-k8s-custom  /otelcol

ENTRYPOINT ["/otelcol"]
