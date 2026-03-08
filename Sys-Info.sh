#!/usr/bin/env bash
set -u

OUT_FILE="${1:-sys-info.txt}"
TMP_ERR="$(mktemp 2>/dev/null || echo /tmp/sysinfo_err.$$)"

# -----------------------------
# Helpers
# -----------------------------
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

run_cmd() {
  local title="$1"
  shift
  subsection "$title"
  {
    echo "+ Command: $*"
    echo
    "$@"
  } >> "$OUT_FILE" 2>>"$TMP_ERR" || {
    echo "[command failed: $*]" >> "$OUT_FILE"
  }
}

run_sh() {
  local title="$1"
  local cmd="$2"
  subsection "$title"
  {
    echo "+ Shell: $cmd"
    echo
    sh -c "$cmd"
  } >> "$OUT_FILE" 2>>"$TMP_ERR" || {
    echo "[shell command failed]" >> "$OUT_FILE"
  }
}

have() {
  command -v "$1" >/dev/null 2>&1
}

safe_cat() {
  local f="$1"
  subsection "File: $f"
  if [ -r "$f" ]; then
    cat "$f" >> "$OUT_FILE" 2>>"$TMP_ERR"
  else
    echo "[not readable or missing]" >> "$OUT_FILE"
  fi
}

print_kv() {
  printf "%-32s %s\n" "$1" "$2" >> "$OUT_FILE"
}

# -----------------------------
# Start
# -----------------------------
: > "$OUT_FILE"

section "SYS INFO REPORT"
line "Generated at: $(date -Is 2>/dev/null || date)"
line "Hostname: $(hostname 2>/dev/null || echo unknown)"
line "User: $(id 2>/dev/null | tr '\n' ' ' || echo unknown)"
line "PWD: $(pwd 2>/dev/null || echo unknown)"
line "Script: $0"
line "Output file: $OUT_FILE"

section "HIGH-LEVEL SUMMARY"
print_kv "OS" "$(uname -s 2>/dev/null || true)"
print_kv "Kernel" "$(uname -r 2>/dev/null || true)"
print_kv "Machine" "$(uname -m 2>/dev/null || true)"
print_kv "Processor" "$(uname -p 2>/dev/null || true)"
print_kv "Platform" "$(uname -i 2>/dev/null || true)"
print_kv "Uptime" "$(uptime 2>/dev/null || cat /proc/uptime 2>/dev/null || echo unknown)"
print_kv "Shell" "${SHELL:-unknown}"
print_kv "PATH" "${PATH:-unknown}"
print_kv "TERMUX_VERSION" "${TERMUX_VERSION:-not-set}"
print_kv "PREFIX" "${PREFIX:-not-set}"
print_kv "ANDROID_ROOT" "${ANDROID_ROOT:-not-set}"
print_kv "ANDROID_DATA" "${ANDROID_DATA:-not-set}"

section "OS / DISTRO / RELEASE"
run_cmd "uname -a" uname -a
safe_cat "/etc/os-release"
safe_cat "/proc/version"
safe_cat "/proc/cmdline"
safe_cat "/proc/sys/kernel/hostname"
safe_cat "/proc/sys/kernel/osrelease"
safe_cat "/proc/sys/kernel/ostype"

section "TERMUX / ANDROID CONTEXT"
run_sh "Detect Termux files and packages" '
  echo "PREFIX=${PREFIX:-}"
  echo "TMPDIR=${TMPDIR:-}"
  echo "HOME=$HOME"
  echo
  ls -ld /data/data/com.termux 2>/dev/null || true
  ls -ld /data/data/com.termux/files 2>/dev/null || true
  ls -ld /data/data/com.termux/files/usr 2>/dev/null || true
  ls -ld /sdcard 2>/dev/null || true
  ls -ld /storage/emulated/0 2>/dev/null || true
'
if have termux-info; then
  run_cmd "termux-info" termux-info
fi
if have getprop; then
  run_cmd "Android getprop" getprop
