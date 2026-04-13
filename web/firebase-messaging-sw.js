importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyAFPmbGYzuFhropyLDn3iidaRlzgVX_hpo",
  authDomain: "insaat-yonetim-takip.firebaseapp.com",
  projectId: "insaat-yonetim-takip",
  storageBucket: "insaat-yonetim-takip.firebasestorage.app",
  messagingSenderId: "478876596230",
  appId: "1:478876596230:web:bf478c1b7775f737dd6b87",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((message) => {
  const notificationTitle = message.notification?.title || "Lento Bildirim";
  const notificationOptions = {
    body: message.notification?.body || "",
    icon: "/icons/Icon-192.png",
  };
  return self.registration.showNotification(notificationTitle, notificationOptions);
});
