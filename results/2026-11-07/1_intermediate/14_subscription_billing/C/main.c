#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Money;
typedef enum { NONE, TRIALING, ACTIVE, PAST_DUE, UNPAID, PAUSED, CANCELED } State;
typedef enum { UNMETERED, GRADUATED, VOLUME } Metering;

static const char *state_names[] = {
    "NONE", "TRIALING", "ACTIVE", "PAST_DUE", "UNPAID", "PAUSED", "CANCELED"
};

typedef struct { char text[32]; } MoneyText;
typedef struct { int upper; Money unit, flat; } Tier;
typedef struct {
    char name[13], cycle[8];
    Money price, setup;
    int length, trial, tier_count;
    bool per_seat;
    Metering mode;
    Tier tiers[10];
} Plan;
typedef struct {
    int day;
    char description[64];
    Money change, balance;
} BalanceRow;
typedef struct {
    char name[13], region[3];
    bool payment_ok;
    Money balance;
    BalanceRow *log;
    int log_count, log_capacity;
} Customer;
typedef struct {
    char name[13];
    bool percent;
    Money value;
    int applications, maximum, redemptions;
} Coupon;
typedef struct {
    int id;
    Customer *customer;
    Plan *plan, *pending_plan;
    int seats, pending_seats;
    State state;
    int start, end, trial_end, pause_start, cancel_on, canceled_on;
    bool cancel_end;
    Coupon *coupon;
    int remaining, usage;
    int first_invoice, last_invoice;
} Subscription;
typedef struct { char description[96]; Money amount; } Item;
typedef struct { Item values[3]; int count; } Items;
typedef struct { Money subtotal, discount, tax, total, credit, due; } Totals;
typedef struct {
    int id, day, next, attempts, retry_index, retry_count;
    int retries[3];
    Subscription *subscription;
    const char *kind;
    Items items;
    Totals totals;
    Money paid, refunded, outstanding;
} Invoice;
typedef struct { int day, subscription; State previous, current; } Event;

static int day = 1;
static Plan plans[20];
static Customer customers[30];
static Coupon coupons[2000];
static Subscription subscriptions[50];
static int plan_count, customer_count, coupon_count, subscription_count;
static int taxes[26][26];
static Invoice *invoices;
static Event *events;
static int invoice_count, invoice_capacity, event_count, event_capacity;

static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
static Money minimum(Money a, Money b) { return a < b ? a : b; }

static void *reserve(void *data, int *capacity, int needed, size_t width) {
    if (needed <= *capacity) return data;
    int next = *capacity ? *capacity * 2 : 16;
    if (next < needed) next = needed;
    void *grown = realloc(data, (size_t)next * width);
    if (!grown) exit(EXIT_FAILURE);
    *capacity = next;
    return grown;
}

static Money cents(const char *text) {
    return strtoll(text, NULL, 10) * 100 + atoi(strchr(text, '.') + 1);
}

static MoneyText money(Money amount) {
    MoneyText result;
    Money magnitude = amount < 0 ? -amount : amount;
    snprintf(result.text, sizeof result.text, "%s%" PRId64 ".%02" PRId64,
             amount < 0 ? "-" : "", magnitude / 100, magnitude % 100);
    return result;
}

static Plan *find_plan(const char *name) {
    for (int i = 0; i < plan_count; ++i)
        if (equal(plans[i].name, name)) return &plans[i];
    return NULL;
}

static Customer *find_customer(const char *name) {
    for (int i = 0; i < customer_count; ++i)
        if (equal(customers[i].name, name)) return &customers[i];
    return NULL;
}

static Coupon *find_coupon(const char *name) {
    for (int i = 0; i < coupon_count; ++i)
        if (equal(coupons[i].name, name)) return &coupons[i];
    return NULL;
}

static Coupon *redeemable_coupon(const char *name) {
    Coupon *coupon = find_coupon(name);
    if (!coupon) printf("ERROR unknown coupon %s\n", name);
    else if (coupon->maximum >= 0 && coupon->redemptions == coupon->maximum) {
        printf("ERROR coupon exhausted %s\n", name);
        return NULL;
    }
    return coupon;
}

static Subscription *find_subscription(const char *text) {
    int id = atoi(text);
    if (id < 1 || id > subscription_count) {
        printf("ERROR unknown sub %s\n", text);
        return NULL;
    }
    return &subscriptions[id - 1];
}

static bool allowed(Subscription *s, unsigned states) {
    if (states & (1u << s->state)) return true;
    printf("ERROR invalid state %d %s\n", s->id, state_names[s->state]);
    return false;
}

