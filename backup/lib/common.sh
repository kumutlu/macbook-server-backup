#!/usr/bin/env bash
# MacBook Server Backup - ortak yardımcılar
# Tüm betikler bu dosyayı "source" eder. Sır içermez.

set -Eeuo pipefail

MB_CONFIG="${MB_CONFIG:-/etc/macbook-backup/macbook-backup.conf}"
MB_LOG_DIR="${MB_LOG_DIR:-/var/log/macbook-backup}"
MB_STATE_DIR="${MB_STATE_DIR:-/var/lib/macbook-backup}"
MB_STAGING_DIR="${MB_STAGING_DIR:-/var/backups/macbook-server}"
MB_HOOKS_DIR="${MB_HOOKS_DIR:-/etc/macbook-backup/hooks}"

mb_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
info()  { printf '%s INFO  %s\n' "$(mb_ts)" "$*"; }
warn()  { printf '%s WARN  %s\n' "$(mb_ts)" "$*" >&2; }
err()   { printf '%s ERROR %s\n' "$(mb_ts)" "$*" >&2; }

die() {
  local code="${MB_DIE_CODE:-1}"
  err "$*"
  exit "$code"
}

# Başarısızlıkta tek satırlık tanılama + isteğe bağlı bildirim.
mb_on_error() {
  local rc=$?
  local where="${BASH_LINENO[0]:-?}"
  err "başarısız komut (satır ${where}, çıkış ${rc}): ${BASH_COMMAND:-bilinmiyor}"
  notify fail "yedek başarısız (çıkış ${rc})"
  exit "$rc"
}

notify() {
  local state="$1" msg="${2:-}"
  [ -n "${MB_NOTIFY_URL:-}" ] || return 0
  local url="$MB_NOTIFY_URL"
  if [ "$state" = "fail" ]; then url="${url%/}/fail"; fi
  # URL bir sırdır; loglanmaz.
  curl -fsS -m 15 --retry 2 -o /dev/null "$url" 2>/dev/null \
    || warn "bildirim gönderilemedi (ağ veya URL hatası): ${msg}"
  return 0
}

load_config() {
  [ -r "$MB_CONFIG" ] || die "yapılandırma okunamadı: $MB_CONFIG (örnek: etc/macbook-backup.conf.example)"
  # Kurulumda "MB_AUTO_INIT=1 mb-backup.sh" ile tek seferlik depo oluşturma: ortam kazanır.
  local auto_init_env="${MB_AUTO_INIT-}"
  # shellcheck disable=SC1090
  . "$MB_CONFIG"
  [ -n "$auto_init_env" ] && MB_AUTO_INIT="$auto_init_env"

  : "${MB_REPOSITORY:?MB_REPOSITORY tanımlı değil (yapılandırma: $MB_CONFIG)}"
  : "${MB_BACKUP_PATHS[*]:?MB_BACKUP_PATHS boş}"

  MB_HOST="${MB_HOST:-$(hostname -s 2>/dev/null || hostname)}"
  MB_KEEP_DAILY="${MB_KEEP_DAILY:-30}"
  MB_KEEP_WEEKLY="${MB_KEEP_WEEKLY:-8}"
  MB_KEEP_MONTHLY="${MB_KEEP_MONTHLY:-12}"
  MB_KEEP_YEARLY="${MB_KEEP_YEARLY:-2}"
  MB_CHECK_DAY="${MB_CHECK_DAY:-7}"
  MB_CHECK_SUBSET="${MB_CHECK_SUBSET:-5%}"
  MB_AUTO_INIT="${MB_AUTO_INIT:-0}"
  MB_RETRY_LOCK="${MB_RETRY_LOCK:-10m}"
  MB_TAG="${MB_TAG:-macbook-server}"
  MB_COMPRESSION="${MB_COMPRESSION:-auto}"
}

prepare_env() {
  export RESTIC_REPOSITORY="$MB_REPOSITORY"
  if [ -n "${MB_PASSWORD_FILE:-}" ]; then
    export RESTIC_PASSWORD_FILE="$MB_PASSWORD_FILE"
  fi
  if [ -n "${MB_RCLONE_CONFIG:-}" ]; then
    export RCLONE_CONFIG="$MB_RCLONE_CONFIG"
  fi
  export RESTIC_CACHE_DIR="${MB_CACHE_DIR:-${MB_STATE_DIR}/restic-cache}"
  export RESTIC_PROGRESS_FPS="${RESTIC_PROGRESS_FPS:-0}"
  export RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
  mkdir -p "$RESTIC_CACHE_DIR" "$MB_STAGING_DIR" "$MB_LOG_DIR"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "gerekli araç bulunamadı: $1"
}

acquire_lock() {
  local f="${MB_STATE_DIR}/backup.lock"
  mkdir -p "$MB_STATE_DIR"
  exec 9>"$f"
  if ! flock -n 9; then
    # Eşzamanlı çalışma depoyu bozmasın: sessizce beklemek yerine açıkça reddet.
    MB_DIE_CODE=75 die "başka bir yedek çalışması sürüyor (kilit: $f)"
  fi
  info "kilit alındı: $f"
}

