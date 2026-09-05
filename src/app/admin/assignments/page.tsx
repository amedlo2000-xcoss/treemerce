import {
  Badge,
  Card,
  DataTable,
  EmptyState,
  Notice,
  PageHeader,
  formatDateTime,
} from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";
import { ASSIGNMENT_SOURCE_LABELS, ASSIGNMENT_STATUS_LABELS } from "@/lib/domain/enums";

import { TransferForm } from "./TransferForm";

type AssignmentRow = {
  id: string;
  customer_id: string;
  assigned_agent_id: string;
  assigned_at: string;
  assignment_source: string;
  status: string;
  customer: { id: string; full_name: string; email: string | null } | null;
  agent: { id: string; public_id: string; display_name: string } | null;
};

type HistoryRow = {
  id: string;
  customer_id: string;
  previous_agent_id: string | null;
  new_agent_id: string;
  reason: string;
  changed_by_role: string;
  changed_at: string;
};

/**
 * STEP8: 顧客担当管理。
 * 担当変更はここからのみ。実行は ADMIN 専用 RPC を通り、
 * 変更前後・理由・実行者・日時が履歴と監査ログに記録される。
 */
export default async function AdminAssignmentsPage({
  searchParams,
}: {
  searchParams: Promise<{ customer_id?: string }>;
}) {
  const { customer_id: customerId } = await searchParams;
  const { supabase } = await requireAdminPage("/admin/assignments");

  let assignmentQuery = supabase
    .from("customer_assignments")
    .select(
      `id, customer_id, assigned_agent_id, assigned_at, assignment_source, status,
       customer:customers ( id, full_name, email ),
       agent:agents!customer_assignments_assigned_agent_id_fkey ( id, public_id, display_name )`,
    )
    .order("assigned_at", { ascending: false })
    .limit(200);

  let historyQuery = supabase
    .from("customer_assignment_history")
    .select("id, customer_id, previous_agent_id, new_agent_id, reason, changed_by_role, changed_at")
    .order("changed_at", { ascending: false })
    .limit(100);

  if (customerId) {
    assignmentQuery = assignmentQuery.eq("customer_id", customerId);
    historyQuery = historyQuery.eq("customer_id", customerId);
  }

  const [{ data: assignmentData }, { data: historyData }, { data: agentData }] = await Promise.all([
    assignmentQuery,
    historyQuery,
    supabase
      .from("agents")
      .select("id, public_id, display_name, status")
      .eq("status", "active")
      .order("public_id"),
  ]);

  const assignments = (assignmentData ?? []) as unknown as AssignmentRow[];
  const history = (historyData ?? []) as HistoryRow[];
  const agents = (agentData ?? []) as { id: string; public_id: string; display_name: string }[];
  const agentById = new Map(agents.map((a) => [a.id, a]));

  const activeAssignments = assignments.filter((a) => a.status === "active");
  const customerOptions = activeAssignments.map((a) => ({
    id: a.customer_id,
    label: `${a.customer?.full_name ?? a.customer_id} — 現担当: ${
      a.agent?.display_name ?? "不明"
    }`,
    currentAgentId: a.assigned_agent_id,
  }));

  return (
    <>
      <PageHeader
        title="顧客担当管理"
        description="購入者ごとの担当代理店を確認し、必要な場合のみ管理者権限で変更します。"
      />

      <Notice tone="warning">
        担当代理店は初回登録時に確定します。ここでの変更は例外的な運用であり、
        変更前後・理由・実行者・日時が担当変更履歴と監査ログの両方に必ず記録されます。
        代理店自身がこの操作を行うことはできません。
      </Notice>

      <Card
        title="担当を変更する"
        description="この操作は管理者のみが実行できます。理由の入力は必須です。"
      >
        {customerOptions.length === 0 ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">
            変更できる担当関係がありません。
          </p>
        ) : (
          <TransferForm
            customers={customerOptions}
            agents={agents.map((a) => ({ id: a.id, label: `${a.public_id} ${a.display_name}` }))}
          />
        )}
      </Card>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">担当一覧</h2>
        {assignments.length === 0 ? (
          <EmptyState title="担当関係がありません" />
        ) : (
          <DataTable headers={["購入者", "担当代理店", "状態", "確定経路", "担当開始"]}>
            {assignments.map((a) => (
              <tr key={a.id} className="bg-white dark:bg-zinc-950">
                <td className="px-4 py-3 text-sm text-zinc-900 dark:text-zinc-100">
                  {a.customer?.full_name ?? "—"}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-700 dark:text-zinc-300">
                  <span className="font-mono text-zinc-500">{a.agent?.public_id}</span>{" "}
                  {a.agent?.display_name}
                </td>
                <td className="px-4 py-3">
                  <Badge tone={a.status === "active" ? "green" : "neutral"}>
                    {ASSIGNMENT_STATUS_LABELS[a.status] ?? a.status}
                  </Badge>
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {ASSIGNMENT_SOURCE_LABELS[a.assignment_source] ?? a.assignment_source}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {formatDateTime(a.assigned_at)}
                </td>
              </tr>
            ))}
          </DataTable>
        )}
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">担当変更履歴</h2>
        {history.length === 0 ? (
          <EmptyState title="担当変更の履歴はありません" />
        ) : (
          <DataTable headers={["変更日時", "変更前", "変更後", "理由", "実行者区分"]}>
            {history.map((h) => (
              <tr key={h.id} className="bg-white dark:bg-zinc-950">
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {formatDateTime(h.changed_at)}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-700 dark:text-zinc-300">
                  {h.previous_agent_id
                    ? (agentById.get(h.previous_agent_id)?.display_name ?? h.previous_agent_id)
                    : "—（初回登録）"}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-700 dark:text-zinc-300">
                  {agentById.get(h.new_agent_id)?.display_name ?? h.new_agent_id}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-700 dark:text-zinc-300">{h.reason}</td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {h.changed_by_role}
                </td>
              </tr>
            ))}
          </DataTable>
        )}
      </section>
    </>
  );
}
