using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) { }
}

readonly record struct Tier(long? Upper, long Unit, long Flat);
readonly record struct LineItem(string Description, long Amount);
readonly record struct Totals(long Subtotal, long Discount, long Tax,
                              long Total, long Credit, long Due);
readonly record struct BalanceEntry(int Day, string Description, long Change, long Balance);
readonly record struct StateEvent(int Day, int Number, string Old, string New);

sealed class Plan
{
    public string Name { get; }
    public long Price { get; }
    public string Cycle { get; }
    public int Length { get; }
    public int Trial { get; set; }
    public long Setup { get; set; }
    public bool PerSeat { get; set; }
    public string? Mode { get; set; }
    public List<Tier> Tiers { get; } = new();

    public Plan(string name, long price, string cycle)
    {
        Name = name;
        Price = price;
        Cycle = cycle;
        Length = cycle switch
        {
            "WEEKLY" => 7,
            "MONTHLY" => 30,
            _ => 360
        };
    }

    public long Fee(int seats) => PerSeat ? Price * seats : Price;

    public long UsageCharge(long units)
    {
        long total = 0;
        long lower = 0;
        for (int index = 0; index < Tiers.Count; ++index)
        {
            var tier = Tiers[index];
            bool last = index == Tiers.Count - 1;
            if (Mode == "VOLUME")
            {
                if (last || tier.Upper is null || units <= tier.Upper.Value)
                    return units * tier.Unit + tier.Flat;
            }
            else
            {
                if (units <= lower) break;
                long end = last || tier.Upper is null ? units : Math.Min(units, tier.Upper.Value);
                total += (end - lower) * tier.Unit + tier.Flat;
                if (last || tier.Upper is null) break;
                lower = tier.Upper.Value;
            }
        }
        return total;
    }
}

sealed class Customer
{
    public string Name { get; }
    public string Region { get; }
    public string Method { get; set; } = "OK";
    public long Balance { get; set; }
    public List<BalanceEntry> Log { get; } = new();
    public List<Subscription> Subscriptions { get; } = new();
    public List<Invoice> Invoices { get; } = new();

    public Customer(string name, string region)
    {
        Name = name;
        Region = region;
    }
}

sealed class Coupon
{
    public string Name { get; }
    public string Kind { get; }
    public long Value { get; }
    public int? Applications { get; }
    public int? Maximum { get; }
    public int Redemptions { get; set; }

    public Coupon(string name, string kind, long value, int? applications, int? maximum)
    {
        Name = name;
        Kind = kind;
        Value = value;
        Applications = applications;
        Maximum = maximum;
    }
}

sealed class Subscription
{
    public int Number { get; }
    public Customer Customer { get; }
    public Plan Plan { get; set; }
    public int Seats { get; set; }
    public string State { get; set; } = "NONE";
    public int? Start { get; set; }
    public int? End { get; set; }
    public int? TrialEnd { get; set; }
    public int? PauseStart { get; set; }
    public (Plan Plan, int Seats)? Pending { get; set; }
    public bool CancelEnd { get; set; }
    public int? CancelOn { get; set; }
    public int? CanceledOn { get; set; }
    public Coupon? Coupon { get; set; }
    public int? Remaining { get; set; }
    public long Usage { get; set; }
    public List<Invoice> Invoices { get; } = new();

    public Subscription(int number, Customer customer, Plan plan, int seats, Coupon? coupon)
    {
        Number = number;
        Customer = customer;
        Plan = plan;
        Seats = seats;
        Coupon = coupon;
        Remaining = coupon?.Applications;
    }

    public long Fee() => Plan.Fee(Seats);
    public string Period() => $"{Start}-{End}";
}

sealed class Invoice
{
    public int Number { get; }
    public Subscription Subscription { get; }
    public Customer Customer => Subscription.Customer;
    public int Day { get; }
    public string Kind { get; }
    public List<LineItem> Items { get; }
    public long Subtotal { get; }
    public long Discount { get; }
    public long Tax { get; }
    public long Total { get; }
    public long Credit { get; }
    public long Due { get; }
    public long Paid { get; set; }
    public long Refunded { get; set; }
    public long Outstanding { get; set; }
    public int Attempts { get; set; }
    public List<int> Retries { get; } = new();

    public Invoice(int number, Subscription subscription, int day, string kind,
                   List<LineItem> items, Totals totals)
    {
        Number = number;
        Subscription = subscription;
        Day = day;
        Kind = kind;
        Items = items;
        Subtotal = totals.Subtotal;
        Discount = totals.Discount;
        Tax = totals.Tax;
        Total = totals.Total;
        Credit = totals.Credit;
        Due = totals.Due;
        Outstanding = totals.Due;
    }

    public string State => Outstanding == 0 ? "PAID" : "OPEN";
}

