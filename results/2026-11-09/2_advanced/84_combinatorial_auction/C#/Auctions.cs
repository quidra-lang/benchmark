using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
public static class Auctions {
    public record Candidate(int number, int bundle, long value);
    public record Clock(int? winner, long price, int steps, List<long?> drops);
    public static List<Candidate> Candidates(List<BidsIo.Bid> bids, bool xor) {
        List<Candidate> result = new();
        for (int number = 1; number < (1 << bids.Count); number++) {
            if (xor && BitOperations.PopCount((uint)number) != 1)
                continue;
            int bundle = 0;
            long value = 0;
            bool valid = true;
            for (int i = 0; i < bids.Count; i++)
                if ((number & (1 << i)) != 0) {
                    BidsIo.Bid bid = bids[i];
                    if ((bundle & bid.bundle) != 0) {
                        valid = false;
                        break;
                    }
                    bundle |= bid.bundle;
                    value += bid.amount;
                }
            if (valid)
                result.Add(new(number, bundle, value));
        }
        return result;
    }
    public static long ValueOf(List<Candidate> candidates, int items) =>
        candidates.Where(candidate => (candidate.bundle & items) == candidate.bundle)
            .Select(candidate => candidate.value)
            .DefaultIfEmpty(0)
            .Max();
    public static Clock English(List<BidsIo.Participant> participants, long reserve,
                                long increment) {
        long price = reserve, paid = 0;
        int steps = 0;
        int? winner = null;
        List<int> remaining = Enumerable.Range(0, participants.Count)
                                  .Where(i => participants[i].value >= price)
                                  .ToList();
        while (remaining.Count >= 2) {
            List<int> previous = remaining;
            price += increment;
            steps++;
            remaining = Enumerable.Range(0, participants.Count)
                            .Where(i => participants[i].value >= price)
                            .ToList();
            if (remaining.Count == 0) {
                winner = previous[0];
                paid = price - increment;
                break;
            }
        }
        if (remaining.Count > 0) {
            winner = remaining[0];
            paid = price;
        }
        List<long?> drops = new();
        foreach (BidsIo.Participant participant in participants) {
            long drop = participant.value < reserve
                            ? reserve
                            : reserve + ((participant.value - reserve) / increment + 1) * increment;
            drops.Add(drop <= price ? drop : null);
        }
        return new(winner, paid, steps, drops);
    }
    public static Clock Dutch(List<BidsIo.Participant> participants, long reserve, long start,
                              long decrement) {
        long price = start;
        int steps = 0;
        while (price >= reserve) {
            int? winner = null;
            for (int i = 0; i < participants.Count; i++)
                if (participants[i].bid >= price &&
                    (winner == null || participants[i].bid > participants[winner.Value].bid))
                    winner = i;
            if (winner != null)
                return new(winner, price, steps, new());
            price -= decrement;
            steps++;
        }
        return new(null, 0, steps, new());
    }
}
