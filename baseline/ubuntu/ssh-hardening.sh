#!/bin/bash
sshuser="user" # User that will connect via ssh
apt-get -y install libpam-google-authenticator

su "$sshuser" -P -c 'google-authenticator' # Answer y y y n y for a recommended setup

echo "auth required pam_google_authenticator.so" >>/etc/pam.d/sshd
echo "auth required pam_permit.so" >>/etc/pam.d/sshd
sed -i -e "s/@include\ common-auth/\#@include\ common-auth/g" /etc/pam.d/sshd


sed -i -e "\
  s/ChallengeResponseAuthentication.*/ChallengeResponseAuthentication\ yes/g; \
  s/AuthenticationMethods.*/AuthenticationMethods\ publickey,keyboard-interactive/g" \
/etc/ssh/sshd_config

cat ./Configs/ssh-allowed.sh >/usr/local/bin/ssh-allowed.sh
chmod +x /usr/local/bin/ssh-allowed.sh
echo "*/10 * * * * /usr/locl/bin/ssh-allowed.sh" >/etc/cron.d/ssh-allowed

systemctl restart sshd
