# 45 — المرجع النهائي لـ ChatGPT لإعادة هندسة موديولات شؤون الغذاء

> **الغرض:** هذا الملف مرجع نهائي واضح بالعربي. أعطه لـ ChatGPT ليكتب برومت إعادة هندسة شاملًا لكل موديول.
> **التغطية:** 34 موديول × 21 عنصر لكل موديول.
> **المرجعية:** كل التحليل التفصيلي في الملفات 00-44 في نفس المجلد.
> **الإطار:** المنصة عربية RTL كاملة، Supabase Postgres + Vercel Serverless + PWA. الاسم "شؤون الغذاء". نظام ERP لمطاعم سعودية متعددة الفروع.

---

## نظرة عامة للنظام (يجب لـ ChatGPT معرفتها)

- **الاسم:** شؤون الغذاء (Shouon Al-Ghithaa).
- **البنية:** ملف واحد `index.html.html` (43,320 سطر) + 17 SQL schema + Vercel functions.
- **قاعدة البيانات:** Supabase (Postgres + Auth + Storage + RLS).
- **اللغة:** واجهة عربية RTL، كود إنجليزي.
- **الأدوار:** 18 دور.
- **الموديولات:** 17 إنتاجي + 17 معاينة = 34.
- **الحالة:** كل موديولات المعاينة خلف feature flag `PREVIEW_MODULES` مفتوحة لـ `test_admin` فقط.
- **المخاطر الحرجة:** R-01 password_plain، R-02 RLS pattern، R-03 CORS `*`.

---

## قالب موديول (21 عنصر)

كل موديول أدناه يحتوي:
1. **الاسم العربي/الإنجليزي المقترح النهائي.**
2. **القسم المؤسسي (Group).**
3. **الغرض الاستراتيجي.**
4. **الكيان المركزي (Central Entity).**
5. **دورة العمل الكاملة (End-to-End Flow).**
6. **قائمة الصفحات/الشاشات المقترحة.**
7. **قائمة الجداول المقترحة (Data Model).**
8. **قائمة APIs الرئيسية.**
9. **قائمة الحالات والانتقالات (State Machine).**
10. **مصفوفة الصلاحيات (Roles × Actions).**
11. **الإشعارات والتنبيهات المطلوبة.**
12. **التقارير والمؤشرات (KPIs).**
13. **العلاقات مع الموديولات الأخرى.**
14. **المخاطر التقنية والأمنية.**
15. **القرارات المطلوبة من صاحب المشروع.**
16. **متطلبات UI/UX (Design System).**
17. **متطلبات Mobile/PWA.**
18. **متطلبات Testing (E2E).**
19. **متطلبات Compliance & Regulations.**
20. **Cross-module Integrations (AI, BI, Documents).**
21. **Roadmap Phase 1/2/3.**

---

# القسم الأول: الموديولات الإنتاجية (17)

## 01 — إدارة المستخدمين والوصول (IAM)

1. **الاسم:** إدارة المستخدمين والوصول (IAM — Identity & Access Management).
2. **القسم:** الحوكمة والأمن.
3. **الغرض:** أساس الهوية والوصول لكل النظام. مبدأ Least Privilege.
4. **الكيان:** `iam_users` (بعد إزالة `password_plain`).
5. **الدورة:** signup_request → HR review → admin approve → welcome → login → daily use (RLS) → role changes (audit) → termination (soft delete).
6. **الصفحات:** `#iam` (dashboard), `#iam_users`, `#iam_roles`, `#iam_overrides`, `#iam_sessions`, `#iam_audit`, `#iam_signup_queue`, `#iam_password_policy`, `#iam_sso`.
7. **الجداول:** `iam_users` (بدون password_plain)، `iam_role_matrix`، `iam_sessions`، `iam_password_history`، `iam_permission_overrides`، `iam_audit_log`، `iam_signup_requests`، `iam_password_policy`.
8. **APIs:** `iam_force_logout(user_id)`, `iam_grant_temporary_permission`, `iam_reset_password_via_email`, `iam_bulk_deactivate`.
9. **الحالات:** signup: `pending → approved / rejected`. session: `active → expired / terminated`. user: `active → suspended → terminated`.
10. **الصلاحيات:** admin/CM = كل شيء. HR = view + limited edit. Employee = self only.
11. **الإشعارات:** signup approval/rejection, force logout, password change, permission override.
12. **KPIs:** active users، failed logins، avg time to onboard، permission overrides count.
13. **العلاقات:** يخدم كل موديول (RLS `current_user_id()`).
14. **المخاطر:** R-01، R-02.
15. **قرارات:** D3 (Supabase Auth JWT)، سياسة password، 18 دور أم دمج.
16. **UI:** hero موحد `.mod-hero` + KPI stripe.
17. **Mobile:** priority على `#my_profile` self-service.
18. **Tests:** E2E signup + login + logout + force logout.
19. **Compliance:** حماية البيانات السعودية (PDPL)، GDPR-like retention.
20. **Cross-module:** AI hook "من دخل آخر 24 ساعة"، BI dashboard.
21. **Roadmap:** P1: R-01 + R-02. P2: Audit UI + reports. P3: SSO + WhatsApp OTP.

## 02 — إدارة الفروع والأقسام

1. **الاسم:** إدارة الفروع والأقسام (Organizational Setup).
2. **القسم:** الحوكمة والبنية.
3. **الغرض:** التنظيم المؤسسي — كل موظف/سجل/حركة مربوطة بفرع/قسم.
4. **الكيان:** `branches`.
5. **الدورة:** جدوى → تراخيص → إنشاء تقني → موظفين + معدات → افتتاح → تشغيل → مراجعات → إغلاق (soft).
6. **الصفحات:** `#branches` (dashboard + KPI)، `#branch/:id`، `#branches_map`، `#departments`، `#branch_assets`، `#branch_hours`، `#branch_licenses`.
7. **الجداول:** `branches` (توسع)، `departments` (توحيد مع `hr_departments`)، `assets` (توحيد `branch_assets` + maintenance_equipment)، `branch_licenses`.
8. **APIs:** `branch_deactivate`, `branch_transfer_assets`, `branch_setup_cost_center`.
9. **الحالات:** `active → paused → closed`.
10. **الصلاحيات:** admin/CM = full. branch_manager = own. ops_manager = all read.
11. **الإشعارات:** رخصة تنتهي، تغيير مدير.
12. **KPIs:** revenue/branch, complaints/branch, turnover/branch.
13. **العلاقات:** يخدم كل الموديولات (`branch_id`).
14. **المخاطر:** R-07 (schemas)، `SET NULL` عند حذف فرع.
15. **قرارات:** D9 (توحيد departments)، D10 (توحيد assets).
16. **UI:** خريطة + بطاقات + hero موحد.
17. **Mobile:** بطاقة فرع مضغوطة.
18. **Tests:** E2E فتح فرع + نقل موظف.
19. **Compliance:** خزن التراخيص كمستندات، ربط بلدية.
20. **Cross-module:** ربط قوي مع Maintenance، Ops، HR، Franchise (`franchise_branches`).
21. **Roadmap:** P1: hub + توحيد. P2: خرائط + IoT. P3: analytics.

