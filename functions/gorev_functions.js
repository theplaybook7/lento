/**
 * Görev atama: yeni gorevler/{id} oluşturulduğunda atanan kullanıcının
 * telefonlarına FCM push bildirimi gönder. Uygulama kapalı olsa bile
 * bildirim gelir.
 */
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();

exports.onGorevAtandi = functions.firestore
  .document("gorevler/{gorevId}")
  .onCreate(async (snap, context) => {
    try {
      const gorev = snap.data() || {};
      const atananEmail = gorev.atananEmail;
      const baslik = gorev.baslik || "Yeni görev";
      const aciklama = gorev.aciklama || "";
      const atayanEmail = gorev.atayanEmail || "";
      const sirketId = gorev.sirketId || "";
      const projeId = gorev.projeId || "";

      if (!atananEmail) {
        console.log("onGorevAtandi: atananEmail yok, atlanıyor");
        return null;
      }

      // Atanan kullanıcıyı email ile bul -> fcmTokens al
      let tokens = [];
      let atananUid = null;
      try {
        const userRecord = await admin.auth().getUserByEmail(atananEmail);
        atananUid = userRecord.uid;
        const userDoc = await db.collection("users").doc(userRecord.uid).get();
        if (userDoc.exists && Array.isArray(userDoc.data().fcmTokens)) {
          tokens = userDoc.data().fcmTokens;
        }
      } catch (e) {
        console.log(`onGorevAtandi: kullanıcı bulunamadı ${atananEmail}: ${e.message}`);
      }

      if (tokens.length === 0) {
        console.log(`onGorevAtandi: ${atananEmail} için FCM token yok, sadece in-app bildirim var`);
        return null;
      }

      const body = aciklama
        ? `${baslik}\n${aciklama}`
        : `${atayanEmail ? atayanEmail + " tarafından" : ""} yeni görev atandı`;

      const message = {
        notification: {
          title: `📋 Yeni Görev: ${baslik}`,
          body: body.length > 180 ? body.substring(0, 177) + "..." : body,
        },
        data: {
          type: "gorev_atama",
          gorevId: context.params.gorevId,
          sirketId: sirketId,
          projeId: projeId,
          atayanEmail: atayanEmail,
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              "content-available": 1,
            },
          },
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
          } else {
            console.error(`onGorevAtandi FCM hatası: ${err.message}`);
          }
        }
      }

      if (invalidTokens.length > 0 && atananUid) {
        try {
          await db
            .collection("users")
            .doc(atananUid)
            .update({
              fcmTokens: admin.firestore.FieldValue.arrayRemove(invalidTokens),
            });
        } catch (_) {}
      }

      console.log(
        `✅ Görev FCM push: ${atananEmail} -> ${tokens.length - invalidTokens.length}/${tokens.length} cihaz`
      );
      return null;
    } catch (error) {
      console.error("❌ onGorevAtandi hatası:", error);
      return null;
    }
  });