sealed class BillingService
{
    private int day = 1;
    private readonly Dictionary<string, Plan> plans = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> taxes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Customer> customers = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Coupon> coupons = new(StringComparer.Ordinal);
    private readonly List<Subscription> subscriptions = new();
    private readonly List<Invoice> invoices = new();
    private readonly List<StateEvent> events = new();
    private readonly List<string> output = new();

    private static int Integer(string value) => int.Parse(value, CultureInfo.InvariantCulture);

    private static long Cents(string amount)
    {
        var parts = amount.Split('.');
        return long.Parse(parts[0], CultureInfo.InvariantCulture) * 100
             + long.Parse(parts[1], CultureInfo.InvariantCulture);
    }

    private static string Money(long amount)
    {
        long absolute = Math.Abs(amount);
        return (amount < 0 ? "-" : "") + (absolute / 100).ToString(CultureInfo.InvariantCulture)
             + "." + (absolute % 100).ToString("D2", CultureInfo.InvariantCulture);
    }

    private static string SignedMoney(long amount) => (amount > 0 ? "+" : "") + Money(amount);
    private static string Percent(long basisPoints) => Money(basisPoints) + "%";

    private static string Join(IEnumerable<object?> parts) =>
        string.Join(" ", parts.Select(p => Convert.ToString(p, CultureInfo.InvariantCulture) ?? ""));

    private void Emit(params object?[] parts) => output.Add(Join(parts));
    private void Indent(params object?[] parts) => output.Add("  " + Join(parts));

    private void Notice(params object?[] parts)
    {
        var all = new object?[parts.Length + 2];
        all[0] = "day";
        all[1] = day;
        Array.Copy(parts, 0, all, 2, parts.Length);
        Indent(all);
    }

    private static void Fail(string reason) => throw new CommandError(reason);

    private Plan RequirePlan(string name)
    {
        if (!plans.TryGetValue(name, out var plan)) Fail("unknown plan " + name);
        return plan!;
    }

    private Customer RequireCustomer(string name)
    {
        if (!customers.TryGetValue(name, out var customer)) Fail("unknown customer " + name);
        return customer!;
    }

    private Coupon RedeemableCoupon(string name)
    {
        if (!coupons.TryGetValue(name, out var coupon)) Fail("unknown coupon " + name);
        if (coupon!.Maximum.HasValue && coupon.Redemptions == coupon.Maximum.Value)
            Fail("coupon exhausted " + name);
        return coupon;
    }

    private Subscription RequireSubscription(string text, params string[] allowed)
    {
        int number = Integer(text);
        if (number < 1 || number > subscriptions.Count) Fail("unknown sub " + text);
        Subscription subscription = subscriptions[number - 1];
        if (allowed.Length > 0 && !allowed.Contains(subscription.State))
            Fail("invalid state " + text + " " + subscription.State);
        return subscription;
    }

    private Invoice RequireInvoice(string text)
    {
        int number = Integer(text);
        if (number < 1 || number > invoices.Count) Fail("unknown invoice " + text);
        return invoices[number - 1];
    }

    private int TaxRate(string region) => taxes.GetValueOrDefault(region);

    private void BalanceChange(Customer customer, long amount, string description)
    {
        if (amount == 0) return;
        customer.Balance += amount;
        customer.Log.Add(new BalanceEntry(day, description, amount, customer.Balance));
    }

    private void ChangeState(Subscription subscription, string state)
    {
        string previous = subscription.State;
        if (previous == "PAST_DUE")
            foreach (var invoice in subscription.Invoices) invoice.Retries.Clear();
        subscription.State = state;
        Notice("sub", subscription.Number, previous, "->", state);
        events.Add(new StateEvent(day, subscription.Number, previous, state));
    }

    private static LineItem PeriodItem(Plan plan, int seats, int start) =>
        new($"charge {plan.Name} seats {seats} {start}-{start + plan.Length}", plan.Fee(seats));

    private static List<LineItem> OpeningItems(Subscription subscription, int start)
    {
        var result = new List<LineItem> { PeriodItem(subscription.Plan, subscription.Seats, start) };
        if (subscription.Plan.Setup != 0)
            result.Add(new LineItem("setup " + subscription.Plan.Name, subscription.Plan.Setup));
        return result;
    }

    private static List<LineItem> UsageItems(Subscription subscription, bool close = false)
    {
        if (subscription.Plan.Mode is null || subscription.Usage == 0)
            return new List<LineItem>();
        long units = subscription.Usage;
        var result = new List<LineItem> {
            new($"usage {subscription.Plan.Name} {units} units",
                subscription.Plan.UsageCharge(units))
        };
        if (close) subscription.Usage = 0;
        return result;
    }

