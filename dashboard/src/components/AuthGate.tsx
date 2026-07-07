import { useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

export function AuthGate({ children }: { children: (session: Session) => ReactNode }) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  async function sendMagicLink(e: React.FormEvent) {
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

  if (session === undefined) {
    return <CenteredShell>Loading…</CenteredShell>;
  }

  if (!session) {
    return (
      <CenteredShell>
        <div className="w-full max-w-sm rounded-xl border border-[var(--border)] bg-[var(--panel)] p-8">
          <h1 className="mb-1 text-xl font-semibold">Farlo Dashboard</h1>
          <p className="mb-6 text-sm text-[var(--muted)]">Sign in with a magic link.</p>
          {sent ? (
            <p className="text-sm text-[var(--good)]">
              Check {email} for a sign-in link.
            </p>
          ) : (
            <form onSubmit={sendMagicLink} className="flex flex-col gap-3">
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
                {sending ? 'Sending…' : 'Send magic link'}
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
