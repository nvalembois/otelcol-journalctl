# renovate: datasource=github-tags depName=open-telemetry/opentelemetry-collector-releases
ARG OTELCOL_VERSION=v0.150.1
ARG USER_NAME=nonroot
ARG USER_UID=65532
ARG GROUP_NAME=$USER_NAME
ARG GROUP_UID=$USER_UID

### Build manifest
FROM docker.io/library/python:3.14.4-alpine@sha256:dd4d2bd5b53d9b25a51da13addf2be586beebd5387e289e798e4083d94ca837a AS manifest

ARG OTELCOL_VERSION

WORKDIR /tmp 

COPY manifest-template.yaml scripts/requirements.txt scripts/merge.py ./

RUN set -e \
 && PIP_DISABLE_PIP_VERSION_CHECK=1 \
    pip install --no-cache-dir --root-user-action ignore -r requirements.txt \
 && python merge.py --version ${OTELCOL_VERSION#v} >manifest.yaml

### Build otelcol-k8s-custom
FROM docker.io/library/golang:1.26.2-alpine@sha256:f85330846cde1e57ca9ec309382da3b8e6ae3ab943d2739500e08c86393a21b1 AS build-otelcol

ARG OTELCOL_VERSION
ARG USER_NAME
ARG USER_UID
ARG GROUP_NAME
ARG GROUP_UID

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

COPY --from=manifest /tmp/manifest.yaml ./

# build otelcol
RUN set -e \
 && go install go.opentelemetry.io/collector/cmd/builder@v${OTELCOL_VERSION#v} \
 && builder --config manifest.yaml \
 && rm -r otelcol-distribution* 

# create minimal passwd/group for scratch image
RUN set -e \
 && addgroup -Sg $GROUP_UID $GROUP_NAME \
 && adduser -SHDg 'non root user' -h '/' \
      -u $USER_UID -G $GROUP_NAME $USER_NAME \
 && getent passwd root $USER_NAME nobody > passwd \
 && echo '-- passwd --' && cat passwd \
 && getent group root $GROUP_NAME nobody > group \
 && echo '-- group --' && cat group

### Build image
FROM scratch

ARG USER_UID
ARG GROUP_UID

USER ${USER_UID}:${GROUP_UID}

COPY --from=build-otelcol /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build-otelcol /tmp/passwd /etc/group /etc/
COPY --from=build-otelcol --chmod=755 /tmp/_build/otelcol-k8s-custom  /otelcol

ENTRYPOINT ["/otelcol"]