static int tax_rate(Customer *customer) {
    return taxes[customer->region[0] - 'A'][customer->region[1] - 'A'];
}

static Money fee(Plan *plan, int seats) {
    return plan->price * (plan->per_seat ? seats : 1);
}

static void balance_change(Customer *customer, Money change, const char *description) {
    if (!change) return;
    customer->balance += change;
    customer->log = reserve(customer->log, &customer->log_capacity,
                            customer->log_count + 1, sizeof *customer->log);
    BalanceRow *row = &customer->log[customer->log_count++];
    *row = (BalanceRow){.day = day, .change = change, .balance = customer->balance};
    strcpy(row->description, description);
}

static void change_state(Subscription *s, State next) {
    State previous = s->state;
    if (previous == PAST_DUE)
        for (int id = s->first_invoice; id; id = invoices[id - 1].next)
            invoices[id - 1].retry_count = 0;
    s->state = next;
    printf("  day %d sub %d %s -> %s\n", day, s->id,
           state_names[previous], state_names[next]);
    events = reserve(events, &event_capacity, event_count + 1, sizeof *events);
    events[event_count++] = (Event){day, s->id, previous, next};
}

static Money usage_charge(Plan *plan, int units) {
    Money amount = 0;
    int lower = 0;
    for (int i = 0; i < plan->tier_count; ++i) {
        Tier tier = plan->tiers[i];
        bool last = i + 1 == plan->tier_count || tier.upper == -1;
        if (plan->mode == VOLUME) {
            if (last || units <= tier.upper) return units * tier.unit + tier.flat;
        } else {
            if (units <= lower) break;
            int end = last || units < tier.upper ? units : tier.upper;
            amount += (end - lower) * tier.unit + tier.flat;
            if (last) break;
            lower = tier.upper;
        }
    }
    return amount;
}

static void add_period(Items *items, Plan *plan, int seats, int start) {
    Item *item = &items->values[items->count++];
    snprintf(item->description, sizeof item->description, "charge %s seats %d %d-%d",
             plan->name, seats, start, start + plan->length);
    item->amount = fee(plan, seats);
}

static Items opening_items(Subscription *s, int start) {
    Items items = {0};
    add_period(&items, s->plan, s->seats, start);
    if (s->plan->setup) {
        Item *item = &items.values[items.count++];
        snprintf(item->description, sizeof item->description, "setup %s", s->plan->name);
        item->amount = s->plan->setup;
    }
    return items;
}

static Items usage_items(Subscription *s) {
    Items items = {0};
    if (s->plan->mode != UNMETERED && s->usage) {
        Item *item = &items.values[items.count++];
        snprintf(item->description, sizeof item->description, "usage %s %d units",
                 s->plan->name, s->usage);
        item->amount = usage_charge(s->plan, s->usage);
    }
    return items;
}

static Items close_usage(Subscription *s) {
    Items items = usage_items(s);
    if (items.count) s->usage = 0;
    return items;
}

static Totals invoice_totals(Subscription *s, Items items) {
    Totals totals = {0};
    for (int i = 0; i < items.count; ++i) totals.subtotal += items.values[i].amount;
    if (s->coupon && s->remaining != 0 && totals.subtotal > 0)
        totals.discount = s->coupon->percent
            ? totals.subtotal * s->coupon->value / 10000
            : minimum(totals.subtotal, s->coupon->value);
    totals.tax = (totals.subtotal - totals.discount) * tax_rate(s->customer) / 10000;
    totals.total = totals.subtotal - totals.discount + totals.tax;
    totals.credit = minimum(s->customer->balance, totals.total);
    totals.due = totals.total - totals.credit;
    return totals;
}

static void issue(Subscription *s, const char *kind, Items items) {
    Totals totals = invoice_totals(s, items);
    if (s->coupon && s->remaining > 0 && totals.subtotal > 0) --s->remaining;
    invoices = reserve(invoices, &invoice_capacity, invoice_count + 1, sizeof *invoices);
    int id = ++invoice_count;
    Invoice *bill = &invoices[id - 1];
    *bill = (Invoice){.id = id, .day = day, .subscription = s, .kind = kind,
                      .items = items, .totals = totals, .outstanding = totals.due};
    if (s->last_invoice) invoices[s->last_invoice - 1].next = id;
    else s->first_invoice = id;
    s->last_invoice = id;
    char description[64];
    snprintf(description, sizeof description, "applied invoice %d", id);
    balance_change(s->customer, -totals.credit, description);
    const char *result = "PAID";
    if (totals.due) {
        if (s->state == UNPAID) result = "OPEN";
        else {
            bill->attempts = 1;
            if (s->customer->payment_ok) {
                bill->paid = bill->outstanding;
                bill->outstanding = 0;
            } else result = "FAILED";
        }
    }
    printf("  day %d invoice %d sub %d %s total %s credit %s due %s %s\n",
           day, id, s->id, kind, money(totals.total).text, money(totals.credit).text,
           money(totals.due).text, result);
    if (equal(result, "FAILED")) {
        if (s->state == ACTIVE) change_state(s, PAST_DUE);
        if (s->state == PAST_DUE) {
            bill->retry_count = 3;
            bill->retries[0] = day + 3;
            bill->retries[1] = day + 5;
            bill->retries[2] = day + 7;
        }
    }
}

