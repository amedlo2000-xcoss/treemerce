import { redirect } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AgentRow } from "@/lib/domain/types";

export type ViewerRole = "admin" | "agent" | "guest";

export type Viewer = {
  userId: string | null;
  email: string | null;
  agent: AgentRow | null;
  isAdmin: boolean;
  adminRole: string | null;
  role: ViewerRole;
};

export const GUEST: Viewer = {
  userId: null,
  email: null,
  agent: null,
  isAdmin: false,
  adminRole: null,
  role: "guest",
};

/**
 * ログイン中のユーザーが「代理店」なのか「管理者」なのかを判定する。
 * 絶対原則1: agents と customers は別会員区分なので、ここで customers は一切見ない。
 */
export async function resolveViewer(supabase: SupabaseClient): Promise<Viewer> {
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return GUEST;

  const [{ data: agent }, { data: adminRow }] = await Promise.all([
    supabase.from("agents").select("*").eq("auth_user_id", user.id).maybeSingle(),
    supabase
      .from("admin_roles")
      .select("role, revoked_at")
      .eq("auth_user_id", user.id)
      .is("revoked_at", null)
      .maybeSingle(),
  ]);

  const isAdmin = Boolean(adminRow);

  return {
    userId: user.id,
    email: user.email ?? null,
    agent: (agent as AgentRow | null) ?? null,
    isAdmin,
    adminRole: (adminRow?.role as string | undefined) ?? null,
    role: isAdmin ? "admin" : agent ? "agent" : "guest",
  };
}

export async function getViewer(): Promise<Viewer> {
  const supabase = await createSupabaseServerClient();
  return resolveViewer(supabase);
}

/** ページ用: 代理店でなければログインへリダイレクトする。 */
export async function requireAgentPage(returnTo: string) {
  const supabase = await createSupabaseServerClient();
  const viewer = await resolveViewer(supabase);

  if (!viewer.userId) redirect(`/login?next=${encodeURIComponent(returnTo)}`);
  if (!viewer.agent) redirect("/onboarding");
  if (viewer.agent.status !== "active") redirect("/onboarding?status=inactive");

  return { supabase, viewer, agent: viewer.agent };
}

/** ページ用: 管理者でなければ弾く。 */
export async function requireAdminPage(returnTo: string) {
  const supabase = await createSupabaseServerClient();
  const viewer = await resolveViewer(supabase);

  if (!viewer.userId) redirect(`/login?next=${encodeURIComponent(returnTo)}`);
  if (!viewer.isAdmin) redirect("/agent?error=admin_only");

  return { supabase, viewer };
}
