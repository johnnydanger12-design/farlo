-- truck-menus was PDF-only and its insert policy let ANY authenticated user
-- upload into ANY truck's folder (no ownership scoping), with no delete
-- policy at all — same class of gap already fixed for menu-item-photos in
-- 20260704155653_scope_menu_item_photos_storage_policies_by_truck_ownership.sql.
-- Widen mime types to also accept a photo of a paper menu (not just PDF), and
-- scope insert/delete to the truck's owner via auth_user_owns_truck(), keyed
-- off the existing <truck_id>/<filename> upload path convention
-- (StorageService.uploadImage's ownerId param is passed the truck id for
-- this bucket, matching the menu-item-photos call site).

update storage.buckets
set allowed_mime_types = array['application/pdf','image/jpeg','image/png','image/webp']
where id = 'truck-menus';

drop policy if exists "menus_upload_auth" on storage.objects;

create policy "menus_upload_owner" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'truck-menus'
  and auth_user_owns_truck(((storage.foldername(name))[1])::uuid)
);

create policy "menus_delete_owner" on storage.objects
for delete to authenticated
using (
  bucket_id = 'truck-menus'
  and auth_user_owns_truck(((storage.foldername(name))[1])::uuid)
);
