-- ═══════════════════════════════════════════════════════════
-- المشتريات Procurement — Phase 1 (Wave 2 Module 26)
-- ═══════════════════════════════════════════════════════════
-- 6 جداول: طلبات الشراء + بنودها + أوامر الشراء + بنودها +
-- إيصالات الاستلام + بنودها
-- + دالة proc_receive_goods() تُتمّ الاستلام في transaction واحد:
--   خصم/زيادة المخزون + إنشاء فاتورة مورد AP + تحديث حالة الأمر
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير المشتريات
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_procurement_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'finance_manager', 'procurement_manager');
$$;

-- السماح بمصدر قيود جديد: proc_grn (تسجيل استلام في AP)
ALTER TABLE acct_journal_entries DROP CONSTRAINT IF EXISTS acct_journal_entries_source_type_check;
ALTER TABLE acct_journal_entries ADD CONSTRAINT acct_journal_entries_source_type_check
  CHECK (source_type IN (
    'manual', 'hr_payroll', 'bill', 'invoice', 'payment', 'receipt',
    'cafe_order', 'depreciation', 'closing', 'opening', 'reversal',
    'ops_order', 'pay_settlement', 'pos_sale', 'proc_grn'
  ));

-- ───────────────────────────────────────────────────────────
-- 1) proc_requisitions — طلبات الشراء الداخلية
--    DECISION: الفرع/القسم يقدم طلب. لازم يوافق مدير قبل التحويل لأمر شراء.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_requisitions (
  id                BIGSERIAL PRIMARY KEY,
  requisition_no    TEXT UNIQUE,
  branch_id         BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  department_id     BIGINT REFERENCES departments(id) ON DELETE SET NULL,
  requested_by      BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  priority          TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  needed_by_date    DATE,
  status            TEXT NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'converted', 'cancelled')),
  approved_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_req_branch_idx    ON proc_requisitions(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS proc_req_status_idx    ON proc_requisitions(status) WHERE status IN ('submitted', 'approved');
CREATE INDEX IF NOT EXISTS proc_req_requester_idx ON proc_requisitions(requested_by, created_at DESC);

DROP TRIGGER IF EXISTS proc_req_updated_at ON proc_requisitions;
CREATE TRIGGER proc_req_updated_at BEFORE UPDATE ON proc_requisitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION proc_assign_requisition_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.requisition_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM proc_requisitions WHERE requisition_no LIKE 'PR-' || v_year || '-%';
    NEW.requisition_no := 'PR-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proc_req_assign_no ON proc_requisitions;
CREATE TRIGGER proc_req_assign_no BEFORE INSERT ON proc_requisitions
  FOR EACH ROW EXECUTE FUNCTION proc_assign_requisition_no();

-- ───────────────────────────────────────────────────────────
-- 2) proc_requisition_items — بنود طلبات الشراء
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_requisition_items (
  id                  BIGSERIAL PRIMARY KEY,
  requisition_id      BIGINT NOT NULL REFERENCES proc_requisitions(id) ON DELETE CASCADE,
  inventory_item_id   BIGINT REFERENCES acct_inventory_items(id) ON DELETE SET NULL,
  item_name           TEXT NOT NULL,
  quantity            NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  unit                TEXT NOT NULL DEFAULT 'unit',
  estimated_price     NUMERIC(12,2),
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_req_items_req_idx ON proc_requisition_items(requisition_id);

-- ───────────────────────────────────────────────────────────
-- 3) proc_purchase_orders — أوامر الشراء للموردين
--    DECISION: نستخدم acct_vendors (موجود من AP). received_qty يتحدّث
--    من داخل دالة proc_receive_goods لضمان الاتساق.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_purchase_orders (
  id                  BIGSERIAL PRIMARY KEY,
  po_no               TEXT UNIQUE,
  vendor_id           BIGINT NOT NULL REFERENCES acct_vendors(id) ON DELETE RESTRICT,
  branch_id           BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  requisition_id      BIGINT REFERENCES proc_requisitions(id) ON DELETE SET NULL,
  order_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_delivery   DATE,
  status              TEXT NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft', 'sent', 'confirmed', 'partial', 'received', 'closed', 'cancelled')),
  subtotal            NUMERIC(12,2) NOT NULL DEFAULT 0,
  discount_amount     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  vat_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  payment_terms       TEXT,
  delivery_address    TEXT,
  approved_by         BIGINT REFERENCES users(id) ON DELETE SET NULL,
  approved_at         TIMESTAMPTZ,
  sent_at             TIMESTAMPTZ,
  created_by          BIGINT REFERENCES users(id) ON DELETE SET NULL,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_po_vendor_idx  ON proc_purchase_orders(vendor_id, order_date DESC);
CREATE INDEX IF NOT EXISTS proc_po_branch_idx  ON proc_purchase_orders(branch_id, order_date DESC);
CREATE INDEX IF NOT EXISTS proc_po_status_idx  ON proc_purchase_orders(status) WHERE status IN ('sent', 'confirmed', 'partial');

DROP TRIGGER IF EXISTS proc_po_updated_at ON proc_purchase_orders;
CREATE TRIGGER proc_po_updated_at BEFORE UPDATE ON proc_purchase_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION proc_assign_po_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.po_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM proc_purchase_orders WHERE po_no LIKE 'PO-' || v_year || '-%';
    NEW.po_no := 'PO-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proc_po_assign_no ON proc_purchase_orders;
CREATE TRIGGER proc_po_assign_no BEFORE INSERT ON proc_purchase_orders
  FOR EACH ROW EXECUTE FUNCTION proc_assign_po_no();

-- ───────────────────────────────────────────────────────────
-- 4) proc_purchase_order_items — بنود أوامر الشراء
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_purchase_order_items (
  id                    BIGSERIAL PRIMARY KEY,
  po_id                 BIGINT NOT NULL REFERENCES proc_purchase_orders(id) ON DELETE CASCADE,
  requisition_item_id   BIGINT REFERENCES proc_requisition_items(id) ON DELETE SET NULL,
  inventory_item_id     BIGINT REFERENCES acct_inventory_items(id) ON DELETE SET NULL,
  item_name             TEXT NOT NULL,
  quantity              NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  received_quantity     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),
  unit                  TEXT NOT NULL DEFAULT 'unit',
  unit_price            NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  discount_amount       NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  line_total            NUMERIC(12,2) NOT NULL DEFAULT 0,
  notes                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_po_items_po_idx ON proc_purchase_order_items(po_id);

