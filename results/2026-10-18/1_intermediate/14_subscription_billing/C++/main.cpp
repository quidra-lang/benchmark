#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;
using Money = int64_t;

struct CommandError : runtime_error {
    using runtime_error::runtime_error;
};

int number(const string& text) {
    return stoi(text);
}

Money cents(const string& text) {
    size_t dot = text.find('.');
    return stoll(text.substr(0, dot)) * 100 + stoll(text.substr(dot + 1));
}

string money(Money value) {
    string sign = value < 0 ? "-" : "";
    value = llabs(value);
    string fraction = to_string(value % 100);
    return sign + to_string(value / 100) + "." +
           (fraction.size() == 1 ? "0" : "") + fraction;
}

string signed_money(Money value) {
    return (value > 0 ? "+" : "") + money(value);
}

string percentage(int basis_points) {
    return money(basis_points) + "%";
}

int period_length(const string& cycle) {
    return cycle == "WEEKLY" ? 7 : cycle == "MONTHLY" ? 30 : 360;
}

struct Tier {
    int upper;
    Money unit;
    Money flat;
};

struct Plan {
    string name;
    Money price = 0;
    string cycle;
    int length = 0;
    int trial = 0;
    Money setup = 0;
    bool per_seat = false;
    string mode;
    vector<Tier> tiers;

    Money fee(int seats) const {
        return price * (per_seat ? seats : 1);
    }

    Money usage_charge(int units) const {
        Money amount = 0;
        int lower = 0;
        for (size_t i = 0; i < tiers.size(); ++i) {
            const Tier& tier = tiers[i];
            bool last = i + 1 == tiers.size();
            if (mode == "VOLUME") {
                if (last || tier.upper < 0 || units <= tier.upper)
                    return units * tier.unit + tier.flat;
            } else {
                if (units <= lower) break;
                int end = last || tier.upper < 0 ? units : min(units, tier.upper);
                amount += static_cast<Money>(end - lower) * tier.unit + tier.flat;
                if (last || tier.upper < 0) break;
                lower = tier.upper;
            }
        }
        return amount;
    }
};

struct BalanceRow {
    int day;
    string description;
    Money change;
    Money balance;
};

struct Customer {
    string name;
    string region;
    string method = "OK";
    Money balance = 0;
    vector<BalanceRow> log;
    vector<int> subscriptions;
    vector<int> invoices;
};

struct Coupon {
    string name;
    string kind;
    Money value = 0;
    int applications = -1;
    int maximum = -1;
    int redemptions = 0;
};

struct Subscription {
    int number;
    string customer;
    string plan;
    int seats;
    string state = "NONE";
    int start = -1;
    int end = -1;
    int trial_end = -1;
    int pause_start = -1;
    string pending_plan;
    int pending_seats = 0;
    bool cancel_end = false;
    int cancel_on = -1;
    int canceled_on = -1;
    string coupon;
    int remaining = -1;
    int usage = 0;
    vector<int> invoices;
};

struct Item {
    string description;
    Money amount;
};

struct Totals {
    Money subtotal = 0, discount = 0, tax = 0, total = 0, credit = 0, due = 0;
};

struct Invoice {
    int number;
    int subscription;
    string customer;
    int day;
    string kind;
    vector<Item> items;
    Totals totals;
    Money paid = 0;
    Money refunded = 0;
    Money outstanding = 0;
    int attempts = 0;
    vector<int> retries;

    string state() const {
        return outstanding ? "OPEN" : "PAID";
    }
};

struct Event {
    int day;
    int subscription;
    string previous;
    string current;
};

class BillingService {
    int day = 1;
    map<string, Plan> plans;
    map<string, int> tax_rates;
    map<string, Customer> customers;
    map<string, Coupon> coupons;
    vector<Subscription> subscriptions;
    vector<Invoice> invoices;
    vector<Event> events;
    vector<string> output;

    template<class... Args>
    void emit(int indent, const Args&... parts) {
        ostringstream text;
        text << string(indent, ' ');
        bool first = true;
        ((text << (first ? "" : " ") << parts, first = false), ...);
        output.push_back(text.str());
    }

    template<class... Args>
    void notice(const Args&... parts) {
        ostringstream text;
        bool first = true;
        ((text << (first ? "" : " ") << parts, first = false), ...);
        emit(2, "day", day, text.str());
    }

