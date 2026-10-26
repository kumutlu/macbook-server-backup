# Google OAuth kurulumu (`drive.file`)

Hedef: rclone yalnızca **kendi oluşturduğu** Drive dosyalarına erişsin; başka hiçbir dosya
görünmesin. Bunun için `drive.file` kapsamı kullanılır. Bu kapsam **restricted değildir**;
`drive` veya `drive.readonly` gibi kapsamlar gibi CASA/security assessment gerektirmez.

## 1. Google Cloud projesi

1. https://console.cloud.google.com/ → yeni proje (ör. `macbook-server-backup`).
2. **APIs & Services → Library → Google Drive API → Enable.**

## 2. OAuth consent screen

1. **APIs & Services → OAuth consent screen**.
2. User type: **External** (kişisel Gmail hesabı için).
3. App name: `MacBook Server Backup`. Support e-mail ve developer contact kendi adresin
   olabilir — bu bilgiler **sitede yayımlanmaz**.
4. **Scopes → Add or remove scopes** → yalnızca şunu ekle:
   `https://www.googleapis.com/auth/drive.file`
   (Bu kapsam "non-sensitive" olarak işaretlidir; "restricted" listesinde yoktur.)
5. **Publishing status: In production** seç.

> **Kritik:** Publishing status **Testing** iken External uygulamalarda refresh token
> **7 gün** sonra geçersiz olur ve gece yedeği sessizce çalışmaz hale gelir. Bu yüzden
> Testing'de bırakma. Gözat: Google, Testing + External için "authorization/refresh token
> will expire after 7 days of consent" diyor.
> `drive.file` non-sensitive olduğu için production'a almak normalde doğrulama incelemesi
> gerektirmez; Google yine de marka doğrulaması isterse konsol ekranı seni yönlendirir.

## 3. OAuth client

1. **Credentials → Create credentials → OAuth client ID**.
2. Application type: **Desktop app** (rclone için doğru tip; client secret gizli sayılmaz
   ama yine de depoya girmez).
3. Client ID ve secret'ı rclone yapılandırmasına yazacaksın.

## 4. rclone yetkilendirme

Sunucuda, root olarak:

```bash
sudo rclone config create gdrive drive scope=drive.file
```

Bu komut tarayıcı açamıyorsa sana bir URL verir; kişisel Mac'inde açıp Google hesabınla
onaylarsın, dönen kodu sunucuya yapıştırırsın (headless akış). Alternatif olarak kişisel
Mac'inde `rclone authorize "drive"` çalıştırıp çıkan tokenı sunucuda
`rclone config` içine yapıştırabilirsin.

Test:

```bash
sudo rclone lsd gdrive:
sudo rclone mkdir gdrive:MacBook-Server-Backups        # depo klasörü
sudo rclone lsd gdrive:MacBook-Server-Backups
```

`drive.file` kapsamında `rclone about gdrive:` **çalışmaz** (kota izni yok). Bu beklenen
davranıştır; yedek için gerekli de değildir.

## 5. Token nerede durur

`/root/.config/rclone/rclone.conf` (0600). Bu dosya:

- yedeğe **dahil edilmez** (`excludes.txt` → `/root` yedeğe girse bile bu dosya ayrıca
  değerlendirilmeli; istersen `/root/.config/rclone` satırını `excludes.txt` içine ekle),
- GitHub'a **gönderilmez** (`.gitignore`),
- loglara **yazılmaz**.

Token sızarsa: Google Hesap → Güvenlik → Üçüncü taraf erişimi → erişimi kaldır, sonra
`rclone config reconnect gdrive:`.

## 6. Site ve gizlilik sayfası tutarlılığı

https://kumutlu.github.io/macbook-server-backup/ sayfasında yazanlar bu kurulumla uyumlu:

- tek kapsam `drive.file`,
- yalnızca uygulamanın kendi oluşturduğu dosyalar,
- analitik/izleme yok, veri paylaşımı yok,
- tek kullanıcı, kişisel yedekleme.

Site ve gerçek davranış arasında fark oluşursa **siteyi değil, gerçeği** esas al: ya kodu
 ya da sayfayı güncelle. Sayfaya e-posta, IP veya sunucu ayrıntısı eklenmez.

## 7. Unattended çalışma kontrolü

- Token yenilenmesi otomatiktir; 7 günlük sınır yalnızca Testing modunda geçerli.
- Google, 6 ay kullanılmayan refresh token'ları da iptal edebilir; günlük çalışma bunu önler.
- İlk otomatik yedekten sonra `journalctl -u macbook-backup` ile bir hafta boyunca hata
  olmadığını doğrula.
