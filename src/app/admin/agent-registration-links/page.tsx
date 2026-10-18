import {
  Badge,
  Card,
  DataTable,
  EmptyState,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDateTime,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { REGISTRATION_LINK_STATE_BADGE, REGISTRATION_LINK_STATE_LABELS } from "@/lib/domain/enums";
import type { AdminRegistrationLink } from "@/lib/domain/types";

import { IssueLinkForm, RevokeLinkButton } from "./LinkActions";

/**
 * 運営の代理店登録リンク (super_admin 専用。RPC 側でも判定)。
 * リンクから届く申し込みは「代理店申請」の承認画面で審査する。招待元はなし (運営からの直接登録)。
 * リンクの URL は発行の直後に一度だけ表示する (DB にはハッシュだけを保存しているため再表示できない)。
 */
export default async function AdminAgentRegistrationLinksPage() {
  const { supabase } = await requireSuperAdminPage("/admin/agent-registration-links");

  const { data, error } = await supabase.rpc("treemerce_admin_list_registration_links");
  if (error) throw new Error("代理店登録リンクを読み込めませんでした。");
  const links = (data ?? []) as AdminRegistrationLink[];

  return (
    <>
      <PageHeader
        title="代理店登録リンク"
        description="運営から代理店登録をご案内するためのリンクです。リンクから申し込んだ人は会員登録を行わず、承認すると招待元なし (運営からの直接登録) の代理店になります。発行・無効化は監査ログに記録されます。"
      />

      <Card
        title="リンクを発行"
        description="有効期限と使用回数の上限は任意です。使用回数は、申し込みを受け付けた件数で数えます (重複したお申し込みは数えません)。"
      >
        <IssueLinkForm />
      </Card>

      <SectionTitle count={links.length}>発行済みのリンク</SectionTitle>

      {links.length === 0 ? (
        <EmptyState title="発行済みのリンクはありません" />
      ) : (
        <DataTable headers={["メモ", "状態", "使用回数", "有効期限", "申し込み", "発行日時", ""]}>
          {links.map((l) => (
            <tr key={l.id}>
              <td className={TD_STRONG}>{l.note ?? "—"}</td>
              <td className={TD}>
                <Badge tone={REGISTRATION_LINK_STATE_BADGE[l.state] ?? "neutral"}>
                  {REGISTRATION_LINK_STATE_LABELS[l.state] ?? l.state}
                </Badge>
              </td>
              <td className={`${TD} tabular-nums`}>
                {l.used_count}
                {l.max_uses != null ? ` / ${l.max_uses}` : " (上限なし)"}
              </td>
              <td className={`${TD} whitespace-nowrap`}>{l.expires_at ? formatDateTime(l.expires_at) : "なし"}</td>
              <td className={`${TD} whitespace-nowrap tabular-nums`}>
                承認待ち {l.applications.pending} / 承認 {l.applications.approved} / 却下 {l.applications.rejected}
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(l.created_at)}</td>
              <td className={TD}>{l.status === "active" ? <RevokeLinkButton linkId={l.id} /> : null}</td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
