import java.util.*;
import java.util.regex.Pattern;
public final class Main {
    static final List<String> FORMATS = List.of("first_price", "second_price", "english", "dutch",
                                                "all_pay"),
                              OUTCOMES = List.of("vcg", "greedy", "critical", "saa"),
                              MECHANISMS =
                                  List.of("vcg", "pay_as_bid", "greedy", "critical", "saa");
    static final Pattern BID_FORM = Pattern.compile("[a-z]+(?:\\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})"),
                         CTR_FORM = Pattern.compile("[1-9][0-9]*/[1-9][0-9]*");
    static String numbers(Collection<Integer> numbers) {
        List<Integer> sorted = new ArrayList<>(numbers);
        sorted.sort(Integer::compare);
        return sorted.isEmpty() ? "-"
                                : String.join("+", sorted.stream().map(Object::toString).toList());
    }
    static long sum(long[] values) {
        long total = 0;
        for (long value : values)
            total += value;
        return total;
    }
    static void count(Map<String, Long> counters, String name, long amount) {
        counters.merge(name, amount, Long::sum);
    }
    static long get(Map<String, Long> counters, String name) {
        return counters.getOrDefault(name, 0L);
    }
    record Rejection(int number, String name, String reason) {}
    record Below(BidsIo.Bid bid, long reserve) {}
    record Parsed(String error, int bundle, long amount) {}
    static final class Bidder {
        String name, language;
        List<BidsIo.Bid> valid = new ArrayList<>(), eligible = new ArrayList<>();
        Bidder(String name, String language) {
            this.name = name;
            this.language = language;
        }
    }
    record Allocation(List<BidsIo.Bid> winning, Map<Integer, Integer> owners, List<Integer> unsold,
                      long accepted, long retained, long welfare) {}
    static Allocation allocation(List<BidsIo.Bid> bids, List<Integer> offered,
                                 List<BidsIo.Item> items) {
        List<BidsIo.Bid> winning = new ArrayList<>(bids);
        winning.sort(Comparator.comparingInt(BidsIo.Bid::number));
        Map<Integer, Integer> owners = new HashMap<>();
        long accepted = 0, retained = 0;
        for (BidsIo.Bid bid : winning) {
            accepted += bid.amount();
            for (int item : offered)
                if ((bid.bundle() & (1 << item)) != 0)
                    owners.put(item, bid.bidder());
        }
        List<Integer> unsold = new ArrayList<>();
        for (int item : offered)
            if (!owners.containsKey(item)) {
                unsold.add(item);
                retained += items.get(item).reserve();
            }
        return new Allocation(winning, owners, unsold, accepted, retained, accepted + retained);
    }
    record Ascending(List<String> lines, long[] payments, long[] utilities, long revenue,
                     long retained, long welfare, int rounds, String reason, long exposure,
                     int exposed) {}
    static final class CombinatorialAuction {
        String name;
        BidsIo input;
        List<Integer> offered = new ArrayList<>();
        Map<String, Integer> itemIds = new HashMap<>();
        List<Bidder> bidders = new ArrayList<>();
        List<String> names = new ArrayList<>();
        List<BidsIo.Bid> valid = new ArrayList<>(), eligible = new ArrayList<>(), order;
        List<Below> below = new ArrayList<>();
        List<Rejection> rejected = new ArrayList<>();
        int bidCount, offeredMask;
        WdpSolver.Result optimal;
        Allocation exact, greedy;
        Map<Integer, Payments.Critical> critical;
        Map<Integer, Payments.Vcg> vcgDetails;
        long[] values, greedyValues, vcgPaid, vcgUtilities, criticalPaid, criticalUtilities;
        long vcgRevenue, criticalRevenue;
        Ascending saa;
        long param(String key) { return input.params.get(key); }
        CombinatorialAuction(BidsIo.RawAuction raw, BidsIo input) {
            this.input = input;
            name = raw.name;
            for (int i = 0; i < input.items.size(); i++)
                itemIds.put(input.items.get(i).name(), i);
            for (String item : raw.items) {
                int id = itemIds.get(item);
                offered.add(id);
                offeredMask |= 1 << id;
            }
            validate(raw.lines);
            for (Bidder bidder : bidders)
                names.add(bidder.name);
            optimal = WdpSolver.solve(offered, input.items, eligible);
            exact = allocation(optimal.winning, offered, input.items);
            order = WdpSolver.greedyOrder(eligible);
            greedy = allocation(WdpSolver.greedySelect(order), offered, input.items);
            critical = Payments.critical(order, greedy.winning(), input.items);
            vcgDetails = Payments.vcg(offered, input.items, eligible, optimal, bidders.size());
            int count = bidders.size();
            values = new long[count];
            greedyValues = new long[count];
            vcgPaid = new long[count];
            vcgUtilities = new long[count];
            criticalPaid = new long[count];
            criticalUtilities = new long[count];
            for (BidsIo.Bid bid : exact.winning())
                values[bid.bidder()] += bid.amount();
            for (BidsIo.Bid bid : greedy.winning()) {
                greedyValues[bid.bidder()] += bid.amount();
                criticalPaid[bid.bidder()] += critical.get(bid.number()).payment();
            }
            for (int i = 0; i < count; i++) {
                vcgPaid[i] = vcgDetails.containsKey(i) ? vcgDetails.get(i).payment() : 0;
                vcgUtilities[i] = values[i] - vcgPaid[i];
                criticalUtilities[i] = greedyValues[i] - criticalPaid[i];
            }
            vcgRevenue = sum(vcgPaid);
            criticalRevenue = sum(criticalPaid);
            saa = ascending();
        }
        Parsed bidError(String text, Bidder bidder) {
            if (!BID_FORM.matcher(text).matches())
                return new Parsed("malformed bid", 0, 0);
            String[] parts = text.split(":");
            String[] itemNames = parts[0].split("\\+");
            int mask = 0;
            for (String name : itemNames) {
                Integer id = itemIds.get(name);
                if (id == null)
                    return new Parsed("unknown item " + name, 0, 0);
                int bit = 1 << id;
                if ((offeredMask & bit) == 0)
                    return new Parsed("item not offered " + name, 0, 0);
                if ((mask & bit) != 0)
                    return new Parsed("duplicate item " + name, 0, 0);
                mask |= bit;
            }
            if (itemNames.length > param("max_bundle_size"))
                return new Parsed("bundle too large", 0, 0);
            long amount = Long.parseLong(parts[1]);
            if (amount == 0)
                return new Parsed("zero value", 0, 0);
            for (BidsIo.Bid earlier : bidder.valid)
                if (earlier.bundle() == mask)
                    return new Parsed("duplicate bundle " + earlier.number(), 0, 0);
            if (bidder.valid.size() >= param("max_bids_per_bidder"))
                return new Parsed("too many bids", 0, 0);
            return new Parsed(null, mask, amount);
        }
        void validate(List<BidsIo.BidderLine> lines) {
            Set<String> seen = new HashSet<>();
            for (BidsIo.BidderLine line : lines) {
                String error = seen.add(line.name()) ? null : "duplicate bidder";
                if (error == null && !line.language().equals("XOR") &&
                    !line.language().equals("OR"))
                    error = "bad language " + line.language();
                Bidder bidder = null;
                int id = bidders.size();
                if (error == null) {
                    bidder = new Bidder(line.name(), line.language());
                    bidders.add(bidder);
                }
                for (String text : line.bids()) {
                    bidCount++;
                    if (error != null) {
                        rejected.add(new Rejection(bidCount, line.name(), error));
                        continue;
                    }
                    Parsed parsed = bidError(text, bidder);
                    if (parsed.error() != null) {
                        rejected.add(new Rejection(bidCount, line.name(), parsed.error()));
                        continue;
                    }
                    BidsIo.Bid bid = new BidsIo.Bid(bidCount, id, parsed.bundle(), parsed.amount(),
                                                    line.language().equals("XOR"));
                    bidder.valid.add(bid);
                    valid.add(bid);
                    long reserve = 0;
                    for (int item : offered)
                        if ((bid.bundle() & (1 << item)) != 0)
                            reserve += input.items.get(item).reserve();
                    if (bid.amount() >= reserve) {
                        eligible.add(bid);
                        bidder.eligible.add(bid);
                    } else
                        below.add(new Below(bid, reserve));
                }
            }
        }
        Ascending ascending() {
            int count = bidders.size(), itemCount = input.items.size();
            long increment = param("saa_increment");
            List<List<Auctions.Candidate>> choices = new ArrayList<>();
            int[] eligibility = new int[count];
            for (int i = 0; i < count; i++) {
                Bidder bidder = bidders.get(i);
                List<Auctions.Candidate> candidates =
                    Auctions.candidates(bidder.valid, bidder.language.equals("XOR"));
                choices.add(candidates);
                for (Auctions.Candidate candidate : candidates)
                    eligibility[i] = Math.max(eligibility[i], Integer.bitCount(candidate.bundle()));
            }
            long[] prices = new long[itemCount];
            int[] holders = new int[itemCount], bidCounts = new int[itemCount],
                  bidRounds = new int[itemCount], lastRounds = new int[itemCount];
            Arrays.fill(holders, -1);
            for (int item : offered)
                prices[item] = input.items.get(item).reserve();
            long state = param("seed");
            List<String> lines = new ArrayList<>();
            lines.add("AUCTION " + name + " increment " + increment);
            int round = 0;
            String reason = null;
            for (round = 1; round <= param("round_cap"); round++) {
                int[] activities = new int[count], newByBidder = new int[count];
                List<List<Integer>> newByItem = new ArrayList<>();
                for (int item = 0; item < itemCount; item++)
                    newByItem.add(new ArrayList<>());
                int demand = 0;
                for (int id = 0; id < count; id++) {
                    int held = 0;
                    for (int item : offered)
                        if (holders[item] == id)
                            held |= 1 << item;
                    Auctions.Candidate chosen = null;
                    long bestSurplus = 0;
                    for (Auctions.Candidate candidate : choices.get(id))
                        if (Integer.bitCount(candidate.bundle() | held) <= eligibility[id]) {
                            long surplus = candidate.value();
                            for (int item : offered)
                                if ((candidate.bundle() & (1 << item)) != 0)
                                    surplus -=
                                        prices[item] + (holders[item] != -1 && holders[item] != id
                                                            ? increment
                                                            : 0);
                            if (surplus > bestSurplus) {
                                chosen = candidate;
                                bestSurplus = surplus;
                            }
                        }
                    int demanded = chosen == null ? 0 : chosen.bundle();
                    activities[id] = Integer.bitCount(demanded | held);
                    newByBidder[id] = demanded & ~held;
                    demand += Integer.bitCount(newByBidder[id]);
                    for (int item : offered)
                        if ((newByBidder[id] & (1 << item)) != 0)
                            newByItem.get(item).add(id);
                }
                if (demand > 0) {
                    StringBuilder line = new StringBuilder("ROUND " + round + " demand " + demand);
                    for (int id = 0; id < count; id++)
                        if (newByBidder[id] != 0)
                            line.append(' ')
                                .append(names.get(id))
                                .append(':')
                                .append(Report.bundle(newByBidder[id], input.items));
                    lines.add(line.toString());
                    for (int item : offered) {
                        List<Integer> competing = newByItem.get(item);
                        if (competing.isEmpty())
                            continue;
                        int selected = 0;
                        if (competing.size() >= 2) {
                            state = 48271 * state % 2147483647;
                            selected = (int)(state % competing.size());
                        }
                        if (holders[item] != -1)
                            prices[item] += increment;
                        holders[item] = competing.get(selected);
                        bidCounts[item] += competing.size();
                        bidRounds[item]++;
                        lastRounds[item] = round;
                    }
                    StringBuilder standing = new StringBuilder("STANDING");
                    for (int item : offered)
                        standing.append(' ')
                            .append(input.items.get(item).name())
                            .append('=')
                            .append(prices[item])
                            .append('@')
                            .append(holders[item] == -1 ? "-" : names.get(holders[item]));
                    lines.add(standing.toString());
                } else
                    lines.add("ROUND " + round + " none");
                List<String> changed = new ArrayList<>();
                for (int id = 0; id < count; id++)
                    if (activities[id] < eligibility[id]) {
                        eligibility[id] = activities[id];
                        changed.add(names.get(id) + "=" + eligibility[id]);
                    }
                if (!changed.isEmpty())
                    lines.add("ELIGIBILITY " + String.join(" ", changed));
                if (demand == 0 || round == param("round_cap")) {
                    reason = demand == 0 ? "quiet" : "cap";
                    break;
                }
            }
            lines.add("END rounds " + round + " " + reason);
            long retained = 0;
            for (int item : offered) {
                BidsIo.Item record = input.items.get(item);
                if (holders[item] == -1) {
                    retained += record.reserve();
                    lines.add("ITEM " + record.name() + " unsold reserve " + record.reserve());
                } else
                    lines.add("ITEM " + record.name() + " price " + prices[item] + " holder " +
                              names.get(holders[item]) + " bids " + bidCounts[item] + " rounds " +
                              bidRounds[item] + " last " + lastRounds[item]);
            }
            long[] payments = new long[count], utilities = new long[count];
            long totalValue = 0, exposure = 0;
            int exposed = 0;
            for (int id = 0; id < count; id++) {
                int won = 0;
                for (int item : offered)
                    if (holders[item] == id) {
                        won |= 1 << item;
                        payments[id] += prices[item];
                    }
                long value = Auctions.valueOf(choices.get(id), won);
                utilities[id] = value - payments[id];
                totalValue += value;
                if (utilities[id] < 0) {
                    exposure -= utilities[id];
                    exposed++;
                }
                lines.add("BIDDER " + names.get(id) + " won " + Report.bundle(won, input.items) +
                          " paid " + payments[id] + " value " + value + " utility " +
                          utilities[id] + " eligibility " + eligibility[id] +
                          (utilities[id] < 0 ? " exposed" : ""));
            }
            long revenue = sum(payments), welfare = totalValue + retained;
            lines.add("TOTAL revenue " + revenue + " welfare " + welfare + " efficiency " +
                      new Report.Rational(welfare, exact.welfare()) + " exposure " + exposure +
                      " exposed " + exposed);
            return new Ascending(lines, payments, utilities, revenue, retained, welfare, round,
                                 reason, exposure, exposed);
        }
        String unsold(List<Integer> items) {
            List<String> text = new ArrayList<>();
            for (int item : items)
                text.add(input.items.get(item).name());
            return text.isEmpty() ? "-" : String.join(" ", text);
        }
        List<String> wdpReport() {
            List<String> lines = new ArrayList<>();
            lines.add("AUCTION " + name + " items " + offered.size() + " bidders " +
                      bidders.size() + " bids " + bidCount + " valid " + valid.size() +
                      " eligible " + eligible.size());
            for (Bidder bidder : bidders)
                lines.add("BIDDER " + bidder.name + " " + bidder.language + " valid " +
                          bidder.valid.size() + " eligible " + bidder.eligible.size());
            for (Rejection rejection : rejected)
                lines.add("REJECT " + rejection.number() + " " + rejection.name() + " " +
                          rejection.reason());
            for (Below record : below) {
                BidsIo.Bid bid = record.bid();
                lines.add("BELOW_RESERVE " + bid.number() + " " + names.get(bid.bidder()) +
                          " value " + bid.amount() + " reserve " + record.reserve());
            }
            for (WdpSolver.Share share : optimal.shares)
                lines.add("SHARE " + input.items.get(share.item()).name() + " " + share.amount() +
                          " " + (share.source() == null ? "reserve" : "bid " + share.source()));
            lines.add("ROOT_BOUND " + optimal.bound);
            for (WdpSolver.Improvement record : optimal.improvements)
                lines.add("IMPROVE " + record.nodes() + " welfare " + record.welfare() + " bids " +
                          numbers(record.numbers()));
            lines.add("OPTIMAL welfare " + exact.welfare() + " accepted " + exact.accepted() +
                      " retained " + exact.retained() + " winners " + exact.winning().size());
            for (BidsIo.Bid bid : exact.winning())
                lines.add("WIN " + bid.number() + " " + names.get(bid.bidder()) + " " +
                          Report.bundle(bid.bundle(), input.items) + " " + bid.amount());
            lines.add("UNSOLD " + unsold(exact.unsold()));
            lines.add("SEARCH nodes " + optimal.nodes + " pruned " + optimal.pruned + " leaves " +
                      optimal.leaves + " improvements " + optimal.improvements.size());
            List<String> orderNumbers = new ArrayList<>();
            for (BidsIo.Bid bid : order)
                orderNumbers.add(Integer.toString(bid.number()));
            lines.add("GREEDY_ORDER " +
                      (orderNumbers.isEmpty() ? "-" : String.join(" ", orderNumbers)));
            lines.add("GREEDY welfare " + greedy.welfare() + " accepted " + greedy.accepted() +
                      " retained " + greedy.retained() + " winners " + greedy.winning().size() +
                      " efficiency " + new Report.Rational(greedy.welfare(), exact.welfare()));
            for (BidsIo.Bid bid : greedy.winning()) {
                Payments.Critical payment = critical.get(bid.number());
                lines.add(
                    "GWIN " + bid.number() + " " + names.get(bid.bidder()) + " " +
                    Report.bundle(bid.bundle(), input.items) + " " + bid.amount() + " critical " +
                    payment.payment() + " against " +
                    (payment.rival() == null ? "-" : Integer.toString(payment.rival().number())));
            }
            lines.add("GUNSOLD " + unsold(greedy.unsold()));
            for (int item : offered) {
                int demand = 0;
                for (BidsIo.Bid bid : eligible)
                    if ((bid.bundle() & (1 << item)) != 0)
                        demand++;
                Integer exactOwner = exact.owners().get(item), greedyOwner =
                                                                   greedy.owners().get(item);
                lines.add("ITEM " + input.items.get(item).name() + " reserve " +
                          input.items.get(item).reserve() + " demand " + demand + " optimal " +
                          (exactOwner == null ? "-" : names.get(exactOwner)) + " greedy " +
                          (greedyOwner == null ? "-" : names.get(greedyOwner)));
            }
            return lines;
        }
        List<String> vcgReport() {
            List<String> lines = new ArrayList<>();
            lines.add("AUCTION " + name + " welfare " + exact.welfare());
            for (int id = 0; id < names.size(); id++) {
                Payments.Vcg detail = vcgDetails.get(id);
                if (detail == null) {
                    lines.add("BIDDER " + names.get(id) + " lost");
                    continue;
                }
                List<Integer> won = new ArrayList<>();
                for (BidsIo.Bid bid : exact.winning())
                    if (bid.bidder() == id)
                        won.add(bid.number());
                lines.add("BIDDER " + names.get(id) + " won " + numbers(won) + " value " +
                          values[id] + " without " + detail.alternative().welfare +
                          " alternative " + numbers(detail.alternative().numbers) + " payment " +
                          detail.payment() + " utility " + vcgUtilities[id]);
            }
            lines.add("TOTAL revenue " + vcgRevenue + " pay_as_bid " + exact.accepted() +
                      " retained " + exact.retained() + " seller " +
                      (vcgRevenue + exact.retained()) + " bidders " + sum(vcgUtilities));
            for (int id = 0; id < names.size(); id++)
                lines.add("PAYMENTS " + names.get(id) + " vcg " + vcgPaid[id] + " pay_as_bid " +
                          values[id] + " greedy " + greedyValues[id] + " critical " +
                          criticalPaid[id] + " saa " + saa.payments()[id]);
            for (int id = 0; id < names.size(); id++)
                lines.add("UTILITIES " + names.get(id) + " vcg " + vcgUtilities[id] + " critical " +
                          criticalUtilities[id] + " saa " + saa.utilities()[id]);
            return lines;
        }
        String coalitionName(Payments.Coalition coalition) {
            List<String> members = new ArrayList<>();
            for (int id : coalition.members())
                members.add(names.get(id));
            return members.isEmpty() ? "-" : String.join("+", members);
        }
        List<String> coreReport(Map<String, Long> totals) {
            List<String> lines = new ArrayList<>();
            lines.add("AUCTION " + name + " bidders " + bidders.size());
            if (bidders.size() > param("core_max_bidders")) {
                lines.add("SKIPPED");
                count(totals, "skipped", 1);
                return lines;
            }
            count(totals, "checked", 1);
            List<Payments.Coalition> coalitions =
                Payments.coalitions(offered, input.items, eligible, bidders.size());
            lines.add("COALITIONS " + coalitions.size());
            long[] sellers = {vcgRevenue + exact.retained(), greedy.welfare(),
                              criticalRevenue + greedy.retained(), saa.revenue() + saa.retained()};
            long[][] utilities = {vcgUtilities, new long[bidders.size()], criticalUtilities,
                                  saa.utilities()};
            for (int outcome = 0; outcome < OUTCOMES.size(); outcome++) {
                String outcomeName = OUTCOMES.get(outcome);
                List<String> text = new ArrayList<>();
                for (long value : utilities[outcome])
                    text.add(Long.toString(value));
                lines.add("OUTCOME " + outcomeName + " seller " + sellers[outcome] + " utilities " +
                          String.join(" ", text));
                Payments.Blocking blocking =
                    Payments.blocking(coalitions, sellers[outcome], utilities[outcome]);
                for (Payments.Block block : blocking.minimal()) {
                    Payments.Coalition coalition = block.coalition();
                    lines.add("BLOCK " + coalitionName(coalition) + " welfare " +
                              coalition.welfare() + " payoff " + block.payoff() + " deficit " +
                              block.deficit() + " bids " + numbers(coalition.numbers()));
                }
                if (blocking.all().isEmpty()) {
                    lines.add("RESULT core");
                    count(totals, outcomeName, 1);
                } else {
                    Payments.Block worst = blocking.all().getFirst();
                    for (Payments.Block block : blocking.all())
                        if (block.deficit() > worst.deficit())
                            worst = block;
                    lines.add("RESULT blocked " + blocking.all().size() + " minimal " +
                              blocking.minimal().size() + " max_deficit " + worst.deficit() +
                              " by " + coalitionName(worst.coalition()));
                }
            }
            return lines;
        }
    }
    record Rates(String error, List<Report.Rational> values) {}
    record Mechanism(Integer winner, long price, Integer steps) {}
    record LotResult(String name, long[] utilities, long revenue) {}
    static final class Laboratory {
        BidsIo input;
        List<String> wdpLines = new ArrayList<>(), vcgLines = new ArrayList<>(),
                     coreLines = new ArrayList<>(), ascendingLines = new ArrayList<>(),
                     singleLines = new ArrayList<>(), summaryLines = new ArrayList<>();
        Map<String, Long> wdpTotals = new HashMap<>(), vcgTotals = new HashMap<>(),
                          coreTotals = new HashMap<>(), ascendingTotals = new HashMap<>(),
                          groupTotals = new HashMap<>();
        Laboratory() throws Exception {
            input = new BidsIo();
            summaryLines.add("mechanism,revenue,welfare,efficiency");
        }
        long param(String key) { return input.params.get(key); }
        void summaryRow(String name, String mechanism, Report.Rational revenue,
                        Report.Rational welfare, Report.Rational efficiency) {
            summaryLines.add(name + "/" + mechanism + "," + revenue + "," + welfare + "," +
                             efficiency);
        }
        void processAuctions() {
            for (String name : input.runs) {
                CombinatorialAuction auction =
                    new CombinatorialAuction(input.auctions.get(name), input);
                wdpLines.addAll(auction.wdpReport());
                vcgLines.addAll(auction.vcgReport());
                coreLines.addAll(auction.coreReport(coreTotals));
                ascendingLines.addAll(auction.saa.lines());
                count(wdpTotals, "auctions", 1);
                count(wdpTotals, "bids", auction.bidCount);
                count(wdpTotals, "valid", auction.valid.size());
                count(wdpTotals, "eligible", auction.eligible.size());
                count(wdpTotals, "nodes", auction.optimal.nodes);
                count(wdpTotals, "greedy_optimal",
                      auction.greedy.welfare() == auction.exact.welfare() ? 1 : 0);
                long[] revenues = {auction.vcgRevenue, auction.exact.accepted(),
                                   auction.greedy.accepted(), auction.criticalRevenue,
                                   auction.saa.revenue()};
                for (int i = 0; i < MECHANISMS.size(); i++) {
                    String mechanism = MECHANISMS.get(i);
                    count(vcgTotals, mechanism, revenues[i]);
                    long welfare = i <= 1   ? auction.exact.welfare()
                                   : i == 4 ? auction.saa.welfare()
                                            : auction.greedy.welfare();
                    summaryRow(name, mechanism, new Report.Rational(revenues[i]),
                               new Report.Rational(welfare),
                               new Report.Rational(welfare, auction.exact.welfare()));
                }
                count(ascendingTotals, "auctions", 1);
                count(ascendingTotals, "rounds", auction.saa.rounds());
                count(ascendingTotals, "capped", auction.saa.reason().equals("cap") ? 1 : 0);
                count(ascendingTotals, "exposed", auction.saa.exposed());
                count(ascendingTotals, "exposure", auction.saa.exposure());
            }
        }
        String duplicate(List<BidsIo.Participant> participants) {
            Set<String> seen = new HashSet<>();
            for (BidsIo.Participant participant : participants)
                if (!seen.add(participant.name()))
                    return participant.name();
            return null;
        }
        String validateLot(BidsIo.Group group) {
            if (group.participants.isEmpty())
                return "no bidders";
            String duplicate = duplicate(group.participants);
            if (duplicate != null)
                return "duplicate bidder " + duplicate;
            for (BidsIo.Participant participant : group.participants)
                if (participant.bid() > participant.value())
                    return "bid above value " + participant.name();
            return null;
        }
        Rates validateSlots(BidsIo.Group group) {
            List<Report.Rational> rates = new ArrayList<>();
            for (String text : group.arguments) {
                if (!CTR_FORM.matcher(text).matches())
                    return new Rates("bad ctr " + text, null);
                String[] f = text.split("/");
                Report.Rational rate =
                    new Report.Rational(Long.parseLong(f[0]), Long.parseLong(f[1]));
                if (rate.compareTo(new Report.Rational(1)) > 0 ||
                    !rates.isEmpty() && rate.compareTo(rates.getLast()) >= 0)
                    return new Rates("bad ctr " + text, null);
                rates.add(rate);
            }
            if (group.participants.isEmpty())
                return new Rates("no advertisers", null);
            String duplicate = duplicate(group.participants);
            if (duplicate != null)
                return new Rates("duplicate advertiser " + duplicate, null);
            return new Rates(null, rates);
        }
        List<String> lot(BidsIo.Group group) {
            List<BidsIo.Participant> participants = group.participants;
            long reserve = Long.parseLong(group.arguments.getFirst());
            List<Integer> eligible = new ArrayList<>();
            Integer first = null;
            int bestValue = 0;
            for (int i = 0; i < participants.size(); i++) {
                BidsIo.Participant participant = participants.get(i);
                if (participant.value() > participants.get(bestValue).value())
                    bestValue = i;
                if (participant.bid() >= reserve) {
                    eligible.add(i);
                    if (first == null || participant.bid() > participants.get(first).bid())
                        first = i;
                }
            }
            long optimum = Math.max(reserve, participants.get(bestValue).value());
            Integer efficient = participants.get(bestValue).value() >= reserve ? bestValue : null;
            List<String> lines = new ArrayList<>();
            lines.add("LOT " + group.name + " reserve " + reserve + " bidders " +
                      participants.size() + " efficient " +
                      (efficient == null ? "-" : participants.get(efficient).name()) + " optimum " +
                      optimum);
            long firstPrice = first == null ? 0 : participants.get(first).bid(),
                 secondPrice = efficient == null ? 0 : reserve;
            if (efficient != null)
                for (int i = 0; i < participants.size(); i++)
                    if (i != efficient && participants.get(i).value() >= reserve)
                        secondPrice = Math.max(secondPrice, participants.get(i).value());
            Auctions.Clock ascending =
                               Auctions.english(participants, reserve, param("english_increment")),
                           descending = Auctions.dutch(participants, reserve, param("dutch_start"),
                                                       param("dutch_decrement"));
            List<Mechanism> mechanisms = List.of(
                new Mechanism(first, firstPrice, null), new Mechanism(efficient, secondPrice, null),
                new Mechanism(ascending.winner(), ascending.price(), ascending.steps()),
                new Mechanism(descending.winner(), descending.price(), descending.steps()),
                new Mechanism(first, firstPrice, null));
            List<LotResult> results = new ArrayList<>();
            for (int i = 0; i < FORMATS.size(); i++) {
                String name = FORMATS.get(i);
                Mechanism mechanism = mechanisms.get(i);
                Integer winner = mechanism.winner();
                long price = mechanism.price(), revenue = price;
                long[] utilities = new long[participants.size()];
                if (name.equals("all_pay")) {
                    revenue = 0;
                    for (int index : eligible) {
                        utilities[index] = -participants.get(index).bid();
                        revenue += participants.get(index).bid();
                    }
                }
                long welfare;
                String line;
                if (winner == null) {
                    welfare = reserve;
                    line = name.toUpperCase(Locale.ROOT) + " unsold";
                } else {
                    utilities[winner] = participants.get(winner).value() - price;
                    welfare = participants.get(winner).value();
                    line = name.toUpperCase(Locale.ROOT) + " winner " +
                           participants.get(winner).name() + " price " + price + " utility " +
                           utilities[winner];
                }
                if (mechanism.steps() != null)
                    line += " steps " + mechanism.steps();
                Report.Rational efficiency = new Report.Rational(welfare, optimum);
                lines.add(line + " revenue " + revenue + " welfare " + welfare + " efficiency " +
                          efficiency);
                if (name.equals("english")) {
                    StringBuilder drops = new StringBuilder("ENGLISH_DROPS");
                    for (int j = 0; j < participants.size(); j++)
                        drops.append(' ')
                            .append(participants.get(j).name())
                            .append('=')
                            .append(ascending.drops().get(j) == null
                                        ? "-"
                                        : ascending.drops().get(j).toString());
                    lines.add(drops.toString());
                }
                results.add(new LotResult(name, utilities, revenue));
                summaryRow(group.name, name, new Report.Rational(revenue),
                           new Report.Rational(welfare), efficiency);
            }
            for (int i = 0; i < participants.size(); i++) {
                StringBuilder line = new StringBuilder("UTILITY " + participants.get(i).name());
                for (LotResult result : results)
                    line.append(' ').append(result.utilities()[i]);
                lines.add(line.toString());
            }
            results.sort(Comparator.comparingLong(LotResult::revenue).reversed());
            lines.add("RANKING " +
                      String.join(" ", results.stream().map(LotResult::name).toList()));
            return lines;
        }
        List<String> slots(BidsIo.Group group, List<Report.Rational> rates) {
            List<BidsIo.Participant> rankedBids = new ArrayList<>(group.participants),
                                     rankedValues = new ArrayList<>(group.participants);
            rankedBids.sort(Comparator.comparingLong(BidsIo.Participant::bid).reversed());
            rankedValues.sort(Comparator.comparingLong(BidsIo.Participant::value).reversed());
            int count = group.participants.size(), slots = rates.size();
            List<String> lines = new ArrayList<>();
            lines.add("SLOTS " + group.name + " slots " + slots + " advertisers " + count);
            Report.Rational gspRevenue = new Report.Rational(0),
                            gspWelfare = new Report.Rational(0),
                            vcgRevenue = new Report.Rational(0), optimum = new Report.Rational(0);
            for (int rank = 0; rank < Math.min(count, slots); rank++) {
                BidsIo.Participant bidder = rankedBids.get(rank);
                Report.Rational rate = rates.get(rank);
                long price = Payments.gspPrice(rankedBids, rank);
                Report.Rational payment = rate.multiply(price),
                                utility = rate.multiply(bidder.value() - price);
                gspRevenue = gspRevenue.add(payment);
                gspWelfare = gspWelfare.add(rate.multiply(bidder.value()));
                optimum = optimum.add(rate.multiply(rankedValues.get(rank).value()));
                lines.add("GSP " + (rank + 1) + " " + bidder.name() + " ctr " + rate + " bid " +
                          bidder.bid() + " price " + price + " payment " + payment + " utility " +
                          utility);
            }
            Report.Rational efficiency = gspWelfare.divide(optimum);
            lines.add("GSP_TOTAL revenue " + gspRevenue + " welfare " + gspWelfare +
                      " efficiency " + efficiency);
            for (int rank = 0; rank < Math.min(count, slots); rank++) {
                BidsIo.Participant bidder = rankedValues.get(rank);
                Report.Rational rate = rates.get(rank),
                                payment = Payments.slotVcg(rankedValues, rates, rank);
                vcgRevenue = vcgRevenue.add(payment);
                Report.Rational utility = rate.multiply(bidder.value()).subtract(payment);
                lines.add("VCG " + (rank + 1) + " " + bidder.name() + " ctr " + rate + " value " +
                          bidder.value() + " payment " + payment + " price " +
                          payment.divide(rate) + " utility " + utility);
            }
            lines.add("VCG_TOTAL revenue " + vcgRevenue + " welfare " + optimum + " efficiency 1");
            int violations = 0;
            for (int rank = 1; rank < Math.min(count, slots + 1); rank++) {
                BidsIo.Participant bidder = rankedBids.get(rank);
                Report.Rational rate = rank < slots ? rates.get(rank) : new Report.Rational(0),
                                stay = rate.multiply(bidder.value() -
                                                     Payments.gspPrice(rankedBids, rank)),
                                swap = rates.get(rank - 1).multiply(bidder.value() - bidder.bid());
                boolean violated = stay.compareTo(swap) < 0;
                if (violated)
                    violations++;
                lines.add("ENVY " + (rank + 1) + " " + bidder.name() + " stay " + stay + " swap " +
                          swap + " " + (violated ? "violated" : "ok"));
            }
            lines.add(violations == 0 ? "ENVY_FREE yes" : "ENVY_FREE no violations " + violations);
            int deviations = 0;
            for (int rank = 0; rank < count; rank++) {
                BidsIo.Participant bidder = rankedBids.get(rank);
                Report.Rational rate = rank < slots ? rates.get(rank) : new Report.Rational(0),
                                current = rate.multiply(bidder.value() -
                                                        Payments.gspPrice(rankedBids, rank));
                for (int target = 0; target < slots; target++) {
                    if (target == rank)
                        continue;
                    long price = target < rank ? (target < count ? rankedBids.get(target).bid() : 0)
                                               : Payments.gspPrice(rankedBids, target);
                    Report.Rational payoff = rates.get(target).multiply(bidder.value() - price);
                    if (payoff.compareTo(current) > 0) {
                        deviations++;
                        lines.add("DEVIATE " + bidder.name() + " from " + (rank + 1) + " to " +
                                  (target + 1) + " gain " + payoff.subtract(current));
                    }
                }
            }
            lines.add(deviations == 0 ? "NASH yes" : "NASH no deviations " + deviations);
            boolean equilibrium = violations == 0 && deviations == 0;
            lines.add("EQUILIBRIUM " + (equilibrium ? "yes" : "no"));
            count(groupTotals, "envy_free", violations == 0 ? 1 : 0);
            count(groupTotals, "nash", deviations == 0 ? 1 : 0);
            count(groupTotals, "equilibria", equilibrium ? 1 : 0);
            summaryRow(group.name, "gsp", gspRevenue, gspWelfare, efficiency);
            summaryRow(group.name, "vcg", vcgRevenue, optimum, new Report.Rational(1));
            return lines;
        }
        void processGroups() {
            for (BidsIo.Group group : input.groups) {
                boolean lot = group.kind.equals("lot");
                count(groupTotals, lot ? "lots" : "slot_groups", 1);
                String error;
                List<Report.Rational> rates = null;
                if (lot)
                    error = validateLot(group);
                else {
                    Rates result = validateSlots(group);
                    error = result.error();
                    rates = result.values();
                }
                if (error != null) {
                    singleLines.add(group.kind.toUpperCase(Locale.ROOT) + " " + group.name +
                                    " ERROR " + error);
                    count(groupTotals, "errors", 1);
                    continue;
                }
                singleLines.addAll(lot ? lot(group) : slots(group, rates));
            }
        }
        String totals(String prefix, Map<String, Long> totals, List<String> names) {
            StringBuilder line = new StringBuilder(prefix);
            for (String name : names)
                line.append(' ').append(name).append(' ').append(get(totals, name));
            return line.toString();
        }
        void totalLines() {
            wdpLines.add(totals(
                "TOTAL", wdpTotals,
                List.of("auctions", "bids", "valid", "eligible", "nodes", "greedy_optimal")));
            vcgLines.add(totals("OVERALL", vcgTotals, MECHANISMS));
            List<String> coreNames = new ArrayList<>(List.of("checked", "skipped"));
            coreNames.addAll(OUTCOMES);
            coreLines.add(totals("SUMMARY", coreTotals, coreNames));
            ascendingLines.add(
                totals("SUMMARY", ascendingTotals,
                       List.of("auctions", "rounds", "capped", "exposed", "exposure")));
            singleLines.add(totals(
                "SUMMARY", groupTotals,
                List.of("lots", "slot_groups", "errors", "envy_free", "nash", "equilibria")));
        }
        void run() throws Exception {
            processAuctions();
            processGroups();
            totalLines();
            Report.write("wdp.txt", wdpLines);
            Report.write("vcg.txt", vcgLines);
            Report.write("core_check.txt", coreLines);
            Report.write("ascending_log.txt", ascendingLines);
            Report.write("single_item.txt", singleLines);
            Report.write("summary.csv", summaryLines);
        }
    }
    public static void main(String[] args) throws Exception { new Laboratory().run(); }
}
