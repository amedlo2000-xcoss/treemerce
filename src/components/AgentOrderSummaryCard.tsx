import { formatYen } from "@/components/ui";
import { Surface } from "@/components/mobile/primitives";
import type { AgentOrderSummary } from "@/lib/domain/types";

type Aggregate = AgentOrderSummary["subtree"];

function AggregateValue({ value }: { value: Aggregate }) {
  if (value.suppressed) {
    return <span className="text-[14px] font-semibold text-text-secondary">{value.label}</span>;
  }
  return (
    <span className="tabular-nums">
      <span className="text-[18px] font-bold text-text-primary">{value.count}件</span>
      <span className="ml-1.5 text-[13px] text-text-secondary">{formatYen(Number(value.total))}</span>
    </span>
  );
}

/**
 * 代理店向け注文サマリ (treemerce_agent_order_summary の表示)。
 * 傘下・担当変更済み分は件数と金額だけで、5 件未満は「該当データ少数」になる。
 * どの代理店・どの顧客の注文かを示す情報はレスポンス自体に含まれない。
 */
export function AgentOrderSummaryCard({ summary }: { summary: AgentOrderSummary }) {
  return (
    <Surface className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        <div className="rounded-2xl bg-surface-muted px-3 py-3">
          <p className="text-[12px] text-text-secondary">担当顧客の売上</p>
          <p className="mt-0.5 text-[20px] font-bold tabular-nums text-text-primary">
            {formatYen(Number(summary.own_current.total))}
          </p>
          <p className="text-[12px] text-text-secondary">{summary.own_current.count}件 (入金確認済み以降)</p>
        </div>
        <div className="rounded-2xl bg-surface-muted px-3 py-3">
          <p className="text-[12px] text-text-secondary">入金待ち</p>
          <p className="mt-0.5 text-[20px] font-bold tabular-nums text-text-primary">
            {summary.own_awaiting_payment}件
          </p>
          <p className="text-[12px] text-text-secondary">担当顧客の未入金注文</p>
        </div>
      </div>

      <dl className="divide-y divide-border-soft">
        <div className="flex items-center justify-between gap-3 py-2.5">
          <dt className="text-[13px] text-text-secondary">傘下代理店の売上 (匿名集計)</dt>
          <dd>
            <AggregateValue value={summary.subtree} />
          </dd>
        </div>
        {summary.own_transferred.suppressed || summary.own_transferred.count > 0 ? (
          <div className="flex items-center justify-between gap-3 py-2.5">
            <dt className="text-[13px] text-text-secondary">担当変更済み顧客の過去売上</dt>
            <dd>
              <AggregateValue value={summary.own_transferred} />
            </dd>
          </div>
        ) : null}
      </dl>

      <p className="text-[11px] leading-4 text-text-secondary">
        傘下の売上は件数と金額のみの集計です。{summary.k_threshold}件未満の場合は「該当データ少数」と表示します。
      </p>
    </Surface>
  );
}