    static void fail(const string& message) {
        throw CommandError(message);
    }

    Plan& plan(const string& name) {
        auto it = plans.find(name);
        if (it == plans.end()) fail("unknown plan " + name);
        return it->second;
    }

    Customer& customer(const string& name) {
        auto it = customers.find(name);
        if (it == customers.end()) fail("unknown customer " + name);
        return it->second;
    }

    Coupon& redeemable_coupon(const string& name) {
        auto it = coupons.find(name);
        if (it == coupons.end()) fail("unknown coupon " + name);
        if (it->second.maximum >= 0 &&
            it->second.redemptions == it->second.maximum)
            fail("coupon exhausted " + name);
        return it->second;
    }

    Subscription& subscription(const string& text) {
        int id = number(text);
        if (id < 1 || id > static_cast<int>(subscriptions.size()))
            fail("unknown sub " + text);
        return subscriptions[id - 1];
    }

    Subscription& require_state(const string& text, const vector<string>& allowed) {
        Subscription& s = subscription(text);
        if (find(allowed.begin(), allowed.end(), s.state) == allowed.end())
            fail("invalid state " + text + " " + s.state);
        return s;
    }

    Invoice& invoice(const string& text) {
        int id = number(text);
        if (id < 1 || id > static_cast<int>(invoices.size()))
            fail("unknown invoice " + text);
        return invoices[id - 1];
    }

    Money fee(const Subscription& s) const {
        return plans.at(s.plan).fee(s.seats);
    }

    string period(const Subscription& s) const {
        return to_string(s.start) + "-" + to_string(s.end);
    }

    void balance_change(Customer& c, Money change, const string& description) {
        if (change == 0) return;
        c.balance += change;
        c.log.push_back({day, description, change, c.balance});
    }

    void change_state(Subscription& s, const string& next) {
        string old = s.state;
        if (old == "PAST_DUE") {
            for (int id : s.invoices)
                invoices[id - 1].retries.clear();
        }
        s.state = next;
        notice("sub", s.number, old, "->", next);
        events.push_back({day, s.number, old, next});
    }

    Item period_item(const Plan& p, int seats, int start) const {
        return {"charge " + p.name + " seats " + to_string(seats) + " " +
                to_string(start) + "-" + to_string(start + p.length),
                p.fee(seats)};
    }

    vector<Item> opening_items(const Subscription& s, int start) const {
        const Plan& p = plans.at(s.plan);
        vector<Item> items{period_item(p, s.seats, start)};
        if (p.setup)
            items.push_back({"setup " + p.name, p.setup});
        return items;
    }

    vector<Item> usage_items(const Subscription& s) const {
        const Plan& p = plans.at(s.plan);
        if (p.mode.empty() || !s.usage) return {};
        return {{"usage " + p.name + " " + to_string(s.usage) + " units",
                 p.usage_charge(s.usage)}};
    }

    vector<Item> close_usage(Subscription& s) {
        vector<Item> items = usage_items(s);
        if (!items.empty()) s.usage = 0;
        return items;
    }

    bool coupon_usable(const Subscription& s, Money subtotal) const {
        return subtotal > 0 && !s.coupon.empty() && s.remaining != 0;
    }

    Totals invoice_totals(const Subscription& s, const vector<Item>& items) const {
        Totals totals;
        for (const Item& item : items) totals.subtotal += item.amount;
        if (coupon_usable(s, totals.subtotal)) {
            const Coupon& coupon = coupons.at(s.coupon);
            totals.discount = coupon.kind == "PERCENT"
                ? totals.subtotal * coupon.value / 10000
                : min(totals.subtotal, coupon.value);
        }
        const Customer& c = customers.at(s.customer);
        int tax_rate = 0;
        auto it = tax_rates.find(c.region);
        if (it != tax_rates.end()) tax_rate = it->second;
        totals.tax = (totals.subtotal - totals.discount) * tax_rate / 10000;
        totals.total = totals.subtotal - totals.discount + totals.tax;
        totals.credit = min(c.balance, totals.total);
        totals.due = totals.total - totals.credit;
        return totals;
    }

