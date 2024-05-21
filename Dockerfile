FROM docker.io/library/debian:bookworm@sha256:fac2c0fd33e88dfd3bc88a872cfb78dcb167e74af6162d31724df69e482f886c AS build

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

FROM docker.io/otel/opentelemetry-collector-contrib:0.101.0@sha256:070f6031c3310b7a6705e2c30bb9db4ad710a72e189f133d7392f38a7a54806d AS prep

FROM docker.io/library/debian:bookworm-slim@sha256:804194b909ef23fb995d9412c9378fb3505fe2427b70f3cc425339e48a828fca

COPY --from=build /bin/journalctl /bin/journalctl

ARG USER_UID=10001
USER ${USER_UID}

COPY --from=prep /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=prep /etc/otelcol-contrib /etc/otelcol-contrib
COPY --from=prep /otelcol-contrib  /
EXPOSE 4317 55678 55679
ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config", "/etc/otelcol-contrib/config.yaml"]
