#!/usr/bin/env bash
# MacBook Server Backup - güvenli geri yükleme
#
# Üretim dizinlerinin üzerine yazmayı reddeder. Yalnızca boş/yeni bir hedefe yükler.
#
# Kullanım:
#   mb-restore.sh --target /var/tmp/restore [--snapshot latest|ID] [--include /etc/immich]
#
# Gerçek felaket kurtarma için docs/RESTORE.md izlenir: önce yeni disk/VM, sonra hedefe
# geri yükleme, sonra dosyaları bilinçli olarak yerine koyma.

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

trap 'mb_on_error' ERR

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}"; }

SNAPSHOT="latest"
TARGET=""
INCLUDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --snapshot) SNAPSHOT="${2:-}"; shift 2 ;;
    --include) INCLUDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) MB_DIE_CODE=64 die "bilinmeyen argüman: $1" ;;
  esac
done

[ -n "$TARGET" ] || { usage; MB_DIE_CODE=64 die "--target zorunlu"; }

# Üretim yollarını koru: yanlış hedef = veri kaybı.
case "$TARGET" in
  /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/usr|/var|/var/lib|/var/backups)
    MB_DIE_CODE=65 die "hedef üretim yolu olamaz: $TARGET — boş bir alt dizin seç (örn. /var/tmp/restore)" ;;
esac
if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null || true)" ]; then
  MB_DIE_CODE=73 die "hedef boş değil: $TARGET (üzerine yazmam; başka bir dizin seç)"
fi

load_config
prepare_env
require_cmd restic
check_password_file
check_remote_reachable

info "geri yükleme: snapshot=$SNAPSHOT hedef=$TARGET include=${INCLUDE:-<tüm snapshot>}"
restic snapshots "$SNAPSHOT" >/dev/null 2>&1 || MB_DIE_CODE=66 die "snapshot bulunamadı: $SNAPSHOT"

mkdir -p "$TARGET"
if [ -n "$INCLUDE" ]; then
  restic restore "$SNAPSHOT" --target "$TARGET" --include "$INCLUDE"
else
  info "tüm snapshot geri yükleniyor (disk alanı yeterli olmalı)"
  restic restore "$SNAPSHOT" --target "$TARGET"
fi

info "geri yükleme tamamlandı: $TARGET"
info "sonraki adım: içeriği doğrula, sonra servisleri bilinçli olarak durdurup dosyaları yerine koy (docs/RESTORE.md)"