## 03 — الاجتماعات والحوكمة

1. **الاسم:** الاجتماعات والحوكمة (Meetings & Governance).
2. **القسم:** التنفيذ والمتابعة.
3. **الغرض:** توثيق كامل + محاسبة على المخرجات.
4. **الكيان:** `meetings`.
5. **الدورة:** create → invite + RSVP → reminders → agenda → minutes autosave → action_items + decisions → distribution → close after execution.
6. **الصفحات:** `#meetings`, `#meeting/:id` (unified detail), `#meeting_templates`, `#meeting_calendar`, `#meeting_analytics`, `#meeting_archive`.
7. **الجداول:** `meetings` (versioned SQL) + `meeting_attendees` + `meeting_agenda` + `meeting_recordings` + `meeting_transcripts`.
8. **APIs:** `meeting_from_template`, `meeting_convert_action_to_task`, `meeting_auto_close`.
9. **الحالات:** `scheduled → in_progress → completed → in_follow_up → closed / cancelled / postponed`.
10. **الصلاحيات:** organizer + invited + role-based visibility.
11. **الإشعارات:** 24h/1h/15m قبل + upon change.
12. **KPIs:** attendance rate، execution rate، cycle time.
13. **العلاقات:** action_items + decisions + department_tasks (conversion).
14. **المخاطر:** R-07، تداخل مع meeting_tasks.
15. **قرارات:** D4 (Action Items merge)، PDF محضر إلزامي.
16. **UI:** unified hero + KPI + calendar.
17. **Mobile:** notes + push.
18. **Tests:** create → attend → minute → action → close.
19. **Compliance:** archive 10+ سنوات.
20. **Cross-module:** Vision (اجتماع يعالج هدف)، AI transcription، BI health.
21. **Roadmap:** P1: dump schema + توحيد. P2: AI transcription + templates. P3: voting + analytics.

## 04 — المخرجات والالتزامات

1. **الاسم:** المخرجات والالتزامات (Meeting Commitments).
2. **القسم:** التنفيذ والمتابعة.
3. **الغرض:** كل ما اتفق عليه في اجتماع له مسؤول وموعد ودليل.
4. **الكيان:** `action_items` (أو مدموج في `department_tasks`).
5. **الدورة:** create in meeting → assign → notification → in_progress → evidence → review → completed.
6. **الصفحات:** `#action_items`, `#action_item/:id`, `#action_items_overdue`, `#action_items_by_meeting`.
7. **الجداول:** `action_items` (versioned) + `action_item_evidence`.
8. **APIs:** `action_convert_to_task`, `action_reassign`, `action_close_with_evidence`.
9. **الحالات:** `open → in_progress → completed / cancelled` (+ overdue).
10. **الصلاحيات:** assigner + assignee + meeting attendees.
11. **الإشعارات:** assignment، due soon، overdue، escalation.
12. **KPIs:** ratio in-time، avg cycle time، backlog.
13. **العلاقات:** meetings + tasks + notifications.
14. **المخاطر:** التداخل مع department_tasks.
15. **قرارات:** D4 (دمج أم توضيح).
16. **UI:** kanban + hero.
17. **Mobile:** priority.
18. **Tests:** create → assign → close.
19. **Compliance:** archive.
20. **Cross-module:** AI "مخرجاتي المتأخرة"، BI.
21. **Roadmap:** P1: تسمية + dump. P2: convert to task. P3: analytics.

## 05 — التكاليف والمشاريع الداخلية

1. **الاسم:** التكاليف والمشاريع الداخلية (Internal Assignments & Projects).
2. **القسم:** التنفيذ والمتابعة.
3. **الغرض:** تكاليف مباشرة بلا اجتماع + مشاريع طويلة الأمد.
4. **الكيان:** `department_tasks`.
5. **الدورة:** assign → notification → negotiate → in_progress → review → completed with approval.
6. **الصفحات:** `#tasks_hub`, `#task/:id`, `#projects`, `#project/:id`, `#tasks_kanban`, `#tasks_analytics`.
7. **الجداول:** توسع + `task_dependencies` + `task_watchers` + `task_time_tracking`.
8. **APIs:** `task_from_meeting_action`, `task_bulk_reassign`, `task_workload_by_user`.
9. **الحالات:** `new → in_progress → review → completed / cancelled`.
10. **الصلاحيات:** manager assign + assignee execute + watchers see.
11. **الإشعارات:** assign، due، comment.
12. **KPIs:** cycle time، workload، backlog.
13. **العلاقات:** action_items convert + notifications + chat.
14. **المخاطر:** التداخل.
15. **قرارات:** D4.
16. **UI:** kanban + hero موحد.
17. **Mobile:** priority.
18. **Tests:** create → assign → close.
19. **Compliance:** retention.
20. **Cross-module:** AI + BI + voice input.
21. **Roadmap:** P1: dump + تسمية. P2: subtasks + dependencies. P3: AI workload balancing.

## 06 — القرارات المؤسسية

1. **الاسم:** القرارات المؤسسية (Corporate Decisions).
2. **القسم:** التنفيذ والمتابعة.
3. **الغرض:** توثيق كل قرار كسبب + مسؤول + موعد + دليل + تصويت.
4. **الكيان:** `decisions`.
5. **الدورة:** need → study → decide (رسمي) → announce → execute → periodic reports → executed with evidence → assessment.
6. **الصفحات:** `#decisions`, `#decision/:id`, `#decisions_archive`, `#decisions_analytics`.
7. **الجداول:** `decisions` (versioned) + `decision_versions` (supersede).
8. **APIs:** `decision_execute_with_evidence`, `decision_supersede`.
9. **الحالات:** `draft → active → executed / cancelled`.
10. **الصلاحيات:** decision-maker + responsible + viewers.
11. **الإشعارات:** issued، due، escalation.
12. **KPIs:** execution rate، time to execute.
13. **العلاقات:** meetings + tasks + notifications.
14. **المخاطر:** acknowledgment ضعيف.
15. **قرارات:** دليل تنفيذ إلزامي.
16. **UI:** hero + timeline.
17. **Mobile:** read-only priority.
18. **Tests:** issue → execute → close.
19. **Compliance:** signatures (DocuSign integration).
20. **Cross-module:** documents (كل قرار = مستند)، AI.
21. **Roadmap:** P1: dump + evidence. P2: signatures + AI. P3: analytics.

