#!/bin/bash -x


if [[ -z ${SES_USERNAME} || -z ${SES_PASSWORD} ]]
then 
  echo "ERROR: Provide SES_USERNAME and SES_PASSWORD environment variables that are required for this container to relay mail to SES."
  exit 1
fi

#supervisor
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3

[program:postfix]
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stdout
stderr_logfile_maxbytes=0
command=/opt/postfix.sh
EOF

########################################################################
#  postfix SES relay configuration
#  http://docs.aws.amazon.com/ses/latest/DeveloperGuide/postfix.html
########################################################################
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
sleep 10s
tail -F /var/log/mail.log
EOF
chmod +x /opt/postfix.sh

postconf -e myhostname=${MAILDOMAIN:=mail.dev.meetup.com}
postconf -e smtpd_recipient_restrictions=check_recipient_access hash:/etc/postfix/recipient_domains,reject
postconf -e smtp_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e alias_maps=cdb:/etc/mail/aliases
# SMTP clients allowed to relay mail through Postfix
postconf -e  mynetworks="0.0.0.0/0"
postconf -F '*/*/chroot = n'

chown root.root /etc/mail/aliases \
&& chmod 0644 /etc/mail/aliases \
&& postalias cdb:/etc/mail/aliases
postmap /etc/postfix/recipient_domains