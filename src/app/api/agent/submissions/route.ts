import { fail, failFromPostgrest, ok, readJson, requireAgentApi } from "@/lib/api/http";
import { parseSubmissionInput } from "@/lib/api/submission-input";

/**
 * 持込み申請の下書きを作成する (本人のみ)。
 * 申請者は RPC がログイン中の代理店 (app.current_agent_id) に固定する。
 */
export async function POST(request: Request) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const parsed = parseSubmissionInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_save_my_submission", {
    p_submission_id: null,
    ...parsed.input,
  });
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
