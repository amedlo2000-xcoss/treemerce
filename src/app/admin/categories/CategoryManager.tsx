"use client";

import { ArrowDown, ArrowUp } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, Badge, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import type { AdminCategoryRow } from "@/lib/domain/types";

type Editing = { id: string; mode: "rename" | "toggle"; name: string; reason: string } | null;

const SMALL_BUTTON =
  "rounded-xl border border-border-soft px-3 py-1.5 text-[13px] font-medium text-text-primary transition-colors hover:bg-surface-muted disabled:cursor-not-allowed disabled:opacity-50";

/**
 * カテゴリの一覧・追加・名称変更・有効/無効・並べ替え (super_admin 専用)。
 * API (/api/admin/categories/...) と DB でも super_admin・理由必須・削除不可を再判定する。
 */
export function CategoryManager({ categories }: { categories: AdminCategoryRow[] }) {
  const router = useRouter();
  const [newName, setNewName] = useState("");
  const [editing, setEditing] = useState<Editing>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  async function send(url: string, method: string, body: unknown, message: string) {
    setPending(true);
    setError(null);
    setDone(null);
    const response = await fetch(url, {
      method,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    const result = await response.json().catch(() => null);
    setPending(false);
    if (!response.ok) {
      setError(result?.error?.message ?? "保存に失敗しました。");
      return false;
    }
    setDone(message);
    router.refresh();
    return true;
  }

  async function handleAdd(event: React.FormEvent) {
    event.preventDefault();
    if (!newName.trim()) return;
    if (await send("/api/admin/categories", "POST", { name: newName.trim() }, "カテゴリを追加しました。")) {
      setNewName("");
    }
  }

  async function handleEditSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!editing) return;
    if (!editing.reason.trim()) {
      setError("理由を入力してください。");
      return;
    }
    const target = categories.find((c) => c.id === editing.id);
    if (!target) return;
    const ok =
      editing.mode === "rename"
        ? await send(
            `/api/admin/categories/${editing.id}`,
            "PATCH",
            { name: editing.name.trim(), reason: editing.reason.trim() },
            "名称を変更しました。",
          )
        : await send(
            `/api/admin/categories/${editing.id}`,
            "PATCH",
            { is_active: !target.is_active, reason: editing.reason.trim() },
            target.is_active ? "無効にしました。" : "有効にしました。",
          );
    if (ok) setEditing(null);
  }

  async function move(index: number, delta: -1 | 1) {
    const ids = categories.map((c) => c.id);
    const target = index + delta;
    if (target < 0 || target >= ids.length) return;
    [ids[index], ids[target]] = [ids[target], ids[index]];
    await send("/api/admin/categories/order", "PUT", { ids }, "並び順を変更しました。");
  }

  return (
    <div className="space-y-5">
      <form onSubmit={handleAdd} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <Field label="新しいカテゴリ名" className="flex-1">
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            maxLength={40}
            className={FIELD_CLASS}
            placeholder="例: 茶器"
          />
        </Field>
        <button type="submit" disabled={pending || !newName.trim()} className={BUTTON_CLASS}>
          追加
        </button>
      </form>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <ol className="divide-y divide-border-soft rounded-xl border border-border-soft">
        {categories.map((c, index) => (
          <li key={c.id} className="space-y-3 px-3 py-3">
            <div className="flex flex-wrap items-center gap-2">
              <div className="flex gap-1">
                <button
                  type="button"
                  aria-label={`${c.name} を上へ`}
                  onClick={() => move(index, -1)}
                  disabled={pending || index === 0}
                  className={SMALL_BUTTON}
                >
                  <ArrowUp size={14} />
                </button>
                <button
                  type="button"
                  aria-label={`${c.name} を下へ`}
                  onClick={() => move(index, 1)}
                  disabled={pending || index === categories.length - 1}
                  className={SMALL_BUTTON}
                >
                  <ArrowDown size={14} />
                </button>
              </div>
              <span className="min-w-0 flex-1">
                <span className={`block break-words text-[14px] font-medium ${c.is_active ? "text-text-primary" : "text-text-secondary"}`}>
                  {c.name}
                </span>
                <span className="block font-mono text-[11px] text-text-secondary">{c.code}</span>
              </span>
              <span className="flex flex-wrap gap-1">
                {c.is_active ? <Badge tone="green">有効</Badge> : <Badge tone="neutral">無効</Badge>}
                {c.in_use ? <Badge tone="blue">使用中</Badge> : null}
                {c.legacy_code ? <Badge tone="neutral">旧カテゴリと対応</Badge> : null}
              </span>
              <span className="flex gap-1">
                <button
                  type="button"
                  onClick={() => setEditing({ id: c.id, mode: "rename", name: c.name, reason: "" })}
                  disabled={pending}
                  className={SMALL_BUTTON}
                >
                  名称変更
                </button>
                <button
                  type="button"
                  onClick={() => setEditing({ id: c.id, mode: "toggle", name: c.name, reason: "" })}
                  disabled={pending || (c.is_active && c.in_use)}
                  title={c.is_active && c.in_use ? "公開中・準備中の商品が使っているため無効にできません" : undefined}
                  className={SMALL_BUTTON}
                >
                  {c.is_active ? "無効にする" : "有効にする"}
                </button>
              </span>
            </div>

            {editing?.id === c.id ? (
              <form onSubmit={handleEditSubmit} className="space-y-2 rounded-xl bg-surface-muted p-3">
                {editing.mode === "rename" ? (
                  <Field label="新しい名称">
                    <input
                      required
                      maxLength={40}
                      value={editing.name}
                      onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                      className={FIELD_CLASS}
                    />
                  </Field>
                ) : (
                  <p className="text-[13px] text-text-primary">
                    「{c.name}」を{c.is_active ? "無効" : "有効"}にします。
                  </p>
                )}
                <Field label="理由 (必須・監査ログに記録されます)">
                  <input
                    required
                    maxLength={500}
                    value={editing.reason}
                    onChange={(e) => setEditing({ ...editing, reason: e.target.value })}
                    className={FIELD_CLASS}
                  />
                </Field>
                <div className="flex gap-2">
                  <button type="submit" disabled={pending} className={BUTTON_CLASS}>
                    {pending ? "保存中…" : "保存"}
                  </button>
                  <button type="button" onClick={() => setEditing(null)} className={SMALL_BUTTON}>
                    やめる
                  </button>
                </div>
              </form>
            ) : null}
          </li>
        ))}
      </ol>
    </div>
  );
}
