-- ═══════════════════════════════════════════════════════════════════════════
-- ACCOUNTING MODULE — Schema v1.0 (Phase 2.e — Fixed Assets + Depreciation + Inventory)
-- Date: 2026-07-16
-- Target: Supabase Postgres (apply via SQL Editor as a single script)
-- Scope: Fixed assets (migrated from branch_assets where a purchase cost exists),
--        straight-line depreciation schedule + monthly posting function,
--        inventory items + movements with journal entries for stock-out/adjustment.
-- Prerequisites: acct-schema.sql, 2b, 2c, 2d must already be applied.
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) acct_fixed_assets — migrated from branch_assets rows that have a cost
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_fixed_assets (
  id                        BIGSERIAL PRIMARY KEY,
  asset_no                  TEXT UNIQUE,
  name                      TEXT NOT NULL,
  category                  TEXT,
  branch_id                 BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  cost_center_id            BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  purchase_date             DATE NOT NULL DEFAULT CURRENT_DATE,
  cost                      NUMERIC(14,2) NOT NULL CHECK (cost >= 0),
  salvage_value             NUMERIC(14,2) NOT NULL DEFAULT 0,
  useful_life_months        INT NOT NULL DEFAULT 60 CHECK (useful_life_months > 0),
  depreciation_method       TEXT NOT NULL DEFAULT 'straight_line' CHECK (depreciation_method = 'straight_line'),
  coa_asset_account_id            BIGINT REFERENCES acct_chart_of_accounts(id) ON DELETE SET NULL,
  coa_accumulated_depreciation_id BIGINT REFERENCES acct_chart_of_accounts(id) ON DELETE SET NULL,
  status                    TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disposed')),
  disposal_date             DATE,
  disposal_proceeds         NUMERIC(14,2),
  legacy_branch_asset_id    BIGINT UNIQUE REFERENCES branch_assets(id) ON DELETE SET NULL,
  notes                     TEXT,
  created_by                BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at                TIMESTAMPTZ DEFAULT now(),
  updated_at                TIMESTAMPTZ DEFAULT now(),
  deleted_at                TIMESTAMPTZ,
  CONSTRAINT acct_fa_salvage_check CHECK (salvage_value <= cost)
);

