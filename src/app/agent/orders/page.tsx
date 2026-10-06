import { ChevronRight } from "lucide-react";
import Link from "next/link";

import { AgentOrderSummaryCard } from "@/components/AgentOrderSummaryCard";
import { OrderStatusBadge } from "@/components/OrderStatusBadge";
import { formatDate, formatDateTime, formatYen } from "@/components/ui";
import { EmptyState, MobilePageHeader, SectionLabel, Surface } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";
import type { OrderStatus } from "@/lib/domain/enums";
import type { AgentOrderSummary } from "@/lib/domain/types";

type Row = {
  id: string;
  order_no: string;
  customer_id: string;
  status: OrderStatus;
  total: number;
  ordered_at: string;
  payment_due_date: string;
  customer: { full_name: string } | null;
};

/**
 * 担当顧客の注文一覧。
 * RLS (0010) により「自分が現に担当している顧客」の注文だけが返る。
 * 傘下代理店の担当顧客の注文は 1 行も見えない (原則5)。
 * 帰属代理店 (agent_id) は取得も表示もしない。
 */
export default async function AgentOrdersPage() {
  const { supabase } = await requireAgentPage("/agent/orders");

  const [{ data }, { data: summaryData }] = await Promise.all([
    supabase
      .from("orders")
      .select(
        "id, order_no, customer_id, status, total, ordered_at, payment_due_date, customer:customers ( full_name )",
      )
      .order("ordered_at", { ascending: false })
      .limit(200),
    supabase.rpc("treemerce_agent_order_summary", { p_period: "all" }),
  ]);
  const orders = (data ?? []) as unknown as Row[];
  const summary = summaryData as AgentOrderSummary | null;

  return (
    <>
      <MobilePageHeader
        title="担当顧客の注文"
        description="あなたが現在担当しているお客様の注文です。入金確認・発送は運営が行います。"
      />

      {summary ? <AgentOrderSummaryCard summary={summary} /> : null}

      <div className="space-y-2">
        <SectionLabel>注文一覧</SectionLabel>
        {orders.length === 0 ? (
          <EmptyState title="注文はまだありません" description="ショップの紹介リンクは「招待URL」画面から取得できます。" />
        ) : (
          <Surface padded={false} className="divide-y divide-border-soft">
            {orders.map((o) => (
              <Link
                key={o.id}
                href={`/agent/customers/${o.customer_id}`}
                className="flex items-center gap-3 px-4 py-3.5 transition-colors hover:bg-surface-muted"
              >
                <div className="min-w-0 flex-1 space-y-1">
                  <div className="flex items-center gap-2">
                    <p className="truncate text-[15px] font-semibold text-text-primary">
                      {o.customer?.full_name ?? "—"} 様
                    </p>
                    <OrderStatusBadge status={o.status} />
                  </div>
                  <p className="text-[12px] text-text-secondary">
                    <span className="font-mono">{o.order_no}</span> · {formatDateTime(o.ordered_at)}
                    {o.status === "received" ? ` · 支払期限 ${formatDate(o.payment_due_date)}` : ""}
                  </p>
                </div>
                <span className="shrink-0 text-[15px] font-bold tabular-nums text-text-primary">
                  {formatYen(Number(o.total))}
                </span>
                <ChevronRight size={16} className="shrink-0 text-text-secondary" />
              </Link>
            ))}
          </Surface>
        )}
      </div>
    </>
  );
}
