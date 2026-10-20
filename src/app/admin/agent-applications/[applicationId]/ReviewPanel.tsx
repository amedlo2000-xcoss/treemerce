"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

type Action = "approve" | "reject";

const TABS: { key: Action; label: string }[] = [
  { key: "approve", label: "承認" },
  { key: "reject", label: "却下" },
];

/**
 * 代理店申請の承認・却下 (super_admin 専用ページから使う。API と DB でも super_admin を再判定)。
 *   承認 : 申請に固定された紹介者の下に代理店を作る。紹介者はここでは選べない。
 *          確定の前に「○○さんを、△△さん (AG-…) の下に代理店として登録します」と紐づけ先を明記して確認する。
 *   却下 : 代理店は作らない (会員のまま)。理由は監査ログにのみ残る。
 */
export function ReviewPanel({
  applicationId,
  applicantName,
  inviterLabel,
  canApprove,
}: {
  applicationId: string;
  applicantName: string;
  /** 「○○さん（AG-○○○○○○）」。運営のリンクからの申請は null (運営直下) */
  inviterLabel: string | null;
  /** 紹介者が稼働中でない申請は承認できない (DB でも拒否される) */
  canApprove: boolean;
}) {
  const router = useRouter();
  const [action, setAction] = useState<Action>("approve");
  const [reason, setReason] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const approveSentence = inviterLabel
    ? `${applicantName}さんを、${inviterLabel}の下にオブザーバーとして登録します。`
    : `${applicantName}さんを、運営直下 (紹介者なし) のオブザーバーとして登録します。`;

  async function submit() {
    setPending(true);
    setError(null);

    const response = await fetch(`/api/admin/agent-applications/${applicationId}/${action}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "処理に失敗しました。");
      setPending(false);
      setConfirming(false);
      return;
    }

    setPending(false);
    setConfirming(false);
    router.refresh();
  }

  function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    // 承認は紐づけ先を明記した確認を挟んでから確定する
    if (action === "approve" && !confirming) {
      setConfirming(true);
      return;
    }
    void submit();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div role="tablist" className="grid grid-cols-2 gap-1 rounded-xl bg-surface-muted p-1">
        {TABS.map((tab) => (
          <button
            key={tab.key}
            type="button"
            role="tab"
            aria-selected={action === tab.key}
            onClick={() => {
              setAction(tab.key);
              setConfirming(false);
              setError(null);
            }}
            className={`rounded-lg px-3 py-2 text-[14px] font-semibold transition-colors ${
              action === tab.key ? "bg-surface text-text-primary shadow" : "text-text-secondary"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <p className="text-[13px] leading-6 text-text-secondary">
        {action === "approve"
          ? "承認すると、申請に固定された紹介者の下にオブザーバーが作られ、本人はメールアドレスとパスワードでログインして利用できるようになります。紹介者はここでは変更できません。"
          : "却下するとオブザーバーは作られません。却下後に本人が改めて申し込んだ場合は、新しい申請として届きます。"}
      </p>

      <Field
        label={
          action === "approve"
            ? "承認の理由 (任意・監査ログに記録。空のときは「（理由の入力なし）」と記録)"
            : "却下の理由 (必須・監査ログに記録・本人には表示しない)"
        }
      >
        <textarea
          required={action === "reject"}
          rows={3}
          maxLength={1000}
          value={reason}
          onChange={(e) => {
            setReason(e.target.value);
            setConfirming(false);
          }}
          className={FIELD_CLASS}
        />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}

      {action === "approve" && confirming ? (
        <div className="space-y-3 rounded-xl border-2 border-brand/40 bg-brand-soft px-4 py-4">
          <p className="text-[16px] font-bold leading-7 text-text-primary">{approveSentence}</p>
          <p className="text-[12px] leading-5 text-text-secondary">
            紹介者 (招待元) は登録後に変更・追加できません。よろしければ確定してください。
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="submit" disabled={pending} className={BUTTON_CLASS}>
              {pending ? "処理中…" : "この内容で承認を確定する"}
            </button>
            <button
              type="button"
              onClick={() => setConfirming(false)}
              disabled={pending}
              className="rounded-xl border border-border-soft px-3 py-2 text-[13px] font-medium text-text-secondary"
            >
              戻る
            </button>
          </div>
        </div>
      ) : (
        <button
          type="submit"
          disabled={
            pending || (action === "approve" ? !canApprove : reason.trim().length === 0)
          }
          className={BUTTON_CLASS}
        >
          {pending ? "処理中…" : action === "approve" ? "承認する (確認へ)" : "却下する"}
        </button>
      )}
    </form>
  );
}
