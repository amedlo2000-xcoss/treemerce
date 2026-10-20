import { NextResponse } from "next/server";

import { fail, failFromPostgrest, ok, readJson } from "@/lib/api/http";
import { takeRateLimit } from "@/lib/api/rate-limit";
import { requestMeta } from "@/lib/api/request-meta";
import type { AgentTerms, MyAgentApplication } from "@/lib/domain/types";
import { createSupabaseAuthAdmin, createSupabaseIsolatedClient } from "@/lib/supabase/admin";

type Body = {
  token?: string;
  agent_display_name?: string;
  full_name?: string;
  email?: string;
  password?: string;
  phone?: string | null;
  accept_agent_terms?: unknown;
  agent_terms_version?: string | null;
  // ip_address / user_agent は受け取らない (送られてきても無視する)
};

/**
 * 申し込みの受付・重複・既に代理店・同じメールアドレスのアカウントが既にある、のいずれでも返す文面。
 * DB の app.agent_application_received_message() と同じ文面で、応答は常にこれだけにする (絶対原則6)。
 */
const RECEIVED = {
  application_status: "received",
  application_message: "代理店登録のお申し込みを受け付けました。内容を確認のうえ、運営事務局よりご連絡します。",
} as const;

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** 同じ IP アドレスからの申し込みは 10 分間に 5 回まで (入力の誤りで失敗した送信も数える) */
const RATE_LIMIT = { limit: 5, windowMs: 10 * 60 * 1000 };

/**
 * 代理店登録リンク (/join/{トークン}) からの申し込み。運営・代理店のどちらが発行したリンクも同じ。
 * 1回の送信で、メール確認済みのアカウントの作成と代理店の申し込みを行う (確認メールは送らない・ログインはさせない)。
 *
 *   1. リンクと規約の版を確認する (使えないリンクでアカウントを作らない)
 *   2. service_role でアカウントをメール確認済みとして作る (同じメールアドレスがあれば何もせず中立メッセージ)
 *   3. そのアカウントでログインした権限で treemerce_apply_agent_via_link() を呼ぶ
 *      (紹介者の確定・同意の記録・監査ログ・重複の扱いは DB 側。紹介者はリンクから決まり、ここでは渡さない)
 *   4. 申し込みが失敗した、または申請が作られなかった (重複) ときは、作ったアカウントを削除して戻す
 *
 * 代理店になるのは運営の承認 (app.create_agent()) のときだけ。会員登録は行わない。
 * 規約の同意に残す IP アドレスとブラウザ情報は、ここでリクエストヘッダーから取得して渡す。
 */
