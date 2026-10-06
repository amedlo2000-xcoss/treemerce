import Link from "next/link";

import { RatioBars } from "@/components/charts/RatioBars";
import { Notice } from "@/components/ui";
import { BigStat, EmptyState, MobilePageHeader, Surface } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";
import { ANALYTICS_PERIODS } from "@/lib/domain/enums";
import { DEMOGRAPHIC_DIMENSIONS, type Demographics } from "@/lib/domain/types";

/**
 * STEP6: 客層分析。
 *
 * 集計対象 = 自分 + 傘下代理店全員 (商流マップと同じ再帰CTE)。
 * 傘下の他代理店が担当する顧客は、属性値だけが匿名のまま合算される。
 * レスポンスに代理店別の内訳は含まれないため、個々の顧客がどの代理店の担当かは特定できない。
 */
export default async function AgentAnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const { period: rawPeriod } = await searchParams;
  const period = ANALYTICS_PERIODS.some((p) => p.value === rawPeriod)
    ? (rawPeriod as string)
    : "all";

  const { supabase } = await requireAgentPage("/agent/analytics");

  const { data } = await supabase.rpc("treemerce_customer_demographics", {
    p_root_agent_id: null,
    p_period: period,
  });
  const stats = data as Demographics | null;

  return (
    <>
      <MobilePageHeader
        title="客層分析"
        description="あなたと傘下代理店全員が担当する購入者を、属性値のみで集計しています。"
      />

      <Notice tone="info">
        傘下の他代理店が担当する購入者については、氏名・連絡先・購入明細などの個人情報は使用せず、
        年代・性別・地域・顧客タイプ・購入カテゴリの属性値のみを匿名のまま合算しています。
        該当件数が {stats?.k_threshold ?? 5} 件未満のセグメントは「該当データ少数」にまとめています。
      </Notice>

      {/* 期間フィルターはチャート群の上に1行で置く */}
      <div className="flex flex-wrap items-center gap-2 px-1">
        {ANALYTICS_PERIODS.map((p) => (
          <Link
            key={p.value}
            href={`/agent/analytics?period=${p.value}`}
            className={`inline-flex items-center justify-center rounded-2xl border px-4 py-2.5 text-[14px] font-medium transition-colors ${
              period === p.value
                ? "border-brand bg-brand-soft text-brand"
                : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
            }`}
          >
            {p.label}
          </Link>
        ))}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Surface className="!p-4">
          <BigStat
            label="集計対象の購入者"
            value={stats?.total_customers ?? 0}
            hint="自分 + 傘下代理店の担当合計"
          />
        </Surface>
        <Surface className="!p-4">
          <BigStat
            label="集計対象の代理店"
            value={stats?.scope_agent_count ?? 0}
            hint="自分を含む部分木の代理店数"
          />
        </Surface>
      </div>

      {!stats || stats.total_customers === 0 ? (
        <Surface>
          <EmptyState
            title="集計対象のデータがありません"
            description="担当顧客が登録されると、ここに客層の内訳が表示されます。"
          />
        </Surface>
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
    </>
  );
}
