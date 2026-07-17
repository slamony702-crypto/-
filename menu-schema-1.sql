-- ═══════════════════════════════════════════════════════════
-- المنيو والوصفات — المرحلة 1: الفئات والأصناف والوصفات
-- ═══════════════════════════════════════════════════════════
-- 5 جداول: menu_settings + menu_categories + menu_items
-- + menu_item_recipes + menu_channel_prices
-- التكامل: menu_item_recipes.inventory_item_id → acct_inventory_items
-- (الوصفة تربط الصنف بمكوناته من المخزون العام)
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير المنيو (operations_manager أو أعلى)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_menu_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) menu_settings — إعدادات المنيو (صف واحد id=1)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS menu_settings (
  id                          INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  default_target_margin       NUMERIC(5,2) NOT NULL DEFAULT 60 CHECK (default_target_margin BETWEEN 0 AND 99),
  prices_include_vat          BOOLEAN NOT NULL DEFAULT FALSE,
  auto_hide_out_of_stock      BOOLEAN NOT NULL DEFAULT TRUE,
  low_margin_threshold        NUMERIC(5,2) NOT NULL DEFAULT 30,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now()
);

INSERT INTO menu_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS menu_settings_updated_at ON menu_settings;
CREATE TRIGGER menu_settings_updated_at BEFORE UPDATE ON menu_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) menu_categories — فئات المنيو
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS menu_categories (
  id           BIGSERIAL PRIMARY KEY,
  name_ar      TEXT NOT NULL,
  name_en      TEXT,
  description  TEXT,
  icon         TEXT,
  color        TEXT,
  sort_order   INT NOT NULL DEFAULT 0,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_by   BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS menu_categories_active_idx ON menu_categories(is_active, sort_order) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS menu_categories_updated_at ON menu_categories;
CREATE TRIGGER menu_categories_updated_at BEFORE UPDATE ON menu_categories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) menu_items — أصناف المنيو
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS menu_items (
  id                       BIGSERIAL PRIMARY KEY,
  category_id              BIGINT REFERENCES menu_categories(id) ON DELETE SET NULL,
  sku                      TEXT UNIQUE,
  name_ar                  TEXT NOT NULL,
  name_en                  TEXT,
  description              TEXT,
  image_url                TEXT,
  base_price               NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (base_price >= 0),
  target_margin_percent    NUMERIC(5,2) DEFAULT 60 CHECK (target_margin_percent BETWEEN 0 AND 99),
  vat_applicable           BOOLEAN NOT NULL DEFAULT TRUE,
  is_active                BOOLEAN NOT NULL DEFAULT TRUE,
  is_featured              BOOLEAN NOT NULL DEFAULT FALSE,
  preparation_minutes      INT DEFAULT 0 CHECK (preparation_minutes >= 0),
  allergen_notes           TEXT,
  sort_order               INT NOT NULL DEFAULT 0,
  created_by               BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at               TIMESTAMPTZ DEFAULT now(),
  updated_at               TIMESTAMPTZ DEFAULT now(),
  deleted_at               TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS menu_items_category_idx ON menu_items(category_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS menu_items_active_idx   ON menu_items(is_active, sort_order) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS menu_items_featured_idx ON menu_items(is_featured) WHERE deleted_at IS NULL AND is_featured = TRUE;

DROP TRIGGER IF EXISTS menu_items_updated_at ON menu_items;
CREATE TRIGGER menu_items_updated_at BEFORE UPDATE ON menu_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- كود SKU تلقائي MENU-00001
CREATE OR REPLACE FUNCTION menu_assign_sku()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.sku IS NULL THEN NEW.sku := 'MENU-' || LPAD(NEW.id::TEXT, 5, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS menu_items_assign_sku ON menu_items;
CREATE TRIGGER menu_items_assign_sku BEFORE INSERT ON menu_items
  FOR EACH ROW EXECUTE FUNCTION menu_assign_sku();

-- ───────────────────────────────────────────────────────────
-- 4) menu_item_recipes — الوصفة (BOM: صنف → مكونات من المخزون)
--    DECISION: كل مكون في الوصفة يشير لصنف مخزون واحد بكمية دقيقة.
--    التكلفة الفعلية للصنف = مجموع (كمية × unit_cost) لكل مكون.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS menu_item_recipes (
  id                  BIGSERIAL PRIMARY KEY,
  item_id             BIGINT NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  inventory_item_id   BIGINT NOT NULL REFERENCES acct_inventory_items(id) ON DELETE RESTRICT,
  quantity            NUMERIC(10,4) NOT NULL CHECK (quantity > 0),
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT menu_recipes_unique UNIQUE (item_id, inventory_item_id)
);

CREATE INDEX IF NOT EXISTS menu_recipes_item_idx ON menu_item_recipes(item_id);
CREATE INDEX IF NOT EXISTS menu_recipes_inv_idx  ON menu_item_recipes(inventory_item_id);

-- ───────────────────────────────────────────────────────────
-- 5) menu_channel_prices — أسعار مختلفة للقنوات
--    DECISION: لو مفيش سعر مخصص لقناة، يُستخدم base_price
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS menu_channel_prices (
  id         BIGSERIAL PRIMARY KEY,
  item_id    BIGINT NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  channel    TEXT NOT NULL CHECK (channel IN ('dine_in', 'takeaway', 'delivery')),
  price      NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT menu_channel_prices_unique UNIQUE (item_id, channel)
);

CREATE INDEX IF NOT EXISTS menu_channel_prices_item_idx ON menu_channel_prices(item_id);

-- ───────────────────────────────────────────────────────────
-- 6) دالة حساب تكلفة الصنف من الوصفة
--    ترجع تكلفة الصنف الحالية بناءً على unit_cost لكل مكون
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION menu_compute_item_cost(p_item_id BIGINT)
RETURNS NUMERIC LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT COALESCE(SUM(r.quantity * COALESCE(i.unit_cost, 0)), 0)
  FROM menu_item_recipes r
  JOIN acct_inventory_items i ON i.id = r.inventory_item_id
  WHERE r.item_id = p_item_id;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE menu_settings         ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_categories       ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items            ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_recipes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_channel_prices   ENABLE ROW LEVEL SECURITY;

