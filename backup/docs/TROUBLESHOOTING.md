# Sorun giderme

Önce şu üç komut:

```bash
systemctl status macbook-backup.timer
journalctl -u macbook-backup -n 100 --no-pager
sudo mb-verify.sh
```

## Yedek hiç çalışmıyor / timer yok

```bash
systemctl list-timers macbook-backup.timer
sudo systemctl enable --now macbook-backup.timer
```
`ConditionPathExists` yapılandırma dosyasını arar; dosya adı `macbook-backup.conf` olmalı.

## "Google Drive erişimi başarısız"

- Token süresi dolmuş: `sudo rclone config reconnect gdrive:`
- Uygulama hâlâ **Testing** modundaysa token 7 günde bir düşer → `docs/OAUTH.md` §2,
  publishing status **In production** olmalı.
- `drive.file` kapsamında `rclone about gdrive:` çalışmaz; bu hata değildir. `rclone lsd gdrive:` kullan.
- Ağ yoksa: `nmcli`/`ip a`; `After=network-online.target` var ama modem geç açılıyorsa
  `MB_REMOTE_TIMEOUT` artır veya `Restart=on-failure` sayesinde tekrar denemeyi bekle.

## "başka bir yedek çalışması sürüyor" (çıkış 75)

Kilit: `/var/lib/macbook-backup/backup.lock`. Çalışan süreç bittiyse dosya kendiliğinden serbest kalır.
Gerçekten kilitli kaldıysa (süreç öldüyse) `flock` kilit bırakmaz; yine de sorun sürüyorsa:

```bash
sudo systemctl stop macbook-backup.service
sudo restic unlock
```

## "depo yok veya erişilemiyor"

İlk kurulumda beklenen durum. `MB_AUTO_INIT=1` ile bir kez çalıştır ya da `sudo restic init`.
Yanlış `MB_REPOSITORY` (ör. fazladan `:` veya boşluk) aynı hatayı verir.

## Kanca hatası (immich / pihole)

- `container yok (immich_postgres)` → `docker ps` ile gerçek adı bul,
  `IMMICH_DB_CONTAINER` değerini yapılandırmada ayarla.
- `permission denied docker.sock` → servis `SupplementaryGroups=docker` kullanıyor; elle
  çalıştırırken `sudo` kullan.
- `UYARI: pihole-FTL.db dökümü alınamadı` → `sudo apt install sqlite3` (veya `pihole-FTL`).
  Bu durumda yedek durmaz, çünkü Pi-hole ayarları `/etc/pihole` yedeğinde zaten var; tutarlı DB
  kopyası için sqlite3 gerekir.

## Immich fotoğraf arşivi

`MB_GUARD_MAX_GB` sınırı aşılırsa yedek **bilinçli olarak** durur (çıkış 78). Bu koruma,
yanlışlıkla yüzlerce GB'ı yükleyip kotayı doldurmamak içindir. Önce:

```bash
sudo du -sh /srv/immich/library
df -h /
```

Boyut kabul edilebilirse `/srv/immich/library` yolunu `MB_BACKUP_PATHS`'e ekle ve
`MB_GUARD_MAX_GB` değerini bilinçli olarak yükselt. Fotoğraf arşivini yedeğe katmadan da
uygulama verisi (DB + config) korunur.

## Bütünlük kontrolü hata veriyor

```bash
sudo restic check                 # hızlı, yapı kontrolü
sudo restic check --read-data      # tam okuma (uzun)
restic repair index                 # indeks bozulduysa
```
Bozuk pack dosyası varsa `restic repair pack`/`restic repair snapshots` adımları için restic
belgelerine bak; silmeden önce `restic copy` ile sağlam snapshot'ları yeni bir depoya kopyala.

## Disk dolu

Geçici dökümler `/var/backups/macbook-server/databases` altında büyür. Eski dökümler her
çalışmada üzerine yazılır; yine de `du -sh /var/backups/macbook-server` kontrol et. restic
önbelleği `/var/cache/macbook-backup-restic` altındadır ve silinebilir (yeniden oluşur).

## Yedek çok yavaş / sunucu yavaşlıyor

- `MB_LIMIT_UPLOAD=4M` gibi düşür.
- `MB_READ_CONCURRENCY=1` yap (CPU sınırı).
- Servis zaten `Nice=19`, `IOSchedulingClass=idle` ile çalışır.
- İlk yedek her zaman büyüktür; sonrakiler yalnızca değişen blokları yükler (dedupe).

## Şifre dosyası izinleri

`chmod 600 /etc/macbook-backup/restic-password`. Betik yanlış izinde uyarır ama çalışır.

## Geri yükleme testi "snapshot bulunamadı"

`latest` yerine `restic snapshots --host macbook-server` çıktısındaki kısa id'yi ver:
`sudo mb-restore-test.sh 1a2b3c4d`.