static void payment_complete(Invoice *bill) {
    bill->retry_count = 0;
    Subscription *s = bill->subscription;
    if (s->state != PAST_DUE && s->state != UNPAID) return;
    for (int id = s->first_invoice; id; id = invoices[id - 1].next)
        if (invoices[id - 1].outstanding) return;
    s->cancel_on = 0;
    change_state(s, ACTIVE);
}

static void cancel_subscription(Subscription *s) {
    change_state(s, CANCELED);
    s->canceled_on = day;
    s->pending_plan = NULL;
    s->cancel_end = false;
    s->cancel_on = 0;
    Items items = close_usage(s);
    if (items.count) issue(s, "final", items);
}

static void advance_subscription(Subscription *s) {
    if (s->state == PAUSED || s->state == CANCELED) return;
    for (int id = s->first_invoice; id; id = invoices[id - 1].next) {
        Invoice *bill = &invoices[id - 1];
        if (!bill->retry_count || bill->retries[bill->retry_index] != day) continue;
        ++bill->retry_index;
        --bill->retry_count;
        int retry = bill->attempts++;
        if (s->customer->payment_ok) {
            bill->paid += bill->outstanding;
            bill->outstanding = 0;
            printf("  day %d retry %d invoice %d PAID\n", day, retry, id);
            payment_complete(bill);
        } else {
            printf("  day %d retry %d invoice %d FAILED\n", day, retry, id);
            if (!bill->retry_count) {
                change_state(s, UNPAID);
                s->cancel_on = day + 14;
            }
        }
    }
    if (s->state == UNPAID && s->cancel_on == day) cancel_subscription(s);
    if (s->state == TRIALING && s->trial_end == day) {
        if (s->cancel_end) cancel_subscription(s);
        else {
            change_state(s, ACTIVE);
            s->start = day;
            s->end = day + s->plan->length;
            issue(s, "first", opening_items(s, day));
        }
    }
    if ((s->state == ACTIVE || s->state == PAST_DUE || s->state == UNPAID)
        && s->end == day) {
        if (s->cancel_end) cancel_subscription(s);
        else {
            Items items = close_usage(s);
            if (s->pending_plan) {
                printf("  day %d sub %d %s seats %d -> %s seats %d\n", day, s->id,
                       s->plan->name, s->seats, s->pending_plan->name, s->pending_seats);
                s->plan = s->pending_plan;
                s->seats = s->pending_seats;
                s->pending_plan = NULL;
            }
            s->start = day;
            s->end = day + s->plan->length;
            add_period(&items, s->plan, s->seats, day);
            issue(s, "renewal", items);
        }
    }
}

