import Link from "next/link";
import { notFound } from "next/navigation";

import {
  BackLink,
  Badge,
  Card,
  DataTable,
  DetailList,
  DetailRow,
  EmptyState,
  Mono,
  Notice,
  TD,
  TD_STRONG,
  formatDate,
  formatDateTime,
  formatYen,
} from "@/components/ui";
import { ProfileHero, StatTile } from "@/components/mobile/primitives";
import { OrderStatusBadge } from "@/components/OrderStatusBadge";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import {
  AGE_GROUP_LABELS,
  ASSIGNMENT_SOURCE_LABELS,
  CUSTOMER_TYPE_LABELS,
  GENDER_LABELS,
  PRODUCT_CATEGORY_LABELS,
  PURCHASE_STATUS_LABELS,
} from "@/lib/domain/enums";
import type { AssignmentHistoryRow, CustomerRow, PurchaseRow } from "@/lib/domain/types";

import { TransferForm } from "../../assignments/TransferForm";
import { CustomerEditForm } from "./CustomerEditForm";

type CurrentAssignment = {
  id: string;
  assigned_at: string;
  assignment_source: string;
  agent: { id: string; public_id: string; display_name: string } | null;
};

/**
 * 統括管理: 購入者詳細。super_admin 専用 (requireSuperAdminPage)。
 * ADMIN は匿名化の対象外なので、氏名・連絡先・購入内容・購入額・担当代理店を
 * すべてそのまま表示する。担当変更と編集はここから行い、両方とも監査ログに記録される。
 */
