import Link from "next/link";

import {
  Badge,
  DataTable,
  EmptyState,
  Notice,
  PageHeader,
  formatDate,
  formatYen,
} from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { AGE_GROUP_LABELS, CUSTOMER_TYPE_LABELS, GENDER_LABELS } from "@/lib/domain/enums";

type Row = {
  id: string;
  assigned_at: string;
  assignment_source: string;
  customer: {
    id: string;
    full_name: string;
    email: string | null;
    phone: string | null;
    prefecture: string | null;
    age_group: string | null;
    gender: string | null;
    customer_type: string;
    purchases: { id: string; amount: number; status: string }[];
  } | null;
};

/**
 * STEP4: 担当顧客一覧。
 * RLS により、自分が担当している購入者しかここには現れない。
 * 傘下代理店が担当する購入者は 1 行も返らない (絶対原則5)。
 */
export default async function AgentCustomersPage() {
  const { supabase } = await requireAgentPage("/agent/customers");

  const { data } = await supabase
    .from("customer_assignments")
    .select(
      `id, assigned_at, assignment_source,
       customer:customers!inner (
         id, full_name, email, phone, prefecture, age_group, gender, customer_type,
         purchases ( id, amount, status )
       )`,
    )
    .eq("status", "active")
    .order("assigned_at", { ascending: false });

  const rows = (data ?? []) as unknown as Row[];

  return (
    <>
      <PageHeader
        title="担当顧客"
        description="あなたが担当している商品購入者の一覧です。他の代理店が担当する購入者は表示されません。"
      />

      <Notice tone="info">
        担当代理店としての正当な閲覧範囲のため、氏名・連絡先・購入商品を表示しています。
      </Notice>

      {rows.length === 0 ? (
        <EmptyState
          title="担当顧客はまだいません"
          description="あなたの登録URLから購入者が登録されると、ここに表示されます。"
        />
      ) : (
        <DataTable
          headers={["氏名", "連絡先", "属性", "購入合計", "担当開始日", ""]}
        >
          {rows.map((row) => {
            const c = row.customer;
            if (!c) return null;
            const total = (c.purchases ?? [])
              .filter((p) => p.status !== "cancelled" && p.status !== "refunded")
              .reduce((sum, p) => sum + Number(p.amount ?? 0), 0);

            return (
              <tr key={row.id} className="bg-white dark:bg-zinc-950">
                <td className="px-4 py-3">
                  <span className="font-medium text-zinc-900 dark:text-zinc-100">
                    {c.full_name}
                  </span>
                  <div className="mt-0.5">
                    <Badge tone="neutral">
                      {CUSTOMER_TYPE_LABELS[c.customer_type] ?? c.customer_type}
                    </Badge>
                  </div>
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {c.email ?? "—"}
                  <br />
                  {c.phone ?? "—"}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {c.age_group ? (AGE_GROUP_LABELS[c.age_group] ?? c.age_group) : "未回答"} /{" "}
                  {c.gender ? (GENDER_LABELS[c.gender] ?? c.gender) : "未回答"}
                  <br />
                  {c.prefecture ?? "—"}
                </td>
                <td className="px-4 py-3 text-right text-sm tabular-nums text-zinc-900 dark:text-zinc-100">
                  {formatYen(total)}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {formatDate(row.assigned_at)}
                </td>
                <td className="px-4 py-3 text-right">
                  <Link
                    href={`/agent/customers/${c.id}`}
                    className="text-xs font-medium text-blue-700 hover:underline dark:text-blue-400"
                  >
                    詳細
                  </Link>
                </td>
              </tr>
            );
          })}
        </DataTable>
      )}
    </>
  );
}
