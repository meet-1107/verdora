// Firebase Cloud Messaging service worker for the Flutter WEB admin/client.
//
// Config below is for project nexgrova-fba5d (Web app). For web push token
// retrieval you still need a Web Push certificate: Firebase console →
// Project settings → Cloud Messaging → Web configuration → generate a key pair,
// then pass that VAPID key to getToken() on web.
//
// This file must live at web/firebase-messaging-sw.js so it is served from the
// site root.

importScripts(
  "https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js"
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js"
);

firebase.initializeApp({
  apiKey: "AIzaSyA91vZB7_JjNyPE5UguhCQg23wnKOsHoRg",
  appId: "1:311166388305:web:642ab4b171a073e965d070",
  messagingSenderId: "311166388305",
  projectId: "nexgrova-fba5d",
  storageBucket: "nexgrova-fba5d.firebasestorage.app",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  self.registration.showNotification(notification.title || "Notification", {
    body: notification.body || "",
  });
});
