#!/usr/bin/env bash
# MacBook Server Backup - doğrulama: snapshot listesi, boyut, bütünlük, kilit
#
# Kullanım: mb-verify.sh [--full]
#   (varsayılan) restic check --read-data-subset=MB_CHECK_SUBSET
#   --full       tüm veriyi oku (yavaş, ayda bir veya disk şüphesinde)

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

trap 'mb_on_error' ERR

MODE="${1:-subset}"
case "$MODE" in
  subset|--full) : ;;
  -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) MB_DIE_CODE=64 die "bilinmeyen argüman: $MODE" ;;
esac

load_config
prepare_env
require_cmd restic
check_password_file
check_remote_reachable

info "son snapshot'lar:"
restic snapshots --host "$MB_HOST" --latest 5

info "depo istatistikleri:"
restic stats

if [ "$MODE" = "--full" ]; then
  info "TAM bütünlük kontrolü (uzun sürebilir)"
  restic check --read-data
else
  info "kısmi bütünlük kontrolü: ${MB_CHECK_SUBSET}"
  restic check --read-data-subset="$MB_CHECK_SUBSET"
fi

info "doğrulama tamamlandı"
