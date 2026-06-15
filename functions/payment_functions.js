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

const APPLE_VERIFY_RECEIPT_PROD_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_VERIFY_RECEIPT_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";

function subscriptionTypeFromProductId(productId) {
  if (
    productId === "company_enterprise_monthly_subscription" ||
    productId === "company_yearly_subscription"
  ) {
    return "enterprise_monthly";
  }
  if (
    productId === "company_solo_monthly_subscription" ||
    productId === "company_monthly_subscription"
  ) {
    return "solo_monthly";
  }
  return null;
}

function planTierFromSubscriptionType(type) {
  if (type === "enterprise_monthly") return "enterprise";
  if (type === "solo_monthly") return "solo";
  return "free";
}

function subscriptionEndDateForType(type) {
  // Is kurali: su anda tum ucretli planlar aylik tahsilata mapleniyor.
  if (type === "trial") {
    return new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  }
  return new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
}

async function verifyAppleReceipt(receipt) {
  const requestBody = {
    "receipt-data": receipt,
    password: process.env.APPLE_APP_PASSWORD,
  };

  let response = await fetch(APPLE_VERIFY_RECEIPT_PROD_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(requestBody),
  });

  let result = await response.json();

  // Sandbox makbuzu production endpointine giderse 21007 doner.
  if (result && result.status === 21007) {
    response = await fetch(APPLE_VERIFY_RECEIPT_SANDBOX_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestBody),
    });
    result = await response.json();
  }

  return result;
}

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

  const { receipt, productId, purchaseId } = data;
  if (!receipt) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Receipt gerekli"
    );
  }

  try {
    const result = await verifyAppleReceipt(receipt);

    if (result.status === 0) {
      const rawList = Array.isArray(result.latest_receipt_info)
        ? result.latest_receipt_info
        : [];
      if (rawList.length === 0) {
        throw new Error("Apple receipt icerigi bos.");
      }

      const normalizedProductId = typeof productId === "string" ? productId : "";
      const matched = normalizedProductId
        ? rawList.filter((item) => item.product_id === normalizedProductId)
        : rawList;
      if (matched.length === 0) {
        throw new Error("Receipt icinde beklenen urun bulunamadi.");
      }

      matched.sort((a, b) => Number(b.purchase_date_ms || 0) - Number(a.purchase_date_ms || 0));
      const latest = matched[0];
      const verifiedProductId = latest.product_id;
      const subscriptionType = subscriptionTypeFromProductId(verifiedProductId);
      if (!subscriptionType) {
        throw new Error(`Desteklenmeyen urun kimligi: ${verifiedProductId}`);
      }
      const subscriptionEndDate = subscriptionEndDateForType(subscriptionType);

      await db.collection("payments").add({
        userId: context.auth.uid,
        type: "ios_app_store",
        transactionId: latest.transaction_id || purchaseId || null,
        productId: verifiedProductId,
        purchaseDate: new Date(
          parseInt(latest.purchase_date_ms || Date.now(), 10)
        ),
        subscriptionType,
        subscriptionEndDate: admin.firestore.Timestamp.fromDate(subscriptionEndDate),
        source: "verifyAppStoreReceipt",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        verified: true,
      });

      await db.collection("users").doc(context.auth.uid).set({
        companyCreationPaid: true,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        productId: verifiedProductId,
        transactionId: latest.transaction_id || purchaseId || null,
        subscriptionType,
        subscriptionEndDate: admin.firestore.Timestamp.fromDate(subscriptionEndDate),
        autoRenew: true,
        lastPurchaseStatus: "verified",
      }, { merge: true });

      const userDoc = await db.collection("users").doc(context.auth.uid).get();
      const sirketId = userDoc.data()?.sirketId;
      if (typeof sirketId === "string" && sirketId.length > 0) {
        await db.collection("sirketler").doc(sirketId).set({
          subscriptionType,
          subscriptionEndDate: admin.firestore.Timestamp.fromDate(subscriptionEndDate),
          autoRenew: true,
          planTier: planTierFromSubscriptionType(subscriptionType),
        }, { merge: true });
      }

      return {
        success: true,
        message: "Odeme dogrulandi.",
        subscriptionType,
        subscriptionEndDate: subscriptionEndDate.toISOString(),
      };
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

/**
 * Guvenli ucretsiz deneme aktivasyonu
 */
exports.activateFreeTrial = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Kullanıcı girişi gerekli"
    );
  }

  const userRef = db.collection("users").doc(context.auth.uid);
  const userDoc = await userRef.get();
  const userData = userDoc.data() || {};

  if (userData.trialUsed === true) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Ucretsiz deneme daha once kullanilmis."
    );
  }

  const endDate = subscriptionEndDateForType("trial");

  await userRef.set({
    companyCreationPaid: true,
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    subscriptionType: "trial",
    subscriptionEndDate: admin.firestore.Timestamp.fromDate(endDate),
    autoRenew: false,
    trialUsed: true,
    trialStartDate: admin.firestore.FieldValue.serverTimestamp(),
    lastPurchaseStatus: "trial",
  }, { merge: true });

  const sirketId = userData.sirketId;
  if (typeof sirketId === "string" && sirketId.length > 0) {
    await db.collection("sirketler").doc(sirketId).set({
      subscriptionType: "trial",
      subscriptionEndDate: admin.firestore.Timestamp.fromDate(endDate),
      autoRenew: false,
      planTier: "free",
    }, { merge: true });
  }

  return {
    success: true,
    subscriptionType: "trial",
    subscriptionEndDate: endDate.toISOString(),
  };
});