CREATE INDEX IF NOT EXISTS acct_fa_branch_idx ON acct_fixed_assets(branch_id);
CREATE INDEX IF NOT EXISTS acct_fa_status_idx ON acct_fixed_assets(status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS acct_fa_legacy_idx ON acct_fixed_assets(legacy_branch_asset_id);

DROP TRIGGER IF EXISTS acct_fa_updated_at ON acct_fixed_assets;
CREATE TRIGGER acct_fa_updated_at BEFORE UPDATE ON acct_fixed_assets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION acct_assign_asset_no()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.asset_no IS NULL THEN NEW.asset_no := 'FA-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_fa_assign_no ON acct_fixed_assets;
CREATE TRIGGER acct_fa_assign_no BEFORE INSERT ON acct_fixed_assets
  FOR EACH ROW EXECUTE FUNCTION acct_assign_asset_no();

-- One-time migration: branch_assets rows that recorded a purchase cost become
-- fixed assets (default 60-month useful life — adjust per row afterwards from the UI).
-- Category maps to the matching COA pair seeded in Phase 2.a; falls back to
-- Furniture (1240/1241) when the category text doesn't match a known bucket.
INSERT INTO acct_fixed_assets (
  name, category, branch_id, purchase_date, cost, useful_life_months,
  coa_asset_account_id, coa_accumulated_depreciation_id, legacy_branch_asset_id, notes
)
SELECT
  ba.item_name,
  ba.category,
  ba.branch_id,
  COALESCE(ba.purchase_date, CURRENT_DATE),
  ba.purchase_cost,
  60,
  (SELECT id FROM acct_chart_of_accounts WHERE code =
    CASE
      WHEN ba.category ILIKE '%مطبخ%' OR ba.category ILIKE '%kitchen%' THEN '1230'
      WHEN ba.category ILIKE '%سيار%' OR ba.category ILIKE '%vehicle%' THEN '1220'
      WHEN ba.category ILIKE '%كمبيوتر%' OR ba.category ILIKE '%it%' OR ba.category ILIKE '%حاسوب%' THEN '1250'
      ELSE '1240'
    END),
  (SELECT id FROM acct_chart_of_accounts WHERE code =
    CASE
      WHEN ba.category ILIKE '%مطبخ%' OR ba.category ILIKE '%kitchen%' THEN '1231'
      WHEN ba.category ILIKE '%سيار%' OR ba.category ILIKE '%vehicle%' THEN '1221'
      WHEN ba.category ILIKE '%كمبيوتر%' OR ba.category ILIKE '%it%' OR ba.category ILIKE '%حاسوب%' THEN '1251'
      ELSE '1241'
    END),
  ba.id,
  'مُرحَّل تلقائيًا من جرد أصول الفروع — راجع مدة الإهلاك (افتراضيًا 60 شهرًا)'
FROM branch_assets ba
WHERE ba.purchase_cost IS NOT NULL AND ba.purchase_cost > 0
ON CONFLICT (legacy_branch_asset_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) acct_asset_depreciation_schedule — one row per (asset, year, month)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_asset_depreciation_schedule (
  id                BIGSERIAL PRIMARY KEY,
  asset_id          BIGINT NOT NULL REFERENCES acct_fixed_assets(id) ON DELETE CASCADE,
  period_year       INT NOT NULL,
  period_month      INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  amount            NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
  is_posted         BOOLEAN NOT NULL DEFAULT FALSE,
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT acct_ads_unique UNIQUE (asset_id, period_year, period_month)
);

CREATE INDEX IF NOT EXISTS acct_ads_period_idx ON acct_asset_depreciation_schedule(period_year, period_month);
CREATE INDEX IF NOT EXISTS acct_ads_posted_idx ON acct_asset_depreciation_schedule(is_posted);

-- Generates (or re-generates unposted rows of) a straight-line schedule for one asset,
-- starting the month AFTER purchase_date, for useful_life_months periods.
CREATE OR REPLACE FUNCTION acct_generate_depreciation_schedule(p_asset_id BIGINT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  v_asset RECORD;
  v_monthly NUMERIC(14,2);
  v_month_cursor DATE;
  v_created INT := 0;
  i INT;
BEGIN
  SELECT * INTO v_asset FROM acct_fixed_assets WHERE id = p_asset_id;
  IF v_asset IS NULL THEN RAISE EXCEPTION 'Asset % not found', p_asset_id; END IF;

  v_monthly := ROUND((v_asset.cost - v_asset.salvage_value) / v_asset.useful_life_months, 2);
  v_month_cursor := date_trunc('month', v_asset.purchase_date)::DATE + INTERVAL '1 month';

  FOR i IN 1..v_asset.useful_life_months LOOP
    INSERT INTO acct_asset_depreciation_schedule (asset_id, period_year, period_month, amount)
    VALUES (p_asset_id, EXTRACT(YEAR FROM v_month_cursor)::INT, EXTRACT(MONTH FROM v_month_cursor)::INT, v_monthly)
    ON CONFLICT (asset_id, period_year, period_month) DO NOTHING;
    v_created := v_created + 1;
    v_month_cursor := v_month_cursor + INTERVAL '1 month';
  END LOOP;

  RETURN v_created;
END;
$$;

-- Auto-generate the schedule right after an asset is inserted
CREATE OR REPLACE FUNCTION acct_fa_auto_schedule()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM acct_generate_depreciation_schedule(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_fa_auto_schedule_trg ON acct_fixed_assets;
CREATE TRIGGER acct_fa_auto_schedule_trg AFTER INSERT ON acct_fixed_assets
  FOR EACH ROW EXECUTE FUNCTION acct_fa_auto_schedule();

-- Posts ALL unposted depreciation for a given calendar month as ONE consolidated
-- journal entry (debit 5805 Depreciation Expense once per asset line for traceability,
-- credit each asset's own accumulated-depreciation account).
CREATE OR REPLACE FUNCTION run_monthly_depreciation(p_year INT, p_month INT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_expense_account_id BIGINT;
  v_row RECORD;
  v_line_no INT := 1;
  v_total NUMERIC(14,2) := 0;
BEGIN
  SELECT id INTO v_period_id FROM acct_periods WHERE year = p_year AND month = p_month;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'Accounting period %/% not found', p_year, p_month; END IF;

  SELECT id INTO v_expense_account_id FROM acct_chart_of_accounts WHERE code = '5805';
  IF v_expense_account_id IS NULL THEN RAISE EXCEPTION 'Account 5805 (Depreciation Expense) not found'; END IF;

  -- Nothing to post? Return NULL quietly instead of creating an empty entry.
  PERFORM 1 FROM acct_asset_depreciation_schedule
    WHERE period_year = p_year AND period_month = p_month AND is_posted = FALSE LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-DEPR-' || p_year || '-' || LPAD(p_month::TEXT, 2, '0'), (make_date(p_year, p_month, 1) + INTERVAL '1 month' - INTERVAL '1 day')::DATE,
          v_period_id, 'قيد إهلاك شهر ' || p_month || '/' || p_year, 'depreciation', NULL, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  FOR v_row IN
    SELECT s.id AS schedule_id, s.amount, a.name AS asset_name, a.coa_accumulated_depreciation_id
    FROM acct_asset_depreciation_schedule s
    JOIN acct_fixed_assets a ON a.id = s.asset_id
    WHERE s.period_year = p_year AND s.period_month = p_month AND s.is_posted = FALSE AND a.status = 'active'
  LOOP
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, v_line_no, v_expense_account_id, v_row.amount, 0, 'إهلاك: ' || v_row.asset_name);
    v_line_no := v_line_no + 1;
    INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
    VALUES (v_entry_id, v_line_no, v_row.coa_accumulated_depreciation_id, 0, v_row.amount, 'مجمع إهلاك: ' || v_row.asset_name);
    v_line_no := v_line_no + 1;
    v_total := v_total + v_row.amount;

    UPDATE acct_asset_depreciation_schedule SET is_posted = TRUE, journal_entry_id = v_entry_id WHERE id = v_row.schedule_id;
  END LOOP;

  RETURN v_entry_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) acct_inventory_items + acct_inventory_movements
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS acct_inventory_items (
  id            BIGSERIAL PRIMARY KEY,
  sku           TEXT UNIQUE,
  name          TEXT NOT NULL,
  category      TEXT CHECK (category IN ('food', 'beverage', 'consumable') OR category IS NULL),
  unit          TEXT NOT NULL DEFAULT 'unit',
  unit_cost     NUMERIC(12,2) NOT NULL DEFAULT 0,
  quantity_on_hand NUMERIC(14,3) NOT NULL DEFAULT 0,
  reorder_level NUMERIC(14,3) DEFAULT 0,
  asset_account_id BIGINT REFERENCES acct_chart_of_accounts(id) ON DELETE SET NULL,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS acct_inv_items_active_idx ON acct_inventory_items(is_active) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS acct_inv_items_updated_at ON acct_inventory_items;
CREATE TRIGGER acct_inv_items_updated_at BEFORE UPDATE ON acct_inventory_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION acct_assign_sku()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.sku IS NULL THEN NEW.sku := 'SKU-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_inv_items_assign_sku ON acct_inventory_items;
CREATE TRIGGER acct_inv_items_assign_sku BEFORE INSERT ON acct_inventory_items
  FOR EACH ROW EXECUTE FUNCTION acct_assign_sku();

CREATE TABLE IF NOT EXISTS acct_inventory_movements (
  id                BIGSERIAL PRIMARY KEY,
  item_id           BIGINT NOT NULL REFERENCES acct_inventory_items(id) ON DELETE CASCADE,
  movement_date     DATE NOT NULL DEFAULT CURRENT_DATE,
  type              TEXT NOT NULL CHECK (type IN ('in', 'out', 'adjustment')),
  quantity          NUMERIC(14,3) NOT NULL CHECK (quantity > 0),
  unit_cost         NUMERIC(12,2) NOT NULL DEFAULT 0,
  cost_center_id    BIGINT REFERENCES acct_cost_centers(id) ON DELETE SET NULL,
  reference         TEXT,
  journal_entry_id  BIGINT REFERENCES acct_journal_entries(id) ON DELETE SET NULL,
  created_by        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS acct_inv_mov_item_idx ON acct_inventory_movements(item_id);
CREATE INDEX IF NOT EXISTS acct_inv_mov_date_idx ON acct_inventory_movements(movement_date DESC);

-- Applies a movement to quantity_on_hand and, for 'out'/'adjustment', posts a journal.
-- 'in' movements only affect the running quantity — their cost is assumed to already
-- be captured via a Phase 2.b bill, so no separate journal is generated for them.
CREATE OR REPLACE FUNCTION acct_apply_inventory_movement()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type = 'in' THEN
    UPDATE acct_inventory_items SET quantity_on_hand = quantity_on_hand + NEW.quantity WHERE id = NEW.item_id;
  ELSE
    UPDATE acct_inventory_items SET quantity_on_hand = quantity_on_hand - NEW.quantity WHERE id = NEW.item_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS acct_inv_mov_apply ON acct_inventory_movements;
CREATE TRIGGER acct_inv_mov_apply AFTER INSERT ON acct_inventory_movements
  FOR EACH ROW EXECUTE FUNCTION acct_apply_inventory_movement();

CREATE OR REPLACE FUNCTION create_journal_for_inventory_movement(p_movement_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mov RECORD;
  v_item RECORD;
  v_entry_id BIGINT;
  v_period_id BIGINT;
  v_cogs_account_id BIGINT;
  v_amount NUMERIC(14,2);
BEGIN
  SELECT * INTO v_mov FROM acct_inventory_movements WHERE id = p_movement_id;
  IF v_mov IS NULL THEN RAISE EXCEPTION 'Movement % not found', p_movement_id; END IF;
  IF v_mov.type = 'in' THEN RETURN NULL; END IF;
  IF v_mov.journal_entry_id IS NOT NULL THEN RETURN v_mov.journal_entry_id; END IF;

  SELECT * INTO v_item FROM acct_inventory_items WHERE id = v_mov.item_id;
  v_amount := v_mov.quantity * v_mov.unit_cost;
  IF v_amount <= 0 THEN RETURN NULL; END IF;

  v_cogs_account_id := CASE
    WHEN v_mov.type = 'adjustment' THEN (SELECT id FROM acct_chart_of_accounts WHERE code = '5104') -- Waste & Spoilage
    WHEN v_item.category = 'beverage' THEN (SELECT id FROM acct_chart_of_accounts WHERE code = '5102')
    ELSE (SELECT id FROM acct_chart_of_accounts WHERE code = '5101') -- Food Cost
  END;

  SELECT id INTO v_period_id FROM acct_periods WHERE start_date <= v_mov.movement_date AND end_date >= v_mov.movement_date LIMIT 1;
  IF v_period_id IS NULL THEN RAISE EXCEPTION 'No accounting period for date %', v_mov.movement_date; END IF;

  INSERT INTO acct_journal_entries (entry_no, entry_date, period_id, description, source_type, source_id, status, created_by)
  VALUES ('JE-INVMOV-' || p_movement_id, v_mov.movement_date, v_period_id,
          CASE WHEN v_mov.type = 'adjustment' THEN 'قيد تسوية/هدر مخزون: ' ELSE 'قيد صرف مخزون: ' END || v_item.name,
          'manual', p_movement_id, 'draft', current_app_user_id())
  RETURNING id INTO v_entry_id;

  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 1, v_cogs_account_id, v_amount, 0, v_item.name);
  INSERT INTO acct_journal_lines (entry_id, line_no, account_id, debit, credit, description)
  VALUES (v_entry_id, 2, v_item.asset_account_id, 0, v_amount, 'صرف من المخزون: ' || v_item.name);

  UPDATE acct_inventory_movements SET journal_entry_id = v_entry_id WHERE id = p_movement_id;
  RETURN v_entry_id;
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) Row-Level Security
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE acct_fixed_assets                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_asset_depreciation_schedule  ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_inventory_items              ENABLE ROW LEVEL SECURITY;
ALTER TABLE acct_inventory_movements          ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS acct_fa_sel ON acct_fixed_assets;
DROP POLICY IF EXISTS acct_fa_wr  ON acct_fixed_assets;
CREATE POLICY acct_fa_sel ON acct_fixed_assets FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_fa_wr  ON acct_fixed_assets FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_ads_sel ON acct_asset_depreciation_schedule;
DROP POLICY IF EXISTS acct_ads_wr  ON acct_asset_depreciation_schedule;
CREATE POLICY acct_ads_sel ON acct_asset_depreciation_schedule FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_ads_wr  ON acct_asset_depreciation_schedule FOR ALL   TO authenticated USING (is_finance_manager()) WITH CHECK (is_finance_manager());

DROP POLICY IF EXISTS acct_invitem_sel ON acct_inventory_items;
DROP POLICY IF EXISTS acct_invitem_wr  ON acct_inventory_items;
CREATE POLICY acct_invitem_sel ON acct_inventory_items FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_invitem_wr  ON acct_inventory_items FOR ALL   TO authenticated USING (is_gl_accountant()) WITH CHECK (is_gl_accountant());

DROP POLICY IF EXISTS acct_invmov_sel ON acct_inventory_movements;
DROP POLICY IF EXISTS acct_invmov_wr  ON acct_inventory_movements;
CREATE POLICY acct_invmov_sel ON acct_inventory_movements FOR SELECT TO authenticated USING (is_accounting_role());
CREATE POLICY acct_invmov_wr  ON acct_inventory_movements FOR ALL   TO authenticated USING (is_gl_accountant()) WITH CHECK (is_gl_accountant());

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Post-migration checklist:
--   1. SELECT COUNT(*) FROM acct_fixed_assets;  -- migrated branch_assets with a cost
--   2. SELECT asset_no, name, cost, useful_life_months FROM acct_fixed_assets LIMIT 10;
--   3. SELECT COUNT(*) FROM acct_asset_depreciation_schedule;  -- should be assets * useful_life_months
--   4. SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN
--        ('acct_fixed_assets','acct_asset_depreciation_schedule','acct_inventory_items','acct_inventory_movements');
--      All should show rowsecurity = true.
--   5. To run depreciation for a closed month once it's the following month:
--      SELECT run_monthly_depreciation(2026, 7);
-- ═══════════════════════════════════════════════════════════════════════════