static bool setup_command(char **a, int n) {
    if (equal(a[0], "PLAN")) {
        if (find_plan(a[1])) printf("ERROR duplicate plan %s\n", a[1]);
        else {
            Plan *plan = &plans[plan_count++];
            strcpy(plan->name, a[1]);
            strcpy(plan->cycle, a[3]);
            plan->price = cents(a[2]);
            plan->length = equal(a[3], "WEEKLY") ? 7 : equal(a[3], "MONTHLY") ? 30 : 360;
            for (int i = 4; i < n; ++i) {
                if (equal(a[i], "TRIAL")) plan->trial = atoi(a[++i]);
                else if (equal(a[i], "SETUP")) plan->setup = cents(a[++i]);
                else if (equal(a[i], "PERSEAT")) plan->per_seat = true;
                else plan->mode = equal(a[i], "GRADUATED") ? GRADUATED : VOLUME;
            }
            printf("PLAN %s %s %s", plan->name, plan->cycle, money(plan->price).text);
            if (plan->trial) printf(" trial %d", plan->trial);
            if (plan->setup) printf(" setup %s", money(plan->setup).text);
            if (plan->per_seat) printf(" perseat");
            if (plan->mode) printf(" %s", plan->mode == GRADUATED ? "graduated" : "volume");
            putchar('\n');
        }
    } else if (equal(a[0], "TIER")) {
        Plan *plan = find_plan(a[1]);
        int upper = equal(a[2], "INF") ? -1 : atoi(a[2]);
        if (!plan) printf("ERROR unknown plan %s\n", a[1]);
        else if (!plan->mode) printf("ERROR not metered %s\n", a[1]);
        else {
            int previous = plan->tier_count ? plan->tiers[plan->tier_count - 1].upper : 0;
            if (previous == -1 || (upper != -1 && upper <= previous))
                printf("ERROR tier order %s\n", a[1]);
            else {
                plan->tiers[plan->tier_count++] = (Tier){upper, cents(a[3]), cents(a[4])};
                printf("TIER %s %d upto %s unit %s flat %s\n",
                       a[1], plan->tier_count, a[2], a[3], a[4]);
            }
        }
    } else if (equal(a[0], "TAX")) {
        int rate = atoi(a[2]);
        taxes[a[1][0] - 'A'][a[1][1] - 'A'] = rate;
        printf("TAX %s %s%%\n", a[1], money(rate).text);
    } else if (equal(a[0], "CUSTOMER")) {
        if (find_customer(a[1])) printf("ERROR duplicate customer %s\n", a[1]);
        else {
            Customer *customer = &customers[customer_count++];
            strcpy(customer->name, a[1]);
            strcpy(customer->region, a[2]);
            customer->payment_ok = true;
            printf("CUSTOMER %s region %s\n", a[1], a[2]);
        }
    } else if (equal(a[0], "COUPON")) {
        if (find_coupon(a[1])) printf("ERROR duplicate coupon %s\n", a[1]);
        else {
            Coupon *coupon = &coupons[coupon_count++];
            strcpy(coupon->name, a[1]);
            coupon->percent = equal(a[2], "PERCENT");
            coupon->value = coupon->percent ? atoi(a[3]) : cents(a[3]);
            coupon->applications = equal(a[4], "ONCE") ? 1 : -1;
            coupon->maximum = -1;
            int i = 5;
            if (equal(a[4], "REPEATING")) coupon->applications = atoi(a[i++]);
            if (i < n) coupon->maximum = atoi(a[i + 1]);
            printf("COUPON %s %s %s%s ", a[1], coupon->percent ? "percent" : "amount",
                   money(coupon->value).text, coupon->percent ? "%" : "");
            if (equal(a[4], "REPEATING")) printf("repeating %d", coupon->applications);
            else printf("%s", equal(a[4], "ONCE") ? "once" : "forever");
            if (coupon->maximum >= 0) printf(" max %d", coupon->maximum);
            putchar('\n');
        }
    } else return false;
    return true;
}

static void print_items(Items items) {
    for (int i = 0; i < items.count; ++i)
        printf("  %s %s\n", items.values[i].description, money(items.values[i].amount).text);
}

static void print_totals(Totals totals) {
    printf("  subtotal %s discount %s tax %s total %s\n", money(totals.subtotal).text,
           money(totals.discount).text, money(totals.tax).text, money(totals.total).text);
}

static void show_subscription(Subscription *s) {
    printf("SUB %d %s %s seats %d %s\n", s->id, s->customer->name,
           s->plan->name, s->seats, state_names[s->state]);
    if (s->state == TRIALING) printf("  trial until %d\n", s->trial_end);
    if (s->state >= ACTIVE && s->state <= PAUSED) printf("  period %d-%d\n", s->start, s->end);
    if (s->state == PAUSED) printf("  paused since %d\n", s->pause_start);
    if (s->pending_plan) printf("  pending %s seats %d\n", s->pending_plan->name, s->pending_seats);
    if (s->cancel_end) puts("  cancel at end");
    if (s->cancel_on) printf("  cancel on %d\n", s->cancel_on);
    if (s->state == CANCELED) printf("  canceled on %d\n", s->canceled_on);
    if (s->coupon && s->remaining) {
        if (s->remaining < 0) printf("  coupon %s forever\n", s->coupon->name);
        else printf("  coupon %s left %d\n", s->coupon->name, s->remaining);
    }
    if (s->plan->mode && s->state != CANCELED) printf("  usage %d\n", s->usage);
    bool first = true;
    for (int id = s->first_invoice; id; id = invoices[id - 1].next)
        if (invoices[id - 1].outstanding) {
            if (first) printf("  open");
            printf(" %d", id);
            first = false;
        }
    if (!first) putchar('\n');
}

