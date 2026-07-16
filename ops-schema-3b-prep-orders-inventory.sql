-- ═══════════════════════════════════════════════════════════
-- وحدة التشغيل (Operations) — المرحلة 3.b
-- التحضير + الطلبات + المخزون الفرعي (لكل فرع) + الهدر
-- ═══════════════════════════════════════════════════════════
-- يعتمد هذا الملف على: ops-schema-3a-shifts.sql (is_ops_manager,
-- can_access_branch_ops, ops_shifts)، وعلى acct-schema.sql +
-- acct-schema-2e-assets.sql (acct_inventory_items/movements،
-- create_journal_for_inventory_movement، دليل الحسابات).
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) إعدادات التكامل المحاسبي لطلبات المطعم (نفس منطق الكافيه)
-- ───────────────────────────────────────────────────────────
ALTER TABLE acct_settings
  ADD COLUMN IF NOT EXISTS ops_orders_generates_journal_entry BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS ops_revenue_account_id BIGINT,
  ADD COLUMN IF NOT EXISTS ops_delivery_revenue_account_id BIGINT,
  ADD COLUMN IF NOT EXISTS ops_cash_account_id BIGINT;

UPDATE acct_settings SET
  ops_revenue_account_id          = COALESCE(ops_revenue_account_id, (SELECT id FROM acct_chart_of_accounts WHERE code = '4101')),
  ops_delivery_revenue_account_id = COALESCE(ops_delivery_revenue_account_id, (SELECT id FROM acct_chart_of_accounts WHERE code = '4103')),
  ops_cash_account_id             = COALESCE(ops_cash_account_id, (SELECT id FROM acct_chart_of_accounts WHERE code = '1101'))
WHERE id = 1;

-- السماح لمصدر قيود جديد: ops_order
ALTER TABLE acct_journal_entries DROP CONSTRAINT IF EXISTS acct_journal_entries_source_type_check;
ALTER TABLE acct_journal_entries ADD CONSTRAINT acct_journal_entries_source_type_check
  CHECK (source_type IN ('manual', 'hr_payroll', 'bill', 'invoice', 'payment', 'receipt', 'cafe_order', 'depreciation', 'closing', 'opening', 'reversal', 'ops_order'));

-- ───────────────────────────────────────────────────────────
-- 1) ops_prep_plans + ops_prep_plan_items — خطط التحضير اليومية
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_prep_plans (
  id           BIGSERIAL PRIMARY KEY,
  branch_id    BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id     BIGINT REFERENCES ops_shifts(id) ON DELETE SET NULL,
  plan_date    DATE NOT NULL,
  status       TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'confirmed', 'completed')),
  notes        TEXT,
  created_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_prep_plans_branch_date_idx ON ops_prep_plans(branch_id, plan_date DESC);

