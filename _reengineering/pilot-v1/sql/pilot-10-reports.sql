-- ═══════════════════════════════════════════════════════════════════════
-- PILOT v1 — Migration 10 — تقارير Server-side موثوقة
-- ═══════════════════════════════════════════════════════════════════════
-- REQUIRES SUPABASE STAGING للتحقق من النطاق لكل دور. يعتمد على pilot-01..09.
--
-- يعالج فجوات التقارير:
--   • العدّ في المتصفح مسقوف بـ500 صف → تجميع DB (COUNT حقيقي بلا سقف).
--   • لا نطاق فرع/قسم Server-side → الدوال SECURITY INVOKER فتحترم RLS تلقائيًا
--     (المستخدم يجمّع الصفوف التي يراها فقط).
--   • التواريخ UTC → تجميع بحدود يوم/شهر بتوقيت 'Asia/Riyadh'.
--
-- كل الدوال للقراءة فقط. آمنة لإعادة التشغيل.
-- ═══════════════════════════════════════════════════════════════════════

-- نطاق التاريخ يُفسَّر بتوقيت الرياض: [p_from 00:00, p_to+1 00:00) Riyadh → UTC
CREATE OR REPLACE FUNCTION pilot_riyadh_range(p_from DATE, p_to DATE)
RETURNS TABLE(lo TIMESTAMPTZ, hi TIMESTAMPTZ)
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT (p_from::timestamp AT TIME ZONE 'Asia/Riyadh'),
         ((p_to + 1)::timestamp AT TIME ZONE 'Asia/Riyadh');
$$;

-- ─── نظرة عامة موحّدة: (module, metric, value) ─────────────────────────
-- SECURITY INVOKER: يحترم RLS — كل مستخدم يجمّع نطاقه فقط.
CREATE OR REPLACE FUNCTION pilot_report_overview(p_from DATE, p_to DATE)
RETURNS TABLE(module TEXT, metric TEXT, value NUMERIC)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_lo TIMESTAMPTZ; v_hi TIMESTAMPTZ; v_today DATE;
BEGIN
  SELECT lo, hi INTO v_lo, v_hi FROM pilot_riyadh_range(p_from, p_to);
  v_today := (now() AT TIME ZONE 'Asia/Riyadh')::date;

  -- الاجتماعات
  RETURN QUERY SELECT 'meetings', status, count(*)::numeric
    FROM meetings WHERE created_at >= v_lo AND created_at < v_hi GROUP BY status;

  -- المهام (action_items): بالحالة + المتأخرة
  RETURN QUERY SELECT 'tasks', 'status:'||status, count(*)::numeric
    FROM action_items WHERE created_at >= v_lo AND created_at < v_hi GROUP BY status;
  RETURN QUERY SELECT 'tasks', 'overdue', count(*)::numeric
    FROM action_items WHERE status <> 'completed' AND due_date IS NOT NULL AND due_date < v_today;

  -- التكليفات
  RETURN QUERY SELECT 'department_tasks', 'status:'||status, count(*)::numeric
    FROM department_tasks WHERE created_at >= v_lo AND created_at < v_hi GROUP BY status;

  -- القرارات
  RETURN QUERY SELECT 'decisions', 'status:'||status, count(*)::numeric
    FROM decisions WHERE created_at >= v_lo AND created_at < v_hi GROUP BY status;
  RETURN QUERY SELECT 'decisions', 'overdue', count(*)::numeric
    FROM decisions WHERE status NOT IN ('executed','cancelled') AND due_date IS NOT NULL AND due_date < v_today;

  -- الصيانة: بالحالة + إجمالي التكاليف
  RETURN QUERY SELECT 'maintenance', 'status:'||status, count(*)::numeric
    FROM maintenance_requests WHERE created_at >= v_lo AND created_at < v_hi GROUP BY status;
  RETURN QUERY SELECT 'maintenance', 'total_estimated_cost', COALESCE(sum(estimated_cost),0)
    FROM maintenance_requests WHERE created_at >= v_lo AND created_at < v_hi;
  RETURN QUERY SELECT 'maintenance', 'total_final_cost', COALESCE(sum(final_cost),0)
    FROM maintenance_requests WHERE created_at >= v_lo AND created_at < v_hi;

  -- الجودة: متوسط المطابقة + عدم المطابقة
  RETURN QUERY SELECT 'quality', 'avg_compliance_pct', COALESCE(round(avg(compliance_pct),1),0)
    FROM quality_visits WHERE created_at >= v_lo AND created_at < v_hi;
  RETURN QUERY SELECT 'quality', 'non_conform_items', count(*)::numeric
    FROM quality_visit_items qi WHERE qi.status = 'non_conform'
      AND EXISTS (SELECT 1 FROM quality_visits v WHERE v.id = qi.visit_id AND v.created_at >= v_lo AND v.created_at < v_hi);

  -- الطوارئ: بحالة المعالجة + متوسط زمن الاستجابة (دقائق)
  RETURN QUERY SELECT 'emergency', 'status:'||processing_status, count(*)::numeric
    FROM emergency_alerts WHERE created_at >= v_lo AND created_at < v_hi GROUP BY processing_status;
  RETURN QUERY SELECT 'emergency', 'avg_response_minutes',
    COALESCE(round(avg(EXTRACT(EPOCH FROM (first_response_at - created_at))/60)::numeric,1),0)
    FROM emergency_alerts WHERE first_response_at IS NOT NULL AND created_at >= v_lo AND created_at < v_hi;

  -- طلبات التوصيل: بالحالة + الإجمالي المالي
  RETURN QUERY SELECT 'delivery', 'status:'||COALESCE(status,'submitted'), count(*)::numeric
    FROM branch_delivery_requests WHERE created_at >= v_lo AND created_at < v_hi GROUP BY status;
  RETURN QUERY SELECT 'delivery', 'total_amount', COALESCE(sum(amount),0)
    FROM branch_delivery_requests WHERE created_at >= v_lo AND created_at < v_hi;
END $$;

REVOKE ALL ON FUNCTION pilot_report_overview(DATE, DATE) FROM public;
GRANT EXECUTE ON FUNCTION pilot_report_overview(DATE, DATE) TO authenticated;

SELECT 'reports' AS object, 'pilot_report_overview ready' AS status;
