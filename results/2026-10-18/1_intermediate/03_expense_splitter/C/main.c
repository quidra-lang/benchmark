#include <inttypes.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Integer;
typedef struct {
    char **items;
    int count, capacity;
} Strings;
typedef struct {
    char name[11];
    bool active;
    Integer day;
} Member;
typedef struct {
    int member;
    Integer value, result;
} Part;
typedef struct {
    char *id;
    char currency[4], category[13], mode[8];
    Integer day, serial, amount, total, interval, next, copies;
    Part payers[30], participants[30];
    int payer_count, participant_count;
} Expense;
typedef struct {
    int from, to;
    Integer amount, total, day, serial;
    char currency[4];
} Settlement;
typedef struct {
    char code[4];
    Integer rate;
} Currency;
typedef struct {
    char category[13];
    Integer value;
} Budget;
typedef struct {
    char name[13];
    Integer total;
} CategoryTotal;
typedef struct {
    int from, to;
    Integer amount;
} Transfer;
static Member members[30];
static Expense expenses[1500];
static Settlement settlements[1000];
static Currency currencies[1000];
static Budget budgets[1000];
static char *used[1500];
static int member_count, expense_count, settlement_count, currency_count, budget_count, used_count;
static Integer current_day = 1, serial;
static jmp_buf recovery;
static char *error_message;

