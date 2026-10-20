import { notFound } from "next/navigation";

import { AgentProfileForm } from "@/app/agent/my/profile/AgentProfileForm";
import { BackLink, Card, Mono, Notice, PageHeader, formatDateTime } from "@/components/ui";
import { UUID } from "@/lib/api/submission-input";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import type { AgentProfile, AgentRow } from "@/lib/domain/types";

/**
 * 代理店の事業プロフィールを運営が入力・編集する (super_admin 専用, 0020)。
 * 入力済みのプロフィールの変更は理由必須。保存は監査ログに「変更した項目名・理由」だけが残る。
 * 招待経路 (invited_by)・顧客の担当はこの画面から一切変更できない。
 */
export default async function AdminAgentProfileEditPage({ params }: { params: Promise<{ agentId: string }> }) {
  const { agentId } = await params;
  if (!UUID.test(agentId)) notFound();
  const { supabase } = await requireSuperAdminPage(`/admin/agents/${agentId}/profile`);

  const { data: agentData } = await supabase
    .from("agents")
    .select("id, public_id, display_name, status")
    .eq("id", agentId)
    .maybeSingle();
  const agent = agentData as Pick<AgentRow, "id" | "public_id" | "display_name" | "status"> | null;
  if (!agent) notFound();

  const { data, error } = await supabase.rpc("treemerce_admin_get_agent_profile", { p_agent_id: agentId });
  if (error || !data) throw new Error("プロフィールを読み込めませんでした。");
  const profile = data as AgentProfile;

  return (
    <>
      <BackLink href={`/admin/agents/${agent.id}`}>オブザーバー詳細</BackLink>
      <PageHeader
        title="事業プロフィールの入力・編集"
        description="オブザーバーから伺った内容を、運営が代わりに入力します。オブザーバー本人のマイページにも表示されます。"
      />

      <Notice tone="info">
        対象のオブザーバー: <Mono>{agent.public_id}</Mono> <strong>{agent.display_name}</strong>
        <br />
        {profile.found
          ? `最終更新 ${formatDateTime(profile.updated_at)} (${profile.updated_by_role === "super_admin" ? "運営" : "本人"})。変更には理由が必要です。`
          : "まだ入力されていません。初回の入力では理由は任意です。"}
      </Notice>

      {agent.status === "withdrawn" ? (
        <Notice tone="warning">退会済みのオブザーバーのプロフィールは編集できません。</Notice>
      ) : (
        <Card>
          <AgentProfileForm profile={profile} admin={{ agentId: agent.id }} />
        </Card>
      )}
    </>
  );
}
