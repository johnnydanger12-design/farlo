// Gmail API access via a Google Workspace domain-wide-delegation service account.
// The JWT-signing (pemToBytes/b64url/RS256 via crypto.subtle) is the same code already
// proven in send-truck-announcement/index.ts for FCM — only the scope and the added
// `sub` claim (for mailbox impersonation) differ.

interface ServiceAccount {
  client_email: string;
  private_key: string;
}

function pemToBytes(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function b64url(input: string | ArrayBuffer): string {
  const s = typeof input === 'string'
    ? btoa(input)
    : btoa(String.fromCharCode(...new Uint8Array(input)));
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

const GMAIL_SCOPE = 'https://www.googleapis.com/auth/gmail.modify';

// impersonate: the mailbox to act as (e.g. 'support@farlo.app') — the service account
// must be authorized for domain-wide delegation with GMAIL_SCOPE in the Workspace admin
// console for this to succeed.
export async function getGmailAccessToken(impersonate: string): Promise<string> {
  const saJson = Deno.env.get('GMAIL_SERVICE_ACCOUNT_JSON');
  if (!saJson) throw new Error('GMAIL_SERVICE_ACCOUNT_JSON not configured');
  const sa: ServiceAccount = JSON.parse(saJson);

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: GMAIL_SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    sub: impersonate,
    iat: now,
    exp: now + 3600,
  };

  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${b64url(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) {
    throw new Error(`Gmail token exchange failed for ${impersonate}: ${JSON.stringify(data)}`);
  }
  return data.access_token as string;
}

const GMAIL_API = 'https://gmail.googleapis.com/gmail/v1/users/me';

// deno-lint-ignore no-explicit-any
async function gmailFetch(accessToken: string, path: string, init?: RequestInit): Promise<any> {
  const res = await fetch(`${GMAIL_API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gmail API error (${res.status}) ${path}: ${errText}`);
  }
  return res.status === 204 ? null : res.json();
}

export interface GmailThreadSummary {
  id: string;
}

export async function searchThreads(
  accessToken: string,
  query: string,
  maxResults = 25,
): Promise<GmailThreadSummary[]> {
  const params = new URLSearchParams({ q: query, maxResults: String(maxResults) });
  const data = await gmailFetch(accessToken, `/threads?${params}`);
  return data.threads ?? [];
}

// deno-lint-ignore no-explicit-any
export async function getThread(accessToken: string, threadId: string): Promise<any> {
  return gmailFetch(accessToken, `/threads/${threadId}?format=full`);
}

// Real From/To headers are usually `"Display Name" <email@domain.com>`, not a bare
// address — extract just the address so callers can safely test/compare it. Anchoring a
// regex directly against the raw header (e.g. testing for a trailing "@farlo.app") is a
// trap: it silently never matches because the header actually ends in "@farlo.app>".
export function extractEmailAddress(header: string): string {
  const match = header.match(/<([^>]+)>/);
  return (match ? match[1] : header).trim().toLowerCase();
}

// Detects no-reply addresses, auto-responders (vacation replies, out-of-office), and
// bounce/delivery-failure messages, so an auto-sending agent never replies to one and
// risks a reply loop with another automated system on the other end. Checks the
// standard signals well-behaved auto-responders set (RFC 3834 Auto-Submitted,
// Precedence) plus common address/subject conventions for systems that don't.
export function looksAutomated(headers: Record<string, string>, fromEmail: string): boolean {
  const autoSubmitted = (headers['Auto-Submitted'] ?? '').toLowerCase();
  if (autoSubmitted && autoSubmitted !== 'no') return true;

  const precedence = (headers['Precedence'] ?? '').toLowerCase();
  if (['bulk', 'auto_reply', 'list'].includes(precedence)) return true;

  if (headers['X-Autoreply'] || headers['X-Autorespond']) return true;

  if (/no-?reply|do-?not-?reply|mailer-daemon|postmaster|^bounce/i.test(fromEmail)) return true;

  const subject = headers['Subject'] ?? '';
  if (/out of office|automatic reply|auto-reply|delivery status notification|undeliverable|mail delivery (failed|fail)/i.test(subject)) return true;

  return false;
}

function decodeBase64Url(s: string): string {
  return decodeURIComponent(escape(atob(s.replace(/-/g, '+').replace(/_/g, '/'))));
}

// deno-lint-ignore no-explicit-any
export function extractPlainTextBody(payload: any): string {
  if (!payload) return '';
  if (payload.mimeType === 'text/plain' && payload.body?.data) {
    return decodeBase64Url(payload.body.data);
  }
  for (const part of payload.parts ?? []) {
    const text = extractPlainTextBody(part);
    if (text) return text;
  }
  return '';
}

function encodeSubject(text: string): string {
  if (/^[\x00-\x7F]*$/.test(text)) return text;
  return `=?UTF-8?B?${btoa(unescape(encodeURIComponent(text)))}?=`;
}

function buildRawMessage(opts: {
  from: string;
  to: string;
  subject: string;
  bodyText: string;
  inReplyToMessageId?: string;
  references?: string;
}): string {
  const headers = [
    `From: ${opts.from}`,
    `To: ${opts.to}`,
    `Subject: ${encodeSubject(opts.subject)}`,
    'Content-Type: text/plain; charset="UTF-8"',
    'MIME-Version: 1.0',
  ];
  if (opts.inReplyToMessageId) headers.push(`In-Reply-To: ${opts.inReplyToMessageId}`);
  if (opts.references) headers.push(`References: ${opts.references}`);
  const raw = `${headers.join('\r\n')}\r\n\r\n${opts.bodyText}`;
  // Encode as UTF-8 bytes before base64 — btoa() on the raw string only supports
  // Latin1 and throws on anything outside it (en-dashes, arrows, curly quotes, etc,
  // which show up often in normal LLM-written prose). The Subject header itself still
  // needs its own RFC 2047 encoded-word treatment (encodeSubject, above) since header
  // encoding rules are separate from the raw message's transport-level bytes.
  return b64url(new TextEncoder().encode(raw).buffer);
}

// Creates a draft — never sends. Used by Miles (outreach always needs Johnny's review
// before it reaches a prospect) and anywhere else a human checkpoint is still wanted.
export async function createDraft(
  accessToken: string,
  opts: {
    from: string;
    to: string;
    subject: string;
    bodyText: string;
    threadId?: string;
    inReplyToMessageId?: string;
    references?: string;
  },
): Promise<{ id: string }> {
  const raw = buildRawMessage(opts);
  const message: Record<string, unknown> = { raw };
  if (opts.threadId) message.threadId = opts.threadId;
  return gmailFetch(accessToken, '/drafts', {
    method: 'POST',
    body: JSON.stringify({ message }),
  });
}

// Actually sends. Used by Sage for confident, support_kb-grounded answers — every call
// site using this must append an AI-disclosure line to the body; see agent-sage.
export async function sendMessage(
  accessToken: string,
  opts: {
    from: string;
    to: string;
    subject: string;
    bodyText: string;
    threadId?: string;
    inReplyToMessageId?: string;
    references?: string;
  },
): Promise<{ id: string; threadId: string }> {
  const raw = buildRawMessage(opts);
  const body: Record<string, unknown> = { raw };
  if (opts.threadId) body.threadId = opts.threadId;
  return gmailFetch(accessToken, '/messages/send', {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export async function listLabels(accessToken: string): Promise<{ id: string; name: string }[]> {
  const data = await gmailFetch(accessToken, '/labels');
  return data.labels ?? [];
}

// Looks labels up by display name rather than hardcoding Gmail's account-specific
// generated IDs (e.g. "Label_6") — more robust than the ID literals the old Cowork
// prompts used, and self-documenting.
export async function getLabelIdMap(accessToken: string): Promise<Record<string, string>> {
  const labels = await listLabels(accessToken);
  const map: Record<string, string> = {};
  for (const l of labels) map[l.name] = l.id;
  return map;
}

export async function addLabel(accessToken: string, threadId: string, labelId: string): Promise<void> {
  await gmailFetch(accessToken, `/threads/${threadId}/modify`, {
    method: 'POST',
    body: JSON.stringify({ addLabelIds: [labelId] }),
  });
}

export async function removeLabel(accessToken: string, threadId: string, labelId: string): Promise<void> {
  await gmailFetch(accessToken, `/threads/${threadId}/modify`, {
    method: 'POST',
    body: JSON.stringify({ removeLabelIds: [labelId] }),
  });
}
