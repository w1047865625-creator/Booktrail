#!/bin/sh
OUT="${KRG_OUT:-/mnt/us/extensions/booktrail}"
LOG="${KRG_LOG:-/var/log/messages}"
APPENDER="${BOOKTRAIL_SESSION_APPENDER:-$OUT/bin/booktrail-session-append}"
TIME_CONVERTER="${BOOKTRAIL_TIME_CONVERTER:-$APPENDER}"
DB_PATH="${BOOKTRAIL_DB_PATH:-$OUT/booktrail.db}"
GENERATION_FILE="${KRG_GENERATION_FILE:-$OUT/etc/collector_generation}"
GENERATION_LOCK="${KRG_GENERATION_LOCK:-$OUT/etc/collector_generation.lock}"
mkdir -p "$OUT/log" "$OUT/etc" || exit 1

AWK_PROG='
function local_epoch(stamp,    cmd,value,status) {
    if (TIME_CONVERTER !~ /^[[:alnum:]_\/.:-]+$/ ||
        stamp !~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) return -1
    cmd="\"" TIME_CONVERTER "\" --local-epoch " stamp
    status=(cmd | getline value); close(cmd)
    if (status<=0 || value !~ /^[0-9]+$/) return -1
    return value/1000
}
function field_number(name,text,pat,value) {
    pat=name "[[:space:]]*:[[:space:]]*[0-9]+"
    if (!match(text,pat)) return -1
    value=substr(text,RSTART,RLENGTH); sub("^[^:]*:[[:space:]]*","",value); return value+0
}
function field_text(name,text,pat,value) {
    pat=name "[[:space:]]*[:=][[:space:]]*[^[:space:],]+"
    if (!match(text,pat)) return ""
    value=substr(text,RSTART,RLENGTH); sub("^[^:=]*[:=][[:space:]]*","",value); return value
}
function fastmetrics_key(text,value) {
    if (index(text,"fastmetrics:emitPayload:")==0) return ""
    if (!match(text,/Payload key (item_asin|cde_key|book_asin) value [^ ]+/)) return ""
    value=substr(text,RSTART,RLENGTH); sub(/^Payload key (item_asin|cde_key|book_asin) value /,"",value); return value
}
function saver_overlap(start,end,    i,a,b,total) {
    total=0
    for (i=1; i<=saver_count; i++) {
        a=saver_start[i]; b=saver_end[i]
        if (a<end && b>start) {
            if (a<start) a=start
            if (b>end) b=end
            if (b>a) total+=b-a
        }
    }
    if (screen_saver_active && screen_saver_started<end) {
        a=screen_saver_started; b=end
        if (a<start) a=start
        if (b>end) b=end
        if (b>a) total+=b-a
    }
    return total
}
function record_saver_start(at) {
    if (screen_saver_active) return
    if (cur_e!="") {
        flush_interval(cur_s,cur_e,cur_cdekey,cur_day,cur_keys)
        cur_s=""; cur_e=""; cur_cdekey=""; cur_day=""; cur_keys=""
    }
    screen_saver_active=1; screen_saver_started=at
}
function record_saver_end(at) {
    if (!screen_saver_active) return
    if (at<screen_saver_started) at=screen_saver_started
    if (at>screen_saver_started) {
        saver_count++
        saver_start[saver_count]=screen_saver_started
        saver_end[saver_count]=at
    }
    screen_saver_active=0; screen_saver_started=0
}
function persist_keys(keys,    count,key_index,values,key) {
    count=split(keys,values,"\n")
    for (key_index=1; key_index<=count; key_index++) {
        key=values[key_index]
        if (key!="") print key >> state_file
    }
    close(state_file)
    if (seen_next>0 && seen_next%MAX_SEEN==0) {
        for (key_index=0; key_index<MAX_SEEN; key_index++) {
            key=seen_order[(seen_next-MAX_SEEN+key_index)%MAX_SEEN]
            if (key_index==0) print key > state_file
            else print key >> state_file
        }
        close(state_file)
    }
}
function release_keys(keys,    count,key_index,values,key) {
    count=split(keys,values,"\n")
    for (key_index=1; key_index<=count; key_index++) {
        key=values[key_index]
        if (key!="") delete seen[key]
    }
}
function append_session(ck,s,e,d,keys,cmd,status,attempt,error_log) {
    if (ck=="" || d<=0) return
    if (ck !~ /^[[:alnum:]_*.-]+$/ || DB_PATH !~ /^[[:alnum:]_\/.:-]+$/ || APPENDER !~ /^[[:alnum:]_\/.:-]+$/ || generation !~ /^[[:alnum:]_.:-]+$/ || GENERATION_FILE !~ /^[[:alnum:]_\/.:-]+$/ || GENERATION_LOCK !~ /^[[:alnum:]_\/.:-]+$/) {
        print "collector sqlite append rejected unsafe argument cdeKey=" ck >> (OUT "/log/collector_errors.log")
        close(OUT "/log/collector_errors.log")
        return
    }
    cmd="BOOKTRAIL_DB_PATH=\"" DB_PATH "\" BOOKTRAIL_SESSION_GENERATION=\"" generation "\" BOOKTRAIL_GENERATION_FILE=\"" GENERATION_FILE "\" BOOKTRAIL_GENERATION_LOCK=\"" GENERATION_LOCK "\" \"" APPENDER "\" \"" ck "\" " int(s*1000+0.5) " " int(e*1000+0.5) " " int(d*1000+0.5) " krds"
    error_log=(OUT "/log/collector_errors.log")
    attempt=1
    status=1
    while (attempt<=3) {
        status=system(cmd " 2>>\"" error_log "\"")
        if (status==0) break
        if (attempt<3) system("sleep 1")
        attempt++
    }
    if (status!=0) {
        print "collector sqlite append failed cdeKey=" ck " status=" status " attempts=" (attempt-1) >> error_log
        release_keys(keys)
        append_failures++
        return 0
    }
    print ck "," int(s*1000+0.5) "," int(e*1000+0.5) "," int(d*1000+0.5) ",krds" >> (OUT "/log/collector_sqlite.log")
    persist_keys(keys)
    return 1
}
function close_session(seconds) {
    if (sess_s=="") return
    seconds=sess_e-sess_s-saver_overlap(sess_s,sess_e)
    if (seconds<0) seconds=0
    printf "session start=%d end=%d seconds=%.3f intervals=%d\n",int(sess_s),int(sess_e),seconds,sess_n >> (OUT "/log/collector_sessions.log")
    close(OUT "/log/collector_sessions.log")
    if (sess_cdekey=="") print "cdeKey unavailable start=" int(sess_s*1000+0.5) " end=" int(sess_e*1000+0.5) " duration=" int(seconds*1000+0.5) >> (OUT "/log/collector_errors.log")
    append_session(sess_cdekey,sess_s,sess_e,seconds,sess_keys)
    total+=seconds; sess_s=""; sess_e=""; sess_n=0; sess_cdekey=""; sess_keys=""
}
function flush_interval(s,e,ck,event_day,keys,dur,ep,yy,mm) {
    dur=int(((e-s)-saver_overlap(s,e))*1000+0.5); if (dur<=0) return
    if (sess_e!="" && s-sess_e>60) close_session()
    if (sess_s=="") { sess_s=s; sess_cdekey=ck; sess_keys="" }
    else if (sess_cdekey=="" && ck!="") sess_cdekey=ck
    sess_e=e; sess_n++; sess_keys=sess_keys keys; ep=int(e); yy=substr(event_day,3,2); mm=substr(event_day,5,2)
    printf "1,%d,0,0,0,com.lab126.booklet.reader.activeDuration,%d,%s\n",ep,dur,ck >> (OUT "/log/metrics_reader_" yy mm); close(OUT "/log/metrics_reader_" yy mm)
    if (ck!="") { printf "%s,%d,%d\n",ck,ep,dur >> (OUT "/log/metrics_book_" yy mm); close(OUT "/log/metrics_book_" yy mm) }
}
BEGIN {
    MAX_SEEN=4096; seen_next=0
    while ((getline lastkey < state_file)>0) {
        if (lastkey=="" || seen[lastkey]) continue
        slot=seen_next%MAX_SEEN; old_key=seen_order[slot]
        if (old_key!="") delete seen[old_key]
        seen_order[slot]=lastkey; seen[lastkey]=1; seen_next++
    }
    close(state_file); total=0
    screen_saver_active=0; screen_saver_started=0
    saver_count=0; append_failures=0
}
{
    line=$0; event_key=""; key_from_context=fastmetrics_key(line)
    is_power=index(line,"BOOKTRAIL_POWERD goingToScreenSaver")==1 || index(line,"BOOKTRAIL_POWERD outOfScreenSaver")==1
    is_reader=index(line,"ReadingTimerController:Information::NextPage")>0 || index(line,"ReadingTimerController:Information::CloseBook")>0
    if (journal_enabled && (key_from_context!="" || is_power || is_reader)) { print line >> journal_file; close(journal_file) }
    if (key_from_context!="") { current_cdekey=key_from_context; next }
    if (index(line,"BOOKTRAIL_POWERD goingToScreenSaver")==1) {
        split(line,powerd_fields," "); record_saver_start(powerd_fields[3]); next
    }
    if (index(line,"BOOKTRAIL_POWERD outOfScreenSaver")==1) {
        split(line,powerd_fields," "); record_saver_end(powerd_fields[3]); next
    }
    is_nb=index(line,"ReadingTimerController:Information::NextPage")>0; is_cb=index(line,"ReadingTimerController:Information::CloseBook")>0
    if (!is_nb && !is_cb) next
    split($1,ta,":"); event_day=ta[1]; hms=ta[2]; if (length(event_day)!=6 || length(hms)!=6) next
    t=local_epoch(event_day hms); if (t<0) { print "collector local time conversion failed timestamp=" event_day hms >> (OUT "/log/collector_errors.log"); next }; I=field_number("IntervalTime",line)
    event_cdekey=field_text("cdeKey",line); if (event_cdekey=="") event_cdekey=field_text("cde_key",line); if (event_cdekey=="") event_cdekey=field_text("item_asin",line); if (event_cdekey=="") event_cdekey=field_text("book_asin",line); if (event_cdekey=="") event_cdekey=current_cdekey
    key=""
    if (event_cdekey!="") {
        key="v2|" (is_cb?"CloseBook":"NextPage") "|" $1 "|" I "|cde:" length(event_cdekey) ":" event_cdekey
        if (seen[key]) next
        slot=seen_next%MAX_SEEN; old_key=seen_order[slot]
        if (old_key!="") delete seen[old_key]
        seen_order[slot]=key; seen[key]=1; seen_next++
        event_key=key "\n"
    }
    if (I<=0) { if (is_cb) { if (cur_e!="") { flush_interval(cur_s,cur_e,cur_cdekey,cur_day,cur_keys); cur_s=""; cur_e=""; cur_keys="" }; if (sess_s!="") { sess_keys=sess_keys event_key; close_session() } else persist_keys(event_key); current_cdekey=""; cur_cdekey=""; cur_keys="" }; next }
    s=t-I/1000; e=t
    if (cur_e!="" && event_cdekey!=cur_cdekey) { flush_interval(cur_s,cur_e,cur_cdekey,cur_day,cur_keys); cur_s=""; cur_e=""; cur_keys=""; close_session() }
    if (cur_e!="" && s<=cur_e+0.5) { if (e>cur_e) cur_e=e; if (event_cdekey!="") cur_cdekey=event_cdekey; cur_day=event_day; cur_keys=cur_keys event_key }
    else { if (cur_e!="") { flush_interval(cur_s,cur_e,cur_cdekey,cur_day,cur_keys); cur_keys="" }; cur_s=s; cur_e=e; cur_cdekey=event_cdekey; cur_day=event_day; cur_keys=event_key }
    if (is_cb) { if (cur_e!="") { flush_interval(cur_s,cur_e,cur_cdekey,cur_day,cur_keys); cur_s=""; cur_e=""; cur_keys="" }; close_session(); current_cdekey=""; cur_cdekey="" }
}
END { if (cur_e!="") flush_interval(cur_s,cur_e,cur_cdekey,cur_day,cur_keys); close_session(); printf "collector stopped, TOTAL_MERGED_SECONDS=%.3f\n",total >> (OUT "/log/collector_sessions.log"); close(OUT "/log/collector_sessions.log"); if (append_failures>0) exit 1 }
'

