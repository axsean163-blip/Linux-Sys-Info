#!/usr/bin/env bash
set -u

OUT_FILE="${1:-termux-crawler-sys-info.txt}"
ERR_FILE="${TMPDIR:-/tmp}/termux-crawler-probe.$$.$RANDOM.err"

: > "$OUT_FILE"
: > "$ERR_FILE"

section() {
    {
        echo
        echo "============================================================"
        echo "$1"
        echo "============================================================"
    } >> "$OUT_FILE"
}

subsection() {
    {
        echo
        echo "---- $1 ----"
    } >> "$OUT_FILE"
}

line() {
    echo "$1" >> "$OUT_FILE"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

run_cmd() {
    local title="$1"
    shift
    subsection "$title"
    {
        echo "+ Command: $*"
        echo
        "$@"
    } >> "$OUT_FILE" 2>>"$ERR_FILE" || echo "[command failed]" >> "$OUT_FILE"
}

run_sh() {
    local title="$1"
    local cmd="$2"
    subsection "$title"
    {
        echo "+ Shell: $cmd"
        echo
        sh -c "$cmd"
    } >> "$OUT_FILE" 2>>"$ERR_FILE" || echo "[shell failed]" >> "$OUT_FILE"
}

safe_cat() {
    local file="$1"
    subsection "File: $file"
    if [ -r "$file" ]; then
        cat "$file" >> "$OUT_FILE" 2>>"$ERR_FILE"
    else
        echo "[not readable or not found]" >> "$OUT_FILE"
    fi
}

get_php_ini_value() {
    local key="$1"
    php -r "echo ini_get('$key');" 2>/dev/null
}

get_php_ext() {
    local ext="$1"
    php -r "echo extension_loaded('$ext') ? 'yes' : 'no';" 2>/dev/null
}

get_total_mem_mb() {
    awk '/MemTotal:/ {printf "%.0f\n", $2/1024}' /proc/meminfo 2>/dev/null
}

get_cpu_cores() {
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}

recommend_workers() {
    local cores="$1"
    local mem_mb="$2"

    if [ -z "$cores" ] || [ "$cores" -lt 1 ] 2>/dev/null; then
        cores=1
    fi
    if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1 ] 2>/dev/null; then
        mem_mb=1024
    fi

    # Conservative mobile-safe worker suggestion for long-running PHP curl_multi workloads
    if [ "$mem_mb" -lt 1500 ]; then
        echo $(( cores < 2 ? 1 : 2 ))
    elif [ "$mem_mb" -lt 3000 ]; then
        echo $(( cores < 4 ? cores : 4 ))
    elif [ "$mem_mb" -lt 5000 ]; then
        echo $(( cores < 6 ? cores : 6 ))
    else
        echo $(( cores < 8 ? cores : 8 ))
    fi
}

recommend_curl_concurrency() {
    local cores="$1"
    local mem_mb="$2"

    if [ -z "$cores" ] || [ "$cores" -lt 1 ] 2>/dev/null; then
        cores=1
    fi
    if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1 ] 2>/dev/null; then
        mem_mb=1024
    fi

    # For non-downloading crawlers, metadata-only fetches can safely run higher concurrency than media downloads
    local by_cpu=$(( cores * 8 ))
    local by_mem=$(( mem_mb / 180 ))

    [ "$by_cpu" -lt 4 ] && by_cpu=4
    [ "$by_mem" -lt 4 ] && by_mem=4

    if [ "$by_cpu" -lt "$by_mem" ]; then
        echo "$by_cpu"
    else
        echo "$by_mem"
    fi
}

recommend_db_batch() {
    local mem_mb="$1"
    if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1 ] 2>/dev/null; then
        mem_mb=1024
    fi

    if [ "$mem_mb" -lt 1500 ]; then
        echo 25
    elif [ "$mem_mb" -lt 3000 ]; then
        echo 50
    elif [ "$mem_mb" -lt 5000 ]; then
        echo 100
    else
        echo 200
    fi
}

# Gather basics
CORES="$(get_cpu_cores)"
MEM_MB="$(get_total_mem_mb)"
WORKERS="$(recommend_workers "$CORES" "$MEM_MB")"
CURL_CONCURRENCY="$(recommend_curl_concurrency "$CORES" "$MEM_MB")"
DB_BATCH="$(recommend_db_batch "$MEM_MB")"

