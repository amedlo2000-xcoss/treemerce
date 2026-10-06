import { DataTable, EmptyState, Notice, PageHeader, TD, formatDateTime } from "@/components/ui";
import { requireAdminPage } from "@/lib/auth/viewer";
import type { AuditLogRow } from "@/lib/domain/types";

function summarize(state: Record<string, unknown> | null): string {
  if (!state) return "—";
  const agentId = state["assigned_agent_id"];
  if (typeof agentId === "string") return agentId;
  const status = state["status"];
  if (typeof status === "string") return status;
  return "—";
}

export default async function AdminAuditLogsPage() {
  const { supabase } = await requireAdminPage("/admin/audit-logs");

  const [{ data }, { data: agentData }] = await Promise.all([
    supabase
      .from("admin_audit_logs")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(200),
    supabase.from("agents").select("id, public_id, display_name"),
  ]);

  const logs = (data ?? []) as AuditLogRow[];
  const agentById = new Map(
    ((agentData ?? []) as { id: string; public_id: string; display_name: string }[]).map((a) => [
      a.id,
      `${a.public_id} ${a.display_name}`,
    ]),
  );

  const label = (value: string) => agentById.get(value) ?? value;

  return (
    <>
      <PageHeader
        title="監査ログ"
        description="管理者操作の変更前後・理由・実行者・日時の記録です。"
      />

      <Notice tone="info">監査ログは追記専用です。作成後に更新・削除することはできません。</Notice>

      {logs.length === 0 ? (
        <EmptyState title="監査ログはまだありません" />
      ) : (
        <DataTable headers={["日時", "操作", "対象", "変更前", "変更後", "理由", "実行者"]}>
          {logs.map((log) => (
            <tr key={log.id}>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(log.created_at)}</td>
              <td className={TD}>
                <span className="rounded-lg bg-surface-muted px-2 py-1 font-mono text-[12px] text-text-primary">
                  {log.action}
                </span>
              </td>
              <td className={TD}>{log.target_table}</td>
              <td className={TD}>{label(summarize(log.before_state))}</td>
              <td className={TD}>{label(summarize(log.after_state))}</td>
              <td className={`${TD} text-text-primary`}>{log.reason ?? "—"}</td>
              <td className={TD}>
                {log.actor_role}
                <br />
                <span className="font-mono text-[11px] text-text-secondary">
                  {log.actor_user_id ?? "—"}
                </span>
              </td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
