import Link from "next/link";

import { DataTable, EmptyState, Notice, PageHeader, formatDate } from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";
import { AGE_GROUP_LABELS, CUSTOMER_TYPE_LABELS, GENDER_LABELS } from "@/lib/domain/enums";

type Row = {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  prefecture: string | null;
  age_group: string | null;
  gender: string | null;
  customer_type: string;
  created_at: string;
  assignments: {
    id: string;
    status: string;
    assigned_at: string;
    agent: { id: string; public_id: string; display_name: string } | null;
  }[];
};

/**
 * STEP8: 商品購入者管理。
 * CASE10: 購入者に紐づくのは「担当代理店」だけ。
 *         代理店の招待経路 (invited_by) はこの画面には一切出さない。
 */
export default async function AdminCustomersPage() {
  const { supabase } = await requireAdminPage("/admin/customers");

  const { data } = await supabase
    .from("customers")
    .select(
      `id, full_name, email, phone, prefecture, age_group, gender, customer_type, created_at,
       assignments:customer_assignments (
         id, status, assigned_at,
         agent:agents!customer_assignments_assigned_agent_id_fkey ( id, public_id, display_name )
       )`,
    )
    .order("created_at", { ascending: false })
    .limit(200);

  const customers = (data ?? []) as unknown as Row[];

  return (
    <>
      <PageHeader
        title="商品購入者管理"
        description="購入者の情報と、現在の担当代理店を確認します。"
      />

      <Notice tone="info">
        この画面に表示されるのは「購入者 ↔ 担当代理店」の関係だけです。
        代理店同士の招待経路とは別のデータなので、混同しないようご注意ください。
        担当の変更は「顧客担当管理」から行います。
      </Notice>

      {customers.length === 0 ? (
        <EmptyState title="登録済みの購入者がいません" />
      ) : (
        <DataTable headers={["氏名", "連絡先", "属性", "現在の担当代理店", "登録日", ""]}>
          {customers.map((customer) => {
            const active = customer.assignments?.find((a) => a.status === "active");
            return (
              <tr key={customer.id} className="bg-white dark:bg-zinc-950">
                <td className="px-4 py-3 text-sm font-medium text-zinc-900 dark:text-zinc-100">
                  {customer.full_name}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {customer.email ?? "—"}
                  <br />
                  {customer.phone ?? "—"}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {customer.age_group
                    ? (AGE_GROUP_LABELS[customer.age_group] ?? customer.age_group)
                    : "未回答"}{" "}
                  /{" "}
                  {customer.gender
                    ? (GENDER_LABELS[customer.gender] ?? customer.gender)
                    : "未回答"}
                  <br />
                  {customer.prefecture ?? "—"} ·{" "}
                  {CUSTOMER_TYPE_LABELS[customer.customer_type] ?? customer.customer_type}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-700 dark:text-zinc-300">
                  {active?.agent ? (
                    <>
                      <span className="font-mono text-zinc-500">{active.agent.public_id}</span>{" "}
                      {active.agent.display_name}
                      <br />
                      <span className="text-[11px] text-zinc-400">
                        {formatDate(active.assigned_at)} から
                      </span>
                    </>
                  ) : (
                    <span className="text-zinc-400">担当なし</span>
                  )}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {formatDate(customer.created_at)}
                </td>
                <td className="px-4 py-3 text-right">
                  <Link
                    href={`/admin/assignments?customer_id=${customer.id}`}
                    className="text-xs font-medium text-blue-700 hover:underline dark:text-blue-400"
                  >
                    担当を管理
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
