#include "auction.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    char *name, *language;
    Bids valid, eligible;
} Bidder;
typedef struct {
    int number;
    char *name, *message;
} Rejection;
typedef struct {
    char *name;
    int offered, total, bidder_count;
    Bidder bidders[15];
    Bid storage[150];
    int storage_count;
    Bids valid, eligible;
    Rejection rejected[150];
    int rejected_count;
} Auction;
typedef struct {
    Money accepted, retained;
    int unsold;
} Allocation;
typedef struct {
    Lines lines;
    Money payment[15], value[15], utility[15], revenue, welfare, retained, exposure;
    int exposed, rounds;
    bool capped;
} Ascending;
typedef struct {
    Input input;
    Lines wdp, vcg, core, ascending, single, summary;
    int bid_total, valid_total, eligible_total, greedy_optimal, checked, skipped, core_counts[4],
        round_total, capped, exposed, lots, slot_groups, errors, envy_free, nash, equilibria;
    Money revenue_totals[5], exposure, node_total;
} Laboratory;
static Money reserve(const Input *input, int mask) {
    Money total = 0;
    for (int i = 0; i < input->item_count; ++i)
        if (mask & (1 << i))
            total += input->items[i].reserve;
    return total;
}
static int item_index(const Input *input, const char *name) {
    for (int i = 0; i < input->item_count; ++i)
        if (strcmp(input->items[i].name, name) == 0)
            return i;
    return -1;
}
static bool digits(const char *text) {
    if (!*text)
        return false;
    for (; *text; ++text)
        if (*text < '0' || *text > '9')
            return false;
    return true;
}
static bool bid_form(char *text, char *names[60], int *count, Money *amount) {
    char *colon = strchr(text, ':');
    if (!colon || strchr(colon + 1, ':'))
        return false;
    char *number = colon + 1;
    size_t length = strlen(number);
    if (!digits(number) || length > 5 || (length > 1 && number[0] == '0'))
        return false;
    *colon = 0;
    *count = 0;
    char *part = text;
    for (;;) {
        char *plus = strchr(part, '+');
        if (plus)
            *plus = 0;
        if (!*part)
            return false;
        for (char *p = part; *p; ++p)
            if (*p < 'a' || *p > 'z')
                return false;
        names[(*count)++] = part;
        if (!plus)
            break;
        part = plus + 1;
    }
    *amount = strtoll(number, NULL, 10);
    return true;
}
static Auction *validate(const Input *input, const RawAuction *raw) {
    Auction *a = allocate(sizeof(*a));
    memset(a, 0, sizeof(*a));
    a->name = raw->name;
    for (int i = 0; i < raw->offered_count; ++i)
        a->offered |= 1 << item_index(input, raw->offered[i]);
    for (int row = 0; row < raw->line_count; ++row) {
        const BidLine *raw_line = &raw->lines[row];
        char *line_error = NULL;
        for (int i = 0; i < row; ++i)
            if (strcmp(raw->lines[i].name, raw_line->name) == 0) {
                line_error = copy_text("duplicate bidder");
                break;
            }
        if (!line_error && strcmp(raw_line->language, "XOR") && strcmp(raw_line->language, "OR"))
            line_error = format_text("bad language %s", raw_line->language);
        if (line_error) {
            for (int i = 0; i < raw_line->count; ++i)
                a->rejected[a->rejected_count++] =
                    (Rejection){++a->total, raw_line->name, copy_text(line_error)};
            free(line_error);
            continue;
        }
        int k = a->bidder_count++;
        a->bidders[k] = (Bidder){.name = raw_line->name, .language = raw_line->language};
        int bundles[4096] = {0};
        for (int i = 0; i < raw_line->count; ++i) {
            ++a->total;
            char *copy = copy_text(raw_line->raw[i]), *names[60], *message = NULL;
            int size = 0, mask = 0;
            Money amount = 0;
            if (!bid_form(copy, names, &size, &amount))
                message = copy_text("malformed bid");
            else {
                for (int j = 0; j < size; ++j) {
                    int index = item_index(input, names[j]);
                    if (index < 0) {
                        message = format_text("unknown item %s", names[j]);
                        break;
                    }
                    int bit = 1 << index;
                    if (!(a->offered & bit)) {
                        message = format_text("item not offered %s", names[j]);
                        break;
                    }
                    if (mask & bit) {
                        message = format_text("duplicate item %s", names[j]);
                        break;
                    }
                    mask |= bit;
                }
                if (!message) {
                    if (size > input->parameters.max_bundle)
                        message = copy_text("bundle too large");
                    else if (!amount)
                        message = copy_text("zero value");
                    else if (bundles[mask])
                        message = format_text("duplicate bundle %d", bundles[mask]);
                    else if (a->bidders[k].valid.count >= input->parameters.max_bids)
                        message = copy_text("too many bids");
                }
            }
            free(copy);
            if (message) {
                a->rejected[a->rejected_count++] = (Rejection){a->total, raw_line->name, message};
                continue;
            }
            Bid *bid = &a->storage[a->storage_count++];
            *bid = (Bid){a->total,
                         k,
                         mask,
                         size,
                         amount,
                         reserve(input, mask),
                         strcmp(raw_line->language, "XOR") == 0};
            bundles[mask] = bid->number;
            a->valid.items[a->valid.count++] = bid;
            a->bidders[k].valid.items[a->bidders[k].valid.count++] = bid;
            if (amount >= bid->reserve) {
                a->eligible.items[a->eligible.count++] = bid;
                a->bidders[k].eligible.items[a->bidders[k].eligible.count++] = bid;
            }
        }
    }
    return a;
}
static void auction_free(Auction *a) {
    for (int i = 0; i < a->rejected_count; ++i)
        free(a->rejected[i].message);
    free(a);
}
static Allocation allocation(const Input *input, int offered, Bids bids) {
    Money accepted = 0;
    int used = 0;
    for (int i = 0; i < bids.count; ++i) {
        accepted += bids.items[i]->amount;
        used |= bids.items[i]->mask;
    }
    int unsold = offered & ~used;
    return (Allocation){accepted, reserve(input, unsold), unsold};
}
static Bids sorted_bids(Bids bids) {
    for (int i = 1; i < bids.count; ++i) {
        const Bid *bid = bids.items[i];
        int j = i;
        while (j && bids.items[j - 1]->number > bid->number) {
            bids.items[j] = bids.items[j - 1];
            --j;
        }
        bids.items[j] = bid;
    }
    return bids;
}
static Lines wdp_lines(const Input *input, const Auction *a, const SearchResult *r, Bids order,
                       Bids greedy, const Critical critical[151]) {
    Lines out = {0};
    line(&out, "AUCTION %s items %d bidders %d bids %d valid %d eligible %d", a->name,
         population(a->offered), a->bidder_count, a->total, a->valid.count, a->eligible.count);
    for (int i = 0; i < a->bidder_count; ++i)
        line(&out, "BIDDER %s %s valid %d eligible %d", a->bidders[i].name, a->bidders[i].language,
             a->bidders[i].valid.count, a->bidders[i].eligible.count);
    for (int i = 0; i < a->rejected_count; ++i) {
        Rejection e = a->rejected[i];
        line(&out, "REJECT %d %s %s", e.number, e.name, e.message);
    }
    for (int i = 0; i < a->valid.count; ++i) {
        const Bid *b = a->valid.items[i];
        if (b->amount < b->reserve)
            line(&out, "BELOW_RESERVE %d %s value %lld reserve %lld", b->number,
                 a->bidders[b->bidder].name, b->amount, b->reserve);
    }
    char f[64];
    for (int i = 0; i < input->item_count; ++i)
        if (a->offered & (1 << i)) {
            char *source =
                r->sources[i] ? format_text("bid %d", r->sources[i]) : copy_text("reserve");
            line(&out, "SHARE %s %s %s", input->items[i].name, fraction_text(r->shares[i], f),
                 source);
            free(source);
        }
    line(&out, "ROOT_BOUND %s", fraction_text(r->bound, f));
    for (size_t i = 0; i < r->record_count; ++i) {
        Improvement record = r->records[i];
        char *numbers = number_list(record.bids);
        line(&out, "IMPROVE %lld welfare %lld bids %s", record.node, record.welfare, numbers);
        free(numbers);
    }
    Allocation opt = allocation(input, a->offered, r->bids),
               approx = allocation(input, a->offered, greedy);
    line(&out, "OPTIMAL welfare %lld accepted %lld retained %lld winners %d", r->welfare,
         opt.accepted, opt.retained, r->bids.count);
    for (int i = 0; i < r->bids.count; ++i) {
        const Bid *b = r->bids.items[i];
        char *name = bundle(input, b->mask, "+");
        line(&out, "WIN %d %s %s %lld", b->number, a->bidders[b->bidder].name, name, b->amount);
        free(name);
    }
    char *names = bundle(input, opt.unsold, " ");
    line(&out, "UNSOLD %s", names);
    free(names);
    line(&out, "SEARCH nodes %lld pruned %lld leaves %lld improvements %lld", r->nodes, r->pruned,
         r->leaves, r->improvements);
    Text order_text = {0};
    text_add(&order_text, "GREEDY_ORDER");
    if (!order.count)
        text_add(&order_text, " -");
    for (int i = 0; i < order.count; ++i)
        text_format(&order_text, " %d", order.items[i]->number);
    lines_add(&out, text_take(&order_text));
    line(&out, "GREEDY welfare %lld accepted %lld retained %lld winners %d efficiency %s",
         approx.accepted + approx.retained, approx.accepted, approx.retained, greedy.count,
         fraction_text(fraction(approx.accepted + approx.retained, r->welfare), f));
    Bids winning = sorted_bids(greedy);
    for (int i = 0; i < winning.count; ++i) {
        const Bid *b = winning.items[i];
        Critical c = critical[b->number];
        char *name = bundle(input, b->mask, "+"),
             *rival = c.rival ? format_text("%d", c.rival) : copy_text("-");
        line(&out, "GWIN %d %s %s %lld critical %lld against %s", b->number,
             a->bidders[b->bidder].name, name, b->amount, c.payment, rival);
        free(name);
        free(rival);
    }
    names = bundle(input, approx.unsold, " ");
    line(&out, "GUNSOLD %s", names);
    free(names);
    for (int i = 0; i < input->item_count; ++i)
        if (a->offered & (1 << i)) {
            int demand = 0;
            const char *optimal = "-", *approximate = "-";
            for (int j = 0; j < a->eligible.count; ++j)
                if (a->eligible.items[j]->mask & (1 << i))
                    ++demand;
            for (int j = 0; j < r->bids.count; ++j)
                if (r->bids.items[j]->mask & (1 << i))
                    optimal = a->bidders[r->bids.items[j]->bidder].name;
            for (int j = 0; j < greedy.count; ++j)
                if (greedy.items[j]->mask & (1 << i))
                    approximate = a->bidders[greedy.items[j]->bidder].name;
            line(&out, "ITEM %s reserve %lld demand %d optimal %s greedy %s", input->items[i].name,
                 input->items[i].reserve, demand, optimal, approximate);
        }
    return out;
}
static Ascending ascending(const Input *input, const Auction *a, Money optimum) {
    Ascending result = {0};
    Candidates by_bidder[15];
    int n = a->bidder_count, m = input->item_count, eligibility[15] = {0}, holder[12],
        bid_counts[12] = {0}, round_counts[12] = {0}, last_round[12] = {0};
    Money prices[12];
    for (int j = 0; j < m; ++j) {
        prices[j] = input->items[j].reserve;
        holder[j] = -1;
    }
    for (int k = 0; k < n; ++k) {
        by_bidder[k] = candidates(a->bidders[k].valid, strcmp(a->bidders[k].language, "XOR") == 0);
        for (int i = 0; i < by_bidder[k].count; ++i) {
            int size = population(by_bidder[k].items[i].mask);
            if (size > eligibility[k])
                eligibility[k] = size;
        }
    }
    Money state = input->parameters.seed, increment = input->parameters.saa_increment;
    line(&result.lines, "AUCTION %s increment %lld", a->name, increment);
    for (int round = 1;; ++round) {
        int new_bids[15] = {0}, activity[15] = {0}, demand = 0;
        for (int k = 0; k < n; ++k) {
            int held = 0;
            for (int j = 0; j < m; ++j)
                if (holder[j] == k)
                    held |= 1 << j;
            int chosen = 0;
            Money best = 0;
            for (int i = 0; i < by_bidder[k].count; ++i) {
                Candidate c = by_bidder[k].items[i];
                if (population(c.mask | held) > eligibility[k])
                    continue;
                Money cost = 0;
                for (int j = 0; j < m; ++j)
                    if (c.mask & (1 << j))
                        cost += prices[j] + (holder[j] >= 0 && holder[j] != k ? increment : 0);
                Money surplus = c.value - cost;
                if (surplus > best) {
                    best = surplus;
                    chosen = c.mask;
                }
            }
            activity[k] = population(chosen | held);
            new_bids[k] = chosen & ~held;
            demand += population(new_bids[k]);
        }
        if (!demand)
            line(&result.lines, "ROUND %d none", round);
        else {
            Text demand_line = {0};
            text_format(&demand_line, "ROUND %d demand %d", round, demand);
            for (int k = 0; k < n; ++k)
                if (new_bids[k]) {
                    char *names = bundle(input, new_bids[k], "+");
                    text_format(&demand_line, " %s:%s", a->bidders[k].name, names);
                    free(names);
                }
            lines_add(&result.lines, text_take(&demand_line));
            for (int j = 0; j < m; ++j)
                if (a->offered & (1 << j)) {
                    int bidders[15], count = 0;
                    for (int k = 0; k < n; ++k)
                        if (new_bids[k] & (1 << j))
                            bidders[count++] = k;
                    if (!count)
                        continue;
                    bid_counts[j] += count;
                    ++round_counts[j];
                    last_round[j] = round;
                    int chosen = 0;
                    if (count > 1) {
                        state = 48271 * state % 2147483647;
                        chosen = (int)(state % count);
                    }
                    if (holder[j] >= 0)
                        prices[j] += increment;
                    holder[j] = bidders[chosen];
                }
            Text standing = {0};
            text_add(&standing, "STANDING");
            for (int j = 0; j < m; ++j)
                if (a->offered & (1 << j))
                    text_format(&standing, " %s=%lld@%s", input->items[j].name, prices[j],
                                holder[j] < 0 ? "-" : a->bidders[holder[j]].name);
            lines_add(&result.lines, text_take(&standing));
        }
        Text changes = {0};
        for (int k = 0; k < n; ++k)
            if (activity[k] < eligibility[k]) {
                eligibility[k] = activity[k];
                text_format(&changes, " %s=%d", a->bidders[k].name, eligibility[k]);
            }
        if (changes.count) {
            line(&result.lines, "ELIGIBILITY%s", changes.data);
            free(changes.data);
        }
        if (!demand || round == input->parameters.round_cap) {
            result.rounds = round;
            result.capped = demand != 0;
            break;
        }
    }
    line(&result.lines, "END rounds %d %s", result.rounds, result.capped ? "cap" : "quiet");
    int won[15] = {0};
    for (int j = 0; j < m; ++j)
        if (a->offered & (1 << j)) {
            if (holder[j] < 0) {
                result.retained += input->items[j].reserve;
                line(&result.lines, "ITEM %s unsold reserve %lld", input->items[j].name,
                     input->items[j].reserve);
            } else {
                int k = holder[j];
                won[k] |= 1 << j;
                result.payment[k] += prices[j];
                result.revenue += prices[j];
                line(&result.lines, "ITEM %s price %lld holder %s bids %d rounds %d last %d",
                     input->items[j].name, prices[j], a->bidders[k].name, bid_counts[j],
                     round_counts[j], last_round[j]);
            }
        }
    result.welfare = result.retained;
    for (int k = 0; k < n; ++k) {
        result.value[k] = candidate_value(&by_bidder[k], won[k]);
        result.utility[k] = result.value[k] - result.payment[k];
        result.welfare += result.value[k];
        if (result.utility[k] < 0) {
            ++result.exposed;
            result.exposure -= result.utility[k];
        }
        char *names = bundle(input, won[k], "+");
        line(&result.lines, "BIDDER %s won %s paid %lld value %lld utility %lld eligibility %d%s",
             a->bidders[k].name, names, result.payment[k], result.value[k], result.utility[k],
             eligibility[k], result.utility[k] < 0 ? " exposed" : "");
        free(names);
        free(by_bidder[k].items);
    }
    char f[64];
    line(&result.lines, "TOTAL revenue %lld welfare %lld efficiency %s exposure %lld exposed %d",
         result.revenue, result.welfare, fraction_text(fraction(result.welfare, optimum), f),
         result.exposure, result.exposed);
    return result;
}
static void summary_row(Laboratory *l, const char *name, const char *format, Fraction revenue,
                        Fraction welfare, Fraction efficiency) {
    char r[64], w[64], e[64];
    line(&l->summary, "%s/%s,%s,%s,%s", name, format, fraction_text(revenue, r),
         fraction_text(welfare, w), fraction_text(efficiency, e));
}
static char *coalition_name(const Auction *a, const Coalition *c) {
    Text text = {0};
    for (int i = 0; i < c->member_count; ++i) {
        if (i)
            text_add(&text, "+");
        text_add(&text, a->bidders[c->members[i]].name);
    }
    if (!c->member_count)
        text_add(&text, "-");
    return text_take(&text);
}
static char *money_list(const Money *values, int count) {
    Text text = {0};
    for (int i = 0; i < count; ++i)
        text_format(&text, "%s%lld", i ? " " : "", values[i]);
    return text_take(&text);
}
static void process_auction(Laboratory *l, const Auction *a) {
    Input *input = &l->input;
    SearchResult opt = solve_wdp(input, a->offered, a->eligible, true);
    Bids order = greedy_order(a->eligible), greedy = greedy_select(order, 0);
    Critical critical[151];
    critical_payments(order, greedy, critical);
    VcgPayment *payments = allocate(15 * sizeof(VcgPayment));
    vcg_payments(input, a->offered, a->bidder_count, a->eligible, opt.bids, opt.welfare, payments);
    Ascending saa = ascending(input, a, opt.welfare);
    Allocation optimal = allocation(input, a->offered, opt.bids),
               approx = allocation(input, a->offered, greedy);
    Money greedy_welfare = approx.accepted + approx.retained, vcg_utility[15] = {0},
          greedy_pay[15] = {0}, critical_pay[15] = {0}, critical_utility[15] = {0}, vcg_revenue = 0,
          critical_revenue = 0, utility_sum = 0;
    int n = a->bidder_count;
    for (int k = 0; k < n; ++k) {
        vcg_utility[k] = payments[k].utility;
        vcg_revenue += payments[k].payment;
        utility_sum += payments[k].utility;
    }
    for (int i = 0; i < greedy.count; ++i) {
        const Bid *b = greedy.items[i];
        Money payment = critical[b->number].payment;
        greedy_pay[b->bidder] += b->amount;
        critical_pay[b->bidder] += payment;
        critical_utility[b->bidder] += b->amount - payment;
        critical_revenue += payment;
    }
    lines_take(&l->wdp, wdp_lines(input, a, &opt, order, greedy, critical));
    l->bid_total += a->total;
    l->valid_total += a->valid.count;
    l->eligible_total += a->eligible.count;
    l->node_total += opt.nodes;
    l->greedy_optimal += greedy_welfare == opt.welfare;
    line(&l->vcg, "AUCTION %s welfare %lld", a->name, opt.welfare);
    for (int k = 0; k < n; ++k) {
        VcgPayment *p = &payments[k];
        if (!p->won.count)
            line(&l->vcg, "BIDDER %s lost", a->bidders[k].name);
        else {
            char *won = number_list(p->won), *alternative = number_list(p->alternative);
            line(
                &l->vcg,
                "BIDDER %s won %s value %lld without %lld alternative %s payment %lld utility %lld",
                a->bidders[k].name, won, p->value, p->without, alternative, p->payment, p->utility);
            free(won);
            free(alternative);
        }
    }
    line(&l->vcg, "TOTAL revenue %lld pay_as_bid %lld retained %lld seller %lld bidders %lld",
         vcg_revenue, optimal.accepted, optimal.retained, vcg_revenue + optimal.retained,
         utility_sum);
    for (int k = 0; k < n; ++k)
        line(&l->vcg, "PAYMENTS %s vcg %lld pay_as_bid %lld greedy %lld critical %lld saa %lld",
             a->bidders[k].name, payments[k].payment, payments[k].value, greedy_pay[k],
             critical_pay[k], saa.payment[k]);
    for (int k = 0; k < n; ++k)
        line(&l->vcg, "UTILITIES %s vcg %lld critical %lld saa %lld", a->bidders[k].name,
             vcg_utility[k], critical_utility[k], saa.utility[k]);
    line(&l->core, "AUCTION %s bidders %d", a->name, n);
    if (n > input->parameters.core_max) {
        ++l->skipped;
        line(&l->core, "SKIPPED");
    } else {
        ++l->checked;
        Coalitions combinations = coalitions(input, a->offered, n, a->eligible);
        line(&l->core, "COALITIONS %d", combinations.count);
        const char *names[] = {"vcg", "greedy", "critical", "saa"};
        Money sellers[] = {vcg_revenue + optimal.retained, greedy_welfare,
                           critical_revenue + approx.retained, saa.revenue + saa.retained},
              zero[15] = {0};
        const Money *utilities[] = {vcg_utility, zero, critical_utility, saa.utility};
        for (int i = 0; i < 4; ++i) {
            char *values = money_list(utilities[i], n);
            line(&l->core, "OUTCOME %s seller %lld utilities %s", names[i], sellers[i], values);
            free(values);
            Blockers blocked = blockers(&combinations, sellers[i], utilities[i]);
            int minimal = 0, best = 0;
            for (int j = 0; j < blocked.count; ++j) {
                Blocking b = blocked.items[j];
                if (b.deficit > blocked.items[best].deficit)
                    best = j;
                if (b.minimal) {
                    ++minimal;
                    Coalition *c = &combinations.items[b.coalition];
                    char *name = coalition_name(a, c), *numbers = number_list(c->bids);
                    line(&l->core, "BLOCK %s welfare %lld payoff %lld deficit %lld bids %s", name,
                         c->welfare, b.payoff, b.deficit, numbers);
                    free(name);
                    free(numbers);
                }
            }
            if (!blocked.count) {
                ++l->core_counts[i];
                line(&l->core, "RESULT core");
            } else {
                Blocking b = blocked.items[best];
                char *name = coalition_name(a, &combinations.items[b.coalition]);
                line(&l->core, "RESULT blocked %d minimal %d max_deficit %lld by %s", blocked.count,
                     minimal, b.deficit, name);
                free(name);
            }
            free(blocked.items);
        }
        free(combinations.items);
    }
    lines_take(&l->ascending, saa.lines);
    l->round_total += saa.rounds;
    l->capped += saa.capped;
    l->exposed += saa.exposed;
    l->exposure += saa.exposure;
    const char *formats[] = {"vcg", "pay_as_bid", "greedy", "critical", "saa"};
    Money revenues[] = {vcg_revenue, optimal.accepted, approx.accepted, critical_revenue,
                        saa.revenue},
          welfares[] = {opt.welfare, opt.welfare, greedy_welfare, greedy_welfare, saa.welfare};
    for (int i = 0; i < 5; ++i) {
        l->revenue_totals[i] += revenues[i];
        summary_row(l, a->name, formats[i], whole(revenues[i]), whole(welfares[i]),
                    fraction(welfares[i], opt.welfare));
    }
    free(opt.records);
    free(payments);
}
static void process_lot(Laboratory *l, const Group *g) {
    ++l->lots;
    char *error = NULL;
    int n = g->participant_count;
    if (!n)
        error = copy_text("no bidders");
    if (!error)
        for (int i = 0; i < n; ++i) {
            for (int j = 0; j < i; ++j)
                if (strcmp(g->participants[i].name, g->participants[j].name) == 0) {
                    error = format_text("duplicate bidder %s", g->participants[i].name);
                    break;
                }
            if (error)
                break;
        }
    if (!error)
        for (int i = 0; i < n; ++i)
            if (g->participants[i].bid > g->participants[i].value) {
                error = format_text("bid above value %s", g->participants[i].name);
                break;
            }
    if (error) {
        ++l->errors;
        line(&l->single, "LOT %s ERROR %s", g->name, error);
        free(error);
        return;
    }
    Money reserve_price = strtoll(g->arguments[0], NULL, 10);
    int efficient = 0, first = -1;
    for (int i = 0; i < n; ++i) {
        if (g->participants[i].value > g->participants[efficient].value)
            efficient = i;
        if (g->participants[i].bid >= reserve_price &&
            (first < 0 || g->participants[i].bid > g->participants[first].bid))
            first = i;
    }
    Money optimum = g->participants[efficient].value > reserve_price
                        ? g->participants[efficient].value
                        : reserve_price;
    line(&l->single, "LOT %s reserve %lld bidders %d efficient %s optimum %lld", g->name,
         reserve_price, n,
         g->participants[efficient].value >= reserve_price ? g->participants[efficient].name : "-",
         optimum);
    int second = g->participants[efficient].value >= reserve_price ? efficient : -1;
    Money second_price = reserve_price;
    for (int i = 0; i < n; ++i)
        if (i != second && g->participants[i].value >= reserve_price &&
            g->participants[i].value > second_price)
            second_price = g->participants[i].value;
    Parameters *p = &l->input.parameters;
    ClockResult eng = english(g, reserve_price, p->english_increment),
                dut = dutch(g, reserve_price, p->dutch_start, p->dutch_decrement);
    int winners[] = {first, second, eng.winner, dut.winner, first};
    Money first_price = first < 0 ? 0 : g->participants[first].bid,
          prices[] = {first_price, second_price, eng.price, dut.price, first_price},
          revenues[5] = {0}, utilities[20][5] = {{0}};
    const char *labels[] = {"FIRST_PRICE", "SECOND_PRICE", "ENGLISH", "DUTCH", "ALL_PAY"},
               *formats[] = {"first_price", "second_price", "english", "dutch", "all_pay"};
    for (int j = 0; j < 5; ++j) {
        int winner = winners[j];
        Money welfare = winner < 0 ? reserve_price : g->participants[winner].value,
              revenue = winner < 0 ? 0 : prices[j];
        if (winner >= 0)
            utilities[winner][j] = welfare - prices[j];
        if (j == 4) {
            revenue = 0;
            for (int i = 0; i < n; ++i)
                if (g->participants[i].bid >= reserve_price) {
                    revenue += g->participants[i].bid;
                    if (i != winner)
                        utilities[i][j] = -g->participants[i].bid;
                }
        }
        Text result = {0};
        text_add(&result, labels[j]);
        if (winner < 0)
            text_add(&result, " unsold");
        else
            text_format(&result, " winner %s price %lld utility %lld", g->participants[winner].name,
                        prices[j], utilities[winner][j]);
        if (j == 2 || j == 3)
            text_format(&result, " steps %d", j == 2 ? eng.steps : dut.steps);
        char f[64];
        text_format(&result, " revenue %lld welfare %lld efficiency %s", revenue, welfare,
                    fraction_text(fraction(welfare, optimum), f));
        lines_add(&l->single, text_take(&result));
        if (j == 2) {
            Text drops = {0};
            text_add(&drops, "ENGLISH_DROPS");
            for (int i = 0; i < n; ++i) {
                text_format(&drops, " %s=", g->participants[i].name);
                if (eng.drops[i] < 0)
                    text_add(&drops, "-");
                else
                    text_format(&drops, "%lld", eng.drops[i]);
            }
            lines_add(&l->single, text_take(&drops));
        }
        revenues[j] = revenue;
        summary_row(l, g->name, formats[j], whole(revenue), whole(welfare),
                    fraction(welfare, optimum));
    }
    for (int i = 0; i < n; ++i)
        line(&l->single, "UTILITY %s %lld %lld %lld %lld %lld", g->participants[i].name,
             utilities[i][0], utilities[i][1], utilities[i][2], utilities[i][3], utilities[i][4]);
    int ranking[5] = {0, 1, 2, 3, 4};
    for (int i = 1; i < 5; ++i) {
        int current = ranking[i], j = i;
        while (j && revenues[current] > revenues[ranking[j - 1]]) {
            ranking[j] = ranking[j - 1];
            --j;
        }
        ranking[j] = current;
    }
    Text names = {0};
    text_add(&names, "RANKING");
    for (int i = 0; i < 5; ++i)
        text_format(&names, " %s", formats[ranking[i]]);
    lines_add(&l->single, text_take(&names));
}
static bool ctr_fraction(const char *text, Fraction *result) {
    const char *slash = strchr(text, '/');
    if (!slash || strchr(slash + 1, '/') || slash == text || text[0] == '0' || !digits(slash + 1) ||
        slash[1] == '0')
        return false;
    for (const char *p = text; p < slash; ++p)
        if (*p < '0' || *p > '9')
            return false;
    *result = fraction(strtoll(text, NULL, 10), strtoll(slash + 1, NULL, 10));
    return true;
}
static Fraction rate_at(const Fraction *ctr, int slots, int rank) {
    return rank < slots ? ctr[rank] : whole(0);
}
static Money bid_at(const Group *g, const int *order, int rank) {
    return rank < g->participant_count ? g->participants[order[rank]].bid : 0;
}
static void process_slots(Laboratory *l, const Group *g) {
    ++l->slot_groups;
    Fraction ctr[10];
    int n = g->participant_count, k = g->argument_count;
    char *error = NULL;
    for (int i = 0; i < k; ++i)
        if (!ctr_fraction(g->arguments[i], &ctr[i]) || fraction_compare(ctr[i], whole(1)) > 0 ||
            (i && fraction_compare(ctr[i], ctr[i - 1]) >= 0)) {
            error = format_text("bad ctr %s", g->arguments[i]);
            break;
        }
    if (!error && !n)
        error = copy_text("no advertisers");
    if (!error)
        for (int i = 0; i < n; ++i) {
            for (int j = 0; j < i; ++j)
                if (strcmp(g->participants[i].name, g->participants[j].name) == 0) {
                    error = format_text("duplicate advertiser %s", g->participants[i].name);
                    break;
                }
            if (error)
                break;
        }
    if (error) {
        ++l->errors;
        line(&l->single, "SLOTS %s ERROR %s", g->name, error);
        free(error);
        return;
    }
    int gsp[20], vcg[20];
    for (int i = 0; i < n; ++i)
        gsp[i] = vcg[i] = i;
    for (int i = 1; i < n; ++i) {
        int current = gsp[i], j = i;
        while (j && g->participants[current].bid > g->participants[gsp[j - 1]].bid) {
            gsp[j] = gsp[j - 1];
            --j;
        }
        gsp[j] = current;
        current = vcg[i];
        j = i;
        while (j && g->participants[current].value > g->participants[vcg[j - 1]].value) {
            vcg[j] = vcg[j - 1];
            --j;
        }
        vcg[j] = current;
    }
    line(&l->single, "SLOTS %s slots %d advertisers %d", g->name, k, n);
    Fraction gsp_revenue = whole(0), gsp_welfare = whole(0), vcg_revenue = whole(0),
             optimum = whole(0);
    int allocated = n < k ? n : k;
    char f[6][64];
    for (int s = 0; s < allocated; ++s) {
        Participant p = g->participants[gsp[s]];
        Money price = gsp_price(g, gsp, s);
        Fraction payment = fraction_mul(ctr[s], whole(price)),
                 utility = fraction_mul(ctr[s], whole(p.value - price));
        gsp_revenue = fraction_add(gsp_revenue, payment);
        gsp_welfare = fraction_add(gsp_welfare, fraction_mul(ctr[s], whole(p.value)));
        optimum = fraction_add(optimum, fraction_mul(ctr[s], whole(g->participants[vcg[s]].value)));
        line(&l->single, "GSP %d %s ctr %s bid %lld price %lld payment %s utility %s", s + 1,
             p.name, fraction_text(ctr[s], f[0]), p.bid, price, fraction_text(payment, f[1]),
             fraction_text(utility, f[2]));
    }
    line(&l->single, "GSP_TOTAL revenue %s welfare %s efficiency %s",
         fraction_text(gsp_revenue, f[0]), fraction_text(gsp_welfare, f[1]),
         fraction_text(fraction_div(gsp_welfare, optimum), f[2]));
    for (int s = 0; s < allocated; ++s) {
        Participant p = g->participants[vcg[s]];
        Fraction payment = slot_vcg(g, vcg, ctr, k, s),
                 utility = fraction_sub(fraction_mul(ctr[s], whole(p.value)), payment);
        vcg_revenue = fraction_add(vcg_revenue, payment);
        line(&l->single, "VCG %d %s ctr %s value %lld payment %s price %s utility %s", s + 1,
             p.name, fraction_text(ctr[s], f[0]), p.value, fraction_text(payment, f[1]),
             fraction_text(fraction_div(payment, ctr[s]), f[2]), fraction_text(utility, f[3]));
    }
    line(&l->single, "VCG_TOTAL revenue %s welfare %s efficiency 1",
         fraction_text(vcg_revenue, f[0]), fraction_text(optimum, f[1]));
    int violations = 0, deviations = 0, last = n < k + 1 ? n : k + 1;
    for (int s = 1; s < last; ++s) {
        Participant p = g->participants[gsp[s]];
        Fraction stay = fraction_mul(rate_at(ctr, k, s), whole(p.value - bid_at(g, gsp, s + 1))),
                 swap = fraction_mul(rate_at(ctr, k, s - 1), whole(p.value - bid_at(g, gsp, s)));
        bool violated = fraction_compare(stay, swap) < 0;
        violations += violated;
        line(&l->single, "ENVY %d %s stay %s swap %s %s", s + 1, p.name, fraction_text(stay, f[0]),
             fraction_text(swap, f[1]), violated ? "violated" : "ok");
    }
    if (!violations) {
        ++l->envy_free;
        line(&l->single, "ENVY_FREE yes");
    } else
        line(&l->single, "ENVY_FREE no violations %d", violations);
    for (int s = 0; s < n; ++s) {
        Participant p = g->participants[gsp[s]];
        Fraction current = fraction_mul(rate_at(ctr, k, s), whole(p.value - bid_at(g, gsp, s + 1)));
        for (int t = 0; t < k; ++t)
            if (t != s) {
                Money price = bid_at(g, gsp, t < s ? t : t + 1);
                Fraction payoff = fraction_mul(rate_at(ctr, k, t), whole(p.value - price));
                if (fraction_compare(payoff, current) > 0) {
                    ++deviations;
                    line(&l->single, "DEVIATE %s from %d to %d gain %s", p.name, s + 1, t + 1,
                         fraction_text(fraction_sub(payoff, current), f[0]));
                }
            }
    }
    if (!deviations) {
        ++l->nash;
        line(&l->single, "NASH yes");
    } else
        line(&l->single, "NASH no deviations %d", deviations);
    if (!violations && !deviations) {
        ++l->equilibria;
        line(&l->single, "EQUILIBRIUM yes");
    } else
        line(&l->single, "EQUILIBRIUM no");
    summary_row(l, g->name, "gsp", gsp_revenue, gsp_welfare, fraction_div(gsp_welfare, optimum));
    summary_row(l, g->name, "vcg", vcg_revenue, optimum, whole(1));
}
int main(void) {
    Laboratory *l = allocate(sizeof(*l));
    memset(l, 0, sizeof(*l));
    read_input(&l->input);
    line(&l->summary, "mechanism,revenue,welfare,efficiency");
    for (int i = 0; i < l->input.run_count; ++i) {
        RawAuction *raw = NULL;
        for (int j = 0; j < l->input.auction_count; ++j)
            if (strcmp(l->input.runs[i], l->input.auctions[j].name) == 0)
                raw = &l->input.auctions[j];
        Auction *a = validate(&l->input, raw);
        process_auction(l, a);
        auction_free(a);
    }
    for (int i = 0; i < l->input.group_count; ++i)
        if (strcmp(l->input.groups[i].kind, "lot") == 0)
            process_lot(l, &l->input.groups[i]);
        else
            process_slots(l, &l->input.groups[i]);
    line(&l->wdp, "TOTAL auctions %d bids %d valid %d eligible %d nodes %lld greedy_optimal %d",
         l->input.run_count, l->bid_total, l->valid_total, l->eligible_total, l->node_total,
         l->greedy_optimal);
    line(&l->vcg, "OVERALL vcg %lld pay_as_bid %lld greedy %lld critical %lld saa %lld",
         l->revenue_totals[0], l->revenue_totals[1], l->revenue_totals[2], l->revenue_totals[3],
         l->revenue_totals[4]);
    line(&l->core, "SUMMARY checked %d skipped %d vcg %d greedy %d critical %d saa %d", l->checked,
         l->skipped, l->core_counts[0], l->core_counts[1], l->core_counts[2], l->core_counts[3]);
    line(&l->ascending, "SUMMARY auctions %d rounds %d capped %d exposed %d exposure %lld",
         l->input.run_count, l->round_total, l->capped, l->exposed, l->exposure);
    line(&l->single, "SUMMARY lots %d slot_groups %d errors %d envy_free %d nash %d equilibria %d",
         l->lots, l->slot_groups, l->errors, l->envy_free, l->nash, l->equilibria);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        exit(EXIT_FAILURE);
    }
    write_lines("wdp.txt", &l->wdp);
    write_lines("vcg.txt", &l->vcg);
    write_lines("core_check.txt", &l->core);
    write_lines("ascending_log.txt", &l->ascending);
    write_lines("single_item.txt", &l->single);
    write_lines("summary.csv", &l->summary);
    lines_free(&l->wdp);
    lines_free(&l->vcg);
    lines_free(&l->core);
    lines_free(&l->ascending);
    lines_free(&l->single);
    lines_free(&l->summary);
    lines_free(&l->input.storage);
    free(l);
    return EXIT_SUCCESS;
}
