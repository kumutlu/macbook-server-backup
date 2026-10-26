#!/usr/bin/env bash
# MacBook Server Backup - günlük yedek çalıştırıcısı
#
# Kullanım:
#   mb-backup.sh              normal çalışma
#   mb-backup.sh --dry-run    yalnızca ne yapılacağını göster (yükleme yok)
#
# Çıkış kodları: 0 başarı, 75 başka çalışma sürüyor, 78 boyut koruması, diğerleri hata.

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

trap 'mb_on_error' ERR

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
  "") ;;
  *) MB_DIE_CODE=64 die "bilinmeyen argüman: $1" ;;
esac

check_restic_version() {
  local v major minor
  v="$(restic version | awk '{print $2}' | sed 's/^v//')"
  major="${v%%.*}"; minor="$(printf '%s' "$v" | cut -d. -f2)"
  if [ "${major:-0}" -eq 0 ] && [ "${minor:-0}" -lt 16 ]; then
    die "restic >= 0.16 gerekli (kurulu: $v); --limit-upload ve rclone desteği için yükselt"
  fi
  info "restic sürümü: $v"
}

do_backup() {
  local -a args=(
    backup
    --host "$MB_HOST"
    --tag "$MB_TAG"
    --compression "$MB_COMPRESSION"
    --retry-lock "$MB_RETRY_LOCK"
    --exclude-caches
  )
  [ -r "${MB_EXCLUDES_FILE:-}" ] && args+=(--exclude-file "$MB_EXCLUDES_FILE")
  [ -n "${MB_LIMIT_UPLOAD:-}" ] && args+=(--limit-upload "$MB_LIMIT_UPLOAD")
  [ -n "${MB_READ_CONCURRENCY:-}" ] && args+=(--read-concurrency "$MB_READ_CONCURRENCY")
  [ "$DRY_RUN" = "1" ] && args+=(--dry-run)

  args+=("${MB_BACKUP_PATHS[@]}")

  info "kaynaklar: ${MB_BACKUP_PATHS[*]}"
  if [ "$DRY_RUN" = 1 ]; then info "restic backup başlıyor (dry-run)"; else info "restic backup başlıyor"; fi
  restic "${args[@]}"
  info "restic backup tamamlandı"
}

do_forget() {
  local -a args=(
    forget
    --host "$MB_HOST"
    --keep-daily "$MB_KEEP_DAILY"
    --keep-weekly "$MB_KEEP_WEEKLY"
    --keep-monthly "$MB_KEEP_MONTHLY"
    --keep-yearly "$MB_KEEP_YEARLY"
  )
  [ "${MB_PRUNE:-1}" = "1" ] && args+=(--prune)
  info "saklama uygulanıyor: günlük=$MB_KEEP_DAILY haftalık=$MB_KEEP_WEEKLY aylık=$MB_KEEP_MONTHLY yıllık=$MB_KEEP_YEARLY"
  restic "${args[@]}"
}

do_check() {
  [ "${MB_CHECK_SUBSET:-}" = "off" ] && { info "bütünlük kontrolü kapalı"; return 0; }
  info "bütünlük kontrolü: verinin ${MB_CHECK_SUBSET} kadarı okunacak"
  restic check --read-data-subset="$MB_CHECK_SUBSET"
  info "bütünlük kontrolü geçti"
}

main() {
  load_config
  prepare_env
  require_cmd restic
  require_cmd flock
  check_password_file
  check_restic_version
  acquire_lock
  check_remote_reachable
  # Boyut koruması depo oluşturmadan önce: gereksiz init ve yanlış yükleme olmasın.
  guard_source_size
  ensure_repo

  run_hooks pre-backup
  do_backup
  if [ "$DRY_RUN" = "1" ]; then
    info "dry-run: saklama ve kontrol atlandı"
    return 0
  fi
  do_forget
  do_check
  run_hooks post-backup
  info "en son snapshot:"
  restic snapshots --latest 1 --host "$MB_HOST" || true
  notify success "yedek tamam"
  info "bitti"
}

main "$@"
