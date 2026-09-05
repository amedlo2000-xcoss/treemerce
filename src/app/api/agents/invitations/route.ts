import { failFromPostgrest, ok, readJson, requireAgentApi } from "@/lib/api/http";

/** 自分が発行した招待URLの一覧。RLS により他代理店の招待は返らない。 */
export async function GET() {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase
    .from("agent_invitations")
    .select("id, code, status, max_uses, used_count, note, expires_at, created_at")
    .order("created_at", { ascending: false });

  if (error) return failFromPostgrest(error);
  return ok({ invitations: data ?? [] });
}

type Body = { note?: string | null; max_uses?: number | null; expires_at?: string | null };

/** 招待URLの発行。発行者は必ず自分自身 (サーバー側で current_agent_id を使う)。 */
export async function POST(request: Request) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const body = (await readJson<Body>(request)) ?? {};

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_create_agent_invitation", {
    p_note: body.note?.trim() || null,
    p_max_uses: typeof body.max_uses === "number" ? body.max_uses : null,
    p_expires_at: body.expires_at || null,
  });

  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
