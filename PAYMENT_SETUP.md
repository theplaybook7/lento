# Ödeme Sistemi Kurulum Rehberi (In-App Purchase)

Lento uygulaması yalnızca Apple App Store ve Google Play In-App Purchase sistemini kullanır.
Tüm abonelikler StoreKit (iOS) ve Google Play Billing (Android) üzerinden işlenir.

## 1. iOS - App Store Connect

1. **App Store Connect'e giriş yapın:**
   - https://appstoreconnect.apple.com
   - Uygulamanızı seçin

2. **Abonelik Ürünleri:**
   - Ürün ID: `company_monthly_subscription` (Aylık)
   - Ürün ID: `company_yearly_subscription` (Yıllık)
   - Tür: Auto-Renewable Subscription

### Plan Eşlemesi (Apple Review için net metin)

- `company_monthly_subscription` => **SOLO (Tek Kişilik İşletme)**
   - Sınırsız proje
   - Sınırsız cari
   - Personel ekleme yok
   - Proje paylaşımı yok

- `company_yearly_subscription` => **BÜYÜK İŞLETME (Enterprise)**
   - Sınırsız proje
   - Sınırsız cari
   - Sınırsız personel ekleme
   - Proje paylaşımı var (Ruhsat/Şantiye/Muhasebe bazlı)
   - Paylaşılan hesap için düzenleme izni seçilebilir

- Ücretsiz kullanım (IAP olmayan plan):
   - En fazla 1 aktif proje
   - En fazla 10 cari hesap

3. **Sandbox Test Hesabı Oluşturun:**
   - Settings > Users and Access > Sandbox
   - Yeni Tester Ekle
   - Test cihazında "Ayarlar > App Store > Giriş Yap"

4. **Push/FCM için iOS Capability Kontrolü:**
   - Xcode > Runner target > Signing & Capabilities
   - `Push Notifications` capability aktif olmalı
   - `Background Modes` içinde `Remote notifications` aktif olmalı
   - Apple Developer hesabında APNs key/certificate tanımlı olmalı
   - Firebase Console > Project Settings > Cloud Messaging içine APNs key yüklenmiş olmalı

## 2. Android - Google Play Console

1. **Google Play Console'a giriş yapın:**
   - https://play.google.com/console
   - Uygulamanızı seçin

2. **Abonelik Ürünleri Oluşturun:**
   - Monetize > Products > Subscriptions
   - Ürün ID: `company_monthly_subscription`
   - Ürün ID: `company_yearly_subscription`

3. **Sandbox'ı Test Edin:**
   - Ayarlar > Lisans Testi
   - Test cihazlarını ekleyin

## 3. Firebase Cloud Functions

### Deploy

```bash
firebase deploy --only functions
```

Cloud Functions receipt doğrulama için kullanılır:
- `verifyAppStoreReceipt` — Apple receipt doğrulama
- `verifyGooglePlayReceipt` — Google Play receipt doğrulama
- `getPaymentHistory` — Ödeme geçmişi
- `checkPaymentStatus` — Ödeme durumu kontrolü
- `activateFreeTrial` — ücretsiz deneme aktivasyonu

## 4. Firebase iOS Eşleşme Kontrolü

- `ios/Runner/GoogleService-Info.plist` içindeki `GOOGLE_APP_ID`, `BUNDLE_ID`, `PROJECT_ID`
   değerleri Firebase Console iOS app kaydıyla birebir aynı olmalı.
- `lib/firebase_options.dart` içindeki iOS `appId`, `iosBundleId` değerleri
   `GoogleService-Info.plist` ile aynı olmalı.
- `ios/Runner.xcodeproj/project.pbxproj` içinde `PRODUCT_BUNDLE_IDENTIFIER`
   değeri Firebase iOS app bundle id ile aynı olmalı.

## 5. Flutter App Yapılandırma

### pubspec.yaml

```yaml
dependencies:
   in_app_purchase: ^3.3.0
   firebase_core: ^4.10.0
   firebase_auth: ^6.5.2
   cloud_firestore: ^6.5.0
   cloud_functions: ^6.3.2
   firebase_storage: ^13.4.2
   firebase_messaging: ^16.3.0
```

## 6. Testing Checklist

- [ ] iOS: Sandbox test hesabı ile abonelik satın almayı test et
- [ ] Android: Test cihazı ile abonelik satın almayı test et
- [ ] Firestore: Abonelik kaydının oluşturulduğunu doğrula
- [ ] Restore Purchases: Mevcut abonelikleri geri yükleme çalışıyor mu?
- [ ] Company Creation: Şirket oluşturma dialogu açılıyor mu?
- [ ] iOS: FCM token `users/{uid}.fcmTokens` alanına yazılıyor mu?
- [ ] iOS: Bildirim izni isteme ve foreground bildirim davranışı doğru mu?

## 7. Production Checklist

- [ ] Apple: Production Certificate'i upload et
- [ ] Apple: Push Notifications ve Background Modes capability doğrula
- [ ] Google Play: Release build'i submit et
- [ ] Firebase Cloud Functions: Production'a deploy et
- [ ] Firestore Rules: Production rule'larını set et
- [ ] Monitoring: Firebase Console'da logs'ları kontrol et
