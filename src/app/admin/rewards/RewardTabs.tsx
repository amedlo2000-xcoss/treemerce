import Link from "next/link";

const TABS = [
  { href: "/admin/rewards", label: "報酬明細" },
  { href: "/admin/rewards/rates", label: "ランク別の割合" },
] as const;

export function RewardTabs({ current }: { current: (typeof TABS)[number]["href"] }) {
  return (
    <nav className="flex gap-2" aria-label="報酬">
      {TABS.map((t) => (
        <Link
          key={t.href}
          href={t.href}
          aria-current={t.href === current ? "page" : undefined}
          className={`rounded-2xl border px-4 py-2 text-[14px] font-medium ${
            t.href === current
              ? "border-brand bg-brand-soft text-brand"
              : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
          }`}
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}
