import { headers } from "next/headers";

import { Notice, formatDate } from "@/components/ui";
import { EmptyState, MobilePageHeader, SectionLabel, StatusPill, Surface } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";

import { CopyField, InvitationPanel } from "./InvitationPanel";

export default async function InvitationsPage() {
  const { supabase, agent } = await requireAgentPage("/agent/invitations");

  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "";
  const protocol = headerList.get("x-forwarded-proto") ?? "https";
  const origin = host ? `${protocol}://${host}` : "";

  const { data: invitations } = await supabase
    .from("agent_invitations")
    .select("id, code, status, used_count, max_uses, note, expires_at, created_at")
    .order("created_at", { ascending: false });

  return (
    <>
      <MobilePageHeader
        title="招待URL"
        description="代理店の招待URLと、商品購入者の登録URLをここから取得できます。"
      />

      <Notice tone="warning">
        代理店の招待URL (登録経路) と、購入者の登録URL (担当代理店) は別の仕組みです。
        どちらか一方を使っても、もう一方が自動的に変わることはありません。
      </Notice>

      <div className="space-y-2">
        <SectionLabel>商品購入者の登録URL</SectionLabel>
        <Surface>
          <p className="mb-3 text-[13px] leading-5 text-text-secondary">
            このURLから登録された購入者は、あなたが担当代理店として確定します。
          </p>
          <CopyField label="登録URL" value={`${origin}/register/${agent.public_id}`} />
        </Surface>
      </div>

      <div className="space-y-2">
        <SectionLabel>代理店の招待URLを発行</SectionLabel>
        <Surface>
          <InvitationPanel origin={origin} />
        </Surface>
      </div>

      <div className="space-y-2">
        <SectionLabel>発行済みの招待URL</SectionLabel>
        {!invitations || invitations.length === 0 ? (
          <Surface>
            <EmptyState title="発行済みの招待URLはありません" />
          </Surface>
        ) : (
          <Surface padded={false} className="divide-y divide-border-soft px-4">
            {invitations.map((inv) => (
              <div key={inv.id} className="space-y-2 py-4">
                <div className="flex flex-wrap items-center gap-2">
                  <StatusPill tone={inv.status === "active" ? "success" : "neutral"}>
                    {inv.status === "active" ? "有効" : "無効"}
                  </StatusPill>
                  <span className="text-[13px] tabular-nums text-text-secondary">
                    利用数 {inv.used_count}
                    {inv.max_uses ? ` / ${inv.max_uses}` : ""}
                  </span>
                  <span className="text-[12px] text-text-secondary">{formatDate(inv.created_at)}</span>
                </div>
                <CopyField label="URL" value={`${origin}/invite/${inv.code}`} />
                {inv.note ? <p className="text-[13px] text-text-secondary">{inv.note}</p> : null}
              </div>
            ))}
          </Surface>
        )}
      </div>
    </>
  );
}
