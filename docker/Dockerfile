FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    gcc make git bc bison flex \
    libssl-dev libncurses-dev libfdt-dev libgnutls28-dev \
    device-tree-compiler u-boot-tools \
    dosfstools e2fsprogs mtools fdisk \
    python3 python3-dev python3-setuptools swig \
    cpio gzip xz-utils bzip2 \
    curl wget ca-certificates rsync \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
