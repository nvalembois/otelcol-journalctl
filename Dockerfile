FROM docker.io/library/debian:bookworm@sha256:1aadfee8d292f64b045adb830f8a58bfacc15789ae5f489a0fedcd517a862cb9 AS build

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

FROM docker.io/otel/opentelemetry-collector-contrib:0.100.0@sha256:cea61bd39d318b3ec7664794f6be9ed0cce9321059a08b4ec5d3b8d310a4b609 AS prep

FROM docker.io/library/debian:bookworm-slim@sha256:155280b00ee0133250f7159b567a07d7cd03b1645714c3a7458b2287b0ca83cb

COPY --from=build /bin/journalctl /bin/journalctl

ARG USER_UID=10001
USER ${USER_UID}

COPY --from=prep /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=prep /etc/otelcol-contrib /etc/otelcol-contrib
COPY --from=prep /otelcol-contrib  /
EXPOSE 4317 55678 55679
ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config", "/etc/otelcol-contrib/config.yaml"]
