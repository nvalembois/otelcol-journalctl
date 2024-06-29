FROM docker.io/library/debian:bookworm@sha256:a92ed51e0996d8e9de041ca05ce623d2c491444df6a535a566dabd5cb8336946 AS build-journalctl

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
FROM docker.io/library/golang:1.22.4@sha256:a66eda637829ce891e9cf61ff1ee0edf544e1f6c5b0e666c7310dce231a66f28 AS build-otelcol

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

FROM docker.io/library/debian:bookworm-slim@sha256:67f3931ad8cb1967beec602d8c0506af1e37e8d73c2a0b38b181ec5d8560d395

COPY --from=build-journalctl /bin/journalctl /bin/journalctl

ARG USER_UID=10001
USER ${USER_UID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/_build/otelcol-k8s-custom  /
EXPOSE 4317 55678 55679
ENTRYPOINT ["/otelcol-k8s-custom"]
