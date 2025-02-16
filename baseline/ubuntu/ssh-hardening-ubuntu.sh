#!/bin/bash
sshuser="user" # User that will connect via ssh
domain="example.com" # Domain to restrict SSH access to
iprestrict="yes" # Set to yes to allow IP restrictions

apt-get -y install libpam-google-authenticator dnsutils

su "$sshuser" -P -c 'google-authenticator' # Answer y y y n y for a recommended setup

echo "auth required pam_google_authenticator.so" >>/etc/pam.d/sshd
echo "auth required pam_permit.so" >>/etc/pam.d/sshd
sed -i -e "s/@include\ common-auth/\#@include\ common-auth/g" /etc/pam.d/sshd

sed -i -e "\
  s/ChallengeResponseAuthentication.*/ChallengeResponseAuthentication\ yes/g; \
  s/AuthenticationMethods.*/AuthenticationMethods\ publickey,keyboard-interactive/g" \
/etc/ssh/sshd_config

if [[ "$iprestrict" = "yes" ]]; then
  cat ./Configs/ssh-allowed.sh >/usr/local/bin/ssh-allowed.sh
  chmod +x /usr/local/bin/ssh-allowed.sh
  sed -i -e "s/domain=.*/domain=\"""$domain""\"/g" /usr/local/bin/ssh-allowed.sh
  echo '*/10 * * * * root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/ssh-allowed.sh >/dev/null 2>&1' >/etc/cron.d/ssh-allowed
  echo '@reboot root PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\" /usr/local/bin/ssh-allowed.sh >/dev/null 2>&1' >/etc/cron.d/ssh-allowed-reboot
fi

systemctl restart ssh