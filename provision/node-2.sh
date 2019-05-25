#! /bin/sh
set -x
setenforce 0

## hosts
sed -i '/127.0.0.1\s*node/d' /etc/hosts
echo 192.168.99.31 node-1 >> /etc/hosts
echo 192.168.99.32 node-2 >> /etc/hosts
echo 192.168.99.33 node   >> /etc/hosts
export no_proxy=$no_proxy,node-1,node-2

## download packages
yum -y install yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm

yum -y install \
  kmod-drbd90-9.0.16-1.el7_6.elrepo drbd90-utils-9.6.0-1.el7.elrepo
  pcs corosync pacemaker curl nmap-ncat mariadb-server mariadb-devel nginx nfs-utils \
  device-mapper-persistent-data lvm2 docker-ce-17.03.2.ce  docker-ce-selinux-17.03.2.ce \
  --setopt=obsoletes=0 --skip-broken

## disks and volumes
( echo n; echo p; echo 1; echo ; echo ; echo t; echo 8e; echo w; ) | fdisk /dev/vdb
( echo n; echo p; echo 1; echo ; echo ; echo t; echo 8e; echo w; ) | fdisk /dev/vdc

### pre-defined volume group name is 'VolGroup00'
pvcreate /dev/vdb1 /dev/vdc1
pvdisplay
vgextend VolGroup00 /dev/vdb1
vgextend VolGroup00 /dev/vdc1
vgdisplay
lvcreate --name lv_backup --size 5GB VolGroup00
lvcreate --name lv_home --size 5GB VolGroup00
lvcreate --name lv_res0 --size 5GB VolGroup00
lvdisplay

mkfs.xfs -f /dev/VolGroup00/lv_backup
mkfs.xfs -f /dev/VolGroup00/lv_home

cd /tmp
mkdir /backup
mount /dev/VolGroup00/lv_backup /backup
cp -a /home/vagrant/ /backup
mount /dev/VolGroup00/lv_home /home
cp -a /backup/vagrant/ /home
cd ~

df -h
echo /dev/mapper/VolGroup00-lv_backup /backup xfs defaults 0 0 >> /etc/fstab
echo /dev/mapper/VolGroup00-lv_home /home xfs defaults 0 0 >> /etc/fstab

## drbd90(for centos7)
modprobe drbd
lsmod | grep drbd

cat << EOL > /etc/drbd.d/global_common.conf
global {
  usage-count no;
}
common {
  disk {
    resync-rate 50M;
  }
  net {
    protocol C;
    csums-alg sha1;
    verify-alg sha1;
  }
}
EOL

cat << EOL > /etc/drbd.d/r0.res
resource r0 {
  meta-disk internal;
  device /dev/drbd0;
  disk /dev/VolGroup00/lv_res0;
  on node-1 {
    address 192.168.99.31:7788;
  }
  on node-2 {
    address 192.168.99.32:7788;
  }
}
EOL

drbdadm create-md r0
drbdadm up r0

nc -l -p 5678 -w 300s
drbdadm secondary r0

mkdir -p /mnt/drbd

## corosync
nc -l -p 5678 -w 300s
nc -l -p 5678 > /etc/corosync/authkey
chmod 400 /etc/corosync/authkey

cat << EOL > /etc/corosync/corosync.conf
compatibility: whitetank
aisexec {
  user:  root
  group: root
}
amf {
  mode: disabled
}
totem {
  version: 2
  secauth: off
  threads: 0
  rrp_mode: none
  clear_node_high_bit: yes
  token: 4000
  concensus: 7000
  join: 60
  interface {
    member {
      memberaddr: 192.168.99.31
    }
    member {
      memberaddr: 192.168.99.32
    }
    ringnumber: 0
    bindnetaddr: 192.168.99.0
    mcastport: 5405
    ttl: 1
  }
  transport: udpu
}
logging {
  fileline: off
  to_logfile: yes
  to_syslog: no
  logfile: /var/log/cluster/corosync.log
  debug: off
  timestamp: on
  logger_subsys {
    subsys: AMF
    debug: off
  }
}
quorum {
  provider: corosync_votequorum
  expected_votes: 2
  two_node: 1
}
EOL

mkdir -p /etc/corosync/service.d
cat << EOL > /etc/corosync/service.d/pcmk
service {
  name: pacemaker
  ver: 1
}
EOL

## mariadb
mysql_install_db --user=mysql
systemctl start mariadb
systemctl enable mariadb

## nginx
systemctl start nginx
systemctl enable nginx

# docker
systemctl start docker
systemctl enable docker
usermod -aG docker vagrant

## pacemaker
systemctl start pcsd
systemctl enable pcsd
echo hacluster | passwd --stdin hacluster

nc -l -p 5678 -w 300s

## nfs
mkdir -p /exports
mount -t nfs node:/mnt/drbd/nfsroot /exports -o rw,rsize=8192,wsize=8192,soft,intr,timeo=20,retrans=3

echo 'finish'
