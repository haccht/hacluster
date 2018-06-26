#! /bin/sh
set -x

echo 192.168.99.33 casper >> /etc/hosts

## download packages
yum -y install yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

yum -y install nfs-utils docker-ce-17.03.2.ce  docker-ce-selinux-17.03.2.ce \
  --setopt=obsoletes=0 --skip-broken

# docker
systemctl start docker
usermod -aG docker vagrant

# nfs
mkdir -p /mnt/nfs
#mount -t nfs casper:/mnt/drbd/nfsroot /mnt/nfs -o rw,rsize=8192,wsize=8192,soft,intr,timeo=20,retrans=3
