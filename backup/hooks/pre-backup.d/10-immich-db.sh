#!/usr/bin/env bash
# Immich veritabanının tutarlı dökümü (pg_dumpall).
# Canlı veritabanı dosyalarını kopyalamak yerine uygulama tutarlı döküm alınır.
# Servis durdurulmaz.

set -Eeuo pipefail

staging="${MB_STAGING_DIR:?MB_STAGING_DIR tanımsız}/databases"
container="${IMMICH_DB_CONTAINER:-immich_postgres}"
db_user="${IMMICH_DB_USER:-postgres}"

command -v docker >/dev/null 2>&1 || { echo "docker yok; immich dökümü atlandı"; exit 0; }
docker inspect "$container" >/dev/null 2>&1 || { echo "container yok ($container); immich dökümü atlandı"; exit 0; }

mkdir -p "$staging"
tmp="$staging/.immich-all-databases.sql.tmp"
out="$staging/immich-all-databases.sql"

echo "immich dökümü alınıyor: $container -> $out"
if ! docker exec "$container" pg_dumpall --clean --if-exists -U "$db_user" > "$tmp"; then
  rm -f "$tmp"
  echo "HATA: pg_dumpall başarısız ($container). Tutarsız yedek almamak için duruluyor." >&2
  exit 1
fi

if [ ! -s "$tmp" ]; then
  rm -f "$tmp"
  echo "HATA: döküm boş ($container)" >&2
  exit 1
fi

mv -f "$tmp" "$out"
echo "immich dökümü hazır: $(du -h "$out" | awk '{print $1}')"
