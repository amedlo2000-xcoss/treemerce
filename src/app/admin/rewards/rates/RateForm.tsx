"use client";

import { useState } from "react";

import { ConfirmReasonDialog } from "@/components/ConfirmReasonDialog";
import { FIELD_CLASS } from "@/components/ui";
import { AGENT_RANK_LABELS, formatRate, type AgentRank } from "@/lib/domain/rewards";

/** 比率 (0.2) → 入力用の % 文字列 ("20") */
function toPercentText(rate: number): string {
  return String(Number((Number(rate) * 100).toFixed(2)));
}

/**
 * ランク別の紹介者の割合の変更 (super_admin)。% (例: 20) で入力し、理由は必須。
 * 運営の割合は 30% − 紹介者の割合で決まる。確定済みの報酬明細には影響しない。
 */
export function RateForm({ rank, currentRate }: { rank: AgentRank; currentRate: number }) {
  const [percent, setPercent] = useState(toPercentText(currentRate));
  const n = Number(percent.trim());
  const valid =
    percent.trim() !== "" && Number.isFinite(n) && n >= 0 && n <= 30 && Math.round(n * 100) === n * 100;
  const changed = valid && Math.round(n * 100) !== Math.round(Number(currentRate) * 10000);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <label className="flex items-center gap-1.5">
        <span className="sr-only">{AGENT_RANK_LABELS[rank]} の紹介者の割合 (%)</span>
        <input
          type="number"
          inputMode="decimal"
          min={0}
          max={30}
          step={0.01}
          value={percent}
          onChange={(e) => setPercent(e.target.value)}
          className={`${FIELD_CLASS} !w-24 tabular-nums`}
        />
        <span className="text-[13px] text-text-secondary">%</span>
      </label>
      <ConfirmReasonDialog
        triggerLabel="変更"
        disabled={!changed}
        disabledTitle={valid ? "現在と同じ割合です" : "0〜30 の数値 (小数第2位まで) で入力してください"}
        sentence={`${AGENT_RANK_LABELS[rank]} の紹介者の割合を ${formatRate(currentRate)} → ${valid ? `${n}%` : "—"} に変更します`}
        note={`運営の割合は ${valid ? `${Number((30 - n).toFixed(2))}%` : "—"} になります。変更後に確定する報酬から使われ、確定済みの報酬明細は変わりません。`}
        reasonLabel="変更理由 (必須・監査ログに記録されます)"
        confirmLabel="変更する"
        endpoint="/api/admin/rewards/rates"
        payload={{ rank, percent: n }}
      />
      {!valid ? <span className="text-[12px] text-danger">0〜30 で入力</span> : null}
    </div>
  );
}
