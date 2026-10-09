import { fail, failFromPostgrest, ok, readJson, requireAgentApi } from "@/lib/api/http";
import { parseAgentProfileInput } from "@/lib/api/agent-profile-input";

/**
 * 代理店の事業プロフィール (本人のみ)。
 * 取得・保存とも RPC がログイン中の代理店 (app.current_agent_id) に固定するため、
 * 他の代理店のプロフィールを指定する手段はない。監査ログには値を書かない (0016)。
 */
export async function GET() {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_my_agent_profile");
  if (error) return failFromPostgrest(error);
  return ok(data);
}

export async function PUT(request: Request) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const parsed = parseAgentProfileInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc(
    "treemerce_update_my_agent_profile",
    parsed.input,
  );
  if (error) return failFromPostgrest(error);
  return ok(data);
}
