import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    private static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    private record Tier(Long upper, long unit, long flat) {}
    private record Line(String description, long amount) {}
    private record Totals(long subtotal, long discount, long tax, long total, long credit, long due) {}
    private record BalanceEntry(int day, String description, long change, long balance) {}
    private record StateEvent(int day, int number, String oldState, String newState) {}
    private record Pending(Plan plan, int seats) {}

    private static final class Plan {
        final String name;
        final long price;
        final String cycle;
        final int length;
        int trial;
        long setup;
        boolean perSeat;
        String mode;
        final List<Tier> tiers = new ArrayList<>();

        Plan(String name, long price, String cycle) {
            this.name = name;
            this.price = price;
            this.cycle = cycle;
            length = switch (cycle) {
                case "WEEKLY" -> 7;
                case "MONTHLY" -> 30;
                default -> 360;
            };
        }

        long fee(int seats) { return perSeat ? price * seats : price; }

        long usageCharge(long units) {
            long total = 0;
            long lower = 0;
            for (int i = 0; i < tiers.size(); i++) {
                Tier tier = tiers.get(i);
                boolean last = i == tiers.size() - 1;
                if ("VOLUME".equals(mode)) {
                    if (last || tier.upper() == null || units <= tier.upper())
                        return units * tier.unit() + tier.flat();
                } else {
                    if (units <= lower) break;
                    long end = last || tier.upper() == null
                        ? units : Math.min(units, tier.upper());
                    total += (end - lower) * tier.unit() + tier.flat();
                    if (last || tier.upper() == null) break;
                    lower = tier.upper();
                }
            }
            return total;
        }
    }

    private static final class Customer {
        final String name;
        final String region;
        String method = "OK";
        long balance;
        final List<BalanceEntry> log = new ArrayList<>();
        final List<Subscription> subscriptions = new ArrayList<>();
        final List<Invoice> invoices = new ArrayList<>();

        Customer(String name, String region) {
            this.name = name;
            this.region = region;
        }
    }

    private static final class Coupon {
        final String name;
        final String kind;
        final long value;
        final Integer applications;
        final Integer maximum;
        int redemptions;

        Coupon(String name, String kind, long value, Integer applications, Integer maximum) {
            this.name = name;
            this.kind = kind;
            this.value = value;
            this.applications = applications;
            this.maximum = maximum;
        }
    }

    private static final class Subscription {
        final int number;
        final Customer customer;
        Plan plan;
        int seats;
        String state = "NONE";
        Integer start;
        Integer end;
        Integer trialEnd;
        Integer pauseStart;
        Pending pending;
        boolean cancelEnd;
        Integer cancelOn;
        Integer canceledOn;
        Coupon coupon;
        Integer remaining;
        long usage;
        final List<Invoice> invoices = new ArrayList<>();

        Subscription(int number, Customer customer, Plan plan, int seats, Coupon coupon) {
            this.number = number;
            this.customer = customer;
            this.plan = plan;
            this.seats = seats;
            this.coupon = coupon;
            remaining = coupon == null ? null : coupon.applications;
        }

        long fee() { return plan.fee(seats); }
        String period() { return start + "-" + end; }
    }

    private static final class Invoice {
        final int number;
        final Subscription subscription;
        final Customer customer;
        final int day;
        final String kind;
        final List<Line> items;
        final long subtotal;
        final long discount;
        final long tax;
        final long total;
        final long credit;
        final long due;
        long paid;
        long refunded;
        long outstanding;
        int attempts;
        final List<Integer> retries = new ArrayList<>();

        Invoice(int number, Subscription subscription, int day, String kind,
                List<Line> items, Totals totals) {
            this.number = number;
            this.subscription = subscription;
            customer = subscription.customer;
            this.day = day;
            this.kind = kind;
            this.items = items;
            subtotal = totals.subtotal();
            discount = totals.discount();
            tax = totals.tax();
            total = totals.total();
            credit = totals.credit();
            due = totals.due();
            outstanding = due;
        }

        String state() { return outstanding == 0 ? "PAID" : "OPEN"; }
    }

    private static final class Billing {
        int day = 1;
        final Map<String, Plan> plans = new HashMap<>();
        final Map<String, Integer> taxes = new HashMap<>();
        final Map<String, Customer> customers = new HashMap<>();
        final Map<String, Coupon> coupons = new HashMap<>();
        final List<Subscription> subscriptions = new ArrayList<>();
        final List<Invoice> invoices = new ArrayList<>();
        final List<StateEvent> events = new ArrayList<>();
        final List<String> output = new ArrayList<>();

        static long cents(String text) {
            String[] parts = text.split("\\.", 2);
            return Long.parseLong(parts[0]) * 100 + Long.parseLong(parts[1]);
        }

        static String money(long value) {
            long absolute = Math.abs(value);
            return (value < 0 ? "-" : "") + absolute / 100 + "." +
                   String.format(java.util.Locale.ROOT, "%02d", absolute % 100);
        }

        static String signedMoney(long value) {
            return (value > 0 ? "+" : "") + money(value);
        }

        static String percent(long value) { return money(value) + "%"; }

        static String join(Object... parts) {
            StringBuilder line = new StringBuilder();
            for (Object part : parts) {
                if (!line.isEmpty()) line.append(' ');
                line.append(part);
            }
            return line.toString();
        }

        void emit(Object... parts) { output.add(join(parts)); }
        void indented(Object... parts) { output.add("  " + join(parts)); }

        void notice(Object... parts) {
            List<Object> all = new ArrayList<>();
            all.add("day");
            all.add(day);
            all.addAll(Arrays.asList(parts));
            indented(all.toArray());
        }

        static void fail(String reason) { throw new CommandError(reason); }

        Plan plan(String name) {
            Plan result = plans.get(name);
            if (result == null) fail("unknown plan " + name);
            return result;
        }

        Customer customer(String name) {
            Customer result = customers.get(name);
            if (result == null) fail("unknown customer " + name);
            return result;
        }

        Coupon redeemableCoupon(String name) {
            Coupon result = coupons.get(name);
            if (result == null) fail("unknown coupon " + name);
            if (result.maximum != null && result.redemptions == result.maximum)
                fail("coupon exhausted " + name);
            return result;
        }

        Subscription subscription(String text, String... allowed) {
            int number = Integer.parseInt(text);
            if (number < 1 || number > subscriptions.size()) fail("unknown sub " + text);
            Subscription result = subscriptions.get(number - 1);
            if (allowed.length != 0 && !Arrays.asList(allowed).contains(result.state))
                fail("invalid state " + text + " " + result.state);
            return result;
        }

        Invoice invoice(String text) {
            int number = Integer.parseInt(text);
            if (number < 1 || number > invoices.size()) fail("unknown invoice " + text);
            return invoices.get(number - 1);
        }

        int taxRate(String region) { return taxes.getOrDefault(region, 0); }

        void balanceChange(Customer customer, long amount, String description) {
            if (amount == 0) return;
            customer.balance += amount;
            customer.log.add(new BalanceEntry(day, description, amount, customer.balance));
        }

        void changeState(Subscription sub, String state) {
            String old = sub.state;
            if (old.equals("PAST_DUE"))
                for (Invoice inv : sub.invoices) inv.retries.clear();
            sub.state = state;
            notice("sub", sub.number, old, "->", state);
            events.add(new StateEvent(day, sub.number, old, state));
        }

        static Line periodItem(Plan plan, int seats, int start) {
            return new Line("charge " + plan.name + " seats " + seats + " " +
                            start + "-" + (start + plan.length), plan.fee(seats));
        }

        static List<Line> openingItems(Subscription sub, int start) {
            List<Line> result = new ArrayList<>();
            result.add(periodItem(sub.plan, sub.seats, start));
            if (sub.plan.setup != 0)
                result.add(new Line("setup " + sub.plan.name, sub.plan.setup));
            return result;
        }

        static List<Line> usageItems(Subscription sub, boolean close) {
            List<Line> result = new ArrayList<>();
            if (sub.plan.mode == null || sub.usage == 0) return result;
            long units = sub.usage;
            result.add(new Line("usage " + sub.plan.name + " " + units + " units",
                                sub.plan.usageCharge(units)));
            if (close) sub.usage = 0;
            return result;
        }

        static boolean couponUsable(Subscription sub, long subtotal) {
            return subtotal > 0 && sub.coupon != null &&
                   (sub.remaining == null || sub.remaining > 0);
        }

        Totals invoiceTotals(Subscription sub, List<Line> items) {
            long subtotal = 0;
            for (Line item : items) subtotal += item.amount();
            long discount = 0;
            if (couponUsable(sub, subtotal)) {
                Coupon coupon = sub.coupon;
                discount = coupon.kind.equals("PERCENT")
                    ? subtotal * coupon.value / 10000
                    : Math.min(subtotal, coupon.value);
            }
            long tax = (subtotal - discount) * taxRate(sub.customer.region) / 10000;
            long total = subtotal - discount + tax;
            long credit = Math.min(sub.customer.balance, total);
            return new Totals(subtotal, discount, tax, total, credit, total - credit);
        }

        void issue(Subscription sub, String kind, List<Line> items) {
            Totals totals = invoiceTotals(sub, items);
            Invoice inv = new Invoice(invoices.size() + 1, sub, day, kind, items, totals);
            if (couponUsable(sub, inv.subtotal) && sub.remaining != null)
                --sub.remaining;
            invoices.add(inv);
            sub.invoices.add(inv);
            sub.customer.invoices.add(inv);
            balanceChange(sub.customer, -inv.credit, "applied invoice " + inv.number);

            String result;
            if (inv.due == 0) {
                result = "PAID";
            } else if (sub.state.equals("UNPAID")) {
                result = "OPEN";
            } else {
                inv.attempts = 1;
                if (sub.customer.method.equals("OK")) {
                    inv.paid = inv.due;
                    inv.outstanding = 0;
                    result = "PAID";
                } else {
                    result = "FAILED";
                }
            }
            notice("invoice", inv.number, "sub", sub.number, kind,
                   "total", money(inv.total), "credit", money(inv.credit),
                   "due", money(inv.due), result);
            if (result.equals("FAILED")) {
                if (sub.state.equals("ACTIVE")) changeState(sub, "PAST_DUE");
                if (sub.state.equals("PAST_DUE"))
                    Collections.addAll(inv.retries, day + 3, day + 5, day + 7);
            }
        }

        void paymentComplete(Invoice inv) {
            inv.retries.clear();
            Subscription sub = inv.subscription;
            if (sub.state.equals("PAST_DUE") || sub.state.equals("UNPAID")) {
                boolean paid = true;
                for (Invoice other : sub.invoices)
                    if (other.outstanding != 0) paid = false;
                if (paid) {
                    sub.cancelOn = null;
                    changeState(sub, "ACTIVE");
                }
            }
        }

        void cancelSubscription(Subscription sub) {
            changeState(sub, "CANCELED");
            sub.canceledOn = day;
            sub.pending = null;
            sub.cancelEnd = false;
            sub.cancelOn = null;
            List<Line> items = usageItems(sub, true);
            if (!items.isEmpty()) issue(sub, "final", items);
        }

        void retry(Invoice inv) {
            inv.retries.remove(0);
            ++inv.attempts;
            int retryNumber = inv.attempts - 1;
            if (inv.customer.method.equals("OK")) {
                inv.paid += inv.outstanding;
                inv.outstanding = 0;
                notice("retry", retryNumber, "invoice", inv.number, "PAID");
                paymentComplete(inv);
            } else {
                notice("retry", retryNumber, "invoice", inv.number, "FAILED");
                if (inv.retries.isEmpty()) {
                    changeState(inv.subscription, "UNPAID");
                    inv.subscription.cancelOn = day + 14;
                }
            }
        }

        void advanceSubscription(Subscription sub) {
            if (sub.state.equals("PAUSED") || sub.state.equals("CANCELED")) return;
            for (Invoice inv : sub.invoices)
                if (!inv.retries.isEmpty() && inv.retries.get(0) == day) retry(inv);

            if (sub.state.equals("UNPAID") && sub.cancelOn != null && sub.cancelOn == day)
                cancelSubscription(sub);

            if (sub.state.equals("TRIALING") && sub.trialEnd != null && sub.trialEnd == day) {
                if (sub.cancelEnd) {
                    cancelSubscription(sub);
                } else {
                    changeState(sub, "ACTIVE");
                    sub.start = day;
                    sub.end = day + sub.plan.length;
                    issue(sub, "first", openingItems(sub, day));
                }
            }

            if ((sub.state.equals("ACTIVE") || sub.state.equals("PAST_DUE") ||
                 sub.state.equals("UNPAID")) && sub.end != null && sub.end == day) {
                if (sub.cancelEnd) {
                    cancelSubscription(sub);
                } else {
                    List<Line> items = usageItems(sub, true);
                    if (sub.pending != null) {
                        Plan next = sub.pending.plan();
                        int seats = sub.pending.seats();
                        notice("sub", sub.number, sub.plan.name, "seats", sub.seats,
                               "->", next.name, "seats", seats);
                        sub.plan = next;
                        sub.seats = seats;
                        sub.pending = null;
                    }
                    sub.start = day;
                    sub.end = day + sub.plan.length;
                    items.add(periodItem(sub.plan, sub.seats, day));
                    issue(sub, "renewal", items);
                }
            }
        }

        void cmdPlan(String[] a) {
            String name = a[0];
            if (plans.containsKey(name)) fail("duplicate plan " + name);
            Plan plan = new Plan(name, cents(a[1]), a[2]);
            for (int i = 3; i < a.length;) {
                switch (a[i]) {
                    case "TRIAL" -> {
                        plan.trial = Integer.parseInt(a[i + 1]);
                        i += 2;
                    }
                    case "SETUP" -> {
                        plan.setup = cents(a[i + 1]);
                        i += 2;
                    }
                    case "PERSEAT" -> {
                        plan.perSeat = true;
                        ++i;
                    }
                    default -> {
                        plan.mode = a[i];
                        ++i;
                    }
                }
            }
            plans.put(name, plan);
            List<Object> parts = new ArrayList<>(List.of("PLAN", name, a[2], a[1]));
            if (plan.trial != 0) Collections.addAll(parts, "trial", plan.trial);
            if (plan.setup != 0) Collections.addAll(parts, "setup", money(plan.setup));
            if (plan.perSeat) parts.add("perseat");
            if (plan.mode != null) parts.add(plan.mode.toLowerCase(java.util.Locale.ROOT));
            emit(parts.toArray());
        }

        void cmdTier(String[] a) {
            Plan plan = plan(a[0]);
            if (plan.mode == null) fail("not metered " + plan.name);
            Long upper = a[1].equals("INF") ? null : Long.parseLong(a[1]);
            if (!plan.tiers.isEmpty()) {
                Long previous = plan.tiers.getLast().upper();
                if (previous == null || (upper != null && upper <= previous))
                    fail("tier order " + plan.name);
            }
            plan.tiers.add(new Tier(upper, cents(a[2]), cents(a[3])));
            emit("TIER", plan.name, plan.tiers.size(), "upto", a[1],
                 "unit", a[2], "flat", a[3]);
        }

        void cmdTax(String[] a) {
            int rate = Integer.parseInt(a[1]);
            taxes.put(a[0], rate);
            emit("TAX", a[0], percent(rate));
        }

        void cmdCustomer(String[] a) {
            if (customers.containsKey(a[0])) fail("duplicate customer " + a[0]);
            customers.put(a[0], new Customer(a[0], a[1]));
            emit("CUSTOMER", a[0], "region", a[1]);
        }

        void cmdCoupon(String[] a) {
            String name = a[0];
            if (coupons.containsKey(name)) fail("duplicate coupon " + name);
            String application = a[3];
            Integer applications = application.equals("ONCE") ? 1 : null;
            int index = 4;
            if (application.equals("REPEATING")) {
                applications = Integer.parseInt(a[index]);
                ++index;
            }
            Integer maximum = index < a.length ? Integer.parseInt(a[index + 1]) : null;
            long value = a[1].equals("PERCENT") ? Long.parseLong(a[2]) : cents(a[2]);
            Coupon coupon = new Coupon(name, a[1], value, applications, maximum);
            coupons.put(name, coupon);
            List<Object> parts = new ArrayList<>();
            Collections.addAll(parts, "COUPON", name,
                               coupon.kind.toLowerCase(java.util.Locale.ROOT),
                               coupon.kind.equals("PERCENT") ? percent(value) : money(value),
                               application.toLowerCase(java.util.Locale.ROOT));
            if (application.equals("REPEATING")) parts.add(applications);
            if (maximum != null) Collections.addAll(parts, "max", maximum);
            emit(parts.toArray());
        }

        void cmdPaymethod(String[] a) {
            Customer customer = customer(a[0]);
            customer.method = a[1];
            emit("PAYMETHOD", a[0], a[1]);
        }

        void cmdCredit(String[] a) {
            Customer customer = customer(a[0]);
            long value = cents(a[1]);
            if (value == 0) fail("invalid amount");
            balanceChange(customer, value, "grant");
            emit("CREDIT", a[0], "amount", a[1], "balance", money(customer.balance));
        }

        void cmdDay(String[] a) {
            int target = Integer.parseInt(a[0]);
            if (target <= day) fail("invalid day " + a[0]);
            emit("DAY", target);
            for (int today = day + 1; today <= target; ++today) {
                day = today;
                for (Subscription sub : subscriptions) advanceSubscription(sub);
            }
        }

        void cmdSubscribe(String[] a) {
            Customer customer = customer(a[0]);
            Plan plan = plan(a[1]);
            int seats = 1;
            boolean hasSeats = false;
            String couponName = null;
            for (int i = 2; i < a.length; i += 2) {
                if (a[i].equals("SEATS")) {
                    seats = Integer.parseInt(a[i + 1]);
                    hasSeats = true;
                } else {
                    couponName = a[i + 1];
                }
            }
            if (hasSeats && !plan.perSeat) fail("not per-seat " + plan.name);
            if (seats == 0) fail("invalid seats");
            Coupon coupon = couponName == null ? null : redeemableCoupon(couponName);
            Subscription sub = new Subscription(subscriptions.size() + 1,
                                                customer, plan, seats, coupon);
            if (coupon != null) ++coupon.redemptions;
            subscriptions.add(sub);
            customer.subscriptions.add(sub);
            List<Object> parts = new ArrayList<>();
            Collections.addAll(parts, "SUBSCRIBE", "sub", sub.number, customer.name,
                               plan.name, "seats", seats);
            if (coupon != null) Collections.addAll(parts, "coupon", coupon.name);
            emit(parts.toArray());
            if (plan.trial > 0) {
                sub.trialEnd = day + plan.trial;
                changeState(sub, "TRIALING");
            } else {
                changeState(sub, "ACTIVE");
                sub.start = day;
                sub.end = day + plan.length;
                issue(sub, "first", openingItems(sub, day));
            }
        }

        void cmdChange(String[] a) {
            Subscription sub = subscription(a[0], "ACTIVE", "TRIALING");
            Plan plan;
            int seats;
            if (a[1].equals("PLAN")) {
                plan = plan(a[2]);
                seats = plan.perSeat ? sub.seats : 1;
            } else {
                plan = sub.plan;
                if (!plan.perSeat) fail("not per-seat " + plan.name);
                seats = Integer.parseInt(a[2]);
                if (seats == 0) fail("invalid seats");
            }
            if (plan == sub.plan && seats == sub.seats) fail("no change " + a[0]);
            Plan oldPlan = sub.plan;
            int oldSeats = sub.seats;
            List<Object> head = new ArrayList<>();
            Collections.addAll(head, "CHANGE", "sub", sub.number, oldPlan.name, "seats",
                               oldSeats, "->", plan.name, "seats", seats);
            sub.pending = null;
            boolean upgrade = plan.fee(seats) * oldPlan.length >
                              oldPlan.fee(oldSeats) * plan.length;
            if (sub.state.equals("TRIALING")) {
                sub.plan = plan;
                sub.seats = seats;
                head.add("now");
                emit(head.toArray());
            } else if (upgrade) {
                head.add("now");
                emit(head.toArray());
                int days = sub.end - day;
                List<Line> items = usageItems(sub, true);
                items.add(new Line("unused " + oldPlan.name + " seats " + oldSeats +
                                   " " + days + " days",
                                   -(oldPlan.fee(oldSeats) * days / oldPlan.length)));
                items.add(new Line("remaining " + plan.name + " seats " + seats +
                                   " " + days + " days",
                                   plan.fee(seats) * days / plan.length));
                sub.plan = plan;
                sub.seats = seats;
                issue(sub, "upgrade", items);
            } else {
                sub.pending = new Pending(plan, seats);
                Collections.addAll(head, "at", sub.end);
                emit(head.toArray());
            }
        }

        void cmdPause(String[] a) {
            Subscription sub = subscription(a[0], "ACTIVE");
            emit("PAUSE", "sub", sub.number);
            sub.pauseStart = day;
            changeState(sub, "PAUSED");
        }

        void cmdResume(String[] a) {
            Subscription sub = subscription(a[0], "PAUSED");
            int elapsed = day - sub.pauseStart;
            sub.end += elapsed;
            sub.pauseStart = null;
            emit("RESUME", "sub", sub.number, "shift", elapsed, "period", sub.period());
            changeState(sub, "ACTIVE");
        }

        void cmdCancel(String[] a) {
            Subscription sub = subscription(a[0]);
            if (a[1].equals("END")) {
                if (!sub.state.equals("ACTIVE") && !sub.state.equals("TRIALING"))
                    fail("invalid state " + a[0] + " " + sub.state);
                if (sub.cancelEnd) fail("already canceling " + a[0]);
                sub.cancelEnd = true;
                int until = sub.state.equals("TRIALING") ? sub.trialEnd : sub.end;
                emit("CANCEL", "sub", sub.number, "end", until);
            } else {
                if (sub.state.equals("CANCELED"))
                    fail("invalid state " + a[0] + " " + sub.state);
                long refund = 0;
                if (sub.state.equals("ACTIVE") || sub.state.equals("PAUSED")) {
                    int start = sub.state.equals("ACTIVE") ? day : sub.pauseStart;
                    refund = sub.fee() * (sub.end - start) / sub.plan.length;
                }
                balanceChange(sub.customer, refund, "cancel sub " + sub.number);
                emit("CANCEL", "sub", sub.number, "now", "credit", money(refund));
                cancelSubscription(sub);
            }
        }

        void cmdUsage(String[] a) {
            Subscription sub = subscription(a[0], "ACTIVE", "PAST_DUE");
            if (sub.plan.mode == null) fail("not metered " + sub.plan.name);
            long quantity = Long.parseLong(a[1]);
            if (quantity == 0) fail("invalid units");
            sub.usage += quantity;
            emit("USAGE", "sub", sub.number, "units", quantity, "total", sub.usage);
        }

        void cmdApply(String[] a) {
            Subscription sub = subscription(a[0]);
            if (sub.state.equals("CANCELED"))
                fail("invalid state " + a[0] + " " + sub.state);
            Coupon coupon = redeemableCoupon(a[1]);
            ++coupon.redemptions;
            sub.coupon = coupon;
            sub.remaining = coupon.applications;
            emit("APPLY", "sub", sub.number, "coupon", coupon.name);
        }

        void cmdPay(String[] a) {
            Invoice inv = invoice(a[0]);
            if (inv.outstanding == 0) fail("already paid " + a[0]);
            emit("PAY", "invoice", inv.number, "amount", money(inv.outstanding));
            inv.paid += inv.outstanding;
            inv.outstanding = 0;
            paymentComplete(inv);
        }

        void cmdRefund(String[] a) {
            Invoice inv = invoice(a[0]);
            long value = cents(a[1]);
            if (value == 0) fail("invalid amount");
            long maximum = inv.total - inv.refunded;
            if (value > maximum)
                fail("refund exceeds " + a[0] + " " + money(maximum));
            long applied = Math.min(value, inv.outstanding);
            inv.refunded += value;
            inv.outstanding -= applied;
            balanceChange(inv.customer, value - applied, "refund invoice " + inv.number);
            emit("REFUND", "invoice", inv.number, "amount", a[1],
                 "applied", money(applied), "balance", money(inv.customer.balance));
            if (applied > 0 && inv.outstanding == 0) paymentComplete(inv);
        }

        void emitItems(List<Line> items) {
            for (Line line : items) indented(line.description(), money(line.amount()));
        }

        void emitTotals(Totals totals) {
            indented("subtotal", money(totals.subtotal()), "discount", money(totals.discount()),
                     "tax", money(totals.tax()), "total", money(totals.total()));
        }

        void cmdInvoice(String[] a) {
            Invoice inv = invoice(a[0]);
            emit("INVOICE", inv.number, "sub", inv.subscription.number,
                 inv.customer.name, "day", inv.day, inv.kind, inv.state());
            emitItems(inv.items);
            emitTotals(new Totals(inv.subtotal, inv.discount, inv.tax,
                                  inv.total, inv.credit, inv.due));
            indented("credit", money(inv.credit), "due", money(inv.due),
                     "paid", money(inv.paid), "refunded", money(inv.refunded),
                     "outstanding", money(inv.outstanding));
        }

        void cmdSub(String[] a) {
            Subscription sub = subscription(a[0]);
            emit("SUB", sub.number, sub.customer.name, sub.plan.name,
                 "seats", sub.seats, sub.state);
            if (sub.state.equals("TRIALING"))
                indented("trial until", sub.trialEnd);
            if (List.of("ACTIVE", "PAST_DUE", "UNPAID", "PAUSED").contains(sub.state))
                indented("period", sub.period());
            if (sub.state.equals("PAUSED")) indented("paused since", sub.pauseStart);
            if (sub.pending != null)
                indented("pending", sub.pending.plan().name, "seats", sub.pending.seats());
            if (sub.cancelEnd) indented("cancel at end");
            if (sub.cancelOn != null) indented("cancel on", sub.cancelOn);
            if (sub.state.equals("CANCELED")) indented("canceled on", sub.canceledOn);
            if (sub.coupon != null) {
                if (sub.remaining == null)
                    indented("coupon", sub.coupon.name, "forever");
                else if (sub.remaining > 0)
                    indented("coupon", sub.coupon.name, "left", sub.remaining);
            }
            if (sub.plan.mode != null && !sub.state.equals("CANCELED"))
                indented("usage", sub.usage);
            List<Object> open = new ArrayList<>();
            open.add("open");
            for (Invoice inv : sub.invoices) if (inv.outstanding > 0) open.add(inv.number);
            if (open.size() > 1) indented(open.toArray());
        }

        void cmdPreview(String[] a) {
            Subscription sub = subscription(a[0], "TRIALING", "ACTIVE", "PAST_DUE", "UNPAID");
            int when = sub.state.equals("TRIALING") ? sub.trialEnd : sub.end;
            String kind;
            List<Line> items;
            if (sub.cancelEnd) {
                kind = "final";
                items = sub.state.equals("TRIALING") ? new ArrayList<>() : usageItems(sub, false);
            } else if (sub.state.equals("TRIALING")) {
                kind = "first";
                items = openingItems(sub, when);
            } else {
                kind = "renewal";
                Plan next = sub.pending == null ? sub.plan : sub.pending.plan();
                int seats = sub.pending == null ? sub.seats : sub.pending.seats();
                items = usageItems(sub, false);
                items.add(periodItem(next, seats, when));
            }
            emit("PREVIEW", "sub", sub.number, "day", when, kind);
            if (items.isEmpty()) {
                indented("(none)");
                return;
            }
            emitItems(items);
            Totals totals = invoiceTotals(sub, items);
            emitTotals(totals);
            indented("credit", money(totals.credit()), "due", money(totals.due()));
        }

        void cmdStatement(String[] a) {
            Customer customer = customer(a[0]);
            emit("STATEMENT", customer.name, "region", customer.region,
                 "tax", percent(taxRate(customer.region)), "method", customer.method,
                 "balance", money(customer.balance));
            for (Subscription sub : customer.subscriptions)
                indented("sub", sub.number, sub.plan.name, sub.state);
            long outstanding = 0;
            for (Invoice inv : customer.invoices) {
                indented("invoice", inv.number, "day", inv.day, "sub",
                         inv.subscription.number, inv.kind, "total", money(inv.total),
                         "outstanding", money(inv.outstanding));
                outstanding += inv.outstanding;
            }
            indented("outstanding", money(outstanding));
        }

        void cmdLedger(String[] a) {
            Customer customer = customer(a[0]);
            emit("LEDGER", customer.name, "balance", money(customer.balance));
            for (BalanceEntry entry : customer.log)
                indented("day", entry.day(), entry.description(), signedMoney(entry.change()),
                         "balance", money(entry.balance()));
            if (customer.log.isEmpty()) indented("(none)");
        }

        void cmdMrr() {
            Map<String, long[]> byPlan = new TreeMap<>();
            for (Subscription sub : subscriptions) {
                if (!sub.state.equals("ACTIVE") && !sub.state.equals("PAST_DUE")) continue;
                long fee = sub.fee();
                long monthly = switch (sub.plan.cycle) {
                    case "MONTHLY" -> fee;
                    case "YEARLY" -> fee / 12;
                    default -> fee * 30 / 7;
                };
                long[] entry = byPlan.computeIfAbsent(sub.plan.name, key -> new long[2]);
                ++entry[0];
                entry[1] += monthly;
            }
            emit("MRR");
            long count = 0, monthly = 0;
            for (Map.Entry<String, long[]> entry : byPlan.entrySet()) {
                long[] row = entry.getValue();
                indented(entry.getKey(), "subs", row[0], "mrr", money(row[1]));
                count += row[0];
                monthly += row[1];
            }
            indented("total subs", count, "mrr", money(monthly));
        }

        static Object[] agingParts(long[] amounts) {
            return new Object[]{
                "0-30", money(amounts[0]), "31-60", money(amounts[1]),
                "61+", money(amounts[2]), "sum", money(amounts[0] + amounts[1] + amounts[2])
            };
        }

        void cmdAging() {
            Map<String, long[]> byCustomer = new TreeMap<>();
            long[] totals = new long[3];
            for (Invoice inv : invoices) {
                if (inv.outstanding == 0) continue;
                int age = day - inv.day;
                int bucket = age <= 30 ? 0 : age <= 60 ? 1 : 2;
                long[] amounts = byCustomer.computeIfAbsent(inv.customer.name, key -> new long[3]);
                amounts[bucket] += inv.outstanding;
                totals[bucket] += inv.outstanding;
            }
            emit("AGING", "day", day);
            for (Map.Entry<String, long[]> entry : byCustomer.entrySet()) {
                List<Object> parts = new ArrayList<>();
                parts.add(entry.getKey());
                parts.addAll(Arrays.asList(agingParts(entry.getValue())));
                indented(parts.toArray());
            }
            List<Object> parts = new ArrayList<>();
            parts.add("total");
            parts.addAll(Arrays.asList(agingParts(totals)));
            indented(parts.toArray());
        }

        void cmdDunning() {
            emit("DUNNING");
            boolean any = false;
            for (Invoice inv : invoices) {
                if (inv.retries.isEmpty()) continue;
                any = true;
                indented("invoice", inv.number, "sub", inv.subscription.number,
                         inv.customer.name, "outstanding", money(inv.outstanding),
                         "attempts", inv.attempts, "next", inv.retries.get(0));
            }
            if (!any) indented("(none)");
        }

        void cmdRevenue() {
            long subtotal = 0, discount = 0, tax = 0, total = 0,
                 credit = 0, paid = 0, refunded = 0, outstanding = 0, balances = 0;
            for (Invoice inv : invoices) {
                subtotal += inv.subtotal;
                discount += inv.discount;
                tax += inv.tax;
                total += inv.total;
                credit += inv.credit;
                paid += inv.paid;
                refunded += inv.refunded;
                outstanding += inv.outstanding;
            }
            for (Customer customer : customers.values()) balances += customer.balance;
            emit("REVENUE");
            indented("invoices", invoices.size(), "subtotal", money(subtotal),
                     "discount", money(discount), "tax", money(tax), "total", money(total));
            indented("credit", money(credit), "paid", money(paid), "refunded", money(refunded),
                     "outstanding", money(outstanding), "balances", money(balances));
        }

        void cmdEvents(String[] a) {
            Integer selected = a.length == 0 ? null : subscription(a[0]).number;
            if (selected == null) emit("EVENTS");
            else emit("EVENTS", "sub", selected);
            boolean any = false;
            for (StateEvent event : events) {
                if (selected != null && event.number() != selected) continue;
                any = true;
                indented("day", event.day(), "sub", event.number(),
                         event.oldState(), "->", event.newState());
            }
            if (!any) indented("(none)");
        }

        void execute(String command, String[] args) {
            try {
                switch (command) {
                    case "PLAN" -> cmdPlan(args);
                    case "TIER" -> cmdTier(args);
                    case "TAX" -> cmdTax(args);
                    case "CUSTOMER" -> cmdCustomer(args);
                    case "COUPON" -> cmdCoupon(args);
                    case "PAYMETHOD" -> cmdPaymethod(args);
                    case "CREDIT" -> cmdCredit(args);
                    case "DAY" -> cmdDay(args);
                    case "SUBSCRIBE" -> cmdSubscribe(args);
                    case "CHANGE" -> cmdChange(args);
                    case "PAUSE" -> cmdPause(args);
                    case "RESUME" -> cmdResume(args);
                    case "CANCEL" -> cmdCancel(args);
                    case "USAGE" -> cmdUsage(args);
                    case "APPLY" -> cmdApply(args);
                    case "PAY" -> cmdPay(args);
                    case "REFUND" -> cmdRefund(args);
                    case "INVOICE" -> cmdInvoice(args);
                    case "SUB" -> cmdSub(args);
                    case "PREVIEW" -> cmdPreview(args);
                    case "STATEMENT" -> cmdStatement(args);
                    case "LEDGER" -> cmdLedger(args);
                    case "MRR" -> cmdMrr();
                    case "AGING" -> cmdAging();
                    case "DUNNING" -> cmdDunning();
                    case "REVENUE" -> cmdRevenue();
                    case "EVENTS" -> cmdEvents(args);
                }
            } catch (CommandError error) {
                emit("ERROR", error.getMessage());
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(reader.readLine());
        Billing billing = new Billing();
        for (int i = 0; i < count; ++i) {
            String[] fields = reader.readLine().split(" ");
            billing.execute(fields[0], Arrays.copyOfRange(fields, 1, fields.length));
        }
        if (!billing.output.isEmpty())
            System.out.println(String.join("\n", billing.output));
    }
}
