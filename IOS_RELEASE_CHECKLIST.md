# iOS Release Checklist (Lento)

Bu liste iOS/TestFlight/App Store yayini oncesi Flutter + Firebase + IAP uyumlulugunu dogrulamak icin hazirlandi.

## 1. Kimlik ve Proje Eslesmesi

- [ ] `ios/Runner.xcodeproj/project.pbxproj` icindeki `PRODUCT_BUNDLE_IDENTIFIER` = `com.lento.app`
- [ ] `ios/Runner/GoogleService-Info.plist` icindeki `BUNDLE_ID` = `com.lento.app`
- [ ] `lib/firebase_options.dart` icindeki iOS `iosBundleId` = `com.lento.app`
- [ ] Firebase Console > Project Settings > iOS app id degeri `1:478876596230:ios:b862535e946b080bdd6b87`

## 2. Capability ve Entitlement Kontrolu

- [ ] Xcode > Runner > Signing & Capabilities > `In-App Purchase` aktif
- [ ] Xcode > Runner > Signing & Capabilities > `Push Notifications` aktif
- [ ] Xcode > Runner > Signing & Capabilities > `Background Modes` aktif
- [ ] `Background Modes` altinda `Remote notifications` secili
- [ ] Apple Developer profilinde ilgili capability'ler aktif

## 3. Firebase Push (FCM/APNs)

- [ ] Firebase Console > Cloud Messaging > APNs key/certificate yuklu
- [ ] Fiziksel iOS cihazda ilk acilista bildirim izni soruluyor
- [ ] Uygulama login sonrasi `users/{uid}.fcmTokens` alanina token yaziliyor
- [ ] Foreground bildirim sunumu calisiyor (alert/sound/badge)

## 4. StoreKit / Abonelik Urunleri

- [ ] App Store Connect'te urunler tanimli:
  - [ ] `company_monthly_subscription`
  - [ ] `company_yearly_subscription`
- [ ] Uygulamadaki urun id'leri birebir ayni
- [ ] Sandbox test hesabi ile satin alma testi geciyor
- [ ] Restore Purchases calisiyor

## 5. Plan Esleme Dogrulama

- [ ] `monthly` satin alma -> `solo` plan
- [ ] `yearly` satin alma -> `enterprise` plan
- [ ] `trial` -> `free` limitleri
- [ ] Sirket dokumaninda `subscriptionType`, `subscriptionEndDate`, `planTier` alanlari guncelleniyor

## 6. Backend / Function Kontrolu

- [ ] `verifyAppStoreReceipt` deploy edildi
- [ ] `verifyGooglePlayReceipt` deploy edildi
- [ ] `checkPaymentStatus` deploy edildi
- [ ] `getPaymentHistory` deploy edildi
- [ ] `activateFreeTrial` deploy edildi

## 7. Build ve Dagitim

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] Xcode Archive (Release) hatasiz aliniyor
- [ ] TestFlight internal test tamam
- [ ] App Store metadata ve review notlari guncel

## 8. Post-Release Izleme

- [ ] Firebase Crashlytics/Logs izleniyor
- [ ] Satin alma callback ve receipt verify hatalari izleniyor
- [ ] FCM token write/refresh oranlari kontrol ediliyor
