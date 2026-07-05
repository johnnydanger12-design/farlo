DROP POLICY logos_upload_auth ON storage.objects;
CREATE POLICY logos_upload_auth ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'truck-logos' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY photos_upload_auth ON storage.objects;
CREATE POLICY photos_upload_auth ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'truck-photos' AND auth.uid()::text = (storage.foldername(name))[1]);
