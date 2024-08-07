FROM docker.io/library/debian:bookworm@sha256:45f2e735295654f13e3be10da2a6892c708f71a71be845818f6058982761a6d3 AS build-journalctl

ENV DEBIAN_FRONTEND=noninteractive

# renovate: datasource=github-tags depName=systemd/systemd
ARG SYSTEMD_VERSION=v255

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
 && ./configure -Dmode=release -Dlink-journalctl-shared=false -Dstandalone-binaries=true \
                -Dzstd=enabled \
                --buildtype release --prefer-static \
 && ninja -C build journalctl \
 && mv build/journalctl /bin/journalctl \
 && apt-get autopurge --yes \
 && apt-get clean --yes \
 && cd / \
 && rm -rf /tmp/systemd

# FROM docker.io/otel/opentelemetry-collector-contrib:0.103.1@sha256:19a8facab166afc9b5b46bd27040430906cc7d1525ee1fa3f77a62bf97ae8be5 AS prep
FROM docker.io/library/golang:1.22.6@sha256:2bd56f00ff47baf33e64eae7996b65846c7cb5e0a46e0a882ef179fd89654afa AS build-otelcol

ENV DEBIAN_FRONTEND=noninteractive

# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG TARGET_VERSION=0.103.1

ADD manifest.yaml /tmp

RUN set -e \
 && cd /tmp \
 && curl --proto '=https' --tlsv1.2 --silent -fL -o ocb \
    https://github.com/open-telemetry/opentelemetry-collector/releases/download/cmd%2Fbuilder%2Fv${TARGET_VERSION}/ocb_${TARGET_VERSION}_linux_amd64 \
 && chmod +x ocb \
 && curl --proto '=https' --tlsv1.2 --silent -fL -o manifest-k8s.yaml \
    https://github.com/open-telemetry/opentelemetry-collector-releases/raw/v${TARGET_VERSION}/distributions/otelcol-k8s/manifest.yaml \
 && OTELCOL_VERSION="$(awk '$1 == "otelcol_version:" { print $2 }' manifest-k8s.yaml )" \
 && sed -i -e "s/##TARGET_VERSION##/${TARGET_VERSION}/;s/##OTELCOL_VERSION##/${OTELCOL_VERSION}/;" manifest.yaml \
 && ./ocb --config manifest.yaml \
 && rm -r otelcol-distribution* 

FROM docker.io/library/debian:bookworm-slim@sha256:5f7d5664eae4a192c2d2d6cb67fc3f3c7891a8722cd2903cc35aa649a12b0c8d

COPY --from=build-journalctl /bin/journalctl /bin/journalctl

ARG USER_UID=10001
USER ${USER_UID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /

ENTRYPOINT ["/otelcol-k8s-custom"]
