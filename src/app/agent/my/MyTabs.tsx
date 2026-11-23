import Link from "next/link";

const TABS = [
  { href: "/agent/my", label: "プロフィール" },
  { href: "/agent/my/rewards", label: "報酬" },
] as const;

/** MY ページ内のタブ (下部ナビの「MY」はどちらでもアクティブ) */
export function MyTabs({ current }: { current: (typeof TABS)[number]["href"] }) {
  return (
    <nav className="grid grid-cols-2 gap-1 rounded-2xl bg-surface-muted p-1" aria-label="MY">
      {TABS.map((t) => (
        <Link
          key={t.href}
          href={t.href}
          aria-current={t.href === current ? "page" : undefined}
          className={`rounded-xl px-4 py-2 text-center text-[14px] font-semibold transition-colors ${
            t.href === current
              ? "bg-surface text-text-primary shadow-[var(--shadow-card)]"
              : "text-text-secondary hover:text-text-primary"
          }`}
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}
