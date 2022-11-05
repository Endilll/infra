#!/bin/bash

set -exuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

env EXTRA_NFS_ARGS=",ro" "${DIR}/setup-common.sh"

apt-get -y update
apt-get -y install software-properties-common
dpkg --add-architecture i386
curl -s https://dl.winehq.org/wine-builds/winehq.key | apt-key add -
# TODO at some point see if we can upgrade wine
apt-add-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ bionic main'
apt-get install -y \
    binutils-multiarch \
    bison \
    bzip2 \
    cgroup-tools \
    curl \
    dos2unix \
    file \
    flex \
    g++ \
    gawk \
    gcc \
    gnat \
    jq \
    libapparmor-dev \
    libc6-dev-i386 \
    libdatetime-perl \
    libelf-dev \
    libgmp3-dev \
    libprotobuf-dev \
    libnl-route-3-dev \
    libwww-perl \
    linux-libc-dev \
    make \
    nfs-common \
    nginx \
    patch \
    pkg-config \
    protobuf-compiler \
    python3-pip \
    python3.8-venv \
    s3cmd \
    subversion \
    texinfo \
    unzip \
    wget \
    winehq-stable=4.0.3~bionic \
    wine-stable=4.0.3~bionic \
    wine-stable-amd64=4.0.3~bionic \
    wine-stable-i386=4.0.3~bionic \
    xz-utils

pushd /tmp
git clone https://github.com/apmorton/firejail.git firejail-apmorton
cd firejail-apmorton
git checkout 0.9.58.2-ce-patch.1
./configure --enable-apparmor --prefix /usr/local/firejail-0.9.58.2-ce-patch.1
make "-j$(nproc)"
make install
popd

ln -s /usr/local/firejail-0.9.58.2-ce-patch.1/bin/firejail /usr/local/bin

pushd /tmp
git clone https://github.com/netblue30/firejail.git
cd firejail
git checkout 0.9.70
./configure --enable-apparmor --prefix /usr/local/firejail-0.9.70
make "-j$(nproc)"
make install
popd

pushd /tmp
git clone --recursive --branch 3.0 https://github.com/google/nsjail.git
cd nsjail
make "-j$(nproc)"
cp nsjail /usr/local/bin/nsjail
popd


pushd /opt
# node.js
TARGET_NODE_VERSION=v16.17.1
echo "Installing node ${TARGET_NODE_VERSION}"
curl -sL "https://nodejs.org/dist/${TARGET_NODE_VERSION}/node-${TARGET_NODE_VERSION}-linux-x64.tar.xz" | tar xJf - && mv node-${TARGET_NODE_VERSION}-linux-x64 node
popd

cp nginx/nginx-gpu.conf /etc/nginx/nginx.conf
systemctl restart nginx

cp /infra/init/compiler-explorer.service /lib/systemd/system/compiler-explorer.service
systemctl daemon-reload
systemctl enable compiler-explorer

adduser --system --group ce

# setup nvidia drivers https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#runfile-nouveau-ubuntu

pushd /tmp
wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_520.61.05_linux.run
sh cuda_11.8.0_520.61.05_linux.run --silent --driver
popd

echo -e "blacklist nouveau\noptions nouveau modeset=0\n" > /etc/modprobe.d/blacklist-nouveau.conf
update-initramfs -u

# script from https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#runfile-verifications

/sbin/modprobe nvidia

if [ "$?" -eq 0 ]; then
  # Count the number of NVIDIA controllers found.
  NVDEVS=`lspci | grep -i NVIDIA`
  N3D=`echo "$NVDEVS" | grep "3D controller" | wc -l`
  NVGA=`echo "$NVDEVS" | grep "VGA compatible controller" | wc -l`

  N=`expr $N3D + $NVGA - 1`
  for i in `seq 0 $N`; do
    mknod -m 666 /dev/nvidia$i c 195 $i
  done

  mknod -m 666 /dev/nvidiactl c 195 255

else
  exit 1
fi

/sbin/modprobe nvidia-uvm

if [ "$?" -eq 0 ]; then
  # Find out the major device number used by the nvidia-uvm driver
  D=`grep nvidia-uvm /proc/devices | awk '{print $1}'`

  mknod -m 666 /dev/nvidia-uvm c $D 0
else
  exit 1
fi

# /dev/nvidia-modeset
/bin/nvidia-modprobe -m