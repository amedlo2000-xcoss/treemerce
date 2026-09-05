import { headers } from "next/headers";

import { Badge, Card, DataTable, EmptyState, Notice, PageHeader, formatDate } from "@/components/ui";
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
      <PageHeader
        title="招待URL"
        description="代理店の招待URLと、商品購入者の登録URLをここから取得できます。"
      />

      <Notice tone="warning">
        代理店の招待URL (登録経路) と、購入者の登録URL (担当代理店) は別の仕組みです。
        どちらか一方を使っても、もう一方が自動的に変わることはありません。
      </Notice>

      <Card
        title="商品購入者の登録URL"
        description="このURLから登録された購入者は、あなたが担当代理店として確定します。"
      >
        <CopyField label="登録URL" value={`${origin}/register/${agent.public_id}`} />
      </Card>

      <Card title="代理店の招待URLを発行">
        <InvitationPanel origin={origin} />
      </Card>

      {!invitations || invitations.length === 0 ? (
        <EmptyState title="発行済みの招待URLはありません" />
      ) : (
        <DataTable headers={["招待URL", "状態", "利用数", "メモ", "発行日"]}>
          {invitations.map((inv) => (
            <tr key={inv.id} className="bg-white dark:bg-zinc-950">
              <td className="px-4 py-3">
                <CopyField label="" value={`${origin}/invite/${inv.code}`} />
              </td>
              <td className="px-4 py-3">
                <Badge tone={inv.status === "active" ? "green" : "neutral"}>
                  {inv.status === "active" ? "有効" : "無効"}
                </Badge>
              </td>
              <td className="px-4 py-3 text-sm tabular-nums text-zinc-700 dark:text-zinc-300">
                {inv.used_count}
                {inv.max_uses ? ` / ${inv.max_uses}` : ""}
              </td>
              <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                {inv.note ?? "—"}
              </td>
              <td className="px-4 py-3 text-xs text-zinc-600 dark:text-zinc-400">
                {formatDate(inv.created_at)}
              </td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
