-- Photo attachments for the Aiden chat. Unlike every other bucket in this project
-- (avatars, truck-photos, etc. — all public=true, scoped by auth.uid() folder prefix),
-- this one is founder-only, so it's private and gated by is_founder() directly rather
-- than the per-user-folder convention those buckets use.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types, avif_autodetection)
values
  ('aiden-chat-photos', 'aiden-chat-photos', false, 5242880, array['image/jpeg','image/png','image/webp'], false)
on conflict (id) do nothing;

create policy "aiden_chat_photos_founder_all" on storage.objects for all to authenticated
  using (bucket_id = 'aiden-chat-photos' and is_founder())
  with check (bucket_id = 'aiden-chat-photos' and is_founder());
