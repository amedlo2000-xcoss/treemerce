import { notFound } from "next/navigation";

import {
  Badge,
  Card,
  DataTable,
  LinkButton,
  PageHeader,
  formatDate,
  formatDateTime,
  formatYen,
} from "@/components/ui";
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
  const total = purchases
    .filter((p) => p.status !== "cancelled" && p.status !== "refunded")
    .reduce((sum, p) => sum + Number(p.amount ?? 0), 0);

  return (
    <>
      <PageHeader
        title={customer.full_name}
        description={customer.full_name_kana ?? undefined}
        action={
          <LinkButton href="/agent/customers" variant="secondary">
            一覧へ戻る
          </LinkButton>
        }
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="基本情報">
          <dl className="grid grid-cols-[7rem_1fr] gap-y-2.5 text-sm">
            <dt className="text-zinc-500 dark:text-zinc-400">メール</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">{customer.email ?? "—"}</dd>
            <dt className="text-zinc-500 dark:text-zinc-400">電話番号</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">{customer.phone ?? "—"}</dd>
            <dt className="text-zinc-500 dark:text-zinc-400">年代</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">
              {customer.age_group ? (AGE_GROUP_LABELS[customer.age_group] ?? "—") : "未回答"}
            </dd>
            <dt className="text-zinc-500 dark:text-zinc-400">性別</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">
              {customer.gender ? (GENDER_LABELS[customer.gender] ?? "—") : "未回答"}
            </dd>
            <dt className="text-zinc-500 dark:text-zinc-400">都道府県</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">{customer.prefecture ?? "—"}</dd>
            <dt className="text-zinc-500 dark:text-zinc-400">区分</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">
              {CUSTOMER_TYPE_LABELS[customer.customer_type] ?? customer.customer_type}
            </dd>
          </dl>
        </Card>

        <Card title="担当情報" description="担当代理店は初回登録時に確定し、以後は変更されません。">
          <dl className="grid grid-cols-[7rem_1fr] gap-y-2.5 text-sm">
            <dt className="text-zinc-500 dark:text-zinc-400">担当代理店</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">
              {agent.display_name}
              <Badge tone="blue">自分</Badge>
            </dd>
            <dt className="text-zinc-500 dark:text-zinc-400">担当開始日</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">
              {formatDate(assignment.assigned_at)}
            </dd>
            <dt className="text-zinc-500 dark:text-zinc-400">確定経路</dt>
            <dd className="text-zinc-900 dark:text-zinc-100">
              {ASSIGNMENT_SOURCE_LABELS[assignment.assignment_source] ??
                assignment.assignment_source}
            </dd>
            <dt className="text-zinc-500 dark:text-zinc-400">購入合計</dt>
            <dd className="tabular-nums text-zinc-900 dark:text-zinc-100">{formatYen(total)}</dd>
          </dl>
        </Card>
      </div>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">購入履歴</h2>
        {purchases.length === 0 ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">購入履歴はありません。</p>
        ) : (
          <DataTable headers={["購入日", "商品名", "カテゴリ", "数量", "金額", "状態"]}>
            {purchases.map((p) => (
              <tr key={p.id} className="bg-white dark:bg-zinc-950">
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {formatDateTime(p.purchased_at)}
                </td>
                <td className="px-4 py-3 text-sm text-zinc-900 dark:text-zinc-100">
                  {p.product_name}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {PRODUCT_CATEGORY_LABELS[p.product_category] ?? p.product_category}
                </td>
                <td className="px-4 py-3 text-right text-sm tabular-nums">{p.quantity}</td>
                <td className="px-4 py-3 text-right text-sm tabular-nums">
                  {formatYen(Number(p.amount))}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">{p.status}</td>
              </tr>
            ))}
          </DataTable>
        )}
      </section>
    </>
  );
}
