using System.Collections.Generic;
public static class Yaku {
    public record Definition(string name, int closed, int opened);
    public record Item(string name, int value);
    public static readonly List<Definition> YAKU =
        new() { new("riichi", 1, 0),          new("double_riichi", 2, 0),
                new("ippatsu", 1, 0),         new("menzen_tsumo", 1, 0),
                new("pinfu", 1, 0),           new("tanyao", 1, 1),
                new("iipeikou", 1, 0),        new("haku", 1, 1),
                new("hatsu", 1, 1),           new("chun", 1, 1),
                new("jikaze", 1, 1),          new("bakaze", 1, 1),
                new("haitei", 1, 1),          new("houtei", 1, 1),
                new("rinshan", 1, 1),         new("chankan", 1, 1),
                new("chiitoitsu", 2, 0),      new("toitoi", 2, 2),
                new("sanankou", 2, 2),        new("sanshoku_doujun", 2, 1),
                new("sanshoku_doukou", 2, 2), new("ittsu", 2, 1),
                new("chanta", 2, 1),          new("sankantsu", 2, 2),
                new("shousangen", 2, 2),      new("honroutou", 2, 2),
                new("honitsu", 3, 2),         new("junchan", 3, 2),
                new("ryanpeikou", 3, 0),      new("chinitsu", 6, 5) };
    public static readonly List<Item> YAKUMAN =
        new() { new("tenhou", 1),     new("chiihou", 1),        new("kokushi", 1),
                new("kokushi_13", 2), new("suuankou", 1),       new("suuankou_tanki", 2),
                new("daisangen", 1),  new("shousuushii", 1),    new("daisuushii", 2),
                new("tsuuiisou", 1),  new("chinroutou", 1),     new("ryuuiisou", 1),
                new("chuuren", 1),    new("junsei_chuuren", 2), new("suukantsu", 1) };
    public static readonly List<string> FLAGS = new() { "riichi",  "double_riichi", "ippatsu",
                                                        "haitei",  "houtei",        "rinshan",
                                                        "chankan", "tenhou",        "chiihou" },
                                        CATEGORIES = new() { "none",   "mangan",    "haneman",
                                                             "baiman", "sanbaiman", "kazoe_yakuman",
                                                             "yakuman" };
    public static List<Item> Ordinary(HashSet<string> names, bool closed) {
        List<Item> items = new();
        foreach (Definition definition in YAKU)
            if (names.Contains(definition.name) && (closed || definition.opened > 0))
                items.Add(new(definition.name, closed ? definition.closed : definition.opened));
        return items;
    }
    public static List<Item> Yakuman(HashSet<string> names, bool doubled) {
        List<Item> items = new();
        foreach (Item definition in YAKUMAN)
            if (names.Contains(definition.name))
                items.Add(new(definition.name, doubled ? definition.value : 1));
        return items;
    }
}
