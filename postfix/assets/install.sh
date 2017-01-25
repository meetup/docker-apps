#!/bin/bash -x

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
# reject sending mail to any non-@meetup.com address - config in /etc/postfix/recipient_domains
postconf -e smtpd_recipient_restrictions=check_recipient_access,hash:/etc/postfix/recipient_domains,reject
postconf -e alias_maps=cdb:/etc/mail/aliases
# SMTP clients allowed to relay mail through Postfix
postconf -e  mynetworks="0.0.0.0/0"
postconf -F '*/*/chroot = n'

chown root.root /etc/mail/aliases \
&& chmod 0644 /etc/mail/aliases \
&& postalias cdb:/etc/mail/aliases
postmap /etc/postfix/recipient_domains