check_password_file() {
  [ -n "${MB_PASSWORD_FILE:-}" ] || die "MB_PASSWORD_FILE tanımlı değil"
  [ -r "$MB_PASSWORD_FILE" ] || die "şifre dosyası okunamadı: $MB_PASSWORD_FILE (root ve 0600 olmalı)"
  [ -s "$MB_PASSWORD_FILE" ] || die "şifre dosyası boş: $MB_PASSWORD_FILE"
  local mode
  mode="$(stat -c '%a' "$MB_PASSWORD_FILE" 2>/dev/null || echo '???')"
  case "$mode" in
    600|400) : ;;
    *) warn "şifre dosyası izinleri $mode; 600 olmalı: chmod 600 $MB_PASSWORD_FILE" ;;
  esac
}

rclone_remote_name() {
  # rclone:gdrive:path -> gdrive
  local repo_no_prefix="${MB_REPOSITORY#rclone:}"
  printf '%s' "${repo_no_prefix%%:*}"
}

check_remote_reachable() {
  case "$MB_REPOSITORY" in
    rclone:*)
      require_cmd rclone
      local remote; remote="$(rclone_remote_name)"
      info "rclone uzak hedefi denetleniyor: ${remote}:"
      if ! timeout "${MB_REMOTE_TIMEOUT:-90}" rclone lsd "${remote}:" >/dev/null 2>&1; then
        die "Google Drive erişimi başarısız (${remote}:). OAuth tokenı süresi dolmuş veya ağ yok. Kontrol: rclone lsd ${remote}: · yeniden yetkilendirme: rclone config reconnect ${remote}:"
      fi
      info "uzak hedef erişilebilir"
      ;;
    *) : ;;
  esac
}

repo_ready() {
  restic cat config >/dev/null 2>&1
}

ensure_repo() {
  if repo_ready; then
    info "restic deposu hazır: $MB_REPOSITORY"
    return 0
  fi
  if [ "$MB_AUTO_INIT" = "1" ]; then
    info "depo bulunamadı, oluşturuluyor (MB_AUTO_INIT=1): $MB_REPOSITORY"
    restic init
    return 0
  fi
  die "restic deposu yok veya erişilemiyor: $MB_REPOSITORY — oluşturmak için: MB_AUTO_INIT=1 mb-backup.sh ya da: restic init"
}

# Kesintiye uğrayan (ya da öldürülen) bir çalışma depoda bayat bir restic kilidi
# bırakabilir; sonraki yedek bu yüzden başarısız olmamalı. Depoya yazmadan önce kilidi
# yokla ve yalnızca bayat kilitleri temizle. `restic unlock` çalışmakta olan bir sürecin
# kilidini kaldırmaz; kendi eşzamanlı çalışmamızı zaten flock engelliyor.
clear_stale_locks() {
  repo_ready || return 0
  local probe
  if probe="$(restic snapshots --latest 1 2>&1)"; then
    return 0
  fi
  case "$probe" in
    *already\ locked*)
      warn "depoda bayat kilit var (kesintiye uğrayan çalışmadan kalmış olabilir); temizleniyor"
      if restic unlock; then
        info "bayat kilitler temizlendi, devam ediliyor"
      else
        warn "restic unlock başarısız; elle kontrol: restic unlock --remove-all"
      fi
      ;;
  esac
  return 0
}

run_hooks() {
  local phase="${1:-}"
  [ -n "$phase" ] || die "run_hooks: aşama adı verilmedi"
  local dir="${MB_HOOKS_DIR}/${phase}.d"
  # Kancalar ayrı süreçler: gerekli değişkenleri devralmaları için export et.
  export MB_STAGING_DIR MB_HOST MB_CONFIG
  [ -d "$dir" ] || { info "kanca yok: $dir"; return 0; }
  local hook
  for hook in "$dir"/*.sh; do
    [ -e "$hook" ] || continue
    [ -x "$hook" ] || { warn "kanca çalıştırılabilir değil, atlandı: $hook"; continue; }
    info "kanca: $hook"
    if ! "$hook"; then
      # Veritabanı dökümü alınamıyorsa tutarsız yedek almaktansa dur.
      die "kanca başarısız: $hook"
    fi
  done
}

# Verilen dizinlerin toplam boyutu (KB)
path_size_kb() {
  local total_kb=0 p kb
  for p in "$@"; do
    [ -e "$p" ] || continue
    kb="$(du -skx "$p" 2>/dev/null | awk '{print $1}' || true)"
    total_kb=$(( total_kb + ${kb:-0} ))
  done
  echo "$total_kb"
}

kb_to_human() {
  awk -v kb="$1" 'BEGIN { printf "%.1f GB", kb/1024/1024 }'
}

guard_source_size() {
  [ -n "${MB_GUARD_MAX_GB:-}" ] || return 0
  local -a guarded=()
  if declare -p MB_GUARD_PATHS >/dev/null 2>&1; then
    guarded=("${MB_GUARD_PATHS[@]}")
  fi
  [ "${#guarded[@]}" -gt 0 ] || return 0
  local kb limit_kb human
  kb="$(path_size_kb "${guarded[@]}")"
  limit_kb=$(( MB_GUARD_MAX_GB * 1024 * 1024 ))
  human="$(kb_to_human "$kb")"
  info "boyut koruması: ${guarded[*]} = ${human} (üst sınır ${MB_GUARD_MAX_GB} GB)"
  if [ "$kb" -gt "$limit_kb" ]; then
    MB_DIE_CODE=78 die "kaynak beklenenden büyük (${human} > ${MB_GUARD_MAX_GB} GB). Önce boyutu doğrula, sonra MB_GUARD_MAX_GB değerini bilinçli olarak artır."
  fi
}
