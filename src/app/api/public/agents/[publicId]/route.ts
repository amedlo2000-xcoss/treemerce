import { failFromPostgrest, getApiContext, ok } from "@/lib/api/http";

/** 顧客登録フォーム用の代理店公開プロフィール。担当顧客等は一切返さない。 */
export async function GET(_request: Request, context: { params: Promise<{ publicId: string }> }) {
  const { supabase } = await getApiContext();
  const { publicId } = await context.params;

  const { data, error } = await supabase.rpc("treemerce_agent_public_profile", {
    p_public_id: publicId,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
