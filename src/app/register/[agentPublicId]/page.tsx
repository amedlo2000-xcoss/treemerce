import Link from "next/link";
import { notFound } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AgentTerms, MyAgentApplication } from "@/lib/domain/types";

import { CustomerRegisterForm } from "./CustomerRegisterForm";

/**
 * 紹介リンクからの登録フォーム (公開ページ)。
 * 登録した人は全員「会員 (購入者)」になり、「代理店登録も申し込む」「代理店規約に同意する」の
 * 両方にチェックした人だけ代理店申請になる。申し込む場合はログイン (メール確認済み) が必要。
 * 代理店規約が未登録の間は「準備中」と表示し、申し込みのチェックは出さない。
 */
export default async function CustomerRegisterPage({
  params,
  searchParams,
}: {
  params: Promise<{ agentPublicId: string }>;
  searchParams: Promise<{ apply?: string }>;
}) {
  const { agentPublicId } = await params;
  const { apply } = await searchParams;
  const supabase = await createSupabaseServerClient();

  const [{ data }, { data: termsData }, { data: userData }] = await Promise.all([
    supabase.rpc("treemerce_agent_public_profile", { p_public_id: agentPublicId }),
    supabase.rpc("treemerce_current_agent_terms"),
    supabase.auth.getUser(),
  ]);
  const agent = data as { found: boolean; public_id?: string; display_name?: string } | null;
  if (!agent?.found) notFound();

  const terms = (termsData as AgentTerms | null) ?? { available: false };
  const user = userData.user;

  // ログイン中なら、本人の申請状況 (中立的な文面のみ) と代理店かどうかだけを見る
  let application: MyAgentApplication | null = null;
  let isAgent = false;
  if (user) {
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
        <p className="text-[13px] text-text-secondary">
          担当窓口: {agent.display_name}
          <span className="ml-2 font-mono text-[11px]">{agent.public_id}</span>
        </p>

        <div className="rounded-[24px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] sm:p-6">
          <CustomerRegisterForm
            agentPublicId={agentPublicId}
            terms={terms.available ? { version: terms.version, title: terms.title } : null}
            account={user ? { email: user.email ?? null, confirmed: Boolean(user.email_confirmed_at) } : null}
            application={application}
            isAgent={isAgent}
            resumeApply={apply === "1"}
          />
        </div>
      </div>
    </div>
  );
}
