// Shared bearer-secret check for cron -> function calls. Reuses AGENT_EMAIL_SECRET
// (already used by send-agent-email) rather than minting a new secret per function.
export function requireAgentSecret(req: Request): Response | null {
  const authHeader = req.headers.get('Authorization') ?? '';
  const secret = Deno.env.get('AGENT_EMAIL_SECRET') ?? '';
  if (!secret || authHeader !== `Bearer ${secret}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  return null;
}

// Dry-run mode: logs and would-be writes happen against agent_run_log as normal, but
// no real Gmail draft/label/send or content_queue/sales_prospects/support_tickets write
// happens. Checked per-request (query param) or globally (env var) so a function can be
// validated against Cowork's real output before being trusted with real mailboxes.
export function isDryRun(req: Request): boolean {
  const url = new URL(req.url);
  return url.searchParams.get('dry_run') === 'true' || Deno.env.get('AGENT_DRY_RUN') === 'true';
}
