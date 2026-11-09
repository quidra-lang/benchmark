using System;
using System.Collections.Generic;
using System.Linq;
public static class WdpSolver {
    public record Share(int item, Report.Rational amount, int? source);
    public record Improvement(int nodes, long welfare, List<int> numbers);
    public sealed class Result {
        public long? welfare;
        public List<int> numbers = new();
        public List<BidsIo.Bid> winning = new();
        public int nodes, pruned, leaves;
        public List<Improvement> improvements = new();
        public List<Share> shares;
        public Report.Rational bound;
    }
    public static List<Share> Shares(List<int> offered, List<BidsIo.Item> items,
                                     List<BidsIo.Bid> bids) {
        List<Share> result = new();
        foreach (int item in offered) {
            Report.Rational share = new(items[item].reserve);
            int? source = null;
            foreach (BidsIo.Bid bid in bids)
                if ((bid.bundle & (1 << item)) != 0) {
                    Report.Rational candidate = new(bid.amount, bid.Size());
                    if (candidate.CompareTo(share) > 0) {
                        share = candidate;
                        source = bid.number;
                    }
                }
            result.Add(new(item, share, source));
        }
        return result;
    }
    public static int CompareNumbers(List<int> a, List<int> b) {
        for (int i = 0; i < Math.Min(a.Count, b.Count); i++) {
            int c = a[i].CompareTo(b[i]);
            if (c != 0)
                return c;
        }
        return a.Count.CompareTo(b.Count);
    }
    sealed class Search {
        readonly List<int> offered;
        readonly List<BidsIo.Item> items;
        readonly List<BidsIo.Bid> bids;
        int all;
        public Result result = new();
        public Search(List<int> offered, List<BidsIo.Item> items, List<BidsIo.Bid> bids) {
            this.offered = offered;
            this.items = items;
            this.bids = bids.OrderBy(bid => bid.number).ToList();
            foreach (int i in offered)
                all |= 1 << i;
            result.shares = Shares(offered, items, this.bids);
            result.bound = new(0);
            foreach (Share share in result.shares)
                result.bound = result.bound.Add(share.amount);
        }
        public void Visit(int decided, int used, long welfare, List<int> chosen) {
            result.nodes++;
            if (decided == all) {
                result.leaves++;
                List<int> numbers = chosen.Order().ToList();
                if (result.welfare == null || welfare > result.welfare.Value ||
                    welfare == result.welfare.Value &&
                        CompareNumbers(numbers, result.numbers) < 0) {
                    result.welfare = welfare;
                    result.numbers = numbers;
                    result.improvements.Add(new(result.nodes, welfare, new(numbers)));
                }
                return;
            }
            List<BidsIo.Bid> available =
                bids.Where(bid => (bid.bundle & decided) == 0 &&
                                  (!bid.xor || (used & (1 << bid.bidder)) == 0))
                    .ToList();
            List<int> remaining = offered.Where(i => (decided & (1 << i)) == 0).ToList();
            Report.Rational bound = new(welfare);
            foreach (Share share in Shares(remaining, items, available))
                bound = bound.Add(share.amount);
            if (result.welfare != null && bound.CompareTo(new(result.welfare.Value)) < 0) {
                result.pruned++;
                return;
            }
            int first = remaining[0];
            foreach (BidsIo.Bid bid in available)
                if ((bid.bundle & (1 << first)) != 0) {
                    List<int> next = new(chosen) { bid.number };
                    Visit(decided | bid.bundle, bid.xor ? used | (1 << bid.bidder) : used,
                          welfare + bid.amount, next);
                }
            Visit(decided | (1 << first), used, welfare + items[first].reserve, chosen);
        }
    }
    public static Result Solve(List<int> offered, List<BidsIo.Item> items, List<BidsIo.Bid> bids) {
        Search search = new(offered, items, bids);
        search.Visit(0, 0, 0, new());
        foreach (int number in search.result.numbers)
            search.result.winning.Add(bids.First(bid => bid.number == number));
        return search.result;
    }
    public static List<BidsIo.Bid> GreedyOrder(List<BidsIo.Bid> bids) {
        List<BidsIo.Bid> order = new(bids);
        order.Sort((a, b) => {
            long left = a.amount * a.amount * b.Size(), right = b.amount * b.amount * a.Size();
            int c = right.CompareTo(left);
            return c != 0 ? c : a.number.CompareTo(b.number);
        });
        return order;
    }
    public static List<BidsIo.Bid> GreedySelect(List<BidsIo.Bid> bids) {
        List<BidsIo.Bid> chosen = new();
        int occupied = 0, used = 0;
        foreach (BidsIo.Bid bid in bids)
            if ((bid.bundle & occupied) == 0 && (!bid.xor || (used & (1 << bid.bidder)) == 0)) {
                chosen.Add(bid);
                occupied |= bid.bundle;
                if (bid.xor)
                    used |= 1 << bid.bidder;
            }
        return chosen;
    }
}
