"use client";

import { ImageOff, ImagePlus, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import type { SubmissionImageView } from "@/lib/domain/types";
import {
  SUBMISSION_IMAGE_BUCKET,
  SUBMISSION_IMAGE_MAX_BYTES,
  SUBMISSION_IMAGE_MAX_COUNT,
  SUBMISSION_IMAGE_TYPES,
} from "@/lib/submission-images";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

/**
 * 申請画像の追加・削除 (本人の下書き・差し戻しのみ)。
 *   1. API で枠を確保 (RPC が所有者・状態・5 枚の上限を確認し、保存先パスを返す)
 *   2. そのパスへブラウザから非公開バケットにアップロード (Storage の権限が枠の有無を確認)
 *   3. アップロードに失敗したら枠を削除して戻す
 */
export function SubmissionImagesEditor({
  submissionId,
  images,
}: {
  submissionId: string;
  images: SubmissionImageView[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function releaseSlot(imageId: string) {
    await fetch(`/api/agent/submission-images/${imageId}`, { method: "DELETE" }).catch(() => null);
  }

  async function handleAdd(file: File | undefined) {
    if (!file) return;
    setError(null);
    if (!SUBMISSION_IMAGE_TYPES[file.type]) {
      setError("画像は JPEG・PNG・WebP のみ登録できます。");
      return;
    }
    if (file.size > SUBMISSION_IMAGE_MAX_BYTES) {
      setError("画像は 5MB 以下にしてください。");
      return;
    }

    setBusy("add");
    const response = await fetch(`/api/agent/submissions/${submissionId}/images`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ content_type: file.type }),
    });
    const slot = await response.json().catch(() => null);
    if (!response.ok) {
      setBusy(null);
      setError(slot?.error?.message ?? "画像を追加できませんでした。");
      return;
    }

    const { error: uploadError } = await getSupabaseBrowserClient()
      .storage.from(SUBMISSION_IMAGE_BUCKET)
      .upload(slot.storage_path, file, { contentType: file.type, upsert: false });
    if (uploadError) {
      await releaseSlot(slot.image_id);
      setBusy(null);
      setError("画像のアップロードに失敗しました。通信状況を確認して、もう一度お試しください。");
      router.refresh();
      return;
    }

    setBusy(null);
    router.refresh();
  }

  async function handleRemove(imageId: string) {
    if (!window.confirm("この画像を削除しますか？")) return;
    setError(null);
    setBusy(imageId);
    const response = await fetch(`/api/agent/submission-images/${imageId}`, { method: "DELETE" });
    const body = await response.json().catch(() => null);
    setBusy(null);
    if (!response.ok) {
      setError(body?.error?.message ?? "画像を削除できませんでした。");
      return;
    }
    router.refresh();
  }

  const full = images.length >= SUBMISSION_IMAGE_MAX_COUNT;

  return (
    <div className="space-y-3">
      <ul className="grid grid-cols-3 gap-2">
        {images.map((image) => (
          <li
            key={image.id}
            className="relative flex aspect-square items-center justify-center overflow-hidden rounded-2xl border border-border-soft bg-surface-muted"
          >
            {image.url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={image.url} alt="" className="h-full w-full object-cover" />
            ) : (
              <span className="flex flex-col items-center gap-1 px-2 text-center text-[11px] text-text-secondary">
                <ImageOff size={18} />
                表示できません
              </span>
            )}
            <button
              type="button"
              onClick={() => handleRemove(image.id)}
              disabled={busy !== null}
              aria-label="画像を削除"
              className="absolute right-1.5 top-1.5 flex h-8 w-8 items-center justify-center rounded-full bg-surface/90 text-text-secondary shadow disabled:opacity-50"
            >
              <Trash2 size={15} />
            </button>
          </li>
        ))}
        {!full ? (
          <li>
            <label
              className={`flex aspect-square cursor-pointer flex-col items-center justify-center gap-1 rounded-2xl border border-dashed border-border-soft text-[12px] text-text-secondary transition-colors hover:bg-surface-muted ${
                busy !== null ? "pointer-events-none opacity-50" : ""
              }`}
            >
              <ImagePlus size={22} />
              {busy === "add" ? "追加中…" : "画像を追加"}
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="sr-only"
                disabled={busy !== null}
                onChange={(e) => {
                  void handleAdd(e.target.files?.[0]);
                  e.target.value = "";
                }}
              />
            </label>
          </li>
        ) : null}
      </ul>
      <p className="text-[12px] text-text-secondary">
        {images.length} / {SUBMISSION_IMAGE_MAX_COUNT} 枚・JPEG / PNG / WebP、1 枚 5MB まで。
        画像はあなたと運営だけが見られます。
      </p>
      {error ? <p role="alert" className="text-[13px] text-danger">{error}</p> : null}
    </div>
  );
}