-- ───────────────────────────────────────────────────────────
-- 5) proc_goods_receipts — إيصالات الاستلام (GRN)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_goods_receipts (
  id                  BIGSERIAL PRIMARY KEY,
  grn_no              TEXT UNIQUE,
  po_id               BIGINT NOT NULL REFERENCES proc_purchase_orders(id) ON DELETE RESTRICT,
  branch_id           BIGINT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  received_by         BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  received_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  vendor_delivery_no  TEXT,
  status              TEXT NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft', 'received', 'cancelled')),
  bill_id             BIGINT REFERENCES acct_bills(id) ON DELETE SET NULL,
  journal_entry_id    BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_grn_po_idx      ON proc_goods_receipts(po_id);
CREATE INDEX IF NOT EXISTS proc_grn_branch_idx  ON proc_goods_receipts(branch_id, received_at DESC);
CREATE INDEX IF NOT EXISTS proc_grn_status_idx  ON proc_goods_receipts(status);

DROP TRIGGER IF EXISTS proc_grn_updated_at ON proc_goods_receipts;
CREATE TRIGGER proc_grn_updated_at BEFORE UPDATE ON proc_goods_receipts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION proc_assign_grn_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  INT;
BEGIN
  IF NEW.grn_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM proc_goods_receipts WHERE grn_no LIKE 'GRN-' || v_year || '-%';
    NEW.grn_no := 'GRN-' || v_year || '-' || LPAD(v_seq::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proc_grn_assign_no ON proc_goods_receipts;
CREATE TRIGGER proc_grn_assign_no BEFORE INSERT ON proc_goods_receipts
  FOR EACH ROW EXECUTE FUNCTION proc_assign_grn_no();

-- ───────────────────────────────────────────────────────────
-- 6) proc_goods_receipt_items — بنود إيصالات الاستلام
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS proc_goods_receipt_items (
  id                    BIGSERIAL PRIMARY KEY,
  grn_id                BIGINT NOT NULL REFERENCES proc_goods_receipts(id) ON DELETE CASCADE,
  po_item_id            BIGINT NOT NULL REFERENCES proc_purchase_order_items(id) ON DELETE RESTRICT,
  quantity_received     NUMERIC(12,2) NOT NULL CHECK (quantity_received > 0),
  quality_status        TEXT NOT NULL DEFAULT 'accepted'
                         CHECK (quality_status IN ('accepted', 'rejected', 'partial')),
  rejection_reason      TEXT,
  batch_ref             TEXT,
  expiry_date           DATE,
  notes                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS proc_grn_items_grn_idx ON proc_goods_receipt_items(grn_id);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دالة إتمام استلام البضاعة (atomic)
-- ═══════════════════════════════════════════════════════════
-- تفحص الـ GRN، تحدّث received_quantity في بنود PO، تنشئ حركات
-- مخزون IN، تنشئ فاتورة مورد AP، وتحدّث حالة PO (partial/received)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION proc_receive_goods(p_grn_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grn         RECORD;
  v_po          RECORD;
  v_bill_id     BIGINT;
  v_item        RECORD;
  v_po_item     RECORD;
  v_bill_total  NUMERIC := 0;
  v_bill_vat    NUMERIC := 0;
  v_line_total  NUMERIC;
  v_line_no     INT := 0;
  v_all_full    BOOLEAN := TRUE;
  v_expense_acc BIGINT;
BEGIN
  SELECT * INTO v_grn FROM proc_goods_receipts WHERE id = p_grn_id;
  IF v_grn IS NULL THEN RAISE EXCEPTION 'إيصال الاستلام غير موجود'; END IF;
  IF v_grn.status <> 'draft' THEN RAISE EXCEPTION 'إيصال الاستلام مُعتمَد بالفعل'; END IF;

  SELECT * INTO v_po FROM proc_purchase_orders WHERE id = v_grn.po_id;
  IF v_po IS NULL THEN RAISE EXCEPTION 'أمر الشراء غير موجود'; END IF;
  IF v_po.status IN ('cancelled', 'closed') THEN
    RAISE EXCEPTION 'لا يمكن الاستلام على أمر شراء % — الحالة: %', v_po.po_no, v_po.status;
  END IF;

  -- حساب المصروف الافتراضي (تكلفة المواد الغذائية 5101)
  SELECT id INTO v_expense_acc FROM acct_chart_of_accounts WHERE code = '5101' LIMIT 1;
  IF v_expense_acc IS NULL THEN
    RAISE EXCEPTION 'حساب المصروف الافتراضي (5101 تكلفة المواد الغذائية) غير موجود في دليل الحسابات';
  END IF;

  -- (1) تحقق أن أي بند مقبول لا يتجاوز الكمية المتبقية في الأمر
  FOR v_item IN SELECT * FROM proc_goods_receipt_items WHERE grn_id = p_grn_id LOOP
    SELECT * INTO v_po_item FROM proc_purchase_order_items WHERE id = v_item.po_item_id;
    IF v_item.quality_status <> 'rejected' AND
       (v_po_item.received_quantity + v_item.quantity_received) > v_po_item.quantity THEN
      RAISE EXCEPTION 'الكمية المستلمة (%.2f) تتجاوز المتبقي على البند "%"', v_item.quantity_received, v_po_item.item_name;
    END IF;
  END LOOP;

  -- (2) إنشاء فاتورة مورد AP بحالة draft
  --     acct_bills.total محسوب تلقائيًا (GENERATED)، subtotal + vat_amount فقط
  INSERT INTO acct_bills (
    bill_no, vendor_id, bill_date, due_date, subtotal, vat_amount,
    status, notes, created_by
  ) VALUES (
    'BILL-' || v_grn.grn_no,
    v_po.vendor_id,
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '30 days',
    0, 0,
    'draft',
    'فاتورة استلام تلقائية من إيصال ' || v_grn.grn_no,
    current_app_user_id()
  ) RETURNING id INTO v_bill_id;

  -- (3) لكل بند مقبول: حدّث received_quantity + احسب المجاميع
  FOR v_item IN
    SELECT gi.*, poi.item_name, poi.inventory_item_id, poi.unit, poi.unit_price, poi.discount_amount
    FROM proc_goods_receipt_items gi
    JOIN proc_purchase_order_items poi ON poi.id = gi.po_item_id
    WHERE gi.grn_id = p_grn_id AND gi.quality_status <> 'rejected'
  LOOP
    v_line_total := (v_item.quantity_received * v_item.unit_price) - COALESCE(v_item.discount_amount, 0);
    v_bill_total := v_bill_total + v_line_total;
    v_line_no    := v_line_no + 1;

    -- تحديث الكمية المستلمة في بند PO
    UPDATE proc_purchase_order_items
    SET received_quantity = received_quantity + v_item.quantity_received
    WHERE id = v_item.po_item_id;

    -- بند فاتورة مورد (acct_bill_lines.line_total محسوب تلقائيًا)
    INSERT INTO acct_bill_lines (bill_id, line_no, description, quantity, unit_price, account_id, vat_applicable)
    VALUES (v_bill_id, v_line_no, v_item.item_name, v_item.quantity_received, v_item.unit_price, v_expense_acc, TRUE);

    -- حركة مخزون IN (لو الصنف مرتبط بمخزون)
    IF v_item.inventory_item_id IS NOT NULL THEN
      INSERT INTO acct_inventory_movements (
        item_id, movement_date, type, quantity, unit_cost, reference, created_by
      ) VALUES (
        v_item.inventory_item_id,
        CURRENT_DATE,
        'in',
        v_item.quantity_received,
        v_item.unit_price,
        v_grn.grn_no || ' / ' || v_po.po_no,
        current_app_user_id()
      );
    END IF;
  END LOOP;

  -- (4) حدّث فاتورة المورد بالمجاميع (total محسوب تلقائيًا)
  v_bill_vat := ROUND(v_bill_total * 0.15, 2);
  UPDATE acct_bills
  SET subtotal = v_bill_total, vat_amount = v_bill_vat
  WHERE id = v_bill_id;

  -- (5) حدّث GRN
  UPDATE proc_goods_receipts
  SET status = 'received', bill_id = v_bill_id
  WHERE id = p_grn_id;

  -- (6) تحديث حالة PO: partial أو received
  FOR v_po_item IN SELECT * FROM proc_purchase_order_items WHERE po_id = v_po.id LOOP
    IF v_po_item.received_quantity < v_po_item.quantity THEN
      v_all_full := FALSE;
      EXIT;
    END IF;
  END LOOP;

  UPDATE proc_purchase_orders
  SET status = CASE WHEN v_all_full THEN 'received' ELSE 'partial' END
  WHERE id = v_po.id;

  RETURN v_bill_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE proc_requisitions              ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_requisition_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_purchase_orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_purchase_order_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_goods_receipts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE proc_goods_receipt_items       ENABLE ROW LEVEL SECURITY;

-- طلبات الشراء: الطالب يشوف طلبه، مدير المشتريات والمدراء يشوفون الكل
DROP POLICY IF EXISTS proc_req_sel ON proc_requisitions;
CREATE POLICY proc_req_sel ON proc_requisitions FOR SELECT TO authenticated USING (
  requested_by = current_app_user_id()
  OR is_procurement_manager()
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
             AND u.branch_id = proc_requisitions.branch_id
             AND u.role IN ('branch_manager', 'deputy_manager'))
);
DROP POLICY IF EXISTS proc_req_ins ON proc_requisitions;
CREATE POLICY proc_req_ins ON proc_requisitions FOR INSERT TO authenticated
  WITH CHECK (requested_by = current_app_user_id());
DROP POLICY IF EXISTS proc_req_upd ON proc_requisitions;
CREATE POLICY proc_req_upd ON proc_requisitions FOR UPDATE TO authenticated USING (
  (requested_by = current_app_user_id() AND status = 'draft')
  OR is_procurement_manager()
);

-- بنود طلبات الشراء: يتبعن الطلب الأم
DROP POLICY IF EXISTS proc_req_items_sel ON proc_requisition_items;
CREATE POLICY proc_req_items_sel ON proc_requisition_items FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM proc_requisitions r WHERE r.id = proc_requisition_items.requisition_id
          AND (r.requested_by = current_app_user_id() OR is_procurement_manager()))
);
DROP POLICY IF EXISTS proc_req_items_wr ON proc_requisition_items;
CREATE POLICY proc_req_items_wr ON proc_requisition_items FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM proc_requisitions r WHERE r.id = proc_requisition_items.requisition_id
          AND ((r.requested_by = current_app_user_id() AND r.status = 'draft')
               OR is_procurement_manager()))
) WITH CHECK (
  EXISTS (SELECT 1 FROM proc_requisitions r WHERE r.id = proc_requisition_items.requisition_id
          AND ((r.requested_by = current_app_user_id() AND r.status = 'draft')
               OR is_procurement_manager()))
);

