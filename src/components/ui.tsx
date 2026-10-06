import Link from "next/link";
import type { ReactNode } from "react";

export function PageHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <header className="flex flex-wrap items-start justify-between gap-4 border-b border-border-soft pb-5">
      <div>
        <h1 className="text-[22px] font-bold tracking-tight text-text-primary">{title}</h1>
        {description ? (
          <p className="mt-1.5 max-w-2xl text-[14px] leading-6 text-text-secondary">
            {description}
          </p>
        ) : null}
      </div>
      {action}
    </header>
  );
}

export function Card({
  title,
  description,
  children,
  className = "",
}: {
  title?: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`rounded-[20px] border border-border-soft bg-surface p-5 shadow-[var(--shadow-card)] ${className}`}
    >
      {title ? (
        <div className="mb-4">
          <h2 className="text-[15px] font-semibold text-text-primary">{title}</h2>
          {description ? (
            <p className="mt-1 text-[13px] leading-5 text-text-secondary">{description}</p>
          ) : null}
        </div>
      ) : null}
      {children}
    </section>
  );
}

export function Stat({
  label,
  value,
  hint,
  icon,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  icon?: ReactNode;
}) {
  return (
    <div className="rounded-[20px] border border-border-soft bg-surface p-4 shadow-[var(--shadow-card)] md:p-5">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[13px] font-medium text-text-secondary">{label}</p>
        {icon ? (
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-soft text-brand">
            {icon}
          </span>
        ) : null}
      </div>
      <p className="mt-2 text-[28px] font-bold leading-tight tabular-nums text-text-primary">{value}</p>
      {hint ? <p className="mt-1 text-[12px] text-text-secondary">{hint}</p> : null}
    </div>
  );
}

const TONE_CLASSES = {
  neutral: "bg-surface-muted text-text-secondary",
  green: "bg-success-soft text-success",
  amber: "bg-warning-soft text-warning",
  red: "bg-danger-soft text-danger",
  blue: "bg-brand-soft text-brand",
} as const;

/** 代理店ステータス → Badge の色。 */
export const AGENT_STATUS_TONE: Record<string, keyof typeof TONE_CLASSES> = {
  active: "green",
  pending: "amber",
  suspended: "red",
  withdrawn: "neutral",
};

