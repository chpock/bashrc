#!/bin/bash

set -e

GZIP_VERSION="1.14"

# BUILD_DOCKER_IMAGE="dokken/centos-6"
BUILD_DOCKER_IMAGE="public.ecr.aws/ubuntu/ubuntu:26.04"
MY_HOME="$(cd "$(dirname "$0")"; pwd)"
MY_NAME="$(basename "$0")"

if [ ! -e /.dockerenv ]; then
    exec docker run --rm -ti \
        -w /tmp/work \
        -v "${MY_HOME}:/tmp/work" \
        -e EUID="$(id -u)" -e EGID="$(id -g)" \
        "$BUILD_DOCKER_IMAGE" \
        bash "/tmp/work/$MY_NAME"
fi

OUTPUT="$MY_HOME/gzip-portable"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
OUTPUT="${OUTPUT}.${GZIP_VERSION}.${OS}.${ARCH}"

DIR_BUILD="/tmp/build"
DIR_INSTALL="/tmp/install"

MUSL_VERSION="1.2.5"

set -x

rm -f "$OUTPUT"

apt-get update
apt-get install -y make gcc libtool curl

mkdir -p "$DIR_BUILD"
cd "$DIR_BUILD"

curl --silent --fail https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz | tar xz
cd musl-*
./configure --prefix=$DIR_INSTALL/musl --disable-shared
make -j8
make install

CC=$DIR_INSTALL/musl/bin/musl-gcc
export CC

cd "$DIR_BUILD"

curl -L --silent --fail https://ftp.gnu.org/gnu/gzip/gzip-${GZIP_VERSION}.tar.gz | tar xz
cd gzip-*
LDFLAGS="-static" ./configure --prefix=$DIR_INSTALL/gzip
make -j8
make check
make install-strip

cp -f "$DIR_INSTALL/gzip/bin/gzip" "$OUTPUT"
chown "${EUID}:${EGID}" "$OUTPUT"
chmod +x "$OUTPUT"
