# 44 — جاهزية الموديولات للإطلاق (Release Readiness)

> **الغرض:** تقييم كل موديول من زاوية "هل يمكن إطلاقه للمستخدمين الحقيقيين اليوم؟".
> **المعايير:** UI complete + Backend hooked + Permissions + Workflow + Notifications + Tests + Docs.
> **التقدير النهائي بعد التحليل التفصيلي في الملفات 01-34.**

## أ) الجدول التفصيلي

| # | الموديول | UI | Backend | Perm | Workflow | Notif | Reports | Cross | Docs | Tests | Notes | جاهزية |
|---:|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|---|
| 01 | Users | 🟢 | 🟡 | 🔴 | 🟢 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | R-01/R-02 حرجة | ⚠️ SECURITY BLOCK |
| 02 | Branches | 🟡 | 🟡 | 🟢 | 🟢 | 🟡 | 🟡 | 🟢 | 🟢 | 🔴 | لا hub | 🟢 PILOT |
| 03 | Meetings | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | ✅ | ✅ READY |
| 04 | Action Items | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | تكرار مع 05 | ✅ READY |
| 05 | Dept Tasks | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🟡 | تكرار مع 04 | ✅ READY |
| 06 | Decisions | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | Ack ضعيف | ✅ READY |
| 07 | Chat | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | ✅ | ✅ READY |
| 08 | Emergency | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | لا SLA | ✅ READY |
| 09 | Maintenance | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | ✅ | ✅ READY |
| 10 | Quality | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | ✅ | ✅ READY |
| 11 | Cafe | 🟡 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | UI قديم | ✅ READY |
| 12 | Notifications | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | 🟢 | 🟢 | 🔴 | preferences | ✅ READY |
| 13 | My Profile | 🟢 | 🟡 | 🟢 | 🟡 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | ربط HR | 🟢 PILOT |
| 14 | Meeting Requests | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | 🟢 | 🟢 | 🔴 | ✅ | 🟢 PILOT |
| 15 | Vision | 🟡 | 🟡 | 🟢 | 🟡 | 🔴 | 🔴 | 🟡 | 🟢 | 🔴 | OKR ناقص | 🟢 PILOT |
| 16 | Voice Search | 🟢 | 🟡 | 🟢 | 🟡 | 🔴 | 🔴 | 🟢 | 🟢 | 🔴 | ✅ | 🟢 PILOT |
| 17 | AI Rewrite | 🟢 | 🟢 | 🔴 | 🟢 | 🔴 | 🔴 | 🟢 | 🟢 | 🔴 | R-03 | ⚠️ SECURITY |
| 18 | HR | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | ATS ناقص | 🟡 STABILIZE |
| 19 | Accounting | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | VAT phase2 | 🟡 STABILIZE |
| 20 | Operations | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | realtime | 🟡 STABILIZE |
| 21 | Payments | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | route جذر | 🟡 STABILIZE |
| 22 | AI Assistant | 🟢 | 🟡 | 🔴 | 🟡 | 🔴 | 🔴 | 🟢 | 🟢 | 🔴 | R-04 | ⚠️ SECURITY |
| 23 | POS | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | offline | 🟡 STABILIZE |
| 24 | Menu | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🟢 | 🟢 | 🔴 | BOM اختياري | 🟡 STABILIZE |
| 25 | CRM | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | R-08 | 🟡 STABILIZE |
| 26 | HACCP | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | 🔴 | certs تكرار | 🟡 STABILIZE |
| 27 | Procurement | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | multi-approval | 🟡 STABILIZE |
| 28 | Performance | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 | 🟢 | 🔴 | ربط KPI | 🟡 STABILIZE |
| 29 | Delivery | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | 🔴 | driver app | 🟡 STABILIZE |
| 30 | Documents | 🟢 | 🟡 | 🟢 | 🟢 | 🟡 | 🟢 | 🟢 | 🟢 | 🔴 | cron | 🟡 STABILIZE |
| 31 | Call Center | 🟢 | 🔴 | 🟢 | 🟡 | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | PBX | 🟠 BACKEND |
| 32 | BI | 🟢 | 🟡 | 🟢 | 🟢 | 🔴 | 🟢 | 🟢 | 🟢 | 🔴 | CASH_FLOW | 🟡 STABILIZE |
| 33 | Integrations | 🟡 | 🔴 | 🟢 | 🔴 | 🟡 | 🔴 | 🟢 | 🟢 | 🔴 | workers | 🟠 BACKEND |
| 34 | Franchise | 🟢 | 🟡 | 🟢 | 🟢 | 🟡 | 🟢 | 🟡 | 🟢 | 🔴 | AR link | 🟠 BACKEND |

**Legend:** 🟢 جيد | 🟡 مقبول لكن يحتاج | 🔴 غير جاهز

## ب) الملخص التنفيذي

| التصنيف | العدد | الموديولات |
|---|---:|---|
| ✅ READY | 10 | Meetings, Action Items, Dept Tasks, Decisions, Chat, Emergency, Maintenance, Quality, Cafe, Notifications |
| 🟢 PILOT | 5 | Branches, Profile, Meeting Requests, Vision, Voice Search |
| 🟡 STABILIZE | 12 | HR, Accounting, Operations, Payments, POS, Menu, CRM, HACCP, Procurement, Performance, Delivery, Documents, BI |
| 🟠 BACKEND MISSING | 3 | Call Center, Integrations, Franchise |
| ⚠️ SECURITY BLOCK | 3 | Users, AI Rewrite, AI Assistant |

## ج) خطة الإطلاق الموصى بها

### مرحلة 1 (فوري) — Security Fix
1. R-01 password_plain → Supabase Auth JWT.
2. R-02 RLS pattern → JWT-based.
3. R-03 CORS تقييد Origin.
4. R-04 Bearer flow لـ `/api/agent`.

### مرحلة 2 (بعد Security) — Pilot Extended
تفعيل الموديولات ✅ READY + 🟢 PILOT للمستخدمين الحقيقيين.

### مرحلة 3 — Stabilize Preview
معالجة الفجوات في الموديولات 🟡 STABILIZE + قرارات المالك (D1-D8).

### مرحلة 4 — Backend Workers
Integrations Edge Functions + CC PBX + Franchise portal.

### مرحلة 5 — E2E Tests
Playwright/Cypress لـ POS + Meetings + Signup + Payments.