    void issue(Subscription& s, const string& kind, const vector<Item>& items) {
        Totals totals = invoice_totals(s, items);
        int id = static_cast<int>(invoices.size()) + 1;
        Invoice entry{id, s.number, s.customer, day, kind, items, totals};
        entry.outstanding = totals.due;
        if (coupon_usable(s, totals.subtotal) && s.remaining > 0)
            --s.remaining;
        invoices.push_back(move(entry));
        s.invoices.push_back(id);
        Customer& c = customers.at(s.customer);
        c.invoices.push_back(id);
        balance_change(c, -totals.credit, "applied invoice " + to_string(id));
        Invoice& bill = invoices.back();
        string result;
        if (bill.outstanding == 0) {
            result = "PAID";
        } else if (s.state == "UNPAID") {
            result = "OPEN";
        } else {
            bill.attempts = 1;
            if (c.method == "OK") {
                bill.paid = bill.outstanding;
                bill.outstanding = 0;
                result = "PAID";
            } else {
                result = "FAILED";
            }
        }
        notice("invoice", id, "sub", s.number, kind, "total", money(totals.total),
               "credit", money(totals.credit), "due", money(totals.due), result);
        if (result == "FAILED") {
            if (s.state == "ACTIVE") change_state(s, "PAST_DUE");
            if (s.state == "PAST_DUE")
                bill.retries = {day + 3, day + 5, day + 7};
        }
    }

    void payment_complete(Invoice& bill) {
        bill.retries.clear();
        Subscription& s = subscriptions[bill.subscription - 1];
        if (s.state == "PAST_DUE" || s.state == "UNPAID") {
            bool settled = true;
            for (int id : s.invoices)
                if (invoices[id - 1].outstanding)
                    settled = false;
            if (settled) {
                s.cancel_on = -1;
                change_state(s, "ACTIVE");
            }
        }
    }

    void cancel_subscription(Subscription& s) {
        change_state(s, "CANCELED");
        s.canceled_on = day;
        s.pending_plan.clear();
        s.cancel_end = false;
        s.cancel_on = -1;
        vector<Item> items = close_usage(s);
        if (!items.empty()) issue(s, "final", items);
    }

    void retry(Invoice& bill) {
        bill.retries.erase(bill.retries.begin());
        ++bill.attempts;
        int attempt = bill.attempts - 1;
        if (customers.at(bill.customer).method == "OK") {
            bill.paid += bill.outstanding;
            bill.outstanding = 0;
            notice("retry", attempt, "invoice", bill.number, "PAID");
            payment_complete(bill);
        } else {
            notice("retry", attempt, "invoice", bill.number, "FAILED");
            if (bill.retries.empty()) {
                Subscription& s = subscriptions[bill.subscription - 1];
                change_state(s, "UNPAID");
                s.cancel_on = day + 14;
            }
        }
    }

    void advance_subscription(Subscription& s) {
        if (s.state == "PAUSED" || s.state == "CANCELED") return;
        for (int id : s.invoices) {
            Invoice& bill = invoices[id - 1];
            if (!bill.retries.empty() && bill.retries.front() == day)
                retry(bill);
        }
        if (s.state == "UNPAID" && s.cancel_on == day)
            cancel_subscription(s);
        if (s.state == "TRIALING" && s.trial_end == day) {
            if (s.cancel_end) {
                cancel_subscription(s);
            } else {
                change_state(s, "ACTIVE");
                s.start = day;
                s.end = day + plans.at(s.plan).length;
                issue(s, "first", opening_items(s, day));
            }
        }
        if ((s.state == "ACTIVE" || s.state == "PAST_DUE" || s.state == "UNPAID") &&
            s.end == day) {
            if (s.cancel_end) {
                cancel_subscription(s);
            } else {
                vector<Item> items = close_usage(s);
                if (!s.pending_plan.empty()) {
                    notice("sub", s.number, s.plan, "seats", s.seats, "->",
                           s.pending_plan, "seats", s.pending_seats);
                    s.plan = s.pending_plan;
                    s.seats = s.pending_seats;
                    s.pending_plan.clear();
                }
                s.start = day;
                s.end = day + plans.at(s.plan).length;
                items.push_back(period_item(plans.at(s.plan), s.seats, day));
                issue(s, "renewal", items);
            }
        }
    }

