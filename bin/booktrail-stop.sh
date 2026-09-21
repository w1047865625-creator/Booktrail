#!/bin/sh

BASE="${BOOKTRAIL_BASEDIR:-/mnt/us/extensions/booktrail}"
PID_FILE="$BASE/etc/collector.pid"

[ -r "$PID_FILE" ] || exit 0
pid=$(cat "$PID_FILE" 2>/dev/null)
case "$pid" in
    ''|*[!0-9]*)
        rm -f "$PID_FILE"
        exit 0
        ;;
esac

if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    exit 0
fi

cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
case "$cmdline" in
    *krg_collector.sh*) ;;
    *)
        echo "Refusing to stop unrelated process $pid." >&2
        exit 1
        ;;
esac

kill "$pid" 2>/dev/null || exit 1
attempt=0
while kill -0 "$pid" 2>/dev/null && [ "$attempt" -lt 30 ]; do
    usleep 100000
    attempt=$((attempt + 1))
done
if kill -0 "$pid" 2>/dev/null; then
    echo "Booktrail Collector did not stop." >&2
    exit 1
fi
rm -f "$PID_FILE"
