# Geri yükleme

İki şey gerekir: **depo erişimi** (rclone tokenı veya yeni OAuth) ve **restic şifresi**
(çevrimdışı kopya). Şifre yoksa veri kurtarılamaz — restic tasarımı gereği.

Disk arızası sonrası tam yeniden kurulum için: [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md).

## Hızlı kontrol listesi (yeni makinede)

```bash
sudo apt install -y restic rclone
sudo rclone config create gdrive drive scope=drive.file   # aynı Google hesabı
export RESTIC_REPOSITORY="rclone:gdrive:MacBook-Server-Backups/restic"
export RESTIC_PASSWORD_FILE=/root/restic-password         # çevrimdışı kopyadan geri koy
restic snapshots
```

`drive.file` kapsamıyla **yeni** bir rclone tokenı, eski tokenın oluşturduğu dosyaları
göremez (kapsam gereği "benim oluşturmadığım dosya" sayılır). Bu yüzden rclone tokenını da
şifreli bir kasada sakla; felaket anında en kesin yol aynı tokenı geri koymaktır.

## 1. Tek dosya geri yükleme

```bash
restic snapshots --host macbook-server --latest 5
restic restore latest --target /var/tmp/restore --include /srv/immich/.env
```

Ya da betikle (üretim yollarını hedef olarak reddeder, boş hedef ister):

```bash
sudo mb-restore.sh --target /var/tmp/restore --snapshot latest --include /etc/pihole
```

## 2. Tek dosyayı doğrudan dışarı almak

```bash
restic dump latest /etc/pihole/pihole-FTL.db > /var/tmp/pihole-FTL.db
restic dump latest /var/backups/macbook-server/databases/immich-all-databases.sql > /var/tmp/immich.sql
```

## 3. Veritabanlarını geri yükleme (Immich)

Döküm `pg_dumpall --clean` ile alındığı için nesneleri önce siler — doğru veritabanına
uygulandığından emin ol ve önce servisleri durdur (ÜRETİM ETKİSİ: kullanıcılar erişemez;
bunun için onay alınır).

```bash
cd /srv/immich && docker compose stop immich-server immich-microservices
docker exec -i immich_postgres psql -U postgres -d postgres < /var/tmp/immich.sql
docker compose up -d
```

## 4. Pi-hole veritabanı

```bash
sudo systemctl stop pihole-FTL 2>/dev/null || docker stop pihole
sudo cp /var/tmp/pihole-FTL.db /etc/pihole/pihole-FTL.db
sudo systemctl start pihole-FTL 2>/dev/null || docker start pihole
```

## 5. Doğrulama

```bash
sudo mb-verify.sh
sudo mb-restore-test.sh
```

Geri yükleme testi üretim verisine dokunmaz: en son snapshot'tan bir yolu geçici dizine
açar, canlı dosyalarla karşılaştırır ve geçici dizini siler. Ayda bir çalıştır.
