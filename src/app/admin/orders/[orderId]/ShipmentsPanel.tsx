"use client";

import { Check, Copy, Truck } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { Badge, BUTTON_CLASS, FIELD_CLASS, Field, FormMessage, formatDate, formatDateTime } from "@/components/ui";
import { SHIPMENT_STATUS_LABELS, type OrderStatus, type ShipmentStatus } from "@/lib/domain/enums";
import type { OrderShipmentRow, ShipmentRequest } from "@/lib/domain/types";
import { formatShipmentRequest } from "@/lib/shop/shipment-request";

const STATUS_TONE: Record<ShipmentStatus, "neutral" | "amber" | "blue" | "green" | "red"> = {
  awaiting_payment: "neutral",
  ready: "amber",
  requested: "blue",
  shipped: "green",
  cancelled: "red",
};

type ItemLine = { id: string; product_name: string; product_content_volume: string | null; quantity: number };

/**
 * 生産者ごとの発送管理 (super_admin 専用ページから使う)。
 * 発送依頼書の表示・コピー → 「依頼済みにする」 → 発送登録 (発送日・配送業者・送り状番号)。
 * 全生産者の発送登録が終わると、DB 側で注文が自動的に「発送済み」になる。
 * メールでの自動送信 (STEP6) は未実装のため、依頼は手動 (コピーして送る) で行う。
 */
export function ShipmentsPanel({
  shipments,
  requests,
  itemsByProducer,
  orderStatus,
  today,
}: {
  shipments: OrderShipmentRow[];
  requests: Record<string, ShipmentRequest>;
  itemsByProducer: Record<string, ItemLine[]>;
  orderStatus: OrderStatus;
  /** 日本時間の今日 (YYYY-MM-DD)。発送日の初期値・上限 */
  today: string;
}) {
  return (
    <div className="space-y-4">
      {shipments.map((s) => (
        <ShipmentCard
          key={s.id}
          shipment={s}
          request={requests[s.id]}
          items={itemsByProducer[s.producer_id] ?? []}
          orderStatus={orderStatus}
          today={today}
        />
      ))}
    </div>
  );
}

