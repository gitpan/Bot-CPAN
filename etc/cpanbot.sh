#!/bin/sh
echo -n ' cpanbot'

PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin

case "$1" in
start)
        su - cwest -c 'perl /usr/local/perl/cpanbot/cpan-upload.pl > /usr/local/perl/cpanbot/cpan-upload.log 2>&1 &'
        ;;
*)
        echo "Usage: `basename $0` {start}" >&2
        exit 64
        ;;
esac

exit 0
