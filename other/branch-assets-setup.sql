-- ═══════════════════════════════════════════════════════════
-- جرد أصول الفروع — جدول + Storage bucket لصور الأصول
-- شغّل مرة واحدة على Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

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

-- Storage bucket لصور الأصول
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