DROP TRIGGER IF EXISTS ops_prep_plans_updated_at ON ops_prep_plans;
CREATE TRIGGER ops_prep_plans_updated_at BEFORE UPDATE ON ops_prep_plans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS ops_prep_plan_items (
  id                  BIGSERIAL PRIMARY KEY,
  plan_id             BIGINT NOT NULL REFERENCES ops_prep_plans(id) ON DELETE CASCADE,
  item_id             BIGINT REFERENCES acct_inventory_items(id) ON DELETE SET NULL,
  item_name           TEXT NOT NULL,
  unit                TEXT NOT NULL DEFAULT 'unit',
  planned_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
  prepared_quantity   NUMERIC(14,3) NOT NULL DEFAULT 0,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_prep_plan_items_plan_idx ON ops_prep_plan_items(plan_id);

-- ───────────────────────────────────────────────────────────
-- 2) ops_orders + ops_order_items — طلبات المطعم (صالة/سفري/توصيل)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_orders (
  id                BIGSERIAL PRIMARY KEY,
  order_number      TEXT UNIQUE,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id          BIGINT REFERENCES ops_shifts(id) ON DELETE SET NULL,
  order_type        TEXT NOT NULL CHECK (order_type IN ('dine_in', 'takeaway', 'delivery')),
  table_number      TEXT,
  customer_name     TEXT,
  customer_phone    TEXT,
  status            TEXT NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open', 'preparing', 'ready', 'completed', 'cancelled')),
  payment_method    TEXT,
  subtotal          NUMERIC(12,2) NOT NULL DEFAULT 0,
  vat_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  completed_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ops_orders_branch_idx  ON ops_orders(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ops_orders_status_idx  ON ops_orders(status) WHERE status IN ('open', 'preparing', 'ready');

DROP TRIGGER IF EXISTS ops_orders_updated_at ON ops_orders;
CREATE TRIGGER ops_orders_updated_at BEFORE UPDATE ON ops_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION ops_assign_order_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.order_number IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM ops_orders WHERE order_number LIKE 'ORD-' || v_year || '-%';
    NEW.order_number := 'ORD-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ops_orders_assign_number ON ops_orders;
CREATE TRIGGER ops_orders_assign_number BEFORE INSERT ON ops_orders
  FOR EACH ROW EXECUTE FUNCTION ops_assign_order_number();

CREATE TABLE IF NOT EXISTS ops_order_items (
  id          BIGSERIAL PRIMARY KEY,
  order_id    BIGINT NOT NULL REFERENCES ops_orders(id) ON DELETE CASCADE,
  item_name   TEXT NOT NULL,
  quantity    NUMERIC(10,2) NOT NULL DEFAULT 1,
  unit_price  NUMERIC(10,2) NOT NULL DEFAULT 0,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_order_items_order_idx ON ops_order_items(order_id);

-- قيد محاسبي عند اكتمال الطلب — بنفس منطق قيد طلب الكافيه، يُستدعى من
-- طبقة JS (ACCT.integrations.postOpsOrderJournal) لا عبر Trigger، اتساقًا
-- مع نمط بقية عمليات التكامل المحاسبي في هذا النظام.
CREATE OR REPLACE FUNCTION create_journal_for_ops_order(p_order_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_settings RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_revenue_account_id BIGINT;
  v_vat_account_id BIGINT;
  v_net_amount NUMERIC(14,2);
BEGIN
  SELECT * INTO v_order FROM ops_orders WHERE id = p_order_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'Order % not found', p_order_id; END IF;
  IF v_order.status != 'completed' THEN RAISE EXCEPTION 'Order must be completed before generating a journal entry'; END IF;
  IF v_order.journal_entry_id IS NOT NULL THEN RETURN v_order.journal_entry_id; END IF;

  SELECT * INTO v_settings FROM acct_settings WHERE id = 1;
  IF NOT v_settings.ops_orders_generates_journal_entry THEN RETURN NULL; END IF;

  v_revenue_account_id := CASE WHEN v_order.order_type = 'delivery'
    THEN v_settings.ops_delivery_revenue_account_id ELSE v_settings.ops_revenue_account_id END;
  IF v_settings.ops_cash_account_id IS NULL OR v_revenue_account_id IS NULL THEN
    RAISE EXCEPTION 'Ops orders revenue/cash accounts are not configured in acct_settings';
  END IF;

  IF v_order.total_amount <= 0 THEN RETURN NULL; END IF;
  v_net_amount := v_order.total_amount - COALESCE(v_order.vat_amount, 0);

  SELECT id INTO v_period_id FROM acct_periods
    WHERE start_date <= COALESCE(v_order.completed_at::DATE, CURRENT_DATE) AND end_date >= COALESCE(v_order.completed_at::DATE, CURRENT_DATE)
    LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No open accounting period for date %', COALESCE(v_order.completed_at::DATE, CURRENT_DATE); END IF;

  SELECT id INTO v_vat_account_id FROM acct_chart_of_accounts WHERE code = '2104';

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-OPSORD-' || p_order_id, COALESCE(v_order.completed_at::DATE, CURRENT_DATE), v_period_id,
          'قيد طلب مطعم رقم ' || COALESCE(v_order.order_number, p_order_id::TEXT),
          'ops_order', p_order_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 1, v_settings.ops_cash_account_id, v_order.total_amount, 0, 'نقدية — بيع مطعم');
  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 2, v_revenue_account_id, 0, v_net_amount, 'إيرادات مبيعات المطعم');

  IF v_order.vat_amount > 0 AND v_vat_account_id IS NOT NULL THEN
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, 3, v_vat_account_id, 0, v_order.vat_amount, 'ضريبة القيمة المضافة - دائن');
  END IF;

  UPDATE ops_orders SET journal_entry_id = v_entry_id WHERE id = p_order_id;
  RETURN v_entry_id;
END;
$$;

-- ───────────────────────────────────────────────────────────
-- 3) ops_branch_inventory_levels — مستوى المخزون الفعلي في كل فرع
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_branch_inventory_levels (
  id                BIGSERIAL PRIMARY KEY,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  item_id           BIGINT NOT NULL REFERENCES acct_inventory_items(id) ON DELETE CASCADE,
  quantity_on_hand  NUMERIC(14,3) NOT NULL DEFAULT 0,
  reorder_level     NUMERIC(14,3) NOT NULL DEFAULT 0,
  updated_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT ops_branch_inv_unique UNIQUE (branch_id, item_id)
);

