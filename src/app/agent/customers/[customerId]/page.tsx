import { ChevronLeft, Lock, Mail, MessageSquare, Phone, ShoppingBag } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { formatDate, formatDateTime, formatYen } from "@/components/ui";
import {
  EmptyState,
  IconAction,
  InfoRow,
  ProfileHero,
  SectionLabel,
  StatTile,
  StatusPill,
  Surface,
} from "@/components/mobile/primitives";
import { OrderStatusBadge } from "@/components/OrderStatusBadge";
import { requireAgentPage } from "@/lib/auth/viewer";
import {
  AGE_GROUP_LABELS,
  ASSIGNMENT_SOURCE_LABELS,
  CUSTOMER_TYPE_LABELS,
  GENDER_LABELS,
  PRODUCT_CATEGORY_LABELS,
  PURCHASE_STATUS_LABELS,
} from "@/lib/domain/enums";
import type { CustomerRow, PurchaseRow } from "@/lib/domain/types";

const PURCHASE_STATUS_TONE: Record<string, "success" | "warning" | "danger" | "neutral"> = {
  completed: "success",
  pending: "warning",
  cancelled: "neutral",
  refunded: "danger",
};

/**
 * CASE5 / CASE6:
 * RLS により、担当していない購入者は 0 行になり notFound() になる。
 * 「存在するが権限がない」ことも伝えないため 403 ではなく 404 とする。
 *
 * STEP3: 顧客プロフィール。ヒーロー→基本情報→担当情報 (固定・編集UIなし)→購入情報→問い合わせ の順。
 * PC (lg 以上) では左にプロフィール列を固定し、右に購入情報を並べる。
 */
