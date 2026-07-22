# UI_UX_STRUCTURE_AUDIT — بنية الواجهة والتصميم

> اعتمد الاكتشاف على CSS + HTML في `index.html.html` + HANDOFF v121/v122/v123 desktop polish.

## 1) أنماط Hero (4 أنماط)
1. **`.mod-hero`** — بطاقة عنوان موحّدة للموديولات الحديثة (Wave 1-4). background primary + padding 32-36px (desktop). تحتوي `.mod-hero-badge` + KPIs.
2. **`.hr-emp-hero`** — variant للـ HR (ملف موظف). له `.hr-emp-hero-btn`.
3. **`.hero-card`** — النمط القديم في الشاشات الأصلية (meetings, tasks, decisions).
4. **`.task-page-header`** — نمط مبكر بلا bg، فقط h2 + subtitle + أزرار جانبية (يستخدم في meetings/tasks/decisions).

## 2) أنماط KPI (4 أنماط)
1. **`.kpi-card`** — الأصلي (لوحة التحكم، تقارير).
2. **`.kpi-value`** — القيمة الرقمية داخل kpi-card (32-36px على desktop v123).
3. **`.stat-card-premium`** — نمط جديد للـ Waves (dashboard modules).
4. **`.stat-card .value` + `.scp-value`** — variants داخل modules محددة.

## 3) الأنماط المتكررة عبر الشاشات
- **الجدول:** `.hr-emp-table` (HR) + الجداول العامة داخل `.panel`. hover states غير موحّدة (HR فقط له hover واضح بعد v123).
- **الفورمز:** `.form-input`, `.form-select`, `.form-field`, `.form-field.full`. max-width 640px على desktop.
- **البطاقات:** `.panel` + `.panel-header` + `.panel-body` + `.panel-title`.
- **الأزرار:** `.btn`, `.btn-outline`, `.btn-sm`, `.btn-danger`. min-height 38px على desktop.
- **الحوارات:** `.modal-overlay` + `.modal-box`.
- **البادجات:** `.pill-badge`, `.mod-hero-badge`, `.status-badge`.
- **Skeletons:** `.skeleton` + `.skeleton-row`.
- **التقويم:** `.cal-grid`, `.cal-cell`, `.cal-headrow`, `.cal-legend` — خاص بـ meetings calendar فقط.

## 4) Media queries
- **Mobile-first أساسًا** لكن ليس منتظمًا: بعض الشاشات القديمة تستخدم `@media (max-width: 768px)`.
- **v122-v123 نقلت التحسينات إلى `@media (min-width: 1024px)` و `@media (min-width: 1440px)`** — كل التحسينات الجديدة تعتمد min-width فقط.
- **الفوضى:** الاختلاط بين max-width (شاشات قديمة) و min-width (شاشات جديدة) يخلق تناقضات في breakpoints (768/1024/1440).

## 5) الفوضى في font-sizes (41 قيمة مختلفة)
تم رصد 41+ قيمة `font-size` حرفية (10px, 10.5px, 11px, 11.5px, 12px, 12.5px, 13px, 13.5px, 14px, 15px, 16px, 18px, 20px, 22px, 24px, 26px, 28px, 32px, 36px, ...) — بلا مقياس معتمد.

**تم إضافة سلّم `--fs-{xs,sm,base,md,lg,xl,2xl}` في v122** لكن الشاشات القديمة لم تُحدَّث لاستخدامها. **بند مؤجَّل صراحة في HANDOFF: "تطبيق --fs-* بدل الأرقام الحرفية — تجميلي بحت، مكلف بلا فائدة مرئية".**

## 6) 34+ قيمة `border-radius` حرفية
`4px, 6px, 8px, 10px, 12px, 14px, 16px, 18px, 20px, 22px, 24px, 28px, 32px, 50%, 999px, ...`
- v122 أدخلت `--radius-*` لكن الشاشات لم تستخدمه — **بند مؤجَّل صراحة**.

## 7) Content max-width (v122 fix)
- `--content-max: 1440px`.
- `--content-tight: 1120px`.
- `--content-narrow: 780px`.
- `.page-body > * { max-width: var(--content-max); margin-inline: auto; }` — إصلاح مركزي لسيطرة العرض على شاشات > 1440px.
- `.app-full-bleed` استثناء للـ hero / banners.

## 8) Design System v123 (شاشات مطبَّق عليها)
تحسينات desktop-only على:
- `.mod-hero`, `.hr-emp-hero`, `.hero-card` — padding + border-radius موحدة.
- `.mod-stat-val`, `.kpi-value`, `.stat-card .value` — 26 → 32 → 36px.
- `.hr-emp-table` — hover + sticky thead.
- `.form-input`, `.form-select` — max-width 640px.
- `.page-body` — padding 24 → 28 → 32px.
- `.btn` — min-height 38px.
- `.mt-hero-header h2/p` — أحجام أكبر على desktop.

**الشاشات التي لم تُطبَّق عليها v123 صراحة:**
- كل شاشات wave 2-4 التي تستخدم `.hero-card` أو `.task-page-header` القديم.
- بعض الفورمز خارج `.page-body`.
- Cafe / Cafe order status لا يزال بنمط قديم.

## 9) شاشات فارغة أو skeleton فقط
- POS Cashier: touch-optimized خاص — لا يتبع نفس النمط.
- Meetings Calendar: نمط خاص.
- AI Assistant: نمط شبيه بـ Chat.

## 10) نقاط UX ضعيفة موثقة
- **السايدبار طويل جدًا** (21 مجموعة، 15 منها بمفتاح واحد + "قريبًا"). يحتاج إعادة تجميع.
- **بادج "قريبًا" ثابت** بلا تلوين حالة (progress).
- **Breadcrumbs غير موجودة** بشكل موحد.
- **إشعارات UI:** dropdown في الشريط العلوي بلا شاشة "كل الإشعارات" واضحة.
- **بحث عام:** موجود لكن يعتمد على voice + text — لا فلاتر متقدمة.
- **RTL:** كامل، لكن بعض المكتبات الخارجية (lucide icons) بحاجة تعديل يدوي (`palm-tree` → `tree-palm`).
- **الرد على الشاشات الصغيرة (< 768px):** المجموعات القابلة للطي جيدة، لكن الجداول تتطلب scroll أفقي بلا "sticky column" في العرض الأول.
- **Loading states:** skeleton فقط في بعض الشاشات، والباقي "جاري التحميل...".
- **رسائل الخطأ:** غالبًا `error-msg show` مع رسالة Supabase الخام (غير مؤنسنة).

## 11) عناصر UI مكررة / متضاربة
- `.stat-card` مقابل `.stat-card-premium` مقابل `.kpi-card` — 3 أنماط لنفس الفكرة.
- `.mod-hero` مقابل `.hr-emp-hero` مقابل `.hero-card` — 3 أنماط hero.
- `.btn-outline` مقابل `.btn-sm btn-outline` — 4 حجم أزرار مختلفة.
- ألوان hardcoded (`#12372F`, `#245B4B`, `#D32F2F`, ...) في بعض شاشات (meetings calendar type colors).

## 12) توصيات (لا تُطبَّق الآن)
- توحيد `hero` و `KPI` بنمط واحد لكل موديول.
- تطبيق `--fs-*` و `--radius-*` على الشاشات القديمة.
- إعادة تجميع السايدبار (بدل 21 مجموعة → 6-8 مجموعات وظيفية).
- إضافة Breadcrumbs موحدة.
- توحيد رسائل الخطأ العربية.
