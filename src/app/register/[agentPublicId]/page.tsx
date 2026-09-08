import Link from "next/link";
import { notFound } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

import { CustomerRegisterForm } from "./CustomerRegisterForm";

/** 代理店の登録URL経由での商品購入者登録フォーム (公開ページ)。 */
export default async function CustomerRegisterPage({
  params,
}: {
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;
  const supabase = await createSupabaseServerClient();

  const { data } = await supabase.rpc("treemerce_agent_public_profile", {
    p_public_id: agentPublicId,
  });
  const agent = data as { found: boolean; public_id?: string; display_name?: string } | null;

  if (!agent?.found) notFound();

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
          <CustomerRegisterForm agentPublicId={agentPublicId} />
        </div>
      </div>
    </div>
  );
}
