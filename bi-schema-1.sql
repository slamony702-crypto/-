-- ═══════════════════════════════════════════════════════════
-- الذكاء التحليلي BI — Phase 1 (Wave 4 Module 33)
-- ═══════════════════════════════════════════════════════════
-- 3 جداول: تعريفات التقارير + لقطات + العروض المحفوظة
-- + 5 دوال تجميع cross-module جاهزة:
--   bi_daily_summary, bi_branch_ranking, bi_top_menu_items,
--   bi_customer_segments, bi_operations_health
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير الذكاء التحليلي
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_bi_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'finance_manager', 'bi_analyst');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) bi_report_definitions — كتالوج التقارير الجاهزة
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bi_report_definitions (
  id             BIGSERIAL PRIMARY KEY,
  code           TEXT UNIQUE NOT NULL,
  name           TEXT NOT NULL,
  description    TEXT,
  category       TEXT NOT NULL CHECK (category IN ('sales', 'operations', 'finance', 'hr', 'customer', 'quality', 'delivery')),
  icon           TEXT DEFAULT 'bar-chart',
  rpc_name       TEXT,
  requires_dates BOOLEAN NOT NULL DEFAULT TRUE,
  requires_branch BOOLEAN NOT NULL DEFAULT FALSE,
  parameters     JSONB,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS bi_reports_updated_at ON bi_report_definitions;
CREATE TRIGGER bi_reports_updated_at BEFORE UPDATE ON bi_report_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- بذر التقارير الجاهزة
INSERT INTO bi_report_definitions (code, name, description, category, icon, rpc_name, requires_dates, requires_branch) VALUES
  ('DAILY_SUMMARY',      'ملخص يومي شامل',            'مبيعات، طلبات، عملاء، حضور خلال الفترة', 'sales',     'trending-up',    'bi_daily_summary',     TRUE,  FALSE),
  ('BRANCH_RANKING',     'ترتيب أداء الفروع',          'ترتيب الفروع حسب المبيعات والطلبات',       'sales',     'award',          'bi_branch_ranking',    TRUE,  FALSE),
  ('TOP_MENU_ITEMS',     'الأصناف الأكثر مبيعًا',       'ترتيب أصناف المنيو حسب الإيراد',            'sales',     'utensils',       'bi_top_menu_items',    TRUE,  FALSE),
  ('CUSTOMER_SEGMENTS',  'شرائح العملاء',              'توزيع العملاء على VIP/regular/inactive',    'customer',  'users',          'bi_customer_segments', FALSE, FALSE),
  ('OPERATIONS_HEALTH',  'مؤشرات الصحة التشغيلية',    'HACCP، هدر، حضور، شكاوى',                    'operations','activity',       'bi_operations_health', TRUE,  FALSE),
  ('DELIVERY_KPIS',      'أداء التوصيل',              'زمن، إسناد، تسليم، إلغاء',                   'delivery',  'bike',           'bi_delivery_kpis',     TRUE,  FALSE),
  ('CASH_FLOW',          'التدفقات النقدية اليومية',   'مدخول ومصروف نقدي من POS وAP',              'finance',   'wallet',         NULL,                   TRUE,  FALSE)
ON CONFLICT (code) DO NOTHING;

-- ───────────────────────────────────────────────────────────
-- 2) bi_snapshots — لقطات محفوظة للأداء السريع
--    DECISION: نخزّن JSON للمرونة — كل تقرير له شكل مختلف.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bi_snapshots (
  id            BIGSERIAL PRIMARY KEY,
  report_code   TEXT NOT NULL,
  snapshot_type TEXT NOT NULL DEFAULT 'daily' CHECK (snapshot_type IN ('daily', 'weekly', 'monthly', 'ad_hoc')),
  period_start  DATE NOT NULL,
  period_end    DATE NOT NULL,
  branch_id     BIGINT REFERENCES branches(id) ON DELETE CASCADE,
  data          JSONB NOT NULL,
  row_count     INT,
  computed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  computed_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT bi_snap_period CHECK (period_end >= period_start)
);

CREATE INDEX IF NOT EXISTS bi_snap_report_idx ON bi_snapshots(report_code, period_end DESC);
CREATE INDEX IF NOT EXISTS bi_snap_branch_idx ON bi_snapshots(branch_id, period_end DESC) WHERE branch_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS bi_snap_unique_daily ON bi_snapshots(report_code, snapshot_type, period_start, period_end, COALESCE(branch_id, -1));