-- أوامر الشراء: قراءة لمدير المشتريات + المحاسبة، كتابة لمدير المشتريات
DROP POLICY IF EXISTS proc_po_sel ON proc_purchase_orders;
CREATE POLICY proc_po_sel ON proc_purchase_orders FOR SELECT TO authenticated USING (
  is_procurement_manager() OR current_app_role() IN ('finance_manager', 'ap_accountant', 'gl_accountant')
);
DROP POLICY IF EXISTS proc_po_wr ON proc_purchase_orders;
CREATE POLICY proc_po_wr ON proc_purchase_orders FOR ALL TO authenticated
  USING (is_procurement_manager()) WITH CHECK (is_procurement_manager());

-- بنود أوامر الشراء: نفس صلاحية الأم
DROP POLICY IF EXISTS proc_po_items_sel ON proc_purchase_order_items;
CREATE POLICY proc_po_items_sel ON proc_purchase_order_items FOR SELECT TO authenticated USING (
  is_procurement_manager() OR current_app_role() IN ('finance_manager', 'ap_accountant', 'gl_accountant')
);
DROP POLICY IF EXISTS proc_po_items_wr ON proc_purchase_order_items;
CREATE POLICY proc_po_items_wr ON proc_purchase_order_items FOR ALL TO authenticated
  USING (is_procurement_manager()) WITH CHECK (is_procurement_manager());

