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
    message: "担当オブザーバーの変更・解除・移管はできません。",
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
    message: "このオブザーバーの招待元は既に確定しています。変更はできません。",
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
  TREEMERCE_AGENT_NOT_FOUND: { status: 404, message: "指定のオブザーバーが見つかりません。" },
  TREEMERCE_AGENT_NOT_ACTIVE: { status: 400, message: "対象のオブザーバーが稼働状態ではありません。" },
  TREEMERCE_CUSTOMER_NOT_FOUND: { status: 404, message: "対象の購入者が見つかりません。" },
  TREEMERCE_ASSIGNMENT_NOT_FOUND: { status: 404, message: "有効な担当が見つかりません。" },
  TREEMERCE_IDENTIFIER_REQUIRED: {
    status: 400,
    message: "メールアドレスまたは電話番号のいずれかが必要です。",
  },
  TREEMERCE_REASON_REQUIRED: { status: 400, message: "変更理由は必須です。" },
  TREEMERCE_NO_CHANGE: { status: 400, message: "変更内容が現在と同じです。" },
  TREEMERCE_INVALID_INPUT: { status: 400, message: "入力内容が不正です。" },
  TREEMERCE_INVALID_PERIOD: { status: 400, message: "期間の指定が不正です。" },
  TREEMERCE_USER_NOT_FOUND: { status: 404, message: "対象ユーザーが見つかりません。" },
  TREEMERCE_CANNOT_REVOKE_SELF: { status: 400, message: "自分自身の権限は剥奪できません。" },

  // 商品・注文 (0010〜0013)
  // 原則6: 注文の拒否理由は中立に保つ。担当代理店や既存顧客かどうかは一切示さない。
  TREEMERCE_ORDER_UNAVAILABLE: {
    status: 409,
    message: "ご注文を受け付けられませんでした。運営事務局までお問い合わせください。",
  },
  TREEMERCE_ORDERS_CLOSED: { status: 409, message: "現在ご注文を受け付けておりません。" },
  TREEMERCE_PRODUCT_UNAVAILABLE: {
    status: 409,
    message: "ご指定の商品は現在お取り扱いできません。",
  },
  TREEMERCE_OUT_OF_STOCK: { status: 409, message: "在庫が不足している商品があります。" },
  TREEMERCE_INVALID_ITEMS: { status: 400, message: "商品の指定が不正です。" },
  TREEMERCE_PRODUCT_NOT_FOUND: { status: 404, message: "商品が見つかりません。" },
  TREEMERCE_ORDER_NOT_FOUND: { status: 404, message: "注文が見つかりません。" },
  TREEMERCE_INVALID_TRANSITION: { status: 409, message: "この状態へは変更できません。" },
  TREEMERCE_RESTOCK_REQUIRED: {
    status: 400,
    message: "発送済み注文のキャンセルでは、在庫を戻すかどうかを選択してください。",
  },
  TREEMERCE_SETTINGS_INCOMPLETE: {
    status: 400,
    message: "注文受付を開始するには、振込先と販売事業者情報 (名称・所在地・電話番号) が必要です。",
  },
  TREEMERCE_ORDER_IMMUTABLE: { status: 403, message: "注文の帰属・金額は変更できません。" },
  TREEMERCE_ORDER_WRITE_DENIED: { status: 403, message: "注文への直接書込みはできません。" },

  // 生産者・発送 (0014〜0015)
  TREEMERCE_PRODUCER_NOT_FOUND: { status: 404, message: "生産者が見つかりません。" },
  TREEMERCE_PRODUCER_INACTIVE: { status: 400, message: "無効な生産者は選べません。" },
  TREEMERCE_PRODUCER_PLACEHOLDER: {
    status: 400,
    message: "仮の生産者「未設定（運営）」は編集できません。",
  },
  TREEMERCE_SHIPMENT_NOT_FOUND: { status: 404, message: "発送記録が見つかりません。" },
  TREEMERCE_SHIPMENT_NOT_READY: {
    status: 409,
    message: "入金確認前またはキャンセル済みのため、発送依頼書は作成できません。",
  },
  TREEMERCE_SHIPMENT_INVALID_STATE: { status: 409, message: "この発送記録は現在の状態では操作できません。" },
  TREEMERCE_SHIPMENTS_PENDING: {
    status: 409,
    message: "未発送の生産者があります。生産者ごとの発送登録を完了してください。",
  },

  // 代理店の事業プロフィール・持込み申請 (0016〜0018)
  // 他の代理店の申請は「見つかりません」で返す (存在も開示しない)
  TREEMERCE_PROFILE_WRITE_DENIED: { status: 403, message: "プロフィールへの直接書込みはできません。" },
  TREEMERCE_SUBMISSION_NOT_FOUND: { status: 404, message: "申請が見つかりません。" },
  TREEMERCE_SUBMISSION_NOT_EDITABLE: {
    status: 409,
    message: "申請中・確定済みの申請は変更できません。",
  },
  TREEMERCE_SUBMISSION_FINALIZED: { status: 409, message: "この申請は確定済みのため変更できません。" },
  TREEMERCE_SUBMISSION_NOT_APPROVED: {
    status: 409,
    message: "持込み申請が承認されていない商品は公開できません。",
  },
  TREEMERCE_SUBMISSION_WRITE_DENIED: { status: 403, message: "申請への直接書込みはできません。" },
  TREEMERCE_PRODUCT_SOURCE_IMMUTABLE: { status: 403, message: "商品の持込み元は変更できません。" },

  // 運営によるプロフィール入力・申請の代行 (0020〜0021)
  TREEMERCE_PROFILE_CONFLICT: {
    status: 409,
    message: "画面を開いた後にプロフィールが更新されています。開き直してから編集してください。",
  },
  TREEMERCE_AGENT_WITHDRAWN: { status: 409, message: "退会済みのオブザーバーは編集できません。" },
  TREEMERCE_SUBMISSION_NOT_PROXY: {
    status: 403,
    message: "オブザーバー本人が作成した申請は運営が編集できません。",
  },
  TREEMERCE_SUBMISSION_AGENT_MISMATCH: {
    status: 409,
    message: "申請のオブザーバーと指定のオブザーバーが一致しません。画面を開き直してください。",
  },

  // 商品カテゴリ・販売状態 (0022〜0025)
  TREEMERCE_CATEGORY_NOT_FOUND: { status: 400, message: "カテゴリを選択してください。" },
  TREEMERCE_CATEGORY_INACTIVE: { status: 400, message: "無効なカテゴリは選べません。" },
  TREEMERCE_CATEGORY_IN_USE: {
    status: 409,
    message: "公開中・準備中の商品が使っているカテゴリは無効にできません。",
  },
  TREEMERCE_CATEGORY_IMMUTABLE: { status: 400, message: "カテゴリのキーは変更できません。" },
  TREEMERCE_CATEGORY_DELETE_DENIED: { status: 403, message: "カテゴリは削除できません (無効化で扱います)。" },
  TREEMERCE_CATEGORY_WRITE_DENIED: { status: 403, message: "カテゴリへの直接書込みはできません。" },
  TREEMERCE_SERVICE_NOT_ORDERABLE: {
    status: 400,
    message: "サービスは予約の仕組みができるまで公開 (注文可能) にできません。「準備中」で表示できます。",
  },

  // 代理店申請・承認・代理店作成の一本化 (0027〜0028)
  // 原則6: 申請者本人への応答は中立に保つ (重複・既に代理店であることは DB 側で受付と同じ文面になる)
  TREEMERCE_AGENT_APPLICATION_REQUIRED: {
    status: 403,
    message: "オブザーバー登録は、紹介リンクの登録フォームからお申し込みください。",
  },
  TREEMERCE_TERMS_CONSENT_REQUIRED: {
    status: 400,
    message: "オブザーバー登録のお申し込みにはオブザーバー規約への同意が必要です。",
  },
  TREEMERCE_TERMS_NOT_AVAILABLE: {
    status: 409,
    message: "オブザーバー規約を準備中のため、現在お申し込みを受け付けていません。",
  },
  TREEMERCE_TERMS_VERSION_MISMATCH: {
    status: 409,
    message: "オブザーバー規約が更新されています。最新の規約をご確認のうえ、改めて同意してください。",
  },
  TREEMERCE_APPLICANT_EMAIL_MISMATCH: {
    status: 400,
    message: "メールアドレスがログイン中のアカウント (確認済み) と一致しません。",
  },
  TREEMERCE_APPLICATION_NOT_FOUND: { status: 404, message: "申請が見つかりません。" },
  TREEMERCE_APPLICATION_NOT_PENDING: { status: 409, message: "この申請は既に審査済みです。" },
  TREEMERCE_TERMS_ACCEPTANCE_MISSING: {
    status: 409,
    message: "規約の同意記録がない申請は承認できません。",
  },
  TREEMERCE_INVITER_REQUIRED: {
    status: 400,
    message: "招待元を指定してください (オブザーバーを指定するか、招待元なしを明示)。",
  },
  TREEMERCE_INVITER_UNAVAILABLE: {
    status: 409,
    message: "招待元のオブザーバーが稼働中ではないため承認できません。",
  },
  TREEMERCE_AGENT_ALREADY_EXISTS: { status: 409, message: "このアカウントは既にオブザーバーです。" },
  TREEMERCE_AGENT_EMAIL_TAKEN: { status: 409, message: "このメールアドレスのオブザーバーが既に存在します。" },
  TREEMERCE_EMAIL_MISMATCH: { status: 400, message: "メールアドレスが対象アカウントと一致しません。" },
  TREEMERCE_AGENT_CREATE_DENIED: { status: 403, message: "オブザーバーは運営の承認処理でのみ作成できます。" },
  TREEMERCE_INVITED_BY_CREATE_ONLY: { status: 409, message: "招待元はオブザーバーの作成時にのみ設定できます。" },

  // 運営の代理店登録リンク (0030)
  TREEMERCE_REGISTRATION_LINK_UNAVAILABLE: {
    status: 409,
    message: "このオブザーバー登録リンクは利用できません。有効期限が切れたか、利用の上限に達した可能性があります。",
  },
  TREEMERCE_REGISTRATION_LINK_NOT_FOUND: { status: 404, message: "オブザーバー登録リンクが見つかりません。" },
  TREEMERCE_REGISTRATION_LINK_NOT_ACTIVE: { status: 409, message: "このリンクは既に無効化されています。" },
  TREEMERCE_REGISTRATION_LINK_WRITE_DENIED: { status: 403, message: "オブザーバー登録リンクへの直接書込みはできません。" },
  TREEMERCE_REGISTRATION_LINK_IMMUTABLE: { status: 403, message: "発行済みのリンクの内容は変更できません。" },
  TREEMERCE_REGISTRATION_LINK_DELETE_DENIED: { status: 403, message: "オブザーバー登録リンクは削除できません (無効化で扱います)。" },

  // 代理店が発行する代理店登録リンク (0031)
  TREEMERCE_APPLICATION_INVITER_MISMATCH: {
    status: 409,
    message: "申請の紹介者はリンクの発行元と一致しなければなりません。",
  },
};

