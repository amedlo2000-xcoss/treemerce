import Link from "next/link";
import { redirect } from "next/navigation";

import { LinkButton, Notice } from "@/components/ui";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const REASONS: Record<string, string> = {
  not_found: "招待コードが見つかりません。",
  inactive: "この招待URLは無効化されています。",
  expired: "この招待URLは有効期限が切れています。",
  exhausted: "この招待URLは利用上限に達しています。",
  inviter_unavailable: "招待元の代理店が現在ご利用いただけません。",
};

/**
 * 旧来の代理店招待URL。有効なら発行した代理店の登録フォーム (/register/{公開ID}) へ転送する。
 * 代理店のお申し込みはそのフォームで行い、招待元はそのリンクの代理店として申請時点で固定される。
 */
export default async function InvitePage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = await createSupabaseServerClient();

  const { data } = await supabase.rpc("treemerce_resolve_invitation", { p_code: code });
  const resolved = data as { valid: boolean; reason?: string; inviter_public_id?: string } | null;

  if (resolved?.valid && resolved.inviter_public_id) {
    redirect(`/register/${encodeURIComponent(resolved.inviter_public_id)}`);
  }

  return (
    <div className="flex flex-1 items-center justify-center bg-app-bg px-5 py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="mt-2 mb-6 text-[22px] font-bold leading-tight tracking-tight text-text-primary">
          招待URLを利用できません
        </h1>
        <div className="space-y-5 rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
          <Notice tone="warning">
            {REASONS[resolved?.reason ?? ""] ?? "この招待URLは利用できません。"}
          </Notice>
          <LinkButton href="/onboarding" variant="secondary">
            代理店登録について
          </LinkButton>
        </div>
      </div>
    </div>
  );
}
