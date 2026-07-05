// Pure webhook-authorization check, extracted so it's unit-testable —
// security.md §4 Consolidated Risk Register, Medium: "revenuecat-webhook
// fails open (skips signature check) if REVENUECAT_WEBHOOK_SECRET unset."
// The critical property this guards: an unconfigured secret must reject
// every request, never silently accept them.

export function isAuthorizedWebhookRequest(secret: string, authHeader: string | null): boolean {
  if (!secret) return false;
  return authHeader === secret;
}
