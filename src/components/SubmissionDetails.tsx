import { ImageOff } from "lucide-react";
import type { ReactNode } from "react";

import { formatDateTime, formatYen } from "@/components/ui";
import { PRODUCT_CATEGORY_LABELS, SUBMISSION_STATUS_LABELS } from "@/lib/domain/enums";
import type { SubmissionContent, SubmissionEvent, SubmissionImageView } from "@/lib/domain/types";

/**
 * 持込み申請の表示部品 (代理店本人の申請詳細と super_admin の審査画面で共用)。
 * 渡すデータは本人用 / super_admin 用 RPC からしか取得できない (0018)。
 * 生産者の連絡先は、本人と super_admin にだけ表示される前提の画面でのみ使う。
 */

function Block({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="py-2.5">
      <dt className="text-[12px] font-semibold text-text-secondary">{label}</dt>
      <dd className="mt-0.5 whitespace-pre-wrap break-words text-[14px] leading-6 text-text-primary">
        {children}
      </dd>
    </div>
  );
}

const EMPTY = <span className="text-text-secondary">未入力</span>;

function yenOrEmpty(value: number | null) {
  return value == null ? EMPTY : formatYen(Number(value));
}

export function SubmissionProductDetails({ submission }: { submission: SubmissionContent }) {
  return (
    <dl className="divide-y divide-border-soft">
      <Block label="商品名">{submission.name}</Block>
      <Block label="カテゴリ">{PRODUCT_CATEGORY_LABELS[submission.category] ?? submission.category}</Block>
      <Block label="説明">{submission.description ?? EMPTY}</Block>
      <Block label="希望販売価格 (税込)">{yenOrEmpty(submission.desired_price)}</Block>
      <Block label="想定卸値 (任意)">{yenOrEmpty(submission.expected_wholesale_price)}</Block>
      <Block label="内容量">{submission.content_volume ?? EMPTY}</Block>
      <Block label="原材料">{submission.ingredients ?? EMPTY}</Block>
      <Block label="期限の目安">{submission.best_before_note ?? EMPTY}</Block>
    </dl>
  );
}

export function SubmissionProducerDetails({ submission }: { submission: SubmissionContent }) {
  return (
    <dl className="divide-y divide-border-soft">
      <Block label="生産者名">{submission.producer_name ?? EMPTY}</Block>
      <Block label="産地">{submission.producer_origin ?? EMPTY}</Block>
      <Block label="発送元 (都道府県)">{submission.producer_ship_from_prefecture ?? EMPTY}</Block>
      <Block label="発送目安">{submission.producer_ship_lead_time ?? EMPTY}</Block>
      <Block label="担当者名 (非公開)">{submission.producer_contact_name ?? EMPTY}</Block>
      <Block label="電話番号 (非公開)">{submission.producer_contact_phone ?? EMPTY}</Block>
      <Block label="メール (非公開)">{submission.producer_contact_email ?? EMPTY}</Block>
    </dl>
  );
}

export function SubmissionImageGallery({ images }: { images: SubmissionImageView[] }) {
  if (images.length === 0) return <p className="text-[13px] text-text-secondary">画像はありません。</p>;
  return (
    <ul className="grid grid-cols-3 gap-2 sm:grid-cols-5">
      {images.map((image) => (
        <li
          key={image.id}
          className="flex aspect-square items-center justify-center overflow-hidden rounded-xl border border-border-soft bg-surface-muted"
        >
          {image.url ? (
            <a href={image.url} target="_blank" rel="noopener noreferrer" className="block h-full w-full">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={image.url} alt="" className="h-full w-full object-cover" />
            </a>
          ) : (
            <ImageOff size={18} className="text-text-secondary" aria-label="画像を表示できません" />
          )}
        </li>
      ))}
    </ul>
  );
}

const ACTOR_LABELS: Record<string, string> = {
  agent: "代理店",
  super_admin: "運営",
  system: "システム",
};

export function SubmissionTimeline({
  events,
  renderExtra,
}: {
  events: SubmissionEvent[];
  /** 履歴ごとに追加表示する内容 (super_admin の差分表示など) */
  renderExtra?: (event: SubmissionEvent, index: number) => ReactNode;
}) {
  if (events.length === 0) return <p className="text-[13px] text-text-secondary">まだ履歴はありません。</p>;
  return (
    <ol className="space-y-3">
      {[...events].reverse().map((event, reversedIndex) => {
        const index = events.length - 1 - reversedIndex;
        return (
          <li key={`${event.changed_at}-${index}`} className="rounded-xl border border-border-soft px-3 py-2.5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-[14px] font-semibold text-text-primary">
                {SUBMISSION_STATUS_LABELS[event.to_status] ?? event.to_status}
                {event.to_status === "submitted" && event.revision > 1 ? ` (${event.revision} 回目)` : ""}
              </p>
              <p className="text-[12px] text-text-secondary">
                {ACTOR_LABELS[event.actor_role] ?? event.actor_role}・{formatDateTime(event.changed_at)}
              </p>
            </div>
            {event.reason ? (
              <p className="mt-1 whitespace-pre-wrap break-words text-[13px] leading-5 text-text-primary">
                {event.reason}
              </p>
            ) : null}
            {renderExtra?.(event, index)}
          </li>
        );
      })}
    </ol>
  );
}
