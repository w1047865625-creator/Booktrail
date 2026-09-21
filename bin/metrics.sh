#!/bin/sh
BASEDIR=/mnt/us/extensions/booktrail
cd "$BASEDIR" || exit 1

APPENDER="$BASEDIR/bin/booktrail-session-append"
DATABASE="$BASEDIR/booktrail.db"
BACKUP="$BASEDIR/booktrail.pre-4.6.0.db"
if [ ! -f "$DATABASE" ]; then
    BOOKTRAIL_DB_PATH="$DATABASE" "$APPENDER" --initialize-database || exit 1
else
    if [ ! -f "$BACKUP" ]; then
        BOOKTRAIL_DB_PATH="$DATABASE" "$APPENDER" \
            --backup-database "$BACKUP" || exit 1
    fi
    BOOKTRAIL_DB_PATH="$DATABASE" "$APPENDER" --verify-database || exit 1
fi

[ "${1:-}" = "gui" ] || {
    echo "usage: $0 gui" >&2
    exit 2
}

usleep 800000
export DISPLAY=:0
export BOOKTRAIL_LAYOUT_PROFILE=kpw6
if [ -f "$BASEDIR/etc/enable" ]; then
    sh "$BASEDIR/bin/booktrail-start.sh" || exit 1
fi
cd "$BASEDIR/bin" || exit 1
exec ./kindle-reading-gtk
