import { useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { AuthGate } from './components/AuthGate';
import { FleetOverview } from './components/FleetOverview';
import { DirectivesSection } from './components/DirectivesSection';
import { OutreachSection } from './components/OutreachSection';
import { BusinessSnapshot } from './components/BusinessSnapshot';
import { ChatSection } from './components/ChatSection';
import { supabase } from './lib/supabase';

const TABS = ['Business', 'Outreach', 'Directives', 'Chat', 'Fleet'] as const;
type Tab = (typeof TABS)[number];

function MenuIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <path d="M3 5.5h14M3 10h14M3 14.5h14" />
    </svg>
  );
}

function Dashboard({ session }: { session: Session }) {
  const [tab, setTab] = useState<Tab>('Business');
  const [menuOpen, setMenuOpen] = useState(false);

  function select(t: Tab) {
    setTab(t);
    setMenuOpen(false);
  }

  return (
    // h-full (not min-h) + overflow-hidden: this shell is exactly one screen tall
    // (#root is a fixed 100dvh, see index.css). Every tab's content lives inside a
    // flex-1 min-h-0 region below that scrolls *itself* — nothing here relies on
    // page-level (body) scroll, which is what makes the Chat tab able to fill the
    // real screen instead of sitting as a box inside a longer scrollable page.
    <div className="flex h-full flex-col overflow-hidden">
      <div className="mx-auto w-full max-w-6xl shrink-0 px-6 pt-8">
        <header className="mb-8 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setMenuOpen(true)}
              aria-label="Open menu"
              className="rounded-md border border-[var(--border)] p-2 text-[var(--text)] hover:border-[var(--accent)]"
            >
              <MenuIcon />
            </button>
            <div>
              <h1 className="text-lg font-semibold">Farlo Dashboard</h1>
              <p className="text-xs text-[var(--muted)]">{session.user.email}</p>
            </div>
          </div>
          <button
            onClick={() => supabase.auth.signOut()}
            className="rounded-md border border-[var(--border)] px-3 py-1.5 text-sm"
          >
            Sign out
          </button>
        </header>
      </div>

      {/* Backdrop */}
      <div
        onClick={() => setMenuOpen(false)}
        className={`fixed inset-0 z-40 bg-black/50 transition-opacity ${
          menuOpen ? 'pointer-events-auto opacity-100' : 'pointer-events-none opacity-0'
        }`}
      />

      {/* Drawer */}
      <nav
        style={{
          paddingTop: 'calc(env(safe-area-inset-top) + 1rem)',
          paddingBottom: 'calc(env(safe-area-inset-bottom) + 1rem)',
          paddingLeft: 'calc(env(safe-area-inset-left) + 1rem)',
        }}
        className={`fixed inset-y-0 left-0 z-50 w-64 border-r border-[var(--border)] bg-[var(--panel)] pr-4 shadow-xl transition-transform duration-200 ${
          menuOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <div className="mb-6 flex items-center justify-between">
          <span className="text-sm font-semibold">Farlo</span>
          <button
            onClick={() => setMenuOpen(false)}
            aria-label="Close menu"
            className="rounded-md p-1 text-[var(--muted)] hover:text-[var(--text)]"
          >
            ✕
          </button>
        </div>
        <div className="flex flex-col gap-1">
          {TABS.map((t) => (
            <button
              key={t}
              onClick={() => select(t)}
              className={`rounded-md px-3 py-2 text-left text-sm font-medium transition-colors ${
                tab === t
                  ? 'bg-[var(--accent)] text-[#04121f]'
                  : 'text-[var(--muted)] hover:bg-black/20 hover:text-[var(--text)]'
              }`}
            >
              {t}
            </button>
          ))}
        </div>
      </nav>

      {tab === 'Chat' ? (
        <div className="mx-auto flex w-full min-h-0 max-w-6xl flex-1 flex-col px-6 pb-6">
          <ChatSection />
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto max-w-6xl px-6 pb-8">
            {tab === 'Business' && <BusinessSnapshot />}
            {tab === 'Outreach' && <OutreachSection />}
            {tab === 'Directives' && <DirectivesSection />}
            {tab === 'Fleet' && <FleetOverview />}
          </div>
        </div>
      )}
    </div>
  );
}

function App() {
  return <AuthGate>{(session) => <Dashboard session={session} />}</AuthGate>;
}

export default App;
