"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ArrowRightLeft,
  BarChart3,
  ClipboardList,
  Home,
  Network,
  Package,
  Settings,
  ShoppingBag,
  User,
  UserCircle,
  Users,
} from "lucide-react";

/**
 * ナビ項目はサーバーコンポーネント (layout.tsx) からこのクライアントコンポーネントへ
 * props で渡るため、アイコンは関数コンポーネントではなくキー文字列として保持する
 * (関数を Server → Client Component の props に渡すことはできない)。
 */
const ICONS = {
  home: Home,
  user: User,
  users: Users,
  network: Network,
  package: Package,
  "user-circle": UserCircle,
  "arrow-right-left": ArrowRightLeft,
  "bar-chart": BarChart3,
  "clipboard-list": ClipboardList,
  "shopping-bag": ShoppingBag,
  settings: Settings,
} as const;

export type IconKey = keyof typeof ICONS;

export type NavItem = {
  href: string;
  label: string;
  icon: IconKey;
  /** true: 完全一致のみアクティブ扱い (例: ホーム) */
  exact?: boolean;
};

function isActive(pathname: string, item: NavItem) {
  if (item.exact) return pathname === item.href;
  return pathname === item.href || pathname.startsWith(`${item.href}/`);
}

/**
 * スマホ幅 (md未満) でのみ表示する下部固定ナビ。現在地のみブランドカラー。
 * 5 項目までは等幅、それを超える場合 (管理画面) は横スクロールにする。
 */
export function BottomNav({ items }: { items: NavItem[] }) {
  const pathname = usePathname();
  const scrollable = items.length > 5;

  return (
    <nav className="pb-safe fixed inset-x-0 bottom-0 z-40 border-t border-border-soft bg-surface/95 backdrop-blur md:hidden">
      <ul
        className={
          scrollable
            ? "flex items-stretch overflow-x-auto [scrollbar-width:none]"
            : "mx-auto flex max-w-md items-stretch justify-between"
        }
      >
        {items.map((item) => {
          const active = isActive(pathname, item);
          const Icon = ICONS[item.icon];
          return (
            <li key={item.href} className={scrollable ? "w-[4.5rem] shrink-0" : "flex-1"}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className="flex flex-col items-center gap-1 py-2.5 text-[11px] font-medium"
              >
                <Icon
                  size={22}
                  strokeWidth={active ? 2.3 : 1.75}
                  className={active ? "text-brand" : "text-text-secondary"}
                />
                <span className={active ? "text-brand" : "text-text-secondary"}>{item.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/** PC幅 (md以上) での左サイドバー。基本構造はモバイルのナビと同一項目。 */
export function SideNav({
  items,
  brand,
  subtitle,
}: {
  items: NavItem[];
  brand: string;
  subtitle: string;
}) {
  const pathname = usePathname();

  return (
    <aside className="hidden md:sticky md:top-0 md:flex md:h-dvh md:w-60 md:shrink-0 md:flex-col md:overflow-y-auto md:border-r md:border-border-soft md:bg-surface md:px-4 md:py-6">
      <div className="px-2 pb-8">
        <p className="text-[17px] font-bold tracking-tight text-text-primary">{brand}</p>
        <p className="text-[13px] text-text-secondary">{subtitle}</p>
      </div>
      <ul className="space-y-1">
        {items.map((item) => {
          const active = isActive(pathname, item);
          const Icon = ICONS[item.icon];
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`flex items-center gap-3 rounded-2xl px-3 py-2.5 text-[14px] font-medium transition-colors ${
                  active
                    ? "bg-brand-soft text-brand"
                    : "text-text-secondary hover:bg-surface-muted hover:text-text-primary"
                }`}
              >
                <Icon size={19} strokeWidth={active ? 2.3 : 1.8} />
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </aside>
  );
}
