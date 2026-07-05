-- Storage schema baseline capture — companion to 20260704000000_baseline_schema.sql.
--
-- The original baseline dump (iteration 1 of the remediation effort) excluded the
-- `storage` schema entirely (pg_dump schema-only captures of `storage` require the
-- extension's own objects to already exist, and the ad-hoc dump script used at the
-- time scoped to `public` only). That gap was never revisited: two of this
-- remediation effort's own Critical/High storage-bucket ownership fixes
-- (`scope_menu_item_photos_storage_policies_by_truck_ownership`,
-- `scope_truck_logos_photos_upload_to_own_user_folder`) were applied directly to the
-- remote project via `apply_migration` and existed only there — never committed,
-- not even in their pre-fix form. Rebuilding this project from git alone would have
-- silently omitted those fixes entirely.
--
-- This file captures every bucket and every storage.objects RLS policy exactly as
-- they exist on the live project as of this remediation pass (already in their
-- fixed, current form). It is dated to sort immediately after the public-schema
-- baseline and before the two storage-fix migrations below — those migrations'
-- DROP POLICY/CREATE POLICY statements replay harmlessly on top of the already-
-- correct definitions captured here (a no-op re-assertion), so final replayed state
-- matches live state exactly. Verified via a fresh-branch replay + schema diff
-- against the remote project (see REMEDIATION_LOG.md).

-- Buckets
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types, avif_autodetection)
values
  ('avatars', 'avatars', true, null, null, false),
  ('brand', 'brand', true, null, null, false),
  ('menu-item-photos', 'menu-item-photos', true, 5242880, array['image/jpeg','image/png','image/webp'], false),
  ('truck-logos', 'truck-logos', true, null, null, false),
  ('truck-menus', 'truck-menus', true, null, null, false),
  ('truck-photos', 'truck-photos', true, null, null, false)
on conflict (id) do nothing;

-- avatars
create policy "avatar_select" on storage.objects for select to public
  using (bucket_id = 'avatars');

create policy "avatar_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and name = (auth.uid())::text);

create policy "avatar_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and name = (auth.uid())::text);

create policy "avatar_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and name = (auth.uid())::text);

-- menu-item-photos (current/fixed form — pre-existing DROP+CREATE migrations below
-- reassert the same definitions, no-op)
create policy "Public can read menu item photos" on storage.objects for select to public
  using (bucket_id = 'menu-item-photos');

create policy "Authenticated users can upload menu item photos" on storage.objects for insert to public
  with check (bucket_id = 'menu-item-photos' and auth_user_owns_truck(((storage.foldername(name))[1])::uuid));

create policy "Authenticated users can delete menu item photos" on storage.objects for delete to public
  using (bucket_id = 'menu-item-photos' and auth_user_owns_truck(((storage.foldername(name))[1])::uuid));

-- truck-logos (current/fixed form)
create policy "logos_read_public" on storage.objects for select to public
  using (bucket_id = 'truck-logos');

create policy "logos_upload_auth" on storage.objects for insert to authenticated
  with check (bucket_id = 'truck-logos' and (auth.uid())::text = (storage.foldername(name))[1]);

create policy "logos_update_auth" on storage.objects for update to public
  using (bucket_id = 'truck-logos' and auth.uid() = owner);

create policy "logos_delete_auth" on storage.objects for delete to public
  using (bucket_id = 'truck-logos' and auth.uid() = owner);

-- truck-photos (current/fixed form)
create policy "photos_read_public" on storage.objects for select to public
  using (bucket_id = 'truck-photos');

create policy "photos_upload_auth" on storage.objects for insert to authenticated
  with check (bucket_id = 'truck-photos' and (auth.uid())::text = (storage.foldername(name))[1]);

create policy "photos_update_auth" on storage.objects for update to public
  using (bucket_id = 'truck-photos' and auth.uid() = owner);

create policy "photos_delete_auth" on storage.objects for delete to public
  using (bucket_id = 'truck-photos' and auth.uid() = owner);

-- truck-menus
create policy "menus_read_public" on storage.objects for select to public
  using (bucket_id = 'truck-menus');

create policy "menus_upload_auth" on storage.objects for insert to public
  with check (bucket_id = 'truck-menus' and auth.role() = 'authenticated');