/** DB 側の具体的な理由 (「商品名は必須です」等) をそのまま画面に返すコード */
const DETAIL_CODES = new Set([
  "TREEMERCE_INVALID_INPUT",
  "TREEMERCE_REASON_REQUIRED",
  "TREEMERCE_SUBMISSION_NOT_EDITABLE",
  "TREEMERCE_CATEGORY_INACTIVE",
  "TREEMERCE_CATEGORY_NOT_FOUND",
]);

/**
 * DB 側で自前に raise した "TREEMERCE_XXX: 理由" (1 行のみ) から理由部分だけを取り出す。
 * メッセージが TREEMERCE_ で始まらないもの (制約違反・SQL エラー等) や複数行のものは null を返し、
 * 呼び出し側で汎用メッセージにする。制約名・テーブル名・SQL の内容を画面に出さないため。
 */
function detailMessage(message: string | undefined, code: string): string | null {
  const match = message?.match(new RegExp(`^${code}:[ \\t]*([^\\r\\n]+)$`));
  return match?.[1]?.trim() || null;
}

export function failFromPostgrest(error: PostgrestError) {
  const raw = `${error.message ?? ""} ${error.details ?? ""} ${error.hint ?? ""}`;

  for (const [code, mapped] of Object.entries(ERROR_MAP)) {
    if (raw.includes(code)) {
      // DETAIL_CODES は DB 側の具体的な理由 (「産地は必須です」等) をそのまま返す
      const detail = DETAIL_CODES.has(code) ? detailMessage(error.message, code) : null;
      return fail(code, detail ?? mapped.message, mapped.status);
    }
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
    return { error: fail("NOT_AN_AGENT", "オブザーバーアカウントではありません。", 403) } as const;
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
