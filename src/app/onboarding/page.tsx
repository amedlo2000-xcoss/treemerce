import Link from "next/link";
import { redirect } from "next/navigation";

import { Notice } from "@/components/ui";
import { getViewer } from "@/lib/auth/viewer";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";

import { OnboardingForm } from "./OnboardingForm";

export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ invite?: string; status?: string }>;
}) {
  const { invite } = await searchParams;
  const viewer = await getViewer();

  if (!viewer.userId) {
    const next = invite ? `/onboarding?invite=${encodeURIComponent(invite)}` : "/onboarding";
    redirect(`/login?next=${encodeURIComponent(next)}`);
  }

  // 既に稼働中の代理店ならダッシュボードへ
  if (viewer.agent?.status === "active" && (!invite || viewer.agent.invited_by)) {
    redirect("/agent");
  }

  let inviterName: string | null = null;
  if (invite) {
    const supabase = await createSupabaseServerClient();
    const { data } = await supabase.rpc("treemerce_resolve_invitation", { p_code: invite });
    const resolved = data as { valid?: boolean; inviter_display_name?: string } | null;
    if (resolved?.valid) inviterName = resolved.inviter_display_name ?? null;
  }

  const lockedInviter = Boolean(viewer.agent?.invited_by);

  return (
    <div className="flex flex-1 items-center justify-center bg-zinc-50 px-6 py-16 dark:bg-zinc-950">
      <div className="w-full max-w-md space-y-4">
        <Link href="/" className="font-mono text-xs tracking-widest text-zinc-500">
          TREEMERCE
        </Link>
        <h1 className="text-xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
          代理店登録
        </h1>

        {viewer.agent && viewer.agent.status !== "active" ? (
          <Notice tone="warning">
            現在のアカウント状態は「{AGENT_STATUS_LABELS[viewer.agent.status]}」です。
            利用開始には運営による承認が必要です。
          </Notice>
        ) : null}

        {invite && !inviterName ? (
          <Notice tone="warning">
            招待コードが無効か、有効期限が切れています。招待元なしで登録することもできます。
          </Notice>
        ) : null}

        <div className="rounded-xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-900">
          <OnboardingForm
            defaultEmail={viewer.email ?? ""}
            invitationCode={inviterName ? (invite ?? null) : null}
            inviterName={inviterName}
            lockedInviter={lockedInviter}
          />
        </div>
      </div>
    </div>
  );
}
