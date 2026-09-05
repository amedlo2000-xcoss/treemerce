import { failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";

type Body = { email?: string | null; phone?: string | null };

/**
 * 重複登録の事前チェック。
 *
 * 絶対原則6 / 7: email・電話番号という識別子でのみ照合し、
 * 返すのは「重複しているか」と中立メッセージだけ。
 * 担当代理店が誰か、いつ登録されたか等は一切返さない。
 */
export async function POST(request: Request) {
  const { supabase } = await getApiContext();
  const body = (await readJson<Body>(request)) ?? {};

  const { data, error } = await supabase.rpc("treemerce_check_customer_duplicate", {
    p_email: body.email?.trim() || null,
    p_phone: body.phone?.trim() || null,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
