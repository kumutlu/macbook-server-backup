#!/usr/bin/env bash
# MacBook Server Backup - geri yükleme testi (ÜRETİM VERİSİNE DOKUNMAZ)
#
# En son snapshot'tan seçili bir yolu geçici dizine geri yükler, canlı dosyalarla
# sha256 karşılaştırması yapar ve geçici dizini siler.
#
# Kullanım: mb-restore-test.sh [SNAPSHOT]
#   SNAPSHOT: latest (varsayılan), bir id veya "latest" yerine id öneki.

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

trap 'mb_on_error' ERR

SNAPSHOT="${1:-latest}"
TMP_ROOT="${MB_RESTORE_TEST_DIR:-/var/tmp/mb-restore-test}"
TEST_PATH="${MB_RESTORE_TEST_PATH:-/etc/hostname}"
VERIFY_FILES="${MB_RESTORE_TEST_FILES:-25}"

load_config
prepare_env
require_cmd restic
require_cmd sha256sum
check_password_file
check_remote_reachable

TARGET="${TMP_ROOT}/$(date -u +%Y%m%dT%H%M%SZ)"
cleanup() { rm -rf "$TARGET"; }
trap 'cleanup' EXIT

if [ -e "$TARGET" ]; then
  MB_DIE_CODE=73 die "test dizini zaten var: $TARGET"
fi
mkdir -p "$TARGET"

info "geri yükleme testi: snapshot=$SNAPSHOT yol=$TEST_PATH hedef=$TARGET"
if ! restic snapshots "$SNAPSHOT" >/dev/null 2>&1; then
  MB_DIE_CODE=66 die "snapshot bulunamadı: $SNAPSHOT (restic snapshots ile kontrol et)"
fi

restic restore "$SNAPSHOT" --target "$TARGET" --include "$TEST_PATH"

restored="$TARGET${TEST_PATH}"
if [ ! -e "$restored" ]; then
  MB_DIE_CODE=70 die "geri yükleme sonrası beklenen yol yok: $restored"
fi

count="$(find "$restored" -type f 2>/dev/null | wc -l | tr -d ' ')"
info "geri yüklenen dosya sayısı: $count"

matched=0; mismatched=0; checked=0
if [ -d "$TEST_PATH" ]; then
  while IFS= read -r live; do
    rel="${live#"$TEST_PATH"/}"
    copy="$restored/$rel"
    [ -f "$copy" ] || continue
    checked=$(( checked + 1 ))
    if cmp -s "$live" "$copy"; then
      matched=$(( matched + 1 ))
    else
      mismatched=$(( mismatched + 1 ))
      warn "farklı: $live"
    fi
    [ "$checked" -ge "$VERIFY_FILES" ] && break
  done < <(find "$TEST_PATH" -type f 2>/dev/null)
fi

info "karşılaştırma: ${matched} aynı, ${mismatched} farklı, ${checked} dosya (canlı kaynak: ${TEST_PATH})"

if [ "$count" -eq 0 ]; then
  MB_DIE_CODE=70 die "hiç dosya geri yüklenmedi: $TEST_PATH"
fi
if [ "$mismatched" -gt 0 ]; then
  MB_DIE_CODE=70 die "geri yüklenen içerik canlı veriyle uyuşmuyor (${mismatched} dosya)"
fi

notify success "geri yükleme testi başarılı (${count} dosya)"
info "geri yükleme testi BAŞARILI; geçici dizin siliniyor: $TARGET"
