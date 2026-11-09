import java.util.*;
final class Payments {
    record Vcg(long payment, WdpSolver.Result alternative) {}
    record Critical(long payment, BidsIo.Bid rival) {}
    record Coalition(int mask, List<Integer> members, long welfare, List<Integer> numbers) {}
    record Block(Coalition coalition, long payoff, long deficit) {}
    record Blocking(List<Block> all, List<Block> minimal) {}
    static Map<Integer, Vcg> vcg(List<Integer> offered, List<BidsIo.Item> items,
                                 List<BidsIo.Bid> bids, WdpSolver.Result optimal, int count) {
        Map<Integer, Vcg> results = new HashMap<>();
        for (int bidder = 0; bidder < count; bidder++) {
            long value = 0;
            for (BidsIo.Bid bid : optimal.winning)
                if (bid.bidder() == bidder)
                    value += bid.amount();
            if (value == 0)
                continue;
            List<BidsIo.Bid> remaining = new ArrayList<>();
            for (BidsIo.Bid bid : bids)
                if (bid.bidder() != bidder)
                    remaining.add(bid);
            WdpSolver.Result alternative = WdpSolver.solve(offered, items, remaining);
            results.put(bidder,
                        new Vcg(alternative.welfare - (optimal.welfare - value), alternative));
        }
        return results;
    }
    static boolean earlier(long amount, BidsIo.Bid bid, BidsIo.Bid rival) {
        long left = amount * amount * rival.size(),
             right = rival.amount() * rival.amount() * bid.size();
        return left > right || left == right && bid.number() < rival.number();
    }
    static Map<Integer, Critical> critical(List<BidsIo.Bid> order, List<BidsIo.Bid> winning,
                                           List<BidsIo.Item> items) {
        Map<Integer, Critical> results = new HashMap<>();
        for (BidsIo.Bid bid : winning) {
            List<BidsIo.Bid> remaining = new ArrayList<>();
            for (BidsIo.Bid other : order)
                if (other.number() != bid.number())
                    remaining.add(other);
            BidsIo.Bid rival = null;
            for (BidsIo.Bid other : WdpSolver.greedySelect(remaining))
                if ((bid.bundle() & other.bundle()) != 0 ||
                    bid.xor() && bid.bidder() == other.bidder()) {
                    rival = other;
                    break;
                }
            long payment = 0;
            for (int i = 0; i < items.size(); i++)
                if ((bid.bundle() & (1 << i)) != 0)
                    payment += items.get(i).reserve();
            if (rival != null) {
                long low = 1, high = 1;
                while (!earlier(high, bid, rival))
                    high *= 2;
                while (low < high) {
                    long middle = (low + high) / 2;
                    if (earlier(middle, bid, rival))
                        high = middle;
                    else
                        low = middle + 1;
                }
                payment = Math.max(payment, low);
            }
            results.put(bid.number(), new Critical(payment, rival));
        }
        return results;
    }
    static void enumerate(List<Coalition> output, int count, int left, int start, int mask,
                          List<Integer> members, List<Integer> offered, List<BidsIo.Item> items,
                          List<BidsIo.Bid> bids) {
        if (left == 0) {
            List<BidsIo.Bid> allowed = new ArrayList<>();
            for (BidsIo.Bid bid : bids)
                if ((mask & (1 << bid.bidder())) != 0)
                    allowed.add(bid);
            WdpSolver.Result result = WdpSolver.solve(offered, items, allowed);
            output.add(new Coalition(mask, List.copyOf(members), result.welfare, result.numbers));
            return;
        }
        for (int id = start; id <= count - left; id++) {
            List<Integer> next = new ArrayList<>(members);
            next.add(id);
            enumerate(output, count, left - 1, id + 1, mask | (1 << id), next, offered, items,
                      bids);
        }
    }
    static List<Coalition> coalitions(List<Integer> offered, List<BidsIo.Item> items,
                                      List<BidsIo.Bid> bids, int count) {
        List<Coalition> output = new ArrayList<>();
        for (int size = 0; size <= count; size++)
            enumerate(output, count, size, 0, 0, List.of(), offered, items, bids);
        return output;
    }
    static Blocking blocking(List<Coalition> coalitions, long seller, long[] utilities) {
        List<Block> all = new ArrayList<>(), minimal = new ArrayList<>();
        for (Coalition coalition : coalitions) {
            long payoff = seller;
            for (int id : coalition.members())
                payoff += utilities[id];
            if (coalition.welfare() > payoff) {
                Block block = new Block(coalition, payoff, coalition.welfare() - payoff);
                boolean subset = false;
                for (Block previous : all)
                    if ((previous.coalition().mask() & coalition.mask()) ==
                        previous.coalition().mask())
                        subset = true;
                if (!subset)
                    minimal.add(block);
                all.add(block);
            }
        }
        return new Blocking(all, minimal);
    }
    static long gspPrice(List<BidsIo.Participant> ranking, int rank) {
        return rank + 1 < ranking.size() ? ranking.get(rank + 1).bid() : 0;
    }
    static Report.Rational slotVcg(List<BidsIo.Participant> ranking, List<Report.Rational> rates,
                                   int rank) {
        Report.Rational payment = new Report.Rational(0);
        for (int t = rank + 1; t < Math.min(ranking.size(), rates.size() + 1); t++) {
            Report.Rational next = t < rates.size() ? rates.get(t) : new Report.Rational(0);
            payment = payment.add(rates.get(t - 1).subtract(next).multiply(ranking.get(t).value()));
        }
        return payment;
    }
}