function ShipmentCard({
  shipment: s,
  request,
  items,
  orderStatus,
  today,
}: {
  shipment: OrderShipmentRow;
  request: ShipmentRequest | undefined;
  items: ItemLine[];
  orderStatus: OrderStatus;
  today: string;
}) {
  const router = useRouter();
  const [showSheet, setShowSheet] = useState(false);
  const [copied, setCopied] = useState(false);
  const [editing, setEditing] = useState(false);
  const [shipForm, setShipForm] = useState({
    shipped_on: s.shipped_on ?? today,
    carrier: s.carrier ?? "",
    tracking_number: s.tracking_number ?? "",
    reason: "",
  });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const open = s.status === "ready" || s.status === "requested";
  const canShip = open && orderStatus === "payment_confirmed";
  const canCorrect = s.status === "shipped" && ["payment_confirmed", "shipped", "completed"].includes(orderStatus);
  const sheet = request ? formatShipmentRequest(request) : null;

  async function post(url: string, body?: unknown) {
    setPending(true);
    setError(null);
    setDone(null);
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await response.json().catch(() => null);
    setPending(false);
    if (!response.ok) {
      setError(json?.error?.message ?? "処理に失敗しました。");
      return null;
    }
    return json;
  }

  async function copySheet() {
    if (!sheet) return;
    try {
      await navigator.clipboard.writeText(sheet);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("コピーできませんでした。表示されたテキストを選択してコピーしてください。");
      setShowSheet(true);
    }
  }

  async function markRequested() {
    const json = await post(`/api/admin/shipments/${s.id}/request`);
    if (!json) return;
    setDone("発送依頼済みとして記録しました。");
    router.refresh();
  }

  async function submitShip(event: React.FormEvent) {
    event.preventDefault();
    const json = await post(`/api/admin/shipments/${s.id}/ship`, shipForm);
    if (!json) return;
    setDone(
      json.order_status === "shipped" && orderStatus !== "shipped"
        ? "発送を登録しました。全生産者の発送が完了したため、注文を「発送済み」にしました。"
        : canCorrect
          ? "発送記録を訂正しました。"
          : "発送を登録しました。",
    );
    setEditing(false);
    router.refresh();
  }

  const showShipForm = canShip || (canCorrect && editing);

  return (
    <section className="rounded-2xl border border-border-soft p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-[15px] font-semibold text-text-primary">{s.producer_name}</p>
          <p className="text-[12px] text-text-secondary">
            {s.is_placeholder
              ? "運営から発送 (依頼書は不要)"
              : `発送目安: ${s.ship_lead_time ?? "—"}${s.producer_active ? "" : " ・ ※生産者は無効になっています"}`}
          </p>
        </div>
        <Badge tone={STATUS_TONE[s.status]}>{SHIPMENT_STATUS_LABELS[s.status]}</Badge>
      </div>

      <ul className="mt-3 space-y-1 text-[13px] text-text-primary">
        {items.map((item) => (
          <li key={item.id}>
            ・{item.product_name}
            {item.product_content_volume ? (
              <span className="text-text-secondary"> ({item.product_content_volume})</span>
            ) : null}{" "}
            × {item.quantity}
          </li>
        ))}
      </ul>

      {!s.is_placeholder && s.status !== "awaiting_payment" && s.status !== "cancelled" ? (
        <div className="mt-3 space-y-1 text-[12px] text-text-secondary">
          <p>
            依頼の送り先メール: {s.has_notify_email ? "設定済み (メール自動送信は準備中のため、依頼書をコピーして連絡してください)" : "未設定 (依頼書をコピーして連絡してください)"}
          </p>
          {s.requested_at ? (
            <p>
              依頼済み: {formatDateTime(s.requested_at)} ({s.request_channel === "email" ? "メール" : "手動"}
              {s.request_count > 1 ? `・${s.request_count} 回目` : ""})
            </p>
          ) : null}
          {s.last_notify_error ? <p className="text-danger">前回の送信エラー: {s.last_notify_error}</p> : null}
        </div>
      ) : null}

      {s.status === "shipped" ? (
        <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-[13px]">
          <dt className="text-text-secondary">発送日</dt>
          <dd className="text-text-primary">{formatDate(s.shipped_on)}</dd>
          <dt className="text-text-secondary">配送業者</dt>
          <dd className="text-text-primary">{s.carrier ?? "—"}</dd>
          <dt className="text-text-secondary">送り状番号</dt>
          <dd className="font-mono text-text-primary">{s.tracking_number ?? "—"}</dd>
        </dl>
      ) : null}

      {s.status === "awaiting_payment" ? (
        <p className="mt-3 text-[12px] text-text-secondary">入金確認後に発送依頼ができるようになります。</p>
      ) : null}

      {sheet && !s.is_placeholder && s.status !== "shipped" ? (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setShowSheet((v) => !v)}
            className="rounded-xl border border-border-soft px-3 py-2 text-[13px] font-medium text-text-primary hover:bg-surface-muted"
          >
            {showSheet ? "発送依頼書を閉じる" : "発送依頼書を表示"}
          </button>
          <button
            type="button"
            onClick={copySheet}
            className="inline-flex items-center gap-1.5 rounded-xl border border-border-soft px-3 py-2 text-[13px] font-medium text-text-primary hover:bg-surface-muted"
          >
            {copied ? <Check size={14} /> : <Copy size={14} />}
            {copied ? "コピーしました" : "依頼書をコピー"}
          </button>
          {open ? (
            <button
              type="button"
              disabled={pending}
              onClick={markRequested}
              className="rounded-xl border border-brand px-3 py-2 text-[13px] font-semibold text-brand hover:bg-brand-soft disabled:opacity-50"
            >
              {s.status === "requested" ? "再依頼したことを記録" : "依頼済みにする"}
            </button>
          ) : null}
        </div>
      ) : null}

      {showSheet && sheet ? (
        <pre className="mt-3 max-h-80 overflow-auto whitespace-pre-wrap rounded-xl bg-surface-muted p-3 text-[12px] leading-5 text-text-primary">
          {sheet}
        </pre>
      ) : null}

      {canCorrect && !editing ? (
        <button
          type="button"
          onClick={() => setEditing(true)}
          className="mt-3 text-[13px] font-semibold text-brand hover:underline"
        >
          発送記録を訂正する
        </button>
      ) : null}

      {showShipForm ? (
        <form onSubmit={submitShip} className="mt-4 space-y-3 rounded-xl bg-surface-muted/60 p-3">
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="発送日">
              <input
                required
                type="date"
                max={today}
                value={shipForm.shipped_on}
                onChange={(e) => setShipForm((f) => ({ ...f, shipped_on: e.target.value }))}
                className={FIELD_CLASS}
              />
            </Field>
            <Field label="配送業者 (任意)">
              <input
                value={shipForm.carrier}
                onChange={(e) => setShipForm((f) => ({ ...f, carrier: e.target.value }))}
                className={FIELD_CLASS}
                placeholder="例: ヤマト運輸"
              />
            </Field>
            <Field label="送り状番号 (任意)">
              <input
                value={shipForm.tracking_number}
                onChange={(e) => setShipForm((f) => ({ ...f, tracking_number: e.target.value }))}
                className={FIELD_CLASS}
              />
            </Field>
          </div>
          {canCorrect ? (
            <Field label="訂正理由 (必須・監査ログに記録されます)">
              <input
                required
                value={shipForm.reason}
                onChange={(e) => setShipForm((f) => ({ ...f, reason: e.target.value }))}
                className={FIELD_CLASS}
              />
            </Field>
          ) : null}
          <div className="flex gap-2">
            <button
              type="submit"
              disabled={pending || !shipForm.shipped_on || (canCorrect && !shipForm.reason.trim())}
              className={BUTTON_CLASS}
            >
              <Truck size={16} />
              {pending ? "登録中…" : canCorrect ? "訂正を保存" : "発送済みにする"}
            </button>
            {canCorrect ? (
              <button
                type="button"
                onClick={() => setEditing(false)}
                className="rounded-xl border border-border-soft px-4 py-2.5 text-[14px] font-medium text-text-primary"
              >
                やめる
              </button>
            ) : null}
          </div>
        </form>
      ) : null}

      {error ? (
        <div className="mt-3">
          <FormMessage tone="error">{error}</FormMessage>
        </div>
      ) : null}
      {done ? (
        <div className="mt-3">
          <FormMessage tone="success">{done}</FormMessage>
        </div>
      ) : null}
    </section>
  );
}
