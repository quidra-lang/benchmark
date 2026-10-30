using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Text.RegularExpressions;
public static class Program {
    public static readonly List<string> FORMATS =
                                            new List<string> { "first_price", "second_price",
                                                               "english", "dutch", "all_pay" },
                                        OUTCOMES =
                                            new List<string> { "vcg", "greedy", "critical", "saa" },
                                        MECHANISMS =
                                            new List<string> { "vcg", "pay_as_bid", "greedy",
                                                               "critical", "saa" };
    public static readonly Regex BID_FORM = new(@"\A[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})\z",
                                                RegexOptions.CultureInvariant),
                                 CTR_FORM = new(@"\A[1-9][0-9]*/[1-9][0-9]*\z",
                                                RegexOptions.CultureInvariant);
    public static int BitCount(int value) => BitOperations.PopCount((uint)value);
    public static string Numbers(IEnumerable<int> numbers) {
        List<int> sorted = new(numbers);
        sorted.Sort();
        return sorted.Count == 0 ? "-" : string.Join("+", sorted);
    }
    public static long Sum(long[] values) {
        long total = 0;
        foreach (long value in values)
            total += value;
        return total;
    }
    public static void Count(Dictionary<string, long> counters, string name, long amount) {
        counters.AddCount(name, amount);
    }
    public static long Get(Dictionary<string, long> counters, string name) {
        return counters.GetValueOrDefault(name, 0L);
    }
    public record Rejection(int number, string name, string reason) {}
    public record Below(BidsIo.Bid bid, long reserve) {}
    public record Parsed(string error, int bundle, long amount) {}
    public sealed class Bidder {
        public string name, language;
        public List<BidsIo.Bid> valid = new(), eligible = new();
        public Bidder(string name, string language) {
            this.name = name;
            this.language = language;
        }
    }
    public record Allocation(List<BidsIo.Bid> winning, Dictionary<int, int> owners,
                             List<int> unsold, long accepted, long retained, long welfare) {}
    public static Allocation ComputeAllocation(List<BidsIo.Bid> bids, List<int> offered,
                                               List<BidsIo.Item> items) {
        List<BidsIo.Bid> winning = new(bids);
        winning.Sort((a, b) => a.number.CompareTo(b.number));
        Dictionary<int, int> owners = new();
        long accepted = 0, retained = 0;
        foreach (BidsIo.Bid bid in winning) {
            accepted += bid.amount;
            foreach (int item in offered)
                if ((bid.bundle & (1 << item)) != 0)
                    owners[item] = bid.bidder;
        }
        List<int> unsold = new();
        foreach (int item in offered)
            if (!owners.ContainsKey(item)) {
                unsold.Add(item);
                retained += items[item].reserve;
            }
        return new Allocation(winning, owners, unsold, accepted, retained, accepted + retained);
    }
    public record Ascending(List<string> lines, long[] payments, long[] utilities, long revenue,
                            long retained, long welfare, int rounds, string reason, long exposure,
                            int exposed) {}
    public sealed class CombinatorialAuction {
        public string name;
        public BidsIo input;
        public List<int> offered = new();
        public Dictionary<string, int> itemIds = new();
        public List<Bidder> bidders = new();
        public List<string> names = new();
        public List<BidsIo.Bid> valid = new(), eligible = new(), order;
        public List<Below> below = new();
        public List<Rejection> rejected = new();
        public int bidCount, offeredMask;
        public WdpSolver.Result optimal;
        public Allocation exact, greedy;
        public Dictionary<int, Payments.Critical> critical;
        public Dictionary<int, Payments.Vcg> vcgDetails;
        public long[] values, greedyValues, vcgPaid, vcgUtilities, criticalPaid, criticalUtilities;
        public long vcgRevenue, criticalRevenue;
        public Ascending saa;
        public long Param(string key) { return input.settings[key]; }
        public CombinatorialAuction(BidsIo.RawAuction raw, BidsIo input) {
            this.input = input;
            name = raw.name;
            for (int i = 0; i < input.items.Count; i++)
                itemIds[input.items[i].name] = i;
            foreach (string item in raw.items) {
                int id = itemIds[item];
                offered.Add(id);
                offeredMask |= 1 << id;
            }
            Validate(raw.lines);
            foreach (Bidder bidder in bidders)
                names.Add(bidder.name);
            optimal = WdpSolver.Solve(offered, input.items, eligible);
            exact = ComputeAllocation(optimal.winning, offered, input.items);
            order = WdpSolver.GreedyOrder(eligible);
            greedy = ComputeAllocation(WdpSolver.GreedySelect(order), offered, input.items);
            critical = Payments.CriticalPayments(order, greedy.winning, input.items);
            vcgDetails =
                Payments.VcgPayments(offered, input.items, eligible, optimal, bidders.Count);
            int count = bidders.Count;
            values = new long[count];
            greedyValues = new long[count];
            vcgPaid = new long[count];
            vcgUtilities = new long[count];
            criticalPaid = new long[count];
            criticalUtilities = new long[count];
            foreach (BidsIo.Bid bid in exact.winning)
                values[bid.bidder] += bid.amount;
            foreach (BidsIo.Bid bid in greedy.winning) {
                greedyValues[bid.bidder] += bid.amount;
                criticalPaid[bid.bidder] += critical[bid.number].payment;
            }
            for (int i = 0; i < count; i++) {
                vcgPaid[i] = vcgDetails.ContainsKey(i) ? vcgDetails[i].payment : 0;
                vcgUtilities[i] = values[i] - vcgPaid[i];
                criticalUtilities[i] = greedyValues[i] - criticalPaid[i];
            }
            vcgRevenue = Sum(vcgPaid);
            criticalRevenue = Sum(criticalPaid);
            saa = Ascending();
        }
        public Parsed BidError(string text, Bidder bidder) {
            if (!BID_FORM.IsMatch(text))
                return new Parsed("malformed bid", 0, 0);
            string[] parts = text.Split(":");
            string[] itemNames = parts[0].Split('+');
            int mask = 0;
            foreach (string name in itemNames) {
                if (!itemIds.TryGetValue(name, out int id))
                    return new Parsed("unknown item " + name, 0, 0);
                int bit = 1 << id;
                if ((offeredMask & bit) == 0)
                    return new Parsed("item not offered " + name, 0, 0);
                if ((mask & bit) != 0)
                    return new Parsed("duplicate item " + name, 0, 0);
                mask |= bit;
            }
            if (itemNames.Length > Param("max_bundle_size"))
                return new Parsed("bundle too large", 0, 0);
            long amount = long.Parse(parts[1]);
            if (amount == 0)
                return new Parsed("zero value", 0, 0);
            foreach (BidsIo.Bid earlier in bidder.valid)
                if (earlier.bundle == mask)
                    return new Parsed("duplicate bundle " + earlier.number, 0, 0);
            if (bidder.valid.Count >= Param("max_bids_per_bidder"))
                return new Parsed("too many bids", 0, 0);
            return new Parsed(null, mask, amount);
        }
        public void Validate(List<BidsIo.BidderLine> lines) {
            HashSet<string> seen = new();
            foreach (BidsIo.BidderLine line in lines) {
                string error = seen.Add(line.name) ? null : "duplicate bidder";
                if (error == null && !line.language.Equals("XOR") && !line.language.Equals("OR"))
                    error = "bad language " + line.language;
                Bidder bidder = null;
                int id = bidders.Count;
                if (error == null) {
                    bidder = new Bidder(line.name, line.language);
                    bidders.Add(bidder);
                }
                foreach (string text in line.bids) {
                    bidCount++;
                    if (error != null) {
                        rejected.Add(new Rejection(bidCount, line.name, error));
                        continue;
                    }
                    Parsed parsed = BidError(text, bidder);
                    if (parsed.error != null) {
                        rejected.Add(new Rejection(bidCount, line.name, parsed.error));
                        continue;
                    }
                    BidsIo.Bid bid = new BidsIo.Bid(bidCount, id, parsed.bundle, parsed.amount,
                                                    line.language.Equals("XOR"));
                    bidder.valid.Add(bid);
                    valid.Add(bid);
                    long reserve = 0;
                    foreach (int item in offered)
                        if ((bid.bundle & (1 << item)) != 0)
                            reserve += input.items[item].reserve;
                    if (bid.amount >= reserve) {
                        eligible.Add(bid);
                        bidder.eligible.Add(bid);
                    } else
                        below.Add(new Below(bid, reserve));
                }
            }
        }
        public Ascending Ascending() {
            int count = bidders.Count, itemCount = input.items.Count;
            long increment = Param("saa_increment");
            List<List<Auctions.Candidate>> choices = new();
            int[] eligibility = new int[count];
            for (int i = 0; i < count; i++) {
                Bidder bidder = bidders[i];
                List<Auctions.Candidate> candidates =
                    Auctions.Candidates(bidder.valid, bidder.language.Equals("XOR"));
                choices.Add(candidates);
                foreach (Auctions.Candidate candidate in candidates)
                    eligibility[i] = Math.Max(eligibility[i], BitCount(candidate.bundle));
            }
            long[] prices = new long[itemCount];
            int[] holders = new int[itemCount], bidCounts = new int[itemCount],
                  bidRounds = new int[itemCount], lastRounds = new int[itemCount];
            Array.Fill(holders, -1);
            foreach (int item in offered)
                prices[item] = input.items[item].reserve;
            long state = Param("seed");
            List<string> lines = new();
            lines.Add("AUCTION " + name + " increment " + increment);
            int round = 0;
            string reason = null;
            for (round = 1; round <= Param("round_cap"); round++) {
                int[] activities = new int[count], newByBidder = new int[count];
                List<List<int>> newByItem = new();
                for (int item = 0; item < itemCount; item++)
                    newByItem.Add(new());
                int demand = 0;
                for (int id = 0; id < count; id++) {
                    int held = 0;
                    foreach (int item in offered)
                        if (holders[item] == id)
                            held |= 1 << item;
                    Auctions.Candidate chosen = null;
                    long bestSurplus = 0;
                    foreach (Auctions.Candidate candidate in choices[id])
                        if (BitCount(candidate.bundle | held) <= eligibility[id]) {
                            long surplus = candidate.value;
                            foreach (int item in offered)
                                if ((candidate.bundle & (1 << item)) != 0)
                                    surplus -=
                                        prices[item] + (holders[item] != -1 && holders[item] != id
                                                            ? increment
                                                            : 0);
                            if (surplus > bestSurplus) {
                                chosen = candidate;
                                bestSurplus = surplus;
                            }
                        }
                    int demanded = chosen == null ? 0 : chosen.bundle;
                    activities[id] = BitCount(demanded | held);
                    newByBidder[id] = demanded & ~held;
                    demand += BitCount(newByBidder[id]);
                    foreach (int item in offered)
                        if ((newByBidder[id] & (1 << item)) != 0)
                            newByItem[item].Add(id);
                }
                if (demand > 0) {
                    StringBuilder line = new StringBuilder("ROUND " + round + " demand " + demand);
                    for (int id = 0; id < count; id++)
                        if (newByBidder[id] != 0)
                            line.Append(' ').Append(names[id]).Append(':').Append(
                                Report.Bundle(newByBidder[id], input.items));
                    lines.Add(line.ToString());
                    foreach (int item in offered) {
                        List<int> competing = newByItem[item];
                        if (competing.Count == 0)
                            continue;
                        int selected = 0;
                        if (competing.Count >= 2) {
                            state = 48271 * state % 2147483647;
                            selected = (int)(state % competing.Count);
                        }
                        if (holders[item] != -1)
                            prices[item] += increment;
                        holders[item] = competing[selected];
                        bidCounts[item] += competing.Count;
                        bidRounds[item]++;
                        lastRounds[item] = round;
                    }
                    StringBuilder standing = new StringBuilder("STANDING");
                    foreach (int item in offered)
                        standing.Append(' ')
                            .Append(input.items[item].name)
                            .Append('=')
                            .Append(prices[item])
                            .Append('@')
                            .Append(holders[item] == -1 ? "-" : names[holders[item]]);
                    lines.Add(standing.ToString());
                } else
                    lines.Add("ROUND " + round + " none");
                List<string> changed = new();
                for (int id = 0; id < count; id++)
                    if (activities[id] < eligibility[id]) {
                        eligibility[id] = activities[id];
                        changed.Add(names[id] + "=" + eligibility[id]);
                    }
                if (changed.Count != 0)
                    lines.Add("ELIGIBILITY " + string.Join(" ", changed));
                if (demand == 0 || round == Param("round_cap")) {
                    reason = demand == 0 ? "quiet" : "cap";
                    break;
                }
            }
            lines.Add("END rounds " + round + " " + reason);
            long retained = 0;
            foreach (int item in offered) {
                BidsIo.Item record = input.items[item];
                if (holders[item] == -1) {
                    retained += record.reserve;
                    lines.Add("ITEM " + record.name + " unsold reserve " + record.reserve);
                } else
                    lines.Add("ITEM " + record.name + " price " + prices[item] + " holder " +
                              names[holders[item]] + " bids " + bidCounts[item] + " rounds " +
                              bidRounds[item] + " last " + lastRounds[item]);
            }
            long[] payments = new long[count], utilities = new long[count];
            long totalValue = 0, exposure = 0;
            int exposed = 0;
            for (int id = 0; id < count; id++) {
                int won = 0;
                foreach (int item in offered)
                    if (holders[item] == id) {
                        won |= 1 << item;
                        payments[id] += prices[item];
                    }
                long value = Auctions.ValueOf(choices[id], won);
                utilities[id] = value - payments[id];
                totalValue += value;
                if (utilities[id] < 0) {
                    exposure -= utilities[id];
                    exposed++;
                }
                lines.Add("BIDDER " + names[id] + " won " + Report.Bundle(won, input.items) +
                          " paid " + payments[id] + " value " + value + " utility " +
                          utilities[id] + " eligibility " + eligibility[id] +
                          (utilities[id] < 0 ? " exposed" : ""));
            }
            long revenue = Sum(payments), welfare = totalValue + retained;
            lines.Add("TOTAL revenue " + revenue + " welfare " + welfare + " efficiency " +
                      new Report.Rational(welfare, exact.welfare) + " exposure " + exposure +
                      " exposed " + exposed);
            return new Ascending(lines, payments, utilities, revenue, retained, welfare, round,
                                 reason, exposure, exposed);
        }
        public string Unsold(List<int> items) {
            List<string> text = new();
            foreach (int item in items)
                text.Add(input.items[item].name);
            return text.Count == 0 ? "-" : string.Join(" ", text);
        }
        public List<string> WdpReport() {
            List<string> lines = new();
            lines.Add("AUCTION " + name + " items " + offered.Count + " bidders " + bidders.Count +
                      " bids " + bidCount + " valid " + valid.Count + " eligible " +
                      eligible.Count);
            foreach (Bidder bidder in bidders)
                lines.Add("BIDDER " + bidder.name + " " + bidder.language + " valid " +
                          bidder.valid.Count + " eligible " + bidder.eligible.Count);
            foreach (Rejection rejection in rejected)
                lines.Add("REJECT " + rejection.number + " " + rejection.name + " " +
                          rejection.reason);
            foreach (Below record in below) {
                BidsIo.Bid bid = record.bid;
                lines.Add("BELOW_RESERVE " + bid.number + " " + names[bid.bidder] + " value " +
                          bid.amount + " reserve " + record.reserve);
            }
            foreach (WdpSolver.Share share in optimal.shares)
                lines.Add("SHARE " + input.items[share.item].name + " " + share.amount + " " +
                          (share.source == null ? "reserve" : "bid " + share.source));
            lines.Add("ROOT_BOUND " + optimal.bound);
            foreach (WdpSolver.Improvement record in optimal.improvements)
                lines.Add("IMPROVE " + record.nodes + " welfare " + record.welfare + " bids " +
                          Numbers(record.numbers));
            lines.Add("OPTIMAL welfare " + exact.welfare + " accepted " + exact.accepted +
                      " retained " + exact.retained + " winners " + exact.winning.Count);
            foreach (BidsIo.Bid bid in exact.winning)
                lines.Add("WIN " + bid.number + " " + names[bid.bidder] + " " +
                          Report.Bundle(bid.bundle, input.items) + " " + bid.amount);
            lines.Add("UNSOLD " + Unsold(exact.unsold));
            lines.Add("SEARCH nodes " + optimal.nodes + " pruned " + optimal.pruned + " leaves " +
                      optimal.leaves + " improvements " + optimal.improvements.Count);
            List<string> orderNumbers = new();
            foreach (BidsIo.Bid bid in order)
                orderNumbers.Add(Convert.ToString(bid.number));
            lines.Add("GREEDY_ORDER " +
                      (orderNumbers.Count == 0 ? "-" : string.Join(" ", orderNumbers)));
            lines.Add("GREEDY welfare " + greedy.welfare + " accepted " + greedy.accepted +
                      " retained " + greedy.retained + " winners " + greedy.winning.Count +
                      " efficiency " + new Report.Rational(greedy.welfare, exact.welfare));
            foreach (BidsIo.Bid bid in greedy.winning) {
                Payments.Critical payment = critical[bid.number];
                lines.Add("GWIN " + bid.number + " " + names[bid.bidder] + " " +
                          Report.Bundle(bid.bundle, input.items) + " " + bid.amount + " critical " +
                          payment.payment + " against " +
                          (payment.rival == null ? "-" : Convert.ToString(payment.rival.number)));
            }
            lines.Add("GUNSOLD " + Unsold(greedy.unsold));
            foreach (int item in offered) {
                int demand = 0;
                foreach (BidsIo.Bid bid in eligible)
                    if ((bid.bundle & (1 << item)) != 0)
                        demand++;
                string exactOwner =
                           exact.owners.TryGetValue(item, out int exactId) ? names[exactId] : "-",
                       greedyOwner = greedy.owners.TryGetValue(item, out int greedyId)
                                         ? names[greedyId]
                                         : "-";
                lines.Add("ITEM " + input.items[item].name + " reserve " +
                          input.items[item].reserve + " demand " + demand + " optimal " +
                          exactOwner + " greedy " + greedyOwner);
            }
            return lines;
        }
        public List<string> VcgReport() {
            List<string> lines = new();
            lines.Add("AUCTION " + name + " welfare " + exact.welfare);
            for (int id = 0; id < names.Count; id++) {
                Payments.Vcg detail = vcgDetails.GetValueOrDefault(id);
                if (detail == null) {
                    lines.Add("BIDDER " + names[id] + " lost");
                    continue;
                }
                List<int> won = new();
                foreach (BidsIo.Bid bid in exact.winning)
                    if (bid.bidder == id)
                        won.Add(bid.number);
                lines.Add("BIDDER " + names[id] + " won " + Numbers(won) + " value " + values[id] +
                          " without " + detail.alternative.welfare + " alternative " +
                          Numbers(detail.alternative.numbers) + " payment " + detail.payment +
                          " utility " + vcgUtilities[id]);
            }
            lines.Add("TOTAL revenue " + vcgRevenue + " pay_as_bid " + exact.accepted +
                      " retained " + exact.retained + " seller " + (vcgRevenue + exact.retained) +
                      " bidders " + Sum(vcgUtilities));
            for (int id = 0; id < names.Count; id++)
                lines.Add("PAYMENTS " + names[id] + " vcg " + vcgPaid[id] + " pay_as_bid " +
                          values[id] + " greedy " + greedyValues[id] + " critical " +
                          criticalPaid[id] + " saa " + saa.payments[id]);
            for (int id = 0; id < names.Count; id++)
                lines.Add("UTILITIES " + names[id] + " vcg " + vcgUtilities[id] + " critical " +
                          criticalUtilities[id] + " saa " + saa.utilities[id]);
            return lines;
        }
        public string CoalitionName(Payments.Coalition coalition) {
            List<string> members = new();
            foreach (int id in coalition.members)
                members.Add(names[id]);
            return members.Count == 0 ? "-" : string.Join("+", members);
        }
        public List<string> CoreReport(Dictionary<string, long> totals) {
            List<string> lines = new();
            lines.Add("AUCTION " + name + " bidders " + bidders.Count);
            if (bidders.Count > Param("core_max_bidders")) {
                lines.Add("SKIPPED");
                Count(totals, "skipped", 1);
                return lines;
            }
            Count(totals, "checked", 1);
            List<Payments.Coalition> coalitions =
                Payments.Coalitions(offered, input.items, eligible, bidders.Count);
            lines.Add("COALITIONS " + coalitions.Count);
            long[] sellers = { vcgRevenue + exact.retained, greedy.welfare,
                               criticalRevenue + greedy.retained, saa.revenue + saa.retained };
            long[][] utilities = { vcgUtilities, new long[bidders.Count], criticalUtilities,
                                   saa.utilities };
            for (int outcome = 0; outcome < OUTCOMES.Count; outcome++) {
                string outcomeName = OUTCOMES[outcome];
                List<string> text = new();
                foreach (long value in utilities[outcome])
                    text.Add(Convert.ToString(value));
                lines.Add("OUTCOME " + outcomeName + " seller " + sellers[outcome] + " utilities " +
                          string.Join(" ", text));
                Payments.Blocking blocking =
                    Payments.FindBlocking(coalitions, sellers[outcome], utilities[outcome]);
                foreach (Payments.Block block in blocking.minimal) {
                    Payments.Coalition coalition = block.coalition;
                    lines.Add("BLOCK " + CoalitionName(coalition) + " welfare " +
                              coalition.welfare + " payoff " + block.payoff + " deficit " +
                              block.deficit + " bids " + Numbers(coalition.numbers));
                }
                if (blocking.all.Count == 0) {
                    lines.Add("RESULT core");
                    Count(totals, outcomeName, 1);
                } else {
                    Payments.Block worst = blocking.all[0];
                    foreach (Payments.Block block in blocking.all)
                        if (block.deficit > worst.deficit)
                            worst = block;
                    lines.Add("RESULT blocked " + blocking.all.Count + " minimal " +
                              blocking.minimal.Count + " max_deficit " + worst.deficit + " by " +
                              CoalitionName(worst.coalition));
                }
            }
            return lines;
        }
    }
    public record Rates(string error, List<Report.Rational> values) {}
    public record Mechanism(int? winner, long price, int? steps) {}
    public record LotResult(string name, long[] utilities, long revenue) {}
    public sealed class Laboratory {
        public BidsIo input;
        public List<string> wdpLines = new(), vcgLines = new(), coreLines = new(),
                            ascendingLines = new(), singleLines = new(), summaryLines = new();
        public Dictionary<string, long> wdpTotals = new(), vcgTotals = new(), coreTotals = new(),
                                        ascendingTotals = new(), groupTotals = new();
        public Laboratory() {
            input = new BidsIo();
            summaryLines.Add("mechanism,revenue,welfare,efficiency");
        }
        public long Param(string key) { return input.settings[key]; }
        public void SummaryRow(string name, string mechanism, Report.Rational revenue,
                               Report.Rational welfare, Report.Rational efficiency) {
            summaryLines.Add(name + "/" + mechanism + "," + revenue + "," + welfare + "," +
                             efficiency);
        }
        public void ProcessAuctions() {
            foreach (string name in input.runs) {
                CombinatorialAuction auction =
                    new CombinatorialAuction(input.auctions[name], input);
                wdpLines.AddRange(auction.WdpReport());
                vcgLines.AddRange(auction.VcgReport());
                coreLines.AddRange(auction.CoreReport(coreTotals));
                ascendingLines.AddRange(auction.saa.lines);
                Count(wdpTotals, "auctions", 1);
                Count(wdpTotals, "bids", auction.bidCount);
                Count(wdpTotals, "valid", auction.valid.Count);
                Count(wdpTotals, "eligible", auction.eligible.Count);
                Count(wdpTotals, "nodes", auction.optimal.nodes);
                Count(wdpTotals, "greedy_optimal",
                      auction.greedy.welfare == auction.exact.welfare ? 1 : 0);
                long[] revenues = { auction.vcgRevenue, auction.exact.accepted,
                                    auction.greedy.accepted, auction.criticalRevenue,
                                    auction.saa.revenue };
                for (int i = 0; i < MECHANISMS.Count; i++) {
                    string mechanism = MECHANISMS[i];
                    Count(vcgTotals, mechanism, revenues[i]);
                    long welfare = i <= 1   ? auction.exact.welfare
                                   : i == 4 ? auction.saa.welfare
                                            : auction.greedy.welfare;
                    SummaryRow(name, mechanism, new Report.Rational(revenues[i]),
                               new Report.Rational(welfare),
                               new Report.Rational(welfare, auction.exact.welfare));
                }
                Count(ascendingTotals, "auctions", 1);
                Count(ascendingTotals, "rounds", auction.saa.rounds);
                Count(ascendingTotals, "capped", auction.saa.reason.Equals("cap") ? 1 : 0);
                Count(ascendingTotals, "exposed", auction.saa.exposed);
                Count(ascendingTotals, "exposure", auction.saa.exposure);
            }
        }
        public string Duplicate(List<BidsIo.Participant> participants) {
            HashSet<string> seen = new();
            foreach (BidsIo.Participant participant in participants)
                if (!seen.Add(participant.name))
                    return participant.name;
            return null;
        }
        public string ValidateLot(BidsIo.Group group) {
            if (group.participants.Count == 0)
                return "no bidders";
            string duplicate = Duplicate(group.participants);
            if (duplicate != null)
                return "duplicate bidder " + duplicate;
            foreach (BidsIo.Participant participant in group.participants)
                if (participant.bid > participant.value)
                    return "bid above value " + participant.name;
            return null;
        }
        public Rates ValidateSlots(BidsIo.Group group) {
            List<Report.Rational> rates = new();
            foreach (string text in group.arguments) {
                if (!CTR_FORM.IsMatch(text))
                    return new Rates("bad ctr " + text, null);
                string[] f = text.Split("/");
                Report.Rational rate = new Report.Rational(long.Parse(f[0]), long.Parse(f[1]));
                if (rate.CompareTo(new Report.Rational(1)) > 0 ||
                    rates.Count != 0 && rate.CompareTo(rates[^1]) >= 0)
                    return new Rates("bad ctr " + text, null);
                rates.Add(rate);
            }
            if (group.participants.Count == 0)
                return new Rates("no advertisers", null);
            string duplicate = Duplicate(group.participants);
            if (duplicate != null)
                return new Rates("duplicate advertiser " + duplicate, null);
            return new Rates(null, rates);
        }
        public List<string> Lot(BidsIo.Group group) {
            List<BidsIo.Participant> participants = group.participants;
            long reserve = long.Parse(group.arguments[0]);
            List<int> eligible = new();
            int? first = null;
            int bestValue = 0;
            for (int i = 0; i < participants.Count; i++) {
                BidsIo.Participant participant = participants[i];
                if (participant.value > participants[bestValue].value)
                    bestValue = i;
                if (participant.bid >= reserve) {
                    eligible.Add(i);
                    if (first == null || participant.bid > participants[first.Value].bid)
                        first = i;
                }
            }
            long optimum = Math.Max(reserve, participants[bestValue].value);
            int? efficient = participants[bestValue].value >= reserve ? bestValue : null;
            List<string> lines = new();
            lines.Add("LOT " + group.name + " reserve " + reserve + " bidders " +
                      participants.Count + " efficient " +
                      (efficient == null ? "-" : participants[efficient.Value].name) + " optimum " +
                      optimum);
            long firstPrice = first == null ? 0 : participants[first.Value].bid,
                 secondPrice = efficient == null ? 0 : reserve;
            if (efficient != null)
                for (int i = 0; i < participants.Count; i++)
                    if (i != efficient && participants[i].value >= reserve)
                        secondPrice = Math.Max(secondPrice, participants[i].value);
            Auctions.Clock ascending =
                               Auctions.English(participants, reserve, Param("english_increment")),
                           descending = Auctions.Dutch(participants, reserve, Param("dutch_start"),
                                                       Param("dutch_decrement"));
            List<Mechanism> mechanisms = new List<Mechanism> {
                new Mechanism(first, firstPrice, null), new Mechanism(efficient, secondPrice, null),
                new Mechanism(ascending.winner, ascending.price, ascending.steps),
                new Mechanism(descending.winner, descending.price, descending.steps),
                new Mechanism(first, firstPrice, null)
            };
            List<LotResult> results = new();
            for (int i = 0; i < FORMATS.Count; i++) {
                string name = FORMATS[i];
                Mechanism mechanism = mechanisms[i];
                int? winner = mechanism.winner;
                long price = mechanism.price, revenue = price;
                long[] utilities = new long[participants.Count];
                if (name.Equals("all_pay")) {
                    revenue = 0;
                    foreach (int index in eligible) {
                        utilities[index] = -participants[index].bid;
                        revenue += participants[index].bid;
                    }
                }
                long welfare;
                string line;
                if (winner == null) {
                    welfare = reserve;
                    line = name.ToUpperInvariant() + " unsold";
                } else {
                    utilities[winner.Value] = participants[winner.Value].value - price;
                    welfare = participants[winner.Value].value;
                    line = name.ToUpperInvariant() + " winner " + participants[winner.Value].name +
                           " price " + price + " utility " + utilities[winner.Value];
                }
                if (mechanism.steps != null)
                    line += " steps " + mechanism.steps;
                Report.Rational efficiency = new Report.Rational(welfare, optimum);
                lines.Add(line + " revenue " + revenue + " welfare " + welfare + " efficiency " +
                          efficiency);
                if (name.Equals("english")) {
                    StringBuilder drops = new StringBuilder("ENGLISH_DROPS");
                    for (int j = 0; j < participants.Count; j++)
                        drops.Append(' ')
                            .Append(participants[j].name)
                            .Append('=')
                            .Append(ascending.drops[j] == null ? "-"
                                                               : ascending.drops[j].ToString());
                    lines.Add(drops.ToString());
                }
                results.Add(new LotResult(name, utilities, revenue));
                SummaryRow(group.name, name, new Report.Rational(revenue),
                           new Report.Rational(welfare), efficiency);
            }
            for (int i = 0; i < participants.Count; i++) {
                StringBuilder line = new StringBuilder("UTILITY " + participants[i].name);
                foreach (LotResult result in results)
                    line.Append(' ').Append(result.utilities[i]);
                lines.Add(line.ToString());
            }
            results = results.OrderByDescending(result => result.revenue).ToList();
            lines.Add("RANKING " + string.Join(" ", results.Select(result => result.name)));
            return lines;
        }
        public List<string> Slots(BidsIo.Group group, List<Report.Rational> rates) {
            List<BidsIo.Participant> rankedBids = new(group.participants),
                                     rankedValues = new(group.participants);
            rankedBids = rankedBids.OrderByDescending(participant => participant.bid).ToList();
            rankedValues =
                rankedValues.OrderByDescending(participant => participant.value).ToList();
            int count = group.participants.Count, slots = rates.Count;
            List<string> lines = new();
            lines.Add("SLOTS " + group.name + " slots " + slots + " advertisers " + count);
            Report.Rational gspRevenue = new Report.Rational(0),
                            gspWelfare = new Report.Rational(0),
                            vcgRevenue = new Report.Rational(0), optimum = new Report.Rational(0);
            for (int rank = 0; rank < Math.Min(count, slots); rank++) {
                BidsIo.Participant bidder = rankedBids[rank];
                Report.Rational rate = rates[rank];
                long price = Payments.GspPrice(rankedBids, rank);
                Report.Rational payment = rate.Multiply(price),
                                utility = rate.Multiply(bidder.value - price);
                gspRevenue = gspRevenue.Add(payment);
                gspWelfare = gspWelfare.Add(rate.Multiply(bidder.value));
                optimum = optimum.Add(rate.Multiply(rankedValues[rank].value));
                lines.Add("GSP " + (rank + 1) + " " + bidder.name + " ctr " + rate + " bid " +
                          bidder.bid + " price " + price + " payment " + payment + " utility " +
                          utility);
            }
            Report.Rational efficiency = gspWelfare.Divide(optimum);
            lines.Add("GSP_TOTAL revenue " + gspRevenue + " welfare " + gspWelfare +
                      " efficiency " + efficiency);
            for (int rank = 0; rank < Math.Min(count, slots); rank++) {
                BidsIo.Participant bidder = rankedValues[rank];
                Report.Rational rate = rates[rank],
                                payment = Payments.SlotVcg(rankedValues, rates, rank);
                vcgRevenue = vcgRevenue.Add(payment);
                Report.Rational utility = rate.Multiply(bidder.value).Subtract(payment);
                lines.Add("VCG " + (rank + 1) + " " + bidder.name + " ctr " + rate + " value " +
                          bidder.value + " payment " + payment + " price " + payment.Divide(rate) +
                          " utility " + utility);
            }
            lines.Add("VCG_TOTAL revenue " + vcgRevenue + " welfare " + optimum + " efficiency 1");
            int violations = 0;
            for (int rank = 1; rank < Math.Min(count, slots + 1); rank++) {
                BidsIo.Participant bidder = rankedBids[rank];
                Report.Rational rate = rank < slots ? rates[rank] : new Report.Rational(0),
                                stay = rate.Multiply(bidder.value -
                                                     Payments.GspPrice(rankedBids, rank)),
                                swap = rates[rank - 1].Multiply(bidder.value - bidder.bid);
                bool violated = stay.CompareTo(swap) < 0;
                if (violated)
                    violations++;
                lines.Add("ENVY " + (rank + 1) + " " + bidder.name + " stay " + stay + " swap " +
                          swap + " " + (violated ? "violated" : "ok"));
            }
            lines.Add(violations == 0 ? "ENVY_FREE yes" : "ENVY_FREE no violations " + violations);
            int deviations = 0;
            for (int rank = 0; rank < count; rank++) {
                BidsIo.Participant bidder = rankedBids[rank];
                Report.Rational rate = rank < slots ? rates[rank] : new Report.Rational(0),
                                current = rate.Multiply(bidder.value -
                                                        Payments.GspPrice(rankedBids, rank));
                for (int target = 0; target < slots; target++) {
                    if (target == rank)
                        continue;
                    long price = target < rank ? (target < count ? rankedBids[target].bid : 0)
                                               : Payments.GspPrice(rankedBids, target);
                    Report.Rational payoff = rates[target].Multiply(bidder.value - price);
                    if (payoff.CompareTo(current) > 0) {
                        deviations++;
                        lines.Add("DEVIATE " + bidder.name + " from " + (rank + 1) + " to " +
                                  (target + 1) + " gain " + payoff.Subtract(current));
                    }
                }
            }
            lines.Add(deviations == 0 ? "NASH yes" : "NASH no deviations " + deviations);
            bool equilibrium = violations == 0 && deviations == 0;
            lines.Add("EQUILIBRIUM " + (equilibrium ? "yes" : "no"));
            Count(groupTotals, "envy_free", violations == 0 ? 1 : 0);
            Count(groupTotals, "nash", deviations == 0 ? 1 : 0);
            Count(groupTotals, "equilibria", equilibrium ? 1 : 0);
            SummaryRow(group.name, "gsp", gspRevenue, gspWelfare, efficiency);
            SummaryRow(group.name, "vcg", vcgRevenue, optimum, new Report.Rational(1));
            return lines;
        }
        public void ProcessGroups() {
            foreach (BidsIo.Group group in input.groups) {
                bool lot = group.kind.Equals("lot");
                Count(groupTotals, lot ? "lots" : "slot_groups", 1);
                string error;
                List<Report.Rational> rates = null;
                if (lot)
                    error = ValidateLot(group);
                else {
                    Rates result = ValidateSlots(group);
                    error = result.error;
                    rates = result.values;
                }
                if (error != null) {
                    singleLines.Add(group.kind.ToUpperInvariant() + " " + group.name + " ERROR " +
                                    error);
                    Count(groupTotals, "errors", 1);
                    continue;
                }
                singleLines.AddRange(lot ? Lot(group) : Slots(group, rates));
            }
        }
        public string Totals(string prefix, Dictionary<string, long> totals, List<string> names) {
            StringBuilder line = new StringBuilder(prefix);
            foreach (string name in names)
                line.Append(' ').Append(name).Append(' ').Append(Get(totals, name));
            return line.ToString();
        }
        public void TotalLines() {
            wdpLines.Add(Totals("TOTAL", wdpTotals,
                                new List<string> { "auctions", "bids", "valid", "eligible", "nodes",
                                                   "greedy_optimal" }));
            vcgLines.Add(Totals("OVERALL", vcgTotals, MECHANISMS));
            List<string> coreNames = new(new List<string> { "checked", "skipped" });
            coreNames.AddRange(OUTCOMES);
            coreLines.Add(Totals("SUMMARY", coreTotals, coreNames));
            ascendingLines.Add(
                Totals("SUMMARY", ascendingTotals,
                       new List<string> { "auctions", "rounds", "capped", "exposed", "exposure" }));
            singleLines.Add(Totals("SUMMARY", groupTotals,
                                   new List<string> { "lots", "slot_groups", "errors", "envy_free",
                                                      "nash", "equilibria" }));
        }
        public void Run() {
            ProcessAuctions();
            ProcessGroups();
            TotalLines();
            Report.Write("wdp.txt", wdpLines);
            Report.Write("vcg.txt", vcgLines);
            Report.Write("core_check.txt", coreLines);
            Report.Write("ascending_log.txt", ascendingLines);
            Report.Write("single_item.txt", singleLines);
            Report.Write("summary.csv", summaryLines);
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        new Laboratory().Run();
    }
}
public static class CountHelpers {
    public static void AddCount<K>(this IDictionary<K, long> values, K key, long amount) {
        values.TryGetValue(key, out long value);
        values[key] = value + amount;
    }
}
