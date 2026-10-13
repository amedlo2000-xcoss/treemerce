import type { ReactNode } from "react";

/**
 * 画像のない商品の仮イメージ (図形のみの SVG)。商品の placeholder_key (0023) でモチーフを選び、
 * 未指定なら物品 / サービスの汎用のモチーフを描く。仮の画像であることを「イメージ」と表示する。
 * 実在の神社・寺院の写真や建物は描かない。五次元結晶は抽象的な結晶の形にする。
 */

type Motif = { bg: string; draw: ReactNode };

const INK = "#3f3a36";

const MOTIFS: Record<string, Motif> = {
  // はちみつ梅: 梅の実と、はちみつのしずく
  "sample-01": {
    bg: "#f6ecd9",
    draw: (
      <>
        <circle cx="92" cy="112" r="40" fill="#e9b949" />
        <circle cx="78" cy="98" r="10" fill="#f6d989" opacity="0.8" />
        <path d="M92 72 q4 -14 16 -18" stroke="#7a6a3a" strokeWidth="4" fill="none" strokeLinecap="round" />
        <path d="M140 70 q12 18 0 26 q-12 -8 0 -26z" fill="#d99a1e" />
      </>
    ),
  },
  // しそ漬け梅: 赤い梅と、しその葉
  "sample-02": {
    bg: "#f4e4e4",
    draw: (
      <>
        <path d="M60 120 q20 -60 80 -50 q-10 60 -80 50z" fill="#7a4a6e" />
        <path d="M68 116 q30 -28 66 -42" stroke="#5a3352" strokeWidth="2.5" fill="none" />
        <circle cx="112" cy="122" r="32" fill="#b8303a" />
        <circle cx="102" cy="112" r="8" fill="#d8656d" opacity="0.8" />
      </>
    ),
  },
  // 煎茶: 緑の茶碗と茶葉
  "sample-03": {
    bg: "#e6efe2",
    draw: (
      <>
        <path d="M54 92 h92 q-4 52 -46 52 q-42 0 -46 -52z" fill="#f8f5ec" stroke="#8aa57a" strokeWidth="3" />
        <ellipse cx="100" cy="92" rx="46" ry="9" fill="#9cbf6c" />
        <path d="M120 56 q22 -6 30 10 q-22 8 -30 -10z" fill="#5f8a3e" />
        <path d="M100 64 q-12 -18 4 -28 q10 14 -4 28z" fill="#79a64f" />
      </>
    ),
  },
  // ほうじ茶: 茶色の湯気の立つ茶碗
  "sample-04": {
    bg: "#efe4d8",
    draw: (
      <>
        <path d="M58 96 h84 q-4 46 -42 46 q-38 0 -42 -46z" fill="#8a5a3b" />
        <ellipse cx="100" cy="96" rx="42" ry="8" fill="#b07a4c" />
        <path d="M86 80 q-8 -12 0 -24 q8 -12 0 -24" stroke="#a88a72" strokeWidth="3" fill="none" strokeLinecap="round" />
        <path d="M112 80 q-8 -12 0 -24 q8 -12 0 -24" stroke="#a88a72" strokeWidth="3" fill="none" strokeLinecap="round" />
      </>
    ),
  },
  // はちみつ: 蓮の葉に宿る雫
  "sample-05": {
    bg: "#e5efe9",
    draw: (
      <>
        <path d="M100 140 L40 100 A64 40 0 1 1 160 100z" fill="#6f9a7c" />
        <path d="M100 140 L70 86 M100 140 L100 78 M100 140 L130 86" stroke="#4d7a5b" strokeWidth="2.5" />
        <path d="M100 74 q14 20 0 30 q-14 -10 0 -30z" fill="#e8a930" />
      </>
    ),
  },
  // 贈答米: 結び目のある米袋と米粒
  "sample-06": {
    bg: "#f3efe6",
    draw: (
      <>
        <path d="M66 74 h68 l8 70 h-84z" fill="#fbf8f1" stroke="#c9b897" strokeWidth="3" />
        <path d="M80 74 q20 -20 40 0" stroke="#b8323a" strokeWidth="5" fill="none" />
        <circle cx="100" cy="74" r="6" fill="#b8323a" />
        {[0, 1, 2, 3, 4].map((i) => (
          <ellipse key={i} cx={82 + i * 9} cy={112 + (i % 2) * 8} rx="4" ry="7" fill="#e4dac4" />
        ))}
      </>
    ),
  },
  // 羊羹: 切り分けた羊羹と小さな灯り
  "sample-07": {
    bg: "#efe7e2",
    draw: (
      <>
        <rect x="46" y="96" width="78" height="38" rx="4" fill="#5b2f2f" />
        <rect x="132" y="96" width="24" height="38" rx="4" fill="#6e3a3a" />
        <rect x="46" y="96" width="78" height="8" rx="3" fill="#7a4545" />
        <circle cx="140" cy="64" r="14" fill="#f2c46b" opacity="0.35" />
        <path d="M140 54 q8 10 0 18 q-8 -8 0 -18z" fill="#e8a53a" />
      </>
    ),
  },
  // 琥珀糖: 色とりどりの石のかけら
  "sample-08": {
    bg: "#eef0f3",
    draw: (
      <>
        <path d="M56 118 l18 -26 l26 8 l-6 30 l-30 4z" fill="#b6d4d8" />
        <path d="M100 96 l26 -18 l20 22 l-14 26 l-26 -6z" fill="#e7b9c4" />
        <path d="M82 138 l22 -10 l20 14 l-18 14 l-22 -4z" fill="#d8cf9a" />
        <path d="M74 92 l8 -10" stroke="#ffffff" strokeWidth="3" opacity="0.7" strokeLinecap="round" />
      </>
    ),
  },
  // お香: 一本の線香と立ちのぼる煙、背後の森
  "sample-09": {
    bg: "#e4ebe4",
    draw: (
      <>
        <path d="M30 150 q20 -40 40 0z M60 150 q24 -52 48 0z M124 150 q22 -44 44 0z" fill="#9db49a" opacity="0.7" />
        <rect x="98" y="88" width="4" height="56" fill="#7a5a3a" />
        <rect x="80" y="142" width="40" height="8" rx="3" fill={INK} />
        <path d="M100 86 q-12 -14 0 -26 q12 -12 -2 -26" stroke="#b9b5ae" strokeWidth="3" fill="none" strokeLinecap="round" />
      </>
    ),
  },
  // キャンドル: 温かな炎
  "sample-10": {
    bg: "#f1ebe1",
    draw: (
      <>
        <circle cx="100" cy="66" r="26" fill="#f4cf7a" opacity="0.3" />
        <rect x="78" y="88" width="44" height="58" rx="6" fill="#f8f3e8" stroke="#d8c9a8" strokeWidth="3" />
        <rect x="99" y="80" width="2" height="10" fill={INK} />
        <path d="M100 52 q12 16 0 28 q-12 -12 0 -28z" fill="#e8952e" />
      </>
    ),
  },
  // 五次元結晶: 抽象的な多面体の結晶
  "sample-11": {
    bg: "#e8e6f2",
    draw: (
      <>
        <path d="M100 36 L140 84 L120 156 L80 156 L60 84z" fill="#c7c1e6" />
        <path d="M100 36 L120 156 L80 156z" fill="#a99fd8" />
        <path d="M100 36 L60 84 L80 156z" fill="#dcd8f2" />
        <path d="M60 84 L140 84" stroke="#ffffff" strokeWidth="2" opacity="0.8" />
        <path d="M146 48 l4 10 l10 4 l-10 4 l-4 10 l-4 -10 l-10 -4 l10 -4z" fill="#ffffff" opacity="0.9" />
      </>
    ),
  },
  // 整丹 (施術): 穏やかな波紋 (抽象)
  "sample-12": {
    bg: "#e6edf0",
    draw: (
      <>
        <circle cx="100" cy="100" r="54" fill="none" stroke="#a7c0c9" strokeWidth="3" />
        <circle cx="100" cy="100" r="38" fill="none" stroke="#86a9b5" strokeWidth="3" />
        <circle cx="100" cy="100" r="20" fill="#6f95a3" />
        <path d="M40 156 q30 -14 60 0 q30 14 60 0" stroke="#a7c0c9" strokeWidth="3" fill="none" />
      </>
    ),
  },
  // ピアス: しずく形の耳飾り一対
  "sample-13": {
    bg: "#eaf0ee",
    draw: (
      <>
        {[72, 128].map((x) => (
          <g key={x}>
            <circle cx={x} cy="62" r="5" fill="none" stroke="#b39b62" strokeWidth="3" />
            <line x1={x} y1="67" x2={x} y2="88" stroke="#b39b62" strokeWidth="2.5" />
            <path d={`M${x} 88 q18 26 0 44 q-18 -18 0 -44z`} fill="#8fbfb0" />
          </g>
        ))}
      </>
    ),
  },
  // 蜜蝋のアクセサリー: 結び目のある指輪
  "sample-14": {
    bg: "#f4eedc",
    draw: (
      <>
        <ellipse cx="100" cy="112" rx="40" ry="34" fill="none" stroke="#d6aa4c" strokeWidth="10" />
        <path d="M86 78 q14 -18 28 0 q-14 14 -28 0z" fill="#e8c574" stroke="#c19438" strokeWidth="2" />
        <circle cx="100" cy="78" r="6" fill="#c19438" />
      </>
    ),
  },
  // 勾玉
  "sample-15": {
    bg: "#e6ece6",
    draw: (
      <>
        <path d="M118 60 a36 36 0 1 1 -36 62 a22 22 0 1 0 36 -62z" fill="#4f8a6a" transform="rotate(-20 100 100)" />
        <circle cx="112" cy="78" r="6" fill="#e6ece6" />
        <path d="M112 72 q10 -26 30 -30" stroke="#a88a5a" strokeWidth="2.5" fill="none" />
      </>
    ),
  },
  // 創作文字: 筆の円と運筆
  "sample-16": {
    bg: "#f3f0ea",
    draw: (
      <>
        <path d="M150 84 a52 52 0 1 0 -8 58" stroke={INK} strokeWidth="11" fill="none" strokeLinecap="round" />
        <path d="M84 84 q16 6 30 0 M98 74 q2 30 -6 52 M90 106 q16 -4 26 8" stroke="#8a3a32" strokeWidth="6" fill="none" strokeLinecap="round" />
      </>
    ),
  },
  // 風呂敷: 結んだ布包み
  "sample-17": {
    bg: "#ebe8f0",
    draw: (
      <>
        <path d="M52 148 q-6 -50 48 -58 q54 8 48 58z" fill="#5e5a8c" />
        <path d="M70 96 q30 -26 60 0 q-12 -30 -30 -18 q-18 -12 -30 18z" fill="#77729f" />
        <circle cx="100" cy="84" r="8" fill="#4a4674" />
        <path d="M64 124 q36 10 72 0" stroke="#a9a4cf" strokeWidth="3" fill="none" strokeDasharray="6 6" />
      </>
    ),
  },
  // 湯のみ
  "sample-18": {
    bg: "#e9ebe7",
    draw: (
      <>
        <path d="M68 64 h64 l-6 82 h-52z" fill="#a8b4a3" />
        <path d="M68 64 h64 l-2 22 h-60z" fill="#c7d0c2" />
        <ellipse cx="100" cy="64" rx="32" ry="6" fill="#dfe5db" />
        <path d="M74 112 q26 10 52 0" stroke="#7e8b78" strokeWidth="3" fill="none" />
      </>
    ),
  },
  // 一輪挿し: 花器と一輪の花
  "sample-19": {
    bg: "#efeee9",
    draw: (
      <>
        <path d="M90 104 q-26 14 -18 42 h56 q8 -28 -18 -42 v-14 h-20z" fill="#7d7a73" />
        <path d="M100 92 q-4 -30 10 -50" stroke="#6d8a5a" strokeWidth="3" fill="none" />
        <path d="M100 66 q-18 -4 -18 -18 q16 2 18 18z" fill="#86a56f" />
        <circle cx="110" cy="40" r="10" fill="#e3a6a6" />
        <circle cx="110" cy="40" r="4" fill="#f4dc9a" />
      </>
    ),
  },
  // 自己対話ノート: 栞のあるノート
  "sample-20": {
    bg: "#eef0ea",
    draw: (
      <>
        <rect x="58" y="50" width="84" height="106" rx="6" fill="#6b7f6a" />
        <rect x="70" y="50" width="72" height="106" rx="4" fill="#f8f6f0" />
        {[74, 90, 106, 122].map((y) => (
          <line key={y} x1="80" y1={y} x2="132" y2={y} stroke="#d6d2c6" strokeWidth="2" />
        ))}
        <path d="M122 50 v40 l8 -8 l8 8 v-40z" fill="#b8323a" />
      </>
    ),
  },
};