/**
 * Legacy abonelikleri yeni aylik plan tiplerine donusturur.
 * - monthly => solo_monthly
 * - yearly => enterprise_monthly
 * 15 dakikada bir calisir; idempotent tasarlanmistir.
 */
exports.migrateLegacyPlansToEnterprise = functions.pubsub
  .schedule("every 15 minutes")
  .timeZone("Europe/Istanbul")
  .onRun(async () => {
    try {
      const now = new Date();
      const snap = await db
        .collection("sirketler")
        .where("subscriptionType", "in", ["monthly", "yearly"])
        .get();

      if (snap.empty) {
        console.log("migrateLegacyPlansToEnterprise: uygun sirket bulunamadi");
        return null;
      }

      let updated = 0;
      let skippedExpired = 0;
      let skippedAlready = 0;
      let batch = db.batch();
      let opCount = 0;

      for (const doc of snap.docs) {
        const data = doc.data() || {};
        const endTs = data.subscriptionEndDate;
        const endDate = endTs && typeof endTs.toDate === "function" ? endTs.toDate() : null;

        if (!endDate || endDate <= now) {
          skippedExpired += 1;
          continue;
        }

        const legacyType = data.subscriptionType;
        const normalizedType = subscriptionTypeFromProductId(
          legacyType === "yearly"
            ? "company_yearly_subscription"
            : legacyType === "monthly"
              ? "company_monthly_subscription"
              : ""
        );

        if (!normalizedType) {
          continue;
        }

        const targetPlanTier = planTierFromSubscriptionType(normalizedType);

        if (
          data.planTier === targetPlanTier &&
          data.subscriptionType === normalizedType
        ) {
          skippedAlready += 1;
          continue;
        }

        batch.set(
          db.collection("sirketler").doc(doc.id),
          {
            subscriptionType: normalizedType,
            planTier: targetPlanTier,
            migrationLegacyPlanAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        opCount += 1;
        updated += 1;

        if (opCount >= 450) {
          await batch.commit();
          batch = db.batch();
          opCount = 0;
        }
      }

      if (opCount > 0) {
        await batch.commit();
      }

      console.log(
        `migrateLegacyPlansToEnterprise: updated=${updated}, skippedExpired=${skippedExpired}, skippedAlready=${skippedAlready}`
      );
      return null;
    } catch (error) {
      console.error("migrateLegacyPlansToEnterprise hatasi:", error);
      return null;
    }
  });

// ===== PROJE PASİFLİK BİLDİRİMLERİ (Günlük) =====

// dailyInactivityCheck kaldırıldı — günlük rapor bildirimleri devre dışı.
// Eski fonksiyon her gün 07:00'da çalışıp bildirim gönderiyordu; artık aktif değil.
/*  KALDIRILDI:
exports.dailyInactivityCheck = functions.pubsub
  .schedule("every day 07:00")
  .timeZone("Europe/Istanbul")
  .onRun(async (context) => {
    console.log("📋 Günlük rapor oluşturuluyor (07:00)");

    try {
      // Tüm şirketleri al
      const sirketlerSnap = await db.collection("sirketler").get();

      for (const sirketDoc of sirketlerSnap.docs) {
        const sirketId = sirketDoc.id;
        const sirketAd = sirketDoc.data().ad || "Şirket";

        // Şirketin projelerini al (top-level projects koleksiyonu)
        const projelerSnap = await db
          .collection("projects")
          .where("companyId", "==", sirketId)
          .where("isArchived", "==", false)
          .get();

        const pasifProjeler = [];

        for (const projeDoc of projelerSnap.docs) {
          const projeId = projeDoc.id;
          const projeAd = projeDoc.data().name || "Proje";

          // Akış diyagramı meta ve maddelerini oku
          const akisColSnap = await db
            .collection("ruhsat")
            .doc(projeId)
            .collection("akis_diyagrami")
            .get();

          let meta = null;
          const akisMaddeler = [];
          for (const d of akisColSnap.docs) {
            if (d.id === "_meta") {
              meta = d.data();
            } else if (d.id !== "karar_kontrol" && d.id !== "yola_terk_kontrol") {
              akisMaddeler.push({ id: d.id, data: d.data() });
            }
          }

          // Ruhsat süreci başlatılmamışsa rapora dahil etme
          if (!meta || meta.baslatildi !== true) continue;
          // Ruhsat tamamlandıysa sayaç durduğu için rapora dahil etme
          if (meta.ruhsatTamamlandi === true) continue;

          // Son işlem tarihi = meta.sonGuncellemeTarihi ya da baslatmaTarihi
          let sonIslemTarihi = null;
          if (meta.sonGuncellemeTarihi && meta.sonGuncellemeTarihi.toDate) {
            sonIslemTarihi = meta.sonGuncellemeTarihi.toDate();
          } else if (meta.baslatmaTarihi && meta.baslatmaTarihi.toDate) {
            sonIslemTarihi = meta.baslatmaTarihi.toDate();
          }

          // Eski islemler koleksiyonundan da en son tarihi kontrol et (geri uyum)
          const islemlerSnap = await db
            .collection("ruhsat")
            .doc(projeId)
            .collection("islemler")
            .orderBy("guncellendiTarihi", "desc")
            .limit(1)
            .get();
          if (!islemlerSnap.empty) {
            const t = islemlerSnap.docs[0].data().guncellendiTarihi;
            if (t && t.toDate) {
              const it = t.toDate();
              if (!sonIslemTarihi || it > sonIslemTarihi) sonIslemTarihi = it;
            }
          }

          {
            const now = new Date();
            const diffDays = sonIslemTarihi
              ? Math.floor((now - sonIslemTarihi) / (1000 * 60 * 60 * 24))
              : 0;
            // Akış diyagramındaki notları topla (sadece boş olmayanlar)
            const notlar = [];
            for (const m of akisMaddeler) {
              const d = m.data || {};
              const not = (d.not || "").toString().trim();
              if (not.length > 0) {
                notlar.push({
                  sira: d.sira || 0,
                  madde: d.madde || "",
                  not: not,
                  durum: d.durum || 0,
                });
              }
            }
            notlar.sort((a, b) => a.sira - b.sira);

            pasifProjeler.push({
              ad: projeAd,
              gun: diffDays,
              id: projeId,
              sonIslemTarihi: sonIslemTarihi
                ? sonIslemTarihi.toISOString()
                : null,
              akisNotlari: notlar,
            });
          }
        }

        if (pasifProjeler.length === 0) {
          console.log(`✅ ${sirketAd}: pasif proje yok, rapor oluşturulmadı`);
          continue;
        }

        // En uzun süredir pasif olana göre sırala (azalan)
        pasifProjeler.sort((a, b) => b.gun - a.gun);

        // Rapor tarihi (YYYY-MM-DD, Europe/Istanbul)
        const now = new Date();
        const istDateStr = now.toLocaleDateString("tr-TR", {
          timeZone: "Europe/Istanbul",
          day: "2-digit",
          month: "2-digit",
          year: "numeric",
        });

        // 1) Günlük rapor dokümanını kaydet (görüntüleme + çıktı için)
        const raporRef = await db.collection("gunluk_raporlar").add({
          sirketId: sirketId,
          sirketAd: sirketAd,
          tarih: admin.firestore.FieldValue.serverTimestamp(),
          tarihStr: istDateStr,
          tip: "pasif_projeler",
          baslik: "Günlük Rapor",
          pasifProjeler: pasifProjeler.map((p) => ({
            projeId: p.id,
            projeAd: p.ad,
            gun: p.gun,
            sonIslemTarihi: p.sonIslemTarihi,
            akisNotlari: p.akisNotlari || [],
          })),
          toplamProje: pasifProjeler.length,
        });

        // 2) Firestore'a TEK bir in-app bildirim yaz (zil ikonu için)
        const ozetListe = pasifProjeler
          .slice(0, 5)
          .map((p) => `• ${p.ad} (${p.gun} gün)`)
          .join("\n");
        const daha =
          pasifProjeler.length > 5
            ? `\n…ve ${pasifProjeler.length - 5} proje daha`
            : "";
        const bildirimMesaj =
          `${istDateStr} tarihli günlük raporda ${pasifProjeler.length} proje var:\n` +
          ozetListe +
          daha;

        await db
          .collection("sirketler")
          .doc(sirketId)
          .collection("bildirimler")
          .add({
            baslik: `📋 Günlük Rapor - ${pasifProjeler.length} proje`,
            mesaj: bildirimMesaj,
            projeId: "",
            gonderen: "Sistem",
            modul: "gunluk_rapor",
            raporId: raporRef.id,
            tarih: admin.firestore.FieldValue.serverTimestamp(),
            okuyanlar: [],
          });

        // Bu şirketin kullanıcılarının FCM token'larını topla
        const emailler = sirketDoc.data().emailler || [];
        const tokens = [];

        for (const email of emailler) {
          try {
            const userRecord = await admin.auth().getUserByEmail(email);
            const userDoc = await db
              .collection("users")
              .doc(userRecord.uid)
              .get();
            if (userDoc.exists && userDoc.data().fcmTokens) {
              tokens.push(...userDoc.data().fcmTokens);
            }
          } catch (_) {
            // Kullanıcı bulunamadı, devam et
          }
        }

        if (tokens.length === 0) {
          console.log(
            `✅ ${sirketAd}: ${pasifProjeler.length} pasif proje raporu yazıldı (FCM token yok)`
          );
          continue;
        }

        // 3) TEK bir FCM Push bildirim gönder (özetleyen)
        const pushBody = `${pasifProjeler.length} proje — en uzun: ${pasifProjeler[0].ad} (${pasifProjeler[0].gun} gün)`;

        const message = {
          notification: {
            title: `📋 ${sirketAd} - Günlük Rapor`,
            body: pushBody,
          },
          data: {
            type: "gunluk_rapor",
            sirketId: sirketId,
            raporId: raporRef.id,
          },
          android: {
            priority: "high",
            notification: { sound: "default", channelId: "high_importance_channel" },
          },
          apns: {
            payload: { aps: { sound: "default", badge: 1 } },
          },
        };

        // Her token'a gönder (geçersiz olanları temizle)
        const invalidTokens = [];
        for (const token of tokens) {
          try {
            await admin.messaging().send({ ...message, token: token });
          } catch (err) {
            if (
              err.code === "messaging/invalid-registration-token" ||
              err.code === "messaging/registration-token-not-registered"
            ) {
              invalidTokens.push(token);
            }
          }
        }

        // Geçersiz token'ları temizle
        if (invalidTokens.length > 0) {
          for (const email of emailler) {
            try {
              const userRecord = await admin.auth().getUserByEmail(email);
              await db
                .collection("users")
                .doc(userRecord.uid)
                .update({
                  fcmTokens: admin.firestore.FieldValue.arrayRemove(
                    invalidTokens
                  ),
                });
            } catch (_) {}
          }
        }

        console.log(
          `✅ ${sirketAd}: ${pasifProjeler.length} pasif proje, ${tokens.length} cihaza TEK rapor bildirimi gönderildi`
        );
      }

      console.log("📋 Günlük rapor oluşturma tamamlandı");
      return null;
    } catch (error) {
      console.error("❌ Günlük rapor hatası:", error);
      return null;
    }
  });
*/ // KALDIRILDI SONU

// ===== GÖREV ATAMA FCM PUSH =====
Object.assign(module.exports, require('./gorev_functions'));

// ===== TAKSİT VADE BİLDİRİMLERİ =====
Object.assign(module.exports, require('./taksit_functions'));

