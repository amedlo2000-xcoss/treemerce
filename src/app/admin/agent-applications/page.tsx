import Link from "next/link";

import {
  Badge,
  DataTable,
  EmptyState,
  Mono,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDateTime,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import {
  AGENT_APPLICATION_SOURCE_LABELS,
  AGENT_APPLICATION_STATUSES,
  AGENT_APPLICATION_STATUS_BADGE,
  AGENT_APPLICATION_STATUS_LABELS,
  type AgentApplicationStatus,
} from "@/lib/domain/enums";
import type { AdminAgentApplication } from "@/lib/domain/types";

/**
 * 代理店申請の一覧 (super_admin 専用。RPC 側でも判定)。既定は承認待ち。
 * 招待元は申請に使われたリンクの代理店で、申請時点で固定されている (承認時に変更できない)。
 */
export default async function AdminAgentApplicationsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const { supabase } = await requireSuperAdminPage("/admin/agent-applications");

  const statusFilter: AgentApplicationStatus | null =
    status === "all"
      ? null
      : (AGENT_APPLICATION_STATUSES as readonly string[]).includes(status ?? "")
        ? (status as AgentApplicationStatus)
        : "pending";

  const { data, error } = await supabase.rpc("treemerce_admin_list_agent_applications", {
    p_status: statusFilter,
  });
  if (error) throw new Error("代理店申請を読み込めませんでした。");
  const applications = (data ?? []) as AdminAgentApplication[];

  const tabs: { key: string; label: string; active: boolean }[] = [
    ...AGENT_APPLICATION_STATUSES.map((s) => ({
      key: s as string,
      label: AGENT_APPLICATION_STATUS_LABELS[s],
      active: statusFilter === s,
    })),
    { key: "all", label: "すべて", active: statusFilter === null },
  ];

  return (
    <>
      <PageHeader
        title="代理店申請"
        description="紹介リンクの登録フォームと、運営の代理店登録リンクから届いた代理店登録のお申し込みを審査します。承認すると代理店が作られ、却下した場合は会員のままです。承認・却下の理由は監査ログに記録され、申請者本人には表示されません。"
      />

      <nav className="flex flex-wrap gap-2" aria-label="状態で絞り込み">
        {tabs.map((t) => (
          <Link
            key={t.key}
            href={`/admin/agent-applications?status=${t.key}`}
            className={`rounded-full border px-3 py-1.5 text-[13px] font-medium ${
              t.active ? "border-brand bg-brand-soft text-brand" : "border-border-soft text-text-secondary hover:bg-surface-muted"
            }`}
          >
            {t.label}
          </Link>
        ))}
      </nav>

      <SectionTitle count={applications.length}>申請一覧</SectionTitle>

      {applications.length === 0 ? (
        <EmptyState title="該当する申請はありません" />
      ) : (
        <DataTable headers={["申請日時", "代理店名", "メールアドレス", "経路", "招待元", "状態", "審査日時"]}>
          {applications.map((a) => (
            <tr key={a.id}>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(a.created_at)}</td>
              <td className={TD_STRONG}>
                <Link href={`/admin/agent-applications/${a.id}`} className="hover:text-brand">
                  {a.display_name}
                </Link>
              </td>
              <td className={TD}>{a.email}</td>
              <td className={TD}>
                {AGENT_APPLICATION_SOURCE_LABELS[a.source] ?? a.source}
                {a.registration_link?.note ? (
                  <div className="text-[12px] text-text-secondary">{a.registration_link.note}</div>
                ) : null}
              </td>
              <td className={TD}>
                {a.inviter ? (
                  <>
                    <Mono>{a.inviter.public_id}</Mono>
                    <div className="text-text-primary">{a.inviter.display_name}</div>
                  </>
                ) : (
                  "なし (運営からの直接登録)"
                )}
              </td>
              <td className={TD}>
                <Badge tone={AGENT_APPLICATION_STATUS_BADGE[a.status]}>
                  {AGENT_APPLICATION_STATUS_LABELS[a.status]}
                </Badge>
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(a.reviewed_at)}</td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
