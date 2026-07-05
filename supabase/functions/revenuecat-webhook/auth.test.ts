// security.md §4 Consolidated Risk Register, Medium — "revenuecat-webhook
// fails open (skips signature check) if REVENUECAT_WEBHOOK_SECRET unset."
// Run with: deno test supabase/functions/revenuecat-webhook/auth.test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { isAuthorizedWebhookRequest } from './auth.ts';

Deno.test('rejects every request when the secret is unset — fails closed, not open', () => {
  assertEquals(isAuthorizedWebhookRequest('', 'anything'), false);
  assertEquals(isAuthorizedWebhookRequest('', null), false);
  assertEquals(isAuthorizedWebhookRequest('', ''), false);
});

Deno.test('rejects a request with a missing Authorization header when a secret is configured', () => {
  assertEquals(isAuthorizedWebhookRequest('real-secret', null), false);
});

Deno.test('rejects a request with the wrong Authorization value', () => {
  assertEquals(isAuthorizedWebhookRequest('real-secret', 'wrong-secret'), false);
});

Deno.test('accepts a request with the correct Authorization value', () => {
  assertEquals(isAuthorizedWebhookRequest('real-secret', 'real-secret'), true);
});
