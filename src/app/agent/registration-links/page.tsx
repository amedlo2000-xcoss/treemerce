import { IssueLinkForm, RevokeLinkButton } from "@/components/RegistrationLinkActions";
import { MobilePageHeader, SectionLabel, Surface } from "@/components/mobile/primitives";
import { Badge, EmptyState, Notice, formatDateTime } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { REGISTRATION_LINK_STATE_BADGE, REGISTRATION_LINK_STATE_LABELS } from "@/lib/domain/enums";
import type { MyRegistrationLink } from "@/lib/domain/types";

const ENDPOINT = "/api/agent/registration-links";

/**
 * 代理店登録リンクの発行 (代理店本人)。
 * このリンクから申し込んだ人は、運営が承認すると「あなたの紹介で登録した代理店」になる
 * (紐づけ先 = 発行した本人。DB 側で固定され、申し込み後・承認時にも変更できない)。
 * 一覧・無効化できるのは自分が発行したリンクだけ。申し込んだ人の氏名・連絡先・申し込み内容は表示しない。
 */
export default async function AgentRegistrationLinksPage() {
  const { supabase, agent } = await requireAgentPage("/agent/registration-links");

  const { data, error } = await supabase.rpc("treemerce_my_registration_links");
  if (error) throw new Error("オブザーバー登録リンクを読み込めませんでした。");
  const links = (data ?? []) as MyRegistrationLink[];

  return (
    <>
      <MobilePageHeader
        title="オブザーバー登録リンクの発行"
        description="オブザーバーとして登録したい人に渡すリンクです。リンクから申し込み、運営が承認すると、あなたの紹介で登録したオブザーバーになります。"
      />

      <Notice tone="info">
        紹介者は「{agent.display_name}さん ({agent.public_id})」として申し込みフォームに表示され、
        お申し込みの時点で確定します (あとから変更できません)。このリンクでは会員 (購入者) の登録は行いません。
        申し込んだ方の内容や連絡先は、運営だけが確認します。
      </Notice>

      <div className="space-y-2">
        <SectionLabel>リンクを発行</SectionLabel>
        <Surface>
          <p className="mb-3 text-[13px] leading-5 text-text-secondary">
            有効期限と使用回数の上限は任意です。使用回数は、受け付けたお申し込みの件数で数えます。
          </p>
          <IssueLinkForm endpoint={ENDPOINT} />
        </Surface>
      </div>

      <div className="space-y-2">
        <SectionLabel>発行したリンク ({links.length})</SectionLabel>
        {links.length === 0 ? (
          <EmptyState title="発行したリンクはありません" />
        ) : (
          <div className="space-y-3">
            {links.map((l) => (
              <Surface key={l.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0 space-y-1">
                    <p className="truncate text-[15px] font-semibold text-text-primary">{l.note ?? "(メモなし)"}</p>
                    <p className="text-[12px] text-text-secondary">発行 {formatDateTime(l.created_at)}</p>
                  </div>
                  <Badge tone={REGISTRATION_LINK_STATE_BADGE[l.state] ?? "neutral"}>
                    {REGISTRATION_LINK_STATE_LABELS[l.state] ?? l.state}
                  </Badge>
                </div>
                <dl className="mt-3 grid grid-cols-2 gap-2 text-[13px]">
                  <div>
                    <dt className="text-text-secondary">使用回数</dt>
                    <dd className="font-medium tabular-nums text-text-primary">
                      {l.used_count}
                      {l.max_uses != null ? ` / ${l.max_uses}` : " (上限なし)"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-text-secondary">有効期限</dt>
                    <dd className="font-medium text-text-primary">
                      {l.expires_at ? formatDateTime(l.expires_at) : "なし"}
                    </dd>
                  </div>
                </dl>
                {l.status === "active" ? (
                  <div className="mt-3">
                    <RevokeLinkButton endpoint={ENDPOINT} linkId={l.id} />
                  </div>
                ) : null}
              </Surface>
            ))}
          </div>
        )}
        <p className="px-1 text-[12px] leading-5 text-text-secondary">
          リンクの URL は発行した直後にだけ表示されます。紛失した場合は無効化して、新しく発行してください。
        </p>
      </div>
    </>
  );
}
