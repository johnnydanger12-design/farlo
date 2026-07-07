import { useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

// Deliberately code-entry, not click-the-link: as a home-screen web app on
// iOS, this runs in its own isolated storage container, separate from
// Safari. A magic-link click opens Safari (or Gmail's in-app browser) and
// creates the session there — the home-screen app's own storage never sees
// it. Typing the code never leaves this app, so there's no cross-context
// handoff to lose. Requires {{ .Token }} to be present in the Magic Link
// email template in Supabase (Authentication -> Email Templates).
export function AuthGate({ children }: { children: (session: Session) => ReactNode }) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [verifying, setVerifying] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  async function sendCode(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSending(true);
    const { error } = await supabase.auth.signInWithOtp({ email: email.trim() });
    setSending(false);
    if (error) {
      setError(error.message);
      return;
    }
    setSent(true);
  }

  async function verifyCode(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setVerifying(true);
    const { error } = await supabase.auth.verifyOtp({
      email: email.trim(),
      token: code.trim(),
      type: 'email',
    });
    setVerifying(false);
    if (error) {
      setError(error.message);
      return;
    }
    // onAuthStateChange picks up the new session; nothing else to do here.
  }

  if (session === undefined) {
    return <CenteredShell>Loading…</CenteredShell>;
  }

  if (!session) {
    return (
      <CenteredShell>
        <div className="w-full max-w-sm rounded-xl border border-[var(--border)] bg-[var(--panel)] p-8">
          <h1 className="mb-1 text-xl font-semibold">Farlo Dashboard</h1>
          <p className="mb-6 text-sm text-[var(--muted)]">
            {sent ? 'Enter the code from your email.' : 'Sign in with a one-time code.'}
          </p>
          {sent ? (
            <form onSubmit={verifyCode} className="flex flex-col gap-3">
              <input
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                required
                placeholder="123456"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                className="rounded-md border border-[var(--border)] bg-transparent px-3 py-2 text-center text-lg tracking-widest outline-none focus:border-[var(--accent)]"
              />
              <button
                type="submit"
                disabled={verifying}
                className="rounded-md bg-[var(--accent)] px-3 py-2 text-sm font-medium text-[#04121f] disabled:opacity-50"
              >
                {verifying ? 'Verifying…' : 'Verify code'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setSent(false);
                  setCode('');
                  setError(null);
                }}
                className="text-xs text-[var(--muted)]"
              >
                Use a different email
              </button>
              {error && <p className="text-sm text-[var(--bad)]">{error}</p>}
            </form>
          ) : (
            <form onSubmit={sendCode} className="flex flex-col gap-3">
              <input
                type="email"
                required
                placeholder="you@farlo.app"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="rounded-md border border-[var(--border)] bg-transparent px-3 py-2 text-sm outline-none focus:border-[var(--accent)]"
              />
              <button
                type="submit"
                disabled={sending}
                className="rounded-md bg-[var(--accent)] px-3 py-2 text-sm font-medium text-[#04121f] disabled:opacity-50"
              >
                {sending ? 'Sending…' : 'Send code'}
              </button>
              {error && <p className="text-sm text-[var(--bad)]">{error}</p>}
            </form>
          )}
        </div>
      </CenteredShell>
    );
  }

  return <>{children(session)}</>;
}

function CenteredShell({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-svh items-center justify-center p-6">{children}</div>
  );
}