    private static bool CouponUsable(Subscription subscription, long subtotal) =>
        subtotal > 0 && subscription.Coupon is not null &&
        (subscription.Remaining is null || subscription.Remaining > 0);

    private Totals InvoiceTotals(Subscription subscription, List<LineItem> items)
    {
        long subtotal = items.Sum(item => item.Amount);
        long discount = 0;
        if (CouponUsable(subscription, subtotal))
        {
            Coupon coupon = subscription.Coupon!;
            discount = coupon.Kind == "PERCENT"
                ? subtotal * coupon.Value / 10000
                : Math.Min(subtotal, coupon.Value);
        }
        long tax = (subtotal - discount) * TaxRate(subscription.Customer.Region) / 10000;
        long total = subtotal - discount + tax;
        long credit = Math.Min(subscription.Customer.Balance, total);
        return new Totals(subtotal, discount, tax, total, credit, total - credit);
    }

    private void Issue(Subscription subscription, string kind, List<LineItem> items)
    {
        Totals totals = InvoiceTotals(subscription, items);
        var invoice = new Invoice(invoices.Count + 1, subscription, day, kind, items, totals);
        if (CouponUsable(subscription, invoice.Subtotal) && subscription.Remaining.HasValue)
            subscription.Remaining = subscription.Remaining.Value - 1;
        invoices.Add(invoice);
        subscription.Invoices.Add(invoice);
        subscription.Customer.Invoices.Add(invoice);
        BalanceChange(subscription.Customer, -invoice.Credit, "applied invoice " + invoice.Number);

        string result;
        if (invoice.Due == 0)
        {
            result = "PAID";
        }
        else if (subscription.State == "UNPAID")
        {
            result = "OPEN";
        }
        else
        {
            invoice.Attempts = 1;
            if (subscription.Customer.Method == "OK")
            {
                invoice.Paid = invoice.Due;
                invoice.Outstanding = 0;
                result = "PAID";
            }
            else
            {
                result = "FAILED";
            }
        }

        Notice("invoice", invoice.Number, "sub", subscription.Number, kind,
               "total", Money(invoice.Total), "credit", Money(invoice.Credit),
               "due", Money(invoice.Due), result);
        if (result == "FAILED")
        {
            if (subscription.State == "ACTIVE") ChangeState(subscription, "PAST_DUE");
            if (subscription.State == "PAST_DUE")
                invoice.Retries.AddRange(new[] { day + 3, day + 5, day + 7 });
        }
    }

    private void PaymentComplete(Invoice invoice)
    {
        invoice.Retries.Clear();
        Subscription subscription = invoice.Subscription;
        if ((subscription.State == "PAST_DUE" || subscription.State == "UNPAID") &&
            subscription.Invoices.All(entry => entry.Outstanding == 0))
        {
            subscription.CancelOn = null;
            ChangeState(subscription, "ACTIVE");
        }
    }

    private void CancelSubscription(Subscription subscription)
    {
        ChangeState(subscription, "CANCELED");
        subscription.CanceledOn = day;
        subscription.Pending = null;
        subscription.CancelEnd = false;
        subscription.CancelOn = null;
        var items = UsageItems(subscription, true);
        if (items.Count > 0) Issue(subscription, "final", items);
    }

    private void Retry(Invoice invoice)
    {
        invoice.Retries.RemoveAt(0);
        ++invoice.Attempts;
        int retryNumber = invoice.Attempts - 1;
        if (invoice.Customer.Method == "OK")
        {
            invoice.Paid += invoice.Outstanding;
            invoice.Outstanding = 0;
            Notice("retry", retryNumber, "invoice", invoice.Number, "PAID");
            PaymentComplete(invoice);
        }
        else
        {
            Notice("retry", retryNumber, "invoice", invoice.Number, "FAILED");
            if (invoice.Retries.Count == 0)
            {
                ChangeState(invoice.Subscription, "UNPAID");
                invoice.Subscription.CancelOn = day + 14;
            }
        }
    }