## 07 — التواصل والتعاون الداخلي

1. **الاسم:** التواصل والتعاون (Internal Chat & Collaboration).
2. **القسم:** التواصل.
3. **الغرض:** تواصل مؤسسي محفوظ يستبدل واتساب.
4. **الكيان:** `conversations`.
5. **الدورة:** create thread → exchange → search → archive.
6. **الصفحات:** `#chat_hub`, `#thread/:id`, `#channels`, `#dms`, `#chat_search`.
7. **الجداول:** dump + `chat_reactions` + `chat_pinned` + `chat_polls`.
8. **APIs:** `chat_search`, `chat_pin`, `chat_poll_create`.
9. **الحالات:** message: `sent → read → edited / deleted`.
10. **الصلاحيات:** members-based.
11. **الإشعارات:** new message، mention، unread priority.
12. **KPIs:** engagement، response time.
13. **العلاقات:** meetings + tasks (chat خاص).
14. **المخاطر:** R-07.
15. **قرارات:** encryption at rest.
16. **UI:** WhatsApp-like.
17. **Mobile:** priority عالي.
18. **Tests:** send/receive/search.
19. **Compliance:** retention 3+ سنوات.
20. **Cross-module:** WhatsApp Business integration.
21. **Roadmap:** P1: presence + dump. P2: threading + polls. P3: AI summarization.

## 08 — إدارة الطوارئ والاستجابة

1. **الاسم:** إدارة الطوارئ والاستجابة (Incident Response).
2. **القسم:** الأمن التشغيلي.
3. **الغرض:** بلاغ + بث + استجابة سريعة.
4. **الكيان:** `emergency_alerts`.
5. **الدورة:** incident → broadcast → acknowledge → coordinate → resolve → report.
6. **الصفحات:** `#emergency`, `#emergency/:id`, `#emergency_playbooks`, `#emergency_drills`.
7. **الجداول:** dump + `emergency_playbooks` + `emergency_response_log`.
8. **APIs:** `emergency_broadcast`, `emergency_escalate`, `emergency_close_with_report`.
9. **الحالات:** `active → resolved` + SLA زمني.
10. **الصلاحيات:** managers send + all receive by scope.
11. **الإشعارات:** SMS + WhatsApp + Push + Email.
12. **KPIs:** response time p95، false positive.
13. **العلاقات:** HACCP + Maintenance + CRM.
14. **المخاطر:** SLA غير مفروض.
15. **قرارات:** ربط تلقائي مع HACCP.
16. **UI:** hero أحمر.
17. **Mobile:** بصوت خاص.
18. **Tests:** broadcast → acknowledge.
19. **Compliance:** archive 5+ سنوات.
20. **Cross-module:** Twilio SMS.
21. **Roadmap:** P1: SLA + playbooks. P2: Twilio + drills. P3: AI triage.

## 09 — إدارة الأصول والصيانة (EAM)

1. **الاسم:** إدارة الأصول والصيانة (EAM — Enterprise Asset Management).
2. **القسم:** العمليات والصيانة.
3. **الغرض:** كل الأصول + أعطال + وقائية + موردين + اعتمادات + تكلفة.
4. **الكيان:** `assets` (توحيد `branch_assets` + `maintenance_equipment` + `maintenance_assets`).
5. **الدورة:** report → assign → parts/quote → repair → close → cost booking (AP auto).
6. **الصفحات:** `#eam`, `#eam/tickets`, `#eam/preventive`, `#eam/vendors`, `#eam/assets`, `#eam/costs`, `#eam/reports`.
7. **الجداول:** توحيد أصول + `maintenance_requests` + `maintenance_repairs` + `maintenance_preventive_schedule` + `maintenance_quotes` + `maintenance_finance_approvals`.
8. **APIs:** `maintenance_auto_bill`, `preventive_generate_next`, `asset_lifecycle_transition`.
9. **الحالات:** `open → assigned → in_progress → awaiting_parts / awaiting_quote → completed → closed / rejected`.
10. **الصلاحيات:** maintenance_officer + branch_manager + finance approval.
11. **الإشعارات:** assignment، preventive due، budget breach.
12. **KPIs:** MTBF، MTTR، cost/asset.
13. **العلاقات:** Accounting AP، Procurement (spare parts).
14. **المخاطر:** 4 مسارات متكررة.
15. **قرارات:** D10 توحيد الأصول، ربط تلقائي AP.
16. **UI:** hero + timeline + kanban.
17. **Mobile:** priority.
18. **Tests:** report → close.
19. **Compliance:** HACCP معدات.
20. **Cross-module:** IoT sensors.
21. **Roadmap:** P1: توحيد. P2: AP auto + AI. P3: IoT.

## 10 — الجودة والامتثال

1. **الاسم:** الجودة والامتثال (Quality & Compliance).
2. **القسم:** الجودة والسلامة.
3. **الغرض:** زيارات جودة + تقييم + خطط تصحيحية.
4. **الكيان:** `quality_visits`.
5. **الدورة:** schedule → visit → score → action plan → close.
6. **الصفحات:** `#quality`, `#visit/:id`, `#quality_templates`, `#quality_analytics`, `#quality_action_plans`.
7. **الجداول:** dump + `quality_action_plans`.
8. **APIs:** `quality_generate_action_plan`, `quality_score_branch`.
9. **الحالات:** visit: `draft → submitted → approved`.
10. **الصلاحيات:** quality_manager + branch scope.
11. **الإشعارات:** breach، zone review due.
12. **KPIs:** avg score، branch ranking.
13. **العلاقات:** Performance (KPI فرع)، Action Items تلقائي.
14. **المخاطر:** تداخل مع HACCP.
15. **قرارات:** توحيد مع HACCP؟
16. **UI:** hero + score dial.
17. **Mobile:** priority (field).
18. **Tests:** visit → score → plan.
19. **Compliance:** SASO/ISO templates.
20. **Cross-module:** AI image recognition.
21. **Roadmap:** P1: action plans. P2: AI image. P3: cross-standard mapping.

## 11 — طلبات الكافيه الداخلية

1. **الاسم:** طلبات الكافيه (Internal F&B Corner).
2. **القسم:** التشغيل.
3. **الغرض:** ركن كافيه داخلي للموظفين + زوار.
4. **الكيان:** `cafe_orders`.
5. **الدورة:** order → preparing → ready → delivered → invoice + GL.
6. **الصفحات:** `#cafe`, `#cafe_menu`, `#cafe_orders`, `#cafe_reports`.
7. **الجداول:** dump + توسع multi-branch.
8. **APIs:** `cafe_link_to_pos` (اختياري).
9. **الحالات:** `pending → preparing → ready → delivered / cancelled`.
10. **الصلاحيات:** الجميع طلب، ops_manager إعداد.
11. **الإشعارات:** ready.
12. **KPIs:** revenue، popular items، prep time.
13. **العلاقات:** Accounting (invoice).
14. **المخاطر:** تكرار مع POS.
15. **قرارات:** دمج مع POS؟
16. **UI:** v123 refresh.
17. **Mobile:** priority.
18. **Tests:** order → deliver.
19. **Compliance:** —
20. **Cross-module:** CRM loyalty (اقتراح).
21. **Roadmap:** P1: UI refresh. P2: loyalty. P3: dine-in app.