fi

section "CPU / THREADING / SCHEDULING"
safe_cat "/proc/cpuinfo"
safe_cat "/sys/devices/system/cpu/online"
safe_cat "/sys/devices/system/cpu/possible"
run_sh "CPU topology" '
  for f in /sys/devices/system/cpu/cpu*/topology/thread_siblings_list \
           /sys/devices/system/cpu/cpu*/topology/core_id \
           /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor \
           /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
  do
    [ -r "$f" ] && echo "### $f" && cat "$f" && echo
  done
'
run_sh "nproc and getconf" '
  echo "nproc: $(nproc 2>/dev/null || echo n/a)"
  echo "getconf _NPROCESSORS_ONLN: $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo n/a)"
  echo "getconf CLK_TCK: $(getconf CLK_TCK 2>/dev/null || echo n/a)"
'
safe_cat "/proc/loadavg"
safe_cat "/proc/stat"
safe_cat "/proc/interrupts"
safe_cat "/proc/softirqs"
safe_cat "/proc/schedstat"
safe_cat "/proc/sys/kernel/pid_max"
safe_cat "/proc/sys/kernel/threads-max"

section "MEMORY / SWAP"
run_cmd "free -h" free -h
safe_cat "/proc/meminfo"
safe_cat "/proc/swaps"
safe_cat "/proc/vmstat"
safe_cat "/proc/sys/vm/swappiness"
safe_cat "/proc/sys/vm/overcommit_memory"
safe_cat "/proc/sys/vm/overcommit_ratio"
safe_cat "/proc/sys/vm/max_map_count"
safe_cat "/proc/sys/vm/dirty_ratio"
safe_cat "/proc/sys/vm/dirty_background_ratio"

section "DISK / FILESYSTEM / IO"
run_cmd "df -hT" df -hT
run_cmd "df -hi" df -hi
run_cmd "mount" mount
safe_cat "/proc/mounts"
safe_cat "/proc/filesystems"
safe_cat "/proc/diskstats"
run_sh "Block devices" '
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -a -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINT,FSTYPE,MODEL,VENDOR,UUID 2>/dev/null
  else
    echo "lsblk not available"
  fi
'
run_sh "Writable directory checks" '
  for p in "$HOME" "$PWD" /tmp /var/tmp /sdcard /storage/emulated/0 /data/data/com.termux/files/usr/tmp; do
    [ -e "$p" ] || continue
    printf "%-40s exists " "$p"
    [ -d "$p" ] && printf "dir " || printf "not-dir "
    [ -w "$p" ] && printf "writable " || printf "not-writable "
    [ -x "$p" ] && printf "searchable " || printf "not-searchable "
    echo
  done
'

section "ULIMITS / PROCESS LIMITS / SECURITY"
run_cmd "ulimit -a" bash -lc 'ulimit -a'
safe_cat "/proc/self/limits"
safe_cat "/proc/sys/fs/file-max"
safe_cat "/proc/sys/fs/nr_open"
safe_cat "/proc/sys/kernel/random/entropy_avail"
run_sh "Security / SELinux / AppArmor hints" '
  if command -v sestatus >/dev/null 2>&1; then sestatus; else echo "sestatus not available"; fi
  if [ -r /sys/fs/selinux/enforce ]; then echo "SELinux enforce: $(cat /sys/fs/selinux/enforce)"; fi
  if [ -r /sys/module/apparmor/parameters/enabled ]; then echo "AppArmor enabled: $(cat /sys/module/apparmor/parameters/enabled)"; fi
'

section "NETWORK INTERFACES / ROUTES / DNS"
if have ip; then
  run_cmd "ip addr" ip addr
  run_cmd "ip route" ip route
  run_cmd "ip -s link" ip -s link
else
  run_cmd "ifconfig -a" ifconfig -a
  run_cmd "netstat -rn" netstat -rn
