import type { Metadata } from "next";
import Link from "next/link";

import { LinkButton, Notice } from "@/components/ui";
import type { AgentTerms, MyAgentApplication } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { JoinForm } from "./JoinForm";

export const metadata: Metadata = { title: "代理店登録のお申し込み | TREEMERCE", robots: { index: false } };

const REASONS: Record<string, string> = {
  not_found: "この代理店登録リンクは見つかりません。",
  expired: "この代理店登録リンクは有効期限が切れています。",
  exhausted: "この代理店登録リンクは利用の上限に達しています。",
  revoked: "この代理店登録リンクは無効化されています。",
};

/**
 * 運営の代理店登録リンク (公開ページ)。代理店の申し込みだけを受け付け、会員登録は行わない。
 * 招待元はなし (運営からの直接登録)。ログイン (メール確認済み) と3つの同意チェックは紹介リンクと同じ。
 */
export default async function JoinPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const supabase = await createSupabaseServerClient();

  const [{ data: linkData }, { data: termsData }, { data: userData }] = await Promise.all([
    supabase.rpc("treemerce_resolve_registration_link", { p_token: token }),
    supabase.rpc("treemerce_current_agent_terms"),
    supabase.auth.getUser(),
  ]);
  const link = linkData as { valid: boolean; reason?: string } | null;
  const terms = (termsData as AgentTerms | null) ?? { available: false };
  const user = userData.user;

  let application: MyAgentApplication | null = null;
  let isAgent = false;
  if (user && link?.valid) {
    const [{ data: appData }, { data: agentRow }] = await Promise.all([
      supabase.rpc("treemerce_my_agent_application"),
      supabase.from("agents").select("id").eq("auth_user_id", user.id).maybeSingle(),
    ]);
    application = (appData as MyAgentApplication | null) ?? null;
    isAgent = Boolean(agentRow);
  }

  return (
    <div className="flex flex-1 justify-center bg-app-bg px-5 py-10 sm:py-16">
      <div className="w-full max-w-md space-y-5">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="text-[24px] font-bold tracking-tight text-text-primary">代理店登録のお申し込み</h1>

        {!link?.valid ? (
          <div className="space-y-4 rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
            <Notice tone="warning">
              {REASONS[link?.reason ?? ""] ?? "この代理店登録リンクは利用できません。"}
            </Notice>
            <p className="text-[13px] leading-6 text-text-secondary">
              お手数ですが、リンクを受け取った運営事務局までお問い合わせください。
            </p>
            <LinkButton href="/onboarding" variant="secondary">
              代理店登録について
            </LinkButton>
          </div>
        ) : (
          <div className="rounded-[24px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] sm:p-6">
            <JoinForm
              token={token}
              terms={terms.available ? { version: terms.version, title: terms.title } : null}
              account={user ? { email: user.email ?? null, confirmed: Boolean(user.email_confirmed_at) } : null}
              application={application}
              isAgent={isAgent}
            />
          </div>
        )}
      </div>
    </div>
  );
}
