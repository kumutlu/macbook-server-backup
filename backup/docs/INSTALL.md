# Kurulum

Sunucuda `root` yetkisi gerekir. Aşağıdaki komutlar MacBook Server üzerinde çalıştırılır;
kişisel Mac'te değil. SSH anahtarın varsa `ssh sunucu` ile gir.

## 0. Keşif (hiçbir şeyi değiştirmez)

```bash
git clone https://github.com/kumutlu/macbook-server-backup.git
cd macbook-server-backup/backup
sudo ./bin/mb-discover.sh > discover-$(date +%F).txt
less discover-$(date +%F).txt
```

Raporda şunlara bak:

- `/srv/immich/library` boyutu → **Immich fotoğraf arşivini boyutunu görmeden yedeğe eklemeyin**.
- Docker volume'ları (`docker system df -v`) ve hangi container'ların çalıştığı.
- `immich` ve `pihole` container adları — kancalar `immich_postgres` ve `pihole` varsayar.
- Disk alanı: geçici dökümler için `/var/backups` altında boş yer.

Bu dosya sunucu ayrıntısı içerir — GitHub'a yüklemeyin (`.gitignore` zaten yok sayar).

## 1. Paketler

```bash
sudo apt update
sudo apt install -y restic rclone sqlite3
restic version   # >= 0.16 olmalı
rclone version
```

## 2. Kurulum

```bash
sudo ./install.sh
```

Bu komut: betikleri `/opt/macbook-backup` + `/usr/local/bin`, yapılandırmayı
`/etc/macbook-backup`, systemd unit'lerini kurar; `restic-password` dosyasını üretir.

**Hemen yap:** `sudo cat /etc/macbook-backup/restic-password` ile şifreyi parola yöneticine
ve/veya basılı bir kâğıda al. Bu şifre kaybolursa yedekler **kurtarılamaz**.

## 3. Google Drive (drive.file)

Ayrıntılı OAuth adımları: [OAUTH.md](OAUTH.md).

```bash
sudo rclone config create gdrive drive scope=drive.file
sudo rclone lsd gdrive:
```

`lsd` hata verirse token yok/expired demektir; OAUTH.md'ye bak. Not: `drive.file` kapsamıyla
`rclone about` çalışmaz (kota sorgusu izni yoktur) — bu normaldir.

## 4. Yapılandırma

```bash
sudo nano /etc/macbook-backup/macbook-backup.conf
```

Kontrol listesi:

- `MB_REPOSITORY` — `rclone:gdrive:MacBook-Server-Backups/restic`
- `MB_BACKUP_PATHS` — keşif raporundaki gerçek yollar (`/srv/docker`, `/srv/immich`…)
- `MB_GUARD_MAX_GB` — Immich gibi büyük dizinler için üst sınır; aşılırsa yedek **başlamaz**
- `MB_LIMIT_UPLOAD` — ev bağlantısı için `8M` makul
- `MB_KEEP_*` — saklama politikası

Docker volume'ları `/var/lib/docker/volumes` altındadır ve `excludes.txt` yalnızca
`overlay2/image/containers` dizinlerini dışlar; volume verisi yedeklenir. Immich ve Pi-hole
dökümleri kanca ile alındığı için büyük fotoğraf arşivi eklenmese bile uygulama verisi korunur.

## 5. Kuru çalışma, sonra ilk gerçek yedek

```bash
sudo mb-backup.sh --dry-run          # neyin yükleneceğini gösterir
sudo MB_AUTO_INIT=1 mb-backup.sh     # depoyu oluşturur ve ilk yedeği alır
```

İlk yedek boyuta göre saatler sürebilir. Kopan bağlantıda aynı komut kaldığı yerden devam eder.
`/etc/macbook-backup/macbook-backup.conf` içinde `MB_AUTO_INIT=1` bırakmayın; doğruladıktan
sonra `0` yapın.

## 6. Doğrulama ve geri yükleme testi

```bash
sudo mb-verify.sh          # snapshot listesi + istatistik + %5 veri okuma
sudo mb-restore-test.sh    # /etc/hostname gibi bir yolu geçici dizine geri yükler, sha256 karşılaştırır
```

İkisi de başarılı olmadan otomasyonu açmayın.

## 7. Günlük otomasyon

```bash
sudo systemctl enable --now macbook-backup.timer
systemctl list-timers macbook-backup.timer
journalctl -u macbook-backup -n 50
```

Timer `Persistent=true` olduğu için sunucu kapalıyken kaçırılan çalışma açılışta telafi edilir.
`Restart=on-failure` ile başarısız yedek 15 dakika sonra (en fazla 3 kez) yeniden denenir.

## 8. Bildirim (isteğe bağlı)

healthchecks.io gibi bir servisten URL alıp `MB_NOTIFY_URL` olarak yaz: başarıda URL,
hatada `URL/fail` çağrılır. URL'yi herkese açık yere koymayın.
