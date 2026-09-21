#!/bin/sh
BASEDIR="${BOOKTRAIL_BASEDIR:-/mnt/us/extensions/booktrail}"
TARGET="${BOOKTRAIL_SYSLOG_CONFIG:-/etc/syslog-ng/syslog-ng.conf}"
RULES="$BASEDIR/etc/syslog-ng.conf"
LEGACY_BACKUP="$BASEDIR/etc/syslog-ng.conf.bak"
BEGIN_MARKER='# BEGIN BOOKTRAIL MANAGED RULES'
END_MARKER='# END BOOKTRAIL MANAGED RULES'
cd "$BASEDIR" || exit 1

prepare_database()
{
    appender="${BOOKTRAIL_SESSION_APPENDER:-$BASEDIR/bin/booktrail-session-append}"
    database="${BOOKTRAIL_DB_PATH:-$BASEDIR/booktrail.db}"
    backup="$BASEDIR/booktrail.pre-4.6.0.db"
    [ -x "$appender" ] || return 1
    if [ ! -f "$database" ]; then
        BOOKTRAIL_DB_PATH="$database" "$appender" --initialize-database
        return $?
    fi
    if [ ! -f "$backup" ]; then
        BOOKTRAIL_DB_PATH="$database" "$appender" \
            --backup-database "$backup" || return 1
    fi
    BOOKTRAIL_DB_PATH="$database" "$appender" --verify-database
}

validate_config()
{
    command -v syslog-ng >/dev/null 2>&1 || return 0
    syslog-ng -s -f "$1" >/dev/null 2>&1
}

install_config()
{
    candidate="$1"
    rollback="$BASEDIR/etc/syslog-ng.rollback.$$"
    cp -p "$TARGET" "$rollback" || return 1
    if ! mntroot rw || ! cp -p "$candidate" "$TARGET"; then
        mntroot ro >/dev/null 2>&1 || true
        rm -f "$rollback"
        return 1
    fi
    if ! mntroot ro || ! restart syslog; then
        mntroot rw >/dev/null 2>&1 && cp -p "$rollback" "$TARGET" >/dev/null 2>&1
        mntroot ro >/dev/null 2>&1 || true
        restart syslog >/dev/null 2>&1 || true
        rm -f "$rollback"
        return 1
    fi
    rm -f "$rollback"
}

metric_disable_config_only()
{
    candidate="$BASEDIR/etc/syslog-ng.disable.$$"
    if grep -Fq "$BEGIN_MARKER" "$TARGET"; then
        awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
            $0 == begin { managed=1; next }
            $0 == end { managed=0; next }
            !managed { print }
        ' "$TARGET" > "$candidate" || return 1
    elif grep -q 'destination reader_metrics' "$TARGET" 2>/dev/null &&
         [ -r "$LEGACY_BACKUP" ] && [ -s "$LEGACY_BACKUP" ]; then
        cp -p "$LEGACY_BACKUP" "$candidate" || return 1
    else
        return 0
    fi
    if ! validate_config "$candidate" || ! install_config "$candidate"; then
        rm -f "$candidate"
        return 1
    fi
    rm -f "$candidate"
}

metric_enable()
{
    if ! prepare_database; then
        echo "Cannot enable Booktrail: database initialization failed." >&2
        return 1
    fi
    if [ ! -r "$TARGET" ] || [ ! -s "$TARGET" ] ||
       [ ! -r "$RULES" ] || [ ! -s "$RULES" ]; then
        echo "Cannot enable Booktrail: syslog-ng configuration is unavailable." >&2
        return 1
    fi

    candidate="$BASEDIR/etc/syslog-ng.enable.$$"
    source_config="$TARGET"
    if ! grep -Fq "$BEGIN_MARKER" "$TARGET" &&
       grep -q 'destination reader_metrics' "$TARGET" 2>/dev/null &&
       [ -r "$LEGACY_BACKUP" ] && [ -s "$LEGACY_BACKUP" ]; then
        source_config="$LEGACY_BACKUP"
    fi
    cp -p "$source_config" "$candidate" || return 1
    if ! grep -Fq "$BEGIN_MARKER" "$source_config"; then
        printf '\n' >> "$candidate" || return 1
        cat "$RULES" >> "$candidate" || return 1
    fi
    if ! validate_config "$candidate" || ! install_config "$candidate"; then
        rm -f "$candidate"
        echo "Cannot enable Booktrail: merged syslog-ng configuration failed." >&2
        return 1
    fi
    rm -f "$candidate"
    if ! sh "$BASEDIR/bin/booktrail-start.sh"; then
        sh "$BASEDIR/bin/booktrail-stop.sh" >/dev/null 2>&1 || true
        metric_disable_config_only >/dev/null 2>&1 || true
        echo "Cannot enable Booktrail: collector failed to start." >&2
        return 1
    fi
    if ! touch "$BASEDIR/etc/enable"; then
        sh "$BASEDIR/bin/booktrail-stop.sh" >/dev/null 2>&1 || true
        metric_disable_config_only >/dev/null 2>&1 || true
        return 1
    fi
}

