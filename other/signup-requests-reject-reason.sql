-- ==========================================
-- Signup Requests: عمود سبب الرفض
-- Safe to re-run.
-- ==========================================
alter table signup_requests add column if not exists rejection_reason text;
