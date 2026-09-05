import { Badge, DataTable, EmptyState, Notice, PageHeader, formatDate } from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { AgentRow } from "@/lib/domain/types";

/**
 * STEP8: 代理店管理。
 * ここで扱うのは「代理店の登録経路 (invited_by)」だけ。
 * 顧客の担当関係は別メニュー (顧客担当管理) の責務であり、この画面には出さない。
 */
export default async function AdminAgentsPage() {
  const { supabase } = await requireAdminPage("/admin/agents");

  const { data } = await supabase
    .from("agents")
    .select(
      "id, public_id, display_name, email, phone, prefecture, status, invited_by, registered_at",
    )
    .order("registered_at", { ascending: true });

  const agents = (data ?? []) as AgentRow[];
  const byId = new Map(agents.map((a) => [a.id, a]));

  return (
    <>
      <PageHeader
        title="代理店管理"
        description="代理店の登録経路 (招待元) と利用開始状態を管理します。"
      />

      <Notice tone="warning">
        招待元は1代理店につき1つで、一度確定すると変更できません。
        招待元は代理店の登録経路を表すもので、購入者の担当代理店とは別のデータです。
      </Notice>

      {agents.length === 0 ? (
        <EmptyState title="登録済みの代理店がありません" />
      ) : (
        <DataTable
          headers={["代理店ID", "代理店名", "連絡先", "招待元 (登録経路)", "状態", "登録日"]}
        >
          {agents.map((agent) => {
            const inviter = agent.invited_by ? byId.get(agent.invited_by) : null;
            return (
              <tr key={agent.id} className="bg-white dark:bg-zinc-950">
                <td className="px-4 py-3 font-mono text-xs text-zinc-600 dark:text-zinc-400">
                  {agent.public_id}
                </td>
                <td className="px-4 py-3 text-sm font-medium text-zinc-900 dark:text-zinc-100">
                  {agent.display_name}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {agent.email}
                  <br />
                  {agent.phone ?? "—"}
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {inviter ? (
                    <>
                      <span className="font-mono">{inviter.public_id}</span> {inviter.display_name}
                    </>
                  ) : (
                    <span className="text-zinc-400">直接登録 (招待元なし)</span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <Badge tone={agent.status === "active" ? "green" : "neutral"}>
                    {AGENT_STATUS_LABELS[agent.status] ?? agent.status}
                  </Badge>
                </td>
                <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                  {formatDate(agent.registered_at)}
                </td>
              </tr>
            );
          })}
        </DataTable>
      )}
    </>
  );
}
