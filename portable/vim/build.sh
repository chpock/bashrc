#!/bin/bash

set -e

VIM_TAG="v9.2.0081"
NCURSES_VERSION="6.6"

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

OUTPUT="$MY_HOME/vim-portable"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
OUTPUT="${OUTPUT}.${VIM_TAG}.${OS}.${ARCH}"

DIR_BUILD="/tmp/build"
DIR_INSTALL="/tmp/install"
DIR_DIST="/tmp/dist"

MUSL_VERSION="1.2.4"

set -x

rm -f "$OUTPUT"

apt-get update
apt-get install -y git make gcc libtool libtool-bin curl

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

curl --silent --fail https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz | tar xz
cd ncurses-*
LDFLAGS="-static" ./configure --prefix=$DIR_INSTALL/ncurses --without-manpages --without-shared
make -j8
make install

cd "$DIR_BUILD"

git clone --depth 1 --branch "$VIM_TAG" https://github.com/vim/vim.git
cd vim/src
LDFLAGS="-static -L$DIR_INSTALL/ncurses/lib" ./configure \
    --prefix=$DIR_INSTALL/vim \
    --enable-multibyte \
    --enable-terminal \
    --without-local-dir \
    --with-tlib=ncursesw
make -j8
#make test
make installvimbin installrtbase installpack

mkdir -p "$DIR_DIST"
cd "$DIR_DIST"
mv "$DIR_INSTALL/vim/bin/vim" .
mv "$DIR_INSTALL/vim/share/vim"/vim* ./vim-runtime
mv "$DIR_INSTALL/ncurses/share/terminfo" .

sed "s/!VIM_VERSION!/$VIM_TAG/g" "$MY_HOME/stub.sh" > "$OUTPUT"
tar zcf - ./* >> "$OUTPUT"

chown "${EUID}:${EGID}" "$OUTPUT"
chmod +x "$OUTPUT"