CREATE INDEX IF NOT EXISTS ops_branch_inv_branch_idx ON ops_branch_inventory_levels(branch_id);
CREATE INDEX IF NOT EXISTS ops_branch_inv_low_idx    ON ops_branch_inventory_levels(branch_id) WHERE quantity_on_hand <= reorder_level;

DROP TRIGGER IF EXISTS ops_branch_inv_updated_at ON ops_branch_inventory_levels;
CREATE TRIGGER ops_branch_inv_updated_at BEFORE UPDATE ON ops_branch_inventory_levels
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 4) ops_stock_transfers + ops_stock_transfer_items — نقل بين الفروع
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_stock_transfers (
  id              BIGSERIAL PRIMARY KEY,
  from_branch_id  BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  to_branch_id    BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  transfer_date   DATE NOT NULL DEFAULT CURRENT_DATE,
  status          TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'in_transit', 'received', 'cancelled')),
  notes           TEXT,
  requested_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,
  received_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT ops_stock_transfer_diff_branch CHECK (from_branch_id != to_branch_id)
);

CREATE INDEX IF NOT EXISTS ops_stock_transfers_from_idx ON ops_stock_transfers(from_branch_id);
CREATE INDEX IF NOT EXISTS ops_stock_transfers_to_idx   ON ops_stock_transfers(to_branch_id);

