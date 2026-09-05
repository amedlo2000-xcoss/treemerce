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
    <div className="flex flex-1 justify-center bg-zinc-50 px-6 py-16 dark:bg-zinc-950">
      <div className="w-full max-w-md space-y-5">
        <Link href="/" className="font-mono text-xs tracking-widest text-zinc-500">
          TREEMERCE
        </Link>
        <div>
          <h1 className="text-xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
            商品購入者登録
          </h1>
          <p className="mt-1.5 text-sm text-zinc-600 dark:text-zinc-400">
            担当代理店: {agent.display_name}
            <span className="ml-2 font-mono text-xs text-zinc-400">{agent.public_id}</span>
          </p>
        </div>

        <div className="rounded-xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-900">
          <CustomerRegisterForm agentPublicId={agentPublicId} />
        </div>
      </div>
    </div>
  );
}
