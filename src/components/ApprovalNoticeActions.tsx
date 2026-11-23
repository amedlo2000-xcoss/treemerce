"use client";

import { Check, Copy, MessageCircle } from "lucide-react";
import { useState } from "react";

import { lineShareUrl } from "@/lib/approval-notice";

/**
 * 承認済みの申請者へのお知らせ: 「LINEでお知らせ」(LINE の共有画面を新しいタブで開く) と
 * 「文面をコピー」(PC で LINE が開けないときの代わり)。文面はサーバー側で作って渡す。
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

  const base = compact
    ? "inline-flex items-center gap-1 whitespace-nowrap rounded-xl px-3 py-1.5 text-[13px] font-semibold"
    : "inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-xl px-4 py-2.5 text-[14px] font-semibold";

  return (
    <div className="flex flex-wrap items-center gap-2">
      <a
        href={lineShareUrl(text)}
        target="_blank"
        rel="noopener noreferrer"
        className={`${base} bg-[#06C755] text-white hover:opacity-90`}
      >
        <MessageCircle size={compact ? 14 : 16} />
        LINEでお知らせ
      </a>
      <button
        type="button"
        onClick={copy}
        className={`${base} border border-border-soft text-text-primary hover:bg-surface-muted`}
      >
        {copied ? <Check size={compact ? 14 : 16} className="text-success" /> : <Copy size={compact ? 14 : 16} />}
        {copied ? "コピーしました" : "文面をコピー"}
      </button>
      {copyError ? <span className="text-[12px] text-danger">コピーできませんでした</span> : null}
    </div>
  );
}
