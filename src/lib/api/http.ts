import { NextResponse } from "next/server";
import type { PostgrestError } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { resolveViewer, type Viewer } from "@/lib/auth/viewer";

export function ok<T>(data: T, status = 200) {
  return NextResponse.json(data, { status });
}

export function fail(code: string, message: string, status: number) {
  return NextResponse.json({ error: { code, message } }, { status });
}

/**
 * DB 側が投げる TREEMERCE_* 例外を HTTP ステータスに対応づける。
 * DB で拒否されたものが 200 で返ることがないようにするための最終防壁。
 */
const ERROR_MAP: Record<string, { status: number; message: string }> = {
  TREEMERCE_UNAUTHENTICATED: { status: 401, message: "ログインが必要です。" },
  TREEMERCE_FORBIDDEN: { status: 403, message: "この操作を行う権限がありません。" },
  TREEMERCE_ADMIN_ONLY: { status: 403, message: "この操作は管理者のみ実行できます。" },
  TREEMERCE_SUPER_ADMIN_ONLY: { status: 403, message: "この操作は super_admin のみ実行できます。" },
  TREEMERCE_ASSIGNMENT_IMMUTABLE: {
    status: 403,
    message: "担当代理店の変更・解除・移管はできません。",
  },
  TREEMERCE_ASSIGNMENT_WRITE_DENIED: {
    status: 403,
    message: "担当データへの直接書込みは許可されていません。",
  },
  TREEMERCE_HISTORY_WRITE_DENIED: { status: 403, message: "履歴への直接書込みはできません。" },
  TREEMERCE_HISTORY_APPEND_ONLY: { status: 403, message: "履歴は変更・削除できません。" },
  TREEMERCE_AUDIT_APPEND_ONLY: { status: 403, message: "監査ログは変更・削除できません。" },
  TREEMERCE_INVITED_BY_ALREADY_SET: {
    status: 409,
    message: "この代理店の招待元は既に確定しています。変更はできません。",
  },
  TREEMERCE_INVITE_CYCLE: { status: 409, message: "招待経路が循環しています。" },
  TREEMERCE_INVITE_CHAIN_TOO_DEEP: { status: 409, message: "招待経路が深すぎます。" },
  TREEMERCE_SELF_INVITE: { status: 400, message: "自分自身を招待元にはできません。" },
  TREEMERCE_INVITATION_NOT_FOUND: { status: 404, message: "招待コードが見つかりません。" },
  TREEMERCE_INVITATION_INACTIVE: { status: 400, message: "招待コードが無効です。" },
  TREEMERCE_INVITATION_EXPIRED: { status: 400, message: "招待コードの有効期限が切れています。" },
  TREEMERCE_INVITATION_EXHAUSTED: {
    status: 400,
    message: "招待コードの利用上限に達しています。",
  },
  TREEMERCE_AGENT_NOT_FOUND: { status: 404, message: "指定の代理店が見つかりません。" },
  TREEMERCE_AGENT_NOT_ACTIVE: { status: 400, message: "対象の代理店が稼働状態ではありません。" },
  TREEMERCE_CUSTOMER_NOT_FOUND: { status: 404, message: "対象の購入者が見つかりません。" },
  TREEMERCE_ASSIGNMENT_NOT_FOUND: { status: 404, message: "有効な担当が見つかりません。" },
  TREEMERCE_IDENTIFIER_REQUIRED: {
    status: 400,
    message: "メールアドレスまたは電話番号のいずれかが必要です。",
  },
  TREEMERCE_REASON_REQUIRED: { status: 400, message: "変更理由は必須です。" },
  TREEMERCE_NO_CHANGE: { status: 400, message: "既に同じ代理店が担当しています。" },
  TREEMERCE_INVALID_INPUT: { status: 400, message: "入力内容が不正です。" },
  TREEMERCE_INVALID_PERIOD: { status: 400, message: "期間の指定が不正です。" },
  TREEMERCE_USER_NOT_FOUND: { status: 404, message: "対象ユーザーが見つかりません。" },
  TREEMERCE_CANNOT_REVOKE_SELF: { status: 400, message: "自分自身の権限は剥奪できません。" },
};

export function failFromPostgrest(error: PostgrestError) {
  const raw = `${error.message ?? ""} ${error.details ?? ""} ${error.hint ?? ""}`;

  for (const [code, mapped] of Object.entries(ERROR_MAP)) {
    if (raw.includes(code)) return fail(code, mapped.message, mapped.status);
  }

  if (error.code === "42501") {
    return fail("FORBIDDEN", "この操作を行う権限がありません。", 403);
  }
  if (error.code === "23505") {
    return fail("CONFLICT", "既に登録されています。", 409);
  }

  console.error("[treemerce] unexpected postgrest error", error);
  return fail("INTERNAL_ERROR", "処理中にエラーが発生しました。", 500);
}

export async function readJson<T>(request: Request): Promise<T | null> {
  try {
    return (await request.json()) as T;
  } catch {
    return null;
  }
}

export type ApiContext = { supabase: SupabaseClient; viewer: Viewer };

export async function getApiContext(): Promise<ApiContext> {
  const supabase = await createSupabaseServerClient();
  const viewer = await resolveViewer(supabase);
  return { supabase, viewer };
}

/**
 * API 層の代理店ガード。RLS と重ねてもう一度判定する (多層防御)。
 */
export async function requireAgentApi() {
  const ctx = await getApiContext();
  if (!ctx.viewer.userId) {
    return { error: fail("UNAUTHENTICATED", "ログインが必要です。", 401) } as const;
  }
  if (!ctx.viewer.agent) {
    return { error: fail("NOT_AN_AGENT", "代理店アカウントではありません。", 403) } as const;
  }
  if (ctx.viewer.agent.status !== "active") {
    return { error: fail("AGENT_NOT_ACTIVE", "アカウントが稼働状態ではありません。", 403) } as const;
  }
  return { ctx, agent: ctx.viewer.agent } as const;
}

/**
 * API 層の管理者ガード。
 * 絶対原則8: 担当変更系は必ずここを通す (DB 側でも二重に拒否される)。
 */
export async function requireAdminApi() {
  const ctx = await getApiContext();
  if (!ctx.viewer.userId) {
    return { error: fail("UNAUTHENTICATED", "ログインが必要です。", 401) } as const;
  }
  if (!ctx.viewer.isAdmin) {
    return {
      error: fail("TREEMERCE_ADMIN_ONLY", "この操作は管理者のみ実行できます。", 403),
    } as const;
  }
  return { ctx } as const;
}

/**
 * API 層の super_admin 専用ガード。統括管理ページ(全代理店・全顧客の横断詳細/編集/
 * 担当変更/ステータス変更)の書込みエンドポイントはここを通す。
 * DB 側の `app.is_super_admin()` チェックと重ねる多層防御。
 */
export async function requireSuperAdminApi() {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard;
  if (guard.ctx.viewer.adminRole !== "super_admin") {
    return {
      error: fail("TREEMERCE_SUPER_ADMIN_ONLY", "この操作は super_admin のみ実行できます。", 403),
    } as const;
  }
  return guard;
}
