# NFC Read Write · NFC قراءة وكتابة

تطبيق Flutter بسيط لقراءة وكتابة وسوم **NFC / NDEF** (نص أو رابط) على **iOS** و**Android**،
مع بناء تلقائي على GitHub Actions ينتج ملف **IPA غير موقّع** جاهز للتثبيت على الآيفون بعد توقيعه بأي أداة توقيع.

## المزايا

- واجهة عربية (RTL) بسيطة: تبويب قراءة وتبويب كتابة.
- قراءة كل سجلات NDEF الموجودة على الوسم (نص، رابط، وسائط، بيانات خام).
- كتابة سجل نص (Text record) أو سجل رابط (URI record) على أي وسم NDEF قابل للكتابة.
- عرض تفاصيل الوسم: هل هو قابل للكتابة، سعته بالبايت، وحجم الرسالة المكتوبة.
- فحص تلقائي لتوفر NFC على الجهاز مع رسائل خطأ واضحة.

## تشغيل المشروع محليًا

```bash
flutter pub get
flutter run            # على جهاز حقيقي فقط، محاكي iOS لا يدعم NFC
```

بناء نسخة iOS بدون توقيع (على macOS):

```bash
flutter build ios --release --no-codesign
```

## تحميل ملف IPA من GitHub Actions

1. ادفع أي تعديل إلى فرع `main` أو شغّل الـ workflow يدويًا من تبويب **Actions** → **Build iOS IPA (unsigned)** → **Run workflow**.
2. بعد انتهاء البناء (حوالي 5–10 دقائق) نزّل الملف من أحد مكانين:
   - **Actions** → اختر آخر تشغيل → **Artifacts** → `NFC_READ_WRITE-unsigned-ipa`.
   - أو من صفحة **Releases** في المستودع: `NFC_READ_WRITE-unsigned.ipa`.
3. وقّع الملف وثبّته على الآيفون بإحدى الأدوات التالية: **Sideloadly**، **ESign**، **AltStore**، **TrollStore**.

الملف ينتج **بدون توقيع** (unsigned)، لذلك لن يُثبَّت مباشرة قبل توقيعه بحسابك.

## التثبيت على الآيفون

- **Sideloadly** (Windows/macOS): اسحب ملف IPA إلى النافذة، أدخل Apple ID، اضغط Start.
- **ESign / TrollStore**: افتح الملف واختر Sign / Install.
- بعد التوقيع يُثبَّت التطبيق كأي تطبيق عادي من الشاشة الرئيسية.

### ملاحظة مهمة عن NFC على iOS

قراءة وكتابة NFC على iOS تحتاج صلاحية `com.apple.developer.nfc.readersession.formats`
وهي **متاحة فقط لحسابات Apple Developer المدفوعة** (99$ سنويًا). عند التوقيع بحساب مجاني
(Sideloadly / Sideloadly مع Apple ID عادي أو AltStore) سيُثبَّت التطبيق ويعمل كواجهة،
لكن فحص NFC سيرجع «غير متاح» لأن النظام لا يمنح الصلاحية للتوقيع المجاني.
الصلاحية موجودة جاهزة في `ios/Runner/Runner.entitlements`، ويعمل NFC مباشرة إذا وقّعت
الملف ببروفايل يملك صلاحية NFC.

## بنية المشروع

```
lib/main.dart          واجهة التطبيق وإدارة جلسة NFC (nfc_manager / nfc_manager_ndef)
lib/ndef_codec.dart    ترميز وفك ترميز سجلات NDEF النصية والروابط
test/ndef_codec_test.dart
ios/Runner/Runner.entitlements   صلاحية NFC
ios/Runner/Info.plist            NFCReaderUsageDescription
.github/workflows/ios-unsigned-ipa.yml   بناء IPA غير موقّع
```

## الترخيص

استخدم المشروع كما تشاء.