    void cmd_plan(const vector<string>& a) {
        const string& name = a[0];
        if (plans.count(name)) fail("duplicate plan " + name);
        Plan p;
        p.name = name;
        p.price = cents(a[1]);
        p.cycle = a[2];
        p.length = period_length(a[2]);
        for (size_t i = 3; i < a.size(); ++i) {
            if (a[i] == "TRIAL") {
                p.trial = number(a[++i]);
            } else if (a[i] == "SETUP") {
                p.setup = cents(a[++i]);
            } else if (a[i] == "PERSEAT") {
                p.per_seat = true;
            } else if (a[i] == "GRADUATED" || a[i] == "VOLUME") {
                p.mode = a[i];
            }
        }
        plans.emplace(name, p);
        string text = "PLAN " + name + " " + p.cycle + " " + money(p.price);
        if (p.trial) text += " trial " + to_string(p.trial);
        if (p.setup) text += " setup " + money(p.setup);
        if (p.per_seat) text += " perseat";
        if (!p.mode.empty()) {
            text += p.mode == "GRADUATED" ? " graduated" : " volume";
        }
        emit(0, text);
    }

    void cmd_tier(const vector<string>& a) {
        Plan& p = plan(a[0]);
        if (p.mode.empty()) fail("not metered " + p.name);
        int upper = a[1] == "INF" ? -1 : number(a[1]);
        if (!p.tiers.empty()) {
            int previous = p.tiers.back().upper;
            if (previous < 0 || (upper >= 0 && upper <= previous))
                fail("tier order " + p.name);
        }
        p.tiers.push_back({upper, cents(a[2]), cents(a[3])});
        emit(0, "TIER", p.name, p.tiers.size(), "upto", a[1], "unit", a[2], "flat", a[3]);
    }

    void cmd_tax(const vector<string>& a) {
        int rate = number(a[1]);
        tax_rates[a[0]] = rate;
        emit(0, "TAX", a[0], percentage(rate));
    }

    void cmd_customer(const vector<string>& a) {
        if (customers.count(a[0])) fail("duplicate customer " + a[0]);
        Customer c;
        c.name = a[0];
        c.region = a[1];
        customers.emplace(a[0], move(c));
        emit(0, "CUSTOMER", a[0], "region", a[1]);
    }

    void cmd_coupon(const vector<string>& a) {
        if (coupons.count(a[0])) fail("duplicate coupon " + a[0]);
        Coupon c;
        c.name = a[0];
        c.kind = a[1];
        c.value = a[1] == "PERCENT" ? number(a[2]) : cents(a[2]);
        c.applications = a[3] == "ONCE" ? 1 : -1;
        size_t i = 4;
        if (a[3] == "REPEATING") c.applications = number(a[i++]);
        if (i < a.size()) c.maximum = number(a[i + 1]);
        coupons.emplace(c.name, c);
        string shown = c.kind == "PERCENT" ? percentage(static_cast<int>(c.value)) : money(c.value);
        string text = "COUPON " + c.name + " " +
                      (c.kind == "PERCENT" ? "percent" : "amount") + " " +
                      shown + " " + (a[3] == "REPEATING" ? "repeating " +
                      to_string(c.applications) : a[3] == "ONCE" ? "once" : "forever");
        if (c.maximum >= 0) text += " max " + to_string(c.maximum);
        emit(0, text);
    }

    void cmd_paymethod(const vector<string>& a) {
        Customer& c = customer(a[0]);
        c.method = a[1];
        emit(0, "PAYMETHOD", c.name, c.method);
    }

    void cmd_credit(const vector<string>& a) {
        Customer& c = customer(a[0]);
        Money amount = cents(a[1]);
        if (!amount) fail("invalid amount");
        balance_change(c, amount, "grant");
        emit(0, "CREDIT", c.name, "amount", a[1], "balance", money(c.balance));
    }

    void cmd_day(const vector<string>& a) {
        int next = number(a[0]);
        if (next <= day) fail("invalid day " + a[0]);
        emit(0, "DAY", next);
        for (int next_day = day + 1; next_day <= next; ++next_day) {
            day = next_day;
            for (size_t id = 0; id < subscriptions.size(); ++id)
                advance_subscription(subscriptions[id]);
        }
    }

