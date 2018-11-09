## つかいかた

~~~sh
git clone http://magi2.ssc-otemachi.ocn.ad.jp:10080/ruby-vim/hacluster.git
cd hacluster
vagrant plugin install vagrant-libvirt
vagrant up
~~~

vagrant-libvirtはユーザ毎にインストールが必要です。
`vagrant up`後に数分待つと、pacemaker, corosyncが動いた状態でVMが立ち上がります。


## ログイン

~~~sh
vagrant ssh node-1 # node-1向け
vagrant ssh node-2 # node-2向け
~~~
