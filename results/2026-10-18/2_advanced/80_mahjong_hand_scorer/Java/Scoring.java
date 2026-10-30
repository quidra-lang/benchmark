import java.util.*;
final class Scoring {
    record Triplet(List<Integer> kinds, boolean concealed, boolean kan) {}
    record Fu(List<Yaku.Item> items, int total, int rounded) {}
    record Limit(String category, int base) {}
    record Payments(int ron, int dealer, int nondealer, int points) {}
    static Yaku.Item tripletFu(Triplet block) {
        String type = block.kan() ? (block.concealed() ? "closed_kan" : "open_kan")
                                  : (block.concealed() ? "closed_triplet" : "open_triplet");
        int value = block.kan() ? (block.concealed() ? 16 : 8) : (block.concealed() ? 4 : 2);
        return new Yaku.Item(type + " " + Tiles.block(block.kinds()),
                             value * (Tiles.yaochuu(block.kinds().getFirst()) ? 2 : 1));
    }
    static Fu fuBreakdown(String form, int pair, List<Triplet> triplets, String wait,
                          boolean closed, String method, int seat, int round, boolean pinfu) {
        if (form.equals("chiitoitsu"))
            return new Fu(List.of(new Yaku.Item("chiitoitsu", 25)), 25, 25);
        List<Yaku.Item> items = new ArrayList<>();
        items.add(new Yaku.Item("base", 20));
        if (closed && method.equals("ron"))
            items.add(new Yaku.Item("closed_ron", 10));
        if (method.equals("tsumo") && !pinfu)
            items.add(new Yaku.Item("tsumo", 2));
        int pairValue =
            2 * ((pair >= 31 ? 1 : 0) + (pair == seat ? 1 : 0) + (pair == round ? 1 : 0));
        if (pairValue > 0)
            items.add(new Yaku.Item("pair " + Tiles.block(List.of(pair, pair)), pairValue));
        for (Triplet triplet : triplets)
            items.add(tripletFu(triplet));
        if (List.of("kanchan", "penchan", "tanki").contains(wait))
            items.add(new Yaku.Item("wait " + wait, 2));
        int total = 0;
        for (Yaku.Item item : items)
            total += item.value();
        if (!closed && total == 20) {
            items.add(new Yaku.Item("open_pinfu", 10));
            total += 10;
        }
        return new Fu(items, total, (total + 9) / 10 * 10);
    }
    static Limit limit(int han, int fu, Main.Rules rules) {
        if (han >= 13 && rules.kazoeYakuman())
            return new Limit("kazoe_yakuman", 8000);
        if (han >= 11)
            return new Limit("sanbaiman", 6000);
        if (han >= 8)
            return new Limit("baiman", 4000);
        if (han >= 6)
            return new Limit("haneman", 3000);
        int base = fu * (1 << (han + 2));
        return han == 5 || base >= 2000 || rules.kiriage() && base == 1920
            ? new Limit("mangan", 2000)
            : new Limit("none", base);
    }
    static int roundHundred(int value) { return (value + 99) / 100 * 100; }
    static Payments payments(int base, boolean dealer, String method) {
        if (method.equals("ron")) {
            int ron = roundHundred(base * (dealer ? 6 : 4));
            return new Payments(ron, 0, 0, ron);
        }
        if (dealer) {
            int amount = roundHundred(2 * base);
            return new Payments(0, 0, amount, 3 * amount);
        }
        int dealerPayment = roundHundred(2 * base), nondealer = roundHundred(base);
        return new Payments(0, dealerPayment, nondealer, dealerPayment + 2 * nondealer);
    }
}
