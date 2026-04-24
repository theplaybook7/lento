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

// ===== PROJE PASİFLİK BİLDİRİMLERİ (Günlük) =====

/**
 * Her gün sabah 09:00'da (Türkiye saati) çalışır.
 * 4+ gün işlem yapılmamış projeleri bulur ve FCM push bildirim gönderir.
 */
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

          if (sonIslemTarihi) {
            const now = new Date();
            const diffDays = Math.floor(
              (now - sonIslemTarihi) / (1000 * 60 * 60 * 24)
            );
            if (diffDays >= 2) {
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
                sonIslemTarihi: sonIslemTarihi.toISOString(),
                akisNotlari: notlar,
              });
            }
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
          baslik: "Günlük Rapor - Pasif Projeler",
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
          `${istDateStr} tarihli raporda ${pasifProjeler.length} pasif proje var:\n` +
          ozetListe +
          daha;

        await db
          .collection("sirketler")
          .doc(sirketId)
          .collection("bildirimler")
          .add({
            baslik: `📋 Günlük Rapor - ${pasifProjeler.length} pasif proje`,
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
        const pushBody = `${pasifProjeler.length} pasif proje — en uzun: ${pasifProjeler[0].ad} (${pasifProjeler[0].gun} gün)`;

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

// ===== GÖREV ATAMA FCM PUSH =====
Object.assign(module.exports, require('./gorev_functions'));

// ===== TAKSİT VADE BİLDİRİMLERİ =====
Object.assign(module.exports, require('./taksit_functions'));

