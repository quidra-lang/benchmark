import java.util.*;
final class WdpSolver {
    record Share(int item, Report.Rational amount, Integer source) {}
    record Improvement(int nodes, long welfare, List<Integer> numbers) {}
    static final class Result {
        Long welfare;
        List<Integer> numbers = List.of();
        List<BidsIo.Bid> winning = new ArrayList<>();
        int nodes, pruned, leaves;
        List<Improvement> improvements = new ArrayList<>();
        List<Share> shares;
        Report.Rational bound;
    }
    static List<Share> shares(List<Integer> offered, List<BidsIo.Item> items,
                              List<BidsIo.Bid> bids) {
        List<Share> result = new ArrayList<>();
        for (int item : offered) {
            Report.Rational share = new Report.Rational(items.get(item).reserve());
            Integer source = null;
            for (BidsIo.Bid bid : bids)
                if ((bid.bundle() & (1 << item)) != 0) {
                    Report.Rational candidate = new Report.Rational(bid.amount(), bid.size());
                    if (candidate.compareTo(share) > 0) {
                        share = candidate;
                        source = bid.number();
                    }
                }
            result.add(new Share(item, share, source));
        }
        return result;
    }
    static int compareNumbers(List<Integer> a, List<Integer> b) {
        for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
            int c = Integer.compare(a.get(i), b.get(i));
            if (c != 0)
                return c;
        }
        return Integer.compare(a.size(), b.size());
    }
    static final class Search {
        List<Integer> offered;
        List<BidsIo.Item> items;
        List<BidsIo.Bid> bids;
        int all;
        Result result = new Result();
        Search(List<Integer> offered, List<BidsIo.Item> items, List<BidsIo.Bid> bids) {
            this.offered = offered;
            this.items = items;
            this.bids = new ArrayList<>(bids);
            this.bids.sort(Comparator.comparingInt(BidsIo.Bid::number));
            for (int i : offered)
                all |= 1 << i;
            result.shares = shares(offered, items, this.bids);
            result.bound = new Report.Rational(0);
            for (Share share : result.shares)
                result.bound = result.bound.add(share.amount());
        }
        void visit(int decided, int used, long welfare, List<Integer> chosen) {
            result.nodes++;
            if (decided == all) {
                result.leaves++;
                List<Integer> numbers = new ArrayList<>(chosen);
                numbers.sort(Integer::compare);
                if (result.welfare == null || welfare > result.welfare ||
                    welfare == result.welfare && compareNumbers(numbers, result.numbers) < 0) {
                    result.welfare = welfare;
                    result.numbers = numbers;
                    result.improvements.add(
                        new Improvement(result.nodes, welfare, List.copyOf(numbers)));
                }
                return;
            }
            List<BidsIo.Bid> available = new ArrayList<>();
            for (BidsIo.Bid bid : bids)
                if ((bid.bundle() & decided) == 0 &&
                    (!bid.xor() || (used & (1 << bid.bidder())) == 0))
                    available.add(bid);
            List<Integer> remaining = new ArrayList<>();
            for (int i : offered)
                if ((decided & (1 << i)) == 0)
                    remaining.add(i);
            Report.Rational bound = new Report.Rational(welfare);
            for (Share share : shares(remaining, items, available))
                bound = bound.add(share.amount());
            if (result.welfare != null &&
                bound.compareTo(new Report.Rational(result.welfare)) < 0) {
                result.pruned++;
                return;
            }
            int first = remaining.getFirst();
            for (BidsIo.Bid bid : available)
                if ((bid.bundle() & (1 << first)) != 0) {
                    List<Integer> next = new ArrayList<>(chosen);
                    next.add(bid.number());
                    visit(decided | bid.bundle(), bid.xor() ? used | (1 << bid.bidder()) : used,
                          welfare + bid.amount(), next);
                }
            visit(decided | (1 << first), used, welfare + items.get(first).reserve(), chosen);
        }
    }
    static Result solve(List<Integer> offered, List<BidsIo.Item> items, List<BidsIo.Bid> bids) {
        Search search = new Search(offered, items, bids);
        search.visit(0, 0, 0, List.of());
        for (int number : search.result.numbers)
            for (BidsIo.Bid bid : bids)
                if (bid.number() == number)
                    search.result.winning.add(bid);
        return search.result;
    }
    static List<BidsIo.Bid> greedyOrder(List<BidsIo.Bid> bids) {
        List<BidsIo.Bid> order = new ArrayList<>(bids);
        order.sort((a, b) -> {
            long left = a.amount() * a.amount() * b.size(), right =
                                                                b.amount() * b.amount() * a.size();
            int c = Long.compare(right, left);
            return c != 0 ? c : Integer.compare(a.number(), b.number());
        });
        return order;
    }
    static List<BidsIo.Bid> greedySelect(List<BidsIo.Bid> bids) {
        List<BidsIo.Bid> chosen = new ArrayList<>();
        int occupied = 0, used = 0;
        for (BidsIo.Bid bid : bids)
            if ((bid.bundle() & occupied) == 0 &&
                (!bid.xor() || (used & (1 << bid.bidder())) == 0)) {
                chosen.add(bid);
                occupied |= bid.bundle();
                if (bid.xor())
                    used |= 1 << bid.bidder();
            }
        return chosen;
    }
}