DROP TRIGGER IF EXISTS ops_stock_transfers_updated_at ON ops_stock_transfers;
CREATE TRIGGER ops_stock_transfers_updated_at BEFORE UPDATE ON ops_stock_transfers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS ops_stock_transfer_items (
  id            BIGSERIAL PRIMARY KEY,
  transfer_id   BIGINT NOT NULL REFERENCES ops_stock_transfers(id) ON DELETE CASCADE,
  item_id       BIGINT NOT NULL REFERENCES acct_inventory_items(id) ON DELETE CASCADE,
  quantity      NUMERIC(14,3) NOT NULL CHECK (quantity > 0),
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_stock_transfer_items_transfer_idx ON ops_stock_transfer_items(transfer_id);

-- عند تأكيد الاستلام: خصم من مخزون الفرع المُرسِل وإضافة لمخزون الفرع المُستقبِل
CREATE OR REPLACE FUNCTION ops_apply_stock_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
BEGIN
  IF NEW.status = 'received' AND OLD.status IS DISTINCT FROM 'received' THEN
    FOR v_item IN SELECT * FROM ops_stock_transfer_items WHERE transfer_id = NEW.id LOOP
      INSERT INTO ops_branch_inventory_levels (branch_id, item_id, quantity_on_hand)
        VALUES (NEW.from_branch_id, v_item.item_id, -v_item.quantity)
        ON CONFLICT (branch_id, item_id) DO UPDATE
        SET quantity_on_hand = ops_branch_inventory_levels.quantity_on_hand - v_item.quantity;

      INSERT INTO ops_branch_inventory_levels (branch_id, item_id, quantity_on_hand)
        VALUES (NEW.to_branch_id, v_item.item_id, v_item.quantity)
        ON CONFLICT (branch_id, item_id) DO UPDATE
        SET quantity_on_hand = ops_branch_inventory_levels.quantity_on_hand + v_item.quantity;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ops_stock_transfers_apply ON ops_stock_transfers;
CREATE TRIGGER ops_stock_transfers_apply AFTER UPDATE ON ops_stock_transfers
  FOR EACH ROW EXECUTE FUNCTION ops_apply_stock_transfer();

-- ───────────────────────────────────────────────────────────
-- 5) ops_waste_records — سجل الهدر، مرتبط بحركة مخزون محاسبية
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ops_waste_records (
  id            BIGSERIAL PRIMARY KEY,
  branch_id     BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id      BIGINT REFERENCES ops_shifts(id) ON DELETE SET NULL,
  item_id       BIGINT NOT NULL REFERENCES acct_inventory_items(id) ON DELETE CASCADE,
  quantity      NUMERIC(14,3) NOT NULL CHECK (quantity > 0),
  reason        TEXT NOT NULL CHECK (reason IN ('spoilage', 'expired', 'dropped', 'other')),
  notes         TEXT,
  movement_id   BIGINT REFERENCES acct_inventory_movements(id) ON DELETE SET NULL,
  recorded_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_waste_records_branch_idx ON ops_waste_records(branch_id, created_at DESC);

-- خصم الكمية المُهدرة من مخزون الفرع (المخزون العام acct_inventory_items
-- يُخصَم بالفعل عبر create_journal_for_inventory_movement/acct_apply_inventory_movement
-- التي تستدعيها طبقة JS عند تسجيل الهدر — هذا Trigger يخص مخزون الفرع فقط).
CREATE OR REPLACE FUNCTION ops_apply_waste_to_branch_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO ops_branch_inventory_levels (branch_id, item_id, quantity_on_hand)
    VALUES (NEW.branch_id, NEW.item_id, -NEW.quantity)
    ON CONFLICT (branch_id, item_id) DO UPDATE
    SET quantity_on_hand = ops_branch_inventory_levels.quantity_on_hand - NEW.quantity;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ops_waste_records_apply ON ops_waste_records;
CREATE TRIGGER ops_waste_records_apply AFTER INSERT ON ops_waste_records
  FOR EACH ROW EXECUTE FUNCTION ops_apply_waste_to_branch_inventory();

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE ops_prep_plans              ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_prep_plan_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_orders                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_order_items             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_branch_inventory_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_stock_transfers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_stock_transfer_items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops_waste_records           ENABLE ROW LEVEL SECURITY;

-- ops_prep_plans
DROP POLICY IF EXISTS ops_prep_plans_select ON ops_prep_plans;
CREATE POLICY ops_prep_plans_select ON ops_prep_plans FOR SELECT
  USING (can_access_branch_ops(branch_id));
DROP POLICY IF EXISTS ops_prep_plans_write ON ops_prep_plans;
CREATE POLICY ops_prep_plans_write ON ops_prep_plans FOR ALL
  USING (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_prep_plans.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))
  WITH CHECK (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_prep_plans.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')));

-- ops_prep_plan_items: يتبع فرع الخطة
DROP POLICY IF EXISTS ops_prep_plan_items_select ON ops_prep_plan_items;
CREATE POLICY ops_prep_plan_items_select ON ops_prep_plan_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_prep_plans p WHERE p.id = ops_prep_plan_items.plan_id AND can_access_branch_ops(p.branch_id)));
DROP POLICY IF EXISTS ops_prep_plan_items_write ON ops_prep_plan_items;
CREATE POLICY ops_prep_plan_items_write ON ops_prep_plan_items FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_prep_plans p WHERE p.id = ops_prep_plan_items.plan_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = p.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_prep_plans p WHERE p.id = ops_prep_plan_items.plan_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = p.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))));

-- ops_orders
DROP POLICY IF EXISTS ops_orders_select ON ops_orders;
CREATE POLICY ops_orders_select ON ops_orders FOR SELECT
  USING (can_access_branch_ops(branch_id));
DROP POLICY IF EXISTS ops_orders_write ON ops_orders;
CREATE POLICY ops_orders_write ON ops_orders FOR ALL
  USING (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_orders.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))
  WITH CHECK (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_orders.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')));

-- ops_order_items: يتبع فرع الطلب
DROP POLICY IF EXISTS ops_order_items_select ON ops_order_items;
CREATE POLICY ops_order_items_select ON ops_order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_orders o WHERE o.id = ops_order_items.order_id AND can_access_branch_ops(o.branch_id)));
DROP POLICY IF EXISTS ops_order_items_write ON ops_order_items;
CREATE POLICY ops_order_items_write ON ops_order_items FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_orders o WHERE o.id = ops_order_items.order_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = o.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_orders o WHERE o.id = ops_order_items.order_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = o.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))));

