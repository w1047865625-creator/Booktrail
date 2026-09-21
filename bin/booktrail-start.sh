#!/bin/sh

BASE="${BOOKTRAIL_BASEDIR:-/mnt/us/extensions/booktrail}"
PID_FILE="$BASE/etc/collector.pid"

if [ -r "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    case "$pid" in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$pid" 2>/dev/null; then
                cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
                case "$cmdline" in
                    *krg_collector.sh*) exit 0 ;;
                esac
            fi
            ;;
    esac
fi

mkdir -p "$BASE/etc" "$BASE/log" || exit 1
KRG_OUT="$BASE" setsid sh "$BASE/bin/krg_collector.sh" </dev/null >/dev/null 2>&1 &
usleep 200000

if [ -r "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    case "$pid" in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$pid" 2>/dev/null; then
                cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
                case "$cmdline" in
                    *krg_collector.sh*) exit 0 ;;
                esac
            fi
            ;;
    esac
fi

echo "Booktrail Collector failed to start." >&2
exit 1
