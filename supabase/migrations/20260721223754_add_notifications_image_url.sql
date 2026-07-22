alter table notifications add column image_url text;
comment on column notifications.image_url is 'Optional photo attached to an owner announcement (e.g. a limited-time menu item). In-app inbox only — not sent as part of the FCM push itself, which stays plain title+body text.';
