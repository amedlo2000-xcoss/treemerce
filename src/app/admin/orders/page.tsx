import { ChevronRight, Search } from "lucide-react";
import Link from "next/link";

import { OrderStatusBadge } from "@/components/OrderStatusBadge";
import {
  BUTTON_CLASS,
  DataTable,
  EmptyState,
  FIELD_CLASS,
  FilterPanel,
  Mono,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDate,
  formatDateTime,
  formatYen,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import {
  ORDER_STATUSES,
  ORDER_STATUS_LABELS,
  type OrderStatus,
  type ShipmentStatus,
} from "@/lib/domain/enums";

type Row = {
  id: string;
  order_no: string;
  status: OrderStatus;
  total: number;
  ordered_at: string;
  payment_due_date: string;
  ship_name: string;
  contact_email: string | null;
  contact_phone: string | null;
  customer: { id: string; full_name: string } | null;
  agent: { id: string; public_id: string; display_name: string } | null;
  shipments: { status: ShipmentStatus }[];
};

/** 入金確認済みの注文の生産者ごとの発送の進み具合 (例: 発送 1/2)。旧注文・対象外は null。 */
function shipmentProgress(o: Row) {
  if (o.status !== "payment_confirmed" || !o.shipments?.length) return null;
  const active = o.shipments.filter((s) => s.status !== "cancelled");
  const shipped = active.filter((s) => s.status === "shipped").length;
  return `発送 ${shipped}/${active.length}`;
}

/**
 * 注文管理 (super_admin 専用)。全注文を横断して確認する。
 * 帰属代理店名の表示は ADMIN 画面のみ (一般代理店の画面では帰属代理店を表示しない)。
 */
export default async function AdminOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; q?: string }>;
}) {
  const { status: rawStatus, q } = await searchParams;
  const status = (ORDER_STATUSES as readonly string[]).includes(rawStatus ?? "")
    ? (rawStatus as OrderStatus)
    : null;
  const { supabase } = await requireSuperAdminPage("/admin/orders");

  let query = supabase
    .from("orders")
    .select(
      `id, order_no, status, total, ordered_at, payment_due_date, ship_name, contact_email, contact_phone,
       customer:customers ( id, full_name ),
       agent:agents!orders_agent_id_fkey ( id, public_id, display_name ),
       shipments:order_shipments ( status )`,
    )
    .order("ordered_at", { ascending: false })
    .limit(200);

  if (status) query = query.eq("status", status);
  const term = q?.trim();
  if (term) {
    const safe = term.replace(/[,()%]/g, "");
    query = query.or(
      `order_no.ilike.%${safe}%,ship_name.ilike.%${safe}%,contact_email.ilike.%${safe}%,contact_phone.ilike.%${safe}%`,
    );
  }

  const [{ data }, ...counts] = await Promise.all([
    query,
    ...ORDER_STATUSES.map((s) =>
      supabase.from("orders").select("id", { count: "exact", head: true }).eq("status", s),
    ),
  ]);
  const orders = (data ?? []) as unknown as Row[];
  const countByStatus = Object.fromEntries(ORDER_STATUSES.map((s, i) => [s, counts[i].count ?? 0]));

  const tabHref = (s: OrderStatus | null) => {
    const params = new URLSearchParams();
    if (s) params.set("status", s);
    if (term) params.set("q", term);
    const qs = params.toString();
    return qs ? `/admin/orders?${qs}` : "/admin/orders";
  };

  return (
    <>
      <PageHeader
        title="注文管理"
        description="入金確認・発送・完了・キャンセルを管理します。ステータス変更は理由とともに履歴と監査ログに記録されます。"
      />

      <div className="flex flex-wrap gap-2">
        {[null, ...ORDER_STATUSES].map((s) => {
          const active = status === s;
          return (
            <Link
              key={s ?? "all"}
              href={tabHref(s)}
              className={`inline-flex items-center gap-1.5 rounded-full px-3.5 py-2 text-[13px] font-medium transition-colors ${
                active
                  ? "bg-brand text-brand-foreground"
                  : "border border-border-soft bg-surface text-text-secondary hover:text-text-primary"
              }`}
            >
              {s ? ORDER_STATUS_LABELS[s] : "すべて"}
              {s ? (
                <span className={`tabular-nums ${active ? "opacity-80" : "text-text-secondary"}`}>
                  {countByStatus[s]}
                </span>
              ) : null}
            </Link>
          );
        })}
      </div>

      <FilterPanel>
        <form method="get" className="flex flex-col gap-3 sm:flex-row sm:items-end">
          {status ? <input type="hidden" name="status" value={status} /> : null}
          <label className="block flex-1">
            <span className="mb-1.5 block text-[12px] font-semibold text-text-secondary">
              検索 (注文番号・お届け先氏名・メール・電話)
            </span>
            <input name="q" defaultValue={q ?? ""} className={FIELD_CLASS} placeholder="例: TM-20261006" />
          </label>
          <button type="submit" className={BUTTON_CLASS}>
            <Search size={16} />
            検索
          </button>
        </form>
      </FilterPanel>

      <SectionTitle count={orders.length}>注文一覧</SectionTitle>

      {orders.length === 0 ? (
        <EmptyState title="該当する注文はありません" />
      ) : (
        <DataTable headers={["注文番号", "注文者", "帰属代理店", "合計", "状態", "支払期限", "注文日時", ""]}>
          {orders.map((o) => (
            <tr key={o.id}>
              <td className={TD}>
                <Link href={`/admin/orders/${o.id}`} className="font-mono text-[12px] font-semibold text-brand hover:underline">
                  {o.order_no}
                </Link>
              </td>
              <td className={TD_STRONG}>
                {o.customer?.full_name ?? o.ship_name}
                <div className="text-[12px] font-normal text-text-secondary">
                  {o.contact_email ?? o.contact_phone ?? "—"}
                </div>
              </td>
              <td className={TD}>
                {o.agent ? (
                  <>
                    <Mono>{o.agent.public_id}</Mono>{" "}
                    <span className="text-text-primary">{o.agent.display_name}</span>
                  </>
                ) : (
                  "—"
                )}
              </td>
              <td className={`${TD} font-semibold tabular-nums text-text-primary`}>
                {formatYen(Number(o.total))}
              </td>
              <td className={TD}>
                <OrderStatusBadge status={o.status} />
                {shipmentProgress(o) ? (
                  <div className="mt-1 whitespace-nowrap text-[12px] tabular-nums">{shipmentProgress(o)}</div>
                ) : null}
              </td>
              <td className={`${TD} whitespace-nowrap`}>
                {o.status === "received" ? formatDate(o.payment_due_date) : "—"}
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(o.ordered_at)}</td>
              <td className={`${TD} text-right`}>
                <Link
                  href={`/admin/orders/${o.id}`}
                  className="inline-flex items-center gap-0.5 whitespace-nowrap text-[13px] font-semibold text-brand hover:underline"
                >
                  詳細
                  <ChevronRight size={14} />
                </Link>
              </td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