fi
safe_cat "/etc/resolv.conf"
safe_cat "/etc/hosts"
safe_cat "/proc/net/dev"
safe_cat "/proc/net/route"
safe_cat "/proc/net/tcp"
safe_cat "/proc/net/tcp6"
safe_cat "/proc/net/udp"
safe_cat "/proc/net/udp6"

run_sh "DNS / hostname resolution" '
  echo "hostname -f: $(hostname -f 2>/dev/null || echo n/a)"
  echo "getent hosts localhost:"
  getent hosts localhost 2>/dev/null || true
  echo
  echo "getent hosts example.com:"
  getent hosts example.com 2>/dev/null || true
'

run_sh "Outbound connectivity probe headers only" '
  for url in \
    https://example.com \
    https://www.google.com \
    https://www.cloudflare.com
  do
    echo "### $url"
    if command -v curl >/dev/null 2>&1; then
      curl -I -L --max-time 15 --connect-timeout 8 -A "sys-info-probe/1.0" "$url" 2>&1 | sed -n "1,20p"
    else
      echo "curl not available"
    fi
    echo
  done
'

section "PROXY / ENVIRONMENT VARIABLES"
run_sh "Relevant environment variables" '
  env | sort | grep -Ei "^(http|https|ftp|all|no)_proxy=|^(HTTP|HTTPS|FTP|ALL|NO)_PROXY=|^LANG=|^LC_|^TZ=|^TMPDIR=|^HOME=|^USER=|^LOGNAME=|^SHELL=|^PATH=|^PREFIX=|^ANDROID_|^TERMUX_|^TMP=|^TEMP=" || true
'

section "TIME / LOCALE"
run_cmd "date" date
if have timedatectl; then
  run_cmd "timedatectl" timedatectl
fi
run_cmd "locale" locale
safe_cat "/etc/timezone"
run_sh "Timezone symlink" 'ls -l /etc/localtime 2>/dev/null || true'

section "OPEN FILES / SOCKETS / PORT USAGE"
if have ss; then
  run_cmd "ss -tulpen" ss -tulpen
elif have netstat; then
  run_cmd "netstat -tulpen" netstat -tulpen
fi
if have lsof; then
  run_cmd "lsof summary" lsof -nP | sed -n '1,200p'
fi

section "INSTALLED TOOLS RELEVANT TO A PHP CRAWLER"
run_sh "Tool presence and versions" '
  for cmd in \
    bash sh busybox coreutils grep sed awk find xargs sort uniq cut tr \
    curl wget openssl php php-cgi php-fpm composer pecl pear \
    mysql mariadb mysqld mariadbd mysqladmin mysqldump mariadb-dump \
    sqlite3 git tar unzip zip gzip bzip2 xz file stat \
    timeout flock screen tmux nohup ionice nice renice \
    dig nslookup host ping traceroute tracepath \
    jq yq perl python python3 node npm \
    ffmpeg imagemagick convert identify
  do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "%-18s FOUND at %s\n" "$cmd" "$(command -v "$cmd")"
      "$cmd" --version 2>/dev/null | head -n 3 || "$cmd" -V 2>/dev/null | head -n 3 || true
      echo
    else
      printf "%-18s MISSING\n\n" "$cmd"
    fi
  done
'

