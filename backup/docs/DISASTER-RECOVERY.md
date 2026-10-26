# Felaket kurtarma: yeni diske tam yeniden kurulum

Disk arızası, silinme veya yeniden kurulum sonrası izlenecek sıra. Amaç: önce yedeği **boş
bir dizine** açıp incelemek, sonra dosyaları bilinçli olarak yerine koymak. Hiçbir adımda
mevcut üretim verisinin üzerine körlemesine yazılmaz.

Günlük geri yükleme adımları için: [RESTORE.md](RESTORE.md).

## 1. Temel sistemi kur

1. Ubuntu Server'ı yeni diske kur (aynı kullanıcı adı, kendi SSH anahtarın).
2. Gerekli paketler:

```bash
sudo apt update
sudo apt install -y restic rclone docker.io docker-compose-plugin sqlite3
```

3. Depo erişimini geri koy: rclone tokenı (çevrimdışı kasada saklanan `rclone.conf`) ve
   restic şifresi.

```bash
export RESTIC_REPOSITORY="rclone:gdrive:MacBook-Server-Backups/restic"
export RESTIC_PASSWORD_FILE=/root/restic-password
restic snapshots
```

## 2. Yedeği boş bir dizine aç

```bash
mkdir -p /mnt/restore
restic restore latest --target /mnt/restore
ls /mnt/restore
```

Bu adım yalnızca okuma ve geçici dizine yazma yapar; sistemdeki hiçbir servis etkilenmez.

## 3. Dosyaları yerine koy

Önce içeriği gözden geçir, sonra kopyala:

```bash
sudo rsync -aHAX --info=progress2 /mnt/restore/srv/ /srv/
sudo rsync -aHAX /mnt/restore/etc/ /etc/
sudo rsync -aHAX /mnt/restore/opt/ /opt/
sudo rsync -aHAX /mnt/restore/root/ /root/
```

Docker volume'ları için `/mnt/restore/var/lib/docker/volumes` içeriğini ilgili volume'lara
kopyala (`docker volume create` + `rsync`), sonra `docker compose up -d`.

## 4. Uygulama verileri

Immich veritabanını [RESTORE.md](RESTORE.md) §3'teki gibi, Pi-hole veritabanını §4'teki
gibi yerleştir.

## 5. Servisleri doğrula

```bash
docker ps
systemctl status
sudo mb-verify.sh
```

Servisleri tek tek aç ve test et (Immich arayüzü, DNS sorgusu). Yedekleme sistemini yeniden
kur: depoyu klonla, `sudo ./install.sh`, sonra `mb-restore-test.sh`.

## 6. Aynı hataya karşı önlem

- Şifre ve rclone tokenının çevrimdışı kopyalarının hâlâ okunabilir olduğunu doğrula.
- `systemctl list-timers macbook-backup.timer` ile zamanlayıcının açık olduğunu kontrol et.
- İlk otomatik yedekten sonra `journalctl -u macbook-backup` çıktısını incele.
