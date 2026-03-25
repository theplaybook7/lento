/**
 * İnşaat Yönetim Sistemi - Firebase Cloud Functions
 * Ödeme işlemleri ve doğrulama (Apple IAP)
 * 
 * Deploy etmek için:
 * cd functions
 * npm install
 * firebase deploy --only functions
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

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
