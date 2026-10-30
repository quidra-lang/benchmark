#include "auction.hpp"
#include <algorithm>
#include <array>
#include <filesystem>
#include <numeric>
#include <set>

struct Bidder {
    std::string name, language;
    Bids valid, eligible;
};
struct Rejection {
    int number;
    std::string name, message;
};
struct Auction {
    std::string name;
    int offered = 0, total = 0;
    std::vector<Bidder> bidders;
    std::vector<Bid> storage;
    Bids valid, eligible;
    std::vector<Rejection> rejected;
};
static Money reserve(const std::vector<Item> &items, int mask) {
    Money result = 0;
    for (std::size_t i = 0; i < items.size(); ++i)
        if (mask & (1 << i))
            result += items[i].reserve;
    return result;
}
static bool digits(const std::string &value) {
    return !value.empty() &&
           std::all_of(value.begin(), value.end(), [](char c) { return c >= '0' && c <= '9'; });
}
static bool bidForm(const std::string &value, std::vector<std::string> &names, Money &amount) {
    std::size_t colon = value.find(':');
    if (colon == std::string::npos || value.find(':', colon + 1) != std::string::npos)
        return false;
    std::string number = value.substr(colon + 1);
    if (number.size() > 5 || !digits(number) || (number.size() > 1 && number[0] == '0'))
        return false;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = value.find('+', start);
        if (end == std::string::npos || end > colon)
            end = colon;
        std::string name = value.substr(start, end - start);
        if (name.empty() ||
            !std::all_of(name.begin(), name.end(), [](char c) { return c >= 'a' && c <= 'z'; }))
            return false;
        names.push_back(name);
        if (end == colon)
            break;
        start = end + 1;
    }
    amount = std::stoll(number);
    return true;
}
static Auction validate(const Input &input, const RawAuction &raw) {
    Auction auction;
    auction.name = raw.name;
    auction.storage.reserve(150);
    std::map<std::string, int> indices;
    for (int i = 0; i < static_cast<int>(input.items.size()); ++i)
        indices[input.items[i].name] = i;
    for (const std::string &name : raw.offered)
        auction.offered |= 1 << indices.at(name);
    std::set<std::string> seen;
    for (const BidLine &rawLine : raw.lines) {
        std::string error;
        if (seen.count(rawLine.name))
            error = "duplicate bidder";
        else if (rawLine.language != "XOR" && rawLine.language != "OR")
            error = "bad language " + rawLine.language;
        seen.insert(rawLine.name);
        if (!error.empty()) {
            for (std::size_t i = 0; i < rawLine.bids.size(); ++i)
                auction.rejected.push_back({++auction.total, rawLine.name, error});
            continue;
        }
        int bidder = static_cast<int>(auction.bidders.size());
        auction.bidders.push_back({rawLine.name, rawLine.language, {}, {}});
        std::map<int, int> bundles;
        for (const std::string &value : rawLine.bids) {
            ++auction.total;
            std::string message;
            std::vector<std::string> names;
            Money amount = 0;
            int mask = 0;
            if (!bidForm(value, names, amount))
                message = "malformed bid";
            else {
                for (const std::string &name : names) {
                    auto found = indices.find(name);
                    if (found == indices.end()) {
                        message = "unknown item " + name;
                        break;
                    }
                    int bit = 1 << found->second;
                    if (!(auction.offered & bit)) {
                        message = "item not offered " + name;
                        break;
                    }
                    if (mask & bit) {
                        message = "duplicate item " + name;
                        break;
                    }
                    mask |= bit;
                }
                if (message.empty()) {
                    if (static_cast<Money>(names.size()) > input.parameters.at("max_bundle_size"))
                        message = "bundle too large";
                    else if (amount == 0)
                        message = "zero value";
                    else if (bundles.count(mask))
                        message = text("duplicate bundle ", bundles.at(mask));
                    else if (static_cast<Money>(auction.bidders[bidder].valid.size()) >=
                             input.parameters.at("max_bids_per_bidder"))
                        message = "too many bids";
                }
            }
            if (!message.empty()) {
                auction.rejected.push_back({auction.total, rawLine.name, message});
                continue;
            }
            auction.storage.push_back({auction.total, bidder, mask, static_cast<int>(names.size()),
                                       amount, reserve(input.items, mask),
                                       rawLine.language == "XOR"});
            const Bid *bid = &auction.storage.back();
            bundles[mask] = bid->number;
            auction.valid.push_back(bid);
            auction.bidders[bidder].valid.push_back(bid);
            if (amount >= bid->reserve) {
                auction.eligible.push_back(bid);
                auction.bidders[bidder].eligible.push_back(bid);
            }
        }
    }
    return auction;
}
struct Allocation {
    Money accepted, retained;
    int unsold;
};
static Allocation allocation(const Input &input, int offered, const Bids &bids) {
    Money accepted = 0;
    int used = 0;
    for (const Bid *bid : bids) {
        accepted += bid->amount;
        used |= bid->mask;
    }
    return {accepted, reserve(input.items, offered & ~used), offered & ~used};
}
static Bids sorted(Bids bids) {
    std::sort(bids.begin(), bids.end(),
              [](const Bid *a, const Bid *b) { return a->number < b->number; });
    return bids;
}
static std::string unsold(const Input &input, int mask) {
    std::string result = bundle(input.items, mask);
    std::replace(result.begin(), result.end(), '+', ' ');
    return result;
}
static std::vector<std::string> wdpLines(const Input &input, const Auction &a,
                                         const SearchResult &r, const Bids &order,
                                         const Bids &greedy,
                                         const std::map<int, Critical> &critical) {
    std::vector<std::string> output;
    line(output, "AUCTION ", a.name, " items ", population(a.offered), " bidders ",
         a.bidders.size(), " bids ", a.total, " valid ", a.valid.size(), " eligible ",
         a.eligible.size());
    for (const Bidder &bidder : a.bidders)
        line(output, "BIDDER ", bidder.name, " ", bidder.language, " valid ", bidder.valid.size(),
             " eligible ", bidder.eligible.size());
    for (const Rejection &reject : a.rejected)
        line(output, "REJECT ", reject.number, " ", reject.name, " ", reject.message);
    for (const Bid *bid : a.valid)
        if (bid->amount < bid->reserve)
            line(output, "BELOW_RESERVE ", bid->number, " ", a.bidders[bid->bidder].name, " value ",
                 bid->amount, " reserve ", bid->reserve);
    for (int i = 0; i < static_cast<int>(input.items.size()); ++i)
        if (a.offered & (1 << i))
            line(output, "SHARE ", input.items[i].name, " ", r.shares[i], " ",
                 r.sources[i] ? text("bid ", r.sources[i]) : "reserve");
    line(output, "ROOT_BOUND ", r.bound);
    for (const Improvement &record : r.records)
        line(output, "IMPROVE ", record.node, " welfare ", record.welfare, " bids ",
             numberList(record.bids));
    Allocation optimal = allocation(input, a.offered, r.bids),
               approximate = allocation(input, a.offered, greedy);
    line(output, "OPTIMAL welfare ", r.welfare, " accepted ", optimal.accepted, " retained ",
         optimal.retained, " winners ", r.bids.size());
    for (const Bid *bid : r.bids)
        line(output, "WIN ", bid->number, " ", a.bidders[bid->bidder].name, " ",
             bundle(input.items, bid->mask), " ", bid->amount);
    line(output, "UNSOLD ", unsold(input, optimal.unsold));
    line(output, "SEARCH nodes ", r.nodes, " pruned ", r.pruned, " leaves ", r.leaves,
         " improvements ", r.improvements);
    std::vector<std::string> numbers;
    for (const Bid *bid : order)
        numbers.push_back(std::to_string(bid->number));
    line(output, "GREEDY_ORDER ", numbers.empty() ? "-" : join(numbers, " "));
    line(output, "GREEDY welfare ", approximate.accepted + approximate.retained, " accepted ",
         approximate.accepted, " retained ", approximate.retained, " winners ", greedy.size(),
         " efficiency ", Fraction(approximate.accepted + approximate.retained, r.welfare));
    for (const Bid *bid : sorted(greedy)) {
        Critical payment = critical.at(bid->number);
        line(output, "GWIN ", bid->number, " ", a.bidders[bid->bidder].name, " ",
             bundle(input.items, bid->mask), " ", bid->amount, " critical ", payment.payment,
             " against ", payment.rival ? std::to_string(payment.rival) : "-");
    }
    line(output, "GUNSOLD ", unsold(input, approximate.unsold));
    for (int i = 0; i < static_cast<int>(input.items.size()); ++i)
        if (a.offered & (1 << i)) {
            int demand = 0;
            std::string optimalName = "-", greedyName = "-";
            for (const Bid *bid : a.eligible)
                if (bid->mask & (1 << i))
                    ++demand;
            for (const Bid *bid : r.bids)
                if (bid->mask & (1 << i))
                    optimalName = a.bidders[bid->bidder].name;
            for (const Bid *bid : greedy)
                if (bid->mask & (1 << i))
                    greedyName = a.bidders[bid->bidder].name;
            line(output, "ITEM ", input.items[i].name, " reserve ", input.items[i].reserve,
                 " demand ", demand, " optimal ", optimalName, " greedy ", greedyName);
        }
    return output;
}
struct Ascending {
    std::vector<std::string> lines;
    std::vector<Money> payment, value, utility;
    Money revenue = 0, welfare = 0, retained = 0, exposure = 0;
    int exposed = 0, rounds = 0;
    bool capped = false;
};
static Ascending ascending(const Input &input, const Auction &a, Money optimum) {
    Ascending result;
    std::size_t n = a.bidders.size(), m = input.items.size();
    result.payment.resize(n);
    result.value.resize(n);
    result.utility.resize(n);
    std::vector<std::vector<Candidate>> byBidder;
    std::vector<int> eligibility(n), holder(m, -1), bidCounts(m), roundCounts(m), lastRound(m);
    std::vector<Money> prices;
    for (const Item &item : input.items)
        prices.push_back(item.reserve);
    for (std::size_t k = 0; k < n; ++k) {
        byBidder.push_back(candidates(a.bidders[k].valid, a.bidders[k].language == "XOR"));
        for (const Candidate &candidate : byBidder[k])
            eligibility[k] = std::max(eligibility[k], population(candidate.mask));
    }
    Money increment = input.parameters.at("saa_increment"), state = input.parameters.at("seed");
    line(result.lines, "AUCTION ", a.name, " increment ", increment);
    for (int round = 1;; ++round) {
        std::vector<int> newBids(n), activity(n);
        int demand = 0;
        for (std::size_t k = 0; k < n; ++k) {
            int held = 0;
            for (std::size_t j = 0; j < m; ++j)
                if (holder[j] == static_cast<int>(k))
                    held |= 1 << j;
            int chosen = 0;
            Money best = 0;
            for (const Candidate &candidate : byBidder[k]) {
                if (population(candidate.mask | held) > eligibility[k])
                    continue;
                Money cost = 0;
                for (std::size_t j = 0; j < m; ++j)
                    if (candidate.mask & (1 << j))
                        cost +=
                            prices[j] +
                            (holder[j] >= 0 && holder[j] != static_cast<int>(k) ? increment : 0);
                Money surplus = candidate.value - cost;
                if (surplus > best) {
                    best = surplus;
                    chosen = candidate.mask;
                }
            }
            activity[k] = population(chosen | held);
            newBids[k] = chosen & ~held;
            demand += population(newBids[k]);
        }
        if (!demand)
            line(result.lines, "ROUND ", round, " none");
        else {
            std::string demandLine = text("ROUND ", round, " demand ", demand);
            for (std::size_t k = 0; k < n; ++k)
                if (newBids[k])
                    demandLine +=
                        text(" ", a.bidders[k].name, ":", bundle(input.items, newBids[k]));
            result.lines.push_back(demandLine);
            for (std::size_t j = 0; j < m; ++j)
                if (a.offered & (1 << j)) {
                    std::vector<int> bidders;
                    for (std::size_t k = 0; k < n; ++k)
                        if (newBids[k] & (1 << j))
                            bidders.push_back(static_cast<int>(k));
                    if (bidders.empty())
                        continue;
                    bidCounts[j] += static_cast<int>(bidders.size());
                    ++roundCounts[j];
                    lastRound[j] = round;
                    std::size_t chosen = 0;
                    if (bidders.size() > 1) {
                        state = 48271 * state % 2147483647;
                        chosen =
                            static_cast<std::size_t>(state % static_cast<Money>(bidders.size()));
                    }
                    if (holder[j] >= 0)
                        prices[j] += increment;
                    holder[j] = bidders[chosen];
                }
            std::string standing = "STANDING";
            for (std::size_t j = 0; j < m; ++j)
                if (a.offered & (1 << j))
                    standing += text(" ", input.items[j].name, "=", prices[j], "@",
                                     holder[j] < 0 ? "-" : a.bidders[holder[j]].name);
            result.lines.push_back(standing);
        }
        std::string changes;
        for (std::size_t k = 0; k < n; ++k)
            if (activity[k] < eligibility[k]) {
                eligibility[k] = activity[k];
                changes += text(" ", a.bidders[k].name, "=", eligibility[k]);
            }
        if (!changes.empty())
            result.lines.push_back("ELIGIBILITY" + changes);
        if (!demand || round == input.parameters.at("round_cap")) {
            result.rounds = round;
            result.capped = demand != 0;
            break;
        }
    }
    line(result.lines, "END rounds ", result.rounds, " ", result.capped ? "cap" : "quiet");
    std::vector<int> won(n);
    for (std::size_t j = 0; j < m; ++j)
        if (a.offered & (1 << j)) {
            if (holder[j] < 0) {
                result.retained += input.items[j].reserve;
                line(result.lines, "ITEM ", input.items[j].name, " unsold reserve ",
                     input.items[j].reserve);
            } else {
                int k = holder[j];
                won[k] |= 1 << j;
                result.payment[k] += prices[j];
                result.revenue += prices[j];
                line(result.lines, "ITEM ", input.items[j].name, " price ", prices[j], " holder ",
                     a.bidders[k].name, " bids ", bidCounts[j], " rounds ", roundCounts[j],
                     " last ", lastRound[j]);
            }
        }
    result.welfare = result.retained;
    for (std::size_t k = 0; k < n; ++k) {
        result.value[k] = candidateValue(byBidder[k], won[k]);
        result.utility[k] = result.value[k] - result.payment[k];
        result.welfare += result.value[k];
        if (result.utility[k] < 0) {
            ++result.exposed;
            result.exposure -= result.utility[k];
        }
        line(result.lines, "BIDDER ", a.bidders[k].name, " won ", bundle(input.items, won[k]),
             " paid ", result.payment[k], " value ", result.value[k], " utility ",
             result.utility[k], " eligibility ", eligibility[k],
             result.utility[k] < 0 ? " exposed" : "");
    }
    line(result.lines, "TOTAL revenue ", result.revenue, " welfare ", result.welfare,
         " efficiency ", Fraction(result.welfare, optimum), " exposure ", result.exposure,
         " exposed ", result.exposed);
    return result;
}
static void append(std::vector<std::string> &out, const std::vector<std::string> &in) {
    out.insert(out.end(), in.begin(), in.end());
}
static std::string moneyList(const std::vector<Money> &values) {
    std::vector<std::string> parts;
    for (Money value : values)
        parts.push_back(std::to_string(value));
    return join(parts, " ");
}
static std::string coalitionName(const Auction &a, const Coalition &c) {
    std::vector<std::string> names;
    for (int member : c.members)
        names.push_back(a.bidders[member].name);
    return names.empty() ? "-" : join(names, "+");
}
class Laboratory {
    Input input = readInput();
    std::vector<std::string> wdp, vcg, core, ascendingLog, single,
        summary = {"mechanism,revenue,welfare,efficiency"};
    int bidTotal = 0, validTotal = 0, eligibleTotal = 0, nodeTotal = 0, greedyOptimal = 0,
        checked = 0, skipped = 0, coreCounts[4] = {0}, roundTotal = 0, capped = 0, exposed = 0,
        lots = 0, slotGroups = 0, errors = 0, envyFree = 0, nash = 0, equilibria = 0;
    Money revenueTotals[5] = {0}, exposure = 0;
    void summaryRow(const std::string &name, const std::string &format, Fraction revenue,
                    Fraction welfare, Fraction efficiency) {
        line(summary, name, "/", format, ",", revenue, ",", welfare, ",", efficiency);
    }
    void processAuction(const Auction &a) {
        SearchResult optimum = solveWdp(input.items, a.offered, a.eligible);
        Bids order = greedyOrder(a.eligible), greedy = greedySelect(order);
        std::map<int, Critical> critical = criticalPayments(order, greedy);
        std::vector<VcgPayment> payments =
            vcgPayments(input.items, a.offered, static_cast<int>(a.bidders.size()), a.eligible,
                        optimum.bids, optimum.welfare);
        Ascending saa = ascending(input, a, optimum.welfare);
        Allocation optimal = allocation(input, a.offered, optimum.bids),
                   approximate = allocation(input, a.offered, greedy);
        Money greedyWelfare = approximate.accepted + approximate.retained;
        std::size_t n = a.bidders.size();
        std::vector<Money> vcgUtility(n), greedyPay(n), criticalPay(n), criticalUtility(n);
        Money vcgRevenue = 0, criticalRevenue = 0, utilitySum = 0;
        for (std::size_t k = 0; k < n; ++k) {
            vcgUtility[k] = payments[k].utility;
            vcgRevenue += payments[k].payment;
            utilitySum += payments[k].utility;
        }
        for (const Bid *bid : greedy) {
            Money payment = critical.at(bid->number).payment;
            greedyPay[bid->bidder] += bid->amount;
            criticalPay[bid->bidder] += payment;
            criticalUtility[bid->bidder] += bid->amount - payment;
            criticalRevenue += payment;
        }
        append(wdp, wdpLines(input, a, optimum, order, greedy, critical));
        bidTotal += a.total;
        validTotal += static_cast<int>(a.valid.size());
        eligibleTotal += static_cast<int>(a.eligible.size());
        nodeTotal += optimum.nodes;
        greedyOptimal += greedyWelfare == optimum.welfare;
        line(vcg, "AUCTION ", a.name, " welfare ", optimum.welfare);
        for (std::size_t k = 0; k < n; ++k) {
            const VcgPayment &p = payments[k];
            if (p.won.empty())
                line(vcg, "BIDDER ", a.bidders[k].name, " lost");
            else
                line(vcg, "BIDDER ", a.bidders[k].name, " won ", numberList(p.won), " value ",
                     p.value, " without ", p.without, " alternative ", numberList(p.alternative),
                     " payment ", p.payment, " utility ", p.utility);
        }
        line(vcg, "TOTAL revenue ", vcgRevenue, " pay_as_bid ", optimal.accepted, " retained ",
             optimal.retained, " seller ", vcgRevenue + optimal.retained, " bidders ", utilitySum);
        for (std::size_t k = 0; k < n; ++k)
            line(vcg, "PAYMENTS ", a.bidders[k].name, " vcg ", payments[k].payment, " pay_as_bid ",
                 payments[k].value, " greedy ", greedyPay[k], " critical ", criticalPay[k], " saa ",
                 saa.payment[k]);
        for (std::size_t k = 0; k < n; ++k)
            line(vcg, "UTILITIES ", a.bidders[k].name, " vcg ", vcgUtility[k], " critical ",
                 criticalUtility[k], " saa ", saa.utility[k]);
        line(core, "AUCTION ", a.name, " bidders ", n);
        if (static_cast<Money>(n) > input.parameters.at("core_max_bidders")) {
            ++skipped;
            core.push_back("SKIPPED");
        } else {
            ++checked;
            std::vector<Coalition> combinations =
                coalitions(input.items, a.offered, static_cast<int>(n), a.eligible);
            line(core, "COALITIONS ", combinations.size());
            const char *names[] = {"vcg", "greedy", "critical", "saa"};
            Money sellers[] = {vcgRevenue + optimal.retained, greedyWelfare,
                               criticalRevenue + approximate.retained, saa.revenue + saa.retained};
            std::vector<Money> utilities[] = {vcgUtility, std::vector<Money>(n), criticalUtility,
                                              saa.utility};
            for (int i = 0; i < 4; ++i) {
                line(core, "OUTCOME ", names[i], " seller ", sellers[i], " utilities ",
                     moneyList(utilities[i]));
                std::vector<Blocking> blocked = blockers(combinations, sellers[i], utilities[i]);
                int minimal = 0;
                for (const Blocking &b : blocked)
                    if (b.minimal) {
                        ++minimal;
                        const Coalition &c = combinations[b.coalition];
                        line(core, "BLOCK ", coalitionName(a, c), " welfare ", c.welfare,
                             " payoff ", b.payoff, " deficit ", b.deficit, " bids ",
                             numberList(c.bids));
                    }
                if (blocked.empty()) {
                    ++coreCounts[i];
                    core.push_back("RESULT core");
                } else {
                    const Blocking *best = &blocked.front();
                    for (const Blocking &b : blocked)
                        if (b.deficit > best->deficit)
                            best = &b;
                    line(core, "RESULT blocked ", blocked.size(), " minimal ", minimal,
                         " max_deficit ", best->deficit, " by ",
                         coalitionName(a, combinations[best->coalition]));
                }
            }
        }
        append(ascendingLog, saa.lines);
        roundTotal += saa.rounds;
        capped += saa.capped;
        exposed += saa.exposed;
        exposure += saa.exposure;
        const char *formats[] = {"vcg", "pay_as_bid", "greedy", "critical", "saa"};
        Money revenues[] = {vcgRevenue, optimal.accepted, approximate.accepted, criticalRevenue,
                            saa.revenue},
              welfares[] = {optimum.welfare, optimum.welfare, greedyWelfare, greedyWelfare,
                            saa.welfare};
        for (int i = 0; i < 5; ++i) {
            revenueTotals[i] += revenues[i];
            summaryRow(a.name, formats[i], Fraction(revenues[i]), Fraction(welfares[i]),
                       Fraction(welfares[i], optimum.welfare));
        }
    }
    void processLot(const Group &g) {
        ++lots;
        std::string error;
        if (g.participants.empty())
            error = "no bidders";
        std::set<std::string> seen;
        if (error.empty())
            for (const Participant &p : g.participants) {
                if (seen.count(p.name)) {
                    error = "duplicate bidder " + p.name;
                    break;
                }
                seen.insert(p.name);
            }
        if (error.empty())
            for (const Participant &p : g.participants)
                if (p.bid > p.value) {
                    error = "bid above value " + p.name;
                    break;
                }
        if (!error.empty()) {
            ++errors;
            line(single, "LOT ", g.name, " ERROR ", error);
            return;
        }
        const std::vector<Participant> &participants = g.participants;
        Money reservePrice = std::stoll(g.arguments.front());
        int efficient = 0, first = -1;
        for (int i = 0; i < static_cast<int>(participants.size()); ++i) {
            if (participants[i].value > participants[efficient].value)
                efficient = i;
            if (participants[i].bid >= reservePrice &&
                (first < 0 || participants[i].bid > participants[first].bid))
                first = i;
        }
        Money optimum = std::max(reservePrice, participants[efficient].value);
        line(single, "LOT ", g.name, " reserve ", reservePrice, " bidders ", participants.size(),
             " efficient ",
             participants[efficient].value >= reservePrice ? participants[efficient].name : "-",
             " optimum ", optimum);
        int second = participants[efficient].value >= reservePrice ? efficient : -1;
        Money secondPrice = reservePrice;
        for (int i = 0; i < static_cast<int>(participants.size()); ++i)
            if (i != second && participants[i].value >= reservePrice)
                secondPrice = std::max(secondPrice, participants[i].value);
        ClockResult eng = english(participants, reservePrice,
                                  input.parameters.at("english_increment")),
                    dut = dutch(participants, reservePrice, input.parameters.at("dutch_start"),
                                input.parameters.at("dutch_decrement"));
        int winners[] = {first, second, eng.winner, dut.winner, first};
        Money firstPrice = first < 0 ? 0 : participants[first].bid,
              prices[] = {firstPrice, secondPrice, eng.price, dut.price, firstPrice};
        const char *labels[] = {"FIRST_PRICE", "SECOND_PRICE", "ENGLISH", "DUTCH", "ALL_PAY"},
                   *formats[] = {"first_price", "second_price", "english", "dutch", "all_pay"};
        std::array<Money, 5> revenues{};
        std::vector<std::array<Money, 5>> utilities(participants.size());
        for (int j = 0; j < 5; ++j) {
            int winner = winners[j];
            Money welfare = winner < 0 ? reservePrice : participants[winner].value,
                  revenue = winner < 0 ? 0 : prices[j];
            if (winner >= 0)
                utilities[winner][j] = welfare - prices[j];
            if (j == 4) {
                revenue = 0;
                for (std::size_t i = 0; i < participants.size(); ++i)
                    if (participants[i].bid >= reservePrice) {
                        revenue += participants[i].bid;
                        if (static_cast<int>(i) != winner)
                            utilities[i][j] = -participants[i].bid;
                    }
            }
            std::string result =
                winner < 0 ? text(labels[j], " unsold")
                           : text(labels[j], " winner ", participants[winner].name, " price ",
                                  prices[j], " utility ", utilities[winner][j]);
            if (j == 2 || j == 3)
                result += text(" steps ", j == 2 ? eng.steps : dut.steps);
            result += text(" revenue ", revenue, " welfare ", welfare, " efficiency ",
                           Fraction(welfare, optimum));
            single.push_back(result);
            if (j == 2) {
                std::string drops = "ENGLISH_DROPS";
                for (std::size_t i = 0; i < participants.size(); ++i)
                    drops += text(" ", participants[i].name, "=",
                                  eng.drops[i] < 0 ? "-" : std::to_string(eng.drops[i]));
                single.push_back(drops);
            }
            revenues[j] = revenue;
            summaryRow(g.name, formats[j], Fraction(revenue), Fraction(welfare),
                       Fraction(welfare, optimum));
        }
        for (std::size_t i = 0; i < participants.size(); ++i)
            line(single, "UTILITY ", participants[i].name, " ", utilities[i][0], " ",
                 utilities[i][1], " ", utilities[i][2], " ", utilities[i][3], " ", utilities[i][4]);
        std::vector<int> ranking = {0, 1, 2, 3, 4};
        std::stable_sort(ranking.begin(), ranking.end(),
                         [&](int a, int b) { return revenues[a] > revenues[b]; });
        std::vector<std::string> names;
        for (int i : ranking)
            names.push_back(formats[i]);
        line(single, "RANKING ", join(names, " "));
    }
    void processSlots(const Group &g) {
        ++slotGroups;
        std::vector<Fraction> ctr;
        std::string error;
        for (const std::string &value : g.arguments) {
            std::size_t slash = value.find('/');
            std::string a = slash == std::string::npos ? "" : value.substr(0, slash),
                        b = slash == std::string::npos ? "" : value.substr(slash + 1);
            if (!digits(a) || !digits(b) || a[0] == '0' || b[0] == '0') {
                error = "bad ctr " + value;
                break;
            }
            Fraction rate(std::stoll(a), std::stoll(b));
            if (rate.compare(Fraction(1)) > 0 || (!ctr.empty() && rate.compare(ctr.back()) >= 0)) {
                error = "bad ctr " + value;
                break;
            }
            ctr.push_back(rate);
        }
        if (error.empty() && g.participants.empty())
            error = "no advertisers";
        std::set<std::string> seen;
        if (error.empty())
            for (const Participant &p : g.participants) {
                if (seen.count(p.name)) {
                    error = "duplicate advertiser " + p.name;
                    break;
                }
                seen.insert(p.name);
            }
        if (!error.empty()) {
            ++errors;
            line(single, "SLOTS ", g.name, " ERROR ", error);
            return;
        }
        const std::vector<Participant> &participants = g.participants;
        int n = static_cast<int>(participants.size()), k = static_cast<int>(ctr.size());
        std::vector<int> gsp(n), vcgOrder(n);
        std::iota(gsp.begin(), gsp.end(), 0);
        vcgOrder = gsp;
        std::stable_sort(gsp.begin(), gsp.end(),
                         [&](int a, int b) { return participants[a].bid > participants[b].bid; });
        std::stable_sort(vcgOrder.begin(), vcgOrder.end(), [&](int a, int b) {
            return participants[a].value > participants[b].value;
        });
        const auto rate = [&](int rank) { return rank < k ? ctr[rank] : Fraction{}; };
        const auto bid = [&](int rank) -> Money {
            return rank < n ? participants[gsp[rank]].bid : 0;
        };
        line(single, "SLOTS ", g.name, " slots ", k, " advertisers ", n);
        Fraction gspRevenue, gspWelfare, vcgRevenue, optimum;
        for (int s = 0; s < std::min(n, k); ++s) {
            const Participant &p = participants[gsp[s]];
            Money price = gspPrice(participants, gsp, s);
            Fraction payment = ctr[s] * Fraction(price),
                     utility = ctr[s] * Fraction(p.value - price);
            gspRevenue = gspRevenue + payment;
            gspWelfare = gspWelfare + ctr[s] * Fraction(p.value);
            optimum = optimum + ctr[s] * Fraction(participants[vcgOrder[s]].value);
            line(single, "GSP ", s + 1, " ", p.name, " ctr ", ctr[s], " bid ", p.bid, " price ",
                 price, " payment ", payment, " utility ", utility);
        }
        line(single, "GSP_TOTAL revenue ", gspRevenue, " welfare ", gspWelfare, " efficiency ",
             gspWelfare / optimum);
        for (int s = 0; s < std::min(n, k); ++s) {
            const Participant &p = participants[vcgOrder[s]];
            Fraction payment = slotVcg(participants, vcgOrder, ctr, s),
                     utility = ctr[s] * Fraction(p.value) - payment;
            vcgRevenue = vcgRevenue + payment;
            line(single, "VCG ", s + 1, " ", p.name, " ctr ", ctr[s], " value ", p.value,
                 " payment ", payment, " price ", payment / ctr[s], " utility ", utility);
        }
        line(single, "VCG_TOTAL revenue ", vcgRevenue, " welfare ", optimum, " efficiency 1");
        int violations = 0, deviations = 0;
        for (int s = 1; s < std::min(n, k + 1); ++s) {
            const Participant &p = participants[gsp[s]];
            Fraction stay = rate(s) * Fraction(p.value - bid(s + 1)),
                     swap = rate(s - 1) * Fraction(p.value - bid(s));
            bool violated = stay.compare(swap) < 0;
            violations += violated;
            line(single, "ENVY ", s + 1, " ", p.name, " stay ", stay, " swap ", swap, " ",
                 violated ? "violated" : "ok");
        }
        if (!violations) {
            ++envyFree;
            single.push_back("ENVY_FREE yes");
        } else
            line(single, "ENVY_FREE no violations ", violations);
        for (int s = 0; s < n; ++s) {
            const Participant &p = participants[gsp[s]];
            Fraction current = rate(s) * Fraction(p.value - bid(s + 1));
            for (int t = 0; t < k; ++t)
                if (t != s) {
                    Money price = t < s ? bid(t) : bid(t + 1);
                    Fraction payoff = rate(t) * Fraction(p.value - price);
                    if (payoff.compare(current) > 0) {
                        ++deviations;
                        line(single, "DEVIATE ", p.name, " from ", s + 1, " to ", t + 1, " gain ",
                             payoff - current);
                    }
                }
        }
        if (!deviations) {
            ++nash;
            single.push_back("NASH yes");
        } else
            line(single, "NASH no deviations ", deviations);
        if (!violations && !deviations) {
            ++equilibria;
            single.push_back("EQUILIBRIUM yes");
        } else
            single.push_back("EQUILIBRIUM no");
        summaryRow(g.name, "gsp", gspRevenue, gspWelfare, gspWelfare / optimum);
        summaryRow(g.name, "vcg", vcgRevenue, optimum, Fraction(1));
    }