section "TERMUX CRAWLER PROBE REPORT"
line "Generated at: $(date -Is 2>/dev/null || date)"
line "Hostname: $(hostname 2>/dev/null || echo unknown)"
line "User: $(id 2>/dev/null | tr '\n' ' ' || echo unknown)"
line "PWD: $(pwd 2>/dev/null || echo unknown)"

section "QUICK SUMMARY"
line "CPU cores detected: $CORES"
line "Total memory MB: $MEM_MB"
line "Suggested worker processes: $WORKERS"
line "Suggested curl_multi concurrency: $CURL_CONCURRENCY"
line "Suggested DB batch size: $DB_BATCH"

section "TERMUX / ANDROID"
if have termux-info; then
    run_cmd "termux-info" termux-info
else
    subsection "termux-info"
    line "termux-info not found"
    line "TERMUX_VERSION=${TERMUX_VERSION:-not-set}"
    line "PREFIX=${PREFIX:-not-set}"
    line "HOME=${HOME:-not-set}"
fi

if have getprop; then
    run_cmd "getprop" getprop
else
    subsection "getprop"
    line "getprop not found"
fi

run_sh "Termux path checks" '
for p in \
  "$HOME" \
  "${PREFIX:-}" \
  /data/data/com.termux \
  /data/data/com.termux/files \
  /data/data/com.termux/files/usr \
  /data/data/com.termux/files/home \
  /sdcard \
  /storage/emulated/0
do
  [ -n "$p" ] || continue
  [ -e "$p" ] || continue
  echo "### $p"
  ls -ld "$p"
  echo
done
'

section "OS / KERNEL / CPU"
run_cmd "uname -a" uname -a
safe_cat "/proc/version"
safe_cat "/proc/cpuinfo"
safe_cat "/proc/loadavg"
safe_cat "/proc/stat"
safe_cat "/sys/devices/system/cpu/online"

run_sh "CPU governor and freq" '
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor \
         /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq \
         /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq \
         /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq
do
  [ -r "$f" ] && echo "### $f" && cat "$f" && echo
done
'

section "MEMORY / STORAGE"
run_cmd "free -h" free -h
safe_cat "/proc/meminfo"
safe_cat "/proc/swaps"
run_cmd "df -hT" df -hT
run_cmd "df -hi" df -hi
safe_cat "/proc/mounts"

run_sh "Writable crawl paths" '
for p in \
  "$HOME" \
  "$HOME/.crawler" \
  "$HOME/tmp" \
  "${TMPDIR:-}" \
  /data/data/com.termux/files/usr/tmp \
  /sdcard \
  /storage/emulated/0
do
  [ -n "$p" ] || continue
  if [ -e "$p" ]; then
    printf "%-45s exists " "$p"
    [ -d "$p" ] && printf "dir " || printf "not-dir "
    [ -w "$p" ] && printf "writable " || printf "not-writable "
    [ -x "$p" ] && printf "searchable " || printf "not-searchable "
    echo
  else
    printf "%-45s missing\n" "$p"
  fi
done
'

section "POWER / BATTERY / THERMAL"
if have termux-battery-status; then
    run_cmd "termux-battery-status" termux-battery-status
else
    subsection "termux-battery-status"
    line "termux-battery-status not found"
fi

run_sh "Battery and power hints from Android" '
for cmd in dumpsys; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "### dumpsys battery"
    dumpsys battery 2>/dev/null | sed -n "1,120p"
    echo
    echo "### dumpsys deviceidle"
    dumpsys deviceidle 2>/dev/null | sed -n "1,120p"
    echo
    echo "### dumpsys power"
    dumpsys power 2>/dev/null | sed -n "1,120p"
    echo
    break
  fi
done
'

run_sh "Thermal zones" '
for f in /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$f" ] && echo "### $f" && cat "$f" && echo
done
'

section "LIMITS / FD / THREADING"
run_cmd "ulimit -a" bash -lc 'ulimit -a'
safe_cat "/proc/self/limits"
safe_cat "/proc/sys/fs/file-max"
safe_cat "/proc/sys/fs/nr_open"
safe_cat "/proc/sys/kernel/threads-max"
safe_cat "/proc/sys/kernel/pid_max"