// 汎用のモチーフ (placeholder_key が未指定・不明なとき)
const GENERIC_GOODS: Motif = {
  bg: "#efeee9",
  draw: (
    <>
      <path d="M100 52 L148 76 L148 132 L100 156 L52 132 L52 76z" fill="#d8d3c6" />
      <path d="M100 52 L148 76 L100 100 L52 76z" fill="#e6e1d5" />
      <path d="M100 100 L100 156" stroke="#bdb6a6" strokeWidth="2" />
    </>
  ),
};

const GENERIC_SERVICE: Motif = MOTIFS["sample-12"];

/** 商品管理で選べるイラストの種類 (placeholder_key) と、選択肢の表示名 */
export const PLACEHOLDER_OPTIONS: { key: string; label: string }[] = [
  { key: "sample-01", label: "梅の実とはちみつ" },
  { key: "sample-02", label: "梅としその葉" },
  { key: "sample-03", label: "緑の茶碗と茶葉" },
  { key: "sample-04", label: "湯気の立つ茶碗" },
  { key: "sample-05", label: "蓮の葉と雫" },
  { key: "sample-06", label: "米袋と米粒" },
  { key: "sample-07", label: "羊羹と灯り" },
  { key: "sample-08", label: "色とりどりのかけら" },
  { key: "sample-09", label: "線香と森" },
  { key: "sample-10", label: "キャンドル" },
  { key: "sample-11", label: "抽象的な結晶" },
  { key: "sample-12", label: "穏やかな波紋" },
  { key: "sample-13", label: "しずく形の耳飾り" },
  { key: "sample-14", label: "結び目のある指輪" },
  { key: "sample-15", label: "勾玉" },
  { key: "sample-16", label: "筆の円と運筆" },
  { key: "sample-17", label: "結んだ布包み" },
  { key: "sample-18", label: "湯のみ" },
  { key: "sample-19", label: "一輪挿し" },
  { key: "sample-20", label: "栞のあるノート" },
];

export function ProductPlaceholder({
  placeholderKey,
  itemKind = "goods",
  className = "",
}: {
  placeholderKey: string | null | undefined;
  itemKind?: "goods" | "service";
  className?: string;
}) {
  const motif =
    (placeholderKey ? MOTIFS[placeholderKey] : undefined) ??
    (itemKind === "service" ? GENERIC_SERVICE : GENERIC_GOODS);
  return (
    <div className={`relative overflow-hidden ${className}`} style={{ backgroundColor: motif?.bg ?? "#eeeeee" }}>
      <svg viewBox="0 0 200 200" className="h-full w-full" role="img" aria-label="商品のイメージ図">
        {motif?.draw}
      </svg>
      <span className="absolute bottom-2 right-2 rounded-md bg-surface/85 px-1.5 py-0.5 text-[10px] font-medium text-text-secondary">
        イメージ
      </span>
    </div>
  );
}