-- إيصالات الاستلام: موظفي الفرع يستلمون، مدير المشتريات يشوف الكل
DROP POLICY IF EXISTS proc_grn_sel ON proc_goods_receipts;
CREATE POLICY proc_grn_sel ON proc_goods_receipts FOR SELECT TO authenticated USING (
  is_procurement_manager()
  OR received_by = current_app_user_id()
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = proc_goods_receipts.branch_id)
  OR current_app_role() IN ('finance_manager', 'ap_accountant')
);
DROP POLICY IF EXISTS proc_grn_ins ON proc_goods_receipts;
CREATE POLICY proc_grn_ins ON proc_goods_receipts FOR INSERT TO authenticated WITH CHECK (
  received_by = current_app_user_id()
  AND (is_procurement_manager()
       OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = proc_goods_receipts.branch_id))
);
DROP POLICY IF EXISTS proc_grn_upd ON proc_goods_receipts;
CREATE POLICY proc_grn_upd ON proc_goods_receipts FOR UPDATE TO authenticated USING (
  is_procurement_manager() OR (received_by = current_app_user_id() AND status = 'draft')
);

-- بنود إيصالات الاستلام: يتبعن الأم
DROP POLICY IF EXISTS proc_grn_items_sel ON proc_goods_receipt_items;
CREATE POLICY proc_grn_items_sel ON proc_goods_receipt_items FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM proc_goods_receipts g WHERE g.id = proc_goods_receipt_items.grn_id
          AND (is_procurement_manager() OR g.received_by = current_app_user_id()
               OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = g.branch_id)))
);
DROP POLICY IF EXISTS proc_grn_items_wr ON proc_goods_receipt_items;
CREATE POLICY proc_grn_items_wr ON proc_goods_receipt_items FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM proc_goods_receipts g WHERE g.id = proc_goods_receipt_items.grn_id
          AND g.status = 'draft'
          AND (is_procurement_manager() OR g.received_by = current_app_user_id()))
) WITH CHECK (
  EXISTS (SELECT 1 FROM proc_goods_receipts g WHERE g.id = proc_goods_receipt_items.grn_id
          AND g.status = 'draft'
          AND (is_procurement_manager() OR g.received_by = current_app_user_id()))
);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT relname FROM pg_class WHERE relname LIKE 'proc_%';
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'proc_%';
-- 3) SELECT conname FROM pg_constraint WHERE conname = 'acct_journal_entries_source_type_check';
--    -- يجب أن يشمل 'proc_grn' الآن
-- ═══════════════════════════════════════════════════════════
