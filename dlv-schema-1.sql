-- ═══════════════════════════════════════════════════════════
-- التوصيل Delivery — Phase 1 (Wave 3 Module 30)
-- ═══════════════════════════════════════════════════════════
-- 5 جداول: إعدادات + مناطق توصيل + السائقين + طلبات التوصيل + نقاط التتبع
-- + دالة delivery_assign_rider() لإسناد ذرّي
-- + دالة delivery_update_status() لتغيير مراحل الطلب مع بصمة تتبع
-- التنفيذ آمن ومتكرر (idempotent).
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────
-- 0) دالة مساعدة: مدير التوصيل
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_delivery_manager()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT current_app_role() IN ('admin', 'company_manager', 'operations_manager', 'delivery_manager');
$$;

-- ───────────────────────────────────────────────────────────
-- 1) delivery_settings — إعدادات عامة (صف واحد id=1)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS delivery_settings (
  id                          INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  default_prep_minutes        INT NOT NULL DEFAULT 20 CHECK (default_prep_minutes > 0),
  default_delivery_minutes    INT NOT NULL DEFAULT 30 CHECK (default_delivery_minutes > 0),
  min_order_value             NUMERIC(10,2) NOT NULL DEFAULT 30 CHECK (min_order_value >= 0),
  base_delivery_fee           NUMERIC(10,2) NOT NULL DEFAULT 15 CHECK (base_delivery_fee >= 0),
  free_delivery_threshold     NUMERIC(10,2),
  auto_assign_riders          BOOLEAN NOT NULL DEFAULT FALSE,
  sla_late_minutes            INT NOT NULL DEFAULT 45,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now()
);