exec 9>"$OUT/etc/collector.lock"; flock -n 9 || exit 0
if [ ! -s "$GENERATION_FILE" ]; then
    printf '%s-%s\n' "$(date +%s)" "$$" > "$GENERATION_FILE" || exit 1
fi
GENERATION=$(sed -n '1p' "$GENERATION_FILE")
[ -n "$GENERATION" ] || exit 1
JOURNAL="$OUT/etc/collector_pending_events"
run_awk() {
    journal_enabled="$1"
    shift
    awk -v OUT="$OUT" -v DB_PATH="$DB_PATH" -v APPENDER="$APPENDER" -v TIME_CONVERTER="$TIME_CONVERTER" -v generation="$GENERATION" -v GENERATION_FILE="$GENERATION_FILE" -v GENERATION_LOCK="$GENERATION_LOCK" -v state_file="$OUT/etc/collector_last_event" -v journal_file="$JOURNAL" -v journal_enabled="$journal_enabled" "$AWK_PROG" "$@"
}
if [ -s "$JOURNAL" ]; then
    if run_awk 0 "$JOURNAL"; then : > "$JOURNAL"; fi
fi
if [ "${1:-}" = "replay" ]; then
    if run_awk 1 "$2"; then : > "$JOURNAL"; exit 0; else exit 1; fi
