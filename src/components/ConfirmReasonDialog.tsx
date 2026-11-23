"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, type ReactNode } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

/**
 * 「確認の文 + 理由 (必須)」のダイアログを開き、確定で API に POST する共通部品。
 * 確定後は画面を再読み込み (router.refresh) する。理由の必須は API と DB でも再判定される。
 */
export function ConfirmReasonDialog({
  triggerLabel,
  triggerClassName,
  disabled = false,
  disabledTitle,
  sentence,
  note,
  reasonLabel = "理由 (必須・監査ログに記録されます)",
  confirmLabel = "確定",
  endpoint,
  payload,
  tone = "brand",
  onDone,
}: {
  triggerLabel: ReactNode;
  triggerClassName?: string;
  disabled?: boolean;
  disabledTitle?: string;
  sentence: ReactNode;
  note?: ReactNode;
  reasonLabel?: string;
  confirmLabel?: string;
  endpoint: string;
  /** reason 以外に送る値 */
  payload: Record<string, unknown>;
  tone?: "brand" | "danger";
  onDone?: () => void;
}) {
  const router = useRouter();
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function open() {
    setReason("");
    setError(null);
    dialogRef.current?.showModal();
  }

  async function confirm(event: React.FormEvent) {
    event.preventDefault();
    if (!reason.trim()) {
      setError("理由を入力してください。");
      return;
    }
    setPending(true);
    setError(null);

    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...payload, reason }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "処理に失敗しました。");
      return;
    }

    dialogRef.current?.close();
    onDone?.();
    router.refresh();
  }

  const box =
    tone === "danger"
      ? "border-danger/40 bg-danger-soft"
      : "border-brand/40 bg-brand-soft";

  return (
    <>
      <button
        type="button"
        onClick={open}
        disabled={disabled}
        title={disabled ? disabledTitle : undefined}
        className={
          triggerClassName ??
          "whitespace-nowrap rounded-xl border border-brand px-3 py-1.5 text-[13px] font-semibold text-brand hover:bg-brand-soft disabled:cursor-not-allowed disabled:border-border-soft disabled:text-text-secondary disabled:hover:bg-transparent"
        }
      >
        {triggerLabel}
      </button>

      <dialog
        ref={dialogRef}
        onCancel={(e) => {
          if (pending) e.preventDefault();
        }}
        className="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-[20px] border border-border-soft bg-surface p-0 text-left shadow-[var(--shadow-card)] backdrop:bg-black/40"
      >
        <form onSubmit={confirm} className="space-y-4 px-5 py-5">
          <div className={`space-y-2 rounded-xl border-2 px-4 py-4 ${box}`}>
            <p className="text-[16px] font-bold leading-7 text-text-primary">{sentence}</p>
            {note ? <p className="text-[12px] leading-5 text-text-secondary">{note}</p> : null}
          </div>

          <Field label={reasonLabel}>
            <textarea
              required
              rows={3}
              maxLength={1000}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>

          {error ? <FormMessage tone="error">{error}</FormMessage> : null}

          <div className="flex flex-wrap gap-2">
            <button type="submit" disabled={pending || !reason.trim()} className={BUTTON_CLASS}>
              {pending ? "処理中…" : confirmLabel}
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
      </dialog>
    </>
  );
}
