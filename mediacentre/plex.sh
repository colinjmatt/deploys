#!/bin/bash
# Install plex (very basic but here for reference)

( cd /tmp || return
wget https://downloads.plex.tv/plex-media-server-new/1.15.2.793-782228f99/redhat/plexmediaserver-1.15.2.793-782228f99.x86_64.rpm
yum install plexmediaserver-1.15.2.793-782228f99.x86_64.rpm  -y )
bash -c "$(wget -qO - https://raw.githubusercontent.com/mrworf/plexupdate/master/extras/installer.sh)"

firewall-cmd --permanent --zone=drop --add-port="32400"/tcp

# Command to ssh tunnel to sign into plex
ssh -L 32400:localhost:32400 $domain
