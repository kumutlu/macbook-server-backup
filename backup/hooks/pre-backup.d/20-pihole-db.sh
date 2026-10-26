#!/usr/bin/env bash
# Pi-hole SQLite veritabanlarının tutarlı kopyası (sqlite3 ".backup").
# FTL çalışırken düz kopya bozuk olabilir; .backup API'si tutarlı anlık görüntü verir.

set -Eeuo pipefail

staging="${MB_STAGING_DIR:?MB_STAGING_DIR tanımsız}/databases"
mkdir -p "$staging"

dump_one() {
  local src="$1" name out
  name="$(basename "$src")"
  out="$staging/pihole-$name"
  [ -f "$src" ] || return 0

  if command -v pihole-FTL >/dev/null 2>&1; then
    pihole-FTL sqlite3 "$src" ".backup '$out'" && echo "pi-hole dökümü: $out" && return 0
  fi
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$src" ".backup '$out'" && echo "pi-hole dökümü: $out" && return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker inspect pihole >/dev/null 2>&1; then
    docker exec pihole sqlite3 "$src" ".backup '/tmp/$name.bak'" \
      && docker cp "pihole:/tmp/$name.bak" "$out" \
      && docker exec pihole rm -f "/tmp/$name.bak" \
      && echo "pi-hole dökümü (container): $out" && return 0
  fi

  # Bu dosya kritik değilse yedeği durdurmak yerine görünür uyarı bırak.
  echo "UYARI: $src dökümü alınamadı (pihole-FTL, sqlite3 veya pihole container'ı yok)." >&2
  return 0
}

dump_one /etc/pihole/pihole-FTL.db
dump_one /etc/pihole/gravity.db
echo "pi-hole döküm adımı bitti"