export default async function AgentCustomerDetailPage({
  params,
}: {
  params: Promise<{ customerId: string }>;
}) {
  const { customerId } = await params;
  const { supabase, agent } = await requireAgentPage(`/agent/customers/${customerId}`);

  const { data: assignment } = await supabase
    .from("customer_assignments")
    .select("id, assigned_agent_id, assigned_at, assignment_source")
    .eq("customer_id", customerId)
    .eq("status", "active")
    .maybeSingle();

  // ページ層でももう一度「自分が担当か」を確認する (多層防御)
  if (!assignment || assignment.assigned_agent_id !== agent.id) notFound();

  const [{ data: customerData }, { data: purchaseData }, { data: orderData }] = await Promise.all([
    supabase.from("customers").select("*").eq("id", customerId).maybeSingle(),
    supabase
      .from("purchases")
      .select("*")
      .eq("customer_id", customerId)
      .order("purchased_at", { ascending: false }),
    // RLS: 現に担当している顧客の注文のみ。帰属代理店 (agent_id) は取得しない。
    supabase
      .from("orders")
      .select(
        "id, order_no, status, total, ordered_at, payment_due_date, order_items ( id, product_name, quantity, amount )",
      )
      .eq("customer_id", customerId)
      .order("ordered_at", { ascending: false }),
  ]);
  const orders = (orderData ?? []) as {
    id: string;
    order_no: string;
    status: string;
    total: number;
    ordered_at: string;
    payment_due_date: string;
    order_items: { id: string; product_name: string; quantity: number; amount: number }[];
  }[];

  const customer = customerData as CustomerRow | null;
  if (!customer) notFound();

  const purchases = (purchaseData ?? []) as PurchaseRow[];
  const validPurchases = purchases.filter(
    (p) => p.status !== "cancelled" && p.status !== "refunded",
  );
  // 注文は入金確認済み以降のみを購入実績として数える (未入金・キャンセルは含めない)
  const paidOrders = orders.filter((o) =>
    ["payment_confirmed", "shipped", "completed"].includes(o.status),
  );
  const total =
    validPurchases.reduce((sum, p) => sum + Number(p.amount ?? 0), 0) +
    paidOrders.reduce((sum, o) => sum + Number(o.total ?? 0), 0);
  const purchaseCount = validPurchases.length + paidOrders.length;
  const lastPurchaseAt =
    [...validPurchases.map((p) => p.purchased_at), ...paidOrders.map((o) => o.ordered_at)].sort().at(-1) ??
    null;

  return (
    <>
      <Link
        href="/agent/customers"
        className="inline-flex items-center gap-1 px-1 text-[14px] font-medium text-text-secondary transition-colors hover:text-text-primary"
      >
        <ChevronLeft size={18} />
        顧客一覧
      </Link>

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-6 lg:space-y-0">
        {/* 左列: プロフィール (PC では追従) */}
        <div className="space-y-5 lg:sticky lg:top-6">
          <ProfileHero
            name={customer.full_name}
            subtitle={customer.full_name_kana}
            pills={
              <>
                <StatusPill tone="brand">
                  {CUSTOMER_TYPE_LABELS[customer.customer_type] ?? customer.customer_type}
                </StatusPill>
                {customer.age_group ? (
                  <StatusPill>{AGE_GROUP_LABELS[customer.age_group] ?? customer.age_group}</StatusPill>
                ) : null}
                {customer.prefecture ? <StatusPill>{customer.prefecture}</StatusPill> : null}
              </>
            }
            actions={
              <>
                {customer.phone ? (
                  <IconAction href={`tel:${customer.phone}`} label="電話する">
                    <Phone size={18} />
                  </IconAction>
                ) : null}
                {customer.email ? (
                  <IconAction href={`mailto:${customer.email}`} label="メールする">
                    <Mail size={18} />
                  </IconAction>
                ) : null}
              </>
            }
            meta={
              <div className="grid grid-cols-3 gap-2">
                <StatTile label="購入合計" value={formatYen(total)} />
                <StatTile label="購入件数" value={`${purchaseCount}件`} />
                <StatTile label="最終購入" value={lastPurchaseAt ? formatDate(lastPurchaseAt) : "—"} />
              </div>
            }
          />

          <div className="space-y-2">
            <SectionLabel>基本情報</SectionLabel>
            <Surface className="!py-1">
              <dl className="divide-y divide-border-soft">
                <InfoRow label="メール" value={customer.email ?? "—"} />
                <InfoRow label="電話番号" value={customer.phone ?? "—"} />
                <InfoRow
                  label="年代"
                  value={customer.age_group ? (AGE_GROUP_LABELS[customer.age_group] ?? "—") : "未回答"}
                />
                <InfoRow
                  label="性別"
                  value={customer.gender ? (GENDER_LABELS[customer.gender] ?? "—") : "未回答"}
                />
                <InfoRow label="都道府県" value={customer.prefecture ?? "—"} />
              </dl>
            </Surface>
          </div>

          <div className="space-y-2">
            <SectionLabel>担当情報</SectionLabel>
            <Surface>
              <div className="mb-2 flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3 py-2.5">
                <Lock size={16} className="mt-0.5 shrink-0 text-text-secondary" />
                <p className="text-[12px] leading-5 text-text-secondary">
                  担当代理店は初回登録時に確定し、以後変更されません。
                </p>
              </div>
              <dl className="divide-y divide-border-soft">
                <InfoRow
                  label="担当代理店"
                  value={
                    <span className="inline-flex items-center gap-1.5">
                      {agent.display_name}
                      <StatusPill tone="brand">自分</StatusPill>
                    </span>
                  }
                />
                <InfoRow label="代理店ID" value={agent.public_id} mono />
                <InfoRow label="担当開始日" value={formatDate(assignment.assigned_at)} />
                <InfoRow
                  label="確定経路"
                  value={
                    ASSIGNMENT_SOURCE_LABELS[assignment.assignment_source] ??
                    assignment.assignment_source
                  }
                />
              </dl>
            </Surface>
          </div>
        </div>

        {/* 右列: 注文・購入情報・問い合わせ */}
        <div className="space-y-5">
          <div className="space-y-2">
            <SectionLabel>ショップでの注文</SectionLabel>
            {orders.length === 0 ? (
              <EmptyState title="注文はありません" />
            ) : (
              <Surface padded={false} className="divide-y divide-border-soft">
                {orders.map((o) => (
                  <div key={o.id} className="space-y-2 px-4 py-3.5">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0 space-y-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-mono text-[12px] font-semibold text-text-primary">
                            {o.order_no}
                          </span>
                          <OrderStatusBadge status={o.status} />
                        </div>
                        <p className="text-[12px] text-text-secondary">
                          {formatDateTime(o.ordered_at)}
                          {o.status === "received" ? ` · 支払期限 ${formatDate(o.payment_due_date)}` : ""}
                        </p>
                      </div>
                      <p className="shrink-0 text-[15px] font-bold tabular-nums text-text-primary">
                        {formatYen(Number(o.total))}
                      </p>
                    </div>
                    <ul className="space-y-0.5">
                      {o.order_items.map((item) => (
                        <li key={item.id} className="flex justify-between gap-3 text-[13px] text-text-secondary">
                          <span className="truncate">
                            {item.product_name} × {item.quantity}
                          </span>
                          <span className="shrink-0 tabular-nums">{formatYen(Number(item.amount))}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
              </Surface>
            )}
          </div>

          <div className="space-y-2">
            <SectionLabel>その他の購入履歴</SectionLabel>
            {purchases.length === 0 ? (
              <EmptyState title="購入履歴はありません" />
            ) : (
              <Surface padded={false} className="divide-y divide-border-soft">
                {purchases.map((p) => (
                  <div key={p.id} className="flex items-start gap-3 px-4 py-3.5">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
                      <ShoppingBag size={18} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start justify-between gap-3">
                        <p className="truncate text-[15px] font-semibold text-text-primary">
                          {p.product_name}
                        </p>
                        <p className="shrink-0 text-[15px] font-bold tabular-nums text-text-primary">
                          {formatYen(Number(p.amount))}
                        </p>
                      </div>
                      <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-[12px] text-text-secondary">
                        <span>
                          {PRODUCT_CATEGORY_LABELS[p.product_category] ?? p.product_category}
                        </span>
                        <span aria-hidden>·</span>
                        <span>{formatDateTime(p.purchased_at)}</span>
                        <span aria-hidden>·</span>
                        <span>数量 {p.quantity}</span>
                        <StatusPill tone={PURCHASE_STATUS_TONE[p.status] ?? "neutral"}>
                          {PURCHASE_STATUS_LABELS[p.status] ?? p.status}
                        </StatusPill>
                      </div>
                    </div>
                  </div>
                ))}
              </Surface>
            )}
          </div>

          <div className="space-y-2">
            <SectionLabel>問い合わせ履歴</SectionLabel>
            <Surface className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-surface-muted text-text-secondary">
                <MessageSquare size={18} />
              </div>
              <div>
                <p className="text-[14px] font-semibold text-text-primary">準備中の機能です</p>
                <p className="text-[12px] text-text-secondary">今後のアップデートで対応予定です。</p>
              </div>
            </Surface>
          </div>
        </div>
      </div>
    </>
  );
}
