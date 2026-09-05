import Link from "next/link";

import { signOutAction } from "@/app/actions";

export const AGENT_NAV = [
  { href: "/agent", label: "ダッシュボード" },
  { href: "/agent/customers", label: "担当顧客" },
  { href: "/agent/commerce-map", label: "商流マップ" },
  { href: "/agent/analytics", label: "客層分析" },
  { href: "/agent/community", label: "コミュニティマップ" },
  { href: "/agent/invitations", label: "招待URL" },
];

/** STEP8: 「代理店管理」「商品購入者管理」「顧客担当管理」を別メニューにする。 */
export const ADMIN_NAV = [
  { href: "/admin", label: "ダッシュボード" },
  { href: "/admin/agents", label: "代理店管理" },
  { href: "/admin/customers", label: "商品購入者管理" },
  { href: "/admin/assignments", label: "顧客担当管理" },
  { href: "/admin/analytics", label: "客層分析" },
  { href: "/admin/audit-logs", label: "監査ログ" },
];

export function AppShell({
  brand,
  subtitle,
  nav,
  identity,
  children,
}: {
  brand: string;
  subtitle: string;
  nav: { href: string; label: string }[];
  identity: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-1 flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="border-b border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-6 py-3">
          <div className="flex items-baseline gap-3">
            <Link href="/" className="text-base font-semibold tracking-tight">
              {brand}
            </Link>
            <span className="text-xs text-zinc-500 dark:text-zinc-400">{subtitle}</span>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-xs text-zinc-500 dark:text-zinc-400">{identity}</span>
            <form action={signOutAction}>
              <button
                type="submit"
                className="rounded-lg border border-zinc-300 px-3 py-1.5 text-xs font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
              >
                ログアウト
              </button>
            </form>
          </div>
        </div>
        <nav className="mx-auto max-w-6xl overflow-x-auto px-6">
          <ul className="flex gap-1 whitespace-nowrap pb-2">
            {nav.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className="inline-block rounded-lg px-3 py-1.5 text-sm text-zinc-600 transition-colors hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-zinc-800 dark:hover:text-zinc-100"
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 space-y-6 px-6 py-8">{children}</main>
    </div>
  );
}
