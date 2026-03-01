#!/bin/bash

set -e

BASH_VERSION="5.3"

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

OUTPUT="$MY_HOME/bash-portable"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
OUTPUT="${OUTPUT}.${BASH_VERSION}.${OS}.${ARCH}"

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

curl -L --silent --fail https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz | tar xz
cd bash-*
LDFLAGS="-static" ./configure --prefix=$DIR_INSTALL/bash --without-bash-malloc
make -j8
make tests
make install-strip

cp -f "$DIR_INSTALL/bash/bin/bash" "$OUTPUT"
chown "${EUID}:${EGID}" "$OUTPUT"
chmod +x "$OUTPUT"
