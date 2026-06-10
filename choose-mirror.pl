#!/usr/bin/perl -w

# by Erik Braun, license CC0

use strict;
use English;
use File::Basename;
use Getopt::Long;
use IPC::Open2; # open2
use File::Fetch;
use IPC::Cmd qw/ can_run /;
use List::MoreUtils qw(uniq);

use Data::Dumper;

{
    no warnings 'once';
    # store temporary fetch files in /tmp instead of current dir
    $File::Fetch::TMP_DIR = '/tmp';
}

use v5.10; # say, when

my $VERSION = '0.04beta';

my $mirmon_url = 'rsync://poetry.dante.de/MirMon/mirmon.list';
my $sites_url = 'http://mirrors.ctan.org/CTAN.sites';
my $states_url = 'rsync://poetry.dante.de/MirMon/mirmon.state';

my $verbose = 0;
my $max = 20;
my $protocols = 'all';
my $format = 'text';
my $no_header = 0;
my $ping_command = 'fping -ae';
my $curl_command = 'curl -m 3 -s -o /dev/null -w %{time_total} -I';

## --------- Static warning texts (for cleaner indentation) ----------
my $MSG_HTTPS_BUG = <<'END_MSG';
WARNING: File::Fetch < 0.56 has a bug in connection with https
You may:
   Change the scheme in the URL to »http« (and leave the work to the webserver)
OR add the line »https  => [ qw|lwp wget curl| ],« to %METHODS in File/Fetch.pm
OR simply update your Perl installation.

END_MSG

my $MSG_RSYNC_MISSING = <<'END_MSG';
»rsync« is not in your PATH. Fetching the list of mirrors may fail.

END_MSG

my $MSG_FPING_MISSING = <<'END_MSG';
»fping« is not in your PATH. On Debian/Ubuntu type: apt install fping

Falling back to the MUCH slower installed command »ping« (option -v is
recommended). This may fail, since there are different implementations.
In case of strange behaviour try to set your locale to POSIX or en_US.

END_MSG

my $MSG_CURL_MISSING = <<'END_MSG';
»curl« is not in your PATH. On Debian/Ubuntu type: apt install curl

HTTP HEAD timing is not available.

END_MSG
## -------------------------------------------------------------------


main( @ARGV ) unless caller();

sub main {
    Getopt::Long::Configure( 'bundling' );

    GetOptions(
    'mirmon_url|u=s' => \$mirmon_url,
    'states_url|s=s' => \$states_url,
    'max|m=i'        => \$max,
    'protocols|p=s'  => \$protocols,
    'verbose|v'      => \$verbose,
    'format|F=s'     => \$format,
    'no-header!'     => \$no_header,
    'help|h'         => sub { usage(); exit },
    'version|V'      => sub { version(); exit },
    );

    my @protocols = set_protocols($protocols);

    my ($mirmon_file, $sites_file, $states_file) =
      fetch_files($mirmon_url, $sites_url, $states_url);

    my $mirrors_ref = get_mirrors($mirmon_file);

    set_urls($mirrors_ref, $sites_file);

    get_times($mirrors_ref);

    set_states($mirrors_ref, $states_file);

    print_sorted($mirrors_ref, \@protocols);

    # pri<nt Dumper($mirrors_ref);

    exit 0;
}

sub fetch_files {
    my $mirmon_url = shift;
    my $sites_url = shift;
    my $states_url = shift;

    my ($mirmon_file, $sites_file, $states_file);

    my $ff = File::Fetch->new(uri => "$mirmon_url");
    my $where = $ff->fetch(to => \$mirmon_file) or warn $ff->error;
    die "couldn't load $mirmon_url\n" if not defined $where;

    my $ff2 = File::Fetch->new(uri => "$sites_url");
    $where = $ff2->fetch(to => \$sites_file) or warn $ff2->error;
    die "couldn't load $sites_url\n" if not defined $where;

    my $ff3 = File::Fetch->new(uri => "$states_url");
    $where = $ff3->fetch(to => \$states_file) or warn $ff3->error;
    die "couldn't load $states_url\n" if not defined $where;

    check_prerequisites($ff, $ff2, $ff3);

    return ($mirmon_file, $sites_file, $states_file);
}

