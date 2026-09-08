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

export function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: string }) {
  return (
    <div className="rounded-[20px] border border-border-soft bg-surface p-4 shadow-[var(--shadow-card)]">
      <p className="text-[13px] text-text-secondary">{label}</p>
      <p className="mt-1 text-[26px] font-bold tabular-nums text-text-primary">{value}</p>
      {hint ? <p className="mt-1 text-[13px] text-text-secondary">{hint}</p> : null}
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
    <div className="overflow-x-auto rounded-[20px] border border-border-soft">
      <table className="w-full min-w-[42rem] border-collapse text-sm">
        <thead className="bg-surface-muted">
          <tr>
            {headers.map((h) => (
              <th
                key={h}
                className="whitespace-nowrap px-4 py-2.5 text-left text-[12px] font-semibold text-text-secondary"
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border-soft">{children}</tbody>
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