    private void AdvanceSubscription(Subscription subscription)
    {
        if (subscription.State is "PAUSED" or "CANCELED") return;
        foreach (var invoice in subscription.Invoices)
        {
            if (invoice.Retries.Count > 0 && invoice.Retries[0] == day)
                Retry(invoice);
        }
        if (subscription.State == "UNPAID" && subscription.CancelOn == day)
            CancelSubscription(subscription);
        if (subscription.State == "TRIALING" && subscription.TrialEnd == day)
        {
            if (subscription.CancelEnd)
            {
                CancelSubscription(subscription);
            }
            else
            {
                ChangeState(subscription, "ACTIVE");
                subscription.Start = day;
                subscription.End = day + subscription.Plan.Length;
                Issue(subscription, "first", OpeningItems(subscription, day));
            }
        }
        if ((subscription.State is "ACTIVE" or "PAST_DUE" or "UNPAID")
            && subscription.End == day)
        {
            if (subscription.CancelEnd)
            {
                CancelSubscription(subscription);
            }
            else
            {
                var items = UsageItems(subscription, true);
                if (subscription.Pending is { } pending)
                {
                    Notice("sub", subscription.Number, subscription.Plan.Name, "seats",
                           subscription.Seats, "->", pending.Plan.Name, "seats", pending.Seats);
                    subscription.Plan = pending.Plan;
                    subscription.Seats = pending.Seats;
                    subscription.Pending = null;
                }
                subscription.Start = day;
                subscription.End = day + subscription.Plan.Length;
                items.Add(PeriodItem(subscription.Plan, subscription.Seats, day));
                Issue(subscription, "renewal", items);
            }
        }
    }

    private void CmdPlan(string[] args)
    {
        string name = args[0];
        if (plans.ContainsKey(name)) Fail("duplicate plan " + name);
        var plan = new Plan(name, Cents(args[1]), args[2]);
        for (int i = 3; i < args.Length;)
        {
            switch (args[i])
            {
                case "TRIAL":
                    plan.Trial = Integer(args[i + 1]);
                    i += 2;
                    break;
                case "SETUP":
                    plan.Setup = Cents(args[i + 1]);
                    i += 2;
                    break;
                case "PERSEAT":
                    plan.PerSeat = true;
                    ++i;
                    break;
                default:
                    plan.Mode = args[i];
                    ++i;
                    break;
            }
        }
        plans.Add(name, plan);
        var parts = new List<object?> { "PLAN", name, args[2], args[1] };
        if (plan.Trial != 0) parts.AddRange(new object?[] { "trial", plan.Trial });
        if (plan.Setup != 0) parts.AddRange(new object?[] { "setup", Money(plan.Setup) });
        if (plan.PerSeat) parts.Add("perseat");
        if (plan.Mode is not null) parts.Add(plan.Mode.ToLowerInvariant());
        Emit(parts.ToArray());
    }

    private void CmdTier(string[] args)
    {
        Plan plan = RequirePlan(args[0]);
        if (plan.Mode is null) Fail("not metered " + plan.Name);
        long? upper = args[1] == "INF" ? null : long.Parse(args[1], CultureInfo.InvariantCulture);
        if (plan.Tiers.Count > 0)
        {
            long? previous = plan.Tiers[^1].Upper;
            if (previous is null || (upper is not null && upper <= previous))
                Fail("tier order " + plan.Name);
        }
        plan.Tiers.Add(new Tier(upper, Cents(args[2]), Cents(args[3])));
        Emit("TIER", plan.Name, plan.Tiers.Count, "upto", args[1],
             "unit", args[2], "flat", args[3]);
    }

    private void CmdTax(string[] args)
    {
        int rate = Integer(args[1]);
        taxes[args[0]] = rate;
        Emit("TAX", args[0], Percent(rate));
    }

    private void CmdCustomer(string[] args)
    {
        if (customers.ContainsKey(args[0])) Fail("duplicate customer " + args[0]);
        customers[args[0]] = new Customer(args[0], args[1]);
        Emit("CUSTOMER", args[0], "region", args[1]);
    }

    private void CmdCoupon(string[] args)
    {
        string name = args[0];
        if (coupons.ContainsKey(name)) Fail("duplicate coupon " + name);
        string application = args[3];
        int? applications = application == "ONCE" ? 1 : null;
        int index = 4;
        if (application == "REPEATING")
        {
            applications = Integer(args[index]);
            ++index;
        }
        int? maximum = index < args.Length ? Integer(args[index + 1]) : null;
        long value = args[1] == "PERCENT" ? long.Parse(args[2], CultureInfo.InvariantCulture)
                                          : Cents(args[2]);
        var coupon = new Coupon(name, args[1], value, applications, maximum);
        coupons[name] = coupon;
        var parts = new List<object?> {
            "COUPON", name, coupon.Kind.ToLowerInvariant(),
            coupon.Kind == "PERCENT" ? Percent(value) : Money(value),
            application.ToLowerInvariant()
        };
        if (application == "REPEATING") parts.Add(applications);
        if (maximum is not null) parts.AddRange(new object?[] { "max", maximum });
        Emit(parts.ToArray());
    }

    private void CmdPayMethod(string[] args)
    {
        Customer customer = RequireCustomer(args[0]);
        customer.Method = args[1];
        Emit("PAYMETHOD", args[0], args[1]);
    }

    private void CmdCredit(string[] args)
    {
        Customer customer = RequireCustomer(args[0]);
        long value = Cents(args[1]);
        if (value == 0) Fail("invalid amount");
        BalanceChange(customer, value, "grant");
        Emit("CREDIT", args[0], "amount", args[1], "balance", Money(customer.Balance));
    }