static void *allocate(size_t size) {
    void *p = malloc(size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}
static char *slice(const char *s, size_t n) {
    char *copy = allocate(n + 1);
    memcpy(copy, s, n);
    copy[n] = '\0';
    return copy;
}
static char *copy_string(const char *s) { return slice(s, strlen(s)); }
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *s = allocate((size_t)length + 1);
    vsnprintf(s, (size_t)length + 1, pattern, args);
    va_end(args);
    return s;
}
static void push_owned(Strings *s, char *item) {
    if (s->count == s->capacity) {
        s->capacity = s->capacity ? s->capacity * 2 : 8;
        s->items = realloc(s->items, (size_t)s->capacity * sizeof *s->items);
        if (!s->items) exit(EXIT_FAILURE);
    }
    s->items[s->count++] = item;
}
static void push(Strings *s, const char *item) { push_owned(s, copy_string(item)); }
static void free_strings(Strings *s) {
    for (int i = 0; i < s->count; ++i) free(s->items[i]);
    free(s->items);
    *s = (Strings){0};
}
static Strings split(const char *s, char delimiter, int limit) {
    Strings result = {0};
    const char *start = s;
    for (const char *p = s;; ++p) {
        if (!*p || (*p == delimiter && (!limit || result.count + 1 < limit))) {
            push_owned(&result, slice(start, (size_t)(p - start)));
            start = p + 1;
            if (!*p) break;
        }
    }
    return result;
}
static char *join(const Strings *s, const char *separator) {
    size_t size = 1, sep = strlen(separator);
    for (int i = 0; i < s->count; ++i) size += strlen(s->items[i]) + (i ? sep : 0);
    char *result = allocate(size), *p = result;
    for (int i = 0; i < s->count; ++i) {
        if (i) {
            memcpy(p, separator, sep);
            p += sep;
        }
        size_t n = strlen(s->items[i]);
        memcpy(p, s->items[i], n);
        p += n;
    }
    *p = '\0';
    return result;
}
static void fail(const char *message) {
    error_message = copy_string(message);
    longjmp(recovery, 1);
}
static void named_error(const char *message, const char *name) {
    error_message = format("%s %s", message, name);
    longjmp(recovery, 1);
}
static Integer integer(const char *s) { return strtoll(s, NULL, 10); }
static Integer amount(const char *s) { return integer(s) * 100 + integer(strchr(s, '.') + 1); }
static char *money(Integer value) { return format("%" PRId64 ".%02" PRId64, value / 100, value % 100); }
static char *signed_money(Integer value) {
    if (!value) return copy_string("0.00");
    char *absolute = money(value > 0 ? value : -value);
    char *result = format("%c%s", value > 0 ? '+' : '-', absolute);
    free(absolute);
    return result;
}
static char *rate_text(Integer rate) { return format("%" PRId64 ".%04" PRId64, rate / 10000, rate % 10000); }
static char *percentage(Integer part, Integer whole) {
    char *value = money(part * 10000 / whole), *result = format("%s%%", value);
    free(value);
    return result;
}
static void amount_spec(const char *s, Integer *value, char *currency) {
    *value = amount(s);
    const char *at = strchr(s, '@');
    strcpy(currency, at ? at + 1 : "");
}
static Integer convert(Integer value, const char *currency) {
    if (!*currency) return value;
    for (int i = 0; i < currency_count; ++i) {
        if (!strcmp(currencies[i].code, currency)) return (value * currencies[i].rate + 5000) / 10000;
    }
    named_error("unknown currency", currency);
    return 0;
}
static char *note(Integer value, const char *currency) {
    if (!*currency) return copy_string("");
    char *original = money(value), *result = format(" [%s %s]", original, currency);
    free(original);
    return result;
}
static int member_id(const char *name, bool active) {
    for (int i = 0; i < member_count; ++i) {
        if (!strcmp(members[i].name, name)) {
            if (active && !members[i].active) named_error("inactive member", name);
            return i;
        }
    }
    named_error("unknown member", name);
    return -1;
}
static int ordered_members(int *order, bool active) {
    int count = 0;
    for (int i = 0; i < member_count; ++i) {
        if (active && !members[i].active) continue;
        int j = count;
        while (j > 0 && strcmp(members[order[j - 1]].name, members[i].name) > 0) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = i;
        ++count;
    }
    return count;
}
static int expense_id(const char *id) {
    for (int i = 0; i < expense_count; ++i) if (!strcmp(expenses[i].id, id)) return i;
    named_error("unknown expense", id);
    return -1;
}
static int frozen_member(const Expense *e) {
    for (int i = 0; i < e->payer_count; ++i) if (!members[e->payers[i].member].active) return e->payers[i].member;
    for (int i = 0; i < e->participant_count; ++i) if (!members[e->participants[i].member].active) return e->participants[i].member;
    return -1;
}
static void check_frozen(const Expense *e) {
    int id = frozen_member(e);
    if (id >= 0) named_error("inactive member", members[id].name);
}
static void distribute(Integer total, const Integer *weights, int count, Integer *result) {
    Integer sum = 0, remainders[30], left = total;
    int order[30];
    for (int i = 0; i < count; ++i) sum += weights[i];
    for (int i = 0; i < count; ++i) {
        Integer product = total * weights[i];
        result[i] = product / sum;
        remainders[i] = product % sum;
        left -= result[i];
        order[i] = i;
    }
    for (int i = 1; i < count; ++i) {
        int id = order[i], j = i;
        while (j > 0 && remainders[order[j - 1]] < remainders[id]) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = id;
    }
    for (int i = 0; i < left; ++i) ++result[order[i]];
}
static void equal_distribution(Integer total, int count, Integer *result) {
    for (int i = 0; i < count; ++i) result[i] = total / count + (i < total % count ? 1 : 0);
}
static void contributions(Expense *e) {
    Integer weights[30], values[30];
    for (int i = 0; i < e->payer_count; ++i) weights[i] = e->payers[i].value;
    distribute(e->total, weights, e->payer_count, values);
    for (int i = 0; i < e->payer_count; ++i) e->payers[i].result = values[i];
}
static void compute(Expense *e) {
    e->total = convert(e->amount, e->currency);
    Integer specified[30], portions[30], shares[30], sum = 0;
    for (int i = 0; i < e->participant_count; ++i) {
        specified[i] = e->participants[i].value;
        sum += specified[i];
    }
    if (!strcmp(e->mode, "EQUAL")) equal_distribution(e->amount, e->participant_count, portions);
    else if (!strcmp(e->mode, "EXACT")) memcpy(portions, specified, (size_t)e->participant_count * sizeof *portions);
    else if (!strcmp(e->mode, "ADJUST")) {
        equal_distribution(e->amount - sum, e->participant_count, portions);
        for (int i = 0; i < e->participant_count; ++i) portions[i] += specified[i];
    } else distribute(e->amount, specified, e->participant_count, portions);
    distribute(e->total, portions, e->participant_count, shares);
    for (int i = 0; i < e->participant_count; ++i) e->participants[i].result = shares[i];
    contributions(e);
}
static Expense draft_expense(const Strings *a, const Expense *previous) {
    Expense e = previous ? *previous : (Expense){0};
    int payer = member_id(a->items[2], true);
    amount_spec(a->items[3], &e.amount, e.currency);
    Integer total = convert(e.amount, e.currency);
    if (!e.amount || !total) fail("invalid amount");
    strcpy(e.category, a->items[4]);
    strcpy(e.mode, a->items[5]);
    e.payer_count = 1;
    e.payers[0] = (Part){payer, e.amount, 0};
    e.participant_count = 0;
    if (!strcmp(e.mode, "EQUAL") && !strcmp(a->items[6], "ALL")) {
        int order[30], count = ordered_members(order, true);
        for (int i = 0; i < count; ++i) e.participants[e.participant_count++] = (Part){order[i], 0, 0};
    } else {
        bool seen[30] = {false};
        for (int i = 6; i < a->count; ++i) {
            const char *colon = strchr(a->items[i], ':');
            char name[11];
            size_t length = colon ? (size_t)(colon - a->items[i]) : strlen(a->items[i]);
            memcpy(name, a->items[i], length);
            name[length] = '\0';
            int id = member_id(name, true);
            if (seen[id]) named_error("duplicate member", name);
            seen[id] = true;
            Integer value = 0;
            if (colon) value = !strcmp(e.mode, "PERCENT") || !strcmp(e.mode, "SHARES") ? integer(colon + 1) : amount(colon + 1);
            e.participants[e.participant_count++] = (Part){id, value, 0};
        }
    }
    Integer sum = 0;
    for (int i = 0; i < e.participant_count; ++i) sum += e.participants[i].value;
    if ((!strcmp(e.mode, "EXACT") && sum != e.amount) || (!strcmp(e.mode, "PERCENT") && sum != 10000) || (!strcmp(e.mode, "SHARES") && sum == 0) || (!strcmp(e.mode, "ADJUST") && sum > e.amount)) fail("splits do not add up");
    compute(&e);
    return e;
}
static void net(const Expense *e, Integer *result) {
    memset(result, 0, 30 * sizeof *result);
    for (int i = 0; i < e->payer_count; ++i) result[e->payers[i].member] += e->payers[i].result;
    for (int i = 0; i < e->participant_count; ++i) result[e->participants[i].member] -= e->participants[i].result;
}
static bool involved(const Expense *e, int id) {
    for (int i = 0; i < e->payer_count; ++i) if (e->payers[i].member == id) return true;
    for (int i = 0; i < e->participant_count; ++i) if (e->participants[i].member == id) return true;
    return false;
}
static void balances(Integer *result) {
    memset(result, 0, 30 * sizeof *result);
    for (int i = 0; i < expense_count; ++i) {
        Integer change[30];
        net(&expenses[i], change);
        for (int j = 0; j < member_count; ++j) result[j] += change[j];
    }
    for (int i = 0; i < settlement_count; ++i) {
        result[settlements[i].from] += settlements[i].total;
        result[settlements[i].to] -= settlements[i].total;
    }
}
static void debts(Integer result[30][30]) {
    memset(result, 0, 30 * 30 * sizeof(Integer));
    int order[30], count = ordered_members(order, false);
    for (int i = 0; i < expense_count; ++i) {
        Integer change[30];
        net(&expenses[i], change);
        int borrowers[30], lenders[30], nb = 0, nl = 0;
        for (int j = 0; j < count; ++j) {
            int id = order[j];
            if (change[id] < 0) borrowers[nb++] = id;
            if (change[id] > 0) lenders[nl++] = id;
        }
        int b = 0, l = 0;
        while (b < nb && l < nl) {
            int from = borrowers[b], to = lenders[l];
            Integer value = -change[from] < change[to] ? -change[from] : change[to];
            result[from][to] += value;
            change[from] += value;
            change[to] -= value;
            if (!change[from]) ++b;
            if (!change[to]) ++l;
        }
    }
    for (int i = 0; i < settlement_count; ++i) result[settlements[i].from][settlements[i].to] -= settlements[i].total;
    for (int i = 0; i < member_count; ++i) {
        for (int j = i + 1; j < member_count; ++j) {
            Integer value = result[i][j] - result[j][i];
            result[i][j] = value;
            result[j][i] = -value;
        }
    }
}
static Integer spent(const char *category) {
    Integer total = 0;
    for (int i = 0; i < expense_count; ++i) if (!strcmp(expenses[i].category, category)) total += expenses[i].total;
    return total;
}
static void warning(const Expense *e, Strings *out) {
    for (int i = 0; i < budget_count; ++i) {
        if (!strcmp(budgets[i].category, e->category)) {
            Integer total = spent(e->category);
            if (total > budgets[i].value) {
                char *over = money(total - budgets[i].value);
                push_owned(out, format("  WARNING %s over budget by %s", e->category, over));
                free(over);
            }
        }
    }
}
static char *parts_text(const Part *parts, int count) {
    Strings pieces = {0};
    for (int i = 0; i < count; ++i) {
        char *value = money(parts[i].result);
        push_owned(&pieces, format("%s %s", members[parts[i].member].name, value));
        free(value);
    }
    char *result = join(&pieces, " + ");
    free_strings(&pieces);
    return result;
}
static int chronological(int *order) {
    for (int i = 0; i < expense_count; ++i) {
        int j = i;
        while (j > 0 && (expenses[order[j - 1]].day > expenses[i].day || (expenses[order[j - 1]].day == expenses[i].day && expenses[order[j - 1]].serial > expenses[i].serial))) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = i;
    }
    return expense_count;
}
static int greedy(const int *group, int count, const Integer *original, Transfer *result) {
    Integer values[30];
    memcpy(values, original, sizeof values);
    int length = 0;
    for (;;) {
        int from = -1, to = -1;
        for (int i = 0; i < count; ++i) {
            int id = group[i];
            if (values[id] < 0 && (from < 0 || values[id] < values[from])) from = id;
            if (values[id] > 0 && (to < 0 || values[id] > values[to])) to = id;
        }
        if (from < 0) break;
        Integer value = -values[from] < values[to] ? -values[from] : values[to];
        result[length++] = (Transfer){from, to, value};
        values[from] += value;
        values[to] -= value;
    }
    return length;
}
static void transfer_lines(const Transfer *transfers, int count, const char *indent, Strings *out) {
    for (int i = 0; i < count; ++i) {
        char *value = money(transfers[i].amount);
        push_owned(out, format("%s%s -> %s %s", indent, members[transfers[i].from].name, members[transfers[i].to].name, value));
        free(value);
    }
}
static int best_groups(int mask, const Integer *sums, int *memo) {
    if (memo[mask] >= 0) return memo[mask];
    int first = mask & -mask, result = 0;
    for (int sub = mask; sub; sub = (sub - 1) & mask) {
        if ((sub & first) && sums[sub] == 0) {
            int candidate = 1 + best_groups(mask ^ sub, sums, memo);
            if (candidate > result) result = candidate;
        }
    }
    return memo[mask] = result;
}
static bool mask_less(int a, int b, int count) {
    int i = 0, j = 0;
    for (;;) {
        while (i < count && !(a & (1 << i))) ++i;
        while (j < count && !(b & (1 << j))) ++j;
        if (i == count || j == count) return i == count && j != count;
        if (i != j) return i < j;
        ++i;
        ++j;
    }
}
static Strings temporary;
static const char *keep(char *s) {
    push_owned(&temporary, s);
    return s;
}
static const char *m(Integer value) { return keep(money(value)); }
static const char *sm(Integer value) { return keep(signed_money(value)); }
static const char *pct(Integer part, Integer whole) { return keep(percentage(part, whole)); }
static const char *currency_note(Integer value, const char *currency) { return keep(note(value, currency)); }
static int compare_strings(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
static int compare_category_totals(const void *left, const void *right) {
    const CategoryTotal *a = left, *b = right;
    if (a->total != b->total) return a->total > b->total ? -1 : 1;
    return strcmp(a->name, b->name);
}
static void execute(const Strings *a, const char *line, Strings *out) {
    const char *command = a->items[0];
    if (!strcmp(command, "DAY")) {
        Integer day = integer(a->items[1]);
        if (day <= current_day) named_error("invalid day", a->items[1]);
        push_owned(out, format("DAY %" PRId64, day));
        for (;;) {
            int selected = -1;
            for (int i = 0; i < expense_count; ++i) {
                Expense *e = &expenses[i];
                if (e->interval > 0 && e->next <= day && (selected < 0 || e->next < expenses[selected].next || (e->next == expenses[selected].next && e->serial < expenses[selected].serial))) selected = i;
            }
            if (selected < 0) break;
            Expense *original = &expenses[selected];
            if (frozen_member(original) >= 0 || convert(original->amount, original->currency) == 0) {
                push_owned(out, format("  CANCEL %s", original->id));
                original->interval = 0;
                continue;
            }
            Expense copy = *original;
            copy.id = format("%s#%" PRId64, original->id, original->copies + 2);
            copy.day = original->next;
            copy.serial = ++serial;
            copy.interval = copy.next = copy.copies = 0;
            ++original->copies;
            original->next += original->interval;
            compute(&copy);
            used[used_count++] = copy.id;
            expenses[expense_count++] = copy;
            push_owned(out, format("  RECUR %s %s", copy.id, m(copy.total)));
            warning(&copy, out);
        }
        current_day = day;
    } else if (!strcmp(command, "MEMBER")) {
        int id = -1;
        for (int i = 0; i < member_count; ++i) if (!strcmp(members[i].name, a->items[1])) id = i;
        if (id >= 0 && members[id].active) named_error("duplicate member", a->items[1]);
        bool rejoined = id >= 0;
        if (id < 0) {
            id = member_count++;
            strcpy(members[id].name, a->items[1]);
        }
        members[id].active = true;
        members[id].day = current_day;
        push_owned(out, format("MEMBER %s %s", a->items[1], rejoined ? "rejoined" : "joined"));
    } else if (!strcmp(command, "LEAVE")) {
        int id = member_id(a->items[1], true);
        Integer values[30];
        balances(values);
        if (values[id]) named_error("member has a balance", a->items[1]);
        members[id].active = false;
        members[id].day = current_day;
        push_owned(out, format("LEAVE %s", a->items[1]));
    } else if (!strcmp(command, "CURRENCY")) {
        Integer value = integer(a->items[2]);
        int id = -1;
        for (int i = 0; i < currency_count; ++i) if (!strcmp(currencies[i].code, a->items[1])) id = i;
        const char *new_rate = keep(rate_text(value));
        if (id < 0) {
            push_owned(out, format("CURRENCY %s %s", a->items[1], new_rate));
            id = currency_count++;
            strcpy(currencies[id].code, a->items[1]);
        } else push_owned(out, format("CURRENCY %s %s was %s", a->items[1], new_rate, keep(rate_text(currencies[id].rate))));
        currencies[id].rate = value;
    } else if (!strcmp(command, "EXPENSE") || !strcmp(command, "EDIT")) {
        int id = -1;
        if (!strcmp(command, "EXPENSE")) {
            for (int i = 0; i < used_count; ++i) if (!strcmp(used[i], a->items[1])) named_error("duplicate id", a->items[1]);
        } else {
            id = expense_id(a->items[1]);
            check_frozen(&expenses[id]);
        }
        Expense e = draft_expense(a, id < 0 ? NULL : &expenses[id]);
        if (id < 0) {
            e.id = copy_string(a->items[1]);
            e.day = current_day;
            e.serial = ++serial;
            used[used_count++] = e.id;
            expenses[expense_count++] = e;
        } else expenses[id] = e;
        const char *parts = keep(parts_text(e.participants, e.participant_count));
        push_owned(out, format("%s %s %s%s = %s", command, e.id, m(e.total), currency_note(e.amount, e.currency), parts));
        warning(&e, out);
    } else if (!strcmp(command, "PAYERS")) {
        int id = expense_id(a->items[1]);
        check_frozen(&expenses[id]);
        Part payers[30];
        int count = 0;
        Integer sum = 0;
        bool seen[30] = {false};
        for (int i = 2; i < a->count; ++i) {
            const char *colon = strchr(a->items[i], ':');
            char name[11];
            memcpy(name, a->items[i], (size_t)(colon - a->items[i]));
            name[colon - a->items[i]] = '\0';
            int member = member_id(name, true);
            if (seen[member]) named_error("duplicate member", name);
            seen[member] = true;
            Integer value = amount(colon + 1);
            sum += value;
            payers[count++] = (Part){member, value, 0};
        }
        Expense *e = &expenses[id];
        if (sum != e->amount) fail("payers do not add up");
        memcpy(e->payers, payers, (size_t)count * sizeof *payers);
        e->payer_count = count;
        contributions(e);
        push_owned(out, format("PAYERS %s %s%s = %s", e->id, m(e->total), currency_note(e->amount, e->currency), keep(parts_text(e->payers, e->payer_count))));
    } else if (!strcmp(command, "DELETE")) {
        int id = expense_id(a->items[1]);
        check_frozen(&expenses[id]);
        memmove(expenses + id, expenses + id + 1, (size_t)(expense_count - id - 1) * sizeof *expenses);
        --expense_count;
        push_owned(out, format("DELETE %s", a->items[1]));
    } else if (!strcmp(command, "RECURRING")) {
        Expense *e = &expenses[expense_id(a->items[1])];
        e->interval = integer(a->items[2]);
        if (e->interval) {
            e->next = current_day + e->interval;
            push_owned(out, format("RECURRING %s interval %" PRId64 " next %" PRId64, e->id, e->interval, e->next));
        } else push_owned(out, format("RECURRING %s stopped", e->id));
    } else if (!strcmp(command, "SETTLE")) {
        int from = member_id(a->items[1], true);
        int to = member_id(a->items[2], true);
        if (from == to) named_error("same member", a->items[1]);
        Settlement s = {0};
        s.from = from;
        s.to = to;
        amount_spec(a->items[3], &s.amount, s.currency);
        s.total = convert(s.amount, s.currency);
        if (!s.amount || !s.total) fail("invalid amount");
        s.day = current_day;
        s.serial = ++serial;
        settlements[settlement_count++] = s;
        push_owned(out, format("SETTLE %s -> %s %s%s", a->items[1], a->items[2], m(s.total), currency_note(s.amount, s.currency)));
    } else if (!strcmp(command, "BUDGET")) {
        Integer value = amount(a->items[2]);
        int id = -1;
        for (int i = 0; i < budget_count; ++i) if (!strcmp(budgets[i].category, a->items[1])) id = i;
        if (value) {
            if (id < 0) {
                id = budget_count++;
                strcpy(budgets[id].category, a->items[1]);
            }
            budgets[id].value = value;
            push_owned(out, format("BUDGET %s %s", a->items[1], m(value)));
        } else {
            if (id >= 0) {
                memmove(budgets + id, budgets + id + 1, (size_t)(budget_count - id - 1) * sizeof *budgets);
                --budget_count;
            }
            push_owned(out, format("BUDGET %s removed", a->items[1]));
        }
    } else if (!strcmp(command, "BALANCES")) {
        push(out, "BALANCES");
        Integer values[30];
        balances(values);
        int order[30], count = ordered_members(order, true);
        for (int i = 0; i < count; ++i) push_owned(out, format("  %s %s", members[order[i]].name, sm(values[order[i]])));
    } else if (!strcmp(command, "OWES")) {
        int id = member_id(a->items[1], false);
        push_owned(out, format("OWES %s", a->items[1]));
        Integer values[30][30];
        debts(values);
        int order[30], count = ordered_members(order, false);
        for (int j = 0; j < count; ++j) {
            int i = order[j];
            if (i == id || !values[id][i]) continue;
            int from = values[id][i] > 0 ? id : i, to = values[id][i] > 0 ? i : id;
            push_owned(out, format("  %s owes %s %s", members[from].name, members[to].name, m(values[from][to])));
        }
    } else if (!strcmp(command, "HISTORY")) {
        int id = member_id(a->items[1], false);
        typedef struct {
            Integer day, serial, change;
            const char *label;
        } Item;
        Item items[2500];
        int count = 0;
        for (int i = 0; i < expense_count; ++i) {
            const Expense *e = &expenses[i];
            if (involved(e, id)) {
                Integer change[30];
                net(e, change);
                items[count++] = (Item){e->day, e->serial, change[id], e->id};
            }
        }
        for (int i = 0; i < settlement_count; ++i) {
            const Settlement *s = &settlements[i];
            if (s->from == id || s->to == id) items[count++] = (Item){s->day, s->serial, s->from == id ? s->total : -s->total, keep(format("%s->%s", members[s->from].name, members[s->to].name))};
        }
        for (int i = 1; i < count; ++i) {
            Item item = items[i];
            int j = i;
            while (j > 0 && (items[j - 1].day > item.day || (items[j - 1].day == item.day && items[j - 1].serial > item.serial))) {
                items[j] = items[j - 1];
                --j;
            }
            items[j] = item;
        }
        push_owned(out, format("HISTORY %s", a->items[1]));
        Integer running = 0;
        for (int i = 0; i < count; ++i) {
            running += items[i].change;
            push_owned(out, format("  day %" PRId64 " %s %s balance %s", items[i].day, items[i].label, sm(items[i].change), sm(running)));
        }
    } else if (!strcmp(command, "MATRIX")) {
        push(out, "MATRIX");
        int order[30], count = ordered_members(order, true);
        if (!count) push(out, "  (none)");
        else {
            Integer values[30][30];
            debts(values);
            int l = 0, w;
            for (int i = 0; i < count; ++i) if ((int)strlen(members[order[i]].name) > l) l = (int)strlen(members[order[i]].name);
            w = l;
            for (int i = 0; i < count; ++i) {
                for (int j = 0; j < count; ++j) {
                    Integer value = values[order[i]][order[j]];
                    int length = (int)strlen(m(value > 0 ? value : 0));
                    if (i != j && length > w) w = length;
                }
            }
            Strings pieces = {0};
            push_owned(&pieces, format("%*s", l, ""));
            for (int i = 0; i < count; ++i) push_owned(&pieces, format("  %*s", w, members[order[i]].name));
            push_owned(out, join(&pieces, ""));
            free_strings(&pieces);
            for (int i = 0; i < count; ++i) {
                push_owned(&pieces, format("%-*s", l, members[order[i]].name));
                for (int j = 0; j < count; ++j) {
                    Integer value = values[order[i]][order[j]];
                    const char *cell = i == j ? "-" : m(value > 0 ? value : 0);
                    push_owned(&pieces, format("  %*s", w, cell));
                }
                push_owned(out, join(&pieces, ""));
                free_strings(&pieces);
            }
        }
    } else if (!strcmp(command, "CATEGORY")) {
        push(out, "CATEGORY");
        CategoryTotal categories[1500] = {0};
        int category_count = 0;
        Integer total = 0;
        for (int i = 0; i < expense_count; ++i) {
            const Expense *e = &expenses[i];
            int j = 0;
            while (j < category_count && strcmp(categories[j].name, e->category)) ++j;
            if (j == category_count) {
                strcpy(categories[j].name, e->category);
                ++category_count;
            }
            categories[j].total += e->total;
            total += expenses[i].total;
        }
        if (category_count > 1) {
            qsort(categories, category_count, sizeof *categories, compare_category_totals);
        }
        for (int i = 0; i < category_count; ++i) {
            const char *category = categories[i].name;
            Integer value = categories[i].total, shares[30] = {0};
            push_owned(out, format("  %s %s %s", category, m(value), pct(value, total)));
            for (int j = 0; j < expense_count; ++j) {
                const Expense *e = &expenses[j];
                if (!strcmp(e->category, category)) {
                    for (int k = 0; k < e->participant_count; ++k) shares[e->participants[k].member] += e->participants[k].result;
                }
            }
            int order[30], count = ordered_members(order, false);
            for (int j = 1; j < count; ++j) {
                int id = order[j], k = j;
                while (k > 0 && shares[order[k - 1]] < shares[id]) {
                    order[k] = order[k - 1];
                    --k;
                }
                order[k] = id;
            }
            for (int j = 0; j < count; ++j) {
                int id = order[j];
                if (shares[id]) push_owned(out, format("    %s %s %s", members[id].name, m(shares[id]), pct(shares[id], value)));
            }
        }
    } else if (!strcmp(command, "BUDGETS")) {
        push(out, "BUDGETS");
        Strings categories = {0};
        for (int i = 0; i < budget_count; ++i) push(&categories, budgets[i].category);
        if (categories.count > 1) qsort(categories.items, categories.count, sizeof *categories.items, compare_strings);
        for (int i = 0; i < categories.count; ++i) {
            const char *category = categories.items[i];
            Integer b = 0, s = spent(category);
            for (int j = 0; j < budget_count; ++j) if (!strcmp(budgets[j].category, category)) b = budgets[j].value;
            push_owned(out, format("  %s spent %s budget %s used %s %s %s", category, m(s), m(b), pct(s, b), s <= b ? "left" : "over", m(s <= b ? b - s : s - b)));
        }
        free_strings(&categories);
    } else if (!strcmp(command, "TOTALS")) {
        push(out, "TOTALS");
        Integer paid[30] = {0}, shares[30] = {0}, sent[30] = {0}, received[30] = {0};
        Integer expense_total = 0, settlement_total = 0;
        for (int i = 0; i < expense_count; ++i) {
            const Expense *e = &expenses[i];
            expense_total += e->total;
            for (int j = 0; j < e->payer_count; ++j) paid[e->payers[j].member] += e->payers[j].result;
            for (int j = 0; j < e->participant_count; ++j) shares[e->participants[j].member] += e->participants[j].result;
        }
        for (int i = 0; i < settlement_count; ++i) {
            const Settlement *s = &settlements[i];
            settlement_total += s->total;
            sent[s->from] += s->total;
            received[s->to] += s->total;
        }
        int order[30], count = ordered_members(order, false);
        for (int i = 0; i < count; ++i) {
            int id = order[i];
            push_owned(out, format("  %s paid %s share %s sent %s received %s", members[id].name, m(paid[id]), m(shares[id]), m(sent[id]), m(received[id])));
        }
        Strings codes = {0};
        for (int i = 0; i < currency_count; ++i) push(&codes, currencies[i].code);
        if (codes.count > 1) qsort(codes.items, codes.count, sizeof *codes.items, compare_strings);
        for (int i = 0; i < codes.count; ++i) {
            int number = 0;
            Integer original = 0, base = 0;
            for (int j = 0; j < expense_count; ++j) {
                const Expense *e = &expenses[j];
                if (!strcmp(e->currency, codes.items[i])) {
                    ++number;
                    original += e->amount;
                    base += e->total;
                }
            }
            if (number) push_owned(out, format("  currency %s expenses %d amount %s base %s", codes.items[i], number, m(original), m(base)));
        }
        free_strings(&codes);
        push_owned(out, format("  expenses %d total %s settlements %d total %s", expense_count, m(expense_total), settlement_count, m(settlement_total)));
    } else if (!strcmp(command, "MEMBERS")) {
        push(out, "MEMBERS");
        int order[30], count = ordered_members(order, false);
        for (int i = 0; i < count; ++i) {
            int id = order[i], number = 0;
            for (int j = 0; j < expense_count; ++j) if (involved(&expenses[j], id)) ++number;
            push_owned(out, format("  %s %s day %" PRId64 " expenses %d", members[id].name, members[id].active ? "active" : "left", members[id].day, number));
        }
    } else if (!strcmp(command, "EXPENSES")) {
        int member = !strcmp(a->items[1], "MEMBER") ? member_id(a->items[2], false) : -1;
        push(out, line);
        int order[1500], count = chronological(order), number = 0;
        Integer total = 0;
        for (int i = 0; i < count; ++i) {
            const Expense *e = &expenses[order[i]];
            bool matches = !strcmp(a->items[1], "ALL")
                || (!strcmp(a->items[1], "CATEGORY") && !strcmp(e->category, a->items[2]))
                || (!strcmp(a->items[1], "MEMBER") && involved(e, member))
                || (!strcmp(a->items[1], "DAYS") && e->day >= integer(a->items[2]) && e->day <= integer(a->items[3]));
            if (!matches) continue;
            Strings names = {0};
            for (int j = 0; j < e->payer_count; ++j) push(&names, members[e->payers[j].member].name);
            char *joined = join(&names, ",");
            push_owned(out, format("  day %" PRId64 " %s %s %s by %s", e->day, e->id, e->category, m(e->total), joined));
            free(joined);
            free_strings(&names);
            ++number;
            total += e->total;
        }
        push_owned(out, format("  count %d total %s", number, m(total)));
    } else if (!strcmp(command, "PERIODS")) {
        Integer k = integer(a->items[1]);
        Integer totals[10000] = {0};
        int counts[10000] = {0};
        for (int i = 0; i < expense_count; ++i) {
            int group = (int)((expenses[i].day - 1) / k);
            totals[group] += expenses[i].total;
            ++counts[group];
        }
        push_owned(out, format("PERIODS %" PRId64, k));
        for (int i = 0; i < 10000; ++i) {
            if (counts[i]) push_owned(out, format("  days %" PRId64 "-%" PRId64 " expenses %d total %s", i * k + 1, i * k + k, counts[i], m(totals[i])));
        }
    } else if (!strcmp(command, "SHOW")) {
        const Expense *e = &expenses[expense_id(a->items[1])];
        push_owned(out, format("SHOW %s", a->items[1]));
        push_owned(out, format("  day %" PRId64 " category %s mode %s total %s%s", e->day, e->category, e->mode, m(e->total), currency_note(e->amount, e->currency)));
        for (int i = 0; i < e->payer_count; ++i) push_owned(out, format("  paid %s %s", members[e->payers[i].member].name, m(e->payers[i].result)));
        Integer units = 0;
        for (int i = 0; i < e->participant_count; ++i) units += e->participants[i].value;
        for (int i = 0; i < e->participant_count; ++i) {
            Part p = e->participants[i];
            const char *suffix = "";
            if (!strcmp(e->mode, "EXACT")) suffix = keep(format(" %s", m(p.value)));
            if (!strcmp(e->mode, "PERCENT")) suffix = keep(format(" %s%%", m(p.value)));
            if (!strcmp(e->mode, "SHARES")) suffix = keep(format(" %" PRId64 "/%" PRId64, p.value, units));
            if (!strcmp(e->mode, "ADJUST")) suffix = keep(format(" +%s", m(p.value)));
            push_owned(out, format("  share %s %s%s", members[p.member].name, m(p.result), suffix));
        }
        if (e->interval) push_owned(out, format("  recurring interval %" PRId64 " next %" PRId64, e->interval, e->next));
    } else if (!strcmp(command, "SIMPLIFY")) {
        Integer values[30];
        balances(values);
        int all[30], count = ordered_members(all, false), order[30], n = 0;
        for (int i = 0; i < count; ++i) if (values[all[i]]) order[n++] = all[i];
        if (!strcmp(a->items[1], "GREEDY")) {
            Transfer transfers[30];
            int length = greedy(order, n, values, transfers);
            push_owned(out, format("SIMPLIFY GREEDY transfers %d", length));
            transfer_lines(transfers, length, "  ", out);
        } else {
            if (n > 12) fail("too many members");
            Integer sums[4096] = {0};
            int memo[4096];
            for (int i = 0; i < (1 << n); ++i) memo[i] = -1;
            memo[0] = 0;
            for (int mask = 1; mask < (1 << n); ++mask) {
                int bit = 0;
                while (!(mask & (1 << bit))) ++bit;
                sums[mask] = sums[mask ^ (1 << bit)] + values[order[bit]];
            }
            int remaining = (1 << n) - 1, groups = best_groups(remaining, sums, memo);
            push_owned(out, format("SIMPLIFY OPTIMAL transfers %d groups %d", n - groups, groups));
            while (remaining) {
                int first = remaining & -remaining, chosen = 0;
                for (int sub = remaining; sub; sub = (sub - 1) & remaining) {
                    if (!(sub & first) || sums[sub] != 0 || 1 + best_groups(remaining ^ sub, sums, memo) != best_groups(remaining, sums, memo)) continue;
                    if (!chosen || mask_less(sub, chosen, n)) chosen = sub;
                }
                int group[12], length = 0;
                Strings names = {0};
                for (int i = 0; i < n; ++i) {
                    if (chosen & (1 << i)) {
                        group[length++] = order[i];
                        push(&names, members[order[i]].name);
                    }
                }
                char *joined = join(&names, " ");
                push_owned(out, format("  group %s", joined));
                free(joined);
                free_strings(&names);
                Transfer transfers[30];
                int number = greedy(group, length, values, transfers);
                transfer_lines(transfers, number, "    ", out);
                remaining ^= chosen;
            }
        }
    }
    if (out->count == 1 && (!strcmp(command, "BALANCES") || !strcmp(command, "OWES") || !strcmp(command, "HISTORY") || !strcmp(command, "CATEGORY") || !strcmp(command, "BUDGETS") || !strcmp(command, "MEMBERS") || !strcmp(command, "PERIODS"))) push(out, "  (none)");
}
static char *read_line(void) {
    size_t capacity = 256, length = 0;
    char *line = allocate(capacity);
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            line = realloc(line, capacity);
            if (!line) exit(EXIT_FAILURE);
        }
        line[length++] = (char)c;
    }
    if (!length && c == EOF) {
        free(line);
        return NULL;
    }
    line[length] = '\0';
    return line;
}
int main(void) {
    char *line = read_line();
    if (!line) return 0;
    int count = atoi(line);
    free(line);
    for (int i = 0; i < count; ++i) {
        line = read_line();
        if (!line) break;
        Strings a = split(line, ' ', 0);
        if (setjmp(recovery) == 0) {
            Strings out = {0};
            execute(&a, line, &out);
            for (int j = 0; j < out.count; ++j) puts(out.items[j]);
            free_strings(&out);
        } else {
            printf("ERROR %s\n", error_message);
            free(error_message);
            error_message = NULL;
        }
        free_strings(&temporary);
        free_strings(&a);
        free(line);
    }
    for (int i = 0; i < used_count; ++i) free(used[i]);
    return 0;
}
