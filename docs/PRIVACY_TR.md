# Gizlilik Politikası ve KVKK Aydınlatma Metni

Trailhound, gizliliği önceleyen bir yolculuk kaydedicidir. Rotalar, araçlar, yerler ve harcamalar iPhone’undaki yerel SwiftData deposunda kalır. Hesap, bulut sunucusu, analitik veya reklam SDK’sı yoktur.

Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu’nun (KVKK) 10. maddesi kapsamındaki aydınlatma metnidir. Uygulama dili Türkçe olduğunda **Ayarlar → Hakkında → Gizlilik Politikası** bu sayfayı açar. English: [Privacy policy](PRIVACY.md).

## 1. Veri sorumlusu

Nurettin Baş — [nurettin.bas@icloud.com](mailto:nurettin.bas@icloud.com)

## 2. Cihazında kalan veriler (geliştiriciye ulaşmaz)

- GPS noktaları, yolculuk bilgileri, araç profilleri, yazdığın kilometre sayacı ve yolculukların buna eklediği kilometre, araca eklediğin fotoğraflar, kayıtlı yerler, seyahat notları ve harcamalar
- Harcamaya eklediğin fiş fotoğrafları ve bunlardan okunan tutar
- Yalnızca **Sorun bildir** ile göndermeyi seçersen kullanılan tanı günlüğü

**Tutarı oku** özelliği Apple’ın cihaz üzerindeki metin tanıma (Vision) teknolojisini kullanır. Fotoğraf ve okunan metin iPhone’unda işlenir; Trailhound’a, bir yapay zekâ servisine ya da herhangi bir sunucuya gönderilmez.

Konum yalnızca yolculuk kaydı için kullanılır ve sen tanı raporunu e-postayla göndermedikçe Trailhound’a ulaşmaz. O rapor da koordinat, adres, yer adı, araç adı, fotoğraf veya not içermez.