    private void CmdDay(string[] args)
    {
        int target = Integer(args[0]);
        if (target <= day) Fail("invalid day " + args[0]);
        Emit("DAY", target);
        for (int current = day + 1; current <= target; ++current)
        {
            day = current;
            foreach (var subscription in subscriptions) AdvanceSubscription(subscription);
        }
    }

    private void CmdSubscribe(string[] args)
    {
        Customer customer = RequireCustomer(args[0]);
        Plan plan = RequirePlan(args[1]);
        int seats = 1;
        bool hasSeats = false;
        string? couponName = null;
        for (int i = 2; i < args.Length; i += 2)
        {
            if (args[i] == "SEATS")
            {
                seats = Integer(args[i + 1]);
                hasSeats = true;
            }
            else
            {
                couponName = args[i + 1];
            }
        }
        if (hasSeats && !plan.PerSeat) Fail("not per-seat " + plan.Name);
        if (seats == 0) Fail("invalid seats");
        Coupon? coupon = couponName is null ? null : RedeemableCoupon(couponName);
        var subscription = new Subscription(subscriptions.Count + 1, customer, plan, seats, coupon);
        if (coupon is not null) ++coupon.Redemptions;
        subscriptions.Add(subscription);
        customer.Subscriptions.Add(subscription);
        var parts = new List<object?> {
            "SUBSCRIBE", "sub", subscription.Number, customer.Name, plan.Name, "seats", seats
        };
        if (coupon is not null) parts.AddRange(new object?[] { "coupon", coupon.Name });
        Emit(parts.ToArray());
        if (plan.Trial != 0)
        {
            subscription.TrialEnd = day + plan.Trial;
            ChangeState(subscription, "TRIALING");
        }
        else
        {
            ChangeState(subscription, "ACTIVE");
            subscription.Start = day;
            subscription.End = day + plan.Length;
            Issue(subscription, "first", OpeningItems(subscription, day));
        }
    }

