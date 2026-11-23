"use client";

import { Check, Copy, MessageCircle } from "lucide-react";
import { useState } from "react";

import { LINE_GREEN, LINE_OA_CHAT_URL, LINE_OFFICIAL_ACCOUNT_NAME, lineShareUrl } from "@/lib/line";

/**
 * 承認済みの申請者へのお知らせ (運営の承認画面)。LINE 公式アカウントから送る手順:
 *   ① 文面をコピー ② チャットを開き、申請者のお名前のトークを選ぶ ③ 貼り付けて送信
 * 個人の LINE で送る (LINE の共有画面) は補助として小さく残す。文面はサーバー側で作って渡す。
 */
export function ApprovalNoticeActions({ text, compact = false }: { text: string; compact?: boolean }) {
  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState(false);

  async function copy() {
    setCopyError(false);
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopyError(true);
    }
  }

  const size = compact ? 14 : 16;
  const base = compact
    ? "inline-flex items-center gap-1 whitespace-nowrap rounded-xl px-3 py-1.5 text-[13px] font-semibold"
    : "inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-xl px-4 py-2.5 text-[14px] font-semibold";

  return (
    <div className="space-y-2">
      <p className={`${compact ? "text-[11px]" : "text-[13px]"} leading-5 text-text-secondary`}>
        ① 文面をコピー ② チャットを開き、申請者のお名前のトークを選ぶ ③ 貼り付けて送信
      </p>

      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={copy}
          className={`${base} border border-border-soft bg-surface text-text-primary hover:bg-surface-muted`}
        >
          {copied ? <Check size={size} className="text-success" /> : <Copy size={size} />}
          {copied ? "コピーしました" : "文面をコピー"}
        </button>
        <a
          href={LINE_OA_CHAT_URL}
          target="_blank"
          rel="noopener noreferrer"
          title={`${LINE_OFFICIAL_ACCOUNT_NAME} のチャット`}
          style={{ backgroundColor: LINE_GREEN }}
          className={`${base} text-white hover:opacity-90`}
        >
          <MessageCircle size={size} />
          LINE公式アカウントのチャットを開く
        </a>
      </div>
      {copyError ? <p className="text-[12px] text-danger">コピーできませんでした</p> : null}

      <a
        href={lineShareUrl(text)}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-block text-[12px] font-medium text-text-secondary underline-offset-2 hover:text-text-primary hover:underline"
      >
        個人のLINEで送る
      </a>
    </div>
  );
}
