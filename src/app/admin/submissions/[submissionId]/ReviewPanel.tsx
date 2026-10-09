"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import { PRODUCT_CATEGORIES, PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import type { ProducerPublicRow, SubmissionImageView } from "@/lib/domain/types";

type Candidate = ProducerPublicRow & { similarity: number };
type Action = "approve" | "return" | "reject";
type ProducerChoice = { kind: "candidate"; id: string } | { kind: "other" } | { kind: "new" } | null;

const TABS: { key: Action; label: string }[] = [
  { key: "approve", label: "承認" },
  { key: "return", label: "差し戻し" },
  { key: "reject", label: "却下" },
];

function producerLine(p: ProducerPublicRow) {
  return `${p.name} (${p.origin ?? "—"} / 発送元: ${p.ship_from_prefecture ?? "—"})`;
}

/**
 * 持込み申請の審査 (super_admin 専用ページから使う。API と DB でも super_admin を再判定)。
 *   承認     : 生産者を「似た名前の既存生産者」「その他の既存生産者」「新規作成」から明示的に選ぶ。
 *              商品は在庫 0・非公開で作られる。画像は選んだ 1 枚だけを公開用バケットへコピーする。
 *   差し戻し : 理由必須。代理店は修正して再申請できる。
 *   却下     : 理由必須。再申請できない。
 * 承認・差し戻し・却下の理由は、いずれも代理店の画面に表示される。
 */