## 12 — مركز الإشعارات

1. **الاسم:** مركز الإشعارات (Notification Center).
2. **القسم:** التواصل.
3. **الغرض:** مركز موحد لكل الإشعارات + preferences.
4. **الكيان:** `notifications`.
5. **الدورة:** trigger → deliver (multi-channel) → read → archive.
6. **الصفحات:** `#notifications`, `#notification_settings`.
7. **الجداول:** dump + `notification_channels_prefs`.
8. **APIs:** `notification_mark_all_read`, `notification_bulk_delete`.
9. **الحالات:** `is_read` boolean.
10. **الصلاحيات:** self.
11. **الإشعارات:** email + push + WhatsApp + SMS.
12. **KPIs:** delivery rate، read rate.
13. **العلاقات:** كل موديول.
14. **المخاطر:** R-07.
15. **قرارات:** أولوية القنوات.
16. **UI:** inbox unified.
17. **Mobile:** priority.
18. **Tests:** trigger → read.
19. **Compliance:** —
20. **Cross-module:** Twilio + WhatsApp.
21. **Roadmap:** P1: preferences + digest. P2: WhatsApp/SMS. P3: AI priority.

## 13 — ملفي الشخصي (My Hub)

1. **الاسم:** ملفي (My Hub).
2. **القسم:** الشخصي.
3. **الغرض:** لوحة شخصية بكل ما يخص الموظف.
4. **الكيان:** `users` + `hr_employee_profile`.
5. **الدورة:** open → view + self-update → drill-in.
6. **الصفحات:** `#me`, `#me/tasks`, `#me/meetings`, `#me/documents`, `#me/settings`, `#me/security`.
7. **الجداول:** لا حاجة جديدة.
8. **APIs:** aggregate واحد بدل 4 استعلامات.
9. **الحالات:** —
10. **الصلاحيات:** self.
11. **الإشعارات:** ملخصات يومية.
12. **KPIs:** engagement.
13. **العلاقات:** كل موديول.
14. **المخاطر:** تكرار مع HR profile.
15. **قرارات:** توحيد مع HR employee.
16. **UI:** `.mod-hero`.
17. **Mobile:** priority.
18. **Tests:** self-view.
19. **Compliance:** privacy.
20. **Cross-module:** Google Calendar sync، AI "لخّص يومي".
21. **Roadmap:** P1: hero + RPC. P2: HR profile ربط. P3: AI daily brief.

## 14 — طلبات وتحضير الاجتماعات

1. **الاسم:** طلبات الاجتماعات (Meeting Requests & Preparation).
2. **القسم:** التنفيذ.
3. **الغرض:** تدفق طلب + تقرير تحضيري + تحويل لاجتماع.
4. **الكيان:** `meeting_requests`.
5. **الدورة:** request → preparation report → approval → convert to meeting.
6. **الصفحات:** `#meeting_request`, `#request/:id`, `#preparation_reports`, `#request_analytics`.
7. **الجداول:** dump.
8. **APIs:** `mr_convert_to_meeting`, `mr_reject_with_reason`.
9. **الحالات:** يحتاج تحقق.
10. **الصلاحيات:** الجميع submit، managers approve.
11. **الإشعارات:** submission، approval.
12. **KPIs:** approval rate.
13. **العلاقات:** Meetings.
14. **المخاطر:** —
15. **قرارات:** دمج مع Meetings كتبويب؟
16. **UI:** v123.
17. **Mobile:** —
18. **Tests:** request → convert.
19. **Compliance:** —
20. **Cross-module:** AI generation.
21. **Roadmap:** P1: توحيد UI. P2: AI. P3: analytics.

## 15 — الأهداف الاستراتيجية (OKR)

1. **الاسم:** الأهداف الاستراتيجية (OKR / Vision & Goals).
2. **القسم:** الاستراتيجية.
3. **الغرض:** cascading OKR من الشركة إلى الفرد.
4. **الكيان:** `okr_objectives`.
5. **الدورة:** define quarterly → cascade → track → review → assess.
6. **الصفحات:** `#vision`, `#okrs`, `#okr/:id`, `#okr_by_dept`, `#okr_progress`.
7. **الجداول:** توسع كامل: `okr_objectives`, `okr_key_results`, `okr_quarterly_reviews`, `strategic_themes`.
8. **APIs:** `okr_progress_rollup`, `okr_align_with_kpi`.
9. **الحالات:** `active → completed / cancelled`.
10. **الصلاحيات:** dept-based.
11. **الإشعارات:** ربع سنوي review.
12. **KPIs:** progress %، alignment score.
13. **العلاقات:** Performance، Meetings.
14. **المخاطر:** OKR ناقص حاليًا.
15. **قرارات:** تبني OKR كامل؟
16. **UI:** hero + tree.
17. **Mobile:** —
18. **Tests:** create → track → review.
19. **Compliance:** —
20. **Cross-module:** AI SMART generation.
21. **Roadmap:** P1: OKR base. P2: cascading. P3: AI + BI.

## 16 — المساعد الصوتي الشامل

1. **الاسم:** المساعد الصوتي والبحث (Voice & Search).
2. **القسم:** الذكاء.
3. **الغرض:** بحث موحد + أوامر صوتية.
4. **الكيان:** search index + voice interface.
5. **الدورة:** mic → transcript → intent → action.
6. **الصفحات:** `#search`, `#voice_commands`.
7. **الجداول:** search log (اختياري).
8. **APIs:** بحث موحّد + intent classification.
9. **الحالات:** —
10. **الصلاحيات:** الجميع (RLS).
11. **الإشعارات:** —
12. **KPIs:** search success rate.
13. **العلاقات:** كل موديول.
14. **المخاطر:** —
15. **قرارات:** توحيد مع AI Assistant.
16. **UI:** —
17. **Mobile:** —
18. **Tests:** search + voice.
19. **Compliance:** —
20. **Cross-module:** AI Assistant.
21. **Roadmap:** P1: LLM intent. P2: advanced filters. P3: proactive.

## 17 — توليد وصياغة النصوص (Text Assistant)

