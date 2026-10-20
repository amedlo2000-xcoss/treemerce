import { notFound } from "next/navigation";

import { SubmissionForm } from "@/app/agent/submissions/SubmissionForm";
import { BackLink, Card, Mono, Notice, PageHeader } from "@/components/ui";
import { UUID } from "@/lib/api/submission-input";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { loadCatalogCategories } from "@/lib/catalog-categories";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { AgentRow } from "@/lib/domain/types";

/**
 * 持込み申請の代行作成 (super_admin 専用, 0021)。
 * 代理店から伺った内容で、その代理店の名義の下書きを作る。承認すると持込み元はこの代理店になり、
 * 変更できない。代行の申請は代理店本人のマイページでは閲覧のみ。
 */
export default async function AdminProxySubmissionNewPage({ params }: { params: Promise<{ agentId: string }> }) {
  const { agentId } = await params;
  if (!UUID.test(agentId)) notFound();
  const { supabase } = await requireSuperAdminPage(`/admin/agents/${agentId}/submissions/new`);

  const { data: agentData } = await supabase
    .from("agents")
    .select("id, public_id, display_name, status")
    .eq("id", agentId)
    .maybeSingle();
  const agent = agentData as Pick<AgentRow, "id" | "public_id" | "display_name" | "status"> | null;
  if (!agent) notFound();
  const categories = await loadCatalogCategories(supabase);

  return (
    <>
      <BackLink href={`/admin/agents/${agent.id}`}>オブザーバー詳細</BackLink>
      <PageHeader
        title="持込み申請を代行で作成"
        description="オブザーバーから伺った商品を、そのオブザーバーの名義で申請します。下書き保存のあとに画像を追加し、申請・審査へ進めます。"
      />

      <div className="rounded-[20px] border-2 border-brand bg-brand-soft px-5 py-4">
        <p className="text-[12px] font-semibold text-text-secondary">名義のオブザーバー (持込み元になります)</p>
        <p className="mt-1 text-[20px] font-bold text-text-primary">{agent.display_name}</p>
        <p className="mt-0.5 text-[13px] text-text-secondary">
          <Mono>{agent.public_id}</Mono>・{AGENT_STATUS_LABELS[agent.status] ?? agent.status}
        </p>
      </div>

      {agent.status !== "active" ? (
        <Notice tone="warning">稼働中のオブザーバーのみ申請を代行できます。</Notice>
      ) : (
        <>
          <Notice tone="warning">
            承認すると持込み元はこのオブザーバーとして記録され、あとから変更できません。名義のオブザーバーが正しいか確認してください。
            この申請はオブザーバー本人のマイページに「運営が代行作成」として表示されます (本人は閲覧のみ)。
          </Notice>
          <Card>
            <SubmissionForm
              categories={categories}
              proxy={{ agentId: agent.id, agentLabel: `${agent.public_id} ${agent.display_name}` }}
            />
          </Card>
        </>
      )}
    </>
  );
}
