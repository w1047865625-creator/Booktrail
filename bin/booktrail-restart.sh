#!/bin/sh

BASE="${BOOKTRAIL_BASEDIR:-/mnt/us/extensions/booktrail}"
sh "$BASE/bin/booktrail-stop.sh" || exit 1
exec sh "$BASE/bin/booktrail-start.sh"