    void cmd_subscribe(const vector<string>& a) {
        Customer& c = customer(a[0]);
        Plan& p = plan(a[1]);
        int seats = 1;
        bool has_seats = false;
        string coupon_name;
        for (size_t i = 2; i < a.size(); i += 2) {
            if (a[i] == "SEATS") {
                seats = number(a[i + 1]);
                has_seats = true;
            } else {
                coupon_name = a[i + 1];
            }
        }
        if (has_seats && !p.per_seat) fail("not per-seat " + p.name);
        if (seats == 0) fail("invalid seats");
        Coupon* coupon = coupon_name.empty() ? nullptr : &redeemable_coupon(coupon_name);
        int number = static_cast<int>(subscriptions.size()) + 1;
        Subscription s;
        s.number = number;
        s.customer = c.name;
        s.plan = p.name;
        s.seats = seats;
        s.coupon = coupon_name;
        if (coupon != nullptr) {
            ++coupon->redemptions;
            s.remaining = coupon->applications;
        }
        subscriptions.push_back(move(s));
        c.subscriptions.push_back(number);
        Subscription& subscription = subscriptions.back();
        string text = "SUBSCRIBE sub " + to_string(number) + " " + c.name +
                      " " + p.name + " seats " + to_string(seats);
        if (coupon != nullptr) text += " coupon " + coupon_name;
        emit(0, text);
        if (p.trial) {
            subscription.trial_end = day + p.trial;
            change_state(subscription, "TRIALING");
        } else {
            change_state(subscription, "ACTIVE");
            subscription.start = day;
            subscription.end = day + p.length;
            issue(subscription, "first", opening_items(subscription, day));
        }
    }

    void cmd_change(const vector<string>& a) {
        Subscription& s = require_state(a[0], {"ACTIVE", "TRIALING"});
        Plan* p;
        int seats = s.seats;
        if (a[1] == "PLAN") {
            p = &plan(a[2]);
            seats = p->per_seat ? s.seats : 1;
        } else {
            p = &plan(s.plan);
            if (!p->per_seat) fail("not per-seat " + p->name);
            seats = number(a[2]);
            if (!seats) fail("invalid seats");
        }
        if (p->name == s.plan && seats == s.seats)
            fail("no change " + a[0]);
        const Plan& old = plans.at(s.plan);
        int old_seats = s.seats;
        string text = "CHANGE sub " + to_string(s.number) + " " + old.name +
                      " seats " + to_string(old_seats) + " -> " + p->name +
                      " seats " + to_string(seats);
        s.pending_plan.clear();
        bool upgrade = p->fee(seats) * old.length > old.fee(old_seats) * p->length;
        if (s.state == "TRIALING") {
            s.plan = p->name;
            s.seats = seats;
            emit(0, text + " now");
        } else if (upgrade) {
            emit(0, text + " now");
            int days = s.end - day;
            vector<Item> items = close_usage(s);
            items.push_back({"unused " + old.name + " seats " + to_string(old_seats) +
                             " " + to_string(days) + " days",
                             -(old.fee(old_seats) * days / old.length)});
            items.push_back({"remaining " + p->name + " seats " + to_string(seats) +
                             " " + to_string(days) + " days",
                             p->fee(seats) * days / p->length});
            s.plan = p->name;
            s.seats = seats;
            issue(s, "upgrade", items);
        } else {
            s.pending_plan = p->name;
            s.pending_seats = seats;
            emit(0, text, "at", s.end);
        }
    }

    void cmd_pause(const vector<string>& a) {
        Subscription& s = require_state(a[0], {"ACTIVE"});
        emit(0, "PAUSE", "sub", s.number);
        s.pause_start = day;
        change_state(s, "PAUSED");
    }

    void cmd_resume(const vector<string>& a) {
        Subscription& s = require_state(a[0], {"PAUSED"});
        int elapsed = day - s.pause_start;
        s.end += elapsed;
        s.pause_start = -1;
        emit(0, "RESUME", "sub", s.number, "shift", elapsed, "period", period(s));
        change_state(s, "ACTIVE");
    }

    void cmd_cancel(const vector<string>& a) {
        Subscription& s = subscription(a[0]);
        if (a[1] == "END") {
            if (s.state != "ACTIVE" && s.state != "TRIALING")
                fail("invalid state " + a[0] + " " + s.state);
            if (s.cancel_end) fail("already canceling " + a[0]);
            s.cancel_end = true;
            int end = s.state == "TRIALING" ? s.trial_end : s.end;
            emit(0, "CANCEL", "sub", s.number, "end", end);
        } else {
            if (s.state == "CANCELED")
                fail("invalid state " + a[0] + " " + s.state);
            Money refund = 0;
            const Plan& p = plans.at(s.plan);
            if (s.state == "ACTIVE" || s.state == "PAUSED") {
                int start = s.state == "ACTIVE" ? day : s.pause_start;
                refund = fee(s) * (s.end - start) / p.length;
            }
            balance_change(customers.at(s.customer), refund,
                           "cancel sub " + to_string(s.number));
            emit(0, "CANCEL", "sub", s.number, "now", "credit", money(refund));
            cancel_subscription(s);
        }
    }

