FROM docker.io/library/debian:bookworm@sha256:b37bc259c67238d814516548c17ad912f26c3eed48dd9bb54893eafec8739c89 AS build

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

FROM docker.io/otel/opentelemetry-collector-contrib:0.99.0@sha256:42d938c88a19388fc6a37dca64a3643874aba92b88df8ca985eeda3421c8cc80 AS prep

FROM docker.io/library/debian:bookworm-slim@sha256:3d5df92588469a4c503adbead0e4129ef3f88e223954011c2169073897547cac

COPY --from=build /bin/journalctl /bin/journalctl

ARG USER_UID=10001
USER ${USER_UID}

COPY --from=prep /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=prep /etc/otelcol-contrib /etc/otelcol-contrib
COPY --from=prep /otelcol-contrib  /
EXPOSE 4317 55678 55679
ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config", "/etc/otelcol-contrib/config.yaml"]
