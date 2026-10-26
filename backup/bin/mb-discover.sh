#!/usr/bin/env bash
# MacBook Server Backup - keşif raporu (SALT OKUNUR)
#
# Sunucuda çalıştır, çıktıyı incele. Hiçbir dosya değiştirilmez, hiçbir servis durdurulmaz.
# Yapılandırma dosyalarının İÇERİĞİNİ yazdırmaz; yalnızca yol ve boyut gösterir.
#
# Kullanım: sudo mb-discover.sh > discover-$(date +%F).txt

set -Euo pipefail

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "sistem"
uname -a || true
. /etc/os-release 2>/dev/null && echo "sürüm: ${PRETTY_NAME:-bilinmiyor}"
echo "hostname: $(hostname)"
echo "uptime: $(uptime -p 2>/dev/null || uptime)"
echo "kullanıcı: $(id -un) uid=$(id -u)"

section "disk ve dosya sistemleri"
df -hT -x tmpfs -x devtmpfs 2>/dev/null || df -h
echo "--- blok aygıtları ---"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null || true

section "bellek ve cpu"
free -h 2>/dev/null || true
nproc 2>/dev/null || true

section "docker"
if have docker; then
  docker ps --format 'tablo: {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || echo "docker erişilemedi"
  echo "--- volume'lar ve boyutları ---"
  docker system df -v 2>/dev/null | sed -n '1,80p' || true
  echo "--- compose dosyaları (yol) ---"
  find /srv /opt /home /root -maxdepth 4 \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) -type f 2>/dev/null | head -40
else
  echo "docker kurulu değil"
fi

section "servisler (systemd)"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}' | head -40 || true
echo "--- özel unit dosyaları (/etc/systemd/system) ---"
find /etc/systemd/system -maxdepth 2 -name '*.service' -o -maxdepth 2 -name '*.timer' 2>/dev/null | head -40

section "zamanlayıcılar"
systemctl list-timers --all --no-pager --no-legend 2>/dev/null | head -20 || true
echo "--- kullanıcı cron ---"
ls -1 /etc/cron.d 2>/dev/null || true
crontab -l 2>/dev/null | sed 's/^/root: /' || true

section "immich"
found_immich=0
for d in /srv/immich /opt/immich /home/*/immich /srv/docker/immich; do
  if [ -d "$d" ]; then
    found_immich=1
    echo "dizin: $d ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"
    ls -1 "$d" 2>/dev/null | head -20
  fi
done
[ "$found_immich" = 0 ] && echo "immich dizini bulunamadı (yol farklı olabilir)"
for p in /srv/immich/library /mnt/immich /srv/immich/upload; do
  [ -e "$p" ] && echo "immich library: $p = $(du -sh "$p" 2>/dev/null | awk '{print $1}')  <-- BOYUTU GÖRMEDEN YEDEĞE EKLEME"
done
if have docker; then
  docker ps --format '{{.Names}}' 2>/dev/null | grep -i immich | sed 's/^/immich container: /'
fi

section "pi-hole"
for p in /etc/pihole /etc/dnsmasq.d; do
  [ -d "$p" ] && echo "$p = $(du -sh "$p" 2>/dev/null | awk '{print $1}')"
done
for f in /etc/pihole/pihole-FTL.db /etc/pihole/gravity.db; do
  [ -f "$f" ] && echo "$f = $(du -h "$f" | awk '{print $1}')"
done
if have docker; then
  docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'pihole|unbound' | sed 's/^/dns container: /'
fi

section "veritabanları"
for f in $(find /srv /opt /var/lib -maxdepth 4 -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) 2>/dev/null | head -20); do
  echo "$f = $(du -h "$f" | awk '{print $1}')"
done
echo "--- sqlite3 / pg_dump / mysqldump ---"
for t in sqlite3 pg_dump pg_dumpall mysqldump pihole-FTL; do
  printf '%-12s ' "$t"; command -v "$t" || echo "yok"
done

section "yedekleme durumu (mevcut)"
systemctl list-units --all --no-pager --no-legend 2>/dev/null | grep -iE 'backup|restic|rclone|borg' || echo "mevcut yedek servisi yok"
ls -1 /etc/macbook-backup 2>/dev/null || echo "/etc/macbook-backup yok"
for t in restic rclone; do printf '%-8s ' "$t"; command -v "$t" || echo "kurulu değil"; done
[ -r /root/.config/rclone/rclone.conf ] && echo "rclone.conf var (içerik yazdırılmadı)" || echo "rclone.conf yok"

section "ağ"
ip -brief addr 2>/dev/null || ifconfig 2>/dev/null | head -20
echo "--- dinlenen portlar ---"
(ss -ltnH 2>/dev/null || netstat -ltn 2>/dev/null) | awk '{print $4}' | sort -u | head -30

# Not: uzak erişim ayarlarının DEĞERLERİ yazdırılmaz, yalnızca özet sayılar.
SSH_DIR="${SSH_DIR:-/etc/ssh}"
section "uzak erişim ayarları (değer yazdırılmaz)"
ls -1 "$SSH_DIR/sshd_config.d" 2>/dev/null || true
if [ -r "$SSH_DIR/sshd_config" ]; then
  echo "ayar dosyası okunabilir; güvenlikle ilgili satır sayısı:"
  grep -Eic 'permitrootlogin|pubkeyauthentication|passwordauthentication|^port' "$SSH_DIR/sshd_config" 2>/dev/null \
    | sed 's/^/  ilgili satır sayısı: /' || true
  echo "  ayrıntı için sunucuda: sudo sshd -T | grep -E 'permitroot|pubkey'"
fi

printf '\n===== rapor sonu =====\n'
echo "Not: bu dosyayı GitHub'a veya herkese açık bir yere yüklemeyin."
