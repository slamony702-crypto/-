-- ═══════════════════════════════════════════════════════════
-- 🚀 ملف واحد يشغّل كل الميزات الجديدة
-- شغّله مرة واحدة على Supabase SQL Editor
-- 👉 https://supabase.com/dashboard/project/dfuqmmagtteemtpywody/sql/new
-- ═══════════════════════════════════════════════════════════


-- ═══ 1) صورة الملف الشخصي ═══
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url text;
COMMENT ON COLUMN users.avatar_url IS 'رابط صورة الملف الشخصي في Storage';

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('user-avatars', 'user-avatars', true, 5242880, ARRAY['image/jpeg','image/png','image/webp','image/gif'])
ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = 5242880;

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects FOR SELECT USING (bucket_id = 'user-avatars');
DROP POLICY IF EXISTS "avatars_authenticated_upload" ON storage.objects;
CREATE POLICY "avatars_authenticated_upload" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'user-avatars');
DROP POLICY IF EXISTS "avatars_authenticated_update" ON storage.objects;
CREATE POLICY "avatars_authenticated_update" ON storage.objects FOR UPDATE USING (bucket_id = 'user-avatars');
DROP POLICY IF EXISTS "avatars_authenticated_delete" ON storage.objects;
CREATE POLICY "avatars_authenticated_delete" ON storage.objects FOR DELETE USING (bucket_id = 'user-avatars');


-- ═══ 2) جرد أصول الفروع ═══
CREATE TABLE IF NOT EXISTS branch_assets (
  id serial PRIMARY KEY,
  branch_id integer NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  category text NOT NULL,
  item_name text NOT NULL,
  brand text,
  model text,
  serial_no text,
  quantity integer DEFAULT 1,
  purchase_date date,
  purchase_cost numeric(12,2),
  current_condition text,
  location_in_branch text,
  photo_url text,
  notes text,
  created_by integer REFERENCES users(id),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_branch_assets_branch ON branch_assets(branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_assets_category ON branch_assets(category);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('branch-assets', 'branch-assets', true, 10485760, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "assets_public_read" ON storage.objects;
CREATE POLICY "assets_public_read" ON storage.objects FOR SELECT USING (bucket_id = 'branch-assets');
DROP POLICY IF EXISTS "assets_upload" ON storage.objects;
CREATE POLICY "assets_upload" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'branch-assets');
DROP POLICY IF EXISTS "assets_update" ON storage.objects;
CREATE POLICY "assets_update" ON storage.objects FOR UPDATE USING (bucket_id = 'branch-assets');
DROP POLICY IF EXISTS "assets_delete" ON storage.objects;
CREATE POLICY "assets_delete" ON storage.objects FOR DELETE USING (bucket_id = 'branch-assets');


-- ═══ 3) أعمدة إضافية للجودة (اختياري لكن مستحسن) ═══
ALTER TABLE quality_visit_items
  ADD COLUMN IF NOT EXISTS severity text,
  ADD COLUMN IF NOT EXISTS responsible_role text;
COMMENT ON COLUMN quality_visit_items.severity IS 'شدّة المخالفة: critical | medium | low';
COMMENT ON COLUMN quality_visit_items.responsible_role IS 'مسؤول الإصلاح كدور';


-- ═══ ✅ تم! ═══
SELECT '✅ تم تشغيل كل الملفات بنجاح' AS status;