  public:
    void run() {
        for (const std::string &name : input.runs)
            processAuction(validate(input, input.auctions.at(name)));
        for (const Group &group : input.groups)
            if (group.kind == "lot")
                processLot(group);
            else
                processSlots(group);
        line(wdp, "TOTAL auctions ", input.runs.size(), " bids ", bidTotal, " valid ", validTotal,
             " eligible ", eligibleTotal, " nodes ", nodeTotal, " greedy_optimal ", greedyOptimal);
        line(vcg, "OVERALL vcg ", revenueTotals[0], " pay_as_bid ", revenueTotals[1], " greedy ",
             revenueTotals[2], " critical ", revenueTotals[3], " saa ", revenueTotals[4]);
        line(core, "SUMMARY checked ", checked, " skipped ", skipped, " vcg ", coreCounts[0],
             " greedy ", coreCounts[1], " critical ", coreCounts[2], " saa ", coreCounts[3]);
        line(ascendingLog, "SUMMARY auctions ", input.runs.size(), " rounds ", roundTotal,
             " capped ", capped, " exposed ", exposed, " exposure ", exposure);
        line(single, "SUMMARY lots ", lots, " slot_groups ", slotGroups, " errors ", errors,
             " envy_free ", envyFree, " nash ", nash, " equilibria ", equilibria);
        std::filesystem::create_directories("output");
        writeLines("wdp.txt", wdp);
        writeLines("vcg.txt", vcg);
        writeLines("core_check.txt", core);
        writeLines("ascending_log.txt", ascendingLog);
        writeLines("single_item.txt", single);
        writeLines("summary.csv", summary);
    }
};
int main() {
    Laboratory laboratory;
    laboratory.run();
}
