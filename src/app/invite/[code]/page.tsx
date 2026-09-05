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
    <div className="flex flex-1 items-center justify-center bg-zinc-50 px-6 py-16 dark:bg-zinc-950">
      <div className="w-full max-w-md space-y-5">
        <Link href="/" className="font-mono text-xs tracking-widest text-zinc-500">
          TREEMERCE
        </Link>

        {resolved?.valid ? (
          <>
            <h1 className="text-xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
              {resolved.inviter_display_name} さんからの招待
            </h1>
            <Notice tone="info">
              この招待URLから登録すると、招待元は{" "}
              <strong>{resolved.inviter_display_name}</strong> に確定します。
              招待元は1代理店につき1つだけで、一度確定すると変更できません。
              なお招待元は代理店の登録経路を表すもので、顧客の担当代理店とは別のデータです。
            </Notice>
            <LinkButton href={`/onboarding?invite=${encodeURIComponent(code)}`}>
              この招待で登録を進める
            </LinkButton>
          </>
        ) : (
          <>
            <h1 className="text-xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
              招待URLを利用できません
            </h1>
            <Notice tone="warning">
              {REASONS[resolved?.reason ?? ""] ?? "この招待URLは利用できません。"}
            </Notice>
            <LinkButton href="/onboarding" variant="secondary">
              招待元なしで登録する
            </LinkButton>
          </>
        )}
      </div>
    </div>
  );
}
