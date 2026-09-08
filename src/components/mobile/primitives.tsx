import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Mobile Design System (STEP5)
 * カード・数値・チップ・ボタンなど、スマホアプリ的な見た目の共通部品。
 * 既存の src/components/ui.tsx (PC管理画面向け) は admin 系ページで引き続き使用する。
 */

export function Surface({
  children,
  className = "",
  padded = true,
}: {
  children: ReactNode;
  className?: string;
  padded?: boolean;
}) {
  return (
    <section
      className={`rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)] ${
        padded ? "p-5" : ""
      } ${className}`}
    >
      {children}
    </section>
  );
}

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <h2 className="px-1 text-[13px] font-semibold tracking-wide text-text-secondary">
      {children}
    </h2>
  );
}

export function BigStat({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
}) {
  return (
    <div className="flex flex-col gap-0.5">
      <p className="text-[13px] text-text-secondary">{label}</p>
      <p className="text-[28px] font-bold leading-tight tabular-nums text-text-primary">{value}</p>
      {hint ? <p className="text-[13px] text-text-secondary">{hint}</p> : null}
    </div>
  );
}

const STATUS_TONE = {
  success: "bg-success-soft text-success",
  warning: "bg-warning-soft text-warning",
  danger: "bg-danger-soft text-danger",
  brand: "bg-brand-soft text-brand",
  neutral: "bg-surface-muted text-text-secondary",
} as const;

export function StatusPill({
  tone = "neutral",
  children,
}: {
  tone?: keyof typeof STATUS_TONE;
  children: ReactNode;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[12px] font-semibold ${STATUS_TONE[tone]}`}
    >
      {children}
    </span>
  );
}

export function PrimaryButton({
  children,
  href,
  onClick,
  type = "button",
  variant = "primary",
  disabled,
  className = "",
}: {
  children: ReactNode;
  href?: string;
  onClick?: () => void;
  type?: "button" | "submit";
  variant?: "primary" | "secondary" | "ghost";
  disabled?: boolean;
  className?: string;
}) {
  const base =
    "inline-flex w-full items-center justify-center gap-2 rounded-2xl px-5 text-[16px] font-semibold transition-colors h-13 min-h-13 disabled:cursor-not-allowed disabled:opacity-50";
  const variantCls =
    variant === "primary"
      ? "bg-brand text-brand-foreground hover:opacity-90"
      : variant === "secondary"
        ? "border border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
        : "text-brand hover:bg-brand-soft";

  const cls = `${base} ${variantCls} ${className}`;

  if (href) {
    return (
      <Link href={href} className={cls}>
        {children}
      </Link>
    );
  }

  return (
    <button type={type} onClick={onClick} disabled={disabled} className={cls}>
      {children}
    </button>
  );
}

export function Chip({
  children,
  selected = false,
  onClick,
  type = "button",
}: {
  children: ReactNode;
  selected?: boolean;
  onClick?: () => void;
  type?: "button" | "submit";
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      aria-pressed={selected}
      className={`inline-flex items-center justify-center rounded-2xl border px-4 py-2.5 text-[14px] font-medium transition-colors ${
        selected
          ? "border-brand bg-brand-soft text-brand"
          : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
      }`}
    >
      {children}
    </button>
  );
}

export function ProgressBar({ step, total }: { step: number; total: number }) {
  const pct = Math.min(100, Math.max(0, (step / total) * 100));
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between text-[13px] font-medium text-text-secondary">
        <span>
          {step} / {total}
        </span>
      </div>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
        <div
          className="h-full rounded-full bg-brand transition-[width] duration-300"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}

export function MobilePageHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <header className="flex items-start justify-between gap-3 px-1">
      <div>
        <h1 className="text-[26px] font-bold leading-tight tracking-tight text-text-primary">
          {title}
        </h1>
        {description ? (
          <p className="mt-1 text-[14px] leading-6 text-text-secondary">{description}</p>
        ) : null}
      </div>
      {action}
    </header>
  );
}

export function EmptyState({ title, description }: { title: string; description?: string }) {
  return (
    <div className="rounded-[20px] border border-dashed border-border-soft px-6 py-14 text-center">
      <p className="text-[15px] font-semibold text-text-primary">{title}</p>
      {description ? <p className="mt-1.5 text-[13px] text-text-secondary">{description}</p> : null}
    </div>
  );
}
