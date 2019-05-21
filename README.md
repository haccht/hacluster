## つかいかた
QEMU/KVM上で動かすことを前提とした検証構成です。  

~~~sh
git clone http://magi2.ssc-otemachi.ocn.ad.jp:10080/ruby-vim/hacluster.git
cd hacluster
vagrant plugin install vagrant-libvirt
vagrant up
~~~

vagrant-libvirtはユーザ毎にインストールが必要です。
`vagrant up`後に数分待つと、pacemaker/corosyncでHA構成を組んだnode-1, node-2およびhostpcが起動します。
VirtualIP, DRBD, NFSリソースが利用可能です。


## ログイン

~~~sh
vagrant ssh node-1 # node-1向け
vagrant ssh node-2 # node-2向け
~~~
