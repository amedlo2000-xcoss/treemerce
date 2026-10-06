import Link from "next/link";

import { LinkButton, Notice } from "@/components/ui";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const REASONS: Record<string, string> = {
  not_found: "招待コードが見つかりません。",
  inactive: "この招待URLは無効化されています。",
  expired: "この招待URLは有効期限が切れています。",
  exhausted: "この招待URLは利用上限に達しています。",
  inviter_unavailable: "招待元の代理店が現在ご利用いただけません。",
};

export default async function InvitePage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = await createSupabaseServerClient();

  const { data } = await supabase.rpc("treemerce_resolve_invitation", { p_code: code });
  const resolved = data as
    | { valid: boolean; reason?: string; inviter_display_name?: string; inviter_public_id?: string }
    | null;

  return (
    <div className="flex flex-1 items-center justify-center bg-app-bg px-5 py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>

        {resolved?.valid ? (
          <>
            <h1 className="mt-2 mb-6 text-[22px] font-bold leading-tight tracking-tight text-text-primary">
              {resolved.inviter_display_name} さんからの招待
            </h1>
            <div className="space-y-5 rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
              <Notice tone="info">
                この招待URLから登録すると、招待元は{" "}
                <strong>{resolved.inviter_display_name}</strong> に確定します。
                招待元は1代理店につき1つだけで、一度確定すると変更できません。
                なお招待元は代理店の登録経路を表すもので、顧客の担当代理店とは別のデータです。
              </Notice>
              <LinkButton href={`/onboarding?invite=${encodeURIComponent(code)}`}>
                この招待で登録を進める
              </LinkButton>
            </div>
          </>
        ) : (
          <>
            <h1 className="mt-2 mb-6 text-[22px] font-bold leading-tight tracking-tight text-text-primary">
              招待URLを利用できません
            </h1>
            <div className="space-y-5 rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
              <Notice tone="warning">
                {REASONS[resolved?.reason ?? ""] ?? "この招待URLは利用できません。"}
              </Notice>
              <LinkButton href="/onboarding" variant="secondary">
                招待元なしで登録する
              </LinkButton>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