export async function POST(request: Request) {
  // アカウントを作る前に、同じ IP アドレスからの短時間の連続申し込みを止める
  const meta = requestMeta(request);
  const limited = takeRateLimit(`agent-apply:${meta.ipAddress ?? "unknown"}`, RATE_LIMIT.limit, RATE_LIMIT.windowMs);
  if (!limited.ok) {
    return NextResponse.json(
      {
        error: {
          code: "TREEMERCE_RATE_LIMITED",
          message: "短時間に多くのお申し込みがありました。しばらく時間をおいて改めてお試しください。",
        },
      },
      { status: 429, headers: { "retry-after": String(limited.retryAfterSec) } },
    );
  }

  const body = await readJson<Body>(request);

  const token = body?.token?.trim() ?? "";
  const agentDisplayName = body?.agent_display_name?.trim() ?? "";
  const fullName = body?.full_name?.trim() ?? "";
  const email = body?.email?.trim().toLowerCase() ?? "";
  const password = typeof body?.password === "string" ? body.password : "";
  const phone = body?.phone?.trim() || null;
  const termsVersion = body?.agent_terms_version?.trim() || null;

  if (!token) {
    return fail("TREEMERCE_REGISTRATION_LINK_UNAVAILABLE", "この代理店登録リンクは利用できません。", 409);
  }
  if (body?.accept_agent_terms !== true) {
    return fail(
      "TREEMERCE_TERMS_CONSENT_REQUIRED",
      "代理店登録のお申し込みには代理店規約への同意が必要です。",
      400,
    );
  }
  if (!agentDisplayName || agentDisplayName.length > 100) {
    return fail("TREEMERCE_INVALID_INPUT", "代理店名を 100 文字以内で入力してください。", 400);
  }
  if (!fullName || fullName.length > 100) {
    return fail("TREEMERCE_INVALID_INPUT", "氏名を 100 文字以内で入力してください。", 400);
  }
  if (!EMAIL.test(email) || email.length > 254) {
    return fail("TREEMERCE_INVALID_INPUT", "メールアドレスを正しく入力してください。", 400);
  }
  if (password.length < 8 || password.length > 72) {
    return fail("TREEMERCE_INVALID_INPUT", "パスワードは 8 文字以上 72 文字以内で入力してください。", 400);
  }
  if (phone && phone.length > 30) {
    return fail("TREEMERCE_INVALID_INPUT", "電話番号を正しく入力してください。", 400);
  }

  // ---- 1. リンクと規約の版の確認 (アカウントを作る前に) -------------------------
  const anon = createSupabaseIsolatedClient();
  const [{ data: linkData, error: linkError }, { data: termsData, error: termsError }] = await Promise.all([
    anon.rpc("treemerce_resolve_registration_link", { p_token: token }),
    anon.rpc("treemerce_current_agent_terms"),
  ]);
  if (linkError) return failFromPostgrest(linkError);
  if (termsError) return failFromPostgrest(termsError);
  if (!(linkData as { valid?: boolean } | null)?.valid) {
    return fail(
      "TREEMERCE_REGISTRATION_LINK_UNAVAILABLE",
      "この代理店登録リンクは利用できません。有効期限が切れたか、利用の上限に達した可能性があります。",
      409,
    );
  }
  const terms = (termsData as AgentTerms | null) ?? { available: false };
  if (!terms.available) {
    return fail("TREEMERCE_TERMS_NOT_AVAILABLE", "代理店規約を準備中のため、現在お申し込みを受け付けていません。", 409);
  }
  if (terms.version !== termsVersion) {
    return fail(
      "TREEMERCE_TERMS_VERSION_MISMATCH",
      "代理店規約が更新されています。最新の規約をご確認のうえ、改めて同意してください。",
      409,
    );
  }

  // ---- 2. メール確認済みのアカウントを作る ----------------------------------------
  const authAdmin = createSupabaseAuthAdmin();
  const { data: created, error: createError } = await authAdmin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    // 同じメールアドレスのアカウントが既にある → 何もせず、新規と同じ文面 (絶対原則6)
    if (createError?.code === "email_exists" || createError?.code === "user_already_exists") {
      return ok(RECEIVED);
    }
    if (createError?.code === "weak_password") {
      return fail("TREEMERCE_INVALID_INPUT", "パスワードが条件を満たしていません。より長く推測されにくいものにしてください。", 400);
    }
    if (createError?.code === "email_address_invalid") {
      return fail("TREEMERCE_INVALID_INPUT", "メールアドレスを正しく入力してください。", 400);
    }
    // エラーの中身は出さず、コードと状態だけを記録する
    console.error("[treemerce] agent application: createUser failed", createError?.code, createError?.status);
    return fail("INTERNAL_ERROR", "処理中にエラーが発生しました。時間をおいて改めてお試しください。", 500);
  }

  const userId = created.user.id;
  const discardAccount = async () => {
    const { error } = await authAdmin.deleteUser(userId);
    if (error) console.error("[treemerce] agent application: failed to discard account", userId, error.code, error.status);
  };

  // ---- 3. 作ったアカウントの権限で申し込む ---------------------------------------
  const applicant = createSupabaseIsolatedClient();
  try {
    const { error: signInError } = await applicant.auth.signInWithPassword({ email, password });
    if (signInError) {
      console.error("[treemerce] agent application: sign-in failed", signInError.code, signInError.status);
      await discardAccount();
      return fail("INTERNAL_ERROR", "処理中にエラーが発生しました。時間をおいて改めてお試しください。", 500);
    }

    const { error } = await applicant.rpc("treemerce_apply_agent_via_link", {
      p_token: token,
      p_agent_display_name: agentDisplayName,
      p_full_name: fullName,
      p_email: email,
      p_phone: phone,
      p_accept_agent_terms: true,
      p_agent_terms_version: termsVersion,
      p_ip_address: meta.ipAddress,
      p_user_agent: meta.userAgent,
    });
    if (error) {
      await applicant.auth.signOut();
      await discardAccount();
      return failFromPostgrest(error);
    }

    // ---- 4. 申請が作られなかった (電話番号の重複など) ときはアカウントを残さない ----
    const { data: mine } = await applicant.rpc("treemerce_my_agent_application");
    await applicant.auth.signOut();
    if ((mine as MyAgentApplication | null)?.state !== "received") {
      await discardAccount();
    }
  } catch (cause) {
    console.error("[treemerce] agent application: unexpected error", cause instanceof Error ? cause.name : "unknown");
    await discardAccount();
    return fail("INTERNAL_ERROR", "処理中にエラーが発生しました。時間をおいて改めてお試しください。", 500);
  }

  // 申請ID・紹介者・アカウントの情報は返さない
  return ok(RECEIVED);
}