    private void CmdChange(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0], "ACTIVE", "TRIALING");
        Plan plan;
        int seats;
        if (args[1] == "PLAN")
        {
            plan = RequirePlan(args[2]);
            seats = plan.PerSeat ? subscription.Seats : 1;
        }
        else
        {
            plan = subscription.Plan;
            if (!plan.PerSeat) Fail("not per-seat " + plan.Name);
            seats = Integer(args[2]);
            if (seats == 0) Fail("invalid seats");
        }
        if (ReferenceEquals(plan, subscription.Plan) && seats == subscription.Seats)
            Fail("no change " + args[0]);

        Plan oldPlan = subscription.Plan;
        int oldSeats = subscription.Seats;
        var head = new object?[] {
            "CHANGE", "sub", subscription.Number, oldPlan.Name, "seats", oldSeats,
            "->", plan.Name, "seats", seats
        };
        subscription.Pending = null;
        bool upgrade = plan.Fee(seats) * oldPlan.Length > oldPlan.Fee(oldSeats) * plan.Length;
        if (subscription.State == "TRIALING")
        {
            subscription.Plan = plan;
            subscription.Seats = seats;
            Emit(head.Concat(new object?[] { "now" }).ToArray());
        }
        else if (upgrade)
        {
            Emit(head.Concat(new object?[] { "now" }).ToArray());
            int days = subscription.End!.Value - day;
            var items = UsageItems(subscription, true);
            items.Add(new LineItem($"unused {oldPlan.Name} seats {oldSeats} {days} days",
                                   -(oldPlan.Fee(oldSeats) * days / oldPlan.Length)));
            items.Add(new LineItem($"remaining {plan.Name} seats {seats} {days} days",
                                   plan.Fee(seats) * days / plan.Length));
            subscription.Plan = plan;
            subscription.Seats = seats;
            Issue(subscription, "upgrade", items);
        }
        else
        {
            subscription.Pending = (plan, seats);
            Emit(head.Concat(new object?[] { "at", subscription.End }).ToArray());
        }
    }

    private void CmdPause(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0], "ACTIVE");
        Emit("PAUSE", "sub", subscription.Number);
        subscription.PauseStart = day;
        ChangeState(subscription, "PAUSED");
    }

    private void CmdResume(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0], "PAUSED");
        int elapsed = day - subscription.PauseStart!.Value;
        subscription.End += elapsed;
        subscription.PauseStart = null;
        Emit("RESUME", "sub", subscription.Number, "shift", elapsed,
             "period", subscription.Period());
        ChangeState(subscription, "ACTIVE");
    }

    private void CmdCancel(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0]);
        if (args[1] == "END")
        {
            if (subscription.State is not ("ACTIVE" or "TRIALING"))
                Fail("invalid state " + args[0] + " " + subscription.State);
            if (subscription.CancelEnd) Fail("already canceling " + args[0]);
            subscription.CancelEnd = true;
            int until = (subscription.State == "TRIALING"
                         ? subscription.TrialEnd : subscription.End)!.Value;
            Emit("CANCEL", "sub", subscription.Number, "end", until);
        }
        else
        {
            if (subscription.State == "CANCELED")
                Fail("invalid state " + args[0] + " " + subscription.State);
            long refund = 0;
            if (subscription.State is "ACTIVE" or "PAUSED")
            {
                int start = subscription.State == "ACTIVE"
                    ? day : subscription.PauseStart!.Value;
                refund = subscription.Fee() * (subscription.End!.Value - start)
                         / subscription.Plan.Length;
            }
            BalanceChange(subscription.Customer, refund, "cancel sub " + subscription.Number);
            Emit("CANCEL", "sub", subscription.Number, "now", "credit", Money(refund));
            CancelSubscription(subscription);
        }
    }

    private void CmdUsage(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0], "ACTIVE", "PAST_DUE");
        if (subscription.Plan.Mode is null) Fail("not metered " + subscription.Plan.Name);
        long quantity = long.Parse(args[1], CultureInfo.InvariantCulture);
        if (quantity == 0) Fail("invalid units");
        subscription.Usage += quantity;
        Emit("USAGE", "sub", subscription.Number, "units", quantity,
             "total", subscription.Usage);
    }

    private void CmdApply(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0]);
        if (subscription.State == "CANCELED")
            Fail("invalid state " + args[0] + " " + subscription.State);
        Coupon coupon = RedeemableCoupon(args[1]);
        ++coupon.Redemptions;
        subscription.Coupon = coupon;
        subscription.Remaining = coupon.Applications;
        Emit("APPLY", "sub", subscription.Number, "coupon", coupon.Name);
    }

    private void CmdPay(string[] args)
    {
        Invoice invoice = RequireInvoice(args[0]);
        if (invoice.Outstanding == 0) Fail("already paid " + args[0]);
        Emit("PAY", "invoice", invoice.Number, "amount", Money(invoice.Outstanding));
        invoice.Paid += invoice.Outstanding;
        invoice.Outstanding = 0;
        PaymentComplete(invoice);
    }

    private void CmdRefund(string[] args)
    {
        Invoice invoice = RequireInvoice(args[0]);
        long value = Cents(args[1]);
        if (value == 0) Fail("invalid amount");
        long maximum = invoice.Total - invoice.Refunded;
        if (value > maximum) Fail("refund exceeds " + args[0] + " " + Money(maximum));
        long applied = Math.Min(value, invoice.Outstanding);
        invoice.Refunded += value;
        invoice.Outstanding -= applied;
        BalanceChange(invoice.Customer, value - applied, "refund invoice " + invoice.Number);
        Emit("REFUND", "invoice", invoice.Number, "amount", args[1],
             "applied", Money(applied), "balance", Money(invoice.Customer.Balance));
        if (applied > 0 && invoice.Outstanding == 0) PaymentComplete(invoice);
    }

    private void EmitItems(IEnumerable<LineItem> items)
    {
        foreach (var item in items) Indent(item.Description, Money(item.Amount));
    }

    private void EmitTotals(Totals totals)
    {
        Indent("subtotal", Money(totals.Subtotal), "discount", Money(totals.Discount),
               "tax", Money(totals.Tax), "total", Money(totals.Total));
    }

    private void CmdInvoice(string[] args)
    {
        Invoice invoice = RequireInvoice(args[0]);
        Emit("INVOICE", invoice.Number, "sub", invoice.Subscription.Number,
             invoice.Customer.Name, "day", invoice.Day, invoice.Kind, invoice.State);
        EmitItems(invoice.Items);
        EmitTotals(new Totals(invoice.Subtotal, invoice.Discount, invoice.Tax,
                              invoice.Total, invoice.Credit, invoice.Due));
        Indent("credit", Money(invoice.Credit), "due", Money(invoice.Due),
               "paid", Money(invoice.Paid), "refunded", Money(invoice.Refunded),
               "outstanding", Money(invoice.Outstanding));
    }

    private void CmdSub(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0]);
        Emit("SUB", subscription.Number, subscription.Customer.Name, subscription.Plan.Name,
             "seats", subscription.Seats, subscription.State);
        if (subscription.State == "TRIALING")
            Indent("trial until", subscription.TrialEnd);
        if (subscription.State is "ACTIVE" or "PAST_DUE" or "UNPAID" or "PAUSED")
            Indent("period", subscription.Period());
        if (subscription.State == "PAUSED") Indent("paused since", subscription.PauseStart);
        if (subscription.Pending is { } pending)
            Indent("pending", pending.Plan.Name, "seats", pending.Seats);
        if (subscription.CancelEnd) Indent("cancel at end");
        if (subscription.CancelOn is not null) Indent("cancel on", subscription.CancelOn);
        if (subscription.State == "CANCELED") Indent("canceled on", subscription.CanceledOn);
        if (subscription.Coupon is not null)
        {
            if (subscription.Remaining is null)
                Indent("coupon", subscription.Coupon.Name, "forever");
            else if (subscription.Remaining > 0)
                Indent("coupon", subscription.Coupon.Name, "left", subscription.Remaining);
        }
        if (subscription.Plan.Mode is not null && subscription.State != "CANCELED")
            Indent("usage", subscription.Usage);
        var open = subscription.Invoices.Where(invoice => invoice.Outstanding > 0)
                                       .Select(invoice => (object?)invoice.Number).ToArray();
        if (open.Length > 0) Indent(new object?[] { "open" }.Concat(open).ToArray());
    }

    private void CmdPreview(string[] args)
    {
        Subscription subscription = RequireSubscription(args[0],
            "TRIALING", "ACTIVE", "PAST_DUE", "UNPAID");
        int when = (subscription.State == "TRIALING"
                    ? subscription.TrialEnd : subscription.End)!.Value;
        string kind;
        List<LineItem> items;
        if (subscription.CancelEnd)
        {
            kind = "final";
            items = subscription.State == "TRIALING"
                ? new List<LineItem>() : UsageItems(subscription);
        }
        else if (subscription.State == "TRIALING")
        {
            kind = "first";
            items = OpeningItems(subscription, when);
        }
        else
        {
            kind = "renewal";
            var (plan, seats) = subscription.Pending ?? (subscription.Plan, subscription.Seats);
            items = UsageItems(subscription);
            items.Add(PeriodItem(plan, seats, when));
        }
        Emit("PREVIEW", "sub", subscription.Number, "day", when, kind);
        if (items.Count == 0)
        {
            Indent("(none)");
            return;
        }
        EmitItems(items);
        Totals totals = InvoiceTotals(subscription, items);
        EmitTotals(totals);
        Indent("credit", Money(totals.Credit), "due", Money(totals.Due));
    }

    private void CmdStatement(string[] args)
    {
        Customer customer = RequireCustomer(args[0]);
        Emit("STATEMENT", customer.Name, "region", customer.Region,
             "tax", Percent(TaxRate(customer.Region)), "method", customer.Method,
             "balance", Money(customer.Balance));
        foreach (var subscription in customer.Subscriptions)
            Indent("sub", subscription.Number, subscription.Plan.Name, subscription.State);
        foreach (var invoice in customer.Invoices)
            Indent("invoice", invoice.Number, "day", invoice.Day,
                   "sub", invoice.Subscription.Number, invoice.Kind, "total",
                   Money(invoice.Total), "outstanding", Money(invoice.Outstanding));
        Indent("outstanding", Money(customer.Invoices.Sum(invoice => invoice.Outstanding)));
    }

    private void CmdLedger(string[] args)
    {
        Customer customer = RequireCustomer(args[0]);
        Emit("LEDGER", customer.Name, "balance", Money(customer.Balance));
        foreach (var entry in customer.Log)
            Indent("day", entry.Day, entry.Description, SignedMoney(entry.Change),
                   "balance", Money(entry.Balance));
        if (customer.Log.Count == 0) Indent("(none)");
    }

    private void CmdMrr()
    {
        var grouped = new SortedDictionary<string, (int Subs, long Monthly)>(StringComparer.Ordinal);
        foreach (var subscription in subscriptions)
        {
            if (subscription.State is not ("ACTIVE" or "PAST_DUE")) continue;
            long fee = subscription.Fee();
            long monthly = subscription.Plan.Cycle switch
            {
                "MONTHLY" => fee,
                "YEARLY" => fee / 12,
                _ => fee * 30 / 7
            };
            grouped.TryGetValue(subscription.Plan.Name, out var previous);
            grouped[subscription.Plan.Name] = (previous.Subs + 1, previous.Monthly + monthly);
        }
        Emit("MRR");
        foreach (var (name, row) in grouped)
            Indent(name, "subs", row.Subs, "mrr", Money(row.Monthly));
        Indent("total subs", grouped.Sum(row => row.Value.Subs),
               "mrr", Money(grouped.Sum(row => row.Value.Monthly)));
    }

    private static object?[] AgingParts(long[] amounts) => new object?[] {
        "0-30", Money(amounts[0]), "31-60", Money(amounts[1]),
        "61+", Money(amounts[2]), "sum", Money(amounts.Sum())
    };

    private void CmdAging()
    {
        var byCustomer = new SortedDictionary<string, long[]>(StringComparer.Ordinal);
        var totals = new long[3];
        foreach (var invoice in invoices)
        {
            if (invoice.Outstanding == 0) continue;
            int age = day - invoice.Day;
            int bucket = age <= 30 ? 0 : age <= 60 ? 1 : 2;
            if (!byCustomer.TryGetValue(invoice.Customer.Name, out var amounts))
            {
                amounts = new long[3];
                byCustomer[invoice.Customer.Name] = amounts;
            }
            amounts[bucket] += invoice.Outstanding;
            totals[bucket] += invoice.Outstanding;
        }
        Emit("AGING", "day", day);
        foreach (var (name, amounts) in byCustomer)
            Indent(new object?[] { name }.Concat(AgingParts(amounts)).ToArray());
        Indent(new object?[] { "total" }.Concat(AgingParts(totals)).ToArray());
    }

    private void CmdDunning()
    {
        Emit("DUNNING");
        var pending = invoices.Where(invoice => invoice.Retries.Count > 0).ToArray();
        foreach (var invoice in pending)
            Indent("invoice", invoice.Number, "sub", invoice.Subscription.Number,
                   invoice.Customer.Name, "outstanding", Money(invoice.Outstanding),
                   "attempts", invoice.Attempts, "next", invoice.Retries[0]);
        if (pending.Length == 0) Indent("(none)");
    }

    private void CmdRevenue()
    {
        Emit("REVENUE");
        Indent("invoices", invoices.Count,
               "subtotal", Money(invoices.Sum(invoice => invoice.Subtotal)),
               "discount", Money(invoices.Sum(invoice => invoice.Discount)),
               "tax", Money(invoices.Sum(invoice => invoice.Tax)),
               "total", Money(invoices.Sum(invoice => invoice.Total)));
        Indent("credit", Money(invoices.Sum(invoice => invoice.Credit)),
               "paid", Money(invoices.Sum(invoice => invoice.Paid)),
               "refunded", Money(invoices.Sum(invoice => invoice.Refunded)),
               "outstanding", Money(invoices.Sum(invoice => invoice.Outstanding)),
               "balances", Money(customers.Values.Sum(customer => customer.Balance)));
    }

    private void CmdEvents(string[] args)
    {
        int? selected = args.Length == 0 ? null : RequireSubscription(args[0]).Number;
        if (selected is null) Emit("EVENTS");
        else Emit("EVENTS", "sub", selected);
        var matching = events.Where(entry => selected is null || entry.Number == selected).ToArray();
        foreach (var entry in matching)
            Indent("day", entry.Day, "sub", entry.Number, entry.Old, "->", entry.New);
        if (matching.Length == 0) Indent("(none)");
    }

    public void Execute(string line)
    {
        string[] fields = line.Split(' ');
        string[] args = fields.Skip(1).ToArray();
        try
        {
            switch (fields[0])
            {
                case "PLAN": CmdPlan(args); break;
                case "TIER": CmdTier(args); break;
                case "TAX": CmdTax(args); break;
                case "CUSTOMER": CmdCustomer(args); break;
                case "COUPON": CmdCoupon(args); break;
                case "PAYMETHOD": CmdPayMethod(args); break;
                case "CREDIT": CmdCredit(args); break;
                case "DAY": CmdDay(args); break;
                case "SUBSCRIBE": CmdSubscribe(args); break;
                case "CHANGE": CmdChange(args); break;
                case "PAUSE": CmdPause(args); break;
                case "RESUME": CmdResume(args); break;
                case "CANCEL": CmdCancel(args); break;
                case "USAGE": CmdUsage(args); break;
                case "APPLY": CmdApply(args); break;
                case "PAY": CmdPay(args); break;
                case "REFUND": CmdRefund(args); break;
                case "INVOICE": CmdInvoice(args); break;
                case "SUB": CmdSub(args); break;
                case "PREVIEW": CmdPreview(args); break;
                case "STATEMENT": CmdStatement(args); break;
                case "LEDGER": CmdLedger(args); break;
                case "MRR": CmdMrr(); break;
                case "AGING": CmdAging(); break;
                case "DUNNING": CmdDunning(); break;
                case "REVENUE": CmdRevenue(); break;
                case "EVENTS": CmdEvents(args); break;
            }
        }
        catch (CommandError error)
        {
            Emit("ERROR", error.Message);
        }
    }

    public void Print()
    {
        foreach (string line in output) Console.WriteLine(line);
    }
}

static class Program
{
    private static void Main()
    {
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        var service = new BillingService();
        for (int i = 0; i < count; ++i)
            service.Execute(Console.ReadLine()!);
        service.Print();
    }
}
