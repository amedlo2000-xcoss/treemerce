import {
  ArrowRightLeft,
  BarChart3,
  ChevronRight,
  ClipboardList,
  Link2,
  Package,
  Settings,
  ShieldAlert,
  ShoppingBag,
  Truck,
  Wallet,
  User,
  Users,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Link from "next/link";

import { EmptyState, Notice, PageHeader, SectionTitle, Stat, formatDateTime } from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";

const QUICK_LINKS: { href: string; title: string; description: string; icon: LucideIcon }[] = [
  { href: "/admin/agents", title: "代理店管理", description: "招待経路・ステータスの確認", icon: Users },
  { href: "/admin/customers", title: "商品購入者管理", description: "購入者情報の確認・編集", icon: User },
  { href: "/admin/assignments", title: "顧客担当管理", description: "担当代理店の確認・変更", icon: ArrowRightLeft },
  { href: "/admin/orders", title: "注文管理", description: "入金確認・発送・キャンセル", icon: ShoppingBag },
  { href: "/admin/products", title: "商品管理", description: "商品の登録・価格・在庫・公開", icon: Package },
  { href: "/admin/analytics", title: "客層分析", description: "全体・部分木の匿名集計", icon: BarChart3 },
  { href: "/admin/audit-logs", title: "監査ログ", description: "管理者操作の記録", icon: ClipboardList },
  { href: "/admin/settings", title: "ショップ設定", description: "振込先・特商法表記・注文受付", icon: Settings },
];

export default async function AdminDashboard({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const { supabase } = await requireAdminPage("/admin");

  const [agents, customers, assignments, { data: recentLogs }, awaitingPayment, awaitingShipment] = await Promise.all([
    supabase.from("agents").select("id", { count: "exact", head: true }),
    supabase.from("customers").select("id", { count: "exact", head: true }),
    supabase
      .from("customer_assignments")
      .select("id", { count: "exact", head: true })
      .eq("status", "active"),
    supabase
      .from("admin_audit_logs")
      .select("id, action, target_table, reason, created_at, actor_role")
      .order("created_at", { ascending: false })
      .limit(5),
    supabase.from("orders").select("id", { count: "exact", head: true }).eq("status", "received"),
    supabase
      .from("orders")
      .select("id", { count: "exact", head: true })
      .eq("status", "payment_confirmed"),
  ]);

  return (
    <>
      <PageHeader
        title="管理ダッシュボード"
        description="代理店の登録経路と、購入者の担当関係は別々のメニューで管理します。"
      />

      {error === "super_admin_only" ? (
        <Notice tone="danger">
          代理店管理・購入者管理・顧客担当管理は super_admin 専用です。この操作を行うには
          super_admin 権限が必要です。
        </Notice>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-3 md:gap-4">
        <Stat
          label="代理店"
          value={agents.count ?? 0}
          hint="登録経路 = invited_by"
          icon={<Users size={18} />}
        />
        <Stat label="商品購入者" value={customers.count ?? 0} icon={<User size={18} />} />
        <Stat
          label="有効な担当関係"
          value={assignments.count ?? 0}
          hint="1購入者につき1件"
          icon={<Link2 size={18} />}
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 md:gap-4">
        <Link href="/admin/orders?status=received" className="block transition-opacity hover:opacity-90">
          <Stat
            label="入金待ちの注文"
            value={awaitingPayment.count ?? 0}
            hint="支払期限を過ぎると自動キャンセル"
            icon={<Wallet size={18} />}
          />
        </Link>
        <Link href="/admin/orders?status=payment_confirmed" className="block transition-opacity hover:opacity-90">
          <Stat
            label="発送待ちの注文"
            value={awaitingShipment.count ?? 0}
            hint="入金確認済み・未発送"
            icon={<Truck size={18} />}
          />
        </Link>
      </div>

      <div className="flex items-start gap-3 rounded-[20px] border border-warning/25 bg-warning-soft px-4 py-3.5">
        <ShieldAlert size={18} className="mt-0.5 shrink-0 text-warning" />
        <p className="text-[13px] leading-6 text-text-primary">
          担当代理店の変更は管理者のみが実行できます。変更前後・理由・実行者・日時は
          監査ログと担当変更履歴の両方に必ず記録されます。
        </p>
      </div>

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:items-start lg:gap-6 lg:space-y-0">
        <section className="space-y-3">
          <SectionTitle>メニュー</SectionTitle>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
            {QUICK_LINKS.map(({ href, title, description, icon: Icon }) => (
              <Link
                key={href}
                href={href}
                className="group flex items-center gap-3 rounded-[20px] border border-border-soft bg-surface p-4 shadow-[var(--shadow-card)] transition-colors hover:border-brand/40"
              >
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
                  <Icon size={20} />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-[15px] font-semibold text-text-primary">{title}</span>
                  <span className="block truncate text-[12px] text-text-secondary">{description}</span>
                </span>
                <ChevronRight
                  size={18}
                  className="text-text-secondary transition-transform group-hover:translate-x-0.5"
                />
              </Link>
            ))}
          </div>
        </section>

        <section className="space-y-3">
          <SectionTitle>最近の監査ログ</SectionTitle>
          {recentLogs && recentLogs.length > 0 ? (
            <ul className="divide-y divide-border-soft rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)]">
              {recentLogs.map((log) => (
                <li key={log.id} className="flex items-start gap-3 px-4 py-3.5">
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-brand" aria-hidden />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[14px] font-medium text-text-primary">
                      {log.reason ?? "—"}
                    </p>
                    <p className="mt-0.5 flex flex-wrap gap-x-2 text-[12px] text-text-secondary">
                      <span className="font-mono">{log.action}</span>
                      <span>{formatDateTime(log.created_at)}</span>
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          ) : (
            <EmptyState title="記録はまだありません" />
          )}
        </section>
      </div>
    </>
  );
}
