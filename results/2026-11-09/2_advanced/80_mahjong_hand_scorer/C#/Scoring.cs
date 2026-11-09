using System;
using System.Collections.Generic;
using System.Linq;
public static class Scoring {
    public record Triplet(List<int> kinds, bool concealed, bool kan);
    public record Fu(List<Yaku.Item> items, int total, int rounded);
    public record Limit(string category, int basePoints);
    public record Payments(int ron, int dealer, int nondealer, int points);
    public static Yaku.Item TripletFu(Triplet block) {
        string type = block.kan ? (block.concealed ? "closed_kan" : "open_kan")
                                : (block.concealed ? "closed_triplet" : "open_triplet");
        int value = block.kan ? (block.concealed ? 16 : 8) : (block.concealed ? 4 : 2);
        return new(type + " " + Tiles.Block(block.kinds),
                   value * (Tiles.Yaochuu(block.kinds[0]) ? 2 : 1));
    }
    public static Fu FuBreakdown(string form, int pair, List<Triplet> triplets, string wait,
                                 bool closed, string method, int seat, int round, bool pinfu) {
        if (form == "chiitoitsu")
            return new(new() { new("chiitoitsu", 25) }, 25, 25);
        List<Yaku.Item> items = new() { new("base", 20) };
        if (closed && method == "ron")
            items.Add(new("closed_ron", 10));
        if (method == "tsumo" && !pinfu)
            items.Add(new("tsumo", 2));
        int pairValue =
            2 * ((pair >= 31 ? 1 : 0) + (pair == seat ? 1 : 0) + (pair == round ? 1 : 0));
        if (pairValue > 0)
            items.Add(new("pair " + Tiles.Block(new() { pair, pair }), pairValue));
        foreach (Triplet triplet in triplets)
            items.Add(TripletFu(triplet));
        if (new List<string> { "kanchan", "penchan", "tanki" }.Contains(wait))
            items.Add(new("wait " + wait, 2));
        int total = items.Sum(item => item.value);
        if (!closed && total == 20) {
            items.Add(new("open_pinfu", 10));
            total += 10;
        }
        return new(items, total, (total + 9) / 10 * 10);
    }
    public static Limit DetermineLimit(int han, int fu, Program.Rules rules) {
        if (han >= 13 && rules.kazoeYakuman)
            return new("kazoe_yakuman", 8000);
        if (han >= 11)
            return new("sanbaiman", 6000);
        if (han >= 8)
            return new("baiman", 4000);
        if (han >= 6)
            return new("haneman", 3000);
        int basePoints = fu * (1 << (han + 2));
        return han == 5 || basePoints >= 2000 || rules.kiriage && basePoints == 1920
                   ? new("mangan", 2000)
                   : new("none", basePoints);
    }
    public static int RoundHundred(int value) => (value + 99) / 100 * 100;
    public static Payments ComputePayments(int basePoints, bool dealer, string method) {
        if (method == "ron") {
            int ron = RoundHundred(basePoints * (dealer ? 6 : 4));
            return new(ron, 0, 0, ron);
        }
        if (dealer) {
            int amount = RoundHundred(2 * basePoints);
            return new(0, 0, amount, 3 * amount);
        }
        int dealerPayment = RoundHundred(2 * basePoints), nondealer = RoundHundred(basePoints);
        return new(0, dealerPayment, nondealer, dealerPayment + 2 * nondealer);
    }
}
