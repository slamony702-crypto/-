-- ═══════════════════════════════════════════════════════════
-- Migration 6 — Fix: Guard triggers must be SECURITY INVOKER
-- ═══════════════════════════════════════════════════════════
-- Wave: purchase-orders-wave1
-- التاريخ: 2026-07-18 (اكتُشف أثناء اختبار محلي فعلي)
-- ═══════════════════════════════════════════════════════════
-- المشكلة:
--   دوال Trigger الحرس (proc_req_update_guard,
--   proc_req_items_write_guard, proc_po_creation_guard)
--   كانت SECURITY DEFINER. عند تنفيذ trigger كـSECURITY DEFINER
--   يصبح current_user = المالك (postgres) بدلًا من المتصل الفعلي.
--   نتيجة: فحص `current_user NOT IN ('authenticated', 'anon')` يمر
--   دائمًا، مما يوقف الحرس تمامًا.
--
-- الحل:
--   نغيّر هذه الدوال إلى SECURITY INVOKER (السلوك الافتراضي).
--   هذا يجعل current_user بداخلها = المتصل الفعلي، فيعمل الحرس
--   بشكل صحيح للتحديثات المباشرة من العميل وينتظم مع RPCs
--   (لأن الـRPCs بتُنفذ UPDATE بينما current_user=postgres،
--   فيتخطى الحرس).
--
-- تأثير:
--   - RPCs (SECURITY DEFINER) تُنفذ UPDATE داخلها كـpostgres
--     → الحرس يتخطى بشكل صحيح.
--   - Client مباشر (authenticated) → الحرس يفعل عمله.
--   - الدوال ذاتها بتفعل SELECT فقط + RAISE — لا تحتاج صلاحيات
--     خاصة.
-- ═══════════════════════════════════════════════════════════

-- (1) Guard 1: تغييرات proc_requisitions
CREATE OR REPLACE FUNCTION proc_req_update_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
-- ملاحظة: لا SECURITY DEFINER — استخدم SECURITY INVOKER الافتراضي
AS $$
DECLARE
  v_has_chain BOOLEAN;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (SELECT 1 FROM proc_requisition_approvals WHERE requisition_id = OLD.id)
    INTO v_has_chain;

  IF v_has_chain
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('approved', 'rejected', 'cancelled', 'converted') THEN
    RAISE EXCEPTION 'APPROVAL_MULTI_LEVEL_ACTIVE: استخدم proc_approve_step / proc_reject_step / proc_cancel_requisition_approval بدل UPDATE المباشر';
  END IF;

  IF OLD.status IN ('submitted', 'approved')
     AND (NEW.branch_id IS DISTINCT FROM OLD.branch_id
          OR NEW.department_id IS DISTINCT FROM OLD.department_id) THEN
    RAISE EXCEPTION 'REQ_LOCKED_FIELDS: لا يمكن تعديل الفرع أو القسم بعد التقديم — ألغِ المسار أولًا';
  END IF;

  IF NEW.status = 'rejected' AND OLD.status <> 'rejected' THEN
    IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
      RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: سبب الرفض مطلوب';
    END IF;
  END IF;

  IF OLD.status IN ('rejected', 'cancelled', 'converted')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'REQ_TERMINAL_STATE: الطلب في حالة نهائية (%) — لا يمكن تغييرها', OLD.status;
  END IF;

  IF OLD.status = 'submitted' AND NEW.status = 'draft' THEN
    RAISE EXCEPTION 'REQ_INVALID_TRANSITION: لا يُسمح بإرجاع الطلب إلى draft — استخدم إلغاء المسار';
  END IF;

  RETURN NEW;
END;
$$;

-- (2) Guard 2: تعديل بنود الطلب
CREATE OR REPLACE FUNCTION proc_req_items_write_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_req_id BIGINT;
  v_status TEXT;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_req_id := COALESCE(NEW.requisition_id, OLD.requisition_id);
  SELECT status INTO v_status FROM proc_requisitions WHERE id = v_req_id;

  IF v_status IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'REQ_ITEMS_LOCKED: لا يمكن تعديل بنود الطلب — الحالة الحالية %', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- (3) Guard 3: منع إنشاء أمر شراء قبل الاعتماد
-- ملاحظة: هذا Guard مقصود بأن يعمل حتى داخل RPCs (دفاع بعمق)،
-- لذلك لا يحتاج current_user check. نتركه SECURITY INVOKER مع
-- استمرار الحماية العامة.
CREATE OR REPLACE FUNCTION proc_po_creation_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_status  TEXT;
  v_pending INT;
BEGIN
  IF NEW.requisition_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT status INTO v_status FROM proc_requisitions WHERE id = NEW.requisition_id;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'REQ_NOT_FOUND: طلب الشراء المرتبط غير موجود';
  END IF;

  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'PO_BEFORE_APPROVAL: لا يمكن إنشاء أمر شراء قبل اكتمال الاعتماد (الحالة: %)', v_status;
  END IF;

  SELECT COUNT(*) INTO v_pending
    FROM proc_requisition_approvals
    WHERE requisition_id = NEW.requisition_id AND status = 'pending';
  IF v_pending > 0 THEN
    RAISE EXCEPTION 'PO_STEPS_PENDING: توجد % خطوات اعتماد لم تُحسم بعد', v_pending;
  END IF;

  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- تحقق بعد التطبيق:
--   SELECT proname, prosecdef
--   FROM pg_proc
--   WHERE proname IN ('proc_req_update_guard','proc_req_items_write_guard','proc_po_creation_guard');
--   -- prosecdef يجب أن يعود FALSE (SECURITY INVOKER)
-- ═══════════════════════════════════════════════════════════
