// Pure decision logic extracted out of index.ts so it's unit-testable without
// mocking the Supabase client (same pattern as create-payment-intent's
// pricing.ts) — the DB's partial unique index on
// data_export_requests(user_id) WHERE status IN ('pending','processing') is
// the real guarantee; this is just the friendlier pre-check that lets the
// Edge Function return a clear 409 instead of surfacing a raw constraint
// violation to the client.

export interface ExportRequestRow {
  status: string;
}

export function hasActiveRequest(existing: ExportRequestRow[]): boolean {
  return existing.some((r) => r.status === 'pending' || r.status === 'processing');
}
