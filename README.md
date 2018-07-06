## つかいかた

~~~sh
git clone http://magi2.ssc-otemachi.ocn.ad.jp:10080/ruby-vim/hacluster.git
vagrant plugin install vagrant-libvirt
vagrant up
~~~

pacemaker, corosyncが動いた状態で立ち上がります。


## ログイン

~~~sh
vagrant ssh node-1 # node-1向け
vagrant ssh node-2 # node-2向け
~~~
