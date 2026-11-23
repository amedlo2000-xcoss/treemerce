"use client";

import { MailCheck } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";
import { shopLoginUrl } from "@/lib/shop/return-to";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

/**
 * ショップから来た人の会員登録 (/register/{公開ID}?next=/shop/...)。登録後にショップへ戻る。
 *
 *   1. 会員 (購入者) として登録する (既存の入口 treemerce_register_member。担当はこのリンクの
 *      オブザーバーで確定し、既存の会員なら担当は変わらない)
 *   2. ログイン用のアカウントを作る (Supabase Auth。確認メールのリンクから next へ戻る)
 *
 * 運営のショップ (/shop) から来た人 (/register?next=/shop...、agentPublicId = null) は、
 * 1 を treemerce_register_direct_member で行う (担当なし = 運営直接。既存の会員なら何も変わらない。0037)。
 *
 * 原則6: 新規・既存の会員、既存のアカウントのどの場合も、完了の表示は同じ文面にする
 * (既存の会員かどうかを推測できないようにする)。
 */
export function ShopMemberSignup({
  agentPublicId,
  next,
}: {
  /** null は運営のショップ (担当なしで登録する) */
  agentPublicId: string | null;
  /** 戻り先 (このショップ内のパス。カートの中身を含む) */
  next: string;
}) {
  const router = useRouter();
  const [form, setForm] = useState({ full_name: "", full_name_kana: "", email: "", phone: "", password: "" });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<string | null>(null);

  const set = (key: keyof typeof form, value: string) => setForm((prev) => ({ ...prev, [key]: value }));
  const canSubmit =
    !pending && form.full_name.trim() !== "" && /.+@.+\..+/.test(form.email.trim()) && form.password.length >= 8;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    const email = form.email.trim();

    // 1. 会員登録 (新規・既存のどちらでも先へ進む。応答の違いは画面に出さない)
    const member = {
      full_name: form.full_name,
      full_name_kana: form.full_name_kana || null,
      email,
      phone: form.phone || null,
      customer_type: "individual",
    };
    const response = await fetch(agentPublicId ? "/api/public/members/register" : "/api/public/members/direct", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(agentPublicId ? { ...member, agent_public_id: agentPublicId, apply_agent: false } : member),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      setError(body?.error?.message ?? "登録に失敗しました。時間をおいて再度お試しください。");
      setPending(false);
      return;
    }

    // 2. ログイン用のアカウント。氏名・電話番号は注文画面の自動入力のためにアカウントへ保存する
    const supabase = getSupabaseBrowserClient();
    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password: form.password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`,
        data: {
          full_name: form.full_name.trim(),
          full_name_kana: form.full_name_kana.trim(),
          phone: form.phone.trim(),
        },
      },
    });

    if (signUpError) {
      const code = (signUpError as { code?: string }).code ?? "";
      if (code === "user_already_exists" || /already registered/i.test(signUpError.message)) {
        // 既にアカウントがある場合も、新規と同じ表示にする
        setSentTo(email);
      } else if (code === "weak_password") {
        setError("パスワードが簡単すぎます。英字と数字を組み合わせた 8 文字以上にしてください。");
      } else if (code === "over_email_send_rate_limit" || signUpError.status === 429) {
        setError("ただいま確認メールの送信が混み合っています。しばらく時間をおいて再度お試しください。");
      } else {
        setError("登録を完了できませんでした。時間をおいて再度お試しください。");
      }
      setPending(false);
      return;
    }

    if (data.session) {
      // メールの確認が不要な設定の場合は、そのままショップへ戻る
      router.replace(next);
      router.refresh();
      return;
    }

    setSentTo(email);
    setPending(false);
  }

  if (sentTo) {
    return (
      <div className="space-y-4">
        <div className="space-y-2 rounded-2xl border border-success-soft bg-success-soft px-4 py-5 text-[14px] leading-6 text-text-primary">
          <MailCheck size={28} className="text-success" />
          <p className="text-[16px] font-bold">確認メールをお送りしました</p>
          <p>
            <span className="break-all font-semibold">{sentTo}</span> 宛のメールのリンクを押すと、
            ログインした状態でショップに戻り、ご購入を続けられます。カートの中身も引き継がれます。
          </p>
          <p className="text-[12px] text-text-secondary">
            メールが見当たらない場合は、迷惑メールのフォルダもご確認ください。
            既にご登録済みのメールアドレスの場合、確認メールは届きません。ログインからお進みください。
          </p>
        </div>
        <PrimaryButton href={shopLoginUrl(next)} variant="secondary">
          ログインする
        </PrimaryButton>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-5">
      <div>
        <h2 className="text-[22px] font-bold text-text-primary">会員登録（無料）</h2>
        <p className="mt-1.5 text-[14px] leading-6 text-text-secondary">
          ご登録のあと、確認メールのリンクを押すとショップに戻ってご購入を続けられます。
        </p>
      </div>

      <div className="space-y-3">
        <label className="block space-y-1">
          <span className="text-[13px] font-medium text-text-secondary">お名前 (必須)</span>
          <input required autoComplete="name" value={form.full_name} onChange={(e) => set("full_name", e.target.value)} className={INPUT} />
        </label>
        <label className="block space-y-1">
          <span className="text-[13px] font-medium text-text-secondary">フリガナ</span>
          <input value={form.full_name_kana} onChange={(e) => set("full_name_kana", e.target.value)} className={INPUT} />
        </label>
        <label className="block space-y-1">
          <span className="text-[13px] font-medium text-text-secondary">メールアドレス (必須・ログインに使います)</span>
          <input
            type="email"
            required
            autoComplete="email"
            inputMode="email"
            value={form.email}
            onChange={(e) => set("email", e.target.value)}
            className={INPUT}
          />
        </label>
        <label className="block space-y-1">
          <span className="text-[13px] font-medium text-text-secondary">電話番号</span>
          <input type="tel" autoComplete="tel" inputMode="tel" value={form.phone} onChange={(e) => set("phone", e.target.value)} className={INPUT} />
        </label>
        <label className="block space-y-1">
          <span className="text-[13px] font-medium text-text-secondary">パスワード (必須・8 文字以上)</span>
          <input
            type="password"
            required
            minLength={8}
            autoComplete="new-password"
            value={form.password}
            onChange={(e) => set("password", e.target.value)}
            className={INPUT}
          />
        </label>
      </div>

      {error ? <p className="text-[13px] text-danger">{error}</p> : null}

      <PrimaryButton type="submit" disabled={!canSubmit}>
        {pending ? "送信中…" : "登録する"}
      </PrimaryButton>

      <p className="text-center text-[13px] text-text-secondary">
        既に会員の方は
        <Link href={shopLoginUrl(next)} className="mx-1 font-semibold text-brand hover:underline">
          ログイン
        </Link>
      </p>
      <p className="text-center">
        <Link href={next} className="text-[13px] text-text-secondary hover:text-text-primary hover:underline">
          ショップに戻る
        </Link>
      </p>
    </form>
  );
}
