#!/bin/sh

echo "${1}" > VERSION
sed -i -e "/^ENV VERSION=.*/s/.*/ENV VERSION=${1}/" Dockerfile
sed -i -e "/org.opencontainers.image.version=.*/s/.*/LABEL org.opencontainers.image.version=${1}/" Dockerfile
