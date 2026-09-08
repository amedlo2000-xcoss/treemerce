"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

export function LoginForm({ next }: { next: string }) {
  const router = useRouter();
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setMessage(null);

    const supabase = getSupabaseBrowserClient();

    const result =
      mode === "signin"
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password });

    if (result.error) {
      setError(result.error.message);
      setPending(false);
      return;
    }

    if (mode === "signup" && !result.data.session) {
      setMessage("確認メールを送信しました。メール内のリンクから登録を完了してください。");
      setPending(false);
      return;
    }

    router.replace(next);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex rounded-2xl border border-border-soft bg-surface-muted p-1">
        {(["signin", "signup"] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => {
              setMode(m);
              setError(null);
              setMessage(null);
            }}
            className={`flex-1 rounded-xl px-3 py-2 text-[14px] font-medium transition-colors ${
              mode === m ? "bg-brand text-brand-foreground" : "text-text-secondary"
            }`}
          >
            {m === "signin" ? "ログイン" : "新規アカウント"}
          </button>
        ))}
      </div>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">メールアドレス</span>
        <input
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">パスワード</span>
        <input
          type="password"
          required
          minLength={8}
          autoComplete={mode === "signin" ? "current-password" : "new-password"}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className={INPUT}
        />
      </label>

      {error ? <p className="text-[13px] text-danger">{error}</p> : null}
      {message ? <p className="text-[13px] text-brand">{message}</p> : null}

      <PrimaryButton type="submit" disabled={pending}>
        {pending ? "処理中…" : mode === "signin" ? "ログイン" : "アカウントを作成"}
      </PrimaryButton>
    </form>
  );
}
