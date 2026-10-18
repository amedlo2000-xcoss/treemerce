import { notFound } from "next/navigation";

import {
  BackLink,
  Badge,
  Card,
  DetailList,
  DetailRow,
  Mono,
  Notice,
  PageHeader,
  TextLink,
  formatDateTime,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import {
  AGENT_APPLICATION_AUDIT_LABELS,
  AGENT_APPLICATION_SOURCE_LABELS,
  AGENT_APPLICATION_STATUS_BADGE,
  AGENT_APPLICATION_STATUS_LABELS,
  AGENT_STATUS_LABELS,
} from "@/lib/domain/enums";
import type { AdminAgentApplicationDetail } from "@/lib/domain/types";

import { ReviewPanel } from "./ReviewPanel";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 代理店申請の詳細と審査 (super_admin 専用。RPC 側でも判定)。
 * 招待元は申請時点で固定されており、ここでは変更できない。審査の履歴 (理由を含む) は運営にだけ表示する。
 */
export default async function AdminAgentApplicationPage({
  params,
}: {
  params: Promise<{ applicationId: string }>;
}) {
  const { applicationId } = await params;
  const { supabase } = await requireSuperAdminPage(`/admin/agent-applications/${applicationId}`);
  if (!UUID.test(applicationId)) notFound();

  const { data, error } = await supabase.rpc("treemerce_admin_get_agent_application", {
    p_application_id: applicationId,
  });
  if (error) {
    if (`${error.message}`.includes("TREEMERCE_APPLICATION_NOT_FOUND")) notFound();
    throw new Error("代理店申請を読み込めませんでした。");
  }
  const a = data as AdminAgentApplicationDetail;

  return (
    <>
      <BackLink href="/admin/agent-applications">代理店申請の一覧</BackLink>
      <PageHeader
        title={a.display_name}
        description="代理店登録のお申し込み"
        action={
          <Badge tone={AGENT_APPLICATION_STATUS_BADGE[a.status]}>{AGENT_APPLICATION_STATUS_LABELS[a.status]}</Badge>
        }
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="申請内容">
          <DetailList>
            <DetailRow label="経路" value={AGENT_APPLICATION_SOURCE_LABELS[a.source] ?? a.source} />
            {a.registration_link ? (
              <DetailRow label="代理店登録リンク" value={a.registration_link.note ?? "(メモなし)"} />
            ) : null}
            <DetailRow label="代理店名" value={a.display_name} />
            <DetailRow label="メールアドレス" value={a.email} />
            <DetailRow label="電話番号" value={a.phone ?? "—"} />
            <DetailRow label="申請日時" value={formatDateTime(a.created_at)} />
            <DetailRow label="アカウント" value={<Mono>{a.auth_user_id}</Mono>} />
          </DetailList>
        </Card>

        <Card
          title="招待元"
          description="申請の時点で確定しています。紹介リンクからの申請はリンクの代理店、運営の代理店登録リンクからの申請は招待元なし (運営からの直接登録) です。承認するとそのまま招待元 (invited_by) になり、あとから変更・追加できません。会員としての担当代理店とは別のデータです。"
        >
          {a.inviter ? (
            <DetailList>
              <DetailRow
                label="代理店"
                value={<TextLink href={`/admin/agents/${a.inviter.id}`}>{a.inviter.display_name}</TextLink>}
              />
              <DetailRow label="代理店ID" value={<Mono>{a.inviter.public_id}</Mono>} />
              <DetailRow label="状態" value={AGENT_STATUS_LABELS[a.inviter.status]} />
            </DetailList>
          ) : (
            <p className="text-[14px] text-text-secondary">なし (運営からの直接登録)</p>
          )}
          {a.status === "pending" && a.inviter && a.inviter.status !== "active" ? (
            <div className="mt-3">
              <Notice tone="warning">
                招待元の代理店が稼働中ではないため、この申請は承認できません
                (招待元を別の代理店に置き換えることもできません)。
              </Notice>
            </div>
          ) : null}
        </Card>

        <Card title="代理店規約への同意">
          {a.terms ? (
            <DetailList>
              <DetailRow label="規約" value={`${a.terms.title} (第 ${a.terms.version} 版)`} />
              <DetailRow label="同意日時" value={formatDateTime(a.terms.accepted_at)} />
              <DetailRow label="同意時のメールアドレス" value={a.terms.accepted_email ?? "—"} />
              <DetailRow label="IP アドレス" value={a.terms.ip_address ?? "—"} />
              <DetailRow
                label="ブラウザ"
                value={<span className="text-[12px] font-normal">{a.terms.user_agent ?? "—"}</span>}
              />
              <DetailRow label="本文のハッシュ (SHA-256)" value={<Mono>{a.terms.body_sha256.slice(0, 16)}…</Mono>} />
            </DetailList>
          ) : (
            <p className="text-[14px] text-text-secondary">—</p>
          )}
        </Card>

        <Card title="審査">
          <DetailList>
            <DetailRow label="状態" value={AGENT_APPLICATION_STATUS_LABELS[a.status]} />
            <DetailRow label="審査日時" value={formatDateTime(a.reviewed_at)} />
            <DetailRow
              label="作成された代理店"
              value={
                a.created_agent_id ? (
                  <TextLink href={`/admin/agents/${a.created_agent_id}`}>代理店の詳細</TextLink>
                ) : (
                  "—"
                )
              }
            />
          </DetailList>
          {a.audit.length > 0 ? (
            <ul className="mt-4 space-y-2">
              {a.audit.map((log) => (
                <li
                  key={`${log.action}-${log.created_at}`}
                  className="rounded-xl bg-surface-muted px-3 py-2.5 text-[13px]"
                >
                  <div className="flex flex-wrap items-center gap-2 text-text-secondary">
                    <span className="font-semibold text-text-primary">
                      {AGENT_APPLICATION_AUDIT_LABELS[log.action] ?? log.action}
                    </span>
                    <span>{formatDateTime(log.created_at)}</span>
                    <span>({log.actor_role})</span>
                  </div>
                  {log.reason ? (
                    <p className="mt-1 whitespace-pre-wrap break-words text-text-primary">{log.reason}</p>
                  ) : null}
                </li>
              ))}
            </ul>
          ) : null}
        </Card>
      </div>

      {a.status === "pending" ? (
        <Card
          title="承認・却下"
          description="理由は必須です。監査ログに記録され、申請者本人には表示されません (本人には中立的な文面だけが表示されます)。"
        >
          <ReviewPanel applicationId={a.id} />
        </Card>
      ) : null}
    </>
  );
}
