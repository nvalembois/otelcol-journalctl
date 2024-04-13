FROM docker.io/library/debian:bookworm AS build

ENV DEBIAN_FRONTEND=noninteractive

# renovate: datasource=github-tags depName=systemd/systemd
ARG SYSTEMD_VERSION=v255

RUN set -e \
 && apt-get update \
 && apt-get install --yes --mark-auto git python3-venv \
            gcc g++ libc6-dev gperf pkg-config libbpf-dev libmount-dev libcap-dev \
 && cd /tmp \
 && git clone --depth 1 --branch ${SYSTEMD_VERSION} https://github.com/systemd/systemd.git \
 && cd systemd \
 && export PATH=${PATH}:/root/.local/bin \
 && python3 -m venv venv && . ./venv/bin/activate \
 && pip install -r .github/workflows/requirements.txt --require-hashes \
 && pip install jinja2 \
 && ./configure -Dmode=release -Dlink-journalctl-shared=false -Dstandalone-binaries=true \
                --buildtype release --prefer-static \
 && ninja -C build journalctl \
 && mv build/journalctl /bin/journalctl \
 && apt-get autopurge --yes \
 && apt-get clean --yes \
 && cd / \
 && rm -rf /tmp/systemd

FROM docker.io/otel/opentelemetry-collector-contrib:0.98.0 AS prep

FROM docker.io/library/debian:bookworm-slim

COPY --from=build /bin/journalctl /bin/journalctl

ARG USER_UID=10001
USER ${USER_UID}

COPY --from=prep /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=prep /etc/otelcol-contrib /etc/otelcol-contrib
COPY --from=prep /otelcol-contrib  /
EXPOSE 4317 55678 55679
ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config", "/etc/otelcol-contrib/config.yaml"]
