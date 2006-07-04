#!/usr/bin/perl -w

use strict;
use warnings;
use Net::FTP;
use Bot::CPAN::Info;
use Storable;
use File::Copy;

{
    my $path = "$ENV{'HOME'}/.cpanbot"; # path to dir that stores indices
    check_dirs($path);
    get_indices($path);
    make_master_index($path);
}

sub check_dirs {
    my $path = shift;
    unless (-d "$path") {mkdir "$path" or die $!}
    unless (-d "$path/authors") {mkdir "$path/authors" or die $!}
    unless (-d "$path/indices") {mkdir "$path/indices" or die $!}
    unless (-d "$path/modules") {mkdir "$path/modules" or die $!}
}

sub get_indices {
    my $path = shift;
    my $ftp = Net::FTP->new("ftp.funet.fi", Debug => 0) or die "Cannot connect to some.host.name: $@";
    $ftp->login("afoxson\@pobox.com","cpan") or die "Cannot login ", $ftp->message;
    $ftp->cwd("/pub/CPAN/authors") or die "Cannot change working directory ", $ftp->message;
    chdir "$path/authors" or die $!;
    $ftp->get("01mailrc.txt.gz") or die "get failed ", $ftp->message;
    $ftp->cwd("/pub/CPAN/indices") or die "Cannot change working directory ", $ftp->message;
    chdir "$path/indices" or die $!;
    $ftp->get("ls-lR.gz") or die "get failed ", $ftp->message;
    $ftp->cwd("/pub/CPAN/modules") or die "Cannot change working directory ", $ftp->message;
    chdir "$path/modules" or die $!;
    $ftp->get("02packages.details.txt.gz") or die "get failed ", $ftp->message;
    $ftp->cwd("/pub/CPAN/modules") or die "Cannot change working directory ", $ftp->message;
    chdir "$path/modules" or die $!;
    $ftp->get("03modlist.data.gz") or die "get failed ", $ftp->message;
    $ftp->quit;
}

sub make_master_index {
    my $path = shift;
    my $indice_data = Bot::CPAN::Info->new(CPAN => $path);
    $indice_data->fetch_info();
    store $indice_data, "$path/index.inc";
    move "$path/index.inc", "$path/index";
}
