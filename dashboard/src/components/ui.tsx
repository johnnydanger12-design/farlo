import type { ReactNode } from 'react';

export function Card({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="min-w-0 rounded-xl border border-[var(--border)] bg-[var(--panel)] p-5">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-[var(--muted)]">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

export function Stat({ label, value, sub }: { label: string; value: ReactNode; sub?: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs uppercase tracking-wide text-[var(--muted)]">{label}</span>
      <span className="text-2xl font-semibold">{value}</span>
      {sub && <span className="text-xs text-[var(--muted)]">{sub}</span>}
    </div>
  );
}

type PillTone = 'good' | 'warn' | 'bad' | 'muted';

export function Pill({ tone, children }: { tone: PillTone; children: ReactNode }) {
  const colors: Record<PillTone, string> = {
    good: 'bg-[color-mix(in_srgb,var(--good)_18%,transparent)] text-[var(--good)]',
    warn: 'bg-[color-mix(in_srgb,var(--warn)_18%,transparent)] text-[var(--warn)]',
    bad: 'bg-[color-mix(in_srgb,var(--bad)_18%,transparent)] text-[var(--bad)]',
    muted: 'bg-[color-mix(in_srgb,var(--muted)_18%,transparent)] text-[var(--muted)]',
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${colors[tone]}`}>
      {children}
    </span>
  );
}

export function Modal({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
}) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <div onClick={onClose} className="absolute inset-0 bg-black/60" />
      <div
        className="relative z-10 max-h-[85vh] w-full min-w-0 overflow-y-auto rounded-t-2xl border border-[var(--border)] bg-[var(--panel)] p-4 sm:max-w-lg sm:rounded-2xl"
        style={{ paddingBottom: 'calc(env(safe-area-inset-bottom) + 1rem)' }}
      >
        <div className="mb-3 flex items-center justify-between gap-3">
          <h3 className="min-w-0 truncate text-sm font-semibold">{title}</h3>
          <button
            onClick={onClose}
            aria-label="Close"
            className="shrink-0 rounded-md p-1 text-[var(--muted)] hover:text-[var(--text)]"
          >
            ✕
          </button>
        </div>
        <div className="min-w-0">{children}</div>
      </div>
    </div>
  );
}

export function ErrorNote({ message }: { message: string }) {
  return <p className="text-sm text-[var(--bad)]">{message}</p>;
}

export function Loading() {
  return <p className="text-sm text-[var(--muted)]">Loading…</p>;
}