1. **الاسم:** توليد وصياغة النصوص (Text Assistant).
2. **القسم:** الذكاء.
3. **الغرض:** rewrite / translate / summarize.
4. **الكيان:** `/api/ai/*` endpoints.
5. **الدورة:** raw → send → LLM → return.
6. **الصفحات:** integrated buttons.
7. **الجداول:** لا storage.
8. **APIs:** `/api/rewrite`, `/api/translate`, `/api/summarize`.
9. **الحالات:** —
10. **الصلاحيات:** Bearer token.
11. **الإشعارات:** —
12. **KPIs:** usage per user.
13. **العلاقات:** كل النصوص الطويلة.
14. **المخاطر:** R-03 (CORS).
15. **قرارات:** تقييد Origin + Bearer.
16. **UI:** inline.
17. **Mobile:** —
18. **Tests:** call + verify.
19. **Compliance:** لا تسريب.
20. **Cross-module:** كل موديول.
21. **Roadmap:** P1: R-03 fix. P2: توسيع. P3: مزوّدون متعددون.

---

# القسم الثاني: موديولات المعاينة (17)

## 18 — الموارد البشرية الشاملة (HRIS)

1. **الاسم:** HRIS (Human Resource Information System).
2. **القسم:** الإدارة المؤسسية.
3. **الغرض:** كل ما يخص الموظف — من التوظيف إلى المغادرة.
4. **الكيان:** `hr_employee_profile`.
5. **الدورة:** ATS recruit → onboard → attendance daily → leaves + payroll monthly → performance quarterly → contracts renewal → offboard.
6. **الصفحات:** كل الحالية + `#hr_recruitment` (ATS), `#hr_contracts`, `#hr_training`, `#hr_kpi_link`, `#hr_disciplinary`, `#hr_offboarding`, `#hr_reports`, `#hr_assets` (عهد).
7. **الجداول:** `hr_job_openings`, `hr_candidates`, `hr_applications`, `hr_contracts`, `hr_training_records`, `hr_disciplinary`, `hr_exit_interviews`, `hr_assigned_equipment`.
8. **APIs:** `hr_calculate_gratuity`, `hr_generate_contract`, `hr_link_kpi_to_perf`.
9. **الحالات:** attendance 7، leaves 5، payroll 3، contract lifecycle.
10. **الصلاحيات:** hr_manager + payroll_officer + admin + department_manager approve.
11. **الإشعارات:** contract expiry، birthday، work anniversary.
12. **KPIs:** absenteeism، turnover، cost per hire.
13. **العلاقات:** Users، Accounting (payroll)، Performance، Documents، HACCP certs.
14. **المخاطر:** تكرار departments، شهادات.
15. **قرارات:** D9 توحيد، الانتقال لـ `users` أم إبقاء 1:1.
16. **UI:** hero موحد + tabs.
17. **Mobile:** self-service.
18. **Tests:** onboard → payroll → offboard.
19. **Compliance:** نظام العمل السعودي + GOSI.
20. **Cross-module:** Mudad integration، AI recruiting.
21. **Roadmap:** P1: توحيد + ATS. P2: contracts + training. P3: Mudad + AI.

## 19 — الحسابات والمالية (Financial ERP)

1. **الاسم:** الحسابات والمالية (Financial ERP).
2. **القسم:** المالية.
3. **الغرض:** GL كامل + AR/AP + Treasury + Fixed Assets + Inventory + VAT + Closing + Budgets.
4. **الكيان:** `acct_journal_entries`.
5. **الدورة:** transactional posting (auto من modules أخرى) → approval → paid/settled → period close → year close.
6. **الصفحات:** كل الحالية + `#acct_dashboard_finance`, `#acct_close_period_ui`, `#acct_depreciation_run`, `#acct_zatca_phase2`, `#acct_reconciliation`.
7. **الجداول:** 30 حالية + توحيد `acct_customers` مع `crm_customers`.
8. **APIs:** `acct_auto_reconcile_bank`, `acct_zatca_phase2_sign`.
9. **الحالات:** journal 2، bill 5، payment 4، invoice 5 + ZATCA 4، period 3، asset 2.
10. **الصلاحيات:** finance_manager + gl_accountant + ap_officer + ar_officer + approval matrix.
11. **الإشعارات:** approval requests.
12. **KPIs:** DSO، DPO، cash cycle، gross margin.
13. **العلاقات:** كل modules التشغيلية.
14. **المخاطر:** VAT Phase 2 mock، R-08.
15. **قرارات:** D1 (Franchise AR)، D2 (Customers).
16. **UI:** v123.
17. **Mobile:** approval fast.
18. **Tests:** post → approve → pay.
19. **Compliance:** SOCPA + ZATCA + IFRS.
20. **Cross-module:** SADAD، Mada، ZATCA Phase 2.
21. **Roadmap:** P1: UI للـ RPCs. P2: ZATCA Phase 2. P3: multi-currency + AI anomaly.

## 20 — تشغيل المطاعم

1. **الاسم:** تشغيل المطاعم (Restaurant Ops).
2. **القسم:** التشغيل.
3. **الغرض:** ورديات + قوائم فتح/إغلاق + خطط تحضير + مخزون فرع + هدر + مشكلات.
4. **الكيان:** `ops_shifts`.
5. **الدورة:** open shift → checklists → prep plans → orders + POS + Delivery → waste + issues → close shift + handover.
6. **الصفحات:** كل الحالية + `#ops_kitchen_display` (KDS)، `#ops_realtime_dashboard`.
7. **الجداول:** 17 + توسع station-level.
8. **APIs:** `ops_start_shift`, `ops_close_shift_with_handover`, دوال real-time.
9. **الحالات:** shift 3، order 3، others.
10. **الصلاحيات:** operations_manager + branch_manager + employee.
11. **الإشعارات:** issue escalation.
12. **KPIs:** avg ticket time، waste %، prep accuracy.
13. **العلاقات:** POS، Menu، HACCP، Accounting.
14. **المخاطر:** لا real-time.
15. **قرارات:** KDS timing.
16. **UI:** priority للـmobile.
17. **Mobile:** priority عالي.
18. **Tests:** shift lifecycle.
19. **Compliance:** HACCP.
20. **Cross-module:** POS realtime، Menu recipe changes.
21. **Roadmap:** P1: POS realtime. P2: KDS. P3: AI forecasting.

## 21 — المدفوعات والتسويات