-- menu_settings: قراءة للجميع، تعديل لمدير المنيو فقط
DROP POLICY IF EXISTS menu_settings_sel ON menu_settings;
CREATE POLICY menu_settings_sel ON menu_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS menu_settings_wr ON menu_settings;
CREATE POLICY menu_settings_wr ON menu_settings FOR UPDATE TO authenticated
  USING (is_menu_manager()) WITH CHECK (is_menu_manager());

-- menu_categories: قراءة للجميع، كتابة لمدير المنيو
DROP POLICY IF EXISTS menu_categories_sel ON menu_categories;
CREATE POLICY menu_categories_sel ON menu_categories FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS menu_categories_wr ON menu_categories;
CREATE POLICY menu_categories_wr ON menu_categories FOR ALL TO authenticated
  USING (is_menu_manager()) WITH CHECK (is_menu_manager());

-- menu_items: قراءة للجميع (POS يقرأ)، كتابة لمدير المنيو
DROP POLICY IF EXISTS menu_items_sel ON menu_items;
CREATE POLICY menu_items_sel ON menu_items FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS menu_items_wr ON menu_items;
CREATE POLICY menu_items_wr ON menu_items FOR ALL TO authenticated
  USING (is_menu_manager()) WITH CHECK (is_menu_manager());

-- menu_item_recipes: كتابة لمدير المنيو، قراءة لأدوار المحاسبة والتشغيل
-- (المحاسبة تحتاجها لحساب تكلفة المبيعات)
DROP POLICY IF EXISTS menu_recipes_sel ON menu_item_recipes;
CREATE POLICY menu_recipes_sel ON menu_item_recipes FOR SELECT TO authenticated
  USING (is_menu_manager() OR is_accounting_role());
DROP POLICY IF EXISTS menu_recipes_wr ON menu_item_recipes;
CREATE POLICY menu_recipes_wr ON menu_item_recipes FOR ALL TO authenticated
  USING (is_menu_manager()) WITH CHECK (is_menu_manager());

-- menu_channel_prices: مثل menu_items
DROP POLICY IF EXISTS menu_prices_sel ON menu_channel_prices;
CREATE POLICY menu_prices_sel ON menu_channel_prices FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS menu_prices_wr ON menu_channel_prices;
CREATE POLICY menu_prices_wr ON menu_channel_prices FOR ALL TO authenticated
  USING (is_menu_manager()) WITH CHECK (is_menu_manager());

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- بيانات مبدئية (فئات شائعة في المطاعم)
-- ═══════════════════════════════════════════════════════════
BEGIN;

INSERT INTO menu_categories (name_ar, name_en, icon, sort_order) VALUES
  ('الوجبات الرئيسية', 'Main Courses', 'utensils', 1),
  ('المشروبات الساخنة', 'Hot Beverages', 'coffee', 2),
  ('المشروبات الباردة', 'Cold Beverages', 'cup-soda', 3),
  ('السلطات والمقبلات', 'Salads & Appetizers', 'salad', 4),
  ('الحلويات', 'Desserts', 'cake-slice', 5),
  ('الوجبات السريعة', 'Fast Food', 'sandwich', 6)
ON CONFLICT DO NOTHING;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM menu_settings;               -- صف واحد id=1
-- 2) SELECT COUNT(*) FROM menu_categories;      -- 6 فئات مبدئية
-- 3) SELECT * FROM menu_items LIMIT 1;
-- 4) SELECT menu_compute_item_cost(1);          -- تُرجع 0 لأنه لا وصفة بعد
-- 5) SELECT relname, relrowsecurity FROM pg_class
--    WHERE relname LIKE 'menu_%' AND relkind='r';  -- كلها true
-- ═══════════════════════════════════════════════════════════
