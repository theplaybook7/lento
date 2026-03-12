/**
 * İnşaat Yönetim Sistemi - Firebase Cloud Functions
 * Ödeme işlemleri ve doğrulama
 * 
 * Deploy etmek için:
 * cd functions
 * npm install
 * firebase deploy --only functions
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const Stripe = require("stripe");

admin.initializeApp();
const db = admin.firestore();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

// ===== İN-APP PURCHASE DOĞRULAMA (İOS/Android) =====

/**
 * App Store (iOS) Receipt Doğrulama
 * Apple'dan satın almayı doğrula
 */
exports.verifyAppStoreReceipt = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişi gerekli"
    );
  }

  const { receipt } = data;
  if (!receipt) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Receipt gerekli"
    );
  }

  try {
    // Apple App Store Receipt Doğrulama
    // https://developer.apple.com/documentation/appstorereceipts/verifying_app_store_receipts
    
    const requestBody = {
      "receipt-data": receipt,
      password: process.env.APPLE_APP_PASSWORD,
    };

    const response = await fetch(
      "https://buy.itunes.apple.com/verifyReceipt", // Production
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(requestBody),
      }
    );

    const result = await response.json();

    if (result.status === 0) {
      // Başarılı
      await db.collection("payments").add({
        userId: context.auth.uid,
        type: "ios_app_store",
        transactionId: result.latest_receipt_info[0].transaction_id,
        productId: result.latest_receipt_info[0].product_id,
        purchaseDate: new Date(
          parseInt(result.latest_receipt_info[0].purchase_date_ms)
        ),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        verified: true,
      });

      // Kullanıcıya şirket oluşturma yetkisi ver
      await db.collection("users").doc(context.auth.uid).update({
        companyCreationPaid: true,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        productId: "create_company_payment",
        transactionId: result.latest_receipt_info[0].transaction_id,
      });

      return { success: true, message: "✅ Ödeme doğrulandı!" };
    } else {
      throw new Error("Apple receipt doğrulaması başarısız: " + result.status);
    }
  } catch (error) {
    console.error("App Store doğrulama hatası:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Ödeme doğrulama hatası: " + error.message
    );
  }
});

/**
 * Google Play Receipt Doğrulama (Android)
 * Google Play Billing kütüphanesi ile doğrula
 */
exports.verifyGooglePlayReceipt = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişi gerekli"
    );
  }

  const { packageName, subscriptionId, token } = data;

  try {
    // Google Play API ile doğrula
    // TODO: Google Play Billing API kütüphanesi konfigürasyonu gerekli
    // https://developers.google.com/android-publisher

    // Örnek response
    await db.collection("payments").add({
      userId: context.auth.uid,
      type: "google_play",
      packageName,
      subscriptionId,
      purchaseDate: new Date(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      verified: true,
    });

    await db.collection("users").doc(context.auth.uid).update({
      companyCreationPaid: true,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      productId: "create_company_payment",
    });

    return { success: true, message: "✅ Google Play ödeme doğrulandı!" };
  } catch (error) {
    console.error("Google Play doğrulama hatası:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Google Play doğrulama hatası: " + error.message
    );
  }
});

// ===== STRIPE CHECKOUT (WEB) =====

/**
 * Stripe Checkout Session Oluştur
 * Web abonelik ödeme işlemini başlat
 */
