import { headers } from "next/headers";

import { Notice } from "@/components/ui";
import { MobilePageHeader, SectionLabel, Surface } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";

import { CopyField } from "./InvitationPanel";

/**
 * 紹介リンク。登録フォームは1つにまとめた (0027〜0028)。
 * 登録した人は全員あなたが担当の会員になり、代理店登録も申し込んだ人は運営の承認後に
 * あなたが招待元の代理店になる。以前に発行した代理店の招待URLは、この登録URLへ転送される。
 */
export default async function InvitationsPage() {
  const { agent } = await requireAgentPage("/agent/invitations");

  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "";
  const protocol = headerList.get("x-forwarded-proto") ?? "https";
  const origin = host ? `${protocol}://${host}` : "";

  return (
    <>
      <MobilePageHeader
        title="紹介リンク"
        description="会員 (購入者) の登録と代理店登録のお申し込みは、同じ登録URLから受け付けます。"
      />

      <Notice tone="warning">
        会員の担当代理店と、代理店の招待元 (登録経路) は別々に記録されます。
        どちらか一方が変わっても、もう一方が自動的に変わることはありません。
      </Notice>

      <div className="space-y-2">
        <SectionLabel>登録URL</SectionLabel>
        <Surface>
          <p className="mb-3 text-[13px] leading-5 text-text-secondary">
            このURLから登録した人は、あなたが担当代理店の会員として確定します。
            「代理店登録も申し込む」にチェックした人は、運営が承認すると、あなたが招待元の代理店になります
            (招待元はお申し込みの時点で確定し、変更できません)。
          </p>
          <CopyField label="登録URL" value={`${origin}/register/${agent.public_id}`} />
        </Surface>
      </div>

      <div className="space-y-2">
        <SectionLabel>ショップの紹介リンク</SectionLabel>
        <Surface>
          <p className="mb-3 text-[13px] leading-5 text-text-secondary">
            このリンクから初めて注文したお客様は、あなたが担当代理店として確定します。
            すでに担当代理店が決まっているお客様が注文した場合は、そのお客様の現在の担当代理店の注文になります。
          </p>
          <CopyField label="紹介リンク" value={`${origin}/shop/${agent.public_id}`} />
        </Surface>
      </div>

      <p className="px-1 text-[12px] leading-5 text-text-secondary">
        以前に発行した代理店の招待URLは、有効なものに限り、この登録URLへ転送されます。
      </p>
    </>
  );
}
