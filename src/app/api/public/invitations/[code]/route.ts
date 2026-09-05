import { failFromPostgrest, getApiContext, ok } from "@/lib/api/http";

/** 招待コードの有効性と招待元の公開情報だけを返す。顧客情報は一切含まない。 */
export async function GET(_request: Request, context: { params: Promise<{ code: string }> }) {
  const { supabase } = await getApiContext();
  const { code } = await context.params;

  const { data, error } = await supabase.rpc("treemerce_resolve_invitation", { p_code: code });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
