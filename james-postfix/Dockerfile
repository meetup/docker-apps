FROM ubuntu:trusty

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND noninteractive

# Install pkgs
RUN apt-get update && apt-get -y install supervisor postfix sasl2-bin \
    opendkim opendkim-tools postfix-cdb postfix-pcre dkimproxy

# send mail logs to STDOUT
RUN mkdir -p /etc/mail

# Add files
COPY assets/install.sh /opt/install.sh
COPY assets/postfix/mail.meetup.com.pem /etc/postfix/mail.meetup.com.pem
COPY assets/postfix/local_map.pcre /etc/postfix/local_map.pcre
COPY assets/postfix/transports.pcre /etc/postfix/transports.pcre
COPY assets/postfix/main.cf /etc/postfix/main.cf
COPY assets/postfix/master.cf /etc/postfix/master.cf
COPY assets/postfix/meetup_ml_policy.pl /etc/postfix/meetup_ml_policy.pl
COPY assets/postfix/spf-policy.pl /etc/postfix/spf-policy.pl
COPY assets/postfix/virtual /etc/mail/virtual
COPY assets/postfix/aliases /etc/mail/aliases
COPY assets/postfix/access /etc/postfix/access

CMD ["sh", "-c", "/opt/install.sh; /usr/bin/supervisord -c /etc/supervisor/supervisord.conf"]