-- ───────────────────────────────────────────────────────────
-- 3) bi_saved_views — العروض المخصصة للمستخدمين
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bi_saved_views (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_code TEXT NOT NULL,
  name        TEXT NOT NULL,
  filters     JSONB NOT NULL DEFAULT '{}'::JSONB,
  is_default  BOOLEAN NOT NULL DEFAULT FALSE,
  is_shared   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT bi_view_unique_name UNIQUE (user_id, report_code, name)
);

CREATE INDEX IF NOT EXISTS bi_views_user_idx ON bi_saved_views(user_id, report_code);
CREATE INDEX IF NOT EXISTS bi_views_shared_idx ON bi_saved_views(report_code) WHERE is_shared;

DROP TRIGGER IF EXISTS bi_views_updated_at ON bi_saved_views;
CREATE TRIGGER bi_views_updated_at BEFORE UPDATE ON bi_saved_views
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دوال التقارير Cross-Module
-- ═══════════════════════════════════════════════════════════

-- 1) ملخص يومي شامل (POS + Delivery + CRM + HR)
CREATE OR REPLACE FUNCTION bi_daily_summary(p_from DATE, p_to DATE)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_build_object(
    'period', json_build_object('from', p_from, 'to', p_to),
    'pos', (
      SELECT json_build_object(
        'transactions', COUNT(*),
        'gross_sales', COALESCE(SUM(total_amount), 0),
        'net_sales', COALESCE(SUM(total_amount - vat_amount), 0),
        'vat_collected', COALESCE(SUM(vat_amount), 0),
        'avg_ticket', ROUND(AVG(total_amount)::numeric, 2)
      ) FROM pos_transactions
      WHERE status = 'completed' AND completed_at::date BETWEEN p_from AND p_to
    ),
    'delivery', (
      SELECT json_build_object(
        'total_orders', COUNT(*),
        'delivered', COUNT(*) FILTER (WHERE status = 'delivered'),
        'cancelled', COUNT(*) FILTER (WHERE status IN ('cancelled', 'failed')),
        'total_revenue', COALESCE(SUM(total_amount) FILTER (WHERE status = 'delivered'), 0)
      ) FROM delivery_orders
      WHERE created_at::date BETWEEN p_from AND p_to
    ),
    'customers', (
      SELECT json_build_object(
        'new_customers', COUNT(*),
        'total_active', (SELECT COUNT(*) FROM crm_customers WHERE is_active AND deleted_at IS NULL)
      ) FROM crm_customers
      WHERE created_at::date BETWEEN p_from AND p_to AND deleted_at IS NULL
    ),
    'complaints', (
      SELECT json_build_object(
        'new_complaints', COUNT(*),
        'resolved', COUNT(*) FILTER (WHERE status IN ('resolved', 'closed')),
        'open', COUNT(*) FILTER (WHERE status IN ('open', 'in_progress', 'escalated'))
      ) FROM crm_complaints
      WHERE created_at::date BETWEEN p_from AND p_to
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- 2) ترتيب الفروع بالمبيعات
CREATE OR REPLACE FUNCTION bi_branch_ranking(p_from DATE, p_to DATE)
RETURNS TABLE(
  branch_id BIGINT, branch_name TEXT, transactions BIGINT,
  gross_sales NUMERIC, avg_ticket NUMERIC, delivery_orders BIGINT, delivery_revenue NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id AS branch_id,
    b.name AS branch_name,
    COALESCE(pos.txn_count, 0) AS transactions,
    COALESCE(pos.total, 0) AS gross_sales,
    COALESCE(ROUND((pos.total / NULLIF(pos.txn_count, 0))::numeric, 2), 0) AS avg_ticket,
    COALESCE(dlv.order_count, 0) AS delivery_orders,
    COALESCE(dlv.delivered_revenue, 0) AS delivery_revenue
  FROM branches b
  LEFT JOIN (
    SELECT branch_id, COUNT(*) AS txn_count, SUM(total_amount) AS total
    FROM pos_transactions
    WHERE status = 'completed' AND completed_at::date BETWEEN p_from AND p_to
    GROUP BY branch_id
  ) pos ON pos.branch_id = b.id
  LEFT JOIN (
    SELECT branch_id, COUNT(*) AS order_count,
           SUM(total_amount) FILTER (WHERE status = 'delivered') AS delivered_revenue
    FROM delivery_orders
    WHERE created_at::date BETWEEN p_from AND p_to
    GROUP BY branch_id
  ) dlv ON dlv.branch_id = b.id
  WHERE b.is_active
  ORDER BY gross_sales DESC;
END;
$$;

-- 3) أصناف المنيو الأكثر مبيعًا
CREATE OR REPLACE FUNCTION bi_top_menu_items(p_from DATE, p_to DATE, p_limit INT DEFAULT 20)
RETURNS TABLE(
  item_id BIGINT, item_name TEXT, category_name TEXT,
  qty_sold NUMERIC, revenue NUMERIC, times_ordered BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- الأعمدة الصحيحة: menu_items.name_ar و menu_categories.name_ar (لا يوجد عمود "name" في أي منهما)
  RETURN QUERY
  SELECT
    mi.id AS item_id,
    mi.name_ar AS item_name,
    mc.name_ar AS category_name,
    SUM(pti.quantity) AS qty_sold,
    SUM(pti.line_total) AS revenue,
    COUNT(DISTINCT pti.transaction_id) AS times_ordered
  FROM pos_transaction_items pti
  JOIN pos_transactions pt ON pt.id = pti.transaction_id
  LEFT JOIN menu_items mi ON mi.id = pti.menu_item_id
  LEFT JOIN menu_categories mc ON mc.id = mi.category_id
  WHERE pt.status = 'completed' AND pt.completed_at::date BETWEEN p_from AND p_to
  GROUP BY mi.id, mi.name_ar, mc.name_ar
  ORDER BY revenue DESC NULLS LAST
  LIMIT p_limit;
END;
$$;

-- 4) شرائح العملاء
CREATE OR REPLACE FUNCTION bi_customer_segments()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_build_object(
    'segments', (
      SELECT json_object_agg(segment, cnt) FROM (
        SELECT segment, COUNT(*) AS cnt
        FROM crm_customers
        WHERE is_active AND deleted_at IS NULL
        GROUP BY segment
      ) s
    ),
    'loyalty_tiers', (
      SELECT json_object_agg(tier, cnt) FROM (
        SELECT tier, COUNT(*) AS cnt FROM loyalty_accounts GROUP BY tier
      ) t
    ),
    'total_active', (SELECT COUNT(*) FROM crm_customers WHERE is_active AND deleted_at IS NULL),
    'total_loyalty_points', (SELECT COALESCE(SUM(points_balance), 0) FROM loyalty_accounts)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- 5) صحة العمليات (HACCP + الهدر + الحضور + الشكاوى)
CREATE OR REPLACE FUNCTION bi_operations_health(p_from DATE, p_to DATE)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_build_object(
    'haccp', (
      SELECT json_build_object(
        'total_incidents', COUNT(*),
        'critical_open', COUNT(*) FILTER (WHERE severity = 'critical' AND status IN ('open', 'investigating')),
        'resolved', COUNT(*) FILTER (WHERE status IN ('resolved', 'closed')),
        'temperature_breaches', (SELECT COUNT(*) FROM haccp_temperature_logs
                                  WHERE recorded_at::date BETWEEN p_from AND p_to AND is_within_range = FALSE)
      ) FROM haccp_incidents
      WHERE created_at::date BETWEEN p_from AND p_to
    ),
    'complaints', (
      SELECT json_build_object(
        'total', COUNT(*),
        'critical', COUNT(*) FILTER (WHERE severity = 'critical'),
        'open', COUNT(*) FILTER (WHERE status IN ('open', 'in_progress')),
        'avg_satisfaction', ROUND(AVG(satisfaction_rating)::numeric, 2)
      ) FROM crm_complaints
      WHERE created_at::date BETWEEN p_from AND p_to
    ),
    'expiring_docs', (
      SELECT COUNT(*) FROM doc_documents
      WHERE status = 'active' AND expiry_date IS NOT NULL
        AND expiry_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '30 days')
    ),
    'expiring_certs', (
      SELECT COUNT(*) FROM haccp_health_certificates
      WHERE status = 'active' AND expiry_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '30 days')
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- 6) مؤشرات التوصيل
CREATE OR REPLACE FUNCTION bi_delivery_kpis(p_from DATE, p_to DATE)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_build_object(
    'orders', json_build_object(
      'total', COUNT(*),
      'delivered', COUNT(*) FILTER (WHERE status = 'delivered'),
      'cancelled', COUNT(*) FILTER (WHERE status IN ('cancelled', 'failed')),
      'in_progress', COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled', 'failed'))
    ),
    'financial', json_build_object(
      'gross_revenue', COALESCE(SUM(total_amount) FILTER (WHERE status = 'delivered'), 0),
      'delivery_fees', COALESCE(SUM(delivery_fee) FILTER (WHERE status = 'delivered'), 0),
      'avg_ticket', ROUND(AVG(total_amount) FILTER (WHERE status = 'delivered')::numeric, 2)
    ),
    'timing', json_build_object(
      'avg_prep_minutes', ROUND(AVG(EXTRACT(EPOCH FROM (ready_at - accepted_at)) / 60)::numeric, 1),
      'avg_delivery_minutes', ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at - picked_up_at)) / 60)::numeric, 1)
    ),
    'satisfaction', json_build_object(
      'avg_rating', ROUND(AVG(customer_rating)::numeric, 2),
      'rated_count', COUNT(*) FILTER (WHERE customer_rating IS NOT NULL)
    )
  ) INTO v_result
  FROM delivery_orders
  WHERE created_at::date BETWEEN p_from AND p_to;
  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- دالة حفظ لقطة
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION bi_save_snapshot(
  p_report_code TEXT,
  p_snapshot_type TEXT,
  p_from DATE,
  p_to DATE,
  p_branch_id BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data JSON;
  v_id   BIGINT;
BEGIN
  CASE p_report_code
    WHEN 'DAILY_SUMMARY'      THEN v_data := bi_daily_summary(p_from, p_to);
    WHEN 'CUSTOMER_SEGMENTS'  THEN v_data := bi_customer_segments();
    WHEN 'OPERATIONS_HEALTH'  THEN v_data := bi_operations_health(p_from, p_to);
    WHEN 'DELIVERY_KPIS'      THEN v_data := bi_delivery_kpis(p_from, p_to);
    ELSE RAISE EXCEPTION 'التقرير % لا يدعم اللقطات', p_report_code;
  END CASE;

  INSERT INTO bi_snapshots (report_code, snapshot_type, period_start, period_end, branch_id, data, computed_by)
  VALUES (p_report_code, p_snapshot_type, p_from, p_to, p_branch_id, v_data::JSONB, current_app_user_id())
  ON CONFLICT (report_code, snapshot_type, period_start, period_end, COALESCE(branch_id, -1)) DO UPDATE
    SET data = EXCLUDED.data, computed_at = now(), computed_by = current_app_user_id()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE bi_report_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bi_snapshots           ENABLE ROW LEVEL SECURITY;
ALTER TABLE bi_saved_views         ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bi_reports_sel ON bi_report_definitions;
CREATE POLICY bi_reports_sel ON bi_report_definitions FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS bi_reports_wr ON bi_report_definitions;
CREATE POLICY bi_reports_wr ON bi_report_definitions FOR ALL TO authenticated
  USING (current_app_role() IN ('admin', 'company_manager'))
  WITH CHECK (current_app_role() IN ('admin', 'company_manager'));

DROP POLICY IF EXISTS bi_snap_sel ON bi_snapshots;
CREATE POLICY bi_snap_sel ON bi_snapshots FOR SELECT TO authenticated USING (is_bi_manager());
DROP POLICY IF EXISTS bi_snap_ins ON bi_snapshots;
CREATE POLICY bi_snap_ins ON bi_snapshots FOR INSERT TO authenticated WITH CHECK (is_bi_manager());

DROP POLICY IF EXISTS bi_views_sel ON bi_saved_views;
CREATE POLICY bi_views_sel ON bi_saved_views FOR SELECT TO authenticated
  USING (user_id = current_app_user_id() OR is_shared);
DROP POLICY IF EXISTS bi_views_wr ON bi_saved_views;
CREATE POLICY bi_views_wr ON bi_saved_views FOR ALL TO authenticated
  USING (user_id = current_app_user_id()) WITH CHECK (user_id = current_app_user_id());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT count(*) FROM bi_report_definitions;  -- 7 تقارير
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'bi_%';
-- 3) SELECT bi_daily_summary(CURRENT_DATE - 30, CURRENT_DATE);
-- 4) SELECT * FROM bi_branch_ranking(CURRENT_DATE - 30, CURRENT_DATE);
-- ═══════════════════════════════════════════════════════════
