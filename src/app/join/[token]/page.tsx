import type { Metadata } from "next";
import Link from "next/link";

import { LinkButton, Notice } from "@/components/ui";
import type { AgentTerms, RegistrationLinkResolution } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { JoinForm } from "./JoinForm";

export const metadata: Metadata = { title: "オブザーバー登録のお申し込み | TREEMERCE", robots: { index: false } };

const REASONS: Record<string, string> = {
  not_found: "このオブザーバー登録リンクは見つかりません。",
  expired: "このオブザーバー登録リンクは有効期限が切れています。",
  exhausted: "このオブザーバー登録リンクは利用の上限に達しています。",
  revoked: "このオブザーバー登録リンクは無効化されています。",
  unavailable: "このオブザーバー登録リンクは現在ご利用いただけません。",
};

/**
 * 代理店登録リンク (公開ページ)。運営・代理店のどちらが発行したリンクも同じフォームを使う。
 * 一番上に紹介者 (リンクを発行した代理店。運営のリンクは「運営からの直接登録」) を表示する。
 * 紹介者は DB がリンクから決めて返す値で、申し込み時点で固定される (承認時にも変更できない)。
 * 会員登録は行わない。
 */
export default async function JoinPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const supabase = await createSupabaseServerClient();

  const [{ data: linkData }, { data: termsData }] = await Promise.all([
    supabase.rpc("treemerce_resolve_registration_link", { p_token: token }),
    supabase.rpc("treemerce_current_agent_terms"),
  ]);
  const link = linkData as RegistrationLinkResolution | null;
  const terms = (termsData as AgentTerms | null) ?? { available: false };

  return (
    <div className="flex flex-1 justify-center bg-app-bg px-5 py-10 sm:py-16">
      <div className="w-full max-w-md space-y-5">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="text-[24px] font-bold tracking-tight text-text-primary">オブザーバー登録のお申し込み</h1>

        {!link?.valid ? (
          <div className="space-y-4 rounded-[24px] border border-border-soft bg-surface p-6 shadow-[var(--shadow-card)]">
            <Notice tone="warning">
              {REASONS[link?.reason ?? ""] ?? "このオブザーバー登録リンクは利用できません。"}
            </Notice>
            <p className="text-[13px] leading-6 text-text-secondary">
              お手数ですが、リンクを受け取ったオブザーバーまたは運営事務局までお問い合わせください。
            </p>
            <LinkButton href="/onboarding" variant="secondary">
              オブザーバー登録について
            </LinkButton>
          </div>
        ) : (
          <>
            <div className="rounded-[20px] border border-brand/30 bg-brand-soft px-5 py-4">
              <p className="text-[12px] font-medium text-text-secondary">紹介者</p>
              <p className="mt-0.5 text-[17px] font-bold leading-7 text-text-primary">
                {link.inviter ? (
                  <>
                    {link.inviter.display_name}さん
                    <span className="ml-1 font-mono text-[14px] font-semibold text-text-secondary">
                      ({link.inviter.public_id})
                    </span>
                  </>
                ) : (
                  "運営からの直接登録"
                )}
              </p>
              <p className="mt-1 text-[12px] leading-5 text-text-secondary">
                {link.inviter
                  ? "承認されると、このオブザーバーの紹介で登録したオブザーバーになります。紹介者はあとから変更できません。"
                  : "承認されると、運営直下のオブザーバーになります。紹介者はあとから変更できません。"}
              </p>
            </div>

            <div className="rounded-[24px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] sm:p-6">
              <JoinForm
                token={token}
                terms={terms.available ? { version: terms.version, title: terms.title } : null}
              />
            </div>
          </>
        )}
      </div>
    </div>
  );
}
