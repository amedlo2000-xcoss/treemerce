"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton, Chip } from "@/components/mobile/primitives";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { BANK_ACCOUNT_TYPES, BANK_ACCOUNT_TYPE_LABELS } from "@/lib/domain/enums";
import type { BankAccountRow } from "@/lib/domain/types";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-2.5 text-[15px] text-text-primary outline-none focus:border-brand";

function maskAccountNumber(value: string) {
  if (value.length <= 4) return value;
  return `••••${value.slice(-4)}`;
}

export function BankAccountForm({
  agentId,
  account,
}: {
  agentId: string;
  account: BankAccountRow | null;
}) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState({
    bank_name: account?.bank_name ?? "",
    branch_name: account?.branch_name ?? "",
    account_type: account?.account_type ?? "ordinary",
    account_number: account?.account_number ?? "",
    account_holder_kana: account?.account_holder_kana ?? "",
  });

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const supabase = getSupabaseBrowserClient();
    const { error: upsertError } = await supabase
      .from("bank_accounts")
      .upsert({ agent_id: agentId, ...form }, { onConflict: "agent_id" });

    setPending(false);
    if (upsertError) {
      setError(upsertError.message);
      return;
    }
    setEditing(false);
    router.refresh();
  }

  if (!editing) {
    return (
      <div className="space-y-3">
        {account ? (
          <dl className="divide-y divide-border-soft">
            <div className="flex items-center justify-between py-2.5">
              <dt className="text-[13px] text-text-secondary">金融機関</dt>
              <dd className="text-[14px] font-medium text-text-primary">
                {account.bank_name} {account.branch_name}
              </dd>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <dt className="text-[13px] text-text-secondary">口座種別</dt>
              <dd className="text-[14px] font-medium text-text-primary">
                {BANK_ACCOUNT_TYPE_LABELS[account.account_type]}
              </dd>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <dt className="text-[13px] text-text-secondary">口座番号</dt>
              <dd className="font-mono text-[14px] font-medium text-text-primary">
                {maskAccountNumber(account.account_number)}
              </dd>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <dt className="text-[13px] text-text-secondary">口座名義</dt>
              <dd className="text-[14px] font-medium text-text-primary">
                {account.account_holder_kana}
              </dd>
            </div>
          </dl>
        ) : (
          <p className="text-[14px] text-text-secondary">口座情報はまだ登録されていません。</p>
        )}
        <PrimaryButton variant="secondary" onClick={() => setEditing(true)}>
          {account ? "口座情報を編集" : "口座情報を登録"}
        </PrimaryButton>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">金融機関名</span>
        <input
          required
          value={form.bank_name}
          onChange={(e) => setForm((f) => ({ ...f, bank_name: e.target.value }))}
          className={INPUT}
        />
      </label>
      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">支店名</span>
        <input
          required
          value={form.branch_name}
          onChange={(e) => setForm((f) => ({ ...f, branch_name: e.target.value }))}
          className={INPUT}
        />
      </label>
      <div className="space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">口座種別</span>
        <div className="flex flex-wrap gap-2">
          {BANK_ACCOUNT_TYPES.map((type) => (
            <Chip
              key={type}
              type="button"
              selected={form.account_type === type}
              onClick={() => setForm((f) => ({ ...f, account_type: type }))}
            >
              {BANK_ACCOUNT_TYPE_LABELS[type]}
            </Chip>
          ))}
        </div>
      </div>
      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">口座番号</span>
        <input
          required
          inputMode="numeric"
          value={form.account_number}
          onChange={(e) => setForm((f) => ({ ...f, account_number: e.target.value }))}
          className={INPUT}
        />
      </label>
      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">口座名義 (カナ)</span>
        <input
          required
          value={form.account_holder_kana}
          onChange={(e) => setForm((f) => ({ ...f, account_holder_kana: e.target.value }))}
          className={INPUT}
        />
      </label>

      {error ? <p className="text-[13px] text-danger">{error}</p> : null}

      <div className="flex gap-2">
        <PrimaryButton type="submit" disabled={pending}>
          {pending ? "保存中…" : "保存する"}
        </PrimaryButton>
        <PrimaryButton type="button" variant="secondary" onClick={() => setEditing(false)}>
          キャンセル
        </PrimaryButton>
      </div>
    </form>
  );
}
