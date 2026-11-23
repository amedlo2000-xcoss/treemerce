"use client";

import { MessageCircle } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useState } from "react";

import { LINE_ADD_FRIEND_URL, LINE_GREEN, LINE_OFFICIAL_ACCOUNT_NAME } from "@/lib/line";

/**
 * オブザーバー登録のお申し込みの完了画面に出す、LINE 公式アカウントの友だち追加の案内。
 * スマホはボタンから、PC は QR コードを読み取って友だち追加する。
 */
export function LineFriendPanel() {
  const [qrSvg, setQrSvg] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    QRCode.toString(LINE_ADD_FRIEND_URL, { type: "svg", margin: 1, width: 168, errorCorrectionLevel: "M" })
      .then((svg) => {
        if (alive) setQrSvg(svg);
      })
      .catch(() => {
        if (alive) setQrSvg(null);
      });
    return () => {
      alive = false;
    };
  }, []);

  return (
    <section className="space-y-4 rounded-2xl border-2 bg-surface px-4 py-5" style={{ borderColor: LINE_GREEN }}>
      <div className="space-y-2 text-[14px] leading-6 text-text-primary">
        <p>
          承認のお知らせは、LINE公式アカウント『{LINE_OFFICIAL_ACCOUNT_NAME}』からお送りします。
        </p>
        <p>
          友だち追加のあと、お申し込みのお名前を1回だけ送ってください。
          <span className="text-text-secondary">
            （運営からは先にメッセージを送れないため、お名前の送信が必要です）
          </span>
        </p>
      </div>

      <a
        href={LINE_ADD_FRIEND_URL}
        target="_blank"
        rel="noopener noreferrer"
        style={{ backgroundColor: LINE_GREEN }}
        className="flex w-full items-center justify-center gap-2 rounded-2xl px-4 py-3.5 text-[16px] font-bold text-white shadow-[var(--shadow-card)] hover:opacity-90"
      >
        <MessageCircle size={20} />
        LINE公式アカウントを友だち追加
      </a>

      <div className="hidden items-center gap-4 rounded-xl bg-surface-muted p-3 md:flex">
        {qrSvg ? (
          <div
            className="h-[168px] w-[168px] shrink-0 rounded-lg bg-white"
            role="img"
            aria-label={`${LINE_OFFICIAL_ACCOUNT_NAME} の友だち追加 QR コード`}
            dangerouslySetInnerHTML={{ __html: qrSvg }}
          />
        ) : (
          <div className="h-[168px] w-[168px] shrink-0 rounded-lg bg-white" aria-hidden />
        )}
        <p className="text-[13px] leading-6 text-text-secondary">
          パソコンでご覧の方は、スマートフォンの LINE アプリでこの QR コードを読み取って友だち追加してください。
        </p>
      </div>
    </section>
  );
}
