-- menu-item-photos INSERT/DELETE policies previously checked only bucket_id, with
-- no ownership/path scoping — any authenticated user could overwrite or delete any
-- truck's menu photos (supabase-audit.md Critical #4). The upload path convention
-- (storage_service.dart's uploadImage) is always "<truck_id>/<filename>", so the
-- first path segment IS the truck id. Scope both policies to callers who own that
-- truck, matching the auth_user_owns_truck() helper menu_items' own RLS already
-- uses. Validated red/green against an isolated Supabase branch before applying here.

drop policy "Authenticated users can upload menu item photos" on storage.objects;
drop policy "Authenticated users can delete menu item photos" on storage.objects;

create policy "Authenticated users can upload menu item photos" on storage.objects
for insert
with check (
  bucket_id = 'menu-item-photos'
  and auth_user_owns_truck(((storage.foldername(name))[1])::uuid)
);

create policy "Authenticated users can delete menu item photos" on storage.objects
for delete
using (
  bucket_id = 'menu-item-photos'
  and auth_user_owns_truck(((storage.foldername(name))[1])::uuid)
);
