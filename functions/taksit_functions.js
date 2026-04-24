/**
 * Taksit Vade Tarihi Bildirimleri
 * Her gün 07:00 (Europe/Istanbul) çalışır, vadesi gelen taksitleri kontrol eder
 * ve şirketteki kullanıcılara bildirim gönderir.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// admin.initializeApp payment_functions.js içinde zaten yapılıyor
const db = admin.firestore();

function formatTL(n) {
  const v = Number(n || 0);
  return (
    "₺" +
    v.toLocaleString("tr-TR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  );
}

exports.dailyTaksitVadeKontrolu = functions.pubsub
  .schedule("every day 07:00")
  .timeZone("Europe/Istanbul")
  .onRun(async (context) => {
    console.log("💰 Taksit vade kontrolü başladı");

    try {
      // Bugün sonuna kadar (Türkiye saatiyle) vadesi gelen taksitleri al
      const now = new Date();
      const sonGun = new Date(now);
      sonGun.setHours(23, 59, 59, 999);

      const taksitlerSnap = await db
        .collectionGroup("taksitler")
        .where("odendi", "==", false)
        .where("vadeTarihi", "<=", admin.firestore.Timestamp.fromDate(sonGun))
        .get();

      if (taksitlerSnap.empty) {
        console.log("✅ Vadesi gelen taksit yok");
        return null;
      }

      // Şirket bazlı grupla
      // sirketBazli[sirketId] = { sirketAd, emailler, items: [{...}] }
      const sirketBazli = {};

      // cari ve plan dokümanlarını cache'le (aynı plan içinde birden fazla taksit olabilir)
      const cariCache = {};
      const planCache = {};

      for (const taksitDoc of taksitlerSnap.docs) {
        const t = taksitDoc.data();
        // path: cari_hesaplar/{cariId}/taksit_planlari/{planId}/taksitler/{taksitId}
        const planRef = taksitDoc.ref.parent.parent;
        if (!planRef) continue;
        const cariRef = planRef.parent.parent;
        if (!cariRef) continue;

        const cariId = cariRef.id;
        const planId = planRef.id;

        // Cari bilgisi
        if (!cariCache[cariId]) {
          const cariSnap = await cariRef.get();
          if (!cariSnap.exists) continue;
          cariCache[cariId] = cariSnap.data();
        }
        const cari = cariCache[cariId];
        const sirketId = cari.sirketId;
        if (!sirketId) continue;

        // Plan bilgisi
        const planKey = `${cariId}_${planId}`;
        if (!planCache[planKey]) {
          const planSnap = await planRef.get();
          if (!planSnap.exists) continue;
          planCache[planKey] = planSnap.data();
        }
        const plan = planCache[planKey];

        // Sirket bilgisi
        if (!sirketBazli[sirketId]) {
          const sirketSnap = await db.collection("sirketler").doc(sirketId).get();
          if (!sirketSnap.exists) continue;
          const sd = sirketSnap.data();
          sirketBazli[sirketId] = {
            sirketAd: sd.ad || "Şirket",
            emailler: sd.emailler || [],
            items: [],
          };
        }

        const tutar = Number(t.tutar || 0);
        const odenenTutar = Number(t.odenenTutar || 0);
        const kalan = Math.max(0, tutar - odenenTutar);
        if (kalan <= 0.01) continue;

        const vadeT = t.vadeTarihi && t.vadeTarihi.toDate ? t.vadeTarihi.toDate() : null;
        const gunFarki = vadeT
          ? Math.floor((now - vadeT) / (1000 * 60 * 60 * 24))
          : 0;

        sirketBazli[sirketId].items.push({
          cariAd: cari.ad || cari.cariAd || "Cari",
          tip: plan.tip || "tahsilat",
          projeAd: plan.projeAd || "",
          sira: t.sira || 0,
          tutar,
          kalan,
          vadeTarihi: vadeT ? vadeT.toISOString() : null,
          gunGecikme: gunFarki,
          cariId,
          planId,
          taksitId: taksitDoc.id,
        });
      }

      // Her şirket için bildirim oluştur
      for (const sirketId of Object.keys(sirketBazli)) {
        const grup = sirketBazli[sirketId];
        if (grup.items.length === 0) continue;

        // En geciken üstte
        grup.items.sort((a, b) => b.gunGecikme - a.gunGecikme);

        const istDateStr = now.toLocaleDateString("tr-TR", {
          timeZone: "Europe/Istanbul",
          day: "2-digit",
          month: "2-digit",
          year: "numeric",
        });

        // Rapor dokümanı (görüntüleme için)
        const raporRef = await db.collection("gunluk_raporlar").add({
          sirketId,
          sirketAd: grup.sirketAd,
          tarih: admin.firestore.FieldValue.serverTimestamp(),
          tarihStr: istDateStr,
          tip: "taksit_vade",
          baslik: "Vadesi Gelen Taksitler",
          taksitler: grup.items,
          toplamTaksit: grup.items.length,
        });

        // Özet metni — ilk 5
        const ozetSatirlari = grup.items.slice(0, 5).map((it) => {
          const tipKelime = it.tip === "tahsilat" ? "tahsilat" : "ödeme";
          const projeKisim = it.projeAd ? ` - ${it.projeAd}` : "";
          const gecikmeKisim = it.gunGecikme > 0 ? ` (${it.gunGecikme} gün gecikti)` : "";
          return `• ${it.cariAd}${projeKisim} - ${formatTL(it.kalan)} ${tipKelime}${gecikmeKisim}`;
        });
        const daha =
          grup.items.length > 5 ? `\n…ve ${grup.items.length - 5} taksit daha` : "";
        const bildirimMesaj =
          `${istDateStr} tarihinde vadesi gelen ${grup.items.length} taksit:\n` +
          ozetSatirlari.join("\n") +
          daha;

        // In-app bildirim
        await db
          .collection("sirketler")
          .doc(sirketId)
          .collection("bildirimler")
          .add({
            baslik: `💰 Vadesi Gelen ${grup.items.length} Taksit`,
            mesaj: bildirimMesaj,
            projeId: "",
            gonderen: "Sistem",
            modul: "taksit_vade",
            raporId: raporRef.id,
            tarih: admin.firestore.FieldValue.serverTimestamp(),
            okuyanlar: [],
          });

        // FCM token'ları topla
        const tokens = [];
        for (const email of grup.emailler) {
          try {
            const userRecord = await admin.auth().getUserByEmail(email);
            const userDoc = await db.collection("users").doc(userRecord.uid).get();
            if (userDoc.exists && userDoc.data().fcmTokens) {
              tokens.push(...userDoc.data().fcmTokens);
            }
          } catch (_) {}
        }

        if (tokens.length === 0) {
          console.log(
            `✅ ${grup.sirketAd}: ${grup.items.length} taksit raporu yazıldı (FCM token yok)`
          );
          continue;
        }

        const ilk = grup.items[0];
        const ilkTip = ilk.tip === "tahsilat" ? "tahsilat" : "ödeme";
        const pushBody =
          grup.items.length === 1
            ? `${ilk.cariAd}${ilk.projeAd ? " - " + ilk.projeAd : ""} - ${formatTL(
                ilk.kalan
              )} ${ilkTip} vadesi geldi`
            : `${grup.items.length} taksit vadesi geldi — ${ilk.cariAd} ${formatTL(
                ilk.kalan
              )} ${ilkTip}${ilk.gunGecikme > 0 ? " (" + ilk.gunGecikme + " gün gecikti)" : ""}`;

        const message = {
          notification: {
            title: `💰 ${grup.sirketAd} - Taksit Vade`,
            body: pushBody,
          },
          data: {
            type: "taksit_vade",
            sirketId,
            raporId: raporRef.id,
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
              channelId: "high_importance_channel",
            },
          },
          apns: {
            payload: { aps: { sound: "default", badge: 1 } },
          },
        };

        const invalidTokens = [];
        for (const token of tokens) {
          try {
            await admin.messaging().send({ ...message, token });
          } catch (err) {
            if (
              err.code === "messaging/invalid-registration-token" ||
              err.code === "messaging/registration-token-not-registered"
            ) {
              invalidTokens.push(token);
            }
          }
        }

        if (invalidTokens.length > 0) {
          for (const email of grup.emailler) {
            try {
              const userRecord = await admin.auth().getUserByEmail(email);
              await db
                .collection("users")
                .doc(userRecord.uid)
                .update({
                  fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
                });
            } catch (_) {}
          }
        }

        console.log(
          `✅ ${grup.sirketAd}: ${grup.items.length} taksit, ${tokens.length} cihaza bildirim gönderildi`
        );
      }

      console.log("💰 Taksit vade kontrolü tamamlandı");
      return null;
    } catch (error) {
      console.error("❌ Taksit vade kontrolü hatası:", error);
      return null;
    }
  });
