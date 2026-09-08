"use client";

import { X } from "lucide-react";
import { useEffect } from "react";

export function BottomSheet({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
}) {
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/40"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="animate-tm-sheet w-full max-w-md rounded-t-[28px] bg-surface p-5 pb-8 shadow-[var(--shadow-float)]"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        <div className="mx-auto mb-4 h-1.5 w-10 rounded-full bg-surface-muted" />
        {title ? (
          <div className="mb-3 flex items-center justify-between">
            <h3 className="text-[17px] font-bold text-text-primary">{title}</h3>
            <button
              type="button"
              onClick={onClose}
              aria-label="閉じる"
              className="text-text-secondary"
            >
              <X size={20} />
            </button>
          </div>
        ) : null}
        {children}
      </div>
    </div>
  );
}