INSERT INTO delivery_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS delivery_settings_updated_at ON delivery_settings;
CREATE TRIGGER delivery_settings_updated_at BEFORE UPDATE ON delivery_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 2) delivery_zones — مناطق التوصيل لكل فرع
--    DECISION: نستخدم دائرة (مركز + نصف قطر) بدل polygon — أبسط للـ
--    Phase 1 وكافي لأغلب الحالات. polygon يتضاف في Phase 2.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS delivery_zones (
  id                BIGSERIAL PRIMARY KEY,
  branch_id         BIGINT NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  center_latitude   NUMERIC(10,7),
  center_longitude  NUMERIC(10,7),
  radius_km         NUMERIC(6,2) NOT NULL DEFAULT 5 CHECK (radius_km > 0),
  delivery_fee      NUMERIC(10,2) NOT NULL DEFAULT 15 CHECK (delivery_fee >= 0),
  min_order_value   NUMERIC(10,2),
  estimated_minutes INT NOT NULL DEFAULT 30 CHECK (estimated_minutes > 0),
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS delivery_zones_branch_idx ON delivery_zones(branch_id) WHERE is_active;

DROP TRIGGER IF EXISTS delivery_zones_updated_at ON delivery_zones;
CREATE TRIGGER delivery_zones_updated_at BEFORE UPDATE ON delivery_zones
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ───────────────────────────────────────────────────────────
-- 3) delivery_riders — السائقين
--    DECISION: rider ممكن يكون موظف (user_id) أو مستقل (بدون user_id)
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS delivery_riders (
  id                BIGSERIAL PRIMARY KEY,
  rider_code        TEXT UNIQUE,
  full_name         TEXT NOT NULL,
  phone             TEXT NOT NULL,
  user_id           BIGINT REFERENCES users(id) ON DELETE SET NULL,
  branch_id         BIGINT REFERENCES branches(id) ON DELETE SET NULL,
  vehicle_type      TEXT NOT NULL DEFAULT 'motorcycle'
                     CHECK (vehicle_type IN ('motorcycle', 'car', 'bicycle', 'on_foot')),
  vehicle_plate     TEXT,
  license_no        TEXT,
  license_expiry    DATE,
  status            TEXT NOT NULL DEFAULT 'offline'
                     CHECK (status IN ('offline', 'available', 'on_delivery', 'break', 'inactive')),
  current_orders    INT NOT NULL DEFAULT 0 CHECK (current_orders >= 0),
  total_deliveries  INT NOT NULL DEFAULT 0,
  rating            NUMERIC(3,2) CHECK (rating IS NULL OR (rating BETWEEN 0 AND 5)),
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS delivery_riders_branch_idx ON delivery_riders(branch_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS delivery_riders_status_idx ON delivery_riders(status) WHERE is_active AND status = 'available';

DROP TRIGGER IF EXISTS delivery_riders_updated_at ON delivery_riders;
CREATE TRIGGER delivery_riders_updated_at BEFORE UPDATE ON delivery_riders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION delivery_assign_rider_code()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.rider_code IS NULL THEN NEW.rider_code := 'RDR-' || LPAD(NEW.id::TEXT, 4, '0'); END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS delivery_riders_assign_code ON delivery_riders;
CREATE TRIGGER delivery_riders_assign_code BEFORE INSERT ON delivery_riders
  FOR EACH ROW EXECUTE FUNCTION delivery_assign_rider_code();

-- ───────────────────────────────────────────────────────────
-- 4) delivery_orders — طلبات التوصيل
--    DECISION: pos_transaction_id اختياري — يدعم طلبات من POS
--    ومن مصادر خارجية (تليفون/تطبيق التوصيل).
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS delivery_orders (
  id                    BIGSERIAL PRIMARY KEY,
  order_no              TEXT UNIQUE,
  branch_id             BIGINT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  pos_transaction_id    BIGINT REFERENCES pos_transactions(id) ON DELETE SET NULL,
  customer_id           BIGINT REFERENCES crm_customers(id) ON DELETE SET NULL,
  customer_name         TEXT,
  customer_phone        TEXT NOT NULL,
  delivery_address      TEXT NOT NULL,
  address_latitude      NUMERIC(10,7),
  address_longitude     NUMERIC(10,7),
  zone_id               BIGINT REFERENCES delivery_zones(id) ON DELETE SET NULL,
  rider_id              BIGINT REFERENCES delivery_riders(id) ON DELETE SET NULL,
  source                TEXT NOT NULL DEFAULT 'phone'
                         CHECK (source IN ('phone', 'app', 'aggregator', 'walk_in', 'other')),
  aggregator_ref        TEXT,
  subtotal              NUMERIC(10,2) NOT NULL DEFAULT 0,
  delivery_fee          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
  total_amount          NUMERIC(10,2) NOT NULL DEFAULT 0,
  payment_method        TEXT DEFAULT 'cash' CHECK (payment_method IN ('cash', 'card', 'online', 'wallet')),
  is_paid               BOOLEAN NOT NULL DEFAULT FALSE,
  status                TEXT NOT NULL DEFAULT 'new'
                         CHECK (status IN ('new', 'accepted', 'preparing', 'ready', 'assigned', 'picked_up', 'delivered', 'cancelled', 'failed')),
  eta_minutes           INT,
  accepted_at           TIMESTAMPTZ,
  ready_at              TIMESTAMPTZ,
  assigned_at           TIMESTAMPTZ,
  picked_up_at          TIMESTAMPTZ,
  delivered_at          TIMESTAMPTZ,
  cancelled_at          TIMESTAMPTZ,
  cancel_reason         TEXT,
  customer_rating       INT CHECK (customer_rating IS NULL OR customer_rating BETWEEN 1 AND 5),
  customer_feedback     TEXT,
  notes                 TEXT,
  created_by            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS delivery_orders_branch_idx    ON delivery_orders(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS delivery_orders_status_idx    ON delivery_orders(status) WHERE status NOT IN ('delivered', 'cancelled', 'failed');
CREATE INDEX IF NOT EXISTS delivery_orders_rider_idx     ON delivery_orders(rider_id) WHERE rider_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS delivery_orders_customer_idx  ON delivery_orders(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS delivery_orders_pos_idx       ON delivery_orders(pos_transaction_id) WHERE pos_transaction_id IS NOT NULL;

DROP TRIGGER IF EXISTS delivery_orders_updated_at ON delivery_orders;
CREATE TRIGGER delivery_orders_updated_at BEFORE UPDATE ON delivery_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION delivery_assign_order_no()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq  BIGINT;
BEGIN
  IF NEW.order_no IS NULL THEN
    SELECT COUNT(*) + 1 INTO v_seq FROM delivery_orders WHERE order_no LIKE 'DLV-' || v_year || '-%';
    NEW.order_no := 'DLV-' || v_year || '-' || LPAD(v_seq::TEXT, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS delivery_orders_assign_no ON delivery_orders;
CREATE TRIGGER delivery_orders_assign_no BEFORE INSERT ON delivery_orders
  FOR EACH ROW EXECUTE FUNCTION delivery_assign_order_no();

-- ───────────────────────────────────────────────────────────
-- 5) delivery_tracking — نقاط تتبع الطلب (لوج زمني)
--    DECISION: كل تغيير حالة أو موقع سائق يُسجَّل هنا كسجل ثابت.
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS delivery_tracking (
  id            BIGSERIAL PRIMARY KEY,
  order_id      BIGINT NOT NULL REFERENCES delivery_orders(id) ON DELETE CASCADE,
  event_type    TEXT NOT NULL CHECK (event_type IN ('status_change', 'location_ping', 'rider_note', 'customer_note', 'delay')),
  status        TEXT,
  latitude      NUMERIC(10,7),
  longitude     NUMERIC(10,7),
  message       TEXT,
  actor_id      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  actor_rider_id BIGINT REFERENCES delivery_riders(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS delivery_tracking_order_idx ON delivery_tracking(order_id, created_at DESC);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- دوال العمليات الذرية
-- ═══════════════════════════════════════════════════════════

-- تحديث حالة طلب + بصمة زمنية على العمود المناسب + سجل tracking
CREATE OR REPLACE FUNCTION delivery_update_status(
  p_order_id BIGINT,
  p_new_status TEXT,
  p_message TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
BEGIN
  UPDATE delivery_orders
  SET status = p_new_status,
      accepted_at  = CASE WHEN p_new_status = 'accepted'  AND accepted_at  IS NULL THEN v_now ELSE accepted_at  END,
      ready_at     = CASE WHEN p_new_status = 'ready'     AND ready_at     IS NULL THEN v_now ELSE ready_at     END,
      picked_up_at = CASE WHEN p_new_status = 'picked_up' AND picked_up_at IS NULL THEN v_now ELSE picked_up_at END,
      delivered_at = CASE WHEN p_new_status = 'delivered' AND delivered_at IS NULL THEN v_now ELSE delivered_at END,
      cancelled_at = CASE WHEN p_new_status = 'cancelled' AND cancelled_at IS NULL THEN v_now ELSE cancelled_at END
  WHERE id = p_order_id;

  INSERT INTO delivery_tracking (order_id, event_type, status, message, actor_id)
  VALUES (p_order_id, 'status_change', p_new_status, p_message, current_app_user_id());
END;
$$;

-- إسناد طلب لسائق: يفحص التوفر، يزيد عداد الطلبات، ويحدّث حالة الطلب
CREATE OR REPLACE FUNCTION delivery_assign_rider(
  p_order_id BIGINT,
  p_rider_id BIGINT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order  RECORD;
  v_rider  RECORD;
BEGIN
  SELECT * INTO v_order FROM delivery_orders WHERE id = p_order_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'الطلب غير موجود'; END IF;
  IF v_order.status IN ('delivered', 'cancelled', 'failed') THEN
    RAISE EXCEPTION 'لا يمكن إسناد طلب في الحالة: %', v_order.status;
  END IF;
  IF v_order.rider_id IS NOT NULL THEN
    RAISE EXCEPTION 'الطلب مُسنَد بالفعل للسائق % — أزل الإسناد الحالي أولًا', v_order.rider_id;
  END IF;

  SELECT * INTO v_rider FROM delivery_riders WHERE id = p_rider_id;
  IF v_rider IS NULL OR NOT v_rider.is_active THEN RAISE EXCEPTION 'السائق غير موجود أو غير نشط'; END IF;
  IF v_rider.status NOT IN ('available', 'on_delivery') THEN
    RAISE EXCEPTION 'السائق غير متاح — الحالة الحالية: %', v_rider.status;
  END IF;

  UPDATE delivery_orders
  SET rider_id = p_rider_id,
      status = CASE WHEN status IN ('new', 'accepted', 'preparing', 'ready') THEN 'assigned' ELSE status END,
      assigned_at = COALESCE(assigned_at, now())
  WHERE id = p_order_id;

  UPDATE delivery_riders
  SET current_orders = current_orders + 1,
      status = 'on_delivery'
  WHERE id = p_rider_id;

  INSERT INTO delivery_tracking (order_id, event_type, status, message, actor_id, actor_rider_id)
  VALUES (p_order_id, 'status_change', 'assigned', 'تم إسناد الطلب للسائق ' || v_rider.full_name, current_app_user_id(), p_rider_id);
END;
$$;

-- تسليم الطلب: يحدّث الحالة، يقلل عداد السائق، ويزيد إجمالي التوصيلات
CREATE OR REPLACE FUNCTION delivery_mark_delivered(p_order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
BEGIN
  SELECT * INTO v_order FROM delivery_orders WHERE id = p_order_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'الطلب غير موجود'; END IF;
  IF v_order.status = 'delivered' THEN RAISE EXCEPTION 'الطلب مُسلَّم بالفعل'; END IF;
  IF v_order.rider_id IS NULL THEN RAISE EXCEPTION 'لا يوجد سائق مُسنَد للطلب'; END IF;

  UPDATE delivery_orders
  SET status = 'delivered', delivered_at = now(), is_paid = TRUE
  WHERE id = p_order_id;

  -- تحديث السائق: إنقاص عداد الطلبات النشطة، زيادة الإجمالي، وإعادة الحالة لـ available
  -- لو ما بقاش عنده طلبات نشطة. الملاحظة: نستخدم القيمة القديمة قبل الإنقاص
  -- (فلما current_orders = 1 قبل الإنقاص، النتيجة تكون 0 والحالة تصبح available)
  UPDATE delivery_riders
  SET current_orders = GREATEST(current_orders - 1, 0),
      total_deliveries = total_deliveries + 1,
      status = CASE WHEN current_orders <= 1 THEN 'available' ELSE 'on_delivery' END
  WHERE id = v_order.rider_id;

  INSERT INTO delivery_tracking (order_id, event_type, status, message, actor_id)
  VALUES (p_order_id, 'status_change', 'delivered', 'تم تسليم الطلب للعميل', current_app_user_id());
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE delivery_settings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_zones      ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_riders     ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_orders     ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_tracking   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS delivery_settings_sel ON delivery_settings;
CREATE POLICY delivery_settings_sel ON delivery_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS delivery_settings_wr ON delivery_settings;
CREATE POLICY delivery_settings_wr ON delivery_settings FOR UPDATE TO authenticated
  USING (is_delivery_manager()) WITH CHECK (is_delivery_manager());

DROP POLICY IF EXISTS delivery_zones_sel ON delivery_zones;
CREATE POLICY delivery_zones_sel ON delivery_zones FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS delivery_zones_wr ON delivery_zones;
CREATE POLICY delivery_zones_wr ON delivery_zones FOR ALL TO authenticated
  USING (is_delivery_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                    AND u.branch_id = delivery_zones.branch_id
                    AND u.role IN ('branch_manager', 'deputy_manager')))
  WITH CHECK (is_delivery_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                    AND u.branch_id = delivery_zones.branch_id
                    AND u.role IN ('branch_manager', 'deputy_manager')));

DROP POLICY IF EXISTS delivery_riders_sel ON delivery_riders;
CREATE POLICY delivery_riders_sel ON delivery_riders FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS delivery_riders_wr ON delivery_riders;
CREATE POLICY delivery_riders_wr ON delivery_riders FOR ALL TO authenticated
  USING (is_delivery_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                    AND u.branch_id = delivery_riders.branch_id
                    AND u.role IN ('branch_manager', 'deputy_manager')))
  WITH CHECK (is_delivery_manager()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id()
                    AND u.branch_id = delivery_riders.branch_id
                    AND u.role IN ('branch_manager', 'deputy_manager')));

-- الطلبات: قراءة للجميع في الفرع، كتابة لموظفي الفرع أو مدير التوصيل
DROP POLICY IF EXISTS delivery_orders_sel ON delivery_orders;
CREATE POLICY delivery_orders_sel ON delivery_orders FOR SELECT TO authenticated USING (
  is_delivery_manager()
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = delivery_orders.branch_id)
  OR EXISTS (SELECT 1 FROM delivery_riders r WHERE r.id = delivery_orders.rider_id AND r.user_id = current_app_user_id())
);
DROP POLICY IF EXISTS delivery_orders_ins ON delivery_orders;
CREATE POLICY delivery_orders_ins ON delivery_orders FOR INSERT TO authenticated WITH CHECK (
  is_delivery_manager()
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = delivery_orders.branch_id)
);
DROP POLICY IF EXISTS delivery_orders_upd ON delivery_orders;
CREATE POLICY delivery_orders_upd ON delivery_orders FOR UPDATE TO authenticated USING (
  is_delivery_manager()
  OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = delivery_orders.branch_id)
  OR EXISTS (SELECT 1 FROM delivery_riders r WHERE r.id = delivery_orders.rider_id AND r.user_id = current_app_user_id())
);

-- التتبع: قراءة لكل من له صلاحية قراءة الطلب، إدراج فقط عبر الدوال SECURITY DEFINER
DROP POLICY IF EXISTS delivery_tracking_sel ON delivery_tracking;
CREATE POLICY delivery_tracking_sel ON delivery_tracking FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM delivery_orders o WHERE o.id = delivery_tracking.order_id
          AND (is_delivery_manager()
               OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = o.branch_id)
               OR EXISTS (SELECT 1 FROM delivery_riders r WHERE r.id = o.rider_id AND r.user_id = current_app_user_id())))
);
DROP POLICY IF EXISTS delivery_tracking_ins ON delivery_tracking;
CREATE POLICY delivery_tracking_ins ON delivery_tracking FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM delivery_orders o WHERE o.id = delivery_tracking.order_id
            AND (is_delivery_manager()
                 OR EXISTS (SELECT 1 FROM users u WHERE u.id = current_app_user_id() AND u.branch_id = o.branch_id)
                 OR EXISTS (SELECT 1 FROM delivery_riders r WHERE r.id = o.rider_id AND r.user_id = current_app_user_id())))
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- قائمة تحقق ما بعد التنفيذ:
-- 1) SELECT * FROM delivery_settings;
-- 2) SELECT proname FROM pg_proc WHERE proname LIKE 'delivery_%';
-- 3) SELECT relname FROM pg_class WHERE relname LIKE 'delivery_%';
-- ═══════════════════════════════════════════════════════════
