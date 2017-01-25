#!/usr/bin/perl

# postfix-policyd-spf-perl
# http://www.openspf.org/Software
# version 2.002
#
# (C) 2007      Scott Kitterman <scott@kitterman.com>
# (C) 2007      Julian Mehnle <julian@mehnle.net>
# (C) 2003-2004 Meng Weng Wong <mengwong@pobox.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use version; our $VERSION = qv('2.002');

use strict;

use IO::Handle;
use Sys::Syslog qw(:DEFAULT setlogsock);
use NetAddr::IP;
use Mail::SPF;

# ----------------------------------------------------------
#                      configuration
# ----------------------------------------------------------

my $spf_server = Mail::SPF::Server->new();

# Adding more handlers is easy:
my @HANDLERS = (
    {
        name => 'exempt_localhost',
        code => \&exempt_localhost
    },
    {
        name => 'sender_policy_framework',
        code => \&sender_policy_framework
    }
);

my $VERBOSE = 0;

my $DEFAULT_RESPONSE = 'DUNNO';

#
# Syslogging options for verbose mode and for fatal errors.
# NOTE: comment out the $syslog_socktype line if syslogging does not
# work on your system.
#

my $syslog_socktype = 'unix'; # inet, unix, stream, console
my $syslog_facility = 'mail';
my $syslog_options  = 'pid';
my $syslog_ident    = 'postfix/policy-spf';

use constant localhost_addresses => map(
    NetAddr::IP->new($_),
    qw(  127.0.0.0/8  ::ffff:127.0.0.0/104  ::1  )
);  # Does Postfix ever say "client_address=::ffff:<ipv4-address>"?

my %results_cache;  # by message instance

# ----------------------------------------------------------
#                      initialization
# ----------------------------------------------------------

#
# Log an error and abort.
#
sub fatal_exit {
    syslog(err     => "fatal_exit: @_");
    syslog(warning => "fatal_exit: @_");
    syslog(info    => "fatal_exit: @_");
    die("fatal: @_");
}

#
# Unbuffer standard output.
#
STDOUT->autoflush(1);

#
# This process runs as a daemon, so it can't log to a terminal. Use
# syslog so that people can actually see our messages.
#
setlogsock($syslog_socktype);
openlog($syslog_ident, $syslog_options, $syslog_facility);

# ----------------------------------------------------------
#                           main
# ----------------------------------------------------------

#
# Receive a bunch of attributes, evaluate the policy, send the result.
#
my %attr;
while (<STDIN>) {
    chomp;
    
    if (/=/) {
        my ($key, $value) =split (/=/, $_, 2);
        $attr{$key} = $value;
        next;
    }
    elsif (length) {
        syslog(warning => sprintf("warning: ignoring garbage: %.100s", $_));
        next;
    }
    
    if ($VERBOSE) {
        for (sort keys %attr) {
            syslog(debug => "Attribute: %s=%s", $_, $attr{$_});
        }
    }
    
    my $message_instance = $attr{instance};
    my $cache = defined($message_instance) ? $results_cache{$message_instance} ||= {} : {};
    
    my $action = $DEFAULT_RESPONSE;
    
    foreach my $handler (@HANDLERS) {
        my $handler_name = $handler->{name};
        my $handler_code = $handler->{code};
        
        my $response = $handler_code->(attr => \%attr, cache => $cache);
        
        if ($VERBOSE) {
            syslog(debug => "handler %s: %s", $handler_name, $response);
        }
        
        # Pick whatever response is not 'DUNNO'
        if ($response and $response !~ /^DUNNO/i) {
            syslog(info => "handler %s: is decisive.", $handler_name);
            $action = $response;
            last;
        }
    }
    
    syslog(info => "%s: Policy action=%s", $attr{queue_id}, $action);
    
    STDOUT->print("action=$action\n\n");
    %attr = ();
}

# ----------------------------------------------------------
#                handler: localhost exemption
# ----------------------------------------------------------

sub exempt_localhost {
    my %options = @_;
    my $attr = $options{attr};
    if ($attr->{client_address} != '') {
        my $client_address = NetAddr::IP->new($attr->{client_address});
        return 'PREPEND X-Comment SPF not applicable to localhost connection, skipped check'
            if grep($_->contains($client_address), localhost_addresses);
    };
    return 'DUNNO';
}

# ----------------------------------------------------------
#                        handler: SPF
# ----------------------------------------------------------

