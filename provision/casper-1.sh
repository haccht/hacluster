#! /bin/sh
set -x
setenforce 0

## hosts
sed -i '/127.0.0.1\s*capser-1\s.*/d' /etc/hosts
sed -i '/127.0.0.1\s*capser-2\s.*/d' /etc/hosts
echo 192.168.99.31 capser-1 >> /etc/hosts
echo 192.168.99.32 capser-2 >> /etc/hosts
echo 192.168.99.33 casper  >> /etc/hosts
export no_proxy=$no_proxy,capser-1,capser-2

## download packages
yum -y install yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
#rpm -Uvh /vagrant/elrepo-release-7.0-3.el7.elrepo.noarch.rpm

yum -y install \
  kmod-drbd90-9.0.14-1.el7_5.elrepo drbd90-utils-9.3.1-1.el7.elrepo \
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
  on capser-1 {
    address 192.168.99.31:7788;
  }
  on capser-2 {
    address 192.168.99.32:7788;
  }
}
EOL

drbdadm create-md r0
drbdadm up r0

while :; do
  sleep 1
  nc -z capser-2 5678
  [[ $? -eq 0 ]] && break
done
drbdadm primary --force r0

mkdir -p /mnt/drbd
mkfs.xfs -f /dev/drbd0
mount /dev/drbd0 /mnt/drbd

## corosync
mv /dev/random{,.bak}
ln -sf /dev/urandom /dev/random
corosync-keygen
mv /dev/random{.bak,}
while :; do
  sleep 1
  nc -z capser-2 5678
  [[ $? -eq 0 ]] && break
done
sleep 1
cat /etc/corosync/authkey /vagrant/tmp/authkey | nc capser-2 5678

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

cat << EOL > /etc/corosync/service.d/pcmk
service {
  name: pacemaker
  ver: 1
}
EOL

## mariadb
mkdir -p /mnt/drbd/mysql
mysql_install_db --no-defaults --datadir=/mnt/drbd/mysql --user=mysql
chown -R mysql.mysql /mnt/drbd/mysql

# nfs
mkdir /mnt/drbd/nfslib
mkdir /mnt/drbd/nfsroot

## nginx
systemctl start nginx

## docker
systemctl start docker
usermod -aG docker vagrant

## pacemaker
service pcsd start
echo hacluster | passwd --stdin hacluster

while :; do
  nc -z capser-2 5678
  [[ $? -eq 0 ]] && break
done

pcs cluster auth capser-1 capser-2 -u hacluster -p hacluster
pcs cluster setup --name caspercluster capser-1 capser-2 --force
sleep 30
pcs cluster start capser-1 capser-2

while true; do
  pcs status | grep 'Online: \[ capser-1 capser-2 \]' > /dev/null
  if [ $? = 0 ]; then break; else sleep 1; fi
done

pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore
pcs property set start-failure-is-fatal=false
pcs resource defaults migration-threshold=5
pcs resource defaults resource-stickiness=INFINITY
pcs resource defaults failure-timeout=3600s

while true; do
  crm_verify -LV
  if [ $? = 0 ]; then break; else sleep 1; fi
done

pcs status
pcs cluster cib output.cib

pcs -f output.cib resource create drbd ocf:linbit:drbd \
  drbd_resource="r0" drbdconf="/etc/drbd.conf" \
  op start interval="0s" timeout="240s" \
  op stop  interval="0s" timeout="100s" \
  op monitor interval="10s" timeout="20s" role="Master" \
  op monitor interval="20s" timeout="20s" role="Slave"

pcs -f output.cib resource master ms_drbd drbd \
  master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 notify=true

pcs -f output.cib resource create fs ocf:heartbeat:Filesystem \
  device="/dev/drbd0" directory="/mnt/drbd" fstype="xfs" \
  op start timeout="40s" \
  op stop  timeout="40s" \
  op monitor interval="10s" timeout="60s"

pcs -f output.cib resource create vip ocf:heartbeat:IPaddr2 \
  ip="192.168.99.33" cidr_netmask="24" nic="eth1" \
  op start timeout="30s" \
  op stop  timeout="30s" \
  op monitor interval="10s" timeout="20s"

pcs -f output.cib resource create nfs ocf:heartbeat:nfsserver \
  nfs_shared_infodir="/mnt/drbd/nfslib" \
  op start timeout="20s" \
  op stop  timeout="20s" \
  op monitor interval="10s" timeout="10s" on-fail="restart" start-delay="20s"

pcs -f output.cib resource create exportfs ocf:heartbeat:exportfs \
  clientspec="192.168.99.0/24" options="rw,no_root_squash" directory="/mnt/drbd/nfsroot" fsid="root"

pcs -f output.cib resource create mysql ocf:heartbeat:mysql \
  user="mysql" group="mysql" config="/etc/my.cnf" binary="/usr/bin/mysqld_safe" \
  datadir="/mnt/drbd/mysql" pid="/var/run/mariadb/mariadb.pid" socket="/var/lib/mysql/mysql.sock" \
  op start interval="0s" timeout="60s" \
  op stop  interval="0s" timeout="60s" \
  op monitor interval="20s" timeout="30s"

pcs -f output.cib resource group add core fs vip nfs exportfs mysql
pcs -f output.cib constraint colocation add core ms_drbd INFINITY with-rsc-role=Master
pcs -f output.cib constraint order promote ms_drbd then start core
pcs cluster cib-push output.cib

sleep 30
pcs status

while :; do
  nc -z capser-2 5678
  [[ $? -eq 0 ]] && break
done

mkdir -p /exports
mount -t nfs casper:/mnt/drbd/nfsroot /exports -o rw,rsize=8192,wsize=8192,soft,intr,timeo=20,retrans=3
