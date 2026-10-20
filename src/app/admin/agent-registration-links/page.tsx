import {
  Badge,
  Card,
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
import { REGISTRATION_LINK_STATE_BADGE, REGISTRATION_LINK_STATE_LABELS } from "@/lib/domain/enums";
import type { AdminRegistrationLink } from "@/lib/domain/types";

import { IssueLinkForm, RevokeLinkButton } from "@/components/RegistrationLinkActions";

const ENDPOINT = "/api/admin/agent-registration-links";

/**
 * 代理店登録リンク (super_admin 専用。RPC 側でも判定)。
 * ここで発行するリンクは紐づけ先なし (運営直下)。代理店がマイページで発行したリンク (紐づけ先 = 発行した代理店)
 * も一覧に出し、運営はどちらも無効化できる。リンクから届く申し込みは「代理店申請」の承認画面で審査する。
 * リンクの URL は発行の直後に一度だけ表示する (DB にはハッシュだけを保存しているため再表示できない)。
 */
export default async function AdminAgentRegistrationLinksPage() {
  const { supabase } = await requireSuperAdminPage("/admin/agent-registration-links");

  const { data, error } = await supabase.rpc("treemerce_admin_list_registration_links");
  if (error) throw new Error("オブザーバー登録リンクを読み込めませんでした。");
  const links = (data ?? []) as AdminRegistrationLink[];

  return (
    <>
      <PageHeader
        title="オブザーバー登録リンク"
        description="オブザーバー登録のお申し込みを受け付けるリンクです。ここで発行したリンクから申し込んだ人は、承認すると運営直下 (紹介者なし) のオブザーバーになります。オブザーバーがマイページで発行したリンクから申し込んだ人は、承認するとそのオブザーバーの紹介で登録したオブザーバーになります。どちらも会員登録は行いません。発行・無効化は監査ログに記録されます。"
      />

      <Card
        title="運営のリンクを発行 (紐づけ先なし・運営直下)"
        description="有効期限と使用回数の上限は任意です。使用回数は、申し込みを受け付けた件数で数えます (重複したお申し込みは数えません)。"
      >
        <IssueLinkForm endpoint={ENDPOINT} />
      </Card>

      <SectionTitle count={links.length}>発行済みのリンク</SectionTitle>

      {links.length === 0 ? (
        <EmptyState title="発行済みのリンクはありません" />
      ) : (
        <DataTable headers={["発行元 (紐づけ先)", "メモ", "状態", "使用回数", "有効期限", "申し込み", "発行日時", ""]}>
          {links.map((l) => (
            <tr key={l.id}>
              <td className={TD_STRONG}>
                {l.issuer ? (
                  <>
                    <div>{l.issuer.display_name}さん</div>
                    <Mono>{l.issuer.public_id}</Mono>
                  </>
                ) : (
                  "運営直下"
                )}
              </td>
              <td className={TD}>{l.note ?? "—"}</td>
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
              <td className={TD}>{l.status === "active" ? <RevokeLinkButton endpoint={ENDPOINT} linkId={l.id} /> : null}</td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