    void cmd_usage(const vector<string>& a) {
        Subscription& s = require_state(a[0], {"ACTIVE", "PAST_DUE"});
        if (plans.at(s.plan).mode.empty()) fail("not metered " + s.plan);
        int units = number(a[1]);
        if (!units) fail("invalid units");
        s.usage += units;
        emit(0, "USAGE", "sub", s.number, "units", units, "total", s.usage);
    }

    void cmd_apply(const vector<string>& a) {
        Subscription& s = subscription(a[0]);
        if (s.state == "CANCELED") fail("invalid state " + a[0] + " " + s.state);
        Coupon& coupon = redeemable_coupon(a[1]);
        ++coupon.redemptions;
        s.coupon = coupon.name;
        s.remaining = coupon.applications;
        emit(0, "APPLY", "sub", s.number, "coupon", coupon.name);
    }

    void cmd_pay(const vector<string>& a) {
        Invoice& bill = invoice(a[0]);
        if (!bill.outstanding) fail("already paid " + a[0]);
        emit(0, "PAY", "invoice", bill.number, "amount", money(bill.outstanding));
        bill.paid += bill.outstanding;
        bill.outstanding = 0;
        payment_complete(bill);
    }

    void cmd_refund(const vector<string>& a) {
        Invoice& bill = invoice(a[0]);
        Money value = cents(a[1]);
        if (!value) fail("invalid amount");
        Money maximum = bill.totals.total - bill.refunded;
        if (value > maximum)
            fail("refund exceeds " + a[0] + " " + money(maximum));
        Money applied = min(value, bill.outstanding);
        bill.refunded += value;
        bill.outstanding -= applied;
        Customer& c = customers.at(bill.customer);
        balance_change(c, value - applied, "refund invoice " + to_string(bill.number));
        emit(0, "REFUND", "invoice", bill.number, "amount", a[1], "applied",
             money(applied), "balance", money(c.balance));
        if (applied && !bill.outstanding) payment_complete(bill);
    }

    void emit_items(const vector<Item>& items) {
        for (const Item& item : items)
            emit(2, item.description, money(item.amount));
    }

    void emit_totals(const Totals& totals) {
        emit(2, "subtotal", money(totals.subtotal), "discount", money(totals.discount),
             "tax", money(totals.tax), "total", money(totals.total));
    }

    void cmd_invoice(const vector<string>& a) {
        const Invoice& bill = invoice(a[0]);
        emit(0, "INVOICE", bill.number, "sub", bill.subscription, bill.customer,
             "day", bill.day, bill.kind, bill.state());
        emit_items(bill.items);
        emit_totals(bill.totals);
        emit(2, "credit", money(bill.totals.credit), "due", money(bill.totals.due),
             "paid", money(bill.paid), "refunded", money(bill.refunded),
             "outstanding", money(bill.outstanding));
    }

    void cmd_sub(const vector<string>& a) {
        const Subscription& s = subscription(a[0]);
        emit(0, "SUB", s.number, s.customer, s.plan, "seats", s.seats, s.state);
        if (s.state == "TRIALING") emit(2, "trial", "until", s.trial_end);
        if (s.state == "ACTIVE" || s.state == "PAST_DUE" ||
            s.state == "UNPAID" || s.state == "PAUSED")
            emit(2, "period", period(s));
        if (s.state == "PAUSED") emit(2, "paused", "since", s.pause_start);
        if (!s.pending_plan.empty())
            emit(2, "pending", s.pending_plan, "seats", s.pending_seats);
        if (s.cancel_end) emit(2, "cancel", "at", "end");
        if (s.cancel_on >= 0) emit(2, "cancel", "on", s.cancel_on);
        if (s.state == "CANCELED") emit(2, "canceled", "on", s.canceled_on);
        if (!s.coupon.empty()) {
            if (s.remaining < 0) emit(2, "coupon", s.coupon, "forever");
            else if (s.remaining > 0) emit(2, "coupon", s.coupon, "left", s.remaining);
        }
        if (!plans.at(s.plan).mode.empty() && s.state != "CANCELED")
            emit(2, "usage", s.usage);
        string open;
        for (int id : s.invoices) {
            if (invoices[id - 1].outstanding > 0)
                open += " " + to_string(id);
        }
        if (!open.empty()) emit(2, "open" + open);
    }

