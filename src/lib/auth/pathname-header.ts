/** proxy.ts が付ける「現在のパス (+ クエリ)」のリクエストヘッダー名 (proxy から next/headers を読み込まないよう別ファイルにする) */
export const PATHNAME_HEADER = "x-treemerce-pathname";
