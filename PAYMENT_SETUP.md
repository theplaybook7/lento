# Firebase Ödeme Sistemi Kurulum Rehberi

## 1. MOBILE (iOS & Android) - In-App Purchase Setup

### İOS - App Store Connect

1. **App Store Connect'e giriş yapın:**
   - https://appstoreconnect.apple.com
   - Uygulamanızı seçin

2. **In-App Purchase Ürünü Oluşturun:**
   - Müşteri Kaydı > Satın Alınabilir Öğeler
   - Yeni Ürün Ekle
   - Ürün Türü: **Tek Seferlik Satın Alma (Consumable)**
   - Referans Adı: `create_company_payment`
   - Ürün ID: `create_company_payment`
   - Fiyat: $9.99 / €9.99 / ₺99.99
   - Açıklama: "Şirket Oluşturma - İnşaat Yönetim Sistemi"

3. **Sandbox Test Hesabı Oluşturun:**
   - Settings > Users and Access > Sandbox
   - Yeni Tester Ekle
   - Test cihazında "Ayarlar > App Store > Giriş Yap"

### Android - Google Play Console

1. **Google Play Console'a giriş yapın:**
   - https://play.google.com/console
   - Uygulamanızı seçin

2. **In-App Product Oluşturun:**
   - Monetize > Products > In-App Products
   - Yeni Ürün Ekle
   - Ürün ID: `create_company_payment`
   - Ürün Türü: Consumable
   - Başlık: "Şirket Oluşturma"
   - Açıklama: "Yeni bir yapı yönetim şirketi oluşturun"
   - Fiyat: $9.99 / €9.99 / ₺99.99

3. **Sandbox'ı Test Edin:**
   - Ayarlar > Lisans Testi
   - Test cihazlarını ekleyin

## 2. WEB - Stripe Setup

### Stripe Account Oluşturma

1. **Stripe'ye kaydolun:**
   - https://dashboard.stripe.com/register

2. **API Keys Alın:**
   - Developers > API Keys
   - **Publishable Key** (Frontend'de kullanılır)
   - **Secret Key** (Backend/Cloud Functions'da kullanılır)

3. **Webhook Endpoint Oluşturun:**
   - Developers > Webhooks
   - "Add Endpoint" tıklayın
   - URL: `https://yourfunction.cloudfunctions.net/stripeWebhook`
   - Events: `checkout.session.completed`
   - Webhook Secret'i kaydedin

4. **Test Mode:**
   - Development sırasında Test mode kullanın
   - Test kartı: `4242 4242 4242 4242`
   - Expiry: Any future date
   - CVC: Any 3 digits

## 3. Firebase Cloud Functions Deployment

### Setup

```bash
# 1. Firebase CLI'ı yükleyin
npm install -g firebase-tools

# 2. Firebase'de oturum açın
firebase login

# 3. Functions klasörüne gidin
cd functions

# 4. Dependencies yükleyin
npm install
npm install stripe@latest
```

### Environment Variables Ayarlama

```bash
# Local development için
cp .env.template .env.local

# Edit .env.local ve kendi keys'lerinizi ekleyin:
# STRIPE_SECRET_KEY=sk_test_...
# STRIPE_WEBHOOK_SECRET=whsec_...
# APPLE_APP_PASSWORD=...

# Firebase CLI ile prod variables set etmek:
firebase functions:config:set stripe.key="sk_live_..." stripe.webhook_secret="whsec_..." apple.password="..."
```

### Deploy

```bash
# Test etmek (local)
firebase emulators:start --only functions

# Production'a deploy
firebase deploy --only functions
```

## 4. Firestore Security Rules Güncelleme

```bash
firebase deploy --only firestore:rules
```

## 5. Flutter App'ta Yapılandırma

### iOS - Info.plist

```xml
<dict>
  <key>UIDeviceFamily</key>
  <array>
    <integer>1</integer>
    <integer>2</integer>
  </array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>İnşaat Yönetim Sistemi, yerel ağ kullanır.</string>
</dict>
```

### Android - build.gradle

```gradle
dependencies {
  implementation 'com.android.billingclient:billing:6.0.1'
}
```

### pubspec.yaml

```yaml
dependencies:
  in_app_purchase: ^3.1.6
  flutter_stripe: ^11.0.0
```

## 6. Testing Checklist

- [ ] iOS: Sandbox test hesabı ile satın almayı test et
- [ ] Android: Test cihazı ile satın almayı test et
- [ ] Web: Stripe test kartı ile ödemeyi test et
- [ ] Firestore: Ödeme kaydının oluşturulduğunu doğrula
- [ ] Payment Status: `hasCompanyCreationAccess()` true dönüyor mu?
- [ ] Company Creation: Şirket oluşturma dialogu açılıyor mu?

## 7. Production Checklist

- [ ] Stripe Live Keys'i konfigure et
- [ ] Apple: Production Certificate'i upload et
- [ ] Google Play: Release build'i submit et
- [ ] Firebase Cloud Functions: Production'a deploy et
- [ ] Firestore Rules: Production rule'larını set et
- [ ] Monitoring: Firebase Console'da logs'ları kontrol et

## 8. Error Handling & Monitoring

### Firebase Console
- https://console.firebase.google.com
- Logs: Cloud Functions > Logs
- Errors: Firestore > Data > payments collection

### Stripe Dashboard
- Failed payments: https://dashboard.stripe.com/payments
- Webhook logs: Developers > Webhooks > Logs

## Fiyatlandırma Notları

- **Single Product**: Şirket başına bir kerelik ödeme
- **Flexible Pricing**: Para birimine göre ayarlanabilir
  - USD: $9.99
  - EUR: €9.99
  - TRY: ₺99.99
- **Refund Policy**: 30 gün içinde tam geri ödeme

## Türkiye Özel - İyzico Alternative

Eğer Stripe yerine İyzico kullanmak isterseniz:

1. İyzico'ya kaydolun: https://www.iyzipay.com
2. API Keys alın
3. Payment Service'i güncelleyin
4. Cloud Function'ı düzenleyin
