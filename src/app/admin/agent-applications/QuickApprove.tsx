"use client";

import { useRouter } from "next/navigation";
import { useRef, useState } from "react";

import { ApprovalNoticeActions } from "@/components/ApprovalNoticeActions";
import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

/**
 * 一覧からの代理店申請の承認 (super_admin 専用ページから使う。API と DB でも super_admin を再判定)。
 * 詳細ページの承認と同じ API を使う。紹介者は申請に固定された値で、ここでは選べない。
 * 確定の前に「○○さんを、△△さん (AG-…) の下に代理店として登録します」と紐づけ先を明記して確認する。
 * 却下は理由が必須のため、一覧には置かず詳細ページで行う。
 */
export function QuickApprove({
  applicationId,
  applicantName,
  inviterLabel,
  canApprove,
  noticeText,
}: {
  applicationId: string;
  applicantName: string;
  /** 「○○さん（AG-○○○○○○）」。運営のリンクからの申請は null (運営直下) */
  inviterLabel: string | null;
  /** 紹介者が稼働中でない申請は承認できない (DB でも拒否される) */
  canApprove: boolean;
  /** 承認後に本人へ送るお知らせの文面 (承認の直後にダイアログ内で LINE 共有・コピーできる) */
  noticeText: string;
}) {
  const router = useRouter();
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [approved, setApproved] = useState(false);

  const approveSentence = inviterLabel
    ? `${applicantName}さんを、${inviterLabel}の下にオブザーバーとして登録します。`
    : `${applicantName}さんを、運営直下のオブザーバーとして登録します。`;

  function open() {
    setReason("");
    setError(null);
    setApproved(false);
    dialogRef.current?.showModal();
  }

  async function confirm(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const response = await fetch(`/api/admin/agent-applications/${applicationId}/approve`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "処理に失敗しました。");
      return;
    }

    // 承認の直後に本人へのお知らせを出す (閉じるときに一覧を再読み込みする)
    setApproved(true);
  }

  function closeAfterApprove() {
    dialogRef.current?.close();
  }

  return (
    <>
      <button
        type="button"
        onClick={open}
        disabled={!canApprove}
        title={canApprove ? undefined : "紹介者が稼働中でないため承認できません"}
        className="whitespace-nowrap rounded-xl border border-brand px-3 py-1.5 text-[13px] font-semibold text-brand hover:bg-brand-soft disabled:cursor-not-allowed disabled:border-border-soft disabled:text-text-secondary disabled:hover:bg-transparent"
      >
        承認
      </button>

      <dialog
        ref={dialogRef}
        onCancel={(e) => {
          if (pending) e.preventDefault();
        }}
        onClose={() => {
          // 承認後に閉じたら (ボタン・Esc とも) 一覧を再読み込みする
          if (approved) {
            setApproved(false);
            router.refresh();
          }
        }}
        className="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-[20px] border border-border-soft bg-surface p-0 text-left shadow-[var(--shadow-card)] backdrop:bg-black/40"
      >
        {approved ? (
          <div className="space-y-4 px-5 py-5">
            <div className="space-y-1 rounded-xl border-2 border-success/40 bg-success-soft px-4 py-4">
              <p className="text-[16px] font-bold leading-7 text-text-primary">{applicantName}さんを承認しました。</p>
              <p className="text-[12px] leading-5 text-text-secondary">
                本人へのお知らせを LINE で送るか、文面をコピーしてお送りください。
              </p>
            </div>
            <pre className="max-h-56 overflow-auto whitespace-pre-wrap rounded-xl bg-surface-muted p-3 text-[12px] leading-5 text-text-primary">
              {noticeText}
            </pre>
            <ApprovalNoticeActions text={noticeText} />
            <button
              type="button"
              onClick={closeAfterApprove}
              className="rounded-xl border border-border-soft px-3 py-2 text-[13px] font-medium text-text-secondary"
            >
              閉じる
            </button>
          </div>
        ) : (
        <form onSubmit={confirm} className="space-y-4 px-5 py-5">
          <div className="space-y-2 rounded-xl border-2 border-brand/40 bg-brand-soft px-4 py-4">
            <p className="text-[16px] font-bold leading-7 text-text-primary">{approveSentence}</p>
            <p className="text-[12px] leading-5 text-text-secondary">
              紹介者 (招待元) は登録後に変更・追加できません。よろしければ確定してください。
            </p>
          </div>

          <Field label="承認の理由 (任意・監査ログに記録。空のときは「（理由の入力なし）」と記録)">
            <textarea
              rows={3}
              maxLength={1000}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>

          {error ? <FormMessage tone="error">{error}</FormMessage> : null}

          <div className="flex flex-wrap gap-2">
            <button type="submit" disabled={pending} className={BUTTON_CLASS}>
              {pending ? "処理中…" : "確定"}
            </button>
            <button
              type="button"
              onClick={() => dialogRef.current?.close()}
              disabled={pending}
              className="rounded-xl border border-border-soft px-3 py-2 text-[13px] font-medium text-text-secondary"
            >
              戻る
            </button>
          </div>
        </form>
        )}
      </dialog>
    </>
  );
}