fi
EVENT_FIFO="$OUT/etc/collector.events.$$"
mkfifo "$EVENT_FIFO" || exit 1
TAIL_JOB=""; AWK_JOB=""; GOING_JOB=""; OUT_JOB=""
cleanup() {
    trap - EXIT TERM INT
    [ -n "$TAIL_JOB" ] && kill "$TAIL_JOB" 2>/dev/null || true
    [ -n "$GOING_JOB" ] && kill "$GOING_JOB" 2>/dev/null || true
    [ -n "$OUT_JOB" ] && kill "$OUT_JOB" 2>/dev/null || true
    exec 3>&-
    [ -n "$TAIL_JOB" ] && wait "$TAIL_JOB" 2>/dev/null || true
    [ -n "$GOING_JOB" ] && wait "$GOING_JOB" 2>/dev/null || true
    [ -n "$OUT_JOB" ] && wait "$OUT_JOB" 2>/dev/null || true
    [ -n "$AWK_JOB" ] && wait "$AWK_JOB" 2>/dev/null || true
    rm -f "$EVENT_FIFO" "$OUT/etc/collector.pid"
}
trap 'exit 0' TERM INT
trap cleanup EXIT
echo $$ > "$OUT/etc/collector.pid"
renice 5 $$ >/dev/null 2>&1 || true
run_awk 1 < "$EVENT_FIFO" & AWK_JOB=$!
exec 3>"$EVENT_FIFO"
tail -F -n 0 "$LOG" 2>/dev/null >&3 & TAIL_JOB=$!

powerd_watch() {
    event="$1"
    while :; do
        if lipc-wait-event -m com.lab126.powerd "$event" >/dev/null 2>&1; then
            printf 'BOOKTRAIL_POWERD %s %s\n' "$event" "$(date +%s)" >&3
        else
            sleep 5
        fi
    done
}
if command -v lipc-wait-event >/dev/null 2>&1; then
    powerd_watch goingToScreenSaver 2>/dev/null & GOING_JOB=$!
    powerd_watch outOfScreenSaver 2>/dev/null & OUT_JOB=$!
fi
while kill -0 "$AWK_JOB" 2>/dev/null; do
    sleep 1
done
if wait "$AWK_JOB" 2>/dev/null; then
    : > "$JOURNAL"
fi
