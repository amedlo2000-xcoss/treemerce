import type { Metadata } from "next";
import Link from "next/link";

import { formatDate } from "@/components/ui";
import type { AgentTerms } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "オブザーバー規約 | TREEMERCE" };

/**
 * 代理店規約 (公開ページ)。現行の版を表示する。版の公開は DB 管理者が行う (0027)。
 * 規約が未登録の間は「準備中」と表示し、登録フォームでも代理店のお申し込みを受け付けない。
 */
export default async function AgentTermsPage() {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("treemerce_current_agent_terms");
  const terms = (data as AgentTerms | null) ?? { available: false };

  return (
    <div className="flex flex-1 justify-center bg-app-bg px-4 py-10 md:py-14">
      <div className="w-full max-w-2xl space-y-5">
        <Link href="/" className="font-mono text-[11px] tracking-widest text-text-secondary">
          TREEMERCE
        </Link>
        <h1 className="text-[24px] font-bold tracking-tight text-text-primary">
          {terms.available ? terms.title : "オブザーバー規約"}
        </h1>

        <section className="rounded-[20px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] md:p-6">
          {terms.available ? (
            <>
              <p className="mb-4 text-[13px] text-text-secondary">
                第 {terms.version} 版 (公開日 {formatDate(terms.published_at)})
              </p>
              <div className="whitespace-pre-wrap break-words text-[14px] leading-7 text-text-primary">
                {terms.body}
              </div>
            </>
          ) : (
            <p className="text-[14px] leading-6 text-text-secondary">オブザーバー規約は現在準備中です。</p>
          )}
        </section>
      </div>
    </div>
  );
}
