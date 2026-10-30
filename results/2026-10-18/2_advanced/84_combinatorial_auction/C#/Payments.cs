using System;
using System.Collections.Generic;
using System.Linq;
public static class Payments {
    public record Vcg(long payment, WdpSolver.Result alternative);
    public record Critical(long payment, BidsIo.Bid rival);
    public record Coalition(int mask, List<int> members, long welfare, List<int> numbers);
    public record Block(Coalition coalition, long payoff, long deficit);
    public record Blocking(List<Block> all, List<Block> minimal);
    public static Dictionary<int, Vcg> VcgPayments(List<int> offered, List<BidsIo.Item> items,
                                                   List<BidsIo.Bid> bids, WdpSolver.Result optimal,
                                                   int count) {
        Dictionary<int, Vcg> results = new();
        for (int bidder = 0; bidder < count; bidder++) {
            long value = optimal.winning.Where(bid => bid.bidder == bidder).Sum(bid => bid.amount);
            if (value == 0)
                continue;
            WdpSolver.Result alternative =
                WdpSolver.Solve(offered, items, bids.Where(bid => bid.bidder != bidder).ToList());
            results[bidder] =
                new(alternative.welfare.Value - (optimal.welfare.Value - value), alternative);
        }
        return results;
    }
    static bool Earlier(long amount, BidsIo.Bid bid, BidsIo.Bid rival) {
        long left = amount * amount * rival.Size(),
             right = rival.amount * rival.amount * bid.Size();
        return left > right || left == right && bid.number < rival.number;
    }
    public static Dictionary<int, Critical>
    CriticalPayments(List<BidsIo.Bid> order, List<BidsIo.Bid> winning, List<BidsIo.Item> items) {
        Dictionary<int, Critical> results = new();
        foreach (BidsIo.Bid bid in winning) {
            BidsIo.Bid rival =
                WdpSolver.GreedySelect(order.Where(other => other.number != bid.number).ToList())
                    .FirstOrDefault(other => (bid.bundle & other.bundle) != 0 ||
                                             bid.xor && bid.bidder == other.bidder);
            long payment = Enumerable.Range(0, items.Count)
                               .Where(i => (bid.bundle & (1 << i)) != 0)
                               .Sum(i => items[i].reserve);
            if (rival != null) {
                long low = 1, high = 1;
                while (!Earlier(high, bid, rival))
                    high *= 2;
                while (low < high) {
                    long middle = (low + high) / 2;
                    if (Earlier(middle, bid, rival))
                        high = middle;
                    else
                        low = middle + 1;
                }
                payment = Math.Max(payment, low);
            }
            results[bid.number] = new(payment, rival);
        }
        return results;
    }
    static void Enumerate(List<Coalition> output, int count, int left, int start, int mask,
                          List<int> members, List<int> offered, List<BidsIo.Item> items,
                          List<BidsIo.Bid> bids) {
        if (left == 0) {
            WdpSolver.Result result = WdpSolver.Solve(
                offered, items, bids.Where(bid => (mask & (1 << bid.bidder)) != 0).ToList());
            output.Add(new(mask, new(members), result.welfare.Value, result.numbers));
            return;
        }
        for (int id = start; id <= count - left; id++) {
            List<int> next = new(members) { id };
            Enumerate(output, count, left - 1, id + 1, mask | (1 << id), next, offered, items,
                      bids);
        }
    }
    public static List<Coalition> Coalitions(List<int> offered, List<BidsIo.Item> items,
                                             List<BidsIo.Bid> bids, int count) {
        List<Coalition> output = new();
        for (int size = 0; size <= count; size++)
            Enumerate(output, count, size, 0, 0, new(), offered, items, bids);
        return output;
    }
    public static Blocking FindBlocking(List<Coalition> coalitions, long seller, long[] utilities) {
        List<Block> all = new(), minimal = new();
        foreach (Coalition coalition in coalitions) {
            long payoff = seller + coalition.members.Sum(id => utilities[id]);
            if (coalition.welfare > payoff) {
                Block block = new(coalition, payoff, coalition.welfare - payoff);
                if (!all.Any(previous => (previous.coalition.mask & coalition.mask) ==
                                         previous.coalition.mask))
                    minimal.Add(block);
                all.Add(block);
            }
        }
        return new(all, minimal);
    }
    public static long GspPrice(List<BidsIo.Participant> ranking,
                                int rank) => rank + 1 < ranking.Count ? ranking[rank + 1].bid : 0;
    public static Report.Rational SlotVcg(List<BidsIo.Participant> ranking,
                                          List<Report.Rational> rates, int rank) {
        Report.Rational payment = new(0);
        for (int t = rank + 1; t < Math.Min(ranking.Count, rates.Count + 1); t++) {
            Report.Rational next = t < rates.Count ? rates[t] : new(0);
            payment = payment.Add(rates[t - 1].Subtract(next).Multiply(ranking[t].value));
        }
        return payment;
    }
}
