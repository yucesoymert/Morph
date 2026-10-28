# Morph

macOS için saate göre kendiliğinden değişen dinamik duvar kağıdı (`.heic`)
üreten küçük bir SwiftUI uygulaması. Arka planda çalışan süreç yok —
geçişleri macOS'un kendi "Dynamic Desktop" mekanizması yapar; uygulama
sadece doğru dosyayı üretir.

> Xcode projesi, target ve kaynak klasörü `Morph`; bundle ID `com.mertyucesoy.Morph`.

## Hedef (v1)

Karşılama ekranında tür seçilir, sonra editör açılır:

1. İki tür: **Saat** (Sabah 07:00 / Akşam 19:00, `h24`) ve **Görünüm**
   (Açık / Koyu, `apr`).
2. İki bırakma alanı (önizlemeli). Saat türünde `ap: {l: 0, d: 1}` da yazılır.
3. **Oluştur** → `.heic` dosyasını `~/Pictures/Morph/Morph-<zaman>.heic` olarak yazar.
4. Sonuç ekranı: Kaydet / Ayarla (`setDesktopImageURL`, tüm ekranlar) /
   Paylaş / Yeni / Kapat.

Bağımlılık yok — SwiftUI, ImageIO, AppKit yeterli.

## Teknik Not: Dinamik HEIC formatı

- Tek `.heic` dosyasında birden fazla görsel (`CGImageDestination`,
  tür `public.heic`).
- **İlk görsele** XMP metadata eklenir:
  - Namespace: `http://ns.apple.com/namespace/1.0/`, prefix: `apple_desktop`
  - Anahtar: `h24` (saat bazlı). Değer = **binary plist → base64**.
- `h24` plist yapısı:
  ```
  {
    "ti": [ { "i": <görsel indeksi>, "t": <günün kesri 0.0–1.0> }, ... ],
    "ap": { "l": <açık mod görsel indeksi>, "d": <koyu mod görsel indeksi> }
  }
  ```
  Örnek: `t: 0.5` = 12:00, `t: 0.75` = 18:00.
- `ti` sırası önemsiz (çalışan `village.heic` sırasız). `t` yerel duvar saati.
- **Gece yarısı:** macOS listenin sonundan başa sarmıyor; ilk `t`'den önce ilk
  görseli gösteriyor. 07:00/19:00 listesinde 03:00'te sabah görünüyordu.
  `HEICWriter` ilk `t` > 0 ise `t: 0`'a son görseli ekliyor (çalışan tüm
  örneklerde `t: 0` var). Aynı indeks `ti`'de iki kez geçebiliyor.
- `setDesktopImageURL` Index.plist'e stilsiz (`style` yok) yazıyor ama macOS 27'de
  saat bazlı dosya yine saate göre çalışıyor — Equinox'un "önce Sistem
  Ayarları'nda Dinamik seç" adımı gerekmiyor (26.09.2026'da denendi).

- `apple_desktop:apr` (Görünüm türü) — plist `{l, d}`, `h24` yok.

Diğer modlar (v1 dışı):
- `apple_desktop:solar` — güneş yüksekliği/açısına göre (`si` listesi).

## Yapılacaklar

- [x] Proje iskeleti (Xcode macOS App, SwiftUI) — Xcode 27, macOS 15+ hedef
- [x] `HEICWriter`: `[CGImage]` + zaman listesi → `.heic` (saf fonksiyon)
- [x] Minimal self-check: üretilen dosyayı `CGImageSource` ile geri okuyup
      görsel sayısını ve `h24` metadata'sını doğrula —
      `swiftc -o /tmp/heiccheck Morph/HEICWriter.swift Morph/Cycle.swift Checks/main.swift && /tmp/heiccheck`
- [x] UI: iki bırakma alanı (Sabah / Akşam)
- [x] Oluştur → `~/Pictures/Morph/<ad>.heic` → sonuç ekranı (Kaydet / Ayarla / Paylaş / Yeni / Kapat)
- [x] Açılışta dikey karşılama ekranı + tür seçimi (Saat / Görünüm)
- [x] Görsel alanı: kesik çizgili sürükle-bırak + Seç… (PNG, JPEG, TIFF, HEIC)
- [x] Gerçek cihazda test: 03:3x'te akşam görseli görünüyor
- [x] Uygulama adı Morph + kullanıcının logosu AppIcon
- [x] Editör: başlık = seçilen tür, sağ üstte native toggle (Saat / Görünüm),
      tür değişince slot başlıkları fade; slotlar `.fixedSize` ile boyut korur
- [x] Görsel yüklenirken spinner ("Yükleniyor…"), önizleme arka planda (max 1600px)
- [x] Zaman çizelgesi (DayBar): siyah/açık gri, üstünde şu anki saat;
      sol altta renk noktalı key (Sabah / Akşam), sağ altta Oluştur
- [x] Equinox görünümü: açık bırakma alanları, sağ üstte glass segmented tür
      seçici + (⋯ menü | ?) grubu. ⋯: Morph klasörünü göster, Duvar Kağıdı
      Ayarları, Başa dön, Morph hakkında
