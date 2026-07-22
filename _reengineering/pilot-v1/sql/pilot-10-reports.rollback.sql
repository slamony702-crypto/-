-- Rollback التقارير (pilot-10): يزيل دوال التجميع فقط. لا أثر على بيانات.
DROP FUNCTION IF EXISTS pilot_report_overview(DATE, DATE);
DROP FUNCTION IF EXISTS pilot_riyadh_range(DATE, DATE);
SELECT 'reports rollback done';
