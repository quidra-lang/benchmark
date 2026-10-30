import java.util.*;
final class Auctions {
    record Candidate(int number, int bundle, long value) {}
    record Clock(Integer winner, long price, int steps, List<Long> drops) {}
    static List<Candidate> candidates(List<BidsIo.Bid> bids, boolean xor) {
        List<Candidate> result = new ArrayList<>();
        for (int number = 1; number < (1 << bids.size()); number++) {
            if (xor && Integer.bitCount(number) != 1)
                continue;
            int bundle = 0;
            long value = 0;
            boolean valid = true;
            for (int i = 0; i < bids.size(); i++)
                if ((number & (1 << i)) != 0) {
                    BidsIo.Bid bid = bids.get(i);
                    if ((bundle & bid.bundle()) != 0) {
                        valid = false;
                        break;
                    }
                    bundle |= bid.bundle();
                    value += bid.amount();
                }
            if (valid)
                result.add(new Candidate(number, bundle, value));
        }
        return result;
    }
    static long valueOf(List<Candidate> candidates, int items) {
        long value = 0;
        for (Candidate candidate : candidates)
            if ((candidate.bundle() & items) == candidate.bundle())
                value = Math.max(value, candidate.value());
        return value;
    }
    static Clock english(List<BidsIo.Participant> participants, long reserve, long increment) {
        long price = reserve, paid = 0;
        int steps = 0;
        Integer winner = null;
        List<Integer> remaining = new ArrayList<>();
        for (int i = 0; i < participants.size(); i++)
            if (participants.get(i).value() >= price)
                remaining.add(i);
        while (remaining.size() >= 2) {
            List<Integer> previous = remaining;
            price += increment;
            steps++;
            remaining = new ArrayList<>();
            for (int i = 0; i < participants.size(); i++)
                if (participants.get(i).value() >= price)
                    remaining.add(i);
            if (remaining.isEmpty()) {
                winner = previous.getFirst();
                paid = price - increment;
                break;
            }
        }
        if (!remaining.isEmpty()) {
            winner = remaining.getFirst();
            paid = price;
        }
        List<Long> drops = new ArrayList<>();
        for (BidsIo.Participant participant : participants) {
            long drop =
                participant.value() < reserve
                    ? reserve
                    : reserve + ((participant.value() - reserve) / increment + 1) * increment;
            drops.add(drop <= price ? drop : null);
        }
        return new Clock(winner, paid, steps, drops);
    }
    static Clock dutch(List<BidsIo.Participant> participants, long reserve, long start,
                       long decrement) {
        long price = start;
        int steps = 0;
        while (price >= reserve) {
            Integer winner = null;
            for (int i = 0; i < participants.size(); i++)
                if (participants.get(i).bid() >= price &&
                    (winner == null || participants.get(i).bid() > participants.get(winner).bid()))
                    winner = i;
            if (winner != null)
                return new Clock(winner, price, steps, List.of());
            price -= decrement;
            steps++;
        }
        return new Clock(null, 0, steps, List.of());
    }
}