1. **الاسم:** المدفوعات والتسويات (Financial Partners).
2. **القسم:** المالية.
3. **الغرض:** شركاء ماليون (Jahez/HungerStation/Mada/STC) + عقود + كشوف + مقاصة.
4. **الكيان:** `pay_partners`.
5. **الدورة:** partner → contract → statement monthly → clearing batch → payout.
6. **الصفحات:** فصل route جذر `#payments` + `#pay_partners` + `#pay_statements` + `#pay_clearing`.
7. **الجداول:** 7 + توسع multi-currency.
8. **APIs:** `pay_auto_generate_statements`, `pay_reconcile_bank`.
9. **الحالات:** statement 3، batch 3، payout 3.
10. **الصلاحيات:** finance_manager + ap_officer + approval matrix.
11. **الإشعارات:** approval requests.
12. **KPIs:** collection cycle.
13. **العلاقات:** POS + Delivery aggregation.
14. **المخاطر:** —
15. **قرارات:** فصل من Accounting؟
16. **UI:** dashboard مستقل.
17. **Mobile:** approval.
18. **Tests:** statement → clearing → payout.
19. **Compliance:** —
20. **Cross-module:** Jahez/HungerStation/Mada APIs.
21. **Roadmap:** P1: فصل UI. P2: integrations APIs. P3: auto-reconcile.

## 22 — المساعد الذكي المؤسسي

1. **الاسم:** المساعد الذكي (Enterprise AI Agent).
2. **القسم:** الذكاء.
3. **الغرض:** أدوات قراءة (7 حاليًا → 30+) + writes بحرص.
4. **الكيان:** `ai_sessions`.
5. **الدورة:** user → LLM → tool call → RLS-checked execution → result → LLM → answer.
6. **الصفحات:** `#ai_assistant`, `#ai_history`, `#ai_settings`, `#ai_tools_catalog`, `#ai_audit`.
7. **الجداول:** 4 + توسع audit.
8. **APIs:** `/api/agent` مع Bearer flow.
9. **الحالات:** session lifecycle.
10. **الصلاحيات:** Bearer token verification.
11. **الإشعارات:** —
12. **KPIs:** tool success rate.
13. **العلاقات:** كل موديول (30+ أدوات).
14. **المخاطر:** R-04.
15. **قرارات:** توسع لـ writes؟
16. **UI:** chat UI.
17. **Mobile:** priority.
18. **Tests:** each tool.
19. **Compliance:** لا تسريب.
20. **Cross-module:** كل موديول له 2-3 أدوات.
21. **Roadmap:** P1: R-04 + توسع أدوات. P2: writes. P3: proactive.

## 23 — نقاط البيع (POS 2.0)

1. **الاسم:** نقاط البيع (POS 2.0).
2. **القسم:** المبيعات.
3. **الغرض:** كاشير كامل + offline + printer + drawer + ZATCA Phase 2.
4. **الكيان:** `pos_transactions`.
5. **الدورة:** open session → transaction draft → payment splits → build QR → complete_transaction (RPC) → journal + loyalty → close session.
6. **الصفحات:** كل الحالية + `#pos_offline_queue`, `#pos_daily_report`, `#pos_kds_link`.
7. **الجداول:** 5 + `pos_offline_queue` + `pos_receipt_templates`.
8. **APIs:** `pos_sync_offline_batch`, `pos_open_drawer`, `pos_print_receipt`.
9. **الحالات:** session 2، transaction 4، type 3.
10. **الصلاحيات:** cashier + branch + ops_manager oversight.
11. **الإشعارات:** end-of-day.
12. **KPIs:** avg ticket، TPS.
13. **العلاقات:** Menu، CRM، Accounting، Delivery.
14. **المخاطر:** لا offline.
15. **قرارات:** offline priority.
16. **UI:** touch optimization.
17. **Mobile:** iPad/Android.
18. **Tests:** transaction lifecycle.
19. **Compliance:** ZATCA.
20. **Cross-module:** Mada terminal، thermal printer، cash drawer.
21. **Roadmap:** P1: offline + printer. P2: ZATCA Phase 2. P3: AI + KDS.

## 24 — إدارة المنيو والوصفات (Menu Engineering)

1. **الاسم:** إدارة المنيو (Menu Engineering).
2. **القسم:** المطبخ.
3. **الغرض:** أصناف + BOM + أسعار قنوات + engineering.
4. **الكيان:** `menu_items`.
5. **الدورة:** category → item → recipe → channel prices → available.
6. **الصفحات:** كل + `#menu_engineering` (matrix ربحية × شعبية)، `#menu_seasonal`، `#menu_photos`.
7. **الجداول:** 5 + `menu_variants` + `menu_modifiers` + `menu_combos` + `menu_allergens`.
8. **APIs:** `menu_bulk_price_update`, `menu_engineering_score`.
9. **الحالات:** availability + active.
10. **الصلاحيات:** operations_manager + menu_manager.
11. **الإشعارات:** margin drops.
12. **KPIs:** popularity، profitability.
13. **العلاقات:** POS، Inventory، BI.
14. **المخاطر:** BOM اختياري.
15. **قرارات:** BOM إلزامي؟
16. **UI:** v123.
17. **Mobile:** editor.
18. **Tests:** item → recipe → price.
19. **Compliance:** allergen disclosure.
20. **Cross-module:** Jahez menu sync.
21. **Roadmap:** P1: BOM إلزامي. P2: modifiers + combos. P3: AI engineering.

## 25 — علاقات العملاء والولاء (CRM 2.0)

1. **الاسم:** CRM & Loyalty 2.0.
2. **القسم:** العملاء.
3. **الغرض:** عملاء + عناوين + ولاء + شكاوى + حملات.
4. **الكيان:** `crm_customers` (بعد التوحيد).
5. **الدورة:** create customer → addresses → loyalty auto → complaint → resolution.
6. **الصفحات:** كل + `#crm_campaigns`, `#crm_segments_ai`, `#crm_referrals`.
7. **الجداول:** 5 + توحيد مع acct_customers + `crm_campaigns` + `crm_referrals` + `crm_customer_notes`.
8. **APIs:** `crm_merge_duplicates`, `crm_send_campaign`.
9. **الحالات:** complaint 4، loyalty INSERT-only.
10. **الصلاحيات:** operations_manager + crm_manager.
11. **الإشعارات:** birthday، complaint stages.
12. **KPIs:** LTV، NPS، retention.
13. **العلاقات:** POS، Delivery، Cafe، CC.
14. **المخاطر:** R-08.
15. **قرارات:** D2 (توحيد).
16. **UI:** v123.
17. **Mobile:** priority.
18. **Tests:** customer + loyalty + complaint.
19. **Compliance:** GDPR-like.
20. **Cross-module:** WhatsApp Business.
21. **Roadmap:** P1: توحيد + campaigns. P2: WhatsApp + AI. P3: referrals.

## 26 — سلامة الغذاء (HACCP / Food Safety)

