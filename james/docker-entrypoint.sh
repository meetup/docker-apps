#!/bin/bash -x

if [ $1 == 'james' ]
then
	
	# some legacy scripts use /bin/sh and then call bash functions because it works on gentoo..
	ln -sf /bin/bash /bin/sh
	mkdir -p /usr/local # just in case

	# the meetcvs user is needed maybe ?
	groupadd -g 502 tech && useradd -u 505 -g tech -m -s /bin/bash meetcvs
	mkdir -p /home/meetcvs/logs/
	chown -R meetcvs.tech /home/meetcvs/logs/

	# symlinks party!!
	if [[ -d /code/meetup/util && -d /code/james && -d /code/meetup/target/webapps/chapstick ]]
	then 
		mkdir -p /usr/local/meetup/target/webapps
		ln -sf /code/meetup/util /usr/local/meetup/
		ln -sf /code/meetup/target/webapps/chapstick /usr/local/meetup/target/webapps/
		cp -r /code/james /usr/local/
		chown -R meetcvs.tech /usr/local/meetup/ /home/meetcvs/
	fi
	
	echo "Configuring james"
	# IMPORTANT - modify classpath for james
	sed -i -e 's/^\(JVM_EXT_DIRS="\)/\1\$JAVA_HOME\/jre\/lib\/ext:/' /usr/local/james/bin/phoenix.sh 
	
	chsh -s /bin/bash nobody \
	&& mkdir -p /usr/local/james/apps/james/var \
	&& cd /usr/local/james/apps/james/var \
	&& mkdir -p mail mail/inboxes nntp nntp/articleid nntp/temp nntp/spool nntp/groups \
 	&& chmod 2755 mail mail/inboxes nntp nntp/articleid nntp/temp nntp/spool nntp/groups \
	&& chown -R nobody.root /usr/local/james/apps/james/var /usr/local/james/logs /usr/local/james/temp \
	&& mkdir -p /usr/local/james/work \
	&& chown -R nobody.root /usr/local/james/work

	# James configs - mail repository/spool config & log4j config to STDOUT
	ln -sf /opt/config/config.xml /usr/local/james/apps/james/SAR-INF/config.xml \
	&& ln -sf /opt/config/environment.xml /usr/local/james/apps/james/SAR-INF/environment.xml


	# james needs chapstick code
	mkdir -p /usr/local/tomcat
	ln -s /usr/local/meetup/target/webapps /usr/local/tomcat/

	echo "Done configuring james"	
	echo "Starting"

	if [ -n "${MU_ENTRYPOINT}" ]
	then
		exec ${MU_ENTRYPOINT}
	else
		exec /init/james start
	fi
else
	exec $@
fi
