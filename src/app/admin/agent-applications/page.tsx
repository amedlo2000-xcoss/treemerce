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

import { QuickApprove } from "./QuickApprove";

/**
 * 代理店申請の一覧 (super_admin 専用。RPC 側でも判定)。既定は承認待ち。
 * 紹介者 (紐づけ先) は申請に使われたリンクの代理店 (運営のリンクは運営直接) で、申請時点で固定されている
 * (承認時に変更できない)。承認の判断で最も重要な情報なので、一覧の先頭の列に出す。
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
  if (error) throw new Error("オブザーバー申請を読み込めませんでした。");
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
        title="オブザーバー申請"
        description="紹介リンクの登録フォームと、オブザーバー登録リンク (運営・オブザーバーが発行) から届いたオブザーバー登録のお申し込みを審査します。承認すると、紹介者の下にオブザーバーが作られます (紹介者は申し込みの時点で確定しており、変更できません)。承認・却下の理由は監査ログに記録され、申請者本人には表示されません。"
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
        <DataTable headers={["紹介者 (紐づけ先)", "申請日時", "オブザーバー名 / 氏名", "メールアドレス", "経路", "状態", "審査日時", "操作"]}>
          {applications.map((a) => (
            <tr key={a.id}>
              <td className="px-4 py-3 align-top">
                {a.inviter ? (
                  <>
                    <div className="text-[14px] font-bold text-text-primary">{a.inviter.display_name}さん</div>
                    <Mono>{a.inviter.public_id}</Mono>
                  </>
                ) : (
                  <div className="text-[14px] font-bold text-text-primary">運営直接</div>
                )}
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(a.created_at)}</td>
              <td className={TD_STRONG}>
                <Link href={`/admin/agent-applications/${a.id}`} className="hover:text-brand">
                  {a.display_name}
                </Link>
                {a.applicant_name ? (
                  <div className="text-[12px] font-normal text-text-secondary">{a.applicant_name}</div>
                ) : null}
              </td>
              <td className={TD}>{a.email}</td>
              <td className={TD}>
                {AGENT_APPLICATION_SOURCE_LABELS[a.source] ?? a.source}
                {a.registration_link?.note ? (
                  <div className="text-[12px] text-text-secondary">{a.registration_link.note}</div>
                ) : null}
              </td>
              <td className={TD}>
                <Badge tone={AGENT_APPLICATION_STATUS_BADGE[a.status]}>
                  {AGENT_APPLICATION_STATUS_LABELS[a.status]}
                </Badge>
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(a.reviewed_at)}</td>
              <td className={TD}>
                {/* 承認だけを一覧から行える。却下は理由が必須のため詳細ページで行う */}
                {a.status === "pending" ? (
                  <QuickApprove
                    applicationId={a.id}
                    applicantName={a.applicant_name ?? a.display_name}
                    inviterLabel={a.inviter ? `${a.inviter.display_name}さん（${a.inviter.public_id}）` : null}
                    canApprove={!a.inviter || a.inviter.status === "active"}
                  />
                ) : null}
              </td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
