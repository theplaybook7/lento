import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/responsive_utils.dart' as resp;
import '../payment_service.dart';

enum PaywallMode { creation, subscription }

class PaywallScreen extends StatefulWidget {
  final PaywallMode mode;
  const PaywallScreen({super.key, this.mode = PaywallMode.creation});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum PlanType { solo, enterprise, trial }

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = false;
  bool _productsLoading = true;
  String _statusMessage = "";
  final Map<String, ProductDetails> _products = {};
  PlanType _selectedPlan = PlanType.enterprise;
  bool _trialUsed = false;

  @override
  void initState() {
    super.initState();
    // Web'de varsayılan olarak trial seç (IAP yok)
    if (!PaymentService().isPaymentSupported) {
      _selectedPlan = PlanType.trial;
    }
    _prepareStore();
  }

  Future<void> _prepareStore() async {
    final paymentService = PaymentService();
    await paymentService.initialize();

    // Deneme kullanılmış mı kontrol et
    final trialUsed = await paymentService.hasUsedTrial();
    if (mounted) setState(() => _trialUsed = trialUsed);

    if (!paymentService.isPaymentSupported) {
      if (mounted) {
        setState(() {
          _productsLoading = false;
          if (_trialUsed) {
            _statusMessage = 'Abonelik satın alma bu cihazda desteklenmiyor. Lütfen mobil uygulamayı kullanın.';
          }
        });
      }
      return;
    }

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final paymentService = PaymentService();
    final products = await paymentService.fetchSubscriptionProducts();

    if (!mounted) return;

    setState(() {
      _products
        ..clear()
        ..addEntries(products.map((p) => MapEntry(p.id, p)));
      _productsLoading = false;
      if (_products.isEmpty && _statusMessage.isEmpty) {
        // StoreKit hatası varsa sadece bilgi olarak göster (kırmızı değil)
        final storeName = PaymentService().isApplePaymentSupported ? 'App Store' : 'Google Play';
        _statusMessage = paymentService.lastError.isNotEmpty
            ? 'ℹ️ ${paymentService.lastError}'
            : 'ℹ️ $storeName ürün bilgileri yüklenemedi. Fiyatlar tahminidir.';
      }
    });
  }

