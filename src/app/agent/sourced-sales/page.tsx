import { Info } from "lucide-react";
import Link from "next/link";

import { EmptyState, MobilePageHeader, StatusPill, Surface } from "@/components/mobile/primitives";
import { BackLink, formatDateTime, formatYen } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { ANALYTICS_PERIODS, type AnalyticsPeriod } from "@/lib/domain/enums";
import type { SourcedProductSales } from "@/lib/domain/types";

const VALID_PERIODS = new Set<string>(ANALYTICS_PERIODS.map((p) => p.value));

/**
 * 持込み商品の売れ行き (本人のみ)。treemerce_my_sourced_product_sales (0019, STABLE) の表示。
 * 件数・数量・金額だけで、購入者・販売した代理店の情報はレスポンス自体に含まれない。
 * 件数が少ない商品や、他の代理店の担当顧客の注文が少ない商品は「該当データ少数」に丸める。
 */
export default async function AgentSourcedSalesPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const { period: periodParam } = await searchParams;
  const period = (VALID_PERIODS.has(periodParam ?? "") ? periodParam : "all") as AnalyticsPeriod;
  const { supabase } = await requireAgentPage("/agent/sourced-sales");

  const { data, error } = await supabase.rpc("treemerce_my_sourced_product_sales", { p_period: period });
  if (error) throw new Error("売れ行きを読み込めませんでした。");
  const sales = data as SourcedProductSales;

  return (
    <>
      <BackLink href="/agent/submissions">持込み申請</BackLink>
      <MobilePageHeader
        title="持込み商品の売れ行き"
        description="あなたが持ち込んだ商品の注文件数・数量・金額です (入金確認済みの注文のみ)。"
      />

      <nav className="flex gap-2" aria-label="期間">
        {ANALYTICS_PERIODS.map((p) => (
          <Link
            key={p.value}
            href={p.value === "all" ? "/agent/sourced-sales" : `/agent/sourced-sales?period=${p.value}`}
            aria-current={p.value === period ? "page" : undefined}
            className={`rounded-2xl border px-4 py-2 text-[14px] font-medium ${
              p.value === period
                ? "border-brand bg-brand-soft text-brand"
                : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
            }`}
          >
            {p.label}
          </Link>
        ))}
      </nav>

      {sales.products.length === 0 ? (
        <EmptyState
          title="まだ持込み商品はありません"
          description="持込み申請が承認されると、ここに売れ行きが表示されます。"
        />
      ) : (
        <>
          <Surface>
            <p className="text-[12px] text-text-secondary">
              合計{sales.suppressed_product_count > 0 ? " (「該当データ少数」の商品を除く)" : ""}
            </p>
            <p className="mt-1 text-[26px] font-bold tabular-nums text-text-primary">
              {formatYen(Number(sales.visible_total.amount))}
            </p>
            <p className="text-[13px] text-text-secondary">
              {sales.visible_total.order_count}件・{sales.visible_total.quantity}個
            </p>
          </Surface>

          <ul className="space-y-3">
            {sales.products.map((p) => (
              <li key={p.product_id}>
                <Surface>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-[16px] font-semibold text-text-primary">{p.product_name}</p>
                      <p className="mt-0.5 font-mono text-[12px] text-text-secondary">{p.submission_no}</p>
                    </div>
                    <StatusPill tone={p.is_published ? "success" : "neutral"}>
                      {p.is_published ? "販売中" : "非公開"}
                    </StatusPill>
                  </div>
                  {p.suppressed ? (
                    <p className="mt-3 text-[14px] font-semibold text-text-secondary">{p.label ?? "該当データ少数"}</p>
                  ) : (
                    <dl className="mt-3 grid grid-cols-3 gap-2">
                      <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
                        <dt className="text-[12px] text-text-secondary">注文</dt>
                        <dd className="text-[16px] font-bold tabular-nums text-text-primary">{p.order_count}件</dd>
                      </div>
                      <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
                        <dt className="text-[12px] text-text-secondary">数量</dt>
                        <dd className="text-[16px] font-bold tabular-nums text-text-primary">{p.quantity}個</dd>
                      </div>
                      <div className="rounded-2xl bg-surface-muted px-3 py-2.5">
                        <dt className="text-[12px] text-text-secondary">金額</dt>
                        <dd className="truncate text-[16px] font-bold tabular-nums text-text-primary">
                          {formatYen(Number(p.amount))}
                        </dd>
                      </div>
                    </dl>
                  )}
                </Surface>
              </li>
            ))}
          </ul>
        </>
      )}

      <div className="flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3.5 py-3">
        <Info size={14} className="mt-0.5 shrink-0 text-text-secondary" />
        <p className="text-[12px] leading-5 text-text-secondary">
          購入者の情報や、どの代理店から売れたかは表示されません。注文が{sales.k_threshold}件未満の商品や、
          ほかの代理店のお客様の注文が{sales.k_threshold}件未満の商品は「該当データ少数」と表示します。
          集計時刻 {formatDateTime(sales.generated_at)}
        </p>
      </div>
    </>
  );
}
