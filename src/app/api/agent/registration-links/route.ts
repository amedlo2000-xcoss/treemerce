import { failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";
import { readIssueLinkInput } from "@/lib/api/registration-link-input";

/** 自分が発行した代理店登録リンクの一覧 (代理店本人)。トークン・申し込んだ人の情報は含まない。 */
export async function GET() {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_my_registration_links");
  if (error) return failFromPostgrest(error);
  return ok({ links: data ?? [] });
}

/**
 * 代理店登録リンクの発行 (稼働中の代理店本人)。紐づけ先 (紹介者) は DB 側で発行した本人に固定され、
 * 引数では受け取らない。発行は監査ログに残る。トークンはこの応答でだけ返る。
 */
export async function POST(request: Request) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const input = await readIssueLinkInput(request);
  if ("error" in input) return input.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_create_my_registration_link", input.params);
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
