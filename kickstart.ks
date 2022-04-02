lang en_US.UTF-8
keyboard us
timezone America/New_York
zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
reboot
text
network --bootproto=dhcp --device=link --activate --onboot=on  --hostname=microshift-edge-node

ostreesetup --nogpg --osname=rhel --remote=edge --url=file:///run/install/repo/ostree/repo --ref=rhel/8/x86_64/edge

firewall-cmd --add-port=22/tcp --permanent

%post --log=/var/log/anaconda/post-install.log --erroronfail

echo -e 'url=http://192.168.178.105:8080/repo/' >> /etc/ostree/remotes.d/edge.conf

echo -e 'https://github.com/redhat-et/microshift-config?ref=${uuid}' > /etc/transmission-url

useradd -m -d /home/someuser -p \$5\$XDVQ6DxT8S5YWLV7\$8f2om5JfjK56v9ofUkUAwZXTxJl3Sqnc9yPnza4xoJ0 -G wheel someuser

# to add a ssh key uncomment and supply a public key
# mkdir -p /home/redhat/.ssh
# chmod 755 /home/redhat/.ssh
# tee /home/redhat/.ssh/authorized_keys > /dev/null << EOF
# ssh-rsa <key> foo@bar
# EOF
# echo -e 'redhat\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers
