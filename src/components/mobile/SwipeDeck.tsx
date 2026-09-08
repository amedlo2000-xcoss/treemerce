"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useRef, useState } from "react";

/**
 * カードスワイプ (STEP4/5共通)。
 * 「閲覧対象の切り替え」だけを行い、LIKE/NOPE/担当変更などの意味は一切持たせない。
 */
export function SwipeDeck<T>({
  items,
  keyFor,
  renderCard,
}: {
  items: T[];
  keyFor: (item: T, index: number) => string;
  renderCard: (item: T, index: number) => React.ReactNode;
}) {
  const [index, setIndex] = useState(0);
  const [dragX, setDragX] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const startX = useRef<number | null>(null);

  const clamp = (i: number) => Math.max(0, Math.min(items.length - 1, i));
  const goTo = (i: number) => setIndex(clamp(i));

  function onPointerDown(e: React.PointerEvent) {
    startX.current = e.clientX;
    setIsDragging(true);
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }

  function onPointerMove(e: React.PointerEvent) {
    if (startX.current === null) return;
    setDragX(e.clientX - startX.current);
  }

  function onPointerUp() {
    if (startX.current === null) return;
    setIsDragging(false);
    const threshold = 80;
    if (dragX <= -threshold) goTo(index + 1);
    else if (dragX >= threshold) goTo(index - 1);
    setDragX(0);
    startX.current = null;
  }

  if (items.length === 0) return null;

  const current = items[index];
  const next = items[index + 1];

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-center">
        <span className="rounded-full bg-surface-muted px-3 py-1 text-[13px] font-medium tabular-nums text-text-secondary">
          {index + 1} / {items.length}
        </span>
      </div>

      <div className="relative h-[440px] select-none">
        {next ? (
          <div
            key={keyFor(next, index + 1)}
            className="absolute inset-x-3 top-3 h-full scale-[0.96] opacity-60"
            aria-hidden
          >
            {renderCard(next, index + 1)}
          </div>
        ) : null}
        <div
          key={keyFor(current, index)}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
          className="absolute inset-0 touch-pan-y transition-transform duration-200 ease-out"
          style={{
            transform: `translateX(${dragX}px) rotate(${dragX / 30}deg)`,
            transitionDuration: isDragging ? "0ms" : "200ms",
          }}
        >
          {renderCard(current, index)}
        </div>
      </div>

      <div className="flex items-center justify-center gap-4">
        <button
          type="button"
          onClick={() => goTo(index - 1)}
          disabled={index === 0}
          aria-label="前の登録者"
          className="flex h-12 w-12 items-center justify-center rounded-full border border-border-soft bg-surface text-text-primary disabled:opacity-30"
        >
          <ChevronLeft size={22} />
        </button>
        <button
          type="button"
          onClick={() => goTo(index + 1)}
          disabled={index === items.length - 1}
          aria-label="次の登録者"
          className="flex h-12 w-12 items-center justify-center rounded-full border border-border-soft bg-surface text-text-primary disabled:opacity-30"
        >
          <ChevronRight size={22} />
        </button>
      </div>
    </div>
  );
}
