FROM alpine:3.14.3

LABEL org.opencontainers.image.title="dns3l smallstep RA"
LABEL org.opencontainers.image.description="A smallstep ACME RA for DNS3L"
LABEL org.opencontainers.image.version=1.0.0

ENV VERSION=1.0.0

ENV PAGER=less

ARG http_proxy
ARG https_proxy
ARG no_proxy

# provided via BuildKit
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# defaults for none BuildKit
ENV _platform=${TARGETPLATFORM:-linux/amd64}
ENV _os=${TARGETOS:-linux}
ENV _arch=${TARGETARCH:-amd64}
ENV _variant=${TARGETVARIANT:-}

ENV STEP="/home/step"
ENV STEPPATH="/home/step"
ENV STEPDEBUG=1

ARG STEPUID=10043
ARG STEPGID=10043

RUN apk --update upgrade && \
    apk add --no-cache \
        ca-certificates curl less bash busybox-extras \
        jq tzdata coreutils openssl \
        mariadb-client libcap && \
    addgroup -g ${STEPGID} step && \
    adduser -D -u ${STEPUID} -G step step && \
    chmod g-s ${STEPPATH} && \
    chown step:step ${STEPPATH} && \
    rm -rf /var/cache/apk/*

# Install Step
#
ENV STEP_VERSION=0.21.0
ENV STEPCA_VERSION=0.21.0
RUN curl -fsSL https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_${_os}_${STEP_VERSION}_${_arch}${_variant}.tar.gz |\
      tar -xO -zf- step_${STEP_VERSION}/bin/step > /usr/bin/step && \
    curl -fsSL https://github.com/smallstep/certificates/releases/download/v${STEPCA_VERSION}/step-ca_${_os}_${STEPCA_VERSION}_${_arch}${_variant}.tar.gz |\
      tar -xO -zf- step-ca_${STEPCA_VERSION}/bin/step-ca > /usr/bin/step-ca && \
    chmod 0755 /usr/bin/step && \
    chmod 0755 /usr/bin/step-ca && \
    setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/step-ca

# Install Mo Mustache
#
ENV MO_VERSION="2.2.0"
RUN curl -fsSL https://github.com/tests-always-included/mo/archive/$MO_VERSION.tar.gz | \
      tar -xO -zf- mo-$MO_VERSION/mo > /mo && \
    chmod 0755 /mo

COPY wait-for-it.sh /wait-for-it.sh
COPY docker-entrypoint.sh /entrypoint.sh

USER step
WORKDIR $STEPPATH

EXPOSE 9443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/step-ca", "/home/step/config/ca.json", "--issuer-password-file", "/home/step/.acme-ra.pass"]
