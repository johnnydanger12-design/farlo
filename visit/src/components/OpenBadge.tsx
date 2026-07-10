export function OpenBadge({ isOpen }: { isOpen: boolean }) {
  return (
    <span
      className="rounded-full px-2.5 py-0.5 text-xs font-medium"
      style={{
        color: isOpen ? 'var(--open)' : 'var(--closed)',
        backgroundColor: isOpen ? 'color-mix(in srgb, var(--open) 15%, transparent)' : 'color-mix(in srgb, var(--closed) 15%, transparent)',
      }}
    >
      {isOpen ? 'Open now' : 'Closed'}
    </span>
  );
}
