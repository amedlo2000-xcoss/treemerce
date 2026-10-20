import { fail, readJson } from "@/lib/api/http";

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type IssueBody = { note?: string | null; max_uses?: number | null; expires_at?: string | null };

/**
 * 代理店登録リンクの発行の入力 (運営・代理店で共通)。紐づけ先は受け取らない (DB 側が決める)。
 * 上限・期限は DB 側でも再検証する。
 */
export async function readIssueLinkInput(request: Request) {
  const body = (await readJson<IssueBody>(request)) ?? {};
  const note = typeof body.note === "string" ? body.note.trim() : "";
  if (note.length > 200) {
    return { error: fail("TREEMERCE_INVALID_INPUT", "メモは 200 文字以内で入力してください。", 400) } as const;
  }
  const maxUses = body.max_uses == null ? null : Number(body.max_uses);
  if (maxUses !== null && (!Number.isInteger(maxUses) || maxUses <= 0)) {
    return {
      error: fail("TREEMERCE_INVALID_INPUT", "使用回数の上限は 1 以上の整数で指定してください。", 400),
    } as const;
  }
  let expiresAt: string | null = null;
  if (body.expires_at) {
    const date = new Date(body.expires_at);
    if (Number.isNaN(date.getTime())) {
      return { error: fail("TREEMERCE_INVALID_INPUT", "有効期限の指定が不正です。", 400) } as const;
    }
    expiresAt = date.toISOString();
  }
  return { params: { p_note: note || null, p_max_uses: maxUses, p_expires_at: expiresAt } } as const;
}

/** 代理店登録リンクの無効化の入力 (理由必須)。 */
export async function readRevokeLinkInput(request: Request, linkId: string) {
  if (!UUID.test(linkId)) {
    return {
      error: fail("TREEMERCE_REGISTRATION_LINK_NOT_FOUND", "オブザーバー登録リンクが見つかりません。", 404),
    } as const;
  }
  const body = await readJson<{ reason?: unknown }>(request);
  const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
  if (!reason) return { error: fail("TREEMERCE_REASON_REQUIRED", "理由を入力してください。", 400) } as const;
  if (reason.length > 1000) {
    return { error: fail("TREEMERCE_INVALID_INPUT", "理由は 1000 文字以内で入力してください。", 400) } as const;
  }
  return { params: { p_link_id: linkId, p_reason: reason } } as const;
}
