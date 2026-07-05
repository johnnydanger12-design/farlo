-- 4 of 5 public storage buckets had no file-size/MIME-type limit at all
-- (security.md §4 Consolidated Risk Register, Medium) — only menu-item-photos
-- (5MB, image/jpeg|png|webp) had one. Extend the same limits to the other
-- image buckets, and a PDF-appropriate limit to truck-menus. This is enforced
-- by the Storage API itself (reads storage.buckets.file_size_limit /
-- allowed_mime_types on every upload), not by RLS/triggers on storage.objects.
update storage.buckets set file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'] where id = 'avatars';
update storage.buckets set file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'] where id = 'truck-logos';
update storage.buckets set file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'] where id = 'truck-photos';
update storage.buckets set file_size_limit = 10485760, allowed_mime_types = array['application/pdf'] where id = 'truck-menus';
