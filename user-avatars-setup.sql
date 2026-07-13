-- ═══════════════════════════════════════════════════════════
-- إضافة عمود صورة الملف الشخصي + Storage Bucket للصور
-- شغّل هذا الملف مرة واحدة على Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- 1) عمود الصورة في جدول المستخدمين
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url text;
COMMENT ON COLUMN users.avatar_url IS 'رابط صورة الملف الشخصي في Storage';

-- 2) إنشاء Bucket عام للصور
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('user-avatars', 'user-avatars', true, 5242880, ARRAY['image/jpeg','image/png','image/webp','image/gif'])
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif'];

-- 3) سياسات السماح بالرفع والقراءة
DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects FOR SELECT
  USING (bucket_id = 'user-avatars');

DROP POLICY IF EXISTS "avatars_authenticated_upload" ON storage.objects;
CREATE POLICY "avatars_authenticated_upload" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'user-avatars');

DROP POLICY IF EXISTS "avatars_authenticated_update" ON storage.objects;
CREATE POLICY "avatars_authenticated_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'user-avatars');

DROP POLICY IF EXISTS "avatars_authenticated_delete" ON storage.objects;
CREATE POLICY "avatars_authenticated_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'user-avatars');