export function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: keyof typeof TONE_CLASSES;
}) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${TONE_CLASSES[tone]}`}
    >
      {children}
    </span>
  );
}

export function EmptyState({ title, description }: { title: string; description?: string }) {
  return (
    <div className="rounded-[20px] border border-dashed border-border-soft px-6 py-12 text-center">
      <p className="text-[14px] font-medium text-text-primary">{title}</p>
      {description ? <p className="mt-1 text-[13px] text-text-secondary">{description}</p> : null}
    </div>
  );
}

export function Notice({
  tone = "info",
  children,
}: {
  tone?: "info" | "warning" | "danger";
  children: ReactNode;
}) {
  const cls = {
    info: "border-brand/25 bg-brand-soft text-text-primary",
    warning: "border-warning-soft bg-warning-soft text-text-primary",
    danger: "border-danger-soft bg-danger-soft text-text-primary",
  }[tone];

  return <div className={`rounded-2xl border px-4 py-3 text-[14px] leading-6 ${cls}`}>{children}</div>;
}

export function DataTable({
  headers,
  children,
}: {
  headers: string[];
  children: ReactNode;
}) {
  return (
    <div className="overflow-x-auto rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)]">
      <table className="w-full min-w-[42rem] border-collapse text-sm">
        <thead className="bg-surface-muted">
          <tr>
            {headers.map((h) => (
              <th
                key={h}
                className="whitespace-nowrap px-4 py-3 text-left text-[12px] font-semibold tracking-wide text-text-secondary"
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border-soft [&>tr]:transition-colors [&>tr:hover]:bg-surface-muted/60">
          {children}
        </tbody>
      </table>
    </div>
  );
}

export function LinkButton({
  href,
  children,
  variant = "primary",
}: {
  href: string;
  children: ReactNode;
  variant?: "primary" | "secondary";
}) {
  const cls =
    variant === "primary"
      ? "bg-brand text-brand-foreground hover:opacity-90"
      : "border border-border-soft text-text-primary hover:bg-surface-muted";

  return (
    <Link
      href={href}
      className={`inline-flex items-center rounded-2xl px-4 py-2.5 text-[14px] font-medium transition-colors ${cls}`}
    >
      {children}
    </Link>
  );
}

export function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
}

export function formatDateTime(value: string | null | undefined) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

export function formatYen(value: number | null | undefined) {
  if (value == null) return "—";
  return new Intl.NumberFormat("ja-JP", {
    style: "currency",
    currency: "JPY",
    maximumFractionDigits: 0,
  }).format(value);
}

/* ---------------------------------------------------------------------------
 * 管理画面向けの共通部品 (見た目のみ。データ・権限ロジックは各ページ/API 側)
 * ------------------------------------------------------------------------- */

/** input / select / textarea 共通の見た目。 */
export const FIELD_CLASS =
  "w-full rounded-xl border border-border-soft bg-surface px-3 py-2.5 text-[14px] text-text-primary outline-none transition-colors placeholder:text-text-secondary/70 focus:border-brand focus:ring-2 focus:ring-brand/15";

/** 主要アクションボタン。 */
export const BUTTON_CLASS =
  "inline-flex items-center justify-center gap-1.5 rounded-xl bg-brand px-4 py-2.5 text-[14px] font-semibold text-brand-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50";

/** テーブルのセル。 */
export const TD = "px-4 py-3 align-top text-[13px] text-text-secondary";
export const TD_STRONG = "px-4 py-3 align-top text-[14px] font-medium text-text-primary";

export function Field({
  label,
  className = "",
  children,
}: {
  label: string;
  className?: string;
  children: ReactNode;
}) {
  return (
    <label className={`block ${className}`}>
      <span className="mb-1.5 block text-[12px] font-semibold text-text-secondary">{label}</span>
      {children}
    </label>
  );
}

export function FormMessage({
  tone,
  children,
}: {
  tone: "error" | "success";
  children: ReactNode;
}) {
  const cls =
    tone === "error"
      ? "border-danger/25 bg-danger-soft text-danger"
      : "border-success/25 bg-success-soft text-success";
  return (
    <p role={tone === "error" ? "alert" : "status"} className={`rounded-xl border px-3 py-2.5 text-[13px] font-medium ${cls}`}>
      {children}
    </p>
  );
}

/** 検索・絞り込みフォームの外枠。 */
export function FilterPanel({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-[20px] border border-border-soft bg-surface p-4 shadow-[var(--shadow-card)]">
      {children}
    </div>
  );
}

export function SectionTitle({ children, count }: { children: ReactNode; count?: number }) {
  return (
    <h2 className="flex items-center gap-2 px-1 text-[15px] font-semibold text-text-primary">
      {children}
      {count != null ? (
        <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[12px] font-medium tabular-nums text-text-secondary">
          {count}
        </span>
      ) : null}
    </h2>
  );
}

export function DetailList({ children }: { children: ReactNode }) {
  return <dl className="divide-y divide-border-soft">{children}</dl>;
}

export function DetailRow({
  label,
  value,
  mono = false,
}: {
  label: string;
  value: ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex items-start justify-between gap-4 py-2.5">
      <dt className="shrink-0 text-[13px] text-text-secondary">{label}</dt>
      <dd
        className={`min-w-0 break-words text-right text-[14px] font-medium text-text-primary ${
          mono ? "font-mono" : ""
        }`}
      >
        {value}
      </dd>
    </div>
  );
}

export function TextLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link href={href} className="font-medium text-brand hover:underline">
      {children}
    </Link>
  );
}

export function BackLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex items-center gap-1 text-[13px] font-medium text-text-secondary transition-colors hover:text-text-primary"
    >
      <span aria-hidden>←</span>
      {children}
    </Link>
  );
}

/** 代理店IDのような識別子を小さく等幅で表示する。 */
export function Mono({ children }: { children: ReactNode }) {
  return <span className="font-mono text-[12px] text-text-secondary">{children}</span>;
}
