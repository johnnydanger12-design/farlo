import { useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { AuthGate } from './components/AuthGate';
import { FleetOverview } from './components/FleetOverview';
import { CostSection } from './components/CostSection';
import { DirectivesSection } from './components/DirectivesSection';
import { ContentSection } from './components/ContentSection';
import { OutreachSection } from './components/OutreachSection';
import { BusinessSnapshot } from './components/BusinessSnapshot';
import { supabase } from './lib/supabase';

const TABS = ['Fleet', 'Cost', 'Directives', 'Content', 'Outreach', 'Business'] as const;
type Tab = (typeof TABS)[number];

function Dashboard({ session }: { session: Session }) {
  const [tab, setTab] = useState<Tab>('Fleet');

  return (
    <div className="mx-auto max-w-6xl px-6 py-8">
      <header className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">Farlo Dashboard</h1>
          <p className="text-xs text-[var(--muted)]">{session.user.email}</p>
        </div>
        <button
          onClick={() => supabase.auth.signOut()}
          className="rounded-md border border-[var(--border)] px-3 py-1.5 text-sm"
        >
          Sign out
        </button>
      </header>

      <nav className="mb-6 flex gap-1 border-b border-[var(--border)]">
        {TABS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`border-b-2 px-4 py-2 text-sm font-medium transition-colors ${
              tab === t
                ? 'border-[var(--accent)] text-[var(--text)]'
                : 'border-transparent text-[var(--muted)] hover:text-[var(--text)]'
            }`}
          >
            {t}
          </button>
        ))}
      </nav>

      {tab === 'Fleet' && <FleetOverview />}
      {tab === 'Cost' && <CostSection />}
      {tab === 'Directives' && <DirectivesSection />}
      {tab === 'Content' && <ContentSection />}
      {tab === 'Outreach' && <OutreachSection />}
      {tab === 'Business' && <BusinessSnapshot />}
    </div>
  );
}

function App() {
  return <AuthGate>{(session) => <Dashboard session={session} />}</AuthGate>;
}

export default App;