1. **الاسم:** سلامة الغذاء والامتثال (HACCP).
2. **القسم:** الجودة والسلامة.
3. **الغرض:** SASO 2233 + معدات + حرارة + دفعات + شهادات + حوادث.
4. **الكيان:** `haccp_incidents`.
5. **الدورة:** setup CCPs → daily temperature logs → batch tracking → certificates → incident handling.
6. **الصفحات:** كل + `#haccp_iot` (sensors)، `#haccp_audit_trail`، `#haccp_ccps`.
7. **الجداول:** 6 + `haccp_sensor_readings`.
8. **APIs:** `haccp_generate_daily_report`, `haccp_export_audit`.
9. **الحالات:** batch 3، incident 4.
10. **الصلاحيات:** quality_manager + haccp_manager.
11. **الإشعارات:** breach alerts.
12. **KPIs:** breach rate.
13. **العلاقات:** HR (certs)، Emergency، BI.
14. **المخاطر:** تكرار مع HR certs.
15. **قرارات:** توحيد certs.
16. **UI:** v123.
17. **Mobile:** priority (field).
18. **Tests:** log → incident → close.
19. **Compliance:** SASO 2233 + SFDA.
20. **Cross-module:** IoT sensors.
21. **Roadmap:** P1: IoT + توحيد certs. P2: AI anomaly. P3: cross-standard.

## 27 — الشراء الاستراتيجي (Strategic Procurement)

1. **الاسم:** الشراء الاستراتيجي.
2. **القسم:** المشتريات.
3. **الغرض:** PR → PO → GRN → AP آلي + multi-approval + RFP.
4. **الكيان:** `proc_purchase_orders`.
5. **الدورة:** PR draft → submitted → approved → converted_to_po → PO sent_to_vendor → confirmed → GRN → AP bill draft → paid.
6. **الصفحات:** كل + `#proc_rfp`, `#proc_vendor_scorecards`, `#proc_contracts`.
7. **الجداول:** 6 + `proc_rfps` + `proc_vendor_scorecards`.
8. **APIs:** `proc_multi_approval`, `proc_rfq_send_to_vendors`.
9. **الحالات:** PR 6، PO 6+، GRN 2.
10. **الصلاحيات:** operations_manager + finance_manager + procurement_manager.
11. **الإشعارات:** approval requests.
12. **KPIs:** cycle time، savings.
13. **العلاقات:** Accounting (AP)، Inventory.
14. **المخاطر:** تكرار مع acct_purchase_orders.
15. **قرارات:** توحيد.
16. **UI:** v123.
17. **Mobile:** approval.
18. **Tests:** PR → PO → GRN → AP.
19. **Compliance:** —
20. **Cross-module:** vendor portals.
21. **Roadmap:** P1: multi-approval. P2: RFP. P3: AI anomaly.

## 28 — إدارة الأداء (Performance Management)

1. **الاسم:** إدارة الأداء (Performance).
2. **القسم:** الأداء.
3. **الغرض:** KPI + سكوركاردات + تقييمات + أهداف SMART.
4. **الكيان:** `perf_scorecards`.
5. **الدورة:** define KPIs → monthly scorecards → compute score → periodic review → employee ack.
6. **الصفحات:** كل + `#perf_360`, `#perf_talent_matrix`, `#perf_dev_plans`.
7. **الجداول:** 5 + توسع 360.
8. **APIs:** `perf_auto_compute_from_bi`, `perf_link_to_okr`.
9. **الحالات:** scorecard 4، review 4، goal 4.
10. **الصلاحيات:** hr_manager + perf_manager.
11. **الإشعارات:** review scheduled، ack required.
12. **KPIs:** review completion rate.
13. **العلاقات:** HR، Users، BI.
14. **المخاطر:** —
15. **قرارات:** ربط تلقائي BI.
16. **UI:** v123.
17. **Mobile:** —
18. **Tests:** scorecard + review.
19. **Compliance:** OKR framework.
20. **Cross-module:** OKR + BI.
21. **Roadmap:** P1: ربط BI. P2: 360. P3: talent matrix.

## 29 — التوصيل الداخلي (Last-Mile Delivery)

1. **الاسم:** التوصيل والسائقين.
2. **القسم:** التوصيل.
3. **الغرض:** مناطق + سائقين + طلبات + Kanban + driver PWA.
4. **الكيان:** `delivery_orders`.
5. **الدورة:** new → assign rider → prep → pickup → on_the_way → delivered.
6. **الصفحات:** كل + `#dlv_driver_app`, `#dlv_realtime_map`, `#dlv_earnings`.
7. **الجداول:** 5 + توسع GPS tracking + earnings.
8. **APIs:** `dlv_dispatch_auto`, `dlv_realtime_broadcast`.
9. **الحالات:** 9 حالات.
10. **الصلاحيات:** operations_manager + delivery_manager + rider self.
11. **الإشعارات:** status changes.
12. **KPIs:** avg delivery time.
13. **العلاقات:** POS، CRM، BI.
14. **المخاطر:** لا driver app.
15. **قرارات:** D17 (Driver PWA).
16. **UI:** driver-first.
17. **Mobile:** priority أعلى.
18. **Tests:** order lifecycle.
19. **Compliance:** insurance.
20. **Cross-module:** Google Maps، Jahez/HungerStation.
21. **Roadmap:** P1: PWA سائق. P2: platforms integration. P3: AI ETA.

## 30 — إدارة المستندات (DMS)

1. **الاسم:** إدارة المستندات (DMS).
2. **القسم:** المستندات.
3. **الغرض:** 14 تصنيف + polymorphic + signatures + versions.
4. **الكيان:** `doc_documents`.
5. **الدورة:** upload → active → expired → archived.
6. **الصفحات:** كل + `#doc_workflow`, `#doc_signatures`, `#doc_templates`, `#doc_bulk_upload`.
7. **الجداول:** 3 + `doc_signatures` + `doc_workflows` + `doc_versions`.
8. **APIs:** `doc_request_signature`, `doc_lock_version`.
9. **الحالات:** `active → expired → archived`.
10. **الصلاحيات:** hr_manager + doc_manager + owner + related-entity access.
11. **الإشعارات:** expiring (cron scheduler R-15).
12. **KPIs:** expiry compliance.
13. **العلاقات:** polymorphic (كل موديول).
14. **المخاطر:** لا cron.
15. **قرارات:** توحيد HACCP certs.
16. **UI:** v123.
17. **Mobile:** upload photo.
18. **Tests:** upload → access → expire.
19. **Compliance:** retention policies.
20. **Cross-module:** DocuSign integration.
21. **Roadmap:** P1: cron scheduler. P2: signatures. P3: OCR + AI auto-tag.

## 31 — مركز الاتصال (Contact Center)