static void preview(Subscription *s) {
    int due_day = s->state == TRIALING ? s->trial_end : s->end;
    const char *kind;
    Items items = {0};
    if (s->cancel_end) {
        kind = "final";
        if (s->state != TRIALING) items = usage_items(s);
    } else if (s->state == TRIALING) {
        kind = "first";
        items = opening_items(s, due_day);
    } else {
        kind = "renewal";
        items = usage_items(s);
        Plan *plan = s->pending_plan ? s->pending_plan : s->plan;
        int seats = s->pending_plan ? s->pending_seats : s->seats;
        add_period(&items, plan, seats, due_day);
    }
    printf("PREVIEW sub %d day %d %s\n", s->id, due_day, kind);
    if (!items.count) puts("  (none)");
    else {
        Totals totals = invoice_totals(s, items);
        print_items(items);
        print_totals(totals);
        printf("  credit %s due %s\n", money(totals.credit).text, money(totals.due).text);
    }
}

static void subscribe(char **a, int n) {
    Customer *customer = find_customer(a[1]);
    if (!customer) { printf("ERROR unknown customer %s\n", a[1]); return; }
    Plan *plan = find_plan(a[2]);
    if (!plan) { printf("ERROR unknown plan %s\n", a[2]); return; }
    bool has_seats = false;
    int seats = 1;
    const char *coupon_name = NULL;
    for (int i = 3; i < n; i += 2) {
        if (equal(a[i], "SEATS")) {
            has_seats = true;
            seats = atoi(a[i + 1]);
        } else coupon_name = a[i + 1];
    }
    if (has_seats && !plan->per_seat) { printf("ERROR not per-seat %s\n", plan->name); return; }
    if (!seats) { puts("ERROR invalid seats"); return; }
    Coupon *coupon = coupon_name ? redeemable_coupon(coupon_name) : NULL;
    if (coupon_name && !coupon) return;
    Subscription *s = &subscriptions[subscription_count++];
    *s = (Subscription){.id = subscription_count, .customer = customer,
                         .plan = plan, .seats = seats, .coupon = coupon};
    if (coupon) {
        ++coupon->redemptions;
        s->remaining = coupon->applications;
    }
    printf("SUBSCRIBE sub %d %s %s seats %d", s->id, customer->name, plan->name, seats);
    if (coupon) printf(" coupon %s", coupon->name);
    putchar('\n');
    if (plan->trial) {
        s->trial_end = day + plan->trial;
        change_state(s, TRIALING);
    } else {
        change_state(s, ACTIVE);
        s->start = day;
        s->end = day + plan->length;
        issue(s, "first", opening_items(s, day));
    }
}

static void change_subscription(Subscription *s, char **a) {
    if (!allowed(s, (1u << ACTIVE) | (1u << TRIALING))) return;
    Plan *plan = s->plan;
    int seats = s->seats;
    if (equal(a[2], "PLAN")) {
        plan = find_plan(a[3]);
        if (!plan) { printf("ERROR unknown plan %s\n", a[3]); return; }
        if (!plan->per_seat) seats = 1;
    } else {
        if (!plan->per_seat) { printf("ERROR not per-seat %s\n", plan->name); return; }
        seats = atoi(a[3]);
        if (!seats) { puts("ERROR invalid seats"); return; }
    }
    if (plan == s->plan && seats == s->seats) {
        printf("ERROR no change %d\n", s->id);
        return;
    }
    Plan *old = s->plan;
    int old_seats = s->seats;
    s->pending_plan = NULL;
    printf("CHANGE sub %d %s seats %d -> %s seats %d", s->id,
           old->name, old_seats, plan->name, seats);
    if (s->state == TRIALING) {
        s->plan = plan;
        s->seats = seats;
        puts(" now");
    } else if (fee(plan, seats) * old->length > fee(old, old_seats) * plan->length) {
        puts(" now");
        int remaining = s->end - day;
        Items items = close_usage(s);
        Item *unused = &items.values[items.count++];
        snprintf(unused->description, sizeof unused->description, "unused %s seats %d %d days",
                 old->name, old_seats, remaining);
        unused->amount = -(fee(old, old_seats) * remaining / old->length);
        Item *charge = &items.values[items.count++];
        snprintf(charge->description, sizeof charge->description, "remaining %s seats %d %d days",
                 plan->name, seats, remaining);
        charge->amount = fee(plan, seats) * remaining / plan->length;
        s->plan = plan;
        s->seats = seats;
        issue(s, "upgrade", items);
    } else {
        s->pending_plan = plan;
        s->pending_seats = seats;
        printf(" at %d\n", s->end);
    }
}

