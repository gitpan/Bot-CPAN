#!/bin/sh
echo -n ' cpanbot'

PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin

case "$1" in
start)
        su - yourusername -c 'perl /path/to/cpan-upload.pl > /path/to/cpan-upload.log 2>&1 &'
        ;;
*)
        echo "Usage: `basename $0` {start}" >&2
        exit 64
        ;;
esac

exit 0