  Future<void> _buySubscription(PlanType planType) async {
    setState(() {
      _loading = true;
      _statusMessage = "";
    });

    try {
      final paymentService = PaymentService();

      // Deneme başlat
      if (planType == PlanType.trial) {
        final success = await paymentService.startFreeTrial();
        if (success) {
          setState(() {
            _statusMessage = "✅ 1 haftalık ücretsiz deneme başlatıldı! Yönlendiriliyorsunuz...";
            _trialUsed = true;
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context, true);
          });
        } else {
          setState(() {
            _statusMessage = "❌ ${paymentService.lastError.isNotEmpty ? paymentService.lastError : 'Deneme başlatılamadı.'}";
          });
        }
        return;
      }

      if (!paymentService.isPaymentSupported) {
        setState(() {
          _statusMessage = 'Abonelik satın alma bu cihazda desteklenmiyor.';
        });
        return;
      }
      
      bool success = false;
      String productId = '';
      
      switch (planType) {
        case PlanType.enterprise:
          productId = PaymentService.enterpriseMonthlySubscriptionId;
          break;
        case PlanType.solo:
          productId = PaymentService.soloMonthlySubscriptionId;
          break;
        case PlanType.trial:
          break;
      }

      if (productId.isNotEmpty) {
        success = await paymentService.purchaseSubscription(productId);
        
        if (success) {
          setState(() {
            _statusMessage = "✅ Abonelik başarılı! Yönlendiriliyorsunuz...";
          });
          
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context, true);
          });
        } else {
          setState(() {
            _statusMessage = "❌ ${paymentService.lastError.isNotEmpty ? paymentService.lastError : 'Ödeme işlemi başarısız oldu. Lütfen tekrar deneyin.'}";
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = "❌ ${hataCevir(e)}";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    final paymentService = PaymentService();
    setState(() {
      _loading = true;
      _statusMessage = '';
    });

    final restored = await paymentService.restorePurchases();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _statusMessage = restored
          ? '✅ Satın alımlar geri yüklendi. Aboneliğiniz aktifse devam edebilirsiniz.'
          : '❌ ${paymentService.lastError.isNotEmpty ? paymentService.lastError : 'Satın alımlar geri yüklenemedi.'}';
    });
  }

  String _priceTextForPlan(PlanType planType) {
    final id = planType == PlanType.enterprise
        ? PaymentService.enterpriseMonthlySubscriptionId
        : PaymentService.soloMonthlySubscriptionId;
    final product = _products[id];
    if (product != null && product.price.isNotEmpty) {
      return product.price;
    }
    // Fallback fiyatlar (StoreKit yüklenemezse)
    if (!_productsLoading) {
      return planType == PlanType.enterprise ? '₺29.999,99' : '₺2.999,99';
    }
    return 'Yükleniyor...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == PaywallMode.subscription ? 'Abonelik' : 'Şirket Oluşturma'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(resp.isMobile(context) ? 14.0 : 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Premium Icon
              Container(
                width: resp.isMobile(context) ? 80 : 120,
                height: resp.isMobile(context) ? 80 : 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withValues(alpha: 0.6),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.mode == PaywallMode.subscription
                      ? Icons.autorenew
                      : Icons.business,
                  size: resp.isMobile(context) ? 40 : 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                widget.mode == PaywallMode.subscription
                    ? 'Aboneliği Yenile'
                    : 'Şirket Oluştur',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Subtitle
              Text(
                widget.mode == PaywallMode.subscription
                    ? 'Devam etmek için aboneliğinizi yenileyin'
                    : 'Yapı yönetim sisteminizi başlatın',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              if (PaymentService().isPaymentSupported)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_outlined, size: 16, color: AppTheme.primaryColor),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              PaymentService().isApplePaymentSupported
                                  ? 'Ödeme App Store üzerinden güvenli şekilde yapılır'
                                  : 'Ödeme Google Play üzerinden güvenli şekilde yapılır',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plan Ayrimlari',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.brown.shade700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('• ÜCRETSIZ: 1 aktif proje + 10 cari hesap'),
                            const Text('• SOLO (Aylik): Sinirsiz proje/cari, personel ekleme kapali'),
                            const Text('• BUYUK ISLETME (Aylik): Tum ozellikler + personel + proje paylasimi'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 40),

              // Ücretsiz Deneme
              if (!_trialUsed)
                ...[
                  _buildPlanCard(
                    title: "1 Hafta Ücretsiz",
                    subtitle: "Deneme",
                    price: "₺0",
                    duration: "/7 gün",
                    features: [
                      "1 aktif proje hakkı",
                      "10 cari hesap hakkı",
                      "Personel ekleme kapalı",
                      "Proje paylaşımı kapalı",
                      "Kredi kartı gerekmez",
                      "Otomatik yenileme yok",
                    ],
                    planType: PlanType.trial,
                    isPopular: false,
                    isTrial: true,
                  ),
                  const SizedBox(height: 16),
                ],

              // Plans (only on platforms supporting IAP)
              if (PaymentService().isPaymentSupported) ...[
                _buildPlanCard(
                  title: "SOLO",
                  subtitle: "Tek Kişilik İşletme (Aylık)",
                  price: _priceTextForPlan(PlanType.solo),
                  duration: "/ay",
                  features: [
                    "Sınırsız proje yönetimi",
                    "Sınırsız cari hesap",
                    "Personel ekleme kapalı",
                    "Proje paylaşımı yok",
                    "Mali raporlama ve analiz",
                    "Otomatik aylık yenileme",
                    "7 gün para iade garantisi",
                  ],
                  planType: PlanType.solo,
                  isPopular: false,
                  ctaLabel: 'SOLO Başlat',
                ),
                const SizedBox(height: 16),

                _buildPlanCard(
                  title: "BÜYÜK İŞLETME",
                  subtitle: "Enterprise (Aylık)",
                  price: _priceTextForPlan(PlanType.enterprise),
                  duration: "/ay",
                  features: [
                    "Sınırsız proje yönetimi",
                    "Sınırsız cari hesap",
                    "Personel ekleme ve rol yönetimi",
                    "Proje paylaşımı: Ruhsat/Şantiye/Muhasebe bazlı",
                    "Paylaşılan hesap için düzenleme yetkisi seçimi",
                    "Mali raporlama ve analiz",
                    "Otomatik aylık yenileme",
                    "7 gün para iade garantisi",
                    "Öncelikli destek",
                  ],
                  planType: PlanType.enterprise,
                  isPopular: true,
                  ctaLabel: 'Büyük İşletme Başlat',
                ),
              ],
              const SizedBox(height: 40),

              // Status Message
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _statusMessage.contains("❌")
                          ? Colors.red
                          : _statusMessage.contains("ℹ️")
                              ? Colors.blue.shade300
                              : Colors.green,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _statusMessage.contains("❌")
                        ? Colors.red.withValues(alpha: 0.1)
                        : _statusMessage.contains("ℹ️")
                            ? Colors.blue.withValues(alpha: 0.08)
                            : Colors.green.withValues(alpha: 0.1),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusMessage.contains("❌")
                          ? Colors.red
                          : _statusMessage.contains("ℹ️")
                              ? Colors.blue.shade700
                              : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 32),

              // Purchase Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _loading || (_productsLoading && _selectedPlan != PlanType.trial) ? null : () => _buySubscription(_selectedPlan),
                  icon: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              _loading
                                  ? Colors.white
                                  : AppTheme.primaryColor,
                            ),
                          ),
                        )
                      : const Icon(Icons.payment),
                  label: Text(
                    _loading
                        ? "İşleniyor..."
                        : _selectedPlan == PlanType.trial
                            ? "Ücretsiz Dene"
                            : _selectedPlan == PlanType.enterprise ? "Büyük İşletme Başla" : "SOLO Başla",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (PaymentService().isPaymentSupported) ...[
                const SizedBox(height: 4),
                Text(
                  'App Store Ürün Eşleşmesi: company_solo_monthly_subscription = SOLO | company_enterprise_monthly_subscription = BÜYÜK İŞLETME',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _restorePurchases,
                  child: const Text('Satın Alımları Geri Yükle'),
                ),

                // Abonelik Yönetimi Linki
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      PaymentService().isApplePaymentSupported
                          ? 'https://apps.apple.com/account/subscriptions'
                          : 'https://play.google.com/store/account/subscriptions',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Aboneliği Yönet'),
                ),

                // Subscription Terms
                const SizedBox(height: 8),
                Text(
                  PaymentService().isApplePaymentSupported
                      ? "Ödeme, Apple Kimliğiniz hesabına tahsil edilecektir. "
                        "Abonelik, mevcut dönem sona ermeden en az 24 saat önce iptal edilmedikçe otomatik olarak yenilenir. "
                        "Yenileme ücreti, mevcut dönem sona ermeden 24 saat içinde hesabınızdan tahsil edilir. "
                        "Aboneliğinizi Ayarlar > Apple Kimliği > Abonelikler bölümünden yönetebilir veya iptal edebilirsiniz."
                      : "Ödeme, Google hesabınıza tahsil edilecektir. "
                        "Abonelik, mevcut dönem sona ermeden en az 24 saat önce iptal edilmedikçe otomatik olarak yenilenir. "
                        "Yenileme ücreti, mevcut dönem sona ermeden 24 saat içinde hesabınızdan tahsil edilir. "
                        "Aboneliğinizi Google Play > Abonelikler bölümünden yönetebilir veya iptal edebilirsiniz.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('https://insaat-yonetim-takip.web.app/privacy.html'), mode: LaunchMode.externalApplication),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Text(
                        'Gizlilik Politikası',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryColor,
                          decoration: TextDecoration.underline,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Text('|', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('https://insaat-yonetim-takip.web.app/terms.html'), mode: LaunchMode.externalApplication),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Text(
                        'Kullanım Koşulları',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryColor,
                          decoration: TextDecoration.underline,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPlanCard({
    required String title,
    required String subtitle,
    required String price,
    required String duration,
    String? discount,
    required List<String> features,
    required PlanType planType,
    required bool isPopular,
    bool isTrial = false,
    String? ctaLabel,
  }) {
    final isSelected = _selectedPlan == planType;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = planType),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.05) : Colors.white,
        ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(resp.isMobile(context) ? 14.0 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPopular ? AppTheme.primaryColor : null,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    )),
                    if (isPopular)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "TAVSIYELI",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: price,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      TextSpan(
                        text: " $duration",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (discount != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    discount,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ...features.map((feature) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(feature, style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                )),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading || (_productsLoading && !isTrial) ? null : () => _buySubscription(planType),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTrial ? Colors.green : (isPopular ? AppTheme.primaryColor : Colors.grey.shade300),
                      foregroundColor: isTrial ? Colors.white : (isPopular ? Colors.white : Colors.black87),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      isTrial ? "Ücretsiz Dene" : (ctaLabel ?? "Satın Al"),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
