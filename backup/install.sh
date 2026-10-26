#!/usr/bin/env bash
# MacBook Server Backup - kurulum (sunucuda root olarak çalıştırılır)
#
#   sudo ./install.sh
#
# Yaptıkları: betikleri /opt/macbook-backup altına kopyalar, /usr/local/bin'e bağlar,
# /etc/macbook-backup yapılandırmasını (yoksa) oluşturur, restic şifre dosyasını
# (yoksa) üretir, systemd unit'lerini kurar. Var olan yapılandırmayı ve şifreyi EZMEZ.
# Timer'ı otomatik AÇMAZ; önce elle doğrulama yapılmalı.

set -Eeuo pipefail

die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "root olarak çalıştır: sudo ./install.sh"

SRC_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PREFIX=/opt/macbook-backup
CONF_DIR=/etc/macbook-backup

echo "== araçlar =="
for t in restic rclone flock; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  %-8s %s\n' "$t" "$(command -v "$t")"
  else
    printf '  %-8s EKSİK -> sudo apt install -y %s\n' "$t" "$t"
  fi
done
command -v restic >/dev/null 2>&1 || echo "  UYARI: restic yoksa yedek çalışmaz (Ubuntu 24.04: sudo apt install -y restic rclone)"
command -v rclone >/dev/null 2>&1 || echo "  UYARI: rclone yoksa Google Drive'a yükleme yapılamaz"

echo "== betikler =="
install -d -m 755 "$PREFIX" "$PREFIX/bin" "$PREFIX/lib"
install -m 755 "$SRC_DIR"/bin/*.sh "$PREFIX/bin/"
install -m 644 "$SRC_DIR/lib/common.sh" "$PREFIX/lib/"
for f in "$PREFIX"/bin/*.sh; do
  ln -sfn "$f" "/usr/local/bin/$(basename "$f")"
done
echo "  $PREFIX/bin -> /usr/local/bin (mb-backup.sh, mb-verify.sh, mb-restore.sh, mb-restore-test.sh, mb-discover.sh)"

echo "== yapılandırma =="
install -d -m 700 "$CONF_DIR" "$CONF_DIR/hooks" "$CONF_DIR/hooks/pre-backup.d" "$CONF_DIR/hooks/post-backup.d"
if [ -f "$CONF_DIR/macbook-backup.conf" ]; then
  echo "  mevcut yapılandırma korundu: $CONF_DIR/macbook-backup.conf"
else
  install -m 600 "$SRC_DIR/etc/macbook-backup.conf.example" "$CONF_DIR/macbook-backup.conf"
  echo "  oluşturuldu: $CONF_DIR/macbook-backup.conf (düzenle)"
fi
install -m 644 "$SRC_DIR/etc/excludes.txt" "$CONF_DIR/excludes.txt"
for h in "$SRC_DIR"/hooks/pre-backup.d/*.sh; do
  [ -e "$h" ] || continue
  target="$CONF_DIR/hooks/pre-backup.d/$(basename "$h")"
  if [ -f "$target" ]; then
    echo "  kanca korundu: $target"
  else
    install -m 755 "$h" "$target"
    echo "  kanca kuruldu: $target"
  fi
done

echo "== şifre dosyası =="
if [ -f "$CONF_DIR/restic-password" ]; then
  echo "  mevcut şifre dosyası korundu: $CONF_DIR/restic-password"
else
  umask 077
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n' > "$CONF_DIR/restic-password"
  else
    head -c 48 /dev/urandom | base64 | tr -d '\n' > "$CONF_DIR/restic-password"
  fi
  echo >> "$CONF_DIR/restic-password"
  chmod 600 "$CONF_DIR/restic-password"
  echo "  üretildi: $CONF_DIR/restic-password (0600)"
  echo "  >>> BU ŞİFREYİ ŞİMDİ ÇEVRİMDIŞI KAYDET. Kaybı = yedeklerin kaybı."
fi

echo "== dizinler =="
install -d -m 755 /var/backups/macbook-server /var/cache/macbook-backup-restic
install -d -m 750 /var/lib/macbook-backup /var/log/macbook-backup
echo "  /var/backups/macbook-server (geçici dökümler), /var/lib/macbook-backup (kilit), /var/cache/macbook-backup-restic"

echo "== systemd =="
install -m 644 "$SRC_DIR/systemd/macbook-backup.service" /etc/systemd/system/
install -m 644 "$SRC_DIR/systemd/macbook-backup.timer" /etc/systemd/system/
systemctl daemon-reload
echo "  unit'ler kuruldu (henüz etkin değil)"

cat <<'EOS'

== Sıradaki adımlar (elle) ==
1. rclone Google Drive uzak hedefini oluştur (drive.file kapsamı):
     sudo rclone config create gdrive drive scope=drive.file
     sudo rclone lsd gdrive:
2. /etc/macbook-backup/macbook-backup.conf dosyasını düzenle (yollar, saklama, sınır).
3. Şifreyi çevrimdışı kasaya koy (parola yöneticisi + basılı kopya).
4. İlk yedeği elle çalıştır ve izle:
     sudo MB_AUTO_INIT=1 mb-backup.sh
5. Doğrula:  sudo mb-verify.sh
6. Geri yükleme testi: sudo mb-restore-test.sh
7. Ancak bundan sonra zamanlayıcıyı aç:
     sudo systemctl enable --now macbook-backup.timer
EOS