1. **الاسم:** مركز الاتصال ومعالجة الشكاوى.
2. **القسم:** خدمة العملاء.
3. **الغرض:** Agents + Calls + Dispositions + Scripts + Followups + Omnichannel.
4. **الكيان:** `cc_calls`.
5. **الدورة:** queue → start_call → in_progress + agent on_call → end_call → completed + agent available + إحصائيات.
6. **الصفحات:** كل + `#cc_omnichannel` (WhatsApp/Email/SMS)، `#cc_realtime_wallboard`.
7. **الجداول:** 4 + `cc_chat_sessions`, `cc_email_threads`.
8. **APIs:** `cc_pbx_start_call`, `cc_omnichannel_route`.
9. **الحالات:** call 4، agent 5.
10. **الصلاحيات:** operations_manager + cc_manager.
11. **الإشعارات:** followup reminders.
12. **KPIs:** AHT، FCR، CSAT.
13. **العلاقات:** CRM، POS، Delivery.
14. **المخاطر:** R-12 (لا PBX).
15. **قرارات:** D7 (PBX timing).
16. **UI:** v123.
17. **Mobile:** agent mobile.
18. **Tests:** call lifecycle.
19. **Compliance:** call recording consent.
20. **Cross-module:** Twilio، WhatsApp Business.
21. **Roadmap:** P1: PBX/Twilio. P2: omnichannel. P3: AI sentiment.

## 32 — الذكاء التحليلي (BI 2.0)

1. **الاسم:** BI 2.0.
2. **القسم:** الاستراتيجية.
3. **الغرض:** 7 تقارير مبذورة + snapshots + saved views + alerts.
4. **الكيان:** `bi_snapshots`.
5. **الدورة:** definition → RPC → snapshot → view.
6. **الصفحات:** كل + `#bi_dashboards`, `#bi_alerts`, `#bi_predictive`.
7. **الجداول:** 3 + توسع.
8. **APIs:** `bi_cash_flow` (حل CASH_FLOW)، `bi_scheduled_export`.
9. **الحالات:** snapshot type 4.
10. **الصلاحيات:** finance_manager + bi_manager.
11. **الإشعارات:** anomaly alerts.
12. **KPIs:** report usage.
13. **العلاقات:** كل موديول.
14. **المخاطر:** CASH_FLOW placeholder (R-16).
15. **قرارات:** D8 (إلغاء #reports و #analytics)، D12 (CASH_FLOW).
16. **UI:** v123.
17. **Mobile:** —
18. **Tests:** report + snapshot.
19. **Compliance:** —
20. **Cross-module:** Slack/Teams scheduled export.
21. **Roadmap:** P1: CASH_FLOW. P2: alerts + NL queries. P3: predictive.

## 33 — التكاملات الخارجية (Integrations Hub)

1. **الاسم:** التكاملات (Integrations Hub).
2. **القسم:** التكاملات.
3. **الغرض:** 12 مزوّد config + webhooks + workers + retry.
4. **الكيان:** `int_providers`.
5. **الدورة:** provider → connection → event: pending → sent / failed → retrying.
6. **الصفحات:** كل + `#int_playbooks`, `#int_test_console`, `#int_secrets_manager`.
7. **الجداول:** 4 + توسع retry policy + secrets.
8. **APIs:** Edge Functions dedicated (12).
9. **الحالات:** connection 3، event 4.
10. **الصلاحيات:** admin + company_manager + integrations_manager.
11. **الإشعارات:** provider down.
12. **KPIs:** success rate per provider.
13. **العلاقات:** كل موديول.
14. **المخاطر:** R-11 (workers)، R-05 (Vault).
15. **قرارات:** D6 (أولوية) + D15 (Vault).
16. **UI:** v123.
17. **Mobile:** monitoring.
18. **Tests:** send + retry.
19. **Compliance:** PII masking.
20. **Cross-module:** كل موديول.
21. **Roadmap:** P1: Jahez + WhatsApp + Vault. P2: كل الـ12. P3: advanced routing.

## 34 — الفرنشايز والامتيازات (Franchise)

1. **الاسم:** الفرنشايز والامتيازات.
2. **القسم:** الشراكات.
3. **الغرض:** شركاء + عقود + فروع + تقارير مبيعات + روياليتي + بوابة فرنشايزي.
4. **الكيان:** `franchise_agreements`.
5. **الدورة:** partner → agreement → branches → monthly sales report → compute_royalty → issue → AR (auto/manual).
6. **الصفحات:** كل + `#franchisee_portal` (login منفصل)، `#fr_analytics`, `#fr_compliance`.
7. **الجداول:** 5 + `franchisee_users`.
8. **APIs:** `franchise_auto_ar_invoice`, `franchisee_upload_report`.
9. **الحالات:** partner 5، agreement 4، sales report 3، royalty 4.
10. **الصلاحيات:** finance_manager + franchise_manager + franchisee (منفصل).
11. **الإشعارات:** report due، royalty issued.
12. **KPIs:** revenue، compliance rate.
13. **العلاقات:** Accounting AR.
14. **المخاطر:** R-14 (AR link)، لا بوابة.
15. **قرارات:** D1 (AR auto)، D5 (بوابة).
16. **UI:** v123 + portal.
17. **Mobile:** بوابة فرنشايزي.
18. **Tests:** royalty compute + issue.
19. **Compliance:** brand standards.
20. **Cross-module:** BI franchise dashboard.
21. **Roadmap:** P1: AR auto + بوابة MVP. P2: compliance monitoring. P3: analytics.

---

## خاتمة برومت ChatGPT

اطلب من ChatGPT الآن:

> بناءً على المرجع أعلاه لكل موديول (34 موديول × 21 عنصر)، اكتب برومت إعادة هندسة شامل لمنصة "شؤون الغذاء" يتضمن:
> - **Executive Summary** (النظام حاليًا + الهدف).
> - **Priority Matrix** (D1-D20 قرارات المالك بترتيب الأولوية).
> - **Sprint Plan** (P1/P2/P3 لكل موديول).
> - **Security Fixes** (R-01 → R-16).
> - **Data Migration Plan** (SQL versioning R-07).
> - **UI/UX Design System** (v123 extended).
> - **Testing Strategy** (E2E for critical paths).
> - **Cross-module Integration Discipline** (10 auto journals + tokens + AI tools + BI).
> - **Documentation Standards** (نموذج موحد لكل موديول).
> - **Rollout Plan** (READY 15 → STABILIZE 12 → BACKEND 3 → SECURITY 3).

كل موديول ينبغي أن يُعامل كـ "unit" مستقل بـ:
- Data model كامل.
- APIs محددة.
- Screens مذكورة.
- States واضحة.
- Roles.
- Notifications.
- KPIs.
- Cross-module hooks.
- Roadmap 3 مراحل.

**مصدر الحقائق:** الملفات 00-44 في مجلد `_system_discovery/module_deep_discovery/` تحتوي التحليل التفصيلي.
