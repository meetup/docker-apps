FROM openjdk:8u102-jdk

# Be explicit
USER root

# Default to UTF-8 file.encoding
ENV LANG "C.UTF-8"
ENV JAMES_VERSION "james-binary-2.3.2.1"

ENV TZ="America/New_York"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Preinstall Java stuff
# Add apt-source for openjdk
#RUN echo 'deb http://httpredir.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home

# Install debian packages all at once
RUN echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf \
	&& apt-get update && apt-get install --no-install-recommends -y \
		ca-certificates \
		curl \
		python=2.7* \
		python-pip \
	&& rm -rf /var/lib/apt/lists/*

# Postinstall Java stuff
# see CA_CERTIFICATES_JAVA_VERSION notes above
#RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure \
RUN ln -s ${JAVA_HOME} /usr/local/java

# Set up james and enable logging to STDOUT for "docker logs" streaming
RUN cd /usr/local \
	&& mkdir james \
	&& curl -s http://mirror.reverse.net/pub/apache/james/server/${JAMES_VERSION}.tar.gz | tar -xz -C james --strip-components 1 \
	&& chmod +x /usr/local/james/bin/phoenix.sh \ 
	&& mkdir -p /usr/local/james/temp \
	&& touch /usr/local/james/temp/phoenix.console \
	&& chown nobody.root /usr/local/james/temp/phoenix.console \
	&& mkdir -p /usr/local/james/apps/james \
	&& cd /usr/local/james/apps/james \
	&& /usr/local/java/bin/jar -xf ../james.sar

# Install awscli with pip as it seems to be smaller than the bundled option
RUN pip install --upgrade pip && pip install setuptools && pip install awscli

# James config files
RUN mkdir -p /opt/config
COPY config /opt/config

COPY docker-entrypoint.sh /
COPY init /init
COPY phoenix.sh /usr/local/james/bin/phoenix.sh
RUN chmod 755 /docker-entrypoint.sh /init/* /usr/local/james/bin/phoenix.sh 

EXPOSE 6666

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["james"]