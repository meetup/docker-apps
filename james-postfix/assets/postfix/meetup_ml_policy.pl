#!/usr/bin/perl

use strict;
use warnings;

use IO::Handle;
use Sys::Syslog qw( :DEFAULT setlogsock );
use DBI;

##
my $DEBUG = 0;
my $CACHE = 0;

## default response to PF
my $PF_RESP_DUNNO  = 'DUNNO';
my $PF_RESP_REJECT = 'REJECT';

my $DEFAULT_RESPONSE = $PF_RESP_DUNNO;

## db settings
my $DB_STRING = 'DBI:mysql:database=chapstick;host=db-ro.int.meetup.com';
my $DB_USER   = 'meetup_ro';
my $DB_PASS   = 'puteem';

## syslog setup
my $syslog_socktype = 'unix';
my $syslog_facility = 'mail';
my $syslog_options  = 'pid';
my $syslog_ident    = 'postfix/meetup_ml_policy';

# Unbuffer standard output.
STDOUT->autoflush( 1 );

# setup syslog
setlogsock( $syslog_socktype );
openlog( $syslog_ident, $syslog_options, $syslog_facility );

# postfix attrs are:
#
#   request=smtpd_access_policy
#   protocol_state=RCPT
#   protocol_name=SMTP
#   helo_name=some.domain.tld
#   queue_id=8045F2AB23
#   sender=foo@bar.tld
#   recipient=bar@foo.tld
#   recipient_count=0
#   client_address=1.2.3.4
#   client_name=another.domain.tld
#   reverse_client_name=another.domain.tld
#   instance=123.456.7
#   Postfix version 2.2 and later:
#   sasl_method=plain
#   sasl_username=you
#   sasl_sender=
#   size=12345
#   ccert_subject=solaris9.porcupine.org
#   ccert_issuer=Wietse+20Venema
#   ccert_fingerprint=C2:9D:F4:87:71:73:73:D9:18:E7:C2:F3:C1:DA:6E:04
#   Postfix version 2.3 and later:
#   encryption_protocol=TLSv1/SSLv3
#   encryption_cipher=DHE-RSA-AES256-SHA
#   encryption_keysize=256
#   etrn_domain=
#   [empty line]

my %group_cache;
my %results_cache;
my %attr;

while ( <STDIN> ) {
    chomp;
    
	## parse out attrs
    if ( /=/ ) {
        my ( $key, $value ) =split ( /=/, $_, 2 );
        $attr{$key} = $value;
        next;
    }
    elsif ( length ) {
        syslog( warning => sprintf( "warning: ignoring garbage: %.100s", $_ ) );
        next;
    }
    
	## from here on out, we have all the attrs
    if ( $DEBUG ) {
        for ( sort keys %attr ) {
            syslog( debug => "Attribute: %s=%s", $_, $attr{$_} );
        }
    }

	## default response to PF
	my $response = $DEFAULT_RESPONSE;

	## check cache
    my $message_instance = $attr{instance};
    my $cache = defined( $message_instance ) ? $results_cache{ $message_instance } ||= {} : {};
	if ( $cache->{ 'response' } ) {
		$response = $cache->{ 'response' };
	}
	else {
		# get the topic and number
		my $topic;
		my $number;

		my $to = $attr{recipient} || undef;

		if ( defined( $to ) && $to =~ /^([a-zA-Z0-9_][a-zA-Z0-9_\+-\.\']*)-(\d+)(?:-announce)?\@(?:dev\.)?meetup\.com/ ) {
			$topic  = $1;
			$number = $2;
		}

		if ( defined( $topic ) && defined( $number ) ) {
			syslog( info => "checking for topic: %s and number: %s", $topic, $number ) if $DEBUG;

			## check cache
			my $key = $topic . ':' . $number;
			if ( $CACHE && exists $group_cache{ $key } ) {
				syslog( info => "retrieving result from cache" );
				$response = $group_cache{ $key };
			}
			else {
				## check the db
				syslog( info => "retrieving result from db" );
				$response = check_db( $topic, $number );
				$group_cache{ $key } = $response;
			}
		}
	}

	if ( $DEBUG ) {
		syslog( debug => "response: %s", $response );
	}
	
    syslog( info => "%s: Policy action=%s", $attr{queue_id}, $response );
    
    STDOUT->print( "action=$response\n\n" );
    %attr = ();
}

sub check_db {
	my $topic  = shift;
	my $number = shift;

	# grab db handle
	my $dbh = DBI->connect( $DB_STRING, $DB_USER, $DB_PASS, { RaiseError => 1, AutoCommit => 1 } ) or return $PF_RESP_DUNNO;;
	my $sql = "SELECT count(*) FROM chapter c, topic t WHERE c.topic_id = t.topic_id AND"
		. " t.urlkey = ? AND c.number = ? AND c.status IN (?,?,?) AND t.status >= ?";
	my $sth = $dbh->prepare( $sql ) or return $PF_RESP_DUNNO;;

	$sth->execute( $topic, $number, -1, 1, 2, 1 ) or return $PF_RESP_DUNNO;

	syslog( info => "sql: %s", $sql ) if $DEBUG;

	my ( $count ) = $sth->fetchrow_array;

	$sth->finish;
	$dbh->disconnect;

	return ( $count == 0 ) ? $PF_RESP_REJECT : $PF_RESP_DUNNO;
}