sub set_states {
    my $mirrors_ref=shift;
    my $in = shift;
    my %mirrors=%$mirrors_ref; # Beware! %mirrors is a local copy, its contents not!

    for ( split /\n/, $in) {
    s/^\s+|\s+$//g;
    if (m!^(\w+://(.*?)/.*?) (\d{10}) (\w+) !) {
        $mirrors{$2}{'age'}=$3;
        $mirrors{$2}{'status'}=$4;
    } else {
        warn "unknown line in $states_url: $_\n";
    }
    }

    return;
}

sub set_urls {
    my $mirrors_ref=shift;
    my $in = shift;

    for ( split /\n/, $in) {
    s/^\s+|\s+$//g;
    next unless /URL:/;
    # reject lines with unusal characters
    next unless m![\w.:/-]!;
    if (m!URL: (\w+://(.*?)/.*)!) {
        my $hostname = replace_alias($2);
        $mirrors_ref->{$hostname}{'time'}=-1;
        push @{ $mirrors_ref->{$hostname}{'urls'} }, $1;
    } else {
        warn "unknown line in $sites_url: $_\n";
    }
    }

    return;
}


# ===== Helper: Datenaufbereitung ====================================

sub _eligible_sorted_hosts {
    my ($mirrors_ref) = @_;
    my %mirrors = %{$mirrors_ref};
    my @hosts;

    foreach my $host (keys %mirrors) {
    if (($mirrors{$host}{'time'} // -1) >= 0) {
        push @hosts, $host;
    } else {
        say "either down or blocked ping, removed from list: $host" if $verbose;
    }
    }
    return sort { $mirrors{$a}{'time'} <=> $mirrors{$b}{'time'} } @hosts;
}

sub _filter_urls_by_protocols {
    my ($urls_ref, $protocols_ref) = @_;
    return () unless $urls_ref && @$urls_ref;

    # Wenn 'all' enthalten, gib alles zurück
    if (grep { $_ eq 'all' } @$protocols_ref) {
    return @$urls_ref;
    }

    my @out;
    URL:
      for my $u (@$urls_ref) {
      for my $p (@$protocols_ref) {
          if ($u =~ m!^\Q$p\E://!i) {
          push @out, $u;
          next URL;
          }
      }
      }
    return @out;
}

sub _age_hours {
    my ($now, $epoch) = @_;
    return undef unless defined $epoch && $epoch =~ /^\d+$/;
    return int(( $now - $epoch )/3600 + 0.4);
}

sub _protocols_from_urls {
    my ($urls_ref) = @_;
    return [] unless $urls_ref && @$urls_ref;
    my %seen;
    my @p = map { (m{^(\w+)://}i ? lc $1 : ()) } @$urls_ref;
    my @uniq = grep { !$seen{$_}++ } @p;
    return \@uniq;
}

sub _row_for_host {
    my ($host, $mirrors_ref, $urls_filtered_ref, $now) = @_;
    my $m = $mirrors_ref->{$host};

    my $age_h = _age_hours($now, $m->{'age'});
    my $protos = _protocols_from_urls($m->{'urls'});

    return {
    host        => $host,
      latency_ms  => 0.0 + ($m->{'time'} // 0),
      time_source => ($m->{'time_source'} // 'icmp'),
      status      => $m->{'status'},
      age_h       => $age_h,
      urls        => [ @$urls_filtered_ref ],
      protocols   => $protos,
    };
}

# ===== Renderer: Ausgabe-Formate ====================================

# 1) Bisheriges menschenlesbares Layout
sub _render_human_header {
    say "msec\tSrc\tStatus\tAge\tMirror";
}
sub _render_human_row {
    my ($row) = @_;
    my $ms   = $row->{latency_ms};
    my $src  = $row->{time_source} // 'icmp';
    my $st   = $row->{status} // '';
    my $ageh = defined $row->{age_h} ? "$row->{age_h}h" : '';
    my @urls = @{ $row->{urls} // [] };

    # erste Zeile mit den Metriken
    print  $ms;
    print "\t$src";
    print "\t$st";
    print "\t$ageh";

    # URLs: erste in gleicher Zeile, Rest eingerückt
    if (@urls) {
    my $first = shift @urls;
    say "\t$first";
    for my $u (@urls) {
        say "\t\t\t\t$u";
    }
    } else {
    print "\n";
    }
    print "\n";
}

# 2) Simple: "<host> <latency_ms> <proto1,proto2,...>"
sub _render_simple_header {
    return if $no_header;
    say "host latency_ms protocols";
}
sub _render_simple_row {
    my ($row, $protocols_ref) = @_;
    # Liste der Protokolle am Row-Objekt; optional anhand gewünschter $protocols_ref schneiden
    my %allow = ();
    my $use_allow = 0;
    if ($protocols_ref && @$protocols_ref && !grep { $_ eq 'all' } @$protocols_ref) {
    %allow = map { $_ => 1 } @$protocols_ref;
    $use_allow = 1;
    }
    my @p = @{ $row->{protocols} // [] };
    @p = grep { $allow{$_} } @p if $use_allow;

    my $plist = join(',', @p);
    say "$row->{host} $row->{latency_ms} $plist";
}

# 3) NDJSON: eine JSON-Zeile pro Row
sub _render_ndjson_row {
    require JSON::PP;
    my $json = JSON::PP->new->ascii->allow_nonref;
    my ($row) = @_;
    say $json->encode($row);
}

# ===== Orchestrator: print_sorted ===================================

# Erwartet globale Variablen:
#   $verbose, $max, $mirmon_url, $sites_url
# und ggf. $format, $no_header (wenn du die Option eingebaut hast)

sub print_sorted {
    my ($mirrors_ref, $protocols_ref) = @_;
    my %mirrors   = %{$mirrors_ref};
    my @protocols = @{$protocols_ref // []};

    my $now = time();
    my @sorted_hosts = _eligible_sorted_hosts($mirrors_ref);

    # Kopfzeile je nach Format
    if ($format && $format eq 'simple') {
    _render_simple_header();
    } elsif (!$format || $format eq 'human' || $format eq 'text') {
    _render_human_header();
    }

    my $count = 0;
    HOST:
      for my $h (@sorted_hosts) {
      # Sicherheit: Host ohne mirmon-URL melden wie bisher
      unless (defined $mirrors{$h}{'url'}) {
          say "Warning: host $h not in $mirmon_url, but in $sites_url";
          next HOST;
      }
      say "Warning: URL $mirrors{$h}{'url'} not in $sites_url, but in $mirmon_url"
        if not defined $mirrors{$h}{'urls'};

      # URLs nach Protokollwunsch filtern (für Ausgabe)
      my @urls = _filter_urls_by_protocols($mirrors{$h}{'urls'}, \@protocols);
      next HOST unless @urls;

      my $row = _row_for_host($h, $mirrors_ref, \@urls, $now);

      # Ausgabe je Format
      if ($format && $format eq 'simple') {
          _render_simple_row($row, \@protocols);
      } elsif ($format && $format eq 'ndjson') {
          _render_ndjson_row($row);
      } else { # human/text
          _render_human_row($row);
      }

      last if ($max && ++$count >= $max);
      }
    return;
}

sub get_times {
    my $mirrors_ref=shift;
    my %mirrors=%$mirrors_ref;

    my @hosts=keys(%mirrors);

    print  "probing " . scalar @hosts . " hosts:\n" if $verbose;

    if ($ping_command =~ /^fping/) {
    open2(\*PINGOUT, \*PINGIN, "$ping_command") or die "Can't start $ping_command: $!";

    say PINGIN for @hosts;
    close PINGIN;

    while (<PINGOUT>) {
        if (/(.*?) \((\d+\.?\d*) ms\)/) {
        say "$2: $1" if $verbose;
        $mirrors_ref->{$1}{'time'} = $2;
        $mirrors_ref->{$1}{'time_source'} = 'icmp';
        } else {
        print "unknown result from $ping_command: $_";
        }
    }
    close PINGOUT;
    } else {
    # Fallback inetutils-ping / iputils-ping
    foreach my $host (@hosts) {
        open2(\*PINGOUT, \*PINGIN, "$ping_command $host") or die "Can't start $ping_command: $!";
        while (<PINGOUT>) {
        next unless /^64/;
        if (/time=(\d+\.?\d*) ms/) {
            say "$host: $1" if $verbose;
            $mirrors_ref->{$host}{'time'} = $1;
            $mirrors_ref->{$host}{'time_source'} = 'icmp';
        } else {
            print "unknown result from $ping_command: $_";
        }
        }
        close PINGOUT;
        close PINGIN;
    }
    }

     # HTTP fallback for hosts without ICMP response
    http_fallback_times($mirrors_ref);

    return;
}

sub get_mirrors {
    my $in = shift;
    my %mirrors;

    for ( split /\n/, $in) {
    next if /^#/ or /^Root/;
    # reject lines with unusal characters
    next unless m![\w.:/-]!;
    if (m!(\w+://(.*?)/.*)!) {
        $mirrors{$2}{'url'}="$1";
        $mirrors{$2}{'time'}=-1;
    } else {
        warn "unknown line in $mirmon_url: $_\n";
    }
    }

    return \%mirrors;
}

sub set_protocols {
    my $protocols = shift;
    my @in = uniq split /,/, $protocols;

    my @supported = qw/ rsync ftp http https /;
    my @protocols;

    # check for 'all'
    if (grep { $_ eq 'all' } @in) {
    say "It's not useful to use »all« together with other protocols."
      if @in > 1;
    return @supported;
    }

    for my $proto (@in) {
    if (grep { $_ eq $proto } @supported) {
        push @protocols, $proto;
    } else {
        say "Unknown protocol »$proto«";
    }
    }

    return @supported unless @protocols;
    return @protocols;
}

# ---------- HTTP Fallback Timing ----------

sub http_fallback_times {
    my ($mirrors_ref) = @_;

    my @candidates = grep {
    ($mirrors_ref->{$_}{'time'} // -1) < 0
      && defined $mirrors_ref->{$_}{'urls'}
    } keys %{$mirrors_ref};

    return unless @candidates;

    say "probing HTTP latency for " . scalar(@candidates) . " hosts (ICMP blocked?)" if $verbose;

    foreach my $host (@candidates) {
    my $url = _select_http_url($mirrors_ref->{$host}{'urls'});
    next unless $url;

    my $ms = _measure_http_time_ms($url);
    if (defined $ms) {
        $mirrors_ref->{$host}{'time'} = $ms;
        $mirrors_ref->{$host}{'time_source'} = 'http';
        say sprintf "HTTP %5.1f ms: %s -> %s", $ms, $host, $url if $verbose;
    } else {
        say "HTTP timing failed for $host ($url)" if $verbose;
    }
    }
}

sub _select_http_url {
    my ($urls_ref) = @_;
    # Prefer https over http, pick first and normalize to root path
    my @https = grep { m!^https://!i } @$urls_ref;
    my @http  = grep { m!^http://!i } @$urls_ref;
    my $u = $https[0] // $http[0];
    return unless $u;
    $u =~ s!(https?://[^/]+).*!$1/!i;
    return $u;
}

sub _measure_http_time_ms {
    my ($url) = @_;
    # use curl -I to issue HEAD, capture time_total in seconds
    my ($r, $w);
    my $pid = open2($r, $w, "$curl_command '$url'");
    close $w;
    my $out = '';
    while (<$r>) { $out .= $_ }
    close $r;
    waitpid($pid, 0);
    if ($out =~ /([0-9]+(?:\.[0-9]+)?)/) {
    my $sec = $1 + 0.0;
    my $ms = sprintf("%.1f", $sec * 1000.0);
    return $ms + 0.0;
    }
    return;
}

sub replace_alias {
    my $hostname = shift;

    return ('mirror.physik.tu-berlin.de') if $hostname eq 'mirror.physik-pool.tu-berlin.de';
    return ('ftp.mpi-inf.mpg.de')  if $hostname eq 'ftp.mpi-sb.mpg.de';
    return ('ctan.cs.uu.nl')  if $hostname eq 'archive.cs.uu.nl';
    return ('ctan.cs.uu.nl')  if $hostname eq 'rsync.cs.uu.nl';
    return ('piotrkosoft.net')  if $hostname eq 'ftp.piotrkosoft.net';
    return ('muug.ca')  if $hostname eq 'ftp.muug.ca';
    return ('www.texlive.info')  if $hostname eq 'texlive.info';
    return ('www.nic.funet.fi')  if $hostname eq 'ftp.funet.fi';
    return ('ctan.math.utah.edu')  if $hostname eq 'tug.ctan.org';
    return ('vesta.informatik.rwth-aachen.de')  if $hostname eq 'sunsite.informatik.rwth-aachen.de';

    return $hostname;
}
######

sub check_prerequisites {
    my $ff = shift;
    my $ff2 = shift;
    my $ff3 = shift;

    say "Mirmon URL: $mirmon_url\nCTAN sites: $sites_url" if $verbose;

    if ($File::Fetch::VERSION < 0.56 and
    ($ff->scheme eq 'https' or $ff2->scheme eq 'https')) {
        warn $MSG_HTTPS_BUG;
        }

    if ($ff->scheme eq 'rsync' or $ff2->scheme eq 'rsync') {
    can_run('rsync') or warn $MSG_RSYNC_MISSING;
    }

    if ($ping_command =~ /^fping/ and not can_run('fping')) {
    $ping_command = 'ping -c 1 -W 1';
    warn $MSG_FPING_MISSING;
    }

    unless (can_run('curl')) {
    warn $MSG_CURL_MISSING;
    }

    return;
}

sub version {
    my $progname = basename $0;

    say "$progname\t$VERSION";

    return;
}


sub usage {
    my $progname = basename $0;

    print <<"END"
This script returns a list of CTAN mirrors sorted by ping time.

Usage: $progname [options]

OPTIONS:
 -m, --max NR     maximum number of listed mirrors (default: $max),
                  set it to »0« for the entire list
 -p  --protocol   (all, rsync, ftp, http, https)  (default: $protocols)
 -n, --no-header  omit header line (for scripting)
 -v  --verbose    detailed output, can help with debugging
 -h, --help       this help
 -V, --version    print version
END

# Let's hope that rsync://comedy.dante.de/MirMon/ doesn't change
# -u, --url URL    mirror URL in mirmon format
#                  (default: $mirmon_url)
# -s, --states URL states file URL
#                  (default: $states_url)

}

exit;
