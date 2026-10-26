# MacBook Server Backup (restic + rclone + Google Drive)

MacBook Server (Ubuntu Server) → yerel tutarlı döküm → istemci tarafı şifreleme → Google Drive.
Şifreleme ve sıkıştırma sunucuda yapılır; Drive'a yalnızca restic'in şifreli deposu gider.

## Akış

```
03:30 (systemd timer, kaçırılan gün telafi edilir)
  └─ mb-backup.sh
       1. kilit (flock) — eşzamanlı çalışma yok
       2. rclone/Drive erişim testi — erken ve anlaşılır hata
       3. pre-backup kancaları — Immich pg_dumpall, Pi-hole sqlite .backup
       4. restic backup  → rclone:gdrive:MacBook-Server-Backups/restic
       5. restic forget --prune (saklama politikası)
       6. restic check --read-data-subset=5%
       7. başarı/hata bildirimi (isteğe bağlı MB_NOTIFY_URL)
```

## Dosyalar

| Yol | Görev |
| --- | --- |
| `bin/mb-backup.sh` | Günlük yedek çalıştırıcısı (`--dry-run` destekli) |
| `bin/mb-verify.sh` | Snapshot listesi, istatistik, bütünlük kontrolü (`--full`) |
| `bin/mb-restore-test.sh` | Otomatik geri yükleme testi; üretim verisine dokunmaz |
| `bin/mb-restore.sh` | Güvenli geri yükleme; üretim yollarını hedef olarak reddeder |
| `bin/mb-discover.sh` | Sunucuda salt-okunur keşif raporu (servisler, boyutlar) |
| `lib/common.sh` | Ortak fonksiyonlar: yapılandırma, log, kilit, bildirim |
| `hooks/pre-backup.d/` | Tutarlı veritabanı dökümleri |
| `etc/macbook-backup.conf.example` | Yapılandırma örneği (sır içermez) |
| `etc/excludes.txt` | Hariç tutulan yollar (docker katmanları, önbellekler…) |
| `systemd/` | `macbook-backup.service` + `.timer` |
| `install.sh` | Sunucuda kurulum (root) |
| `docs/` | KURULUM, OAUTH, GERİ YÜKLEME, FELAKET KURTARMA, SORUN GİDERME |

## Hızlı başlangıç (sunucuda)

```bash
sudo bash install.sh
sudo bash bin/mb-discover.sh > discover-$(date +%F).txt   # neyin yedekleneceğini gör
sudo rclone config create gdrive drive scope=drive.file
sudo mb-backup.sh --dry-run
sudo MB_AUTO_INIT=1 mb-backup.sh
sudo mb-verify.sh
sudo mb-restore-test.sh
sudo systemctl enable --now macbook-backup.timer
```

## Güvenlik modeli

- **Şifreleme:** restic, AES-256-CTR + Poly1305-AES; anahtar `restic-password` dosyasından
  (`/etc/macbook-backup/restic-password`, 0600). Bu dosya yedeğin parçası **değildir** ve
  kaybı veriyi kurtarılamaz hale getirir → çevrimdışı kopya zorunlu.
- **OAuth:** `drive.file` — rclone yalnızca kendi oluşturduğu dosyaları görür. Token
  `/root/.config/rclone/rclone.conf` içinde (0600), depoya girmez.
- **Sır yok:** depoda şifre, token, anahtar, IP veya e-posta bulunmaz; `.gitignore` bunu zorlar.
- **Hata görünürlüğü:** her adım journald'a yazılır (`journalctl -u macbook-backup`), hata
  durumunda servis başarısız olur ve isteğe bağlı bildirim gönderilir.