static bool subscription_command(char **a, int n) {
    if (equal(a[0], "SUBSCRIBE")) { subscribe(a, n); return true; }
    const char *names[] = {"CHANGE", "PAUSE", "RESUME", "CANCEL", "USAGE", "APPLY", "SUB", "PREVIEW"};
    bool recognized = false;
    for (size_t i = 0; i < sizeof names / sizeof *names; ++i)
        if (equal(a[0], names[i])) recognized = true;
    if (!recognized) return false;
    Subscription *s = find_subscription(a[1]);
    if (!s) return true;
    if (equal(a[0], "CHANGE")) change_subscription(s, a);
    else if (equal(a[0], "PAUSE")) {
        if (!allowed(s, 1u << ACTIVE)) return true;
        printf("PAUSE sub %d\n", s->id);
        s->pause_start = day;
        change_state(s, PAUSED);
    } else if (equal(a[0], "RESUME")) {
        if (!allowed(s, 1u << PAUSED)) return true;
        int shift = day - s->pause_start;
        s->end += shift;
        s->pause_start = 0;
        printf("RESUME sub %d shift %d period %d-%d\n", s->id, shift, s->start, s->end);
        change_state(s, ACTIVE);
    } else if (equal(a[0], "CANCEL")) {
        if (equal(a[2], "END")) {
            if (!allowed(s, (1u << ACTIVE) | (1u << TRIALING))) return true;
            if (s->cancel_end) { printf("ERROR already canceling %d\n", s->id); return true; }
            s->cancel_end = true;
            printf("CANCEL sub %d end %d\n", s->id, s->state == TRIALING ? s->trial_end : s->end);
        } else {
            if (!allowed(s, ~(1u << CANCELED))) return true;
            Money refund = 0;
            if (s->state == ACTIVE || s->state == PAUSED) {
                int start = s->state == ACTIVE ? day : s->pause_start;
                refund = fee(s->plan, s->seats) * (s->end - start) / s->plan->length;
            }
            char description[64];
            snprintf(description, sizeof description, "cancel sub %d", s->id);
            balance_change(s->customer, refund, description);
            printf("CANCEL sub %d now credit %s\n", s->id, money(refund).text);
            cancel_subscription(s);
        }
    } else if (equal(a[0], "USAGE")) {
        if (!allowed(s, (1u << ACTIVE) | (1u << PAST_DUE))) return true;
        if (!s->plan->mode) { printf("ERROR not metered %s\n", s->plan->name); return true; }
        int units = atoi(a[2]);
        if (!units) { puts("ERROR invalid units"); return true; }
        s->usage += units;
        printf("USAGE sub %d units %d total %d\n", s->id, units, s->usage);
    } else if (equal(a[0], "APPLY")) {
        if (!allowed(s, ~(1u << CANCELED))) return true;
        Coupon *coupon = redeemable_coupon(a[2]);
        if (!coupon) return true;
        ++coupon->redemptions;
        s->coupon = coupon;
        s->remaining = coupon->applications;
        printf("APPLY sub %d coupon %s\n", s->id, coupon->name);
    } else if (equal(a[0], "SUB")) show_subscription(s);
    else if (allowed(s, ~((1u << PAUSED) | (1u << CANCELED)))) preview(s);
    return true;
}

static bool invoice_command(char **a) {
    if (!equal(a[0], "PAY") && !equal(a[0], "REFUND") && !equal(a[0], "INVOICE")) return false;
    int id = atoi(a[1]);
    if (id < 1 || id > invoice_count) { printf("ERROR unknown invoice %s\n", a[1]); return true; }
    Invoice *bill = &invoices[id - 1];
    Customer *customer = bill->subscription->customer;
    if (equal(a[0], "PAY")) {
        if (!bill->outstanding) { printf("ERROR already paid %d\n", id); return true; }
        printf("PAY invoice %d amount %s\n", id, money(bill->outstanding).text);
        bill->paid += bill->outstanding;
        bill->outstanding = 0;
        payment_complete(bill);
    } else if (equal(a[0], "REFUND")) {
        Money amount = cents(a[2]);
        if (!amount) { puts("ERROR invalid amount"); return true; }
        Money available = bill->totals.total - bill->refunded;
        if (amount > available) {
            printf("ERROR refund exceeds %d %s\n", id, money(available).text);
            return true;
        }
        Money applied = minimum(amount, bill->outstanding);
        bill->refunded += amount;
        bill->outstanding -= applied;
        char description[64];
        snprintf(description, sizeof description, "refund invoice %d", id);
        balance_change(customer, amount - applied, description);
        printf("REFUND invoice %d amount %s applied %s balance %s\n", id,
               money(amount).text, money(applied).text, money(customer->balance).text);
        if (applied && !bill->outstanding) payment_complete(bill);
    } else {
        printf("INVOICE %d sub %d %s day %d %s %s\n", id, bill->subscription->id,
               customer->name, bill->day, bill->kind, bill->outstanding ? "OPEN" : "PAID");
        print_items(bill->items);
        print_totals(bill->totals);
        printf("  credit %s due %s paid %s refunded %s outstanding %s\n",
               money(bill->totals.credit).text, money(bill->totals.due).text,
               money(bill->paid).text, money(bill->refunded).text, money(bill->outstanding).text);
    }
    return true;
}

