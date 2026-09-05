import Link from "next/link";

import { RatioBars } from "@/components/charts/RatioBars";
import { EmptyState, Notice, PageHeader, Stat } from "@/components/ui";
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
        管理者は全体を集計できますが、レスポンスに含まれるのは属性値の集計のみです。
        該当件数が {stats?.k_threshold ?? 5} 件未満のセグメントは「該当データ少数」にまとめています。
      </Notice>

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-zinc-500 dark:text-zinc-400">期間</span>
        {ANALYTICS_PERIODS.map((p) => (
          <Link
            key={p.value}
            href={buildHref({ period: p.value })}
            className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${
              period === p.value
                ? "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"
                : "border border-zinc-300 text-zinc-700 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
            }`}
          >
            {p.label}
          </Link>
        ))}

        <span className="ml-4 text-xs text-zinc-500 dark:text-zinc-400">対象</span>
        <Link
          href={buildHref({ root: "" })}
          className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-colors ${
            !root
              ? "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"
              : "border border-zinc-300 text-zinc-700 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
          }`}
        >
          全代理店
        </Link>
        {rootAgent ? (
          <span className="rounded-lg bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">
            {rootAgent.public_id} {rootAgent.display_name} の傘下
          </span>
        ) : null}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Stat label="集計対象の購入者" value={stats?.total_customers ?? 0} />
        <Stat label="集計対象の代理店" value={stats?.scope_agent_count ?? 0} />
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
              buckets={stats[dim.key]}
            />
          ))}
        </div>
      )}

      <section className="space-y-2">
        <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
          代理店を指定して集計
        </h2>
        <div className="flex flex-wrap gap-2">
          {agents.map((a) => (
            <Link
              key={a.id}
              href={buildHref({ root: a.id })}
              className="rounded-lg border border-zinc-300 px-2.5 py-1 text-xs text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
            >
              <span className="font-mono text-zinc-500">{a.public_id}</span> {a.display_name}
            </Link>
          ))}
        </div>
      </section>
    </>
  );
}