    void cmd_preview(const vector<string>& a) {
        const Subscription& s = require_state(a[0],
                {"TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"});
        int due_day = s.state == "TRIALING" ? s.trial_end : s.end;
        vector<Item> items;
        string kind;
        if (s.cancel_end) {
            kind = "final";
            if (s.state != "TRIALING") items = usage_items(s);
        } else if (s.state == "TRIALING") {
            kind = "first";
            items = opening_items(s, due_day);
        } else {
            kind = "renewal";
            items = usage_items(s);
            string name = s.pending_plan.empty() ? s.plan : s.pending_plan;
            int seats = s.pending_plan.empty() ? s.seats : s.pending_seats;
            items.push_back(period_item(plans.at(name), seats, due_day));
        }
        emit(0, "PREVIEW", "sub", s.number, "day", due_day, kind);
        if (items.empty()) {
            emit(2, "(none)");
            return;
        }
        emit_items(items);
        Totals totals = invoice_totals(s, items);
        emit_totals(totals);
        emit(2, "credit", money(totals.credit), "due", money(totals.due));
    }

    void cmd_statement(const vector<string>& a) {
        const Customer& c = customer(a[0]);
        int rate = tax_rates.count(c.region) ? tax_rates.at(c.region) : 0;
        emit(0, "STATEMENT", c.name, "region", c.region, "tax",
             percentage(rate), "method", c.method, "balance", money(c.balance));
        Money outstanding = 0;
        for (int id : c.subscriptions) {
            const Subscription& s = subscriptions[id - 1];
            emit(2, "sub", s.number, s.plan, s.state);
        }
        for (int id : c.invoices) {
            const Invoice& bill = invoices[id - 1];
            emit(2, "invoice", bill.number, "day", bill.day, "sub", bill.subscription,
                 bill.kind, "total", money(bill.totals.total),
                 "outstanding", money(bill.outstanding));
            outstanding += bill.outstanding;
        }
        emit(2, "outstanding", money(outstanding));
    }

    void cmd_ledger(const vector<string>& a) {
        const Customer& c = customer(a[0]);
        emit(0, "LEDGER", c.name, "balance", money(c.balance));
        for (const BalanceRow& row : c.log)
            emit(2, "day", row.day, row.description, signed_money(row.change),
                 "balance", money(row.balance));
        if (c.log.empty()) emit(2, "(none)");
    }

    void cmd_mrr(const vector<string>&) {
        map<string, pair<int, Money>> rows;
        for (const Subscription& s : subscriptions) {
            if (s.state != "ACTIVE" && s.state != "PAST_DUE") continue;
            const Plan& p = plans.at(s.plan);
            Money amount = p.fee(s.seats);
            Money monthly = p.cycle == "MONTHLY" ? amount :
                            p.cycle == "YEARLY" ? amount / 12 : amount * 30 / 7;
            auto& row = rows[p.name];
            ++row.first;
            row.second += monthly;
        }
        emit(0, "MRR");
        int count = 0;
        Money sum = 0;
        for (const auto& [name, row] : rows) {
            emit(2, name, "subs", row.first, "mrr", money(row.second));
            count += row.first;
            sum += row.second;
        }
        emit(2, "total", "subs", count, "mrr", money(sum));
    }

    void cmd_aging(const vector<string>&) {
        map<string, vector<Money>> rows;
        vector<Money> totals(3, 0);
        for (const Invoice& bill : invoices) {
            if (!bill.outstanding) continue;
            int age = day - bill.day;
            int bucket = age <= 30 ? 0 : age <= 60 ? 1 : 2;
            auto& row = rows[bill.customer];
            if (row.empty()) row.assign(3, 0);
            row[bucket] += bill.outstanding;
            totals[bucket] += bill.outstanding;
        }
        emit(0, "AGING", "day", day);
        for (const auto& [name, row] : rows) {
            emit(2, name, "0-30", money(row[0]), "31-60", money(row[1]),
                 "61+", money(row[2]), "sum", money(row[0] + row[1] + row[2]));
        }
        emit(2, "total", "0-30", money(totals[0]), "31-60", money(totals[1]),
             "61+", money(totals[2]), "sum", money(totals[0] + totals[1] + totals[2]));
    }