section "PHP OVERVIEW"
if have php; then
  run_cmd "php -v" php -v
  run_cmd "php --ini" php --ini
  run_cmd "php -m" php -m
  run_cmd "php -i (first 300 lines)" bash -lc 'php -i 2>/dev/null | sed -n "1,300p"'
  run_cmd "php loaded extensions detail" bash -lc 'php -r "echo json_encode(get_loaded_extensions(), JSON_PRETTY_PRINT), PHP_EOL;"'
  run_cmd "php selected runtime settings" bash -lc '
    php -r "
      \$keys = [
        \"memory_limit\",
        \"max_execution_time\",
        \"max_input_time\",
        \"default_socket_timeout\",
        \"user_agent\",
        \"allow_url_fopen\",
        \"display_errors\",
        \"log_errors\",
        \"error_log\",
        \"post_max_size\",
        \"upload_max_filesize\",
        \"output_buffering\",
        \"zlib.output_compression\",
        \"realpath_cache_size\",
        \"realpath_cache_ttl\",
        \"disable_functions\",
        \"open_basedir\",
        \"curl.cainfo\",
        \"openssl.cafile\",
        \"openssl.capath\",
        \"sys_temp_dir\",
        \"mysqli.default_socket\",
        \"pdo_mysql.default_socket\",
        \"mysqlnd.collect_statistics\",
        \"mysqlnd.collect_memory_statistics\",
        \"hard_timeout\"
      ];
      foreach (\$keys as \$k) {
        echo str_pad(\$k, 32), ini_get(\$k), PHP_EOL;
      }
    "
  '
  run_cmd "php curl capabilities" bash -lc '
    php -r "
      if (!function_exists(\"curl_version\")) {
        echo \"cURL extension NOT loaded\n\";
        exit(0);
      }
      print_r(curl_version());
    "
  '
  run_cmd "php openssl info" bash -lc '
    php -r "
      echo \"OPENSSL_VERSION_TEXT: \", (defined(\"OPENSSL_VERSION_TEXT\") ? OPENSSL_VERSION_TEXT : \"n/a\"), PHP_EOL;
      echo \"openssl extension loaded: \", (extension_loaded(\"openssl\") ? \"yes\" : \"no\"), PHP_EOL;
    "
  '
  run_cmd "php stream wrappers" bash -lc '
    php -r "print_r(stream_get_wrappers());"
  '
else
  subsection "php"
  line "php not found in PATH"
fi

section "PHP CRAWLER-SPECIFIC READINESS"
run_sh "php readiness notes from environment" '
  echo "Checking likely crawler concerns..."
  echo

  echo "[1] Can PHP run at all?"
  if command -v php >/dev/null 2>&1; then
    php -r "echo \"PHP OK\n\";" 2>/dev/null || echo "PHP execution failed"
  else
    echo "PHP missing"
  fi

  echo
  echo "[2] cURL extension present?"
  if command -v php >/dev/null 2>&1; then
    php -r "echo extension_loaded(\"curl\") ? \"curl=yes\n\" : \"curl=no\n\";" 2>/dev/null || true
  fi

  echo
  echo "[3] PDO / mysqli present?"
  if command -v php >/dev/null 2>&1; then
    php -r "
      echo 'pdo=' . (extension_loaded('pdo') ? 'yes' : 'no') . PHP_EOL;
      echo 'pdo_mysql=' . (extension_loaded('pdo_mysql') ? 'yes' : 'no') . PHP_EOL;
      echo 'mysqli=' . (extension_loaded('mysqli') ? 'yes' : 'no') . PHP_EOL;
      echo 'sqlite3=' . (extension_loaded('sqlite3') ? 'yes' : 'no') . PHP_EOL;
    " 2>/dev/null || true
  fi

  echo
  echo "[4] pcntl / parallelism helpers?"
  if command -v php >/dev/null 2>&1; then
    php -r "
      echo 'pcntl=' . (extension_loaded('pcntl') ? 'yes' : 'no') . PHP_EOL;
      echo 'posix=' . (extension_loaded('posix') ? 'yes' : 'no') . PHP_EOL;
      echo 'pthreads=' . (extension_loaded('pthreads') ? 'yes' : 'no') . PHP_EOL;
      echo 'parallel=' . (extension_loaded('parallel') ? 'yes' : 'no') . PHP_EOL;
    " 2>/dev/null || true
  fi

  echo
  echo "[5] SQLite fallback?"
  if command -v php >/dev/null 2>&1; then
    php -r "
      echo 'pdo_sqlite=' . (extension_loaded('pdo_sqlite') ? 'yes' : 'no') . PHP_EOL;
      echo 'sqlite3=' . (extension_loaded('sqlite3') ? 'yes' : 'no') . PHP_EOL;
    " 2>/dev/null || true
  fi
'

section "CA CERTIFICATES / TLS / OPENSSL"
run_sh "Possible CA bundle locations" '
  for f in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/cert.pem \
    /etc/pki/tls/certs/ca-bundle.crt \
    /system/etc/security/cacerts \
    /data/data/com.termux/files/usr/etc/tls/cert.pem \
    /data/data/com.termux/files/usr/etc/openssl/cert.pem
  do
    if [ -e "$f" ]; then
      echo "FOUND: $f"
      ls -ld "$f"
    else
      echo "MISSING: $f"
    fi
  done
'
if have openssl; then
  run_cmd "openssl version -a" openssl version -a
fi
if have curl; then
  run_cmd "curl -V" curl -V
fi

section "MARIADB / MYSQL"
run_sh "Client and server binaries" '
  for cmd in mysql mariadb mysqld mariadbd mysqladmin mysqldump mariadb-dump mysql_config mariadb-config; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "FOUND: $cmd -> $(command -v "$cmd")"
      "$cmd" --version 2>/dev/null || true
    else
      echo "MISSING: $cmd"
    fi
    echo
  done
'
run_sh "MySQL config file candidates" '
  for f in \
    /etc/my.cnf \
    /etc/mysql/my.cnf \
    /etc/mysql/mariadb.conf.d \
    /data/data/com.termux/files/usr/etc/my.cnf \
    /data/data/com.termux/files/usr/etc/mysql/my.cnf
  do
    if [ -e "$f" ]; then
      echo "### $f"
      ls -ld "$f"
      [ -f "$f" ] && sed -n "1,250p" "$f"
      [ -d "$f" ] && find "$f" -maxdepth 2 -type f | sort
      echo
    fi
  done
'
run_sh "MySQL process hints" '
  ps aux 2>/dev/null | grep -Ei "mariadb|mysqld" | grep -v grep || true
'
if have mysqladmin; then
  run_cmd "mysqladmin variables (may require auth)" mysqladmin variables
fi

section "SYSCTL / KERNEL TUNING RELEVANT TO LONG-RUNNING NETWORK WORKLOADS"
run_sh "Selected sysctl values" '
  for k in \
    net.core.somaxconn \
    net.core.netdev_max_backlog \
    net.ipv4.ip_local_port_range \
    net.ipv4.tcp_fin_timeout \
    net.ipv4.tcp_tw_reuse \
    net.ipv4.tcp_keepalive_time \
    net.ipv4.tcp_keepalive_intvl \
    net.ipv4.tcp_keepalive_probes \
    net.ipv4.tcp_syn_retries \
    net.ipv4.tcp_synack_retries \
    net.ipv4.tcp_max_syn_backlog \
    net.ipv4.tcp_mtu_probing \
    net.ipv4.tcp_sack \
    net.ipv4.tcp_timestamps \
    net.ipv4.tcp_window_scaling \
    net.ipv4.tcp_rmem \
    net.ipv4.tcp_wmem \
    net.ipv4.tcp_mem \
    fs.file-max \
    vm.swappiness \
    vm.overcommit_memory \
    vm.max_map_count \
    kernel.pid_max \
    kernel.threads-max
  do
    if command -v sysctl >/dev/null 2>&1; then
      sysctl "$k" 2>/dev/null || true
    else
      p="/proc/sys/$(echo "$k" | tr . /)"
      [ -r "$p" ] && echo "$k = $(cat "$p")"
    fi
  done
'

section "PROCESS SNAPSHOT"
run_cmd "ps aux" ps aux
run_sh "Top processes by memory and cpu" '
  ps -eo pid,ppid,user,%cpu,%mem,nlwp,rss,vsz,etime,stat,comm,args --sort=-%mem 2>/dev/null | sed -n "1,60p"
  echo
  ps -eo pid,ppid,user,%cpu,%mem,nlwp,rss,vsz,etime,stat,comm,args --sort=-%cpu 2>/dev/null | sed -n "1,60p"
'

section "CRON / SERVICE / SESSION TOOLS"
run_sh "Service/session manager presence" '
  for cmd in systemctl service rc-service crontab at tmux screen nohup; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "FOUND: $cmd -> $(command -v "$cmd")"
      "$cmd" --version 2>/dev/null | head -n 3 || true
    else
      echo "MISSING: $cmd"
    fi
    echo
  done
'
run_sh "crontab -l" 'crontab -l 2>/dev/null || echo "no crontab or not available"'

section "BENCHMARK-ISH MICRO CHECKS"
run_sh "Disk write temp check" '
  d="${TMPDIR:-/tmp}"
  f="$d/sysinfo_write_test.$$"
  echo "Temp dir: $d"
  if [ -d "$d" ] && [ -w "$d" ]; then
    START=$(date +%s 2>/dev/null || true)
    dd if=/dev/zero of="$f" bs=1M count=16 conv=fsync 2>&1
    END=$(date +%s 2>/dev/null || true)
    rm -f "$f"
    echo "Elapsed seconds: $((END-START))"
  else
    echo "Temp dir not writable"
  fi
'
run_sh "DNS timing check with curl" '
  if command -v curl >/dev/null 2>&1; then
    curl -o /dev/null -sS -L --max-time 20 \
      -w "namelookup=%{time_namelookup}\nconnect=%{time_connect}\nappconnect=%{time_appconnect}\nstarttransfer=%{time_starttransfer}\ntotal=%{time_total}\nremote_ip=%{remote_ip}\nhttp_code=%{http_code}\n" \
      https://example.com
  else
    echo "curl not available"
  fi
'

section "PATHS THAT MAY MATTER TO A NON-DOWNLOADING IMAGE CRAWLER"
run_sh "Common storage and app paths" '
  for p in \
    "$HOME" \
    "$PWD" \
    "${TMPDIR:-}" \
    /tmp \
    /var/tmp \
    /sdcard \
    /storage/emulated/0 \
    /data/data/com.termux/files/home \
    /data/data/com.termux/files/usr \
    /data/data/com.termux/files/usr/tmp
  do
    [ -n "$p" ] || continue
    [ -e "$p" ] || continue
    echo "### $p"
    ls -ld "$p"
    df -h "$p" 2>/dev/null || true
    echo
  done
'

section "APP DESIGN NOTES THIS MACHINE SHOULD INFORM"
line "These machine facts are especially relevant to a long-running PHP cURL MariaDB image crawler:"
line "1. CPU cores / nlwp capacity affect curl_multi concurrency and worker count."
line "2. RAM and swap affect queue size, response buffering, DOM parsing, and DB batching."
line "3. fs.file-max and ulimits affect open sockets, file descriptors, temp files, and logs."
line "4. Network and DNS latency affect connection pooling, retry logic, and timeout settings."
line "5. PHP extensions determine whether curl, mysqli/pdo_mysql, pcntl, sqlite, and openssl are usable."
line "6. CA bundle paths affect HTTPS verification."
line "7. MariaDB presence/config affects whether queue, dedupe, and crawl-state should live in DB."
line "8. Disk and writable paths affect logs, temp data, checkpoints, URL frontier snapshots, and exports."
line "9. On Android/Termux, background survival, storage permissions, and power management matter a lot."
line "10. Since the crawler does NOT download images, HTTP HEAD/GET strategy, content-type filtering, URL dedupe, robots policy, and metadata extraction matter more than disk bandwidth."

section "STDERR / FAILURES DURING COLLECTION"
if [ -s "$TMP_ERR" ]; then
  cat "$TMP_ERR" >> "$OUT_FILE"
else
  line "[no stderr captured]"
fi

rm -f "$TMP_ERR"

section "DONE"
line "Report complete: $OUT_FILE"

echo "Wrote $OUT_FILE"
