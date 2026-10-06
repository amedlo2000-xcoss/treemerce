import { AlertTriangle } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { OrderStatusBadge } from "@/components/OrderStatusBadge";
import {
  BackLink,
  Card,
  DataTable,
  DetailList,
  DetailRow,
  EmptyState,
  Mono,
  PageHeader,
  TD,
  TD_STRONG,
  formatDate,
  formatDateTime,
  formatYen,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { ORDER_STATUS_LABELS, PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import type { AdminOrderDetail } from "@/lib/domain/types";

import { OrderStatusForm } from "./OrderStatusForm";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function AgentLink({ agent }: { agent: AdminOrderDetail["agent"] }) {
  if (!agent) return <span className="text-text-secondary">—</span>;
  return (
    <Link href={`/admin/agents/${agent.id}`} className="font-medium text-brand hover:underline">
      <span className="font-mono text-[12px]">{agent.public_id}</span> {agent.display_name}
    </Link>
  );
}

/**
 * 注文詳細 (super_admin 専用)。紹介元 (referral_agent_id) と本人確認フラグは
 * treemerce_admin_get_order でのみ取得でき、一般代理店には一切返らない。
 */
export default async function AdminOrderDetailPage({
  params,
}: {
  params: Promise<{ orderId: string }>;
}) {
  const { orderId } = await params;
  if (!UUID.test(orderId)) notFound();
  const { supabase } = await requireSuperAdminPage(`/admin/orders/${orderId}`);

  const { data } = await supabase.rpc("treemerce_admin_get_order", { p_order_id: orderId });
  const detail = data as AdminOrderDetail | null;
  if (!detail) notFound();

  const { order } = detail;
  const transferred = detail.current_agent && detail.current_agent.id !== order.agent_id;
  const viaOtherLink = order.referral_agent_id && order.referral_agent_id !== order.agent_id;

  return (
    <>
      <BackLink href="/admin/orders">注文一覧</BackLink>
      <PageHeader
        title={`注文 ${order.order_no}`}
        description={`${formatDateTime(order.ordered_at)} 受付`}
        action={<OrderStatusBadge status={order.status} />}
      />

      {order.identity_mismatch ? (
        <div className="flex items-start gap-3 rounded-[20px] border border-warning/30 bg-warning-soft px-4 py-3.5">
          <AlertTriangle size={18} className="mt-0.5 shrink-0 text-warning" />
          <p className="text-[13px] leading-6 text-text-primary">
            本人確認の注意: 既存の購入者とメールアドレスまたは電話番号が一致しましたが、入力された氏名が登録内容と異なります。
            入金確認・発送の前にご本人であることを確認してください。顧客情報は注文によって上書きされていません。
          </p>
        </div>
      ) : null}

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-6 lg:space-y-0">
        <div className="space-y-5">
          <Card title="金額">
            <DetailList>
              <DetailRow label="小計" value={formatYen(Number(order.subtotal))} />
              <DetailRow label="送料" value={formatYen(Number(order.shipping_fee))} />
              <DetailRow label="合計" value={<span className="text-[16px]">{formatYen(Number(order.total))}</span>} />
              <DetailRow label="支払期限" value={formatDate(order.payment_due_date)} />
              <DetailRow label="入金確認" value={formatDateTime(order.paid_at)} />
              <DetailRow label="発送" value={formatDateTime(order.shipped_at)} />
              <DetailRow label="完了" value={formatDateTime(order.completed_at)} />
              <DetailRow label="キャンセル" value={formatDateTime(order.cancelled_at)} />
            </DetailList>
          </Card>

          <Card title="注文者・お届け先">
            <DetailList>
              <DetailRow
                label="購入者"
                value={
                  detail.customer ? (
                    <Link href={`/admin/customers/${detail.customer.id}`} className="font-medium text-brand hover:underline">
                      {detail.customer.full_name}
                    </Link>
                  ) : (
                    "—"
                  )
                }
              />
              <DetailRow label="お届け先氏名" value={order.ship_name} />
              <DetailRow label="郵便番号" value={order.ship_postal_code ?? "—"} />
              <DetailRow label="住所" value={order.ship_address} />
              <DetailRow label="メール" value={order.contact_email ?? "—"} />
              <DetailRow label="電話" value={order.contact_phone ?? "—"} />
              <DetailRow label="備考" value={order.customer_note ?? "—"} />
            </DetailList>
          </Card>

          <Card
            title="代理店"
            description="帰属代理店は注文時点の担当で確定し、担当変更があっても変わりません。"
          >
            <DetailList>
              <DetailRow label="帰属代理店" value={<AgentLink agent={detail.agent} />} />
              <DetailRow label="現在の担当" value={<AgentLink agent={detail.current_agent} />} />
              <DetailRow label="経由した紹介リンク" value={<AgentLink agent={detail.referral_agent} />} />
            </DetailList>
            {transferred || viaOtherLink ? (
              <ul className="mt-3 space-y-1 text-[12px] leading-5 text-text-secondary">
                {transferred ? <li>・注文後に担当変更があったため、帰属代理店と現在の担当が異なります。</li> : null}
                {viaOtherLink ? <li>・担当代理店以外の紹介リンクから注文されました (紹介元は管理者のみ閲覧できます)。</li> : null}
              </ul>
            ) : null}
          </Card>
        </div>

        <div className="space-y-5">
          <Card title="ステータスを変更する" description="この操作は super_admin のみ実行できます。">
            <OrderStatusForm orderId={order.id} current={order.status} />
          </Card>

          <Card title="注文明細">
            <DataTable headers={["商品名", "カテゴリ", "単価", "数量", "金額"]}>
              {detail.items.map((item) => (
                <tr key={item.id}>
                  <td className={TD_STRONG}>
                    {item.product_name}
                    {item.product_sku ? (
                      <div>
                        <Mono>{item.product_sku}</Mono>
                      </div>
                    ) : null}
                  </td>
                  <td className={TD}>{PRODUCT_CATEGORY_LABELS[item.product_category] ?? item.product_category}</td>
                  <td className={`${TD} tabular-nums`}>{formatYen(Number(item.unit_price))}</td>
                  <td className={`${TD} tabular-nums`}>{item.quantity}</td>
                  <td className={`${TD} font-semibold tabular-nums text-text-primary`}>
                    {formatYen(Number(item.amount))}
                  </td>
                </tr>
              ))}
            </DataTable>
          </Card>

          <Card title="ステータス履歴">
            {detail.history.length === 0 ? (
              <EmptyState title="履歴はありません" />
            ) : (
              <ol className="space-y-3">
                {detail.history.map((h) => (
                  <li key={h.id} className="flex gap-3">
                    <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-brand" aria-hidden />
                    <div className="min-w-0">
                      <p className="text-[14px] font-medium text-text-primary">
                        {h.from_status ? `${ORDER_STATUS_LABELS[h.from_status]} → ` : ""}
                        {ORDER_STATUS_LABELS[h.to_status]}
                      </p>
                      <p className="text-[13px] text-text-primary">{h.reason}</p>
                      <p className="text-[12px] text-text-secondary">
                        {formatDateTime(h.changed_at)} · <span className="font-mono">{h.changed_by_role}</span>
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