    void cmd_dunning(const vector<string>&) {
        emit(0, "DUNNING");
        bool found = false;
        for (const Invoice& bill : invoices) {
            if (bill.retries.empty()) continue;
            found = true;
            emit(2, "invoice", bill.number, "sub", bill.subscription, bill.customer,
                 "outstanding", money(bill.outstanding), "attempts", bill.attempts,
                 "next", bill.retries.front());
        }
        if (!found) emit(2, "(none)");
    }

    void cmd_revenue(const vector<string>&) {
        Totals totals;
        Money paid = 0, refunded = 0, outstanding = 0, balances = 0;
        for (const Invoice& bill : invoices) {
            totals.subtotal += bill.totals.subtotal;
            totals.discount += bill.totals.discount;
            totals.tax += bill.totals.tax;
            totals.total += bill.totals.total;
            totals.credit += bill.totals.credit;
            paid += bill.paid;
            refunded += bill.refunded;
            outstanding += bill.outstanding;
        }
        for (const auto& [id, c] : customers) balances += c.balance;
        emit(0, "REVENUE");
        emit(2, "invoices", invoices.size(), "subtotal", money(totals.subtotal),
             "discount", money(totals.discount), "tax", money(totals.tax),
             "total", money(totals.total));
        emit(2, "credit", money(totals.credit), "paid", money(paid),
             "refunded", money(refunded), "outstanding", money(outstanding),
             "balances", money(balances));
    }

    void cmd_events(const vector<string>& a) {
        int selected = 0;
        if (!a.empty()) selected = subscription(a[0]).number;
        if (selected) emit(0, "EVENTS", "sub", selected);
        else emit(0, "EVENTS");
        int count = 0;
        for (const Event& event : events) {
            if (selected && event.subscription != selected) continue;
            emit(2, "day", event.day, "sub", event.subscription,
                 event.previous, "->", event.current);
            ++count;
        }
        if (!count) emit(2, "(none)");
    }

public:
    void execute(const string& line) {
        istringstream stream(line);
        vector<string> a;
        string word;
        while (stream >> word) a.push_back(word);
        if (a.empty()) return;
        string command = a[0];
        a.erase(a.begin());
        try {
            if (command == "PLAN") cmd_plan(a);
            else if (command == "TIER") cmd_tier(a);
            else if (command == "TAX") cmd_tax(a);
            else if (command == "CUSTOMER") cmd_customer(a);
            else if (command == "COUPON") cmd_coupon(a);
            else if (command == "PAYMETHOD") cmd_paymethod(a);
            else if (command == "CREDIT") cmd_credit(a);
            else if (command == "DAY") cmd_day(a);
            else if (command == "SUBSCRIBE") cmd_subscribe(a);
            else if (command == "CHANGE") cmd_change(a);
            else if (command == "PAUSE") cmd_pause(a);
            else if (command == "RESUME") cmd_resume(a);
            else if (command == "CANCEL") cmd_cancel(a);
            else if (command == "USAGE") cmd_usage(a);
            else if (command == "APPLY") cmd_apply(a);
            else if (command == "PAY") cmd_pay(a);
            else if (command == "REFUND") cmd_refund(a);
            else if (command == "INVOICE") cmd_invoice(a);
            else if (command == "SUB") cmd_sub(a);
            else if (command == "PREVIEW") cmd_preview(a);
            else if (command == "STATEMENT") cmd_statement(a);
            else if (command == "LEDGER") cmd_ledger(a);
            else if (command == "MRR") cmd_mrr(a);
            else if (command == "AGING") cmd_aging(a);
            else if (command == "DUNNING") cmd_dunning(a);
            else if (command == "REVENUE") cmd_revenue(a);
            else if (command == "EVENTS") cmd_events(a);
        } catch (const CommandError& error) {
            emit(0, "ERROR", error.what());
        }
    }

    void print() const {
        for (const string& line : output) cout << line << '\n';
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int count;
    cin >> count;
    cin.ignore();
    BillingService service;
    string line;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        service.execute(line);
    }
    service.print();
}
