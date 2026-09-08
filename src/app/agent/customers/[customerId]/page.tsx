import { Lock, User } from "lucide-react";
import { notFound } from "next/navigation";

import { LinkButton, formatDate, formatDateTime, formatYen } from "@/components/ui";
import { EmptyState, StatusPill, Surface } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";
import {
  AGE_GROUP_LABELS,
  ASSIGNMENT_SOURCE_LABELS,
  CUSTOMER_TYPE_LABELS,
  GENDER_LABELS,
  PRODUCT_CATEGORY_LABELS,
} from "@/lib/domain/enums";
import type { CustomerRow, PurchaseRow } from "@/lib/domain/types";

/**
 * CASE5 / CASE6:
 * RLS により、担当していない購入者は 0 行になり notFound() になる。
 * 「存在するが権限がない」ことも伝えないため 403 ではなく 404 とする。
 *
 * STEP3: 顧客プロフィール。基本情報→担当情報 (固定・編集UIなし)→購入情報→問い合わせ の順。
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

  const [{ data: customerData }, { data: purchaseData }] = await Promise.all([
    supabase.from("customers").select("*").eq("id", customerId).maybeSingle(),
    supabase
      .from("purchases")
      .select("*")
      .eq("customer_id", customerId)
      .order("purchased_at", { ascending: false }),
  ]);

  const customer = customerData as CustomerRow | null;
  if (!customer) notFound();

  const purchases = (purchaseData ?? []) as PurchaseRow[];
  const validPurchases = purchases.filter(
    (p) => p.status !== "cancelled" && p.status !== "refunded",
  );
  const total = validPurchases.reduce((sum, p) => sum + Number(p.amount ?? 0), 0);
  const lastPurchase = purchases[0] ?? null;

  return (
    <>
      <div className="flex justify-end px-1">
        <LinkButton href="/agent/customers" variant="secondary">
          一覧へ戻る
        </LinkButton>
      </div>

      <Surface className="flex items-center gap-4">
        <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-brand-soft text-brand">
          <User size={30} strokeWidth={1.6} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[20px] font-bold text-text-primary">{customer.full_name}</p>
          {customer.full_name_kana ? (
            <p className="truncate text-[13px] text-text-secondary">{customer.full_name_kana}</p>
          ) : null}
          <div className="mt-1.5">
            <StatusPill tone="brand">
              {CUSTOMER_TYPE_LABELS[customer.customer_type] ?? customer.customer_type}
            </StatusPill>
          </div>
        </div>
      </Surface>

      <div className="space-y-2 px-1">
        <p className="text-[13px] font-semibold tracking-wide text-text-secondary">基本情報</p>
      </div>
      <Surface>
        <dl className="divide-y divide-border-soft">
          <Row label="メール" value={customer.email ?? "—"} />
          <Row label="電話番号" value={customer.phone ?? "—"} />
          <Row
            label="年代"
            value={customer.age_group ? (AGE_GROUP_LABELS[customer.age_group] ?? "—") : "未回答"}
          />
          <Row
            label="性別"
            value={customer.gender ? (GENDER_LABELS[customer.gender] ?? "—") : "未回答"}
          />
          <Row label="都道府県" value={customer.prefecture ?? "—"} />
          <Row label="担当開始日" value={formatDate(assignment.assigned_at)} />
        </dl>
      </Surface>

      <div className="space-y-2 px-1">
        <p className="text-[13px] font-semibold tracking-wide text-text-secondary">担当情報</p>
      </div>
      <Surface>
        <div className="mb-3 flex items-center gap-2">
          <Lock size={16} className="text-text-secondary" />
          <p className="text-[13px] text-text-secondary">担当代理店は初回登録時に確定し、以後変更されません。</p>
        </div>
        <dl className="divide-y divide-border-soft">
          <Row
            label="担当代理店"
            value={
              <span className="inline-flex items-center gap-1.5">
                {agent.display_name}
                <StatusPill tone="brand">自分</StatusPill>
              </span>
            }
          />
          <Row label="代理店ID" value={agent.public_id} mono />
          <Row
            label="確定経路"
            value={ASSIGNMENT_SOURCE_LABELS[assignment.assignment_source] ?? assignment.assignment_source}
          />
        </dl>
      </Surface>

      <div className="space-y-2 px-1">
        <p className="text-[13px] font-semibold tracking-wide text-text-secondary">購入情報</p>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Surface className="!p-4">
          <p className="text-[13px] text-text-secondary">購入合計</p>
          <p className="mt-0.5 text-[22px] font-bold tabular-nums text-text-primary">
            {formatYen(total)}
          </p>
        </Surface>
        <Surface className="!p-4">
          <p className="text-[13px] text-text-secondary">最終購入日</p>
          <p className="mt-0.5 text-[22px] font-bold tabular-nums text-text-primary">
            {lastPurchase ? formatDate(lastPurchase.purchased_at) : "—"}
          </p>
        </Surface>
      </div>

      {purchases.length === 0 ? (
        <EmptyState title="購入履歴はありません" />
      ) : (
        <Surface padded={false} className="divide-y divide-border-soft px-4">
          {purchases.map((p) => (
            <div key={p.id} className="py-3">
              <div className="flex items-center justify-between">
                <p className="text-[14px] font-medium text-text-primary">{p.product_name}</p>
                <p className="text-[14px] font-semibold tabular-nums text-text-primary">
                  {formatYen(Number(p.amount))}
                </p>
              </div>
              <p className="mt-0.5 text-[12px] text-text-secondary">
                {PRODUCT_CATEGORY_LABELS[p.product_category] ?? p.product_category} ·{" "}
                {formatDateTime(p.purchased_at)} · 数量 {p.quantity} · {p.status}
              </p>
            </div>
          ))}
        </Surface>
      )}

      <div className="space-y-2 px-1">
        <p className="text-[13px] font-semibold tracking-wide text-text-secondary">問い合わせ履歴</p>
      </div>
      <EmptyState title="準備中の機能です" description="今後のアップデートで対応予定です。" />
    </>
  );
}

function Row({
  label,
  value,
  mono = false,
}: {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex items-center justify-between py-2.5">
      <dt className="text-[13px] text-text-secondary">{label}</dt>
      <dd className={`text-[14px] font-medium text-text-primary ${mono ? "font-mono" : ""}`}>
        {value}
      </dd>
    </div>
  );
}
