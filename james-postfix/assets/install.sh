#!/bin/bash -x


# ADD FURTHER POSTFIX CONFIG STUFF PER OUR OLD JAMES CHEF RECIPES

# Create user accounts and set perms - used by postfix
useradd -u 5005 -g 100 -m -s /bin/bash info \
&& mkdir -p /home/info/bin /home/info/mail \
&& chmod 0755 /home/info \
&& chmod 0755 /home/info/bin \
&& chmod 0700 /home/info/mail


useradd -u 5009 -g 100 -m -s /bin/bash reminder \
&& mkdir -p /home/reminder/bin /home/reminder/mail \
&& chmod 0755 /home/reminder \
&& chmod 0755 /home/reminder/bin \
&& chmod 0700 /home/reminder/mail


useradd -u 5007 -g 100 -m -s /bin/ remove_bounce \
&& mkdir -p /home/remove_bounce/bin /home/remove_bounce/mail \
&& chmod 0755 /home/remove_bounce \
&& chmod 0755 /home/remove_bounce/bin \
&& chmod 0700 /home/remove_bounce/mail

useradd -u 5006 -g 100 -m -s /bin/bash support \
&& mkdir -p /home/support/bin /home/support/mail \
&& chmod 0755 /home/support \
&& chmod 0755 /home/support/bin \
&& chmod 0700 /home/support/mail


if [[ -d /code/util ]]
then 
  mkdir -p /usr/local/meetup
  ln -sf /code/util /usr/local/meetup/
fi

users=(info reminder remove_bounce support)

for i in ${users[@]}
do 
  ln -sf /usr/local/meetup/util/email_scripts/templates/reminder_auto_responder.txt /home/${i}/reminder_auto_responder.txt
  ln -sf /usr/local/meetup/util/email_scripts/templates/support_auto_responder.txt /home/${i}/support_auto_responder.txt
  ln -sf /usr/local/meetup/util/email_scripts/email_extract.pl /home/${i}/bin/email_extract.pl
  ln -sf /usr/local/meetup/util/email_scripts/verify_extract.pl /home/${i}/verify_extract.pl
  ln -sf /usr/local/meetup/util/email_scripts/remove_extract.pl /home/${i}/remove_extract.pl
done

cp /usr/local/meetup/util/email_scripts/remove_procmailrc /home/remove_bounce/.procmailrc \
&& chown remove_bounce.users /home/remove_bounce/.procmailrc \
&& chmod 0600 /home/remove_bounce/.procmailrc

chown root.root /etc/mail/aliases \
&& chmod 0644 /etc/mail/aliases \
&& postalias cdb:/etc/mail/aliases

chown root.root /etc/mail/virtual \
&& chmod 0644 /etc/mail/virtual \
&& postmap cdb:/etc/mail/virtual

chown root.root /etc/postfix/access \
&& chmod 0644 /etc/postfix/access \
&& postmap cdb:/etc/postfix/access

# ==> upstream dockerfile stuff
#judgement
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

#supervisor
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:dkimproxy]
command=/usr/sbin/service dkimproxy start

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3

[program:postfix]
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stdout
stderr_logfile_maxbytes=0
command=/opt/postfix.sh
EOF

############
#  postfix
############
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
sleep 10s
tail -F /var/log/mail.log
EOF
chmod +x /opt/postfix.sh
postconf -e myhostname=$maildomain
postconf -F '*/*/chroot = n'

############
# SASL SUPPORT FOR CLIENTS
# The following options set parameters needed by Postfix to enable
# Cyrus-SASL support for authentication of mail clients.
############
# /etc/postfix/main.cf
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
# smtpd.conf
cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
# sasldb2
echo $smtp_user | tr , \\n > /tmp/passwd
while IFS=':' read -r _user _pwd; do
  echo $_pwd | saslpasswd2 -p -c -u $maildomain $_user
done < /tmp/passwd
chown postfix.sasl /etc/sasldb2


#############
#  dkimproxy
#############

# It seems for the james servers we only use dkimproxy for decrypting incoming email
# headers - and not for signing outgoing messages

cat > /etc/dkimproxy/dkimproxy_in.conf <<EOF
# specify what address/port DKIMproxy should listen on
listen    127.0.0.1:10025

# specify what address/port DKIMproxy forwards mail to
relay     127.0.0.1:10026
EOF

cat > /etc/dkimproxy/dkimproxy_out.conf <<EOF
# specify what address/port DKIMproxy should listen on
listen    127.0.0.1:10027

# specify what address/port DKIMproxy forwards mail to
relay     127.0.0.1:10028

# specify what domains DKIMproxy can sign for (comma-separated, no spaces)
domain    meetup.com

# specify what signatures to add
#signature dkim(c=relaxed)
#signature domainkeys(c=nofws)

# specify location of the private key
#keyfile   /full/path/to/private.key

# specify the selector (i.e. the name of the key record put in DNS)
selector  postfix

# control how many processes DKIMproxy uses
#  - more information on these options (and others) can be found by
#    running `perldoc Net::Server::PreFork'.
#min_servers 5
#min_spare_servers 2
EOF