metric_disable()
{
    if ! sh "$BASEDIR/bin/booktrail-stop.sh"; then
        echo "Cannot disable Booktrail: collector did not stop." >&2
        return 1
    fi
    if ! metric_disable_config_only; then
        sh "$BASEDIR/bin/booktrail-start.sh" >/dev/null 2>&1 || true
        echo "Cannot disable Booktrail: syslog-ng configuration was not restored." >&2
        return 1
    fi
    rm -f "$BASEDIR/etc/enable" || return 1
}

metric_reset()
{
    appender="${BOOKTRAIL_SESSION_APPENDER:-$BASEDIR/bin/booktrail-session-append}"
    database="${BOOKTRAIL_DB_PATH:-$BASEDIR/booktrail.db}"
    if [ ! -x "$appender" ] || [ ! -f "$database" ]; then
        echo "Cannot reset Booktrail: database or appender is unavailable." >&2
        return 21
    fi
    was_enabled=0
    [ -f "$BASEDIR/etc/enable" ] && was_enabled=1
    if ! sh "$BASEDIR/bin/booktrail-stop.sh"; then
        echo "Cannot reset Booktrail: collector did not stop." >&2
        return 20
    fi

    lock_file="$BASEDIR/etc/collector_generation.lock"
    generation_file="$BASEDIR/etc/collector_generation"
    exec 9>"$lock_file" || return 21
    if ! flock -x 9; then
        exec 9>&-
        return 21
    fi
    new_generation="$(date +%s)-$$"
    if ! printf '%s\n' "$new_generation" > "$generation_file"; then
        flock -u 9
        exec 9>&-
        [ "$was_enabled" -eq 0 ] || sh "$BASEDIR/bin/booktrail-start.sh" >/dev/null 2>&1 || true
        echo "Cannot reset Booktrail: database reset or validation failed." >&2
        return 21
    fi
    BOOKTRAIL_DB_PATH="$database" "$appender" --reset-statistics
    reset_status=$?
    if [ "$reset_status" -ne 0 ] && [ "$reset_status" -ne 24 ]; then
        flock -u 9
        exec 9>&-
        [ "$was_enabled" -eq 0 ] || sh "$BASEDIR/bin/booktrail-start.sh" >/dev/null 2>&1 || true
        echo "Cannot reset Booktrail: database reset failed." >&2
        return 21
    fi
    if ! BOOKTRAIL_DB_PATH="$database" "$appender" --verify-database; then
        flock -u 9
        exec 9>&-
        [ "$was_enabled" -eq 0 ] || sh "$BASEDIR/bin/booktrail-start.sh" >/dev/null 2>&1 || true
        echo "Booktrail data was cleared, but database verification failed." >&2
        return 24
    fi
    if ! rm -f "$BASEDIR"/log/* "$BASEDIR/etc/collector_last_event"; then
        flock -u 9
        exec 9>&-
        [ "$was_enabled" -eq 0 ] || sh "$BASEDIR/bin/booktrail-start.sh" >/dev/null 2>&1 || true
        echo "Cannot reset Booktrail: collector state cleanup failed." >&2
        return 22
    fi
    flock -u 9
    exec 9>&-
    if [ "$was_enabled" -eq 1 ] && ! sh "$BASEDIR/bin/booktrail-start.sh"; then
        echo "Cannot reset Booktrail: collector failed to restart." >&2
        return 23
    fi
    [ "$reset_status" -eq 0 ] || return 24
}

case "$1" in
    enable) metric_enable ;;
    disable) metric_disable ;;
    reset) metric_reset ;;
    *) echo "usage: $0 {enable|disable|reset}" >&2; exit 2 ;;
esac
