import Link from "next/link";
import { notFound } from "next/navigation";

import {
  AGENT_STATUS_TONE,
  BackLink,
  Badge,
  Card,
  DetailList,
  DetailRow,
  EmptyState,
  Mono,
  formatDate,
} from "@/components/ui";
import { ProfileHero, StatTile } from "@/components/mobile/primitives";
import { AgentProfileDetails } from "@/components/AgentProfileDetails";
import { CommerceMapTree } from "@/components/CommerceMapTree";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { AgentProfile, AgentRow, CommerceMap } from "@/lib/domain/types";

import { AgentStatusForm } from "./AgentStatusForm";

/**
 * 統括管理: 代理店詳細。super_admin 専用 (requireSuperAdminPage)。
 * 傘下ツリー・担当顧客の実データは既存の商流マップRPC (treemerce_commerce_map) を
 * この代理店をrootにして呼び出すことで得る。ADMIN として呼ぶため、
 * 傘下の他代理店が担当する顧客も匿名化されずに表示される (絶対原則5の対象は一般代理店のみ)。
 */
export default async function AdminAgentDetailPage({
  params,
}: {
  params: Promise<{ agentId: string }>;
}) {
  const { agentId } = await params;
  const { supabase } = await requireSuperAdminPage(`/admin/agents/${agentId}`);

  const { data: agentData } = await supabase
    .from("agents")
    .select("*")
    .eq("id", agentId)
    .maybeSingle();

  const agent = agentData as AgentRow | null;
  if (!agent) notFound();

  const [{ data: mapData }, { data: inviterData }, { data: profileData }] = await Promise.all([
    supabase.rpc("treemerce_commerce_map", { p_root_agent_id: agentId }),
    agent.invited_by
      ? supabase
          .from("agents")
          .select("id, public_id, display_name, status")
          .eq("id", agent.invited_by)
          .maybeSingle()
      : Promise.resolve({ data: null }),
    // 0016: 事業プロフィールは super_admin 用 RPC でのみ取得できる
    supabase.rpc("treemerce_admin_get_agent_profile", { p_agent_id: agentId }),
  ]);

  const map = mapData as CommerceMap;
  const profile = (profileData as AgentProfile | null) ?? null;
  const inviter = inviterData as {
    id: string;
    public_id: string;
    display_name: string;
    status: string;
  } | null;

  const directInvitees = map.agents.filter((a) => a.invited_by === agentId);
  const rootNode = map.agents.find((a) => a.agent_id === agentId);

  return (
    <>
      <BackLink href="/admin/agents">代理店一覧</BackLink>

      <ProfileHero
        name={agent.display_name}
        subtitle={agent.public_id}
        mono
        pills={
          <Badge tone={AGENT_STATUS_TONE[agent.status] ?? "neutral"}>
            {AGENT_STATUS_LABELS[agent.status] ?? agent.status}
          </Badge>
        }
        meta={
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <StatTile label="登録日" value={formatDate(agent.registered_at)} />
            <StatTile label="直接の担当顧客" value={`${rootNode?.customer_count ?? 0}件`} />
            <StatTile label="直接の招待" value={`${directInvitees.length}件`} />
            <StatTile label="傘下代理店 (全体)" value={`${Math.max(map.agents.length - 1, 0)}件`} />
          </div>
        }
      />

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-6 lg:space-y-0">
        <div className="space-y-5">
          <Card title="基本情報">
            <DetailList>
              <DetailRow label="代理店ID" value={agent.public_id} mono />
              <DetailRow label="法人名" value={agent.legal_name ?? "—"} />
              <DetailRow label="メール" value={agent.email} />
              <DetailRow label="電話番号" value={agent.phone ?? "—"} />
              <DetailRow label="都道府県" value={agent.prefecture ?? "—"} />
            </DetailList>
          </Card>

          <Card
            title="事業プロフィール"
            description={
              profile?.updated_at
                ? `代理店本人が入力した内容です (最終更新 ${formatDate(profile.updated_at)})。super_admin のみ閲覧できます。`
                : "代理店本人が入力する項目です。super_admin のみ閲覧できます。"
            }
          >
            {!profile ? (
              <p className="text-[13px] text-text-secondary">プロフィールを読み込めませんでした。</p>
            ) : profile.found ? (
              <AgentProfileDetails profile={profile} />
            ) : (
              <p className="text-[13px] text-text-secondary">まだ入力されていません。</p>
            )}
            <Link
              href={`/admin/submissions?agent=${agent.id}`}
              className="mt-3 inline-block text-[13px] font-semibold text-brand hover:underline"
            >
              この代理店の持込み申請を見る
            </Link>
          </Card>

          <Card
            title="招待経緯 (登録経路)"
            description="登録経路 (invited_by) は購入者の担当代理店とは別データです。"
          >
            <DetailList>
              <DetailRow
                label="招待元"
                value={
                  inviter ? (
                    <Link
                      href={`/admin/agents/${inviter.id}`}
                      className="font-medium text-brand hover:underline"
                    >
                      <span className="font-mono text-[12px]">{inviter.public_id}</span>{" "}
                      {inviter.display_name}
                    </Link>
                  ) : (
                    <span className="text-text-secondary">直接登録 (招待元なし)</span>
                  )
                }
              />
            </DetailList>

            <p className="mb-2 mt-4 text-[12px] font-semibold text-text-secondary">
              この代理店の招待で登録した代理店 ({directInvitees.length}件)
            </p>
            {directInvitees.length === 0 ? (
              <p className="text-[13px] text-text-secondary">まだいません。</p>
            ) : (
              <ul className="divide-y divide-border-soft rounded-xl border border-border-soft">
                {directInvitees.map((a) => (
                  <li key={a.agent_id}>
                    <Link
                      href={`/admin/agents/${a.agent_id}`}
                      className="flex items-center gap-2 px-3 py-2.5 text-[14px] transition-colors hover:bg-surface-muted"
                    >
                      <Mono>{a.public_id}</Mono>
                      <span className="font-medium text-text-primary">{a.display_name}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card
            title="ステータスを変更する"
            description="この操作は super_admin のみ実行できます。登録経路 (invited_by) は変更されません。"
          >
            <AgentStatusForm agentId={agent.id} currentStatus={agent.status} />
          </Card>
        </div>

        <Card
          title="傘下ツリー・担当顧客"
          description="この代理店を根とする部分木です。super_admin のため、傘下の他代理店が担当する顧客の実データも表示されます。"
        >
          {map.agents.length === 0 ? (
            <EmptyState title="データがありません" />
          ) : (
            <CommerceMapTree map={map} />
          )}
        </Card>
      </div>
    </>
  );
}