static bool customer_command(char **a) {
    if (!equal(a[0], "PAYMETHOD") && !equal(a[0], "CREDIT") &&
        !equal(a[0], "STATEMENT") && !equal(a[0], "LEDGER")) return false;
    Customer *customer = find_customer(a[1]);
    if (!customer) { printf("ERROR unknown customer %s\n", a[1]); return true; }
    if (equal(a[0], "PAYMETHOD")) {
        customer->payment_ok = equal(a[2], "OK");
        printf("PAYMETHOD %s %s\n", a[1], a[2]);
    } else if (equal(a[0], "CREDIT")) {
        Money amount = cents(a[2]);
        if (!amount) { puts("ERROR invalid amount"); return true; }
        balance_change(customer, amount, "grant");
        printf("CREDIT %s amount %s balance %s\n", a[1], a[2], money(customer->balance).text);
    } else if (equal(a[0], "LEDGER")) {
        printf("LEDGER %s balance %s\n", a[1], money(customer->balance).text);
        for (int i = 0; i < customer->log_count; ++i) {
            BalanceRow row = customer->log[i];
            printf("  day %d %s %s%s balance %s\n", row.day, row.description,
                   row.change > 0 ? "+" : "", money(row.change).text, money(row.balance).text);
        }
        if (!customer->log_count) puts("  (none)");
    } else {
        printf("STATEMENT %s region %s tax %s%% method %s balance %s\n",
               customer->name, customer->region, money(tax_rate(customer)).text,
               customer->payment_ok ? "OK" : "FAIL", money(customer->balance).text);
        for (int i = 0; i < subscription_count; ++i) {
            Subscription *s = &subscriptions[i];
            if (s->customer == customer)
                printf("  sub %d %s %s\n", s->id, s->plan->name, state_names[s->state]);
        }
        Money outstanding = 0;
        for (int i = 0; i < invoice_count; ++i) {
            Invoice *bill = &invoices[i];
            if (bill->subscription->customer != customer) continue;
            printf("  invoice %d day %d sub %d %s total %s outstanding %s\n",
                   bill->id, bill->day, bill->subscription->id, bill->kind,
                   money(bill->totals.total).text, money(bill->outstanding).text);
            outstanding += bill->outstanding;
        }
        printf("  outstanding %s\n", money(outstanding).text);
    }
    return true;
}

static int compare_plans(const void *a, const void *b) {
    Plan *const *left = a, *const *right = b;
    return strcmp((*left)->name, (*right)->name);
}

static int compare_customers(const void *a, const void *b) {
    Customer *const *left = a, *const *right = b;
    return strcmp((*left)->name, (*right)->name);
}

static void monthly_revenue(void) {
    Plan *ordered[20];
    for (int i = 0; i < plan_count; ++i) ordered[i] = &plans[i];
    qsort(ordered, (size_t)plan_count, sizeof *ordered, compare_plans);
    puts("MRR");
    int total_count = 0;
    Money total = 0;
    for (int i = 0; i < plan_count; ++i) {
        Plan *plan = ordered[i];
        int count = 0;
        Money amount = 0;
        for (int j = 0; j < subscription_count; ++j) {
            Subscription *s = &subscriptions[j];
            if (s->plan != plan || (s->state != ACTIVE && s->state != PAST_DUE)) continue;
            Money cost = fee(plan, s->seats);
            amount += plan->length == 30 ? cost : plan->length == 360 ? cost / 12 : cost * 30 / 7;
            ++count;
        }
        if (count) printf("  %s subs %d mrr %s\n", plan->name, count, money(amount).text);
        total_count += count;
        total += amount;
    }
    printf("  total subs %d mrr %s\n", total_count, money(total).text);
}

