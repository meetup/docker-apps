# docker-james-stack

For running james in a dev env - specifically on our devboxes. 

### Build james locally 

```bash
cd /usr/local/meetup
ant james
```

### Start james and postfix containers
- NOTE: the following volumes are bind-mounted into the james container for providing needed james libs.
    volumes:
     - /usr/local/meetup:/code/meetup
     - /usr/local/james:/james_libs

```bash
cd /path/to/docker-james-stack
docker-compose up
```

### Note 
- The postfix container is accessible from the james container via docker links (using mail.int.meetup.com)
- The postfix container is configured to reject sending emails to all other domains except @meetup.com; configured in /etc/postfix/recipient_domains