export function ReviewPanel({
  submission,
  candidates,
  otherProducers,
  images,
}: {
  submission: {
    id: string;
    name: string;
    category: string;
    desired_price: number | null;
    producer_name: string | null;
    producer_origin: string | null;
    producer_ship_from_prefecture: string | null;
    producer_ship_lead_time: string | null;
  };
  candidates: Candidate[];
  otherProducers: ProducerPublicRow[];
  images: SubmissionImageView[];
}) {
  const router = useRouter();
  const [action, setAction] = useState<Action>("approve");
  const [choice, setChoice] = useState<ProducerChoice>(candidates.length > 0 ? null : { kind: "new" });
  const [otherId, setOtherId] = useState("");
  const [productName, setProductName] = useState(submission.name);
  const [category, setCategory] = useState(submission.category);
  const [price, setPrice] = useState(submission.desired_price != null ? String(Number(submission.desired_price)) : "");
  const [imageId, setImageId] = useState<string>("");
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [approved, setApproved] = useState<{ productId: string; imageError: string | null } | null>(null);

  function switchAction(next: Action) {
    setAction(next);
    setReason("");
    setError(null);
  }

  async function post(path: string, body: Record<string, unknown>) {
    setPending(true);
    setError(null);
    const response = await fetch(`/api/admin/submissions/${submission.id}/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await response.json().catch(() => null);
    setPending(false);
    if (!response.ok) {
      setError(data?.error?.message ?? "処理に失敗しました。");
      return null;
    }
    return data;
  }

  async function handleApprove(event: React.FormEvent) {
    event.preventDefault();
    if (!choice) {
      setError("生産者を選んでください。");
      return;
    }
    const producerId = choice.kind === "candidate" ? choice.id : choice.kind === "other" ? otherId : null;
    if (choice.kind !== "new" && !producerId) {
      setError("既存の生産者を選んでください。");
      return;
    }
    if (!window.confirm("この申請を承認します。生産者と商品 (非公開・在庫 0) が作成されます。よろしいですか？")) return;

    const data = await post("approve", {
      producer_mode: choice.kind === "new" ? "new" : "existing",
      producer_id: producerId,
      product_name: productName,
      price,
      category,
      image_id: imageId || null,
      reason: reason || null,
    });
    if (!data) return;
    setApproved({ productId: data.product_id, imageError: data.image_error ?? null });
    router.refresh();
  }

  async function handleReview(event: React.FormEvent) {
    event.preventDefault();
    const label = action === "return" ? "差し戻し" : "却下";
    if (!window.confirm(`この申請を${label}します。よろしいですか？`)) return;
    const data = await post(action, { reason });
    if (!data) return;
    router.refresh();
  }

  if (approved) {
    return (
      <div className="space-y-3">
        <FormMessage tone="success">承認しました。商品を非公開・在庫 0 で作成しました。</FormMessage>
        {approved.imageError ? (
          <FormMessage tone="error">
            画像のコピーに失敗しました: {approved.imageError} 商品の編集画面から画像を設定してください。
          </FormMessage>
        ) : null}
        <Link href={`/admin/products/${approved.productId}`} className={BUTTON_CLASS}>
          商品の価格・在庫を確定する
        </Link>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div role="tablist" className="grid grid-cols-3 gap-1 rounded-xl bg-surface-muted p-1">
        {TABS.map((tab) => (
          <button
            key={tab.key}
            type="button"
            role="tab"
            aria-selected={action === tab.key}
            onClick={() => switchAction(tab.key)}
            className={`rounded-lg px-3 py-2 text-[14px] font-semibold transition-colors ${
              action === tab.key ? "bg-surface text-text-primary shadow" : "text-text-secondary"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {action === "approve" ? (
        <form onSubmit={handleApprove} className="space-y-5">
          <fieldset className="space-y-2">
            <legend className="mb-1 text-[14px] font-semibold text-text-primary">生産者</legend>
            {candidates.length > 0 ? (
              <p className="rounded-xl border border-warning/30 bg-warning-soft px-3 py-2.5 text-[13px] leading-5 text-text-primary">
                申請の生産者「{submission.producer_name}」と似た名前の生産者が登録されています。
                同じ生産者であれば既存の生産者を選んでください (重複して登録しないため)。
              </p>
            ) : null}

            {candidates.map((p) => (
              <label
                key={p.id}
                className="flex cursor-pointer items-start gap-3 rounded-xl border border-border-soft px-3 py-2.5"
              >
                <input
                  type="radio"
                  name="producer"
                  checked={choice?.kind === "candidate" && choice.id === p.id}
                  onChange={() => setChoice({ kind: "candidate", id: p.id })}
                  className="mt-1 accent-[var(--brand)]"
                />
                <span className="text-[14px] text-text-primary">
                  <span className="font-semibold">既存: {p.name}</span>
                  <span className="ml-1 text-[12px] text-text-secondary">(類似度 {Math.round(p.similarity * 100)}%)</span>
                  <span className="block text-[12px] text-text-secondary">
                    産地 {p.origin ?? "—"} / 発送元 {p.ship_from_prefecture ?? "—"} / 発送目安 {p.ship_lead_time ?? "—"}
                  </span>
                </span>
              </label>
            ))}

            <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-border-soft px-3 py-2.5">
              <input
                type="radio"
                name="producer"
                checked={choice?.kind === "other"}
                onChange={() => setChoice({ kind: "other" })}
                className="mt-1 accent-[var(--brand)]"
              />
              <span className="flex-1 space-y-2 text-[14px] text-text-primary">
                <span className="font-semibold">{candidates.length > 0 ? "その他の既存生産者を選ぶ" : "既存の生産者を選ぶ"}</span>
                {choice?.kind === "other" ? (
                  <select value={otherId} onChange={(e) => setOtherId(e.target.value)} className={FIELD_CLASS}>
                    <option value="">選択してください</option>
                    {otherProducers.map((p) => (
                      <option key={p.id} value={p.id}>
                        {producerLine(p)}
                      </option>
                    ))}
                  </select>
                ) : null}
              </span>
            </label>

            <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-border-soft px-3 py-2.5">
              <input
                type="radio"
                name="producer"
                checked={choice?.kind === "new"}
                onChange={() => setChoice({ kind: "new" })}
                className="mt-1 accent-[var(--brand)]"
              />
              <span className="text-[14px] text-text-primary">
                <span className="font-semibold">新規作成 (申請の生産者情報から作成)</span>
                <span className="block text-[12px] text-text-secondary">
                  {submission.producer_name} / 産地 {submission.producer_origin} / 発送元{" "}
                  {submission.producer_ship_from_prefecture} / 発送目安 {submission.producer_ship_lead_time}
                  。連絡先は super_admin 専用の項目に引き継がれます。
                </span>
              </span>
            </label>
          </fieldset>

          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="商品名" className="sm:col-span-2">
              <input required value={productName} onChange={(e) => setProductName(e.target.value)} maxLength={100} className={FIELD_CLASS} />
            </Field>
            <Field label="価格 (円・税込。仮の価格。公開前に商品管理で確定してください)">
              <input
                required
                type="number"
                min={0}
                step={1}
                inputMode="numeric"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                className={FIELD_CLASS}
              />
            </Field>
            <Field label="カテゴリ">
              <select value={category} onChange={(e) => setCategory(e.target.value)} className={FIELD_CLASS}>
                {PRODUCT_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {PRODUCT_CATEGORY_LABELS[c]}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <fieldset className="space-y-2">
            <legend className="mb-1 text-[14px] font-semibold text-text-primary">
              商品画像{" "}
              <span className="text-[12px] font-normal text-text-secondary">
                (選んだ 1 枚だけを公開用の保存先へコピーします。それ以外の画像は公開されません)
              </span>
            </legend>
            <div className="flex flex-wrap gap-2">
              <label
                className={`flex h-20 w-20 cursor-pointer items-center justify-center rounded-xl border text-[12px] ${
                  imageId === "" ? "border-brand bg-brand-soft text-brand" : "border-border-soft text-text-secondary"
                }`}
              >
                <input type="radio" name="image" className="sr-only" checked={imageId === ""} onChange={() => setImageId("")} />
                使わない
              </label>
              {images
                .filter((image) => image.url)
                .map((image) => (
                  <label
                    key={image.id}
                    className={`h-20 w-20 cursor-pointer overflow-hidden rounded-xl border-2 ${
                      imageId === image.id ? "border-brand" : "border-transparent"
                    }`}
                  >
                    <input
                      type="radio"
                      name="image"
                      className="sr-only"
                      checked={imageId === image.id}
                      onChange={() => setImageId(image.id)}
                    />
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={image.url ?? ""} alt="" className="h-full w-full object-cover" />
                  </label>
                ))}
            </div>
          </fieldset>

          <Field label="承認理由 (任意・代理店にも表示されます)">
            <textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} className={FIELD_CLASS} />
          </Field>

          {error ? <FormMessage tone="error">{error}</FormMessage> : null}
          <button type="submit" disabled={pending || !choice} className={BUTTON_CLASS}>
            {pending ? "処理中…" : "承認する"}
          </button>
        </form>
      ) : (
        <form onSubmit={handleReview} className="space-y-4">
          <p className="text-[13px] leading-5 text-text-secondary">
            {action === "return"
              ? "差し戻すと、代理店が内容を修正して再申請できます。"
              : "却下すると、この申請は再申請できなくなります。"}
          </p>
          <Field label={`${action === "return" ? "差し戻し" : "却下"}の理由 (必須・代理店にも表示されます)`}>
            <textarea
              required
              rows={4}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              maxLength={1000}
              className={FIELD_CLASS}
            />
          </Field>
          {error ? <FormMessage tone="error">{error}</FormMessage> : null}
          <button type="submit" disabled={pending || !reason.trim()} className={BUTTON_CLASS}>
            {pending ? "処理中…" : action === "return" ? "差し戻す" : "却下する"}
          </button>
        </form>
      )}
    </div>
  );
}
