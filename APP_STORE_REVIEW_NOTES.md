# App Store Güncelleme Notları — v1.0.4 (Build 11)

## "Yenilikler" (What's New) — App Store Connect'e yazılacak metin

```
v1.0.4 Güncelleme

• Şifremi unuttum özelliği eklendi — giriş ekranından doğrudan şifre sıfırlama
• iOS'ta belge ve fotoğraf yükleme hataları giderildi
• Cari hesap işlemlerinde kararlılık iyileştirmeleri
• Projeler artık ruhsat işlem önceliğine göre sıralanıyor (en eski/işlemsiz projeler önce)
• Genel performans ve kararlılık güncellemeleri
```

## Reviewer Notları (App Review Information — Notes alanına)

```
Test Hesabı:
E-posta: [test hesabı e-postası]
Şifre: [test hesabı şifresi]

Uygulama bir inşaat yönetim sistemidir. Giriş yaptıktan sonra projeler, cari hesaplar, 
ödeme planları ve ruhsat takibi ekranlarına erişilebilir.

Abonelik ayrımları (inceleme için):
- company_monthly_subscription => SOLO (Tek Kişilik İşletme)
	* Sınırsız proje/cari
	* Personel ekleme yok
	* Proje paylaşımı yok
- company_yearly_subscription => BÜYÜK İŞLETME (Enterprise)
	* Sınırsız proje/cari/personel
	* Proje paylaşımı var
	* Paylaşılan hesap için düzenleme yetkisi aç/kapat var

Ücretsiz plan limiti:
- En fazla 1 aktif proje
- En fazla 10 cari hesap

Bu güncellemede yapılan değişiklikler:
1. Giriş ekranına "Şifremi Unuttum" butonu eklendi
2. iOS'ta fotoğraf/belge yükleme hatası düzeltildi
3. Cari hesap ve proje detay ekranlarında veri tipi hataları giderildi
4. Proje listesi sıralama mantığı iyileştirildi
```

## iOS Build Adımları (Mac'te yapılacak)

```bash
# 1. Kodu çek
cd ~/projects/lento
git pull origin master

# 2. Bağımlılıkları güncelle
flutter pub get
cd ios && pod install && cd ..

# 3. Release build oluştur
flutter build ipa --release

# 4. Xcode Organizer ile dağıt
# Xcode → Window → Organizer → Archives → Distribute App → App Store Connect
# veya:
# xcrun altool --upload-app -f build/ios/ipa/insaat_yonetim.ipa -t ios -u APPLE_ID -p APP_SPECIFIC_PASSWORD
```

## Bu Sürümde Yapılan Tüm Değişiklikler

| Değişiklik | Dosya(lar) |
|---|---|
| Şifremi unuttum özelliği | login_screen.dart |
| iOS fotoğraf/belge yükleme (REST API) | upload_helper.dart |
| Firebase iOS yapılandırma düzeltmesi | firebase_options.dart, GoogleService-Info.plist |
| Cari hesap safe cast düzeltmeleri | cari_hesap_screen.dart, firebase_service.dart |
| Storage metadata eklenmesi | 4 ekran dosyası |
| Firestore güvenli tip dönüşümleri | project_model.dart, payment_plan.dart |
| Proje sıralama (ruhsat önceliği) | firebase_service.dart |
| Şirket değiştir butonları kaldırıldı | dashboard.dart |
| Debug print temizliği | upload_helper.dart, cari_hesap_screen.dart, project_details_screen.dart |
| Versiyon 1.0.4+11 | pubspec.yaml |