**Harita ve yol tarifi (Apple MapKit):** Harita görüntüsü, yer araması, yolculuk başı ve sonundaki sokak adları ve canlı haritadaki **planlanan yol** Apple’ın MapKit hizmetinden gelir. Canlı haritada bir varış noktası seçtiğinde, sürüş tarifi almak için o anki konumun ve varış noktası Apple’a gönderilir. Apple’ın yanıtındaki sıradaki dönüş ve mesafesi haritada gösterilir ve kaydedilmez. Yer araması yazdığında aranan metin ve harita bölgesi Apple’a gider. Bu istekler iPhone’undan doğrudan Apple’a, [Apple’ın gizlilik politikası](https://www.apple.com/tr/legal/privacy/) kapsamında gider. Arada Trailhound sunucusu yoktur; Trailhound bu verileri almaz. Varış noktası ve planlanan yol kaydedilmez; yalnızca o kayıt sürerken bellekte tutulur ve kayıt bitince silinir.

Bu veriler geliştirici tarafından işlenmez; kontrol tamamen sendedir.

## 3. Geliştiricinin işlediği veriler, amaçları ve hukuki sebepleri

| Veri | Amaç | Hukuki sebep |
|------|------|--------------|
| **Sorun bildir** ile gönderdiğin tanı dosyası (`trailhound-debug.txt`): zaman damgaları, kayıt başlat/durdur/duraklat olayları, Bluetooth / Canlı Etkinlik / widget olayları, hız, mesafe, GPS doğruluğu, yolculuk kimliği önekleri | Bildirdiğin sorunu bulmak ve gidermek | Her gönderimde ayrıca verdiğin **açık rıza** (KVKK m.5/1) |
| Bize yazdığın e-posta ve e-posta adresin | Talebini yanıtlamak | Bir hakkın tesisi, kullanılması veya korunması ve talebinin yerine getirilmesi (KVKK m.5/2-c, m.5/2-f) |

Bu veriler takip, reklam, pazarlama veya analitik için kullanılmaz.

## 4. Toplama yöntemi

Veriler yalnızca **senin başlattığın** bir işlemle toplanır: Ayarlar → **Sorun bildir** ekranında dosyanın içeriği gösterilir, onayın beklenir ve dosya Apple Mail veya seçtiğin paylaşım uygulamasıyla senin göndermenle iletilir. Otomatik yükleme yoktur.

## 5. Saklama süresi

- Cihazdaki tanı günlüğü: en fazla **30 gün** ve en fazla **2 MB**. Sorun bildir ekranından istediğin zaman silebilirsin.
- Gönderilen rapor ve e-postalar: vaka kapanana kadar, kapandıktan sonra en fazla **90 gün**. Hukuki bir talep veya yasal yükümlülük daha uzun saklamayı gerektirmedikçe bu süre sonunda silinir.
- Yolculuklar: Ayarlar’daki saklama süresine göre 30, 90 veya 365 gün sonra otomatik silinebilir ya da sen silene kadar tutulur.

## 6. Aktarım ve yurt dışı aktarım

Veriler üçüncü kişilere satılmaz veya pazarlama amacıyla aktarılmaz. Raporlar ve e-postalar geliştiricinin Apple iCloud Mail kutusuna ulaşır. Apple bu iletileri Türkiye dışındaki sunucularda saklayabilir. Bu aktarım yalnızca senin göndermeni seçtiğin anda, talebini yanıtlamak amacıyla gerçekleşir (KVKK m.9). Başka bir e-posta sağlayıcısı (ör. Gmail) seçersen ileti o sağlayıcının koşullarına göre işlenir.

Bahşiş (destek) ödemelerini Apple, Uygulama İçi Satın Alma ile işler. Trailhound kart bilgini, Apple hesabını veya kimliğini görmez; bahşiş hiçbir özelliğin kilidini açmaz.

## 7. KVKK m.11 kapsamındaki hakların

Veri sorumlusuna başvurarak şunları isteyebilirsin:

- Kişisel verinin işlenip işlenmediğini öğrenme ve işlenmişse bilgi talep etme
- İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme
- Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme
- Eksik veya yanlış işlenmişse düzeltilmesini isteme
- KVKK m.7 çerçevesinde silinmesini veya yok edilmesini isteme
- Düzeltme ve silme işlemlerinin aktarılan üçüncü kişilere bildirilmesini isteme
- Münhasıran otomatik sistemlerle analiz edilmesi sonucunda aleyhine bir sonuç çıkmasına itiraz etme
- Kanuna aykırı işleme nedeniyle zarara uğramışsan zararın giderilmesini talep etme

Başvurunu [nurettin.bas@icloud.com](mailto:nurettin.bas@icloud.com) adresine gönderebilirsin. Talebin en geç **30 gün** içinde ücretsiz olarak sonuçlandırılır. Açık rızanı istediğin zaman geri alabilirsin; bu, geri almadan önceki işlemeyi etkilemez.

Yanıtı yeterli bulmazsan [Kişisel Verileri Koruma Kurumu](https://www.kvkk.gov.tr)’na şikâyette bulunabilirsin.

## 8. Çocuklar

Trailhound bir sürüş günlüğüdür ve çocuklara yönelik değildir. Hiç kimseden, çocuklar dahil, bilerek veri toplamaz.

## 9. Seçeneklerin

- **Sorun bildir**’e dokunmazsan tanı verisi telefondan hiç çıkmaz
- Cihazdaki günlüğü Sorun bildir ekranından silebilirsin
- Mail’de göndermeden önce eki kaldırabilirsin
- Daha önce gönderdiğin bir raporun silinmesini e-postayla isteyebilirsin
- Uygulamayı silmek yerel depoyu, fiş fotoğraflarını ve kalan günlükleri kaldırır

## 10. Değişiklikler

Bu metin değişirse yeni sürüm aynı adreste, güncellenmiş tarihle yayımlanır.

_Son güncelleme: 1 Kasım 2026_

Ayrıca bkz. [Destek](SUPPORT.md) ve [Teşekkürler](ACKNOWLEDGEMENTS.md).
