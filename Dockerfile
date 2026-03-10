# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG OTELCOL_VERSION=v0.147.0

### Build manifest
FROM docker.io/library/python:3.14.3-alpine@sha256:faee120f7885a06fcc9677922331391fa690d911c020abb9e8025ff3d908e510 AS manifest
ARG OTELCOL_VERSION

WORKDIR /build 
COPY requirements.txt ./
RUN set -e \
 && PIP_DISABLE_PIP_VERSION_CHECK=1 \
    pip install --no-cache-dir --root-user-action ignore -r requirements.txt
COPY manifest-template.yaml merge.py ./
RUN python merge.py --version ${OTELCOL_VERSION#v} >manifest.yaml

### Build otelcol-k8s-custom
FROM docker.io/library/golang:1.26.1@sha256:e2ddb153f786ee6210bf8c40f7f35490b3ff7d38be70d1a0d358ba64225f6428 AS build-otelcol
ARG OTELCOL_VERSION

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp
COPY --from=manifest /build/manifest.yaml ./

RUN set -e \
 && go install go.opentelemetry.io/collector/cmd/builder@v${OTELCOL_VERSION#v} \
 && builder --config manifest.yaml \
 && rm -r otelcol-distribution* 

FROM scratch

ARG USER_UID=10001
ARG USER_GID=10001
USER ${USER_UID}:${USER_GID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol --chmod=755 /tmp/_build/otelcol-k8s-custom  /otelcol

ENTRYPOINT ["/otelcol"]
