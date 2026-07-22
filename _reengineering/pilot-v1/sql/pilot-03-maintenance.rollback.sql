-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Rollback لموديول الصيانة (pilot-03)
-- ═══════════════════════════════════════════════════════════════════════
-- يعيد الصيانة إلى حالتها قبل التصليب: يزيل الحرّاس والتدقيق والسياسات
-- الجديدة، ويعيد سياسة using(true) المؤقتة حتى لا تُقفَل الجداول.
-- لا يحذف أي بيانات ولا يزيل الأعمدة المضافة (updated_by/reopen_count تبقى
-- بلا ضرر). آمن لإعادة التشغيل.
-- ═══════════════════════════════════════════════════════════════════════

-- تريجرز
DROP TRIGGER IF EXISTS trg_mr_guard ON maintenance_requests;
DROP TRIGGER IF EXISTS trg_mr_touch ON maintenance_requests;
DROP TRIGGER IF EXISTS trg_mr_audit ON maintenance_requests;
DROP TRIGGER IF EXISTS trg_mfa_audit ON maintenance_finance_approvals;
DROP TRIGGER IF EXISTS trg_mrep_audit ON maintenance_repairs;
DROP TRIGGER IF EXISTS trg_mq_audit ON maintenance_quotes;
DROP FUNCTION IF EXISTS mr_guard_transition();

-- قيد الحالة
ALTER TABLE maintenance_requests DROP CONSTRAINT IF EXISTS mr_status_chk;

-- السياسات الجديدة
DROP POLICY IF EXISTS mr_sel ON maintenance_requests;
DROP POLICY IF EXISTS mr_ins ON maintenance_requests;
DROP POLICY IF EXISTS mr_upd ON maintenance_requests;
DROP POLICY IF EXISTS mr_del ON maintenance_requests;
DROP POLICY IF EXISTS br_sel ON branches;
DROP POLICY IF EXISTS br_wr ON branches;
DO $$
DECLARE child TEXT;
  children TEXT[] := ARRAY['maintenance_inspections','maintenance_quotes',
    'maintenance_finance_approvals','maintenance_repairs','maintenance_receipts',
    'maintenance_attachments','maintenance_timeline'];
BEGIN
  FOREACH child IN ARRAY children LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_sel', child);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', child || '_wr', child);
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS mr_is_maint_admin();
DROP FUNCTION IF EXISTS mr_user_in_branch(BIGINT);

-- إعادة السياسة المؤقتة المفتوحة (كي لا تُقفَل الجداول بعد التراجع)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='mr_all') THEN
    CREATE POLICY mr_all ON maintenance_requests FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='br_all') THEN
    CREATE POLICY br_all ON branches FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

SELECT 'maintenance rollback done' AS status;