section "NETWORK / DNS / SOCKETS"
if have ip; then
    run_cmd "ip addr" ip addr
    run_cmd "ip route" ip route
else
    subsection "network"
    line "ip command not found"
fi

safe_cat "/etc/resolv.conf"
safe_cat "/proc/net/dev"
safe_cat "/proc/net/tcp"
safe_cat "/proc/net/tcp6"
safe_cat "/proc/net/udp"
safe_cat "/proc/net/udp6"

if have curl; then
    run_cmd "curl -V" curl -V
    run_sh "curl timing probe" '
curl -o /dev/null -sS -L --max-time 20 \
  -w "namelookup=%{time_namelookup}\nconnect=%{time_connect}\nappconnect=%{time_appconnect}\nstarttransfer=%{time_starttransfer}\ntotal=%{time_total}\nremote_ip=%{remote_ip}\nhttp_code=%{http_code}\n" \
  https://example.com
'
else
    subsection "curl"
    line "curl not found"
fi

section "TLS / CERTIFICATES"
if have openssl; then
    run_cmd "openssl version -a" openssl version -a
else
    subsection "openssl"
    line "openssl not found"
fi

run_sh "Likely CA bundle locations" '
for f in \
  /data/data/com.termux/files/usr/etc/tls/cert.pem \
  /data/data/com.termux/files/usr/etc/openssl/cert.pem \
  /etc/ssl/certs/ca-certificates.crt \
  /etc/ssl/cert.pem \
  /system/etc/security/cacerts
do
  if [ -e "$f" ]; then
    echo "FOUND: $f"
    ls -ld "$f"
  else
    echo "MISSING: $f"
  fi
done
'

section "PHP"
if have php; then
    run_cmd "php -v" php -v
    run_cmd "php --ini" php --ini
    run_cmd "php -m" php -m
    run_cmd "php selected ini values" bash -lc '
php -r "
\$keys = [
  \"memory_limit\",
  \"max_execution_time\",
  \"default_socket_timeout\",
  \"user_agent\",
  \"allow_url_fopen\",
  \"display_errors\",
  \"log_errors\",
  \"error_log\",
  \"curl.cainfo\",
  \"openssl.cafile\",
  \"openssl.capath\",
  \"sys_temp_dir\",
  \"mysqli.default_socket\",
  \"pdo_mysql.default_socket\"
];
foreach (\$keys as \$k) {
  echo str_pad(\$k, 32), ini_get(\$k), PHP_EOL;
}
"
'
    run_cmd "PHP extensions readiness" bash -lc '
