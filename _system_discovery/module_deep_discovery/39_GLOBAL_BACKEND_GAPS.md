# 39 — فجوات Backend الشاملة

> **المرجع:** `_system_discovery/BACKEND_GAPS_REPORT.md`.

## أ) الفجوات المصنَّفة

### 🟥 UI بلا Backend (UI_ONLY / MOCK_DATA)

| الشاشة | السبب |
|---|---|
| Integrations Marketplace (`#int_marketplace`) | لا Edge Function لكل مزوّد (R-11) |
| Integrations 12 مزوّد config forms | نفس |
| CC Call recording | لا PBX (R-12) |
| BI CASH_FLOW report | لا `rpc_name` (R-16) |
| بوابة الفرنشايزي | غير موجودة |
| Delivery driver mobile PWA | غير موجودة |

### 🟦 Backend بلا UI (BACKEND_ONLY)

| الوظيفة | التفصيل |
|---|---|
| `compute_vat_totals` | استخدام جزئي |
| `run_monthly_depreciation` | لا زر تشغيل |
| `close_fiscal_year` | لا شاشة اعتماد |
| `get_budget_vs_actual` | drill-down جزئي |
| `doc_expire_overdue` | لا Cron scheduler (R-15) |
| `dashboard_summary` RPC (perf-fix-1) | جاهز، الفرونت لم يُحدَّث |
| كل triggers auto-numbering | تعمل بذاتها بلا شاشة |
| Franchise → AR link | R-14 قرار المالك |
| Delivery cross-integration (Jahez/HungerStation) | webhooks جاهزة بلا workers |

### 🟨 مربوطة جزئيًا

راجع `BACKEND_GAPS_REPORT.md` لكل موديول (Menu, CRM, POS, HACCP, Procurement, Performance, Delivery, Documents, CC, BI, Integrations, Franchise) — قائمة تفصيلية.

## ب) الفجوات المتكررة

### ب-1) لا Cron / Scheduler
- `doc_expire_overdue` (R-15).
- `run_monthly_depreciation` (يدوي).
- `franchise_sales_report_monthly_reminder` (اقتراح).
- `int_events_retry_scheduler` (يدوي).
- `bi_snapshot_daily/weekly/monthly` (يدوي).

### ب-2) لا Edge Functions حقيقية
- 12 مزوّد Integrations.
- CC PBX/WhatsApp/SMS.
- Delivery platforms.
- Payment gateways.

### ب-3) لا Auth Bearer verification
- `/api/agent` `extraInstructions` (R-04).
- `/api/rewrite` (R-03).

### ب-4) جداول بلا SQL versioned (R-07)
- meetings, action_items, decisions, department_tasks
- maintenance_*, quality_*, cafe_*
- conversations, notifications, emergency_*
- users, role_permissions, ...

## ج) الأولوية

### 🔴 حرجة
1. R-01 password_plain.
2. R-02 RLS pattern.
3. R-03 CORS `*`.

### 🟠 عالية
4. R-04 extraInstructions.
5. R-05 Vault للـ secrets.
6. R-06 GEMINI_API_KEY.
7. R-07 SQL versioning.
8. R-08 crm/acct customers.

### 🟡 متوسطة
9. R-10 لا E2E tests.
10. R-11 Integrations workers.
11. R-12 CC PBX.
12. R-13 dashboard aggregation RPC.
13. R-14 Franchise → AR.
14. R-15 doc_expire cron.
15. R-16 BI CASH_FLOW.

### 🟢 منخفضة
16. R-18 → R-24 (cosmetic + minor).

## د) توصيات

1. **إنشاء `edge/` directory** في Vercel للـEdge Functions.
2. **إعداد GitHub Actions** لتشغيل SQL migrations منظمًا.
3. **إعداد pg_cron** أو Supabase scheduled functions.
4. **إضافة Bearer auth flow** لكل serverless endpoint.
5. **دمج Supabase Vault** للـ secrets.
6. **بدء E2E tests** بـ Playwright (POS + Meetings + Signup أولاً).
