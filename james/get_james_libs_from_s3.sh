#!/bin/bash -x
# Use this script to get the latest james build from s3 if 


get_james_libs_from_s3 () {
	
	sudo mkdir -p /usr/local/james_libs && \
	sudo chown $USER.tech -R /usr/local/james_libs && \
	cd /usr/local/james_libs
	aws s3 cp s3://com.meetup.dev.apps.code/CURRENT .
	aws s3 cp s3://com.meetup.dev.apps.code/$(cat CURRENT)/james.tar.gz .
	tar xzf james.tar.gz
}

get_james_libs_from_s3

exit 0 