- [x] TIPS kartı (açılışta fade + hafif spring büyüme; sheet değil, overlay: sheet pencereden büyüyemiyor ve dışarı
      tıklayınca kapanmıyor): karşılamada tür seçilince ve ? ile açılır, dışarı
      tıklayınca / Esc ile kapanır; 420×400, sol üstte buzlu TIPS rozeti. Editör
      min yükseklik 420 ki kart her türde sığsın. Görseller kullanıcının kendi görselleri
      (`TimeTip` / `AppearanceTip` imageset, 1672×941 JPEG)
- [x] DayBar açık temada: sabah = slot açık grisi (0.97), akşam = orta gri (0.72)
- [x] Hakkında penceresi (özel, `AboutView`): ikon, açıklama, Sürüm/Build,
      İkonu değiştir, en altta copyright. Ayarlar (⌘,): uygulama ikonu seçimi —
      Morph, Blueprint, Candy, Paper, Galaxy, Disco (kullanıcının tasarımları; kaldırılmış bir seçim açılışta Morph'a döner).
      Seçim Dock (`applicationIconImage`) + Finder (`NSWorkspace.setIcon`, bundle köküne
      `Icon\r` yazar — yalnız Release; Debug'da codesign bunu reddediyor, build
      kırılıyordu). Her açılışta yeniden uygulanır.
- [x] Sonuç ekranı: iki görsel yan yana (dosyanın kendisinden, arka planda),
      "Yeni" onay ister
- [x] Saat türüne **Işık Döngüsü** modu (Sabah / Akşam ↔ Işık Döngüsü): 2..N görsel,
      her biri kendi saatinde. Şeritte "+" ile çoklu ekleme (yeni görsel en geç saatin
      2 saat sonrasına; şerit saate göre sıralı, kartlar animasyonla yer değiştirir), timeline'da tutamaç sürükleme (5 dk adım), çubuğa tıklayınca
      seçili görsel oraya, karttaki saate tıklayınca iPhone alarmı gibi saat/dakika
      tekerleği (kaydır, sürükle ya da tıkla; Vazgeç / yeşil Tamam). Çizelgede üst üste
      binen tutamaçlarda öndeki net, arkadakiler soluk; tek satır. Açık/koyu (`ap`) = 12:00'ye ve
      00:00'a en yakın görseller. Kendi TIPS kartı (`CycleTip`, "Anladım"): moda ilk
      geçişte ve ? ile açılır; TIPS kartları artık `Tip` değeri (görsel/başlık/metin/buton). Her TIPS kartı kendiliğinden yalnız bir kez açılır (`@AppStorage("seenTips")`), ? ile her zaman. Dosyada görseller saate göre sıralı. Saf yardımcılar
      `Morph/Cycle.swift`, self-check'te.
- [ ] 07:00 ve 19:00 geçişlerini gözle doğrula
- [ ] Işık Döngüsü: 4+ görselli dosya masaüstünde saatinde geçiyor mu
- [ ] Kullanıcı denemeli: toolbar toggle görünümü, sonuç ekranında "Yeni"
      (çökme düzeltildi), slot başlığı fade, key'de görsel noktaları,
      Görünüm (`apr`) türü masaüstünde; toolbar'daki glass segmented seçici
      ve ⋯/? grubu (ImageRenderer toolbar çizmiyor)

## Dağıtım (DMG)

Developer ID yok → ad-hoc imza; alan kişi ilk açılışta Gatekeeper uyarısını
Sistem Ayarları › Gizlilik ve Güvenlik › "Yine de Aç" ile geçer.
`-destination 'generic/platform=macOS'` şart, yoksa yalnız arm64 çıkıyor.

```sh
D=/tmp/morph-rel; rm -rf $D; xcodebuild -project Morph.xcodeproj -scheme Morph \
  -configuration Release -destination 'generic/platform=macOS' -derivedDataPath $D build
mkdir $D/dmg && cp -R $D/Build/Products/Release/Morph.app $D/dmg/ && ln -s /Applications $D/dmg/
hdiutil create -volname Morph -srcfolder $D/dmg -ov -format UDZO ~/Desktop/Morph-1.0.dmg
```

## Çalışma notu

Kullanıcı Morph'u Xcode'dan çalıştırırken GUI otomasyonu (System Events,
süreç adıyla) yapma — kullanıcının açık penceresine tıklıyor. Görsel kontrol
için ImageRenderer ile ekran dışı çizim kullan.

## Sonraya bırakılanlar

- Açık kaynak yapmadan önce: LICENSE dosyası seç (TIPS görselleri artık
  kendimizin, Equinox lisansı gerekmiyor). Repo: github.com/yucesoymert/Morph (şimdilik private).

- Güneş bazlı mod (`solar`) — saat bazlı çalıştıktan sonra.
- Mevcut `.heic` dosyasını açıp düzenleme.
- İmzalama, sandbox, App Store — yalnız kişisel kullanım için gerekmiyor.

## Referanslar

- `wallpapper` (mczachurski, açık kaynak CLI) — aynı formatın referans
  implementasyonu; metadata detayında takılırsak bak.
- `Equinox` (rlxone, MIT) — aynı format + GUI; sonuç ekranı buradan esinlendi.
