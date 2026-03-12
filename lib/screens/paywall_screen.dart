import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../theme/app_theme.dart';
import '../payment_service.dart';
import '../web_payment_service.dart';

class PaywallScreen extends StatefulWidget {
  /// [email] verilirse auth olmadan Stripe checkout yapılır (yeni kullanıcı akışı)
  final String? email;
  const PaywallScreen({super.key, this.email});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum PlanType { monthly, yearly }

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = false;
  bool _productsLoading = true;
  String _statusMessage = "";
  final Map<String, ProductDetails> _products = {};

  bool get _isWeb => kIsWeb;

  @override
  void initState() {
    super.initState();
    _prepareStore();
  }

  Future<void> _prepareStore() async {
    if (_isWeb) {
      // Web: Stripe fiyatları statik, yükleme gerekmez
      setState(() => _productsLoading = false);
      return;
    }

    final paymentService = PaymentService();
    await paymentService.initialize();

    if (!paymentService.isApplePaymentSupported) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pop(context, false);
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
        _statusMessage = paymentService.lastError.isNotEmpty
            ? paymentService.lastError
            : 'App Store ürünleri yüklenemedi. Lütfen tekrar deneyin.';
      }
    });
  }

  Future<void> _buySubscription(PlanType planType) async {
    setState(() {
      _loading = true;
      _statusMessage = "";
    });

    try {
      if (_isWeb) {
        await _buySubscriptionWeb(planType);
        return;
      }

      final paymentService = PaymentService();

      if (!paymentService.isApplePaymentSupported) {
        setState(() {
          _statusMessage = 'Bu sürümde ödeme yalnızca Apple App Store (iOS/macOS) üzerinden yapılabilir.';
        });
        return;
      }
      
      bool success = false;
      String productId = '';
      
      switch (planType) {
        case PlanType.yearly:
          productId = 'company_yearly_subscription';
          break;
        case PlanType.monthly:
          productId = 'company_monthly_subscription';
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
        _statusMessage = "❌ Hata: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _buySubscriptionWeb(PlanType planType) async {
    // Email: widget parametresinden veya auth'lu kullanıcıdan al
    String? email = widget.email;
    if (email == null || email.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      email = user?.email;
    }

    // Hala email yoksa kullanıcıdan iste
    if (email == null || email.isEmpty) {
      email = await _askForEmail();
      if (email == null || email.isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }
    }

    final webPayment = WebPaymentService();
    final planTypeStr = planType == PlanType.yearly ? 'yearly' : 'monthly';

    final started = await webPayment.startCheckout(planType: planTypeStr, email: email);

    if (!mounted) return;

    if (started) {
      setState(() {
        _statusMessage = "✅ Stripe ödeme sayfasına yönlendiriliyorsunuz... "
            "Ödeme tamamlandıktan sonra bu sayfaya geri dönün.";
        _loading = false;
      });
    } else {
      setState(() {
        _statusMessage = "❌ ${webPayment.lastError}";
        _loading = false;
      });
    }
  }

  Future<String?> _askForEmail() async {
    final emailCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('E-Posta Adresi'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'E-Posta',
            hintText: 'ornek@email.com',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İPTAL'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailCtrl.text.trim();
              if (email.isNotEmpty && email.contains('@')) {
                Navigator.pop(ctx, email);
              }
            },
            child: const Text('DEVAM'),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePurchases() async {
    if (_isWeb) {
      // Web: Firestore'dan ödeme durumunu kontrol et
      setState(() {
        _loading = true;
        _statusMessage = '';
      });
      final webPayment = WebPaymentService();
      final status = await webPayment.getSubscriptionStatus();
      if (!mounted) return;
      if (status['active'] == true) {
        setState(() {
          _loading = false;
          _statusMessage = '✅ Aktif aboneliğiniz bulundu! Devam edebilirsiniz.';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context, true);
        });
      } else {
        setState(() {
          _loading = false;
          _statusMessage = '❌ Aktif abonelik bulunamadı.';
        });
      }
      return;
    }

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
    if (_isWeb) {
      final key = planType == PlanType.yearly ? 'yearly' : 'monthly';
      return WebPaymentService.webPlans[key]?['price'] as String? ?? '';
    }
    final id = planType == PlanType.yearly
        ? PaymentService.yearlySubscriptionId
        : PaymentService.monthlySubscriptionId;
    final product = _products[id];
    if (product != null && product.price.isNotEmpty) {
      return product.price;
    }
    return 'Yükleniyor...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Şirket Oluşturma"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Premium Icon
              Container(
                width: 120,
                height: 120,
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
                  Icons.business,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                "Şirket Oluştur",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Subtitle
              Text(
                "Yapı yönetim sisteminizi başlatın",
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      _isWeb
                          ? 'Güvenli ödeme Stripe altyapısı ile yapılır'
                          : 'Ödeme App Store üzerinden güvenli şekilde yapılır',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Plans
              _buildPlanCard(
                title: "Aylık",
                subtitle: "Subscription",
                price: _priceTextForPlan(PlanType.monthly),
                duration: "/ay",
                features: [
                  "Sınırsız proje yönetimi",
                  "Personel ve rol yönetimi",
                  "Mali raporlama ve analiz",
                  "Otomatik aylık yenileme",
                  "7 gün para iade garantisi",
                ],
                planType: PlanType.monthly,
                isPopular: false,
              ),
              const SizedBox(height: 16),

              _buildPlanCard(
                title: "Yıllık",
                subtitle: "En Uygun",
                price: _priceTextForPlan(PlanType.yearly),
                duration: "/yıl",
                discount: "2 ay tasarruf et",
                features: [
                  "Sınırsız proje yönetimi",
                  "Personel ve rol yönetimi",
                  "Mali raporlama ve analiz",
                  "Otomatik yıllık yenileme",
                  "30 gün para iade garantisi",
                  "Öncelikli destek",
                ],
                planType: PlanType.yearly,
                isPopular: true,
              ),
              const SizedBox(height: 40),

              // Status Message
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _statusMessage.contains("❌")
                          ? Colors.red
                          : Colors.green,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _statusMessage.contains("❌")
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusMessage.contains("❌")
                          ? Colors.red
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
                  onPressed: _loading || _productsLoading ? null : () => _buySubscription(PlanType.yearly),
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
                        : "Başla",
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

              TextButton(
                onPressed: _loading ? null : _restorePurchases,
                child: Text(_isWeb ? 'Ödeme Durumunu Kontrol Et' : 'Satın Alımları Geri Yükle'),
              ),

              // Subscription Terms
              const SizedBox(height: 8),
              Text(
                _isWeb
                    ? "Abonelik, iptal edilmedikçe otomatik olarak yenilenir. "
                      "Aboneliğinizi Stripe müşteri portalı üzerinden yönetebilir veya iptal edebilirsiniz."
                    : "Abonelik, iptal edilmedikçe otomatik olarak yenilenir. "
                      "Yenileme ücreti, mevcut dönem sona ermeden 24 saat önce hesabınızdan tahsil edilir. "
                      "Aboneliğinizi Ayarlar > Apple Kimliği > Abonelikler bölümünden yönetebilir veya iptal edebilirsiniz.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isWeb
                    ? "Ödeme Stripe üzerinden güvenli şekilde yapılır."
                    : "Ödeme App Store üzerinden güvenli şekilde yapılır.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
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
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isPopular ? AppTheme.primaryColor : Colors.grey.shade300,
          width: isPopular ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        color: isPopular ? AppTheme.primaryColor.withValues(alpha: 0.05) : Colors.white,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
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
                    ),
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
                    onPressed: _loading || _productsLoading ? null : () => _buySubscription(planType),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular ? AppTheme.primaryColor : Colors.grey.shade300,
                      foregroundColor: isPopular ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      "Satın Al",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