export default async function AdminCustomerDetailPage({
  params,
}: {
  params: Promise<{ customerId: string }>;
}) {
  const { customerId } = await params;
  const { supabase } = await requireSuperAdminPage(`/admin/customers/${customerId}`);

  const [
    { data: customerData },
    { data: purchaseData },
    { data: assignmentData },
    { data: historyData },
    { data: agentData },
    { data: orderData },
  ] = await Promise.all([
    supabase.from("customers").select("*").eq("id", customerId).maybeSingle(),
    supabase
      .from("purchases")
      .select("*")
      .eq("customer_id", customerId)
      .order("purchased_at", { ascending: false }),
    supabase
      .from("customer_assignments")
      .select(
        "id, assigned_at, assignment_source, agent:agents!customer_assignments_assigned_agent_id_fkey ( id, public_id, display_name )",
      )
      .eq("customer_id", customerId)
      .eq("status", "active")
      .maybeSingle(),
    supabase
      .from("customer_assignment_history")
      .select("*")
      .eq("customer_id", customerId)
      .order("changed_at", { ascending: false }),
    supabase
      .from("agents")
      .select("id, public_id, display_name, status")
      .eq("status", "active")
      .order("public_id"),
    supabase
      .from("orders")
      .select("id, order_no, status, total, ordered_at")
      .eq("customer_id", customerId)
      .order("ordered_at", { ascending: false }),
  ]);

  const customer = customerData as CustomerRow | null;
  if (!customer) notFound();

  const purchases = (purchaseData ?? []) as PurchaseRow[];
  const history = (historyData ?? []) as AssignmentHistoryRow[];
  const currentAssignment = assignmentData as unknown as CurrentAssignment | null;
  const agents = (agentData ?? []) as { id: string; public_id: string; display_name: string }[];
  const agentById = new Map(agents.map((a) => [a.id, a]));

  const validPurchases = purchases.filter(
    (p) => p.status !== "cancelled" && p.status !== "refunded",
  );
  const total = validPurchases.reduce((sum, p) => sum + Number(p.amount ?? 0), 0);

  const lastPurchase = purchases[0] ?? null;
  const orders = (orderData ?? []) as {
    id: string;
    order_no: string;
    status: string;
    total: number;
    ordered_at: string;
  }[];

  return (
    <>
      <BackLink href="/admin/customers">購入者一覧</BackLink>

      <ProfileHero
        name={customer.full_name}
        subtitle={customer.full_name_kana}
        pills={
          <>
            <Badge tone="blue">
              {CUSTOMER_TYPE_LABELS[customer.customer_type] ?? customer.customer_type}
            </Badge>
            {customer.prefecture ? <Badge>{customer.prefecture}</Badge> : null}
            {currentAssignment?.agent ? (
              <Badge tone="green">担当: {currentAssignment.agent.display_name}</Badge>
            ) : (
              <Badge tone="amber">担当なし</Badge>
            )}
          </>
        }
        meta={
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <StatTile label="購入合計" value={formatYen(total)} />
            <StatTile label="購入件数" value={`${purchases.length}件`} />
            <StatTile
              label="最終購入"
              value={lastPurchase ? formatDate(lastPurchase.purchased_at) : "—"}
            />
            <StatTile label="登録日" value={formatDate(customer.created_at)} />
          </div>
        }
      />

      <Notice tone="info">
        super_admin には匿名化を適用しません。実名・連絡先・購入内容がすべて表示されています。
      </Notice>

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-6 lg:space-y-0">
        <div className="space-y-5">
          <Card title="基本情報">
            <DetailList>
              <DetailRow label="メール" value={customer.email ?? "—"} />
              <DetailRow label="電話番号" value={customer.phone ?? "—"} />
              <DetailRow label="郵便番号" value={customer.postal_code ?? "—"} />
              <DetailRow label="住所" value={customer.address_line ?? "—"} />
              <DetailRow label="都道府県" value={customer.prefecture ?? "—"} />
              <DetailRow
                label="年代"
                value={
                  customer.age_group ? (AGE_GROUP_LABELS[customer.age_group] ?? "—") : "未回答"
                }
              />
              <DetailRow
                label="性別"
                value={customer.gender ? (GENDER_LABELS[customer.gender] ?? "—") : "未回答"}
              />
              <DetailRow label="備考" value={customer.note ?? "—"} />
            </DetailList>
          </Card>

          <Card
            title="現在の担当代理店"
            description="担当代理店は初回登録時に確定します。変更は下部フォームから super_admin が行います。"
          >
            {currentAssignment?.agent ? (
              <DetailList>
                <DetailRow
                  label="代理店"
                  value={
                    <Link
                      href={`/admin/agents/${currentAssignment.agent.id}`}
                      className="font-medium text-brand hover:underline"
                    >
                      <span className="font-mono text-[12px]">
                        {currentAssignment.agent.public_id}
                      </span>{" "}
                      {currentAssignment.agent.display_name}
                    </Link>
                  }
                />
                <DetailRow label="担当開始日" value={formatDate(currentAssignment.assigned_at)} />
                <DetailRow
                  label="確定経路"
                  value={
                    ASSIGNMENT_SOURCE_LABELS[currentAssignment.assignment_source] ??
                    currentAssignment.assignment_source
                  }
                />
              </DetailList>
            ) : (
              <p className="text-[13px] text-text-secondary">現在の担当がありません。</p>
            )}
          </Card>
        </div>

        <div className="space-y-5">
          <Card title="購入情報">
            {purchases.length === 0 ? (
              <EmptyState title="購入履歴はありません" />
            ) : (
              <DataTable headers={["商品名", "カテゴリ", "数量", "金額", "状態", "購入日時"]}>
                {purchases.map((p) => (
                  <tr key={p.id}>
                    <td className={TD_STRONG}>{p.product_name}</td>
                    <td className={TD}>
                      {PRODUCT_CATEGORY_LABELS[p.product_category] ?? p.product_category}
                    </td>
                    <td className={`${TD} tabular-nums`}>{p.quantity}</td>
                    <td className={`${TD} font-semibold tabular-nums text-text-primary`}>
                      {formatYen(Number(p.amount))}
                    </td>
                    <td className={TD}>
                      <Badge tone={PURCHASE_STATUS_TONE[p.status] ?? "neutral"}>
                        {PURCHASE_STATUS_LABELS[p.status] ?? p.status}
                      </Badge>
                    </td>
                    <td className={`${TD} whitespace-nowrap`}>{formatDateTime(p.purchased_at)}</td>
                  </tr>
                ))}
              </DataTable>
            )}
          </Card>

          <Card title="注文履歴" description="ショップからの注文です。詳細・ステータス変更は注文管理から行います。">
            {orders.length === 0 ? (
              <EmptyState title="注文はありません" />
            ) : (
              <DataTable headers={["注文番号", "合計", "状態", "注文日時"]}>
                {orders.map((o) => (
                  <tr key={o.id}>
                    <td className={TD}>
                      <Link
                        href={`/admin/orders/${o.id}`}
                        className="font-mono text-[12px] font-semibold text-brand hover:underline"
                      >
                        {o.order_no}
                      </Link>
                    </td>
                    <td className={`${TD} font-semibold tabular-nums text-text-primary`}>
                      {formatYen(Number(o.total))}
                    </td>
                    <td className={TD}>
                      <OrderStatusBadge status={o.status} />
                    </td>
                    <td className={`${TD} whitespace-nowrap`}>{formatDateTime(o.ordered_at)}</td>
                  </tr>
                ))}
              </DataTable>
            )}
          </Card>

          <Card title="担当変更履歴">
            {history.length === 0 ? (
              <EmptyState title="担当変更の履歴はありません" />
            ) : (
              <DataTable headers={["変更日時", "変更前", "変更後", "理由", "実行者区分"]}>
                {history.map((h) => (
                  <tr key={h.id}>
                    <td className={`${TD} whitespace-nowrap`}>{formatDateTime(h.changed_at)}</td>
                    <td className={TD}>
                      {h.previous_agent_id
                        ? (agentById.get(h.previous_agent_id)?.display_name ?? h.previous_agent_id)
                        : "—（初回登録）"}
                    </td>
                    <td className={`${TD} text-text-primary`}>
                      {agentById.get(h.new_agent_id)?.display_name ?? h.new_agent_id}
                    </td>
                    <td className={TD}>{h.reason}</td>
                    <td className={TD}>
                      <Mono>{h.changed_by_role}</Mono>
                    </td>
                  </tr>
                ))}
              </DataTable>
            )}
          </Card>

          <Card
            title="担当代理店を変更する"
            description="この操作は super_admin のみ実行できます。理由の入力は必須です。"
          >
            {currentAssignment?.agent ? (
              <TransferForm
                fixedCustomer={{
                  id: customer.id,
                  label: customer.full_name,
                  currentAgentId: currentAssignment.agent.id,
                }}
                agents={agents.map((a) => ({
                  id: a.id,
                  label: `${a.public_id} ${a.display_name}`,
                }))}
              />
            ) : (
              <p className="text-[13px] text-text-secondary">
                現在の担当がないため、担当変更を実行できません。
              </p>
            )}
          </Card>

          <Card
            title="購入者情報を編集する"
            description="識別子(氏名/メール/電話)を含む全項目を編集できます。理由の入力は必須です。"
          >
            <CustomerEditForm customer={customer} />
          </Card>
        </div>
      </div>
    </>
  );
}

const PURCHASE_STATUS_TONE: Record<string, "green" | "amber" | "red" | "neutral"> = {
  completed: "green",
  pending: "amber",
  cancelled: "neutral",
  refunded: "red",
};