php -r "
\$exts = [\"curl\",\"openssl\",\"pdo\",\"pdo_mysql\",\"mysqli\",\"sqlite3\",\"pdo_sqlite\",\"pcntl\",\"posix\"];
foreach (\$exts as \$e) {
  echo str_pad(\$e, 16), (extension_loaded(\$e) ? \"yes\" : \"no\"), PHP_EOL;
}
"
'
    run_cmd "PHP cURL capabilities" bash -lc '
php -r "
if (function_exists(\"curl_version\")) {
  print_r(curl_version());
} else {
  echo \"curl extension not loaded\n\";
}
"
'
else
    subsection "php"
    line "php not found"
fi

section "MARIADB / MYSQL"
run_sh "MariaDB and MySQL binary presence" '
for cmd in mariadb mysql mariadbd mysqld mysqladmin mysqldump mariadb-dump; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "FOUND: $cmd -> $(command -v "$cmd")"
    "$cmd" --version 2>/dev/null || true
  else
    echo "MISSING: $cmd"
  fi
  echo
done
'

run_sh "Possible MariaDB config files" '
for f in \
  /data/data/com.termux/files/usr/etc/my.cnf \
  /data/data/com.termux/files/usr/etc/mysql/my.cnf \
  /etc/my.cnf \
  /etc/mysql/my.cnf
do
  if [ -e "$f" ]; then
    echo "### $f"
    ls -ld "$f"
    [ -f "$f" ] && sed -n "1,200p" "$f"
    echo
  fi
done
'

run_sh "MariaDB process hints" '
ps aux 2>/dev/null | grep -Ei "maria|mysql" | grep -v grep || true
'

section "CRAWLER-SPECIFIC PRACTICAL RECOMMENDATIONS"

PHP_MEMORY_LIMIT="$(get_php_ini_value memory_limit)"
PHP_MAX_EXEC="$(get_php_ini_value max_execution_time)"
PHP_SOCKET_TIMEOUT="$(get_php_ini_value default_socket_timeout)"
PHP_CURL_EXT="$(get_php_ext curl)"
PHP_PDO_MYSQL="$(get_php_ext pdo_mysql)"
PHP_MYSQLI="$(get_php_ext mysqli)"
PHP_SQLITE3="$(get_php_ext sqlite3)"
PHP_PCNTL="$(get_php_ext pcntl)"
PHP_POSIX="$(get_php_ext posix)"

line "Recommended architecture notes:"
line "- Use a frontier queue in MariaDB or SQLite."
line "- Since images are NOT downloaded, store metadata only: page_url, image_url, referrer, alt, title, width, height, mime, status, timestamps, hash-of-url."
line "- Prefer curl_multi with bounded concurrency instead of unbounded threading."
line "- Use checkpointing every 25 to 200 URLs depending on memory and DB speed."
line "- Keep HTML bodies and parsed DOMs out of long-lived arrays."
line "- Stream logs to files, not giant in-memory buffers."
line "- Use HEAD where safe, but fall back to GET because many sites lie or block HEAD."
line "- Deduplicate aggressively by canonicalized URL and by normalized image URL."

line ""
line "Detected PHP signals:"
line "php memory_limit           : ${PHP_MEMORY_LIMIT:-unknown}"
line "php max_execution_time     : ${PHP_MAX_EXEC:-unknown}"
line "php default_socket_timeout : ${PHP_SOCKET_TIMEOUT:-unknown}"
line "php ext curl               : ${PHP_CURL_EXT:-unknown}"
line "php ext pdo_mysql          : ${PHP_PDO_MYSQL:-unknown}"
line "php ext mysqli             : ${PHP_MYSQLI:-unknown}"
line "php ext sqlite3            : ${PHP_SQLITE3:-unknown}"
line "php ext pcntl              : ${PHP_PCNTL:-unknown}"
line "php ext posix              : ${PHP_POSIX:-unknown}"

line ""
line "Suggested starting crawler config:"
line "worker_processes           = $WORKERS"
line "curl_multi_concurrency     = $CURL_CONCURRENCY"
line "db_batch_size              = $DB_BATCH"
line "dns_cache_ttl_seconds      = 300"
line "connect_timeout_seconds    = 10"
line "request_timeout_seconds    = 20"
line "low_speed_time_seconds     = 15"
line "max_redirects              = 5"
line "per_host_concurrency       = 2"
line "retry_attempts             = 2"
line "retry_backoff_ms           = 800"
line "checkpoint_every_urls      = $DB_BATCH"
line "log_flush_interval_secs    = 5"

line ""
line "Termux / Android survival hints:"
line "- Keep screen awake or use a wakelock if available."
line "- Disable battery optimization for Termux in Android settings."
line "- Prefer running while charging for long crawls."
line "- Watch thermal throttling on sustained concurrency."
line "- Use internal app storage for queue DB and logs when possible."
line "- Use /sdcard mainly for exports, not hot DB writes."

section "OPTIONAL TERMUX WAKELOCK / JOB CONTROL"
if have termux-wake-lock; then
    line "termux-wake-lock is available"
else
    line "termux-wake-lock is not available"
fi

if have termux-job-scheduler; then
    line "termux-job-scheduler is available"
else
    line "termux-job-scheduler is not available"
fi

run_sh "Session tools" '
for cmd in tmux screen nohup flock; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "FOUND: $cmd -> $(command -v "$cmd")"
  else
    echo "MISSING: $cmd"
  fi
done
'

section "STDERR CAPTURED"
if [ -s "$ERR_FILE" ]; then
    cat "$ERR_FILE" >> "$OUT_FILE"
else
    line "[none]"
fi

rm -f "$ERR_FILE"

section "DONE"
line "Wrote report to: $OUT_FILE"

echo "Wrote $OUT_FILE"
