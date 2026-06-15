# Package Upgrade Plan

Bu plan iki fazliydi; Faz-1 uygulandi, Faz-2 istege bagli daha buyuk gecislerdir.

## Faz-1 (Dusuk Risk) - Uygulandi

Asagidaki paketler en son cozumlenebilir surumlere yukseltildi:

- cupertino_icons -> 1.0.9
- firebase_core -> 4.10.0
- firebase_auth -> 6.5.2
- cloud_firestore -> 6.5.0
- cloud_functions -> 6.3.2
- firebase_storage -> 13.4.2
- firebase_messaging -> 16.3.0
- image_picker -> 1.2.2
- in_app_purchase -> 3.3.0
- pdf -> 3.12.0
- printing -> 5.14.3

Dogrulama:
- `flutter analyze` -> temiz
- web release build -> basarili

## Faz-2 (Yuksek Etki / Breaking Olasiligi)

Asagidaki paketler buyuk surum atlamasi gerektiriyor; ayri bir branch ve regresyon testi ile ilerlenmeli:

- flutter_local_notifications (17.x -> 22.x)
- file_picker (8.x -> 11.x)
- syncfusion_flutter_pdfviewer (27.x -> 33.x)
- intl (0.19 -> 0.20)

On kosullar:
- iOS/Android fiziksel cihaz test matrisi
- TestFlight smoke test
- Kritik ekranlar: giris, paywall, cari, proje detay, bildirim
