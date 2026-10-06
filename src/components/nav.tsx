import { signOutAction } from "@/app/actions";
import { BottomNav, SideNav, type NavItem } from "@/components/mobile/BottomNav";

/** 代理店マイページ: スマホ下部ナビ/PCサイドバー共通の5項目。 */
export const AGENT_NAV: NavItem[] = [
  { href: "/agent", label: "ホーム", icon: "home", exact: true },
  { href: "/agent/customers", label: "顧客", icon: "user" },
  { href: "/agent/organization", label: "組織", icon: "network" },
  { href: "/agent/content", label: "コンテンツ", icon: "package" },
  { href: "/agent/my", label: "MY", icon: "user-circle" },
];

export const ADMIN_NAV: NavItem[] = [
  { href: "/admin", label: "ダッシュボード", icon: "home", exact: true },
  { href: "/admin/agents", label: "代理店管理", icon: "users" },
  { href: "/admin/customers", label: "購入者管理", icon: "user" },
  { href: "/admin/assignments", label: "担当管理", icon: "arrow-right-left" },
  { href: "/admin/products", label: "商品管理", icon: "package" },
  { href: "/admin/orders", label: "注文管理", icon: "shopping-bag" },
  { href: "/admin/analytics", label: "客層分析", icon: "bar-chart" },
  { href: "/admin/audit-logs", label: "監査ログ", icon: "clipboard-list" },
  { href: "/admin/settings", label: "ショップ設定", icon: "settings" },
];

export function AppShell({
  brand,
  subtitle,
  nav,
  identity,
  wide = false,
  children,
}: {
  brand: string;
  subtitle: string;
  nav: NavItem[];
  identity: string;
  /** 管理画面: テーブル中心のため PC 幅を広く取る */
  wide?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-full flex-1 bg-app-bg">
      <SideNav items={nav} brand={brand} subtitle={subtitle} />

      <div className="flex min-h-full flex-1 flex-col">
        <header className="border-b border-border-soft bg-surface md:border-b-0 md:bg-transparent">
          <div className="mx-auto flex max-w-3xl items-center justify-between gap-3 px-4 py-3 md:max-w-none md:px-8 md:py-6">
            <div className="md:hidden">
              <span className="text-[15px] font-bold tracking-tight text-text-primary">{brand}</span>
            </div>
            <div className="hidden md:block">
              <p className="inline-flex items-center gap-2 rounded-full border border-border-soft bg-surface px-3 py-1.5 text-[12px] font-medium text-text-secondary">
                <span className="h-2 w-2 rounded-full bg-success" aria-hidden />
                {identity}
              </p>
            </div>
            <div className="flex items-center gap-3">
              <span className="max-w-[45vw] truncate text-[12px] text-text-secondary md:hidden">{identity}</span>
              <form action={signOutAction}>
                <button
                  type="submit"
                  className="rounded-full border border-border-soft px-3 py-1.5 text-[12px] font-medium text-text-secondary transition-colors hover:bg-surface-muted"
                >
                  ログアウト
                </button>
              </form>
            </div>
          </div>
        </header>

        <main className={`mx-auto w-full max-w-3xl flex-1 space-y-5 px-4 pb-28 pt-4 ${wide ? "md:max-w-6xl" : "md:max-w-5xl"} md:space-y-6 md:px-8 md:pb-10 md:pt-0`}>
          {children}
        </main>
      </div>

      <BottomNav items={nav} />
    </div>
  );
}