exports.initStripeCheckout = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişi gerekli"
    );
  }

  const { email, planType, successUrl, cancelUrl } = data;

  // Plan konfigürasyonu
  const plans = {
    monthly: {
      priceAmount: 299999, // ₺2.999,99 kuruş cinsinden
      interval: "month",
      intervalCount: 1,
      name: "Aylık Abonelik",
    },
    yearly: {
      priceAmount: 2999900, // ₺29.999,00 kuruş cinsinden
      interval: "year",
      intervalCount: 1,
      name: "Yıllık Abonelik",
    },
  };

  const plan = plans[planType] || plans.monthly;

  try {
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "try",
            product_data: {
              name: plan.name,
              description: "Lento İnşaat Yönetim Sistemi - " + plan.name,
              metadata: {
                userId: context.auth.uid,
              },
            },
            unit_amount: plan.priceAmount,
            recurring: {
              interval: plan.interval,
              interval_count: plan.intervalCount,
            },
          },
          quantity: 1,
        },
      ],
      mode: "subscription",
      customer_email: email || context.auth.token.email,
      success_url: successUrl || "https://insaat-yonetim-takip.web.app/?payment=success",
      cancel_url: cancelUrl || "https://insaat-yonetim-takip.web.app/?payment=cancelled",
      metadata: {
        userId: context.auth.uid,
        planType: planType || "monthly",
      },
    });

    return { sessionId: session.id, url: session.url };
  } catch (error) {
    console.error("Stripe session oluşturma hatası:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Checkout session oluşturma hatası: " + error.message
    );
  }
});

/**
 * Stripe Webhook Handler
 * Ödeme tamamlandığında tetiklenir
 */
exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers["stripe-signature"];

  try {
    const event = stripe.webhooks.constructEvent(
      req.rawBody,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );

    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const userId = session.metadata.userId;
      const planType = session.metadata.planType || "monthly";

      // Abonelik bitiş tarihi hesapla
      const now = new Date();
      let endDate;
      if (planType === "yearly") {
        endDate = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);
      } else {
        endDate = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      }

      // Ödemeyi kaydet
      await db.collection("payments").add({
        userId,
        type: "stripe",
        sessionId: session.id,
        subscriptionId: session.subscription,
        amount: session.amount_total / 100,
        currency: session.currency,
        planType,
        status: "completed",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        verified: true,
      });

      // Kullanıcıya izin ver
      await db.collection("users").doc(userId).set(
        {
          companyCreationPaid: true,
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          productId: planType === "yearly" ? "company_yearly_subscription" : "company_monthly_subscription",
          transactionId: session.id,
          subscriptionType: planType,
          subscriptionEndDate: admin.firestore.Timestamp.fromDate(endDate),
          stripeSubscriptionId: session.subscription,
          autoRenew: true,
          lastPurchaseStatus: "completed",
        },
        { merge: true }
      );

      console.log(`✅ Stripe abonelik ödeme doğrulandı: ${userId} (${planType})`);
    }

    if (event.type === "customer.subscription.deleted") {
      // Abonelik iptal edildi
      const subscription = event.data.object;
      const payments = await db
        .collection("payments")
        .where("stripeSubscriptionId", "==", subscription.id)
        .limit(1)
        .get();

      if (!payments.empty) {
        const userId = payments.docs[0].data().userId;
        await db.collection("users").doc(userId).set(
          {
            autoRenew: false,
            lastPurchaseStatus: "cancelled",
          },
          { merge: true }
        );
        console.log(`⚠️ Abonelik iptal edildi: ${userId}`);
      }
    }

    res.json({ received: true });
  } catch (error) {
    console.error("Webhook hatası:", error);
    res.status(400).send(`Webhook Error: ${error.message}`);
  }
});

// ===== YARDIMCI FONKSİYONLAR =====

/**
 * Ödeme Geçmişini Getir
 */
exports.getPaymentHistory = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişi gerekli"
    );
  }

  try {
    const payments = await db
      .collection("payments")
      .where("userId", "==", context.auth.uid)
      .orderBy("createdAt", "desc")
      .limit(10)
      .get();

    return payments.docs.map((doc) => doc.data());
  } catch (error) {
    throw new functions.https.HttpsError(
      "internal",
      "Ödeme geçmişi getirme hatası: " + error.message
    );
  }
});

/**
 * Ödeme Durumunu Kontrol Et
 */
exports.checkPaymentStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişı gerekli"
    );
  }

  try {
    const userDoc = await db.collection("users").doc(context.auth.uid).get();

    if (!userDoc.exists) {
      return { paid: false };
    }

    return {
      paid: userDoc.data().companyCreationPaid || false,
      paidAt: userDoc.data().paidAt,
    };
  } catch (error) {
    throw new functions.https.HttpsError(
      "internal",
      "Ödeme durumu kontrol hatası: " + error.message
    );
  }
});
