-- ═══════════════════════════════════════════════════════════
-- دالة تجميع سريع للـ Dashboard — Perf Fix v121
-- ═══════════════════════════════════════════════════════════
-- تُستخدم في pageDashboard بدل ثلاث استعلامات بلا حد
-- تُرجع JSON فيه كل الأرقام اللي تحتاجها الشاشة الأولى
-- التنفيذ آمن ومتكرر (idempotent — CREATE OR REPLACE FUNCTION)
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION dashboard_summary(p_user_id BIGINT, p_dept_id BIGINT DEFAULT NULL, p_is_admin BOOLEAN DEFAULT FALSE)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
  v_today       DATE := CURRENT_DATE;
BEGIN
  RETURN json_build_object(
    'meetings', json_build_object(
      'this_month', (
        SELECT COUNT(*) FROM meetings m WHERE m.meeting_datetime >= v_month_start::TIMESTAMPTZ
        AND (p_is_admin
             OR (p_dept_id IS NOT NULL AND m.department_id = p_dept_id)
             OR m.organizer_id = p_user_id)
      ),
      'open', (
        SELECT COUNT(*) FROM meetings m WHERE m.status IN ('scheduled', 'in_follow_up')
        AND (p_is_admin
             OR (p_dept_id IS NOT NULL AND m.department_id = p_dept_id)
             OR m.organizer_id = p_user_id)
      ),
      'closed', (
        SELECT COUNT(*) FROM meetings m WHERE m.status = 'closed'
        AND m.meeting_datetime >= (v_month_start - INTERVAL '3 months')::TIMESTAMPTZ
        AND (p_is_admin
             OR (p_dept_id IS NOT NULL AND m.department_id = p_dept_id)
             OR m.organizer_id = p_user_id)
      )
    ),
    'tasks', json_build_object(
      'completed', (
        SELECT COUNT(*) FROM action_items ai WHERE ai.status = 'completed'
        AND ai.updated_at >= (v_month_start - INTERVAL '3 months')::TIMESTAMPTZ
        AND (p_is_admin
             OR (p_dept_id IS NOT NULL AND ai.department_id = p_dept_id)
             OR ai.assigned_to = p_user_id)
      ),
      'delayed', (
        SELECT COUNT(*) FROM action_items ai
        WHERE (ai.status = 'delayed' OR (ai.due_date IS NOT NULL AND ai.due_date < v_today AND ai.status <> 'completed'))
        AND (p_is_admin
             OR (p_dept_id IS NOT NULL AND ai.department_id = p_dept_id)
             OR ai.assigned_to = p_user_id)
      )
    ),
    'maintenance', json_build_object(
      'urgent_open', (
        SELECT COUNT(*) FROM maintenance_requests mr
        WHERE mr.severity IN ('high', 'critical') AND mr.status NOT IN ('closed', 'rejected')
      )
    )
  );
END;
$$;

-- تحقق:
-- SELECT dashboard_summary(1, NULL, TRUE);  -- كل الأقسام لمدير
-- SELECT dashboard_summary(1, 2, FALSE);    -- قسم 2 لموظف عادي
