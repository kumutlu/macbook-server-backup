# MacBook Server Backup

Bu depo iki bölümden oluşur:

1. **Bilgi ve gizlilik sayfası** (`index.html`, `privacy.html`) — Google OAuth için yayımlanan
   statik sayfalar. Aşağıda.
2. **Yedekleme sistemi** (`backup/`) — restic + rclone ile uçtan uca şifreli, günlük,
   otomatik yedekleme ve geri yükleme araçları. Kurulum: [backup/docs/INSTALL.md](backup/docs/INSTALL.md),
   genel bakış: [backup/README.md](backup/README.md).

Depoda şifre, OAuth tokenı, SSH anahtarı, sunucu IP'si veya e-posta adresi **bulunmaz**
(`.gitignore` bunu zorlar).

## Bilgi ve gizlilik sayfası

İki statik dosya, `kumutlu/macbook-server-backup` deposunun kökünde yayımlanır:

- `index.html` — uygulama adı, kişisel yedekleme amacı ve `drive.file` kapsamı.
- `privacy.html` — gizlilik sayfası; aynı üç bilgi, veri işleme ve silme başlıklarıyla.

Sayfalar tek tek kendi kendine yeterlidir: harici yazı tipi, betik, izleme kodu veya üçüncü
taraf isteği yoktur. Tek bağlantı kendi aralarındaki `index.html` / `privacy.html` bağlantısıdır.

## Yayın

- Depo: `kumutlu/macbook-server-backup` (public)
- Kaynak: `main` dalı, kök klasör (`/`)
- Adres: https://kumutlu.github.io/macbook-server-backup/

GitHub Pages ücretsiz planda çalışır; özel alan adı, ücretli plan veya faturalandırma gerekmez.
Sayfa sunucu tarafı kod çalıştırmaz, yalnızca statik dosya olarak servis edilir.

## Sayfaya konmayacaklar

Bu dosyalara hiçbir zaman şunlar eklenmemelidir: sunucu veya IP adresi, e-posta adresi,
parola, token, SSH anahtarı, yedek içeriği. Sayfa yalnızca uygulama adı, kişisel yedekleme
amacı ve `drive.file` kapsamıyla yalnızca uygulamanın kendi oluşturduğu dosyalara eriştiği
bilgisini içerir.

> Not: sayfanın önceki sürümü kişisel e-posta adresini yayımlıyordu; bu sürümde kaldırıldı.
