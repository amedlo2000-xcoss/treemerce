import type { CatalogCategory } from "@/lib/domain/catalog-categories";

/**
 * オブザーバー特典付き製品・サービスのサンプルデータ (企画段階)。
 *
 * オブザーバー特典付き製品一覧 (/observer-products) 専用のローカルデータで、DB の商品・注文・代理店とは一切つながらない。
 * 価格・提供者・連絡先・産地・発送日数・施術時間などの架空の値は作らず、すべて「未定」で表示する。
 * 商品名は神社や寺院の建物・風景などをモチーフにした仮称で、神社・寺院の公認・提携の商品ではない。
 */
export type ObserverSample = {
  id: string;
  /** 商品の種類 */
  type: string;
  /** 商品名 (仮称) */
  name: string;
  /** 商品名の読み仮名 (空なら表示しない) */
  reading: string;
  description: string;
  category: CatalogCategory;
};

export const OBSERVER_SAMPLES: readonly ObserverSample[] = [
  { id: "sample-01", type: "はちみつ梅", name: "奉献漬", reading: "ほうけんづけ", description: "奉献の心を贈り物に重ねた、まろやかな甘さのはちみつ梅。", category: "食品・飲料" },
  { id: "sample-02", type: "しそ漬け梅", name: "梅結び", reading: "うめむすび", description: "人とのご縁を結ぶ気持ちを込めた、しその香りを楽しむ梅干し。", category: "食品・飲料" },
  { id: "sample-03", type: "煎茶", name: "参道茶", reading: "さんどうちゃ", description: "参道を歩く穏やかなひとときをイメージした、日々の休憩に楽しむ煎茶。", category: "食品・飲料" },
  { id: "sample-04", type: "ほうじ茶", name: "禅庭茶", reading: "ぜんていちゃ", description: "禅寺の庭の静けさをイメージした、香ばしい香りのほうじ茶。", category: "食品・飲料" },
  { id: "sample-05", type: "はちみつ", name: "蓮の雫", reading: "はすのしずく", description: "蓮の葉に宿る雫をイメージした、食卓や贈り物に取り入れるはちみつ。", category: "食品・飲料" },
  { id: "sample-06", type: "贈答米", name: "結び米", reading: "むすびまい", description: "食を分かち合う喜びと、人とのつながりをテーマにした贈答用のお米。", category: "食品・飲料" },
  { id: "sample-07", type: "羊羹", name: "灯明菓", reading: "とうみょうか", description: "寺院に灯る温かな明かりをイメージした、お茶の時間を彩る羊羹。", category: "食品・飲料" },
  { id: "sample-08", type: "琥珀糖", name: "石庭のかけら", reading: "せきていのかけら", description: "石庭の石をモチーフにした、色と形を楽しめる琥珀糖。", category: "食品・飲料" },
  { id: "sample-09", type: "お香", name: "社叢香", reading: "しゃそうこう", description: "神社を囲む森をイメージした、落ち着いた香りを楽しむお香。", category: "香り・キャンドル" },
  { id: "sample-10", type: "キャンドル", name: "伽藍の灯", reading: "がらんのあかり", description: "寺院の灯りをモチーフにした、温かな光で空間を彩るキャンドル。", category: "香り・キャンドル" },
  { id: "sample-11", type: "五次元結晶", name: "五次元結晶", reading: "ごじげんけっしょう", description: "想像を形にする世界観を伝える結晶作品。素材や仕様は正式な製品案内に合わせて掲載予定。", category: "五次元結晶" },
  { id: "sample-12", type: "整丹（ジャップカサイ）", name: "整丹・参道のひととき", reading: "", description: "整丹（ジャップカサイ）の施術サービス。施術内容・対象・所要時間は提供者の案内に合わせて掲載予定。", category: "施術・体験" },
  { id: "sample-13", type: "耳飾り・ピアス", name: "社の雫", reading: "やしろのしずく", description: "社の木々に宿る雫をモチーフにした、耳元を彩るピアス。", category: "アクセサリー" },
  { id: "sample-14", type: "蜜蝋を用いた指輪・アクセサリー", name: "蜜の結び", reading: "みつのむすび", description: "結びの形を取り入れた、蜜蝋を用いて制作するアクセサリー。素材・製法の詳細は確認後に掲載予定。", category: "アクセサリー" },
  { id: "sample-15", type: "勾玉", name: "杜の曲玉", reading: "もりのまがたま", description: "神社を囲む杜をイメージし、伝統的な勾玉の形を現代的に表現した装飾品。", category: "アクセサリー" },
  { id: "sample-16", type: "創作文字作品", name: "結び文字", reading: "むすびもじ", description: "名前や大切な言葉を、結びや和の意匠を取り入れた創作文字で表現するアート作品。", category: "アート" },
  { id: "sample-17", type: "風呂敷", name: "結び布", reading: "むすびぬの", description: "結びをテーマにした模様で、包む・運ぶ・飾るを楽しめる風呂敷。", category: "生活雑貨" },
  { id: "sample-18", type: "湯のみ", name: "禅庭の器", reading: "ぜんていのうつわ", description: "禅寺の庭の色や佇まいをイメージした、日々のお茶を楽しむ湯のみ。", category: "生活雑貨" },
  { id: "sample-19", type: "一輪挿し", name: "石庭一輪", reading: "せきていいちりん", description: "石庭の静かな景色をモチーフにした、一輪の花を引き立てる花器。", category: "生活雑貨" },
  { id: "sample-20", type: "自己対話ノート", name: "巡り帳", reading: "めぐりちょう", description: "神社仏閣を巡る旅になぞらえ、日々の気づきや自分への問いを記録するノート。", category: "文具" },
];

/** 未確定の項目の表示 (0 円・無料などで代用しない) */
export const SAMPLE_UNDECIDED = "未定";

/** 全サンプル共通の掲載理由 */
export const SAMPLE_LISTING_REASON = "TOWAオブザーバー特典付き製品・サービスの掲載イメージを紹介するため。";