-- ops_branch_inventory_levels: قراءة لأهل الفرع، تعديل لمدير التشغيل فقط (التعديل يتم عبر triggers أصلاً)
DROP POLICY IF EXISTS ops_branch_inv_select ON ops_branch_inventory_levels;
CREATE POLICY ops_branch_inv_select ON ops_branch_inventory_levels FOR SELECT
  USING (can_access_branch_ops(branch_id));
DROP POLICY IF EXISTS ops_branch_inv_write ON ops_branch_inventory_levels;
CREATE POLICY ops_branch_inv_write ON ops_branch_inventory_levels FOR ALL
  USING (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_branch_inventory_levels.branch_id AND u.role IN ('branch_manager', 'deputy_manager')))
  WITH CHECK (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_branch_inventory_levels.branch_id AND u.role IN ('branch_manager', 'deputy_manager')));

-- ops_stock_transfers: مرئي لفرعي الإرسال والاستقبال
DROP POLICY IF EXISTS ops_stock_transfers_select ON ops_stock_transfers;
CREATE POLICY ops_stock_transfers_select ON ops_stock_transfers FOR SELECT
  USING (can_access_branch_ops(from_branch_id) OR can_access_branch_ops(to_branch_id));
DROP POLICY IF EXISTS ops_stock_transfers_write ON ops_stock_transfers;
CREATE POLICY ops_stock_transfers_write ON ops_stock_transfers FOR ALL
  USING (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id IN (ops_stock_transfers.from_branch_id, ops_stock_transfers.to_branch_id) AND u.role IN ('branch_manager', 'deputy_manager')))
  WITH CHECK (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id IN (ops_stock_transfers.from_branch_id, ops_stock_transfers.to_branch_id) AND u.role IN ('branch_manager', 'deputy_manager')));

-- ops_stock_transfer_items: يتبع صلاحية التحويل الأصلي
DROP POLICY IF EXISTS ops_stock_transfer_items_select ON ops_stock_transfer_items;
CREATE POLICY ops_stock_transfer_items_select ON ops_stock_transfer_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM ops_stock_transfers t WHERE t.id = ops_stock_transfer_items.transfer_id
           AND (can_access_branch_ops(t.from_branch_id) OR can_access_branch_ops(t.to_branch_id))));
DROP POLICY IF EXISTS ops_stock_transfer_items_write ON ops_stock_transfer_items;
CREATE POLICY ops_stock_transfer_items_write ON ops_stock_transfer_items FOR ALL
  USING (EXISTS (SELECT 1 FROM ops_stock_transfers t WHERE t.id = ops_stock_transfer_items.transfer_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id IN (t.from_branch_id, t.to_branch_id) AND u.role IN ('branch_manager', 'deputy_manager')))))
  WITH CHECK (EXISTS (SELECT 1 FROM ops_stock_transfers t WHERE t.id = ops_stock_transfer_items.transfer_id AND (is_ops_manager() OR EXISTS (
           SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id IN (t.from_branch_id, t.to_branch_id) AND u.role IN ('branch_manager', 'deputy_manager')))));

-- ops_waste_records
DROP POLICY IF EXISTS ops_waste_records_select ON ops_waste_records;
CREATE POLICY ops_waste_records_select ON ops_waste_records FOR SELECT
  USING (can_access_branch_ops(branch_id));
DROP POLICY IF EXISTS ops_waste_records_write ON ops_waste_records;
CREATE POLICY ops_waste_records_write ON ops_waste_records FOR ALL
  USING (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_waste_records.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')))
  WITH CHECK (is_ops_manager() OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
           AND u.branch_id = ops_waste_records.branch_id AND u.role IN ('branch_manager', 'deputy_manager', 'employee')));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ (Post-migration checklist):
-- 1) SELECT * FROM ops_prep_plans LIMIT 1;
-- 2) SELECT * FROM ops_orders LIMIT 1;
-- 3) SELECT * FROM ops_branch_inventory_levels LIMIT 1;
-- 4) SELECT * FROM ops_stock_transfers LIMIT 1;
-- 5) SELECT * FROM ops_waste_records LIMIT 1;
-- 6) SELECT ops_revenue_account_id, ops_delivery_revenue_account_id,
--    ops_cash_account_id FROM acct_settings WHERE id = 1; -- يجب ألا تكون NULL
-- ═══════════════════════════════════════════════════════════
