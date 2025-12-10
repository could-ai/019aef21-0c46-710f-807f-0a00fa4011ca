CREATE TABLE IF NOT EXISTS user_trained_images (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  image_url TEXT NOT NULL,
  file_name TEXT,
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE user_trained_images ENABLE ROW LEVEL SECURITY;

-- Allow public access for now (since no auth yet)
CREATE POLICY "Allow all operations on user_trained_images" ON user_trained_images FOR ALL USING (true);

-- Storage bucket setup
INSERT INTO storage.buckets (id, name, public)
VALUES ('user_uploads', 'user_uploads', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
CREATE POLICY "Allow all operations on user_uploads" ON storage.objects FOR ALL USING (bucket_id = 'user_uploads');
