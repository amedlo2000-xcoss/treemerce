import Link from "next/link";

import { RatioBars } from "@/components/charts/RatioBars";
import { EmptyState, Notice, PageHeader, Stat, formatYen } from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";
import { ANALYTICS_PERIODS } from "@/lib/domain/enums";
import { DEMOGRAPHIC_DIMENSIONS, type Demographics } from "@/lib/domain/types";

/** STEP6: ADMIN は全代理店横断の集計と、任意の代理店を根とした部分木の集計を閲覧できる。 */
export default async function AdminAnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string; root?: string }>;
}) {
  const { period: rawPeriod, root } = await searchParams;
  const period = ANALYTICS_PERIODS.some((p) => p.value === rawPeriod)
    ? (rawPeriod as string)
    : "all";

  const { supabase } = await requireAdminPage("/admin/analytics");

  const [{ data }, { data: agentData }] = await Promise.all([
    supabase.rpc("treemerce_customer_demographics", {
      p_root_agent_id: root || null,
      p_period: period,
    }),
    supabase
      .from("agents")
      .select("id, public_id, display_name")
      .eq("status", "active")
      .order("public_id"),
  ]);

  const stats = data as Demographics | null;
  const agents = (agentData ?? []) as { id: string; public_id: string; display_name: string }[];
  const rootAgent = root ? agents.find((a) => a.id === root) : null;

  const buildHref = (next: { period?: string; root?: string }) => {
    const params = new URLSearchParams();
    params.set("period", next.period ?? period);
    const nextRoot = next.root !== undefined ? next.root : (root ?? "");
    if (nextRoot) params.set("root", nextRoot);
    return `/admin/analytics?${params.toString()}`;
  };

  return (
    <>
      <PageHeader
        title="客層分析"
        description="全代理店横断の集計と、特定の代理店を根とする部分木の集計を確認できます。"
      />

      <Notice tone="info">
        管理者は全体を集計できますが、レスポンスに含まれるのは属性値の集計のみです。 該当件数が{" "}
        {stats?.k_threshold ?? 5} 件未満のセグメントは「該当データ少数」にまとめています。
      </Notice>

      <div className="flex flex-wrap items-center gap-2 rounded-[20px] border border-border-soft bg-surface p-4 shadow-[var(--shadow-card)]">
        <span className="mr-1 text-[12px] font-semibold text-text-secondary">期間</span>
        {ANALYTICS_PERIODS.map((p) => (
          <Link
            key={p.value}
            href={buildHref({ period: p.value })}
            className={`rounded-full px-3.5 py-2 text-[13px] font-medium transition-colors ${
              period === p.value
                ? "bg-brand text-brand-foreground"
                : "border border-border-soft bg-surface text-text-secondary hover:bg-surface-muted hover:text-text-primary"
            }`}
          >
            {p.label}
          </Link>
        ))}

        <span className="mr-1 text-[12px] font-semibold text-text-secondary sm:ml-4">対象</span>
        <Link
          href={buildHref({ root: "" })}
          className={`rounded-full px-3.5 py-2 text-[13px] font-medium transition-colors ${
            !root
              ? "bg-brand text-brand-foreground"
              : "border border-border-soft bg-surface text-text-secondary hover:bg-surface-muted hover:text-text-primary"
          }`}
        >
          全代理店
        </Link>
        {rootAgent ? (
          <span className="rounded-full bg-brand px-3 py-1.5 text-[12px] font-medium text-brand-foreground">
            {rootAgent.public_id} {rootAgent.display_name} の傘下
          </span>
        ) : null}
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="集計対象の購入者" value={stats?.total_customers ?? 0} />
        <Stat label="集計対象の代理店" value={stats?.scope_agent_count ?? 0} />
        <Stat label="購入した人" value={stats?.purchasing_customers ?? 0} hint="入金確認済み以降" />
        <Stat
          label="売上合計"
          value={stats?.total_sales == null ? "該当データ少数" : formatYen(Number(stats.total_sales))}
          hint="購入者が少ない場合は非表示"
        />
      </div>

      {!stats || stats.total_customers === 0 ? (
        <EmptyState title="集計対象のデータがありません" />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {DEMOGRAPHIC_DIMENSIONS.map((dim) => (
            <RatioBars
              key={dim.key}
              title={dim.title}
              dimension={dim.key}
              buckets={stats[dim.key] ?? []}
            />
          ))}
        </div>
      )}

      <section className="space-y-3">
        <h2 className="px-1 text-[15px] font-semibold text-text-primary">代理店を指定して集計</h2>
        <div className="flex flex-wrap gap-2">
          {agents.map((a) => (
            <Link
              key={a.id}
              href={buildHref({ root: a.id })}
              className="rounded-full border border-border-soft bg-surface px-3 py-1.5 text-[12px] text-text-primary transition-colors hover:border-brand/40 hover:bg-brand-soft"
            >
              <span className="font-mono text-text-secondary">{a.public_id}</span> {a.display_name}
            </Link>
          ))}
        </div>
      </section>
    </>
  );
}
