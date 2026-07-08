import { useEffect, useState } from 'react';
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Stat } from './ui';
import { CostSection } from './CostSection';

interface Snapshot {
  totalConsumers: number;
  totalOwners: number;
  activeBusinesses: number;
  liveNow: number;
  activeSubscriptionsByPlan: Record<string, number>;
  openTickets: number;
  urgentTickets: number;
  signupsByDay: { date: string; count: number }[];
}

const DAY_MS = 24 * 60 * 60 * 1000;

export function BusinessSnapshot() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const [profilesRes, trucksRes, subsRes, ticketsRes] = await Promise.all([
        supabase.from('profiles').select('role, created_at'),
        supabase.from('food_trucks').select('is_active, is_open'),
        supabase.from('subscriptions').select('status, product_identifier'),
        supabase.from('support_tickets').select('status, priority'),
      ]);

      if (cancelled) return;

      const firstError = [profilesRes, trucksRes, subsRes, ticketsRes].find((r) => r.error)?.error;
      if (firstError) {
        setError(firstError.message);
        return;
      }

      const profiles = profilesRes.data ?? [];
      const trucks = trucksRes.data ?? [];
      const subs = subsRes.data ?? [];
      const tickets = ticketsRes.data ?? [];

      const since = Date.now() - 30 * DAY_MS;
      const dayBuckets = new Map<string, number>();
      for (const p of profiles) {
        const t = new Date(p.created_at).getTime();
        if (t < since) continue;
        const day = p.created_at.slice(0, 10);
        dayBuckets.set(day, (dayBuckets.get(day) ?? 0) + 1);
      }
      const signupsByDay = [...dayBuckets.entries()]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([date, count]) => ({ date: date.slice(5), count }));

      const activeSubscriptionsByPlan: Record<string, number> = {};
      for (const s of subs) {
        if (s.status !== 'active' && s.status !== 'trialing') continue;
        const plan = s.product_identifier ?? 'unknown';
        activeSubscriptionsByPlan[plan] = (activeSubscriptionsByPlan[plan] ?? 0) + 1;
      }

      setSnapshot({
        totalConsumers: profiles.filter((p) => p.role === 'consumer').length,
        totalOwners: profiles.filter((p) => p.role === 'owner').length,
        activeBusinesses: trucks.filter((t) => t.is_active).length,
        liveNow: trucks.filter((t) => t.is_open).length,
        activeSubscriptionsByPlan,
        openTickets: tickets.filter((t) => t.status === 'open').length,
        urgentTickets: tickets.filter((t) => t.priority === 'urgent' && t.status === 'open').length,
        signupsByDay,
      });
    }

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  if (error) return <Card title="Business snapshot"><ErrorNote message={error} /></Card>;
  if (!snapshot) return <Card title="Business snapshot"><Loading /></Card>;

  const totalActiveSubs = Object.values(snapshot.activeSubscriptionsByPlan).reduce((a, b) => a + b, 0);

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <Card title="Business snapshot">
        <div className="grid grid-cols-2 gap-6 sm:grid-cols-3 lg:grid-cols-5">
          <Stat label="Consumers" value={snapshot.totalConsumers} />
          <Stat label="Truck owners" value={snapshot.totalOwners} />
          <Stat label="Active businesses" value={snapshot.activeBusinesses} sub={`${snapshot.liveNow} live now`} />
          <Stat
            label="Active subscriptions"
            value={totalActiveSubs}
            sub={Object.entries(snapshot.activeSubscriptionsByPlan)
              .map(([plan, n]) => `${n} ${plan}`)
              .join(', ') || 'none'}
          />
          <Stat
            label="Open tickets"
            value={snapshot.openTickets}
            sub={snapshot.urgentTickets > 0 ? `${snapshot.urgentTickets} urgent` : undefined}
          />
        </div>
      </Card>

      <Card title="Signups — last 30 days">
        <div className="h-56 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={snapshot.signupsByDay}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
              <XAxis dataKey="date" stroke="var(--muted)" fontSize={12} />
              <YAxis stroke="var(--muted)" fontSize={12} allowDecimals={false} />
              <Tooltip contentStyle={{ background: 'var(--panel)', border: '1px solid var(--border)' }} />
              <Line type="monotone" dataKey="count" stroke="var(--accent)" strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </Card>

      <CostSection />
    </div>
  );
}
