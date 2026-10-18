import Link from "next/link";
import { redirect } from "next/navigation";

import { LinkButton, Notice } from "@/components/ui";
import { getViewer } from "@/lib/auth/viewer";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { MyAgentApplication } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * 代理店登録の案内 (旧: 代理店登録フォーム)。
 *
 * 代理店は紹介リンクの登録フォームから申し込み、運営 (super_admin) の承認でだけ作られる。
 * このページでは代理店を作らない。ログイン中なら本人の申請状況を中立的な文面だけで表示する
 * (却下の理由・招待元は表示しない)。旧来の招待URL (?invite=) は発行元の登録フォームへ案内する。
 */
export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ invite?: string }>;
}) {
  const { invite } = await searchParams;
  const viewer = await getViewer();

  if (viewer.agent?.status === "active") {
    redirect("/agent");
  }

  const supabase = await createSupabaseServerClient();

  let registerHref: string | null = null;
  if (invite) {
    const { data } = await supabase.rpc("treemerce_resolve_invitation", { p_code: invite });
    const resolved = data as { valid?: boolean; inviter_public_id?: string } | null;
    if (resolved?.valid && resolved.inviter_public_id) {
      registerHref = `/register/${encodeURIComponent(resolved.inviter_public_id)}`;
    }
  }

  let application: MyAgentApplication | null = null;
  if (viewer.userId) {
    const { data } = await supabase.rpc("treemerce_my_agent_application");
    application = (data as MyAgentApplication | null) ?? null;
  }

  return (
    <div className="flex flex-1 items-center justify-center bg-app-bg px-5 py-16">
      <div className="w-full max-w-md space-y-4">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="text-[26px] font-bold tracking-tight text-text-primary">代理店登録について</h1>

        {viewer.agent ? (
          <Notice tone="warning">
            現在のアカウント状態は「{AGENT_STATUS_LABELS[viewer.agent.status]}」です。
            詳しくは運営事務局までお問い合わせください。
          </Notice>
        ) : application && application.state !== "none" && application.message ? (
          <Notice tone="info">{application.message}</Notice>
        ) : null}

        <div className="space-y-4 rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
          <p className="text-[14px] leading-7 text-text-primary">
            代理店登録は、代理店から受け取った紹介リンクの登録フォームからお申し込みいただけます。
            フォームで「代理店登録も申し込む」と「代理店規約に同意する」にチェックしてお申し込みください。
            運営が確認したうえで、代理店としてご利用いただけるようになります。
          </p>
          {registerHref ? (
            <LinkButton href={registerHref}>登録フォームへ進む</LinkButton>
          ) : (
            <p className="text-[13px] leading-6 text-text-secondary">
              紹介リンクがお手元にない場合は、紹介を受けた代理店または運営事務局までお問い合わせください。
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