static void print_aging(const char *name, Money buckets[3]) {
    printf("  %s 0-30 %s 31-60 %s 61+ %s sum %s\n", name,
           money(buckets[0]).text, money(buckets[1]).text, money(buckets[2]).text,
           money(buckets[0] + buckets[1] + buckets[2]).text);
}

static void aging(void) {
    Customer *ordered[30];
    for (int i = 0; i < customer_count; ++i) ordered[i] = &customers[i];
    qsort(ordered, (size_t)customer_count, sizeof *ordered, compare_customers);
    Money totals[3] = {0};
    printf("AGING day %d\n", day);
    for (int i = 0; i < customer_count; ++i) {
        Money buckets[3] = {0};
        for (int j = 0; j < invoice_count; ++j) {
            Invoice *bill = &invoices[j];
            if (bill->subscription->customer != ordered[i] || !bill->outstanding) continue;
            int age = day - bill->day;
            buckets[age <= 30 ? 0 : age <= 60 ? 1 : 2] += bill->outstanding;
        }
        if (buckets[0] || buckets[1] || buckets[2]) print_aging(ordered[i]->name, buckets);
        for (int j = 0; j < 3; ++j) totals[j] += buckets[j];
    }
    print_aging("total", totals);
}

static void revenue(void) {
    Money subtotal = 0, discount = 0, tax = 0, total = 0, credit = 0;
    Money paid = 0, refunded = 0, outstanding = 0, balances = 0;
    for (int i = 0; i < invoice_count; ++i) {
        Invoice *bill = &invoices[i];
        subtotal += bill->totals.subtotal;
        discount += bill->totals.discount;
        tax += bill->totals.tax;
        total += bill->totals.total;
        credit += bill->totals.credit;
        paid += bill->paid;
        refunded += bill->refunded;
        outstanding += bill->outstanding;
    }
    for (int i = 0; i < customer_count; ++i) balances += customers[i].balance;
    puts("REVENUE");
    printf("  invoices %d subtotal %s discount %s tax %s total %s\n", invoice_count,
           money(subtotal).text, money(discount).text, money(tax).text, money(total).text);
    printf("  credit %s paid %s refunded %s outstanding %s balances %s\n",
           money(credit).text, money(paid).text, money(refunded).text,
           money(outstanding).text, money(balances).text);
}

static void command(char **a, int n) {
    if (setup_command(a, n) || customer_command(a) ||
        subscription_command(a, n) || invoice_command(a)) return;
    if (equal(a[0], "DAY")) {
        int next = atoi(a[1]);
        if (next <= day) { printf("ERROR invalid day %s\n", a[1]); return; }
        printf("DAY %d\n", next);
        while (day < next) {
            ++day;
            for (int i = 0; i < subscription_count; ++i) advance_subscription(&subscriptions[i]);
        }
    } else if (equal(a[0], "MRR")) monthly_revenue();
    else if (equal(a[0], "AGING")) aging();
    else if (equal(a[0], "REVENUE")) revenue();
    else if (equal(a[0], "DUNNING")) {
        puts("DUNNING");
        int count = 0;
        for (int i = 0; i < invoice_count; ++i) {
            Invoice *bill = &invoices[i];
            if (!bill->retry_count) continue;
            printf("  invoice %d sub %d %s outstanding %s attempts %d next %d\n",
                   bill->id, bill->subscription->id, bill->subscription->customer->name,
                   money(bill->outstanding).text, bill->attempts, bill->retries[bill->retry_index]);
            ++count;
        }
        if (!count) puts("  (none)");
    } else if (equal(a[0], "EVENTS")) {
        int filter = 0;
        if (n == 2) {
            Subscription *s = find_subscription(a[1]);
            if (!s) return;
            filter = s->id;
            printf("EVENTS sub %d\n", filter);
        } else puts("EVENTS");
        int count = 0;
        for (int i = 0; i < event_count; ++i) {
            Event event = events[i];
            if (filter && event.subscription != filter) continue;
            printf("  day %d sub %d %s -> %s\n", event.day, event.subscription,
                   state_names[event.previous], state_names[event.current]);
            ++count;
        }
        if (!count) puts("  (none)");
    }
}

int main(void) {
    char line[512];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count && fgets(line, sizeof line, stdin); ++i) {
        char *args[20];
        int size = 0;
        for (char *token = strtok(line, " \r\n"); token; token = strtok(NULL, " \r\n"))
            args[size++] = token;
        command(args, size);
    }
    for (int i = 0; i < customer_count; ++i) free(customers[i].log);
    free(events);
    free(invoices);
    return 0;
}
