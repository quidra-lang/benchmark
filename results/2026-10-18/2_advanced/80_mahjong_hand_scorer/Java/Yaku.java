import java.util.*;
final class Yaku {
    record Definition(String name, int closed, int opened) {}
    record Item(String name, int value) {}
    static final List<Definition> YAKU =
        List.of(new Definition("riichi", 1, 0), new Definition("double_riichi", 2, 0),
                new Definition("ippatsu", 1, 0), new Definition("menzen_tsumo", 1, 0),
                new Definition("pinfu", 1, 0), new Definition("tanyao", 1, 1),
                new Definition("iipeikou", 1, 0), new Definition("haku", 1, 1),
                new Definition("hatsu", 1, 1), new Definition("chun", 1, 1),
                new Definition("jikaze", 1, 1), new Definition("bakaze", 1, 1),
                new Definition("haitei", 1, 1), new Definition("houtei", 1, 1),
                new Definition("rinshan", 1, 1), new Definition("chankan", 1, 1),
                new Definition("chiitoitsu", 2, 0), new Definition("toitoi", 2, 2),
                new Definition("sanankou", 2, 2), new Definition("sanshoku_doujun", 2, 1),
                new Definition("sanshoku_doukou", 2, 2), new Definition("ittsu", 2, 1),
                new Definition("chanta", 2, 1), new Definition("sankantsu", 2, 2),
                new Definition("shousangen", 2, 2), new Definition("honroutou", 2, 2),
                new Definition("honitsu", 3, 2), new Definition("junchan", 3, 2),
                new Definition("ryanpeikou", 3, 0), new Definition("chinitsu", 6, 5));
    static final List<Item> YAKUMAN =
        List.of(new Item("tenhou", 1), new Item("chiihou", 1), new Item("kokushi", 1),
                new Item("kokushi_13", 2), new Item("suuankou", 1), new Item("suuankou_tanki", 2),
                new Item("daisangen", 1), new Item("shousuushii", 1), new Item("daisuushii", 2),
                new Item("tsuuiisou", 1), new Item("chinroutou", 1), new Item("ryuuiisou", 1),
                new Item("chuuren", 1), new Item("junsei_chuuren", 2), new Item("suukantsu", 1));
    static final List<String> FLAGS = List.of("riichi", "double_riichi", "ippatsu", "haitei",
                                              "houtei", "rinshan", "chankan", "tenhou", "chiihou"),
                              CATEGORIES = List.of("none", "mangan", "haneman", "baiman",
                                                   "sanbaiman", "kazoe_yakuman", "yakuman");
    static List<Item> ordinary(Set<String> names, boolean closed) {
        List<Item> items = new ArrayList<>();
        for (Definition definition : YAKU)
            if (names.contains(definition.name()) && (closed || definition.opened() > 0))
                items.add(new Item(definition.name(),
                                   closed ? definition.closed() : definition.opened()));
        return items;
    }
    static List<Item> yakuman(Set<String> names, boolean doubled) {
        List<Item> items = new ArrayList<>();
        for (Item definition : YAKUMAN)
            if (names.contains(definition.name()))
                items.add(new Item(definition.name(), doubled ? definition.value() : 1));
        return items;
    }
}
