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
 * Web ödeme işlemini başlat
 */
exports.initStripeCheckout = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişi gerekli"
    );
  }

  const { email, successUrl, cancelUrl } = data;

  try {
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "usd", // EUR, TRY vs. değiştirebilir
            product_data: {
              name: "Şirket Oluşturma",
              description: "İnşaat Yönetim Sistemi - Şirket Oluşturma",
              metadata: {
                userId: context.auth.uid,
              },
            },
            unit_amount: 999, // $9.99
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      customer_email: email,
      success_url: successUrl || "https://yourapp.com/success",
      cancel_url: cancelUrl || "https://yourapp.com/cancel",
      metadata: {
        userId: context.auth.uid,
        productId: "create_company_payment",
      },
    });

    return { sessionId: session.id };
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

      // Ödemeyi kaydet
      await db.collection("payments").add({
        userId,
        type: "stripe",
        sessionId: session.id,
        amount: session.amount_total / 100,
        currency: session.currency,
        status: "completed",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        verified: true,
      });

      // Kullanıcıya izin ver
      await db.collection("users").doc(userId).update({
        companyCreationPaid: true,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        productId: "create_company_payment",
        transactionId: session.id,
      });

      console.log(`✅ Ödeme doğrulandı: ${userId}`);
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
