-- ═══════════════════════════════════════════════════════════
-- سيكشن «طلبات شركات التوصيل» — خاص بمدير الفرع
-- ═══════════════════════════════════════════════════════════
-- الغرض: يوثّق مدير الفرع أي طلب وارد من شركة توصيل بالصور:
--   • اسم شركة التوصيل (من قائمة)
--   • صورة الفاتورة (إلزامية)
--   • صورتان للطلب (إلزامية الأولى، الثانية اختيارية)
--
-- آمن للتشغيل أكثر من مرة (idempotent) — لا يحذف ولا يعدّل أي بيانات قائمة.
-- الصور تُرفع على bucket «maintenance» الموجود مسبقًا تحت مسار
-- delivery-requests/ — لا يحتاج إنشاء bucket جديد.
-- ═══════════════════════════════════════════════════════════

-- ─── (1) جدول شركات التوصيل (قائمة الاختيار) ───────────────
CREATE TABLE IF NOT EXISTS delivery_companies (
  id          BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order  INT NOT NULL DEFAULT 100,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- اسم فريد حتى لا تتكرر الشركة عند إعادة التشغيل
CREATE UNIQUE INDEX IF NOT EXISTS delivery_companies_name_uniq
  ON delivery_companies (name);

-- الشركات الشائعة في السوق السعودي — تُضاف مرة واحدة فقط
INSERT INTO delivery_companies (name, sort_order)
SELECT v.name, v.ord
FROM (VALUES
  ('هنقرستيشن', 10),
  ('جاهز', 20),
  ('مرسول', 30),
  ('كيتا', 40),
  ('ذا شفز', 50),
  ('نينجا', 60),
  ('توصي', 70),
  ('شغف', 80),
  ('أخرى', 999)
) AS v(name, ord)
WHERE NOT EXISTS (SELECT 1 FROM delivery_companies d WHERE d.name = v.name);

-- ─── (2) جدول الطلبات الموثّقة ──────────────────────────────
CREATE TABLE IF NOT EXISTS branch_delivery_requests (
  id                BIGSERIAL PRIMARY KEY,
  branch_id         BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  company_id        BIGINT REFERENCES delivery_companies(id) ON DELETE SET NULL,
  -- نسخة نصية من اسم الشركة وقت التسجيل: لو حُذفت الشركة لاحقًا يبقى السجل مفهومًا
  company_name      TEXT,
  order_ref         TEXT,               -- رقم الطلب لدى شركة التوصيل (اختياري)
  amount            NUMERIC(12,2),      -- قيمة الفاتورة (اختياري)
  notes             TEXT,
  invoice_photo_url TEXT NOT NULL,      -- صورة الفاتورة — إلزامية
  order_photo1_url  TEXT,               -- صورة الطلب (1)
  order_photo2_url  TEXT,               -- صورة الطلب (2)
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS bdr_branch_created_idx
  ON branch_delivery_requests (branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS bdr_company_idx
  ON branch_delivery_requests (company_id);
CREATE INDEX IF NOT EXISTS bdr_created_by_idx
  ON branch_delivery_requests (created_by);

-- ─── (3) تفعيل RLS ──────────────────────────────────────────
ALTER TABLE delivery_companies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE branch_delivery_requests ENABLE ROW LEVEL SECURITY;

-- قائمة الشركات: كل مستخدم مسجّل يقرأها (يحتاجها لملء القائمة المنسدلة)
DROP POLICY IF EXISTS delivery_companies_read ON delivery_companies;
CREATE POLICY delivery_companies_read ON delivery_companies
  FOR SELECT USING (current_app_user_id() IS NOT NULL);

-- تعديل قائمة الشركات: الإدارة العليا فقط
DROP POLICY IF EXISTS delivery_companies_write ON delivery_companies;
CREATE POLICY delivery_companies_write ON delivery_companies
  FOR ALL
  USING (current_app_role() IN ('admin', 'company_manager'))
  WITH CHECK (current_app_role() IN ('admin', 'company_manager'));

-- قراءة الطلبات: مدير الفرع يرى فرعه فقط، والإدارة العليا ترى الكل
DROP POLICY IF EXISTS bdr_select ON branch_delivery_requests;
CREATE POLICY bdr_select ON branch_delivery_requests
  FOR SELECT USING (
    current_app_role() IN ('admin', 'company_manager')
    OR EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = current_app_user_id()
        AND u.branch_id = branch_delivery_requests.branch_id
    )
  );

-- الإضافة: مدير الفرع (أو نائبه) على فرعه هو فقط — لا يستطيع التسجيل باسم فرع آخر
DROP POLICY IF EXISTS bdr_insert ON branch_delivery_requests;
CREATE POLICY bdr_insert ON branch_delivery_requests
  FOR INSERT WITH CHECK (
    current_app_role() IN ('admin', 'company_manager')
    OR EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = current_app_user_id()
        AND u.role IN ('branch_manager', 'deputy_manager')
        AND u.branch_id = branch_delivery_requests.branch_id
    )
  );

-- التعديل/الحذف: صاحب السجل على فرعه، أو الإدارة العليا
DROP POLICY IF EXISTS bdr_update ON branch_delivery_requests;
CREATE POLICY bdr_update ON branch_delivery_requests
  FOR UPDATE
  USING (
    current_app_role() IN ('admin', 'company_manager')
    OR created_by = current_app_user_id()
  )
  WITH CHECK (
    current_app_role() IN ('admin', 'company_manager')
    OR created_by = current_app_user_id()
  );

DROP POLICY IF EXISTS bdr_delete ON branch_delivery_requests;
CREATE POLICY bdr_delete ON branch_delivery_requests
  FOR DELETE USING (
    current_app_role() IN ('admin', 'company_manager')
    OR created_by = current_app_user_id()
  );

-- ─── (4) تأكيد النتيجة ──────────────────────────────────────
SELECT 'delivery_companies' AS table_name, COUNT(*)::TEXT AS rows FROM delivery_companies
UNION ALL
SELECT 'branch_delivery_requests', COUNT(*)::TEXT FROM branch_delivery_requests;
