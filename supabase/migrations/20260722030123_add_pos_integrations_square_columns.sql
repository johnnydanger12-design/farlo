-- Square-specific columns. external_merchant_id/api_token_secret_name are reused
-- as Square's location-agnostic merchant id and access-token secret respectively.
alter table public.pos_integrations
  add column refresh_token_secret_name text,
  add column token_expires_at timestamptz,
  add column square_location_id text;