sub sender_policy_framework {
    my %options = @_;
    my $attr    = $options{attr};
    my $cache   = $options{cache};
    
    # -------------------------------------------------------------------------
    # Always do HELO check first.  If no HELO policy, it's only one lookup.
    # This avoids the need to do any MAIL FROM processing for null sender.
    # -------------------------------------------------------------------------
    
    my $helo_result = $cache->{helo_result};
    
    if (not defined($helo_result)) {
        # No HELO result has been cached from earlier checks on this message.
        
        my $helo_request = eval {
            Mail::SPF::Request->new(
                scope           => 'helo',
                identity        => $attr->{helo_name},
                ip_address      => $attr->{client_address}
            );
        };
        
        if ($@) {
            # An unexpected error occurred during request creation,
            # probably due to invalid input data!
            my $errmsg = $@;
            $errmsg = $errmsg->text if UNIVERSAL::isa($@, 'Mail::SPF::Exception');
            syslog(
                info => "%s:HELO check failed - Mail::SPF->new(%s, %s, %s) failed: %s",
                $attr->{queue_id}, $attr->{client_address}, $attr->{sender}, $attr->{helo_name}, $errmsg
            );
            return;
        }
        
        $helo_result = $cache->{helo_result} = $spf_server->process($helo_request);
    }
    
    my $helo_result_code    = $helo_result->code;  # 'pass', 'fail', etc.
    my $helo_local_exp      = $helo_result->local_explanation;
    my $helo_authority_exp  = $helo_result->authority_explanation
        if $helo_result->is_code('fail');
    my $helo_spf_header     = $helo_result->received_spf_header;
    
    if ($VERBOSE) {
        syslog(
            info => "%s: SPF %s: HELO/EHLO: %s, IP Address: %s, Recipient: %s",
            $attr->{queue_id}, $helo_result, $attr->{helo_name}, $attr->{client_address},
            $attr->{recipient}
        );
    };
    
    # Reject on HELO fail.  Defer on HELO temperror if message would otherwise
    # be accepted.  Use the HELO result and return for null sender.
    if ($helo_result->is_code('fail')) {
        return "550 $helo_authority_exp";
    }
    elsif ($helo_result->is_code('temperror')) {
        return "DEFER_IF_PERMIT SPF-Result=$helo_local_exp";
    }
    elsif ($attr->{sender} eq '') {
        return "PREPEND $helo_spf_header"
            unless $cache->{added_spf_header}++;
    }
    
    # -------------------------------------------------------------------------
    # Do MAIL FROM check (as HELO did not give a definitive result)
    # -------------------------------------------------------------------------
    
    my $mfrom_result = $cache->{mfrom_result};
    
    if (not defined($mfrom_result)) {
        # No MAIL FROM result has been cached from earlier checks on this message.
        
        my $mfrom_request = eval {
            Mail::SPF::Request->new(
                scope           => 'mfrom',
                identity        => $attr->{sender},
                ip_address      => $attr->{client_address},
                helo_identity   => $attr->{helo_name}  # for %{h} macro expansion
            );
        };
        
        if ($@) {
            # An unexpected error occurred during request creation,
            # probably due to invalid input data!
            my $errmsg = $@;
            $errmsg = $errmsg->text if UNIVERSAL::isa($@, 'Mail::SPF::Exception');
            syslog(
                info => "%s: Mail From (sender) check failed - Mail::SPF->new(%s, %s, %s) failed: %s",
                $attr->{queue_id}, $attr->{client_address}, $attr->{sender}, $attr->{helo_name}, $errmsg
            );
            return;
        } 
        
        $mfrom_result = $cache->{mfrom_result} = $spf_server->process($mfrom_request);
    }
    
    my $mfrom_result_code   = $mfrom_result->code;  # 'pass', 'fail', etc.
    my $mfrom_local_exp     = $mfrom_result->local_explanation;
    my $mfrom_authority_exp = $mfrom_result->authority_explanation
        if $mfrom_result->is_code('fail');
    my $mfrom_spf_header    = $mfrom_result->received_spf_header;
    
    if ($VERBOSE) {
        syslog(
            info => "%s: SPF %s: Envelope-from: %s, IP Address: %s, Recipient: %s",
            $attr->{queue_id}, $mfrom_result, $attr->{sender}, $attr->{client_address},
            $attr->{recipient}
        );
    };
    
    # Same approach as HELO....
    if ($mfrom_result->is_code('fail')) {
        return "550 $mfrom_authority_exp";
    }
    elsif ($mfrom_result->is_code('temperror')) {
        return "DEFER_IF_PERMIT SPF-Result=$mfrom_local_exp";
    }
    else {
        return "PREPEND $mfrom_spf_header"
            unless $cache->{added_spf_header}++;
    }
    
    return;
}
