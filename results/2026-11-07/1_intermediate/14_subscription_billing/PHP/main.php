<?php

declare(strict_types=1);

const PERIOD_LENGTHS = ['WEEKLY' => 7, 'MONTHLY' => 30, 'YEARLY' => 360];

final class CommandError extends RuntimeException {}

function cents(string $text): int
{
    [$whole, $fraction] = explode('.', $text);
    return (int) $whole * 100 + (int) $fraction;
}

function money(int $value): string
{
    $sign = $value < 0 ? '-' : '';
    $absolute = abs($value);
    return $sign . intdiv($absolute, 100) . '.' . str_pad((string) ($absolute % 100), 2, '0', STR_PAD_LEFT);
}

function signedMoney(int $value): string
{
    return ($value > 0 ? '+' : '') . money($value);
}

function percentage(int $basisPoints): string
{
    return money($basisPoints) . '%';
}

function floorDiv(int $numerator, int $denominator): int
{
    $quotient = intdiv($numerator, $denominator);
    return $numerator < 0 && $numerator % $denominator !== 0 ? $quotient - 1 : $quotient;
}

final class Plan
{
    public int $length;
    public int $trial = 0;
    public int $setup = 0;
    public bool $perSeat = false;
    public ?string $mode = null;
    public array $tiers = [];

    public function __construct(
        public string $name,
        public int $price,
        public string $cycle
    ) {
        $this->length = PERIOD_LENGTHS[$cycle];
    }

    public function fee(int $seats): int
    {
        return $this->price * ($this->perSeat ? $seats : 1);
    }

    public function usageCharge(int $units): int
    {
        $lower = 0;
        $total = 0;
        $count = count($this->tiers);
        foreach ($this->tiers as $index => [$upper, $unitPrice, $flatFee]) {
            $last = $index === $count - 1;
            if ($this->mode === 'VOLUME') {
                if ($last || $upper === null || $units <= $upper) {
                    return $units * $unitPrice + $flatFee;
                }
            } else {
                if ($units <= $lower) {
                    break;
                }
                $end = $last || $upper === null ? $units : min($units, $upper);
                $total += ($end - $lower) * $unitPrice + $flatFee;
                if ($last || $upper === null) {
                    break;
                }
                $lower = $upper;
            }
        }
        return $total;
    }
}

final class Customer
{
    public string $method = 'OK';
    public int $balance = 0;
    public array $log = [];
    public array $subscriptions = [];
    public array $invoices = [];

    public function __construct(
        public string $name,
        public string $region
    ) {}
}

final class Coupon
{
    public int $redemptions = 0;

    public function __construct(
        public string $name,
        public string $kind,
        public int $value,
        public ?int $applications,
        public ?int $maximum
    ) {}
}

final class Subscription
{
    public string $state = 'NONE';
    public ?int $start = null;
    public ?int $end = null;
    public ?int $trialEnd = null;
    public ?int $pauseStart = null;
    public ?array $pending = null;
    public bool $cancelEnd = false;
    public ?int $cancelOn = null;
    public ?int $canceledOn = null;
    public ?int $remaining;
    public int $usage = 0;
    public array $invoices = [];

    public function __construct(
        public int $number,
        public Customer $customer,
        public Plan $plan,
        public int $seats,
        public ?Coupon $coupon
    ) {
        $this->remaining = $coupon?->applications;
    }

    public function fee(): int
    {
        return $this->plan->fee($this->seats);
    }

    public function period(): string
    {
        return $this->start . '-' . $this->end;
    }
}

final class Invoice
{
    public int $subtotal;
    public int $discount;
    public int $tax;
    public int $total;
    public int $credit;
    public int $due;
    public int $paid = 0;
    public int $refunded = 0;
    public int $outstanding;
    public int $attempts = 0;
    public array $retries = [];
    public Customer $customer;

    public function __construct(
        public int $number,
        public Subscription $subscription,
        public int $day,
        public string $kind,
        public array $items,
        array $totals
    ) {
        [$this->subtotal, $this->discount, $this->tax, $this->total,
         $this->credit, $this->due] = $totals;
        $this->customer = $subscription->customer;
        $this->outstanding = $this->due;
    }

    public function state(): string
    {
        return $this->outstanding === 0 ? 'PAID' : 'OPEN';
    }
}

final class BillingService
{
    private int $day = 1;
    private array $plans = [];
    private array $taxRates = [];
    private array $customers = [];
    private array $coupons = [];
    private array $subscriptions = [];
    private array $invoices = [];
    private array $events = [];
    private array $output = [];

    private function emit(string|int ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    private function indented(string|int ...$parts): void
    {
        $this->output[] = '  ' . implode(' ', $parts);
    }

    private function notice(string|int ...$parts): void
    {
        $this->indented('day', $this->day, ...$parts);
    }

    private function plan(string $name): Plan
    {
        if (!isset($this->plans[$name])) {
            throw new CommandError('unknown plan ' . $name);
        }
        return $this->plans[$name];
    }

    private function customer(string $name): Customer
    {
        if (!isset($this->customers[$name])) {
            throw new CommandError('unknown customer ' . $name);
        }
        return $this->customers[$name];
    }

    private function redeemableCoupon(string $name): Coupon
    {
        if (!isset($this->coupons[$name])) {
            throw new CommandError('unknown coupon ' . $name);
        }
        $coupon = $this->coupons[$name];
        if ($coupon->maximum !== null && $coupon->redemptions === $coupon->maximum) {
            throw new CommandError('coupon exhausted ' . $name);
        }
        return $coupon;
    }

    private function subscription(string $text, ?array $allowed = null): Subscription
    {
        $number = (int) $text;
        if ($number < 1 || $number > count($this->subscriptions)) {
            throw new CommandError('unknown sub ' . $text);
        }
        $subscription = $this->subscriptions[$number - 1];
        if ($allowed !== null && !in_array($subscription->state, $allowed, true)) {
            throw new CommandError('invalid state ' . $text . ' ' . $subscription->state);
        }
        return $subscription;
    }

    private function invoice(string $text): Invoice
    {
        $number = (int) $text;
        if ($number < 1 || $number > count($this->invoices)) {
            throw new CommandError('unknown invoice ' . $text);
        }
        return $this->invoices[$number - 1];
    }

    private function balanceChange(Customer $customer, int $change, string $description): void
    {
        if ($change !== 0) {
            $customer->balance += $change;
            $customer->log[] = [$this->day, $description, $change, $customer->balance];
        }
    }

    private function changeState(Subscription $subscription, string $state): void
    {
        $old = $subscription->state;
        if ($old === 'PAST_DUE') {
            foreach ($subscription->invoices as $invoice) {
                $invoice->retries = [];
            }
        }
        $subscription->state = $state;
        $this->notice('sub', $subscription->number, $old, '->', $state);
        $this->events[] = [$this->day, $subscription->number, $old, $state];
    }

    private function periodItem(Plan $plan, int $seats, int $start): array
    {
        return [
            'charge ' . $plan->name . ' seats ' . $seats . ' ' .
            $start . '-' . ($start + $plan->length),
            $plan->fee($seats)
        ];
    }

    private function openingItems(Subscription $subscription, int $start): array
    {
        $plan = $subscription->plan;
        $items = [$this->periodItem($plan, $subscription->seats, $start)];
        if ($plan->setup !== 0) {
            $items[] = ['setup ' . $plan->name, $plan->setup];
        }
        return $items;
    }

    private function usageItems(Subscription $subscription, bool $close = false): array
    {
        if ($subscription->plan->mode === null || $subscription->usage === 0) {
            return [];
        }
        $units = $subscription->usage;
        $item = [
            'usage ' . $subscription->plan->name . ' ' . $units . ' units',
            $subscription->plan->usageCharge($units)
        ];
        if ($close) {
            $subscription->usage = 0;
        }
        return [$item];
    }

    private function couponUsable(Subscription $subscription, int $subtotal): bool
    {
        return $subtotal > 0 && $subscription->coupon !== null &&
            ($subscription->remaining === null || $subscription->remaining > 0);
    }

    private function invoiceTotals(Subscription $subscription, array $items): array
    {
        $subtotal = 0;
        foreach ($items as $item) {
            $subtotal += $item[1];
        }
        $discount = 0;
        if ($this->couponUsable($subscription, $subtotal)) {
            $coupon = $subscription->coupon;
            $discount = $coupon->kind === 'PERCENT'
                ? floorDiv($subtotal * $coupon->value, 10000)
                : min($subtotal, $coupon->value);
        }
        $tax = floorDiv(
            ($subtotal - $discount) * ($this->taxRates[$subscription->customer->region] ?? 0),
            10000
        );
        $total = $subtotal - $discount + $tax;
        $credit = min($subscription->customer->balance, $total);
        return [$subtotal, $discount, $tax, $total, $credit, $total - $credit];
    }

    private function issue(Subscription $subscription, string $kind, array $items): void
    {
        $totals = $this->invoiceTotals($subscription, $items);
        $invoice = new Invoice(
            count($this->invoices) + 1, $subscription, $this->day, $kind, $items, $totals
        );
        if ($this->couponUsable($subscription, $invoice->subtotal) &&
            $subscription->remaining !== null) {
            --$subscription->remaining;
        }
        $this->invoices[] = $invoice;
        $subscription->invoices[] = $invoice;
        $subscription->customer->invoices[] = $invoice;
        $this->balanceChange(
            $subscription->customer, -$invoice->credit, 'applied invoice ' . $invoice->number
        );

        if ($invoice->due === 0) {
            $result = 'PAID';
        } elseif ($subscription->state === 'UNPAID') {
            $result = 'OPEN';
        } else {
            $invoice->attempts = 1;
            if ($subscription->customer->method === 'OK') {
                $invoice->paid = $invoice->due;
                $invoice->outstanding = 0;
                $result = 'PAID';
            } else {
                $result = 'FAILED';
            }
        }
        $this->notice(
            'invoice', $invoice->number, 'sub', $subscription->number,
            $kind, 'total', money($invoice->total), 'credit', money($invoice->credit),
            'due', money($invoice->due), $result
        );
        if ($result === 'FAILED') {
            if ($subscription->state === 'ACTIVE') {
                $this->changeState($subscription, 'PAST_DUE');
            }
            if ($subscription->state === 'PAST_DUE') {
                $invoice->retries = [$this->day + 3, $this->day + 5, $this->day + 7];
            }
        }
    }

    private function paymentComplete(Invoice $invoice): void
    {
        $invoice->retries = [];
        $subscription = $invoice->subscription;
        if (!in_array($subscription->state, ['PAST_DUE', 'UNPAID'], true)) {
            return;
        }
        foreach ($subscription->invoices as $other) {
            if ($other->outstanding !== 0) {
                return;
            }
        }
        $subscription->cancelOn = null;
        $this->changeState($subscription, 'ACTIVE');
    }

    private function cancelSubscription(Subscription $subscription): void
    {
        $this->changeState($subscription, 'CANCELED');
        $subscription->canceledOn = $this->day;
        $subscription->pending = null;
        $subscription->cancelEnd = false;
        $subscription->cancelOn = null;
        $items = $this->usageItems($subscription, true);
        if ($items) {
            $this->issue($subscription, 'final', $items);
        }
    }

    private function retry(Invoice $invoice): void
    {
        array_shift($invoice->retries);
        ++$invoice->attempts;
        $number = $invoice->attempts - 1;
        if ($invoice->customer->method === 'OK') {
            $invoice->paid += $invoice->outstanding;
            $invoice->outstanding = 0;
            $this->notice('retry', $number, 'invoice', $invoice->number, 'PAID');
            $this->paymentComplete($invoice);
        } else {
            $this->notice('retry', $number, 'invoice', $invoice->number, 'FAILED');
            if (!$invoice->retries) {
                $this->changeState($invoice->subscription, 'UNPAID');
                $invoice->subscription->cancelOn = $this->day + 14;
            }
        }
    }

    private function advanceSubscription(Subscription $subscription): void
    {
        if ($subscription->state === 'PAUSED' || $subscription->state === 'CANCELED') {
            return;
        }
        foreach ($subscription->invoices as $invoice) {
            if ($invoice->retries && $invoice->retries[0] === $this->day) {
                $this->retry($invoice);
            }
        }
        if ($subscription->state === 'UNPAID' && $subscription->cancelOn === $this->day) {
            $this->cancelSubscription($subscription);
        }
        if ($subscription->state === 'TRIALING' && $subscription->trialEnd === $this->day) {
            if ($subscription->cancelEnd) {
                $this->cancelSubscription($subscription);
            } else {
                $this->changeState($subscription, 'ACTIVE');
                $subscription->start = $this->day;
                $subscription->end = $this->day + $subscription->plan->length;
                $this->issue(
                    $subscription, 'first', $this->openingItems($subscription, $this->day)
                );
            }
        }
        if (in_array($subscription->state, ['ACTIVE', 'PAST_DUE', 'UNPAID'], true) &&
            $subscription->end === $this->day) {
            if ($subscription->cancelEnd) {
                $this->cancelSubscription($subscription);
            } else {
                $items = $this->usageItems($subscription, true);
                if ($subscription->pending !== null) {
                    [$plan, $seats] = $subscription->pending;
                    $this->notice(
                        'sub', $subscription->number, $subscription->plan->name,
                        'seats', $subscription->seats, '->', $plan->name, 'seats', $seats
                    );
                    $subscription->plan = $plan;
                    $subscription->seats = $seats;
                    $subscription->pending = null;
                }
                $subscription->start = $this->day;
                $subscription->end = $this->day + $subscription->plan->length;
                $items[] = $this->periodItem(
                    $subscription->plan, $subscription->seats, $this->day
                );
                $this->issue($subscription, 'renewal', $items);
            }
        }
    }

    private function cmdPlan(array $args): void
    {
        [$name, $amount, $cycle] = array_slice($args, 0, 3);
        if (isset($this->plans[$name])) {
            throw new CommandError('duplicate plan ' . $name);
        }
        $plan = new Plan($name, cents($amount), $cycle);
        $options = array_slice($args, 3);
        for ($i = 0; $i < count($options);) {
            $option = $options[$i];
            if ($option === 'TRIAL') {
                $plan->trial = (int) $options[$i + 1];
                $i += 2;
            } elseif ($option === 'SETUP') {
                $plan->setup = cents($options[$i + 1]);
                $i += 2;
            } else {
                if ($option === 'PERSEAT') {
                    $plan->perSeat = true;
                } else {
                    $plan->mode = $option;
                }
                ++$i;
            }
        }
        $this->plans[$name] = $plan;
        $parts = ['PLAN', $name, $cycle, $amount];
        if ($plan->trial !== 0) {
            array_push($parts, 'trial', $plan->trial);
        }
        if ($plan->setup !== 0) {
            array_push($parts, 'setup', money($plan->setup));
        }
        if ($plan->perSeat) {
            $parts[] = 'perseat';
        }
        if ($plan->mode !== null) {
            $parts[] = strtolower($plan->mode);
        }
        $this->emit(...$parts);
    }

    private function cmdTier(array $args): void
    {
        [$name, $limit, $unit, $flat] = $args;
        $plan = $this->plan($name);
        if ($plan->mode === null) {
            throw new CommandError('not metered ' . $name);
        }
        $upper = $limit === 'INF' ? null : (int) $limit;
        if ($plan->tiers) {
            $previous = $plan->tiers[count($plan->tiers) - 1][0];
            if ($previous === null || ($upper !== null && $upper <= $previous)) {
                throw new CommandError('tier order ' . $name);
            }
        }
        $plan->tiers[] = [$upper, cents($unit), cents($flat)];
        $this->emit('TIER', $name, count($plan->tiers), 'upto', $limit,
                    'unit', $unit, 'flat', $flat);
    }

    private function cmdTax(array $args): void
    {
        [$region, $bp] = $args;
        $this->taxRates[$region] = (int) $bp;
        $this->emit('TAX', $region, percentage((int) $bp));
    }

    private function cmdCustomer(array $args): void
    {
        [$name, $region] = $args;
        if (isset($this->customers[$name])) {
            throw new CommandError('duplicate customer ' . $name);
        }
        $this->customers[$name] = new Customer($name, $region);
        $this->emit('CUSTOMER', $name, 'region', $region);
    }

    private function cmdCoupon(array $args): void
    {
        [$name, $kind, $value, $application] = array_slice($args, 0, 4);
        if (isset($this->coupons[$name])) {
            throw new CommandError('duplicate coupon ' . $name);
        }
        $options = array_slice($args, 4);
        $applications = $application === 'ONCE' ? 1 : null;
        $index = 0;
        if ($application === 'REPEATING') {
            $applications = (int) $options[0];
            $index = 1;
        }
        $maximum = $index < count($options) ? (int) $options[$index + 1] : null;
        $numeric = $kind === 'PERCENT' ? (int) $value : cents($value);
        $coupon = new Coupon($name, $kind, $numeric, $applications, $maximum);
        $this->coupons[$name] = $coupon;
        $shown = $kind === 'PERCENT' ? percentage($numeric) : money($numeric);
        $parts = ['COUPON', $name, strtolower($kind), $shown, strtolower($application)];
        if ($application === 'REPEATING') {
            $parts[] = $applications;
        }
        if ($maximum !== null) {
            array_push($parts, 'max', $maximum);
        }
        $this->emit(...$parts);
    }

    private function cmdPaymethod(array $args): void
    {
        [$name, $method] = $args;
        $customer = $this->customer($name);
        $customer->method = $method;
        $this->emit('PAYMETHOD', $name, $method);
    }

    private function cmdCredit(array $args): void
    {
        [$name, $amount] = $args;
        $customer = $this->customer($name);
        $value = cents($amount);
        if ($value === 0) {
            throw new CommandError('invalid amount');
        }
        $this->balanceChange($customer, $value, 'grant');
        $this->emit('CREDIT', $name, 'amount', $amount, 'balance', money($customer->balance));
    }

    private function cmdDay(array $args): void
    {
        $text = $args[0];
        $target = (int) $text;
        if ($target <= $this->day) {
            throw new CommandError('invalid day ' . $text);
        }
        $this->emit('DAY', $target);
        for ($day = $this->day + 1; $day <= $target; ++$day) {
            $this->day = $day;
            foreach ($this->subscriptions as $subscription) {
                $this->advanceSubscription($subscription);
            }
        }
    }

    private function cmdSubscribe(array $args): void
    {
        [$name, $planName] = array_slice($args, 0, 2);
        $customer = $this->customer($name);
        $plan = $this->plan($planName);
        $seats = 1;
        $hasSeats = false;
        $couponName = null;
        $options = array_slice($args, 2);
        for ($i = 0; $i < count($options); $i += 2) {
            if ($options[$i] === 'SEATS') {
                $seats = (int) $options[$i + 1];
                $hasSeats = true;
            } else {
                $couponName = $options[$i + 1];
            }
        }
        if ($hasSeats && !$plan->perSeat) {
            throw new CommandError('not per-seat ' . $planName);
        }
        if ($seats === 0) {
            throw new CommandError('invalid seats');
        }
        $coupon = $couponName === null ? null : $this->redeemableCoupon($couponName);
        $subscription = new Subscription(
            count($this->subscriptions) + 1, $customer, $plan, $seats, $coupon
        );
        if ($coupon !== null) {
            ++$coupon->redemptions;
        }
        $this->subscriptions[] = $subscription;
        $customer->subscriptions[] = $subscription;
        $parts = ['SUBSCRIBE', 'sub', $subscription->number, $name, $planName,
                  'seats', $seats];
        if ($coupon !== null) {
            array_push($parts, 'coupon', $coupon->name);
        }
        $this->emit(...$parts);
        if ($plan->trial !== 0) {
            $subscription->trialEnd = $this->day + $plan->trial;
            $this->changeState($subscription, 'TRIALING');
        } else {
            $this->changeState($subscription, 'ACTIVE');
            $subscription->start = $this->day;
            $subscription->end = $this->day + $plan->length;
            $this->issue($subscription, 'first', $this->openingItems($subscription, $this->day));
        }
    }

    private function cmdChange(array $args): void
    {
        [$text, $kind, $value] = $args;
        $subscription = $this->subscription($text, ['ACTIVE', 'TRIALING']);
        $oldPlan = $subscription->plan;
        $oldSeats = $subscription->seats;
        if ($kind === 'PLAN') {
            $plan = $this->plan($value);
            $seats = $plan->perSeat ? $oldSeats : 1;
        } else {
            $plan = $oldPlan;
            if (!$plan->perSeat) {
                throw new CommandError('not per-seat ' . $plan->name);
            }
            $seats = (int) $value;
            if ($seats === 0) {
                throw new CommandError('invalid seats');
            }
        }
        if ($plan === $oldPlan && $seats === $oldSeats) {
            throw new CommandError('no change ' . $text);
        }
        $head = ['CHANGE', 'sub', $subscription->number, $oldPlan->name,
                 'seats', $oldSeats, '->', $plan->name, 'seats', $seats];
        $subscription->pending = null;
        $upgrade = $plan->fee($seats) * $oldPlan->length >
                   $oldPlan->fee($oldSeats) * $plan->length;
        if ($subscription->state === 'TRIALING') {
            $subscription->plan = $plan;
            $subscription->seats = $seats;
            $this->emit(...[...$head, 'now']);
        } elseif ($upgrade) {
            $this->emit(...[...$head, 'now']);
            $days = $subscription->end - $this->day;
            $items = $this->usageItems($subscription, true);
            $items[] = [
                'unused ' . $oldPlan->name . ' seats ' . $oldSeats . ' ' . $days . ' days',
                -intdiv($oldPlan->fee($oldSeats) * $days, $oldPlan->length)
            ];
            $items[] = [
                'remaining ' . $plan->name . ' seats ' . $seats . ' ' . $days . ' days',
                intdiv($plan->fee($seats) * $days, $plan->length)
            ];
            $subscription->plan = $plan;
            $subscription->seats = $seats;
            $this->issue($subscription, 'upgrade', $items);
        } else {
            $subscription->pending = [$plan, $seats];
            $this->emit(...[...$head, 'at', $subscription->end]);
        }
    }

    private function cmdPause(array $args): void
    {
        $subscription = $this->subscription($args[0], ['ACTIVE']);
        $this->emit('PAUSE', 'sub', $subscription->number);
        $subscription->pauseStart = $this->day;
        $this->changeState($subscription, 'PAUSED');
    }

    private function cmdResume(array $args): void
    {
        $subscription = $this->subscription($args[0], ['PAUSED']);
        $elapsed = $this->day - $subscription->pauseStart;
        $subscription->end += $elapsed;
        $subscription->pauseStart = null;
        $this->emit('RESUME', 'sub', $subscription->number, 'shift',
                    $elapsed, 'period', $subscription->period());
        $this->changeState($subscription, 'ACTIVE');
    }

    private function cmdCancel(array $args): void
    {
        [$text, $when] = $args;
        $subscription = $this->subscription($text);
        if ($when === 'END') {
            if (!in_array($subscription->state, ['ACTIVE', 'TRIALING'], true)) {
                throw new CommandError('invalid state ' . $text . ' ' . $subscription->state);
            }
            if ($subscription->cancelEnd) {
                throw new CommandError('already canceling ' . $text);
            }
            $subscription->cancelEnd = true;
            $day = $subscription->state === 'TRIALING'
                ? $subscription->trialEnd : $subscription->end;
            $this->emit('CANCEL', 'sub', $subscription->number, 'end', $day);
        } else {
            if ($subscription->state === 'CANCELED') {
                throw new CommandError('invalid state ' . $text . ' ' . $subscription->state);
            }
            $refund = 0;
            if (in_array($subscription->state, ['ACTIVE', 'PAUSED'], true)) {
                $start = $subscription->state === 'ACTIVE'
                    ? $this->day : $subscription->pauseStart;
                $refund = intdiv(
                    $subscription->fee() * ($subscription->end - $start),
                    $subscription->plan->length
                );
            }
            $this->balanceChange(
                $subscription->customer, $refund, 'cancel sub ' . $subscription->number
            );
            $this->emit('CANCEL', 'sub', $subscription->number, 'now',
                        'credit', money($refund));
            $this->cancelSubscription($subscription);
        }
    }

    private function cmdUsage(array $args): void
    {
        [$text, $units] = $args;
        $subscription = $this->subscription($text, ['ACTIVE', 'PAST_DUE']);
        if ($subscription->plan->mode === null) {
            throw new CommandError('not metered ' . $subscription->plan->name);
        }
        $quantity = (int) $units;
        if ($quantity === 0) {
            throw new CommandError('invalid units');
        }
        $subscription->usage += $quantity;
        $this->emit('USAGE', 'sub', $subscription->number, 'units',
                    $quantity, 'total', $subscription->usage);
    }

    private function cmdApply(array $args): void
    {
        [$text, $name] = $args;
        $subscription = $this->subscription($text);
        if ($subscription->state === 'CANCELED') {
            throw new CommandError('invalid state ' . $text . ' ' . $subscription->state);
        }
        $coupon = $this->redeemableCoupon($name);
        ++$coupon->redemptions;
        $subscription->coupon = $coupon;
        $subscription->remaining = $coupon->applications;
        $this->emit('APPLY', 'sub', $subscription->number, 'coupon', $name);
    }

    private function cmdPay(array $args): void
    {
        $text = $args[0];
        $invoice = $this->invoice($text);
        if ($invoice->outstanding === 0) {
            throw new CommandError('already paid ' . $text);
        }
        $this->emit('PAY', 'invoice', $invoice->number,
                    'amount', money($invoice->outstanding));
        $invoice->paid += $invoice->outstanding;
        $invoice->outstanding = 0;
        $this->paymentComplete($invoice);
    }

    private function cmdRefund(array $args): void
    {
        [$text, $amount] = $args;
        $invoice = $this->invoice($text);
        $value = cents($amount);
        if ($value === 0) {
            throw new CommandError('invalid amount');
        }
        $maximum = $invoice->total - $invoice->refunded;
        if ($value > $maximum) {
            throw new CommandError('refund exceeds ' . $text . ' ' . money($maximum));
        }
        $applied = min($value, $invoice->outstanding);
        $invoice->refunded += $value;
        $invoice->outstanding -= $applied;
        $this->balanceChange(
            $invoice->customer, $value - $applied, 'refund invoice ' . $invoice->number
        );
        $this->emit(
            'REFUND', 'invoice', $invoice->number, 'amount', $amount,
            'applied', money($applied), 'balance', money($invoice->customer->balance)
        );
        if ($applied !== 0 && $invoice->outstanding === 0) {
            $this->paymentComplete($invoice);
        }
    }

    private function emitItems(array $items): void
    {
        foreach ($items as [$description, $amount]) {
            $this->indented($description, money($amount));
        }
    }

    private function emitTotals(array $totals): void
    {
        [$subtotal, $discount, $tax, $total] = $totals;
        $this->indented(
            'subtotal', money($subtotal), 'discount', money($discount),
            'tax', money($tax), 'total', money($total)
        );
    }

    private function cmdInvoice(array $args): void
    {
        $invoice = $this->invoice($args[0]);
        $this->emit(
            'INVOICE', $invoice->number, 'sub', $invoice->subscription->number,
            $invoice->customer->name, 'day', $invoice->day,
            $invoice->kind, $invoice->state()
        );
        $this->emitItems($invoice->items);
        $this->emitTotals([
            $invoice->subtotal, $invoice->discount, $invoice->tax, $invoice->total
        ]);
        $this->indented(
            'credit', money($invoice->credit), 'due', money($invoice->due),
            'paid', money($invoice->paid), 'refunded', money($invoice->refunded),
            'outstanding', money($invoice->outstanding)
        );
    }

    private function cmdSub(array $args): void
    {
        $subscription = $this->subscription($args[0]);
        $state = $subscription->state;
        $this->emit(
            'SUB', $subscription->number, $subscription->customer->name,
            $subscription->plan->name, 'seats', $subscription->seats, $state
        );
        if ($state === 'TRIALING') {
            $this->indented('trial until', $subscription->trialEnd);
        }
        if (in_array($state, ['ACTIVE', 'PAST_DUE', 'UNPAID', 'PAUSED'], true)) {
            $this->indented('period', $subscription->period());
        }
        if ($state === 'PAUSED') {
            $this->indented('paused since', $subscription->pauseStart);
        }
        if ($subscription->pending !== null) {
            [$plan, $seats] = $subscription->pending;
            $this->indented('pending', $plan->name, 'seats', $seats);
        }
        if ($subscription->cancelEnd) {
            $this->indented('cancel at end');
        }
        if ($subscription->cancelOn !== null) {
            $this->indented('cancel on', $subscription->cancelOn);
        }
        if ($state === 'CANCELED') {
            $this->indented('canceled on', $subscription->canceledOn);
        }
        if ($subscription->coupon !== null) {
            if ($subscription->remaining === null) {
                $this->indented('coupon', $subscription->coupon->name, 'forever');
            } elseif ($subscription->remaining > 0) {
                $this->indented(
                    'coupon', $subscription->coupon->name, 'left', $subscription->remaining
                );
            }
        }
        if ($subscription->plan->mode !== null && $state !== 'CANCELED') {
            $this->indented('usage', $subscription->usage);
        }
        $open = [];
        foreach ($subscription->invoices as $invoice) {
            if ($invoice->outstanding !== 0) {
                $open[] = $invoice->number;
            }
        }
        if ($open) {
            $this->indented('open', ...$open);
        }
    }

    private function cmdPreview(array $args): void
    {
        $subscription = $this->subscription(
            $args[0], ['TRIALING', 'ACTIVE', 'PAST_DUE', 'UNPAID']
        );
        $day = $subscription->state === 'TRIALING'
            ? $subscription->trialEnd : $subscription->end;
        if ($subscription->cancelEnd) {
            $kind = 'final';
            $items = $subscription->state === 'TRIALING'
                ? [] : $this->usageItems($subscription);
        } elseif ($subscription->state === 'TRIALING') {
            $kind = 'first';
            $items = $this->openingItems($subscription, $day);
        } else {
            $kind = 'renewal';
            [$plan, $seats] = $subscription->pending ??
                              [$subscription->plan, $subscription->seats];
            $items = $this->usageItems($subscription);
            $items[] = $this->periodItem($plan, $seats, $day);
        }
        $this->emit('PREVIEW', 'sub', $subscription->number, 'day', $day, $kind);
        if (!$items) {
            $this->indented('(none)');
            return;
        }
        $this->emitItems($items);
        $totals = $this->invoiceTotals($subscription, $items);
        $this->emitTotals($totals);
        $this->indented('credit', money($totals[4]), 'due', money($totals[5]));
    }

    private function cmdStatement(array $args): void
    {
        $customer = $this->customer($args[0]);
        $this->emit(
            'STATEMENT', $customer->name, 'region', $customer->region,
            'tax', percentage($this->taxRates[$customer->region] ?? 0),
            'method', $customer->method, 'balance', money($customer->balance)
        );
        foreach ($customer->subscriptions as $subscription) {
            $this->indented(
                'sub', $subscription->number, $subscription->plan->name, $subscription->state
            );
        }
        $outstanding = 0;
        foreach ($customer->invoices as $invoice) {
            $this->indented(
                'invoice', $invoice->number, 'day', $invoice->day,
                'sub', $invoice->subscription->number, $invoice->kind,
                'total', money($invoice->total),
                'outstanding', money($invoice->outstanding)
            );
            $outstanding += $invoice->outstanding;
        }
        $this->indented('outstanding', money($outstanding));
    }

    private function cmdLedger(array $args): void
    {
        $customer = $this->customer($args[0]);
        $this->emit('LEDGER', $customer->name, 'balance', money($customer->balance));
        if (!$customer->log) {
            $this->indented('(none)');
        }
        foreach ($customer->log as [$day, $description, $change, $balance]) {
            $this->indented(
                'day', $day, $description, signedMoney($change), 'balance', money($balance)
            );
        }
    }

    private function cmdMrr(): void
    {
        $byPlan = [];
        foreach ($this->subscriptions as $subscription) {
            if (!in_array($subscription->state, ['ACTIVE', 'PAST_DUE'], true)) {
                continue;
            }
            $fee = $subscription->fee();
            $cycle = $subscription->plan->cycle;
            $monthly = $cycle === 'MONTHLY' ? $fee :
                       ($cycle === 'YEARLY' ? intdiv($fee, 12) : intdiv($fee * 30, 7));
            $name = $subscription->plan->name;
            if (!isset($byPlan[$name])) {
                $byPlan[$name] = [0, 0];
            }
            ++$byPlan[$name][0];
            $byPlan[$name][1] += $monthly;
        }
        $this->emit('MRR');
        ksort($byPlan, SORT_STRING);
        $count = 0;
        $total = 0;
        foreach ($byPlan as $name => [$subscriptions, $monthly]) {
            $this->indented($name, 'subs', $subscriptions, 'mrr', money($monthly));
            $count += $subscriptions;
            $total += $monthly;
        }
        $this->indented('total subs', $count, 'mrr', money($total));
    }

    private function agingParts(array $amounts): array
    {
        return [
            '0-30', money($amounts[0]), '31-60', money($amounts[1]),
            '61+', money($amounts[2]), 'sum', money(array_sum($amounts))
        ];
    }

    private function cmdAging(): void
    {
        $byCustomer = [];
        $totals = [0, 0, 0];
        foreach ($this->invoices as $invoice) {
            if ($invoice->outstanding === 0) {
                continue;
            }
            $age = $this->day - $invoice->day;
            $bucket = $age <= 30 ? 0 : ($age <= 60 ? 1 : 2);
            $name = $invoice->customer->name;
            $byCustomer[$name] ??= [0, 0, 0];
            $byCustomer[$name][$bucket] += $invoice->outstanding;
            $totals[$bucket] += $invoice->outstanding;
        }
        $this->emit('AGING', 'day', $this->day);
        ksort($byCustomer, SORT_STRING);
        foreach ($byCustomer as $name => $amounts) {
            $this->indented($name, ...$this->agingParts($amounts));
        }
        $this->indented('total', ...$this->agingParts($totals));
    }

    private function cmdDunning(): void
    {
        $this->emit('DUNNING');
        $found = false;
        foreach ($this->invoices as $invoice) {
            if ($invoice->retries) {
                $found = true;
                $this->indented(
                    'invoice', $invoice->number, 'sub', $invoice->subscription->number,
                    $invoice->customer->name, 'outstanding', money($invoice->outstanding),
                    'attempts', $invoice->attempts, 'next', $invoice->retries[0]
                );
            }
        }
        if (!$found) {
            $this->indented('(none)');
        }
    }

    private function cmdRevenue(): void
    {
        $subtotal = 0;
        $discount = 0;
        $tax = 0;
        $total = 0;
        $credit = 0;
        $paid = 0;
        $refunded = 0;
        $outstanding = 0;
        foreach ($this->invoices as $invoice) {
            $subtotal += $invoice->subtotal;
            $discount += $invoice->discount;
            $tax += $invoice->tax;
            $total += $invoice->total;
            $credit += $invoice->credit;
            $paid += $invoice->paid;
            $refunded += $invoice->refunded;
            $outstanding += $invoice->outstanding;
        }
        $balances = 0;
        foreach ($this->customers as $customer) {
            $balances += $customer->balance;
        }
        $this->emit('REVENUE');
        $this->indented(
            'invoices', count($this->invoices), 'subtotal', money($subtotal),
            'discount', money($discount), 'tax', money($tax), 'total', money($total)
        );
        $this->indented(
            'credit', money($credit), 'paid', money($paid),
            'refunded', money($refunded), 'outstanding', money($outstanding),
            'balances', money($balances)
        );
    }

    private function cmdEvents(array $args): void
    {
        $selected = $args ? $this->subscription($args[0])->number : null;
        if ($selected === null) {
            $this->emit('EVENTS');
        } else {
            $this->emit('EVENTS', 'sub', $selected);
        }
        $found = false;
        foreach ($this->events as [$day, $number, $old, $new]) {
            if ($selected === null || $number === $selected) {
                $found = true;
                $this->indented('day', $day, 'sub', $number, $old, '->', $new);
            }
        }
        if (!$found) {
            $this->indented('(none)');
        }
    }

    public function execute(string $line): void
    {
        $arguments = explode(' ', $line);
        $command = array_shift($arguments);
        try {
            switch ($command) {
                case 'PLAN':       $this->cmdPlan($arguments);       break;
                case 'TIER':       $this->cmdTier($arguments);       break;
                case 'TAX':        $this->cmdTax($arguments);        break;
                case 'CUSTOMER':   $this->cmdCustomer($arguments);   break;
                case 'COUPON':     $this->cmdCoupon($arguments);     break;
                case 'PAYMETHOD':  $this->cmdPaymethod($arguments);  break;
                case 'CREDIT':     $this->cmdCredit($arguments);     break;
                case 'DAY':        $this->cmdDay($arguments);        break;
                case 'SUBSCRIBE':  $this->cmdSubscribe($arguments);  break;
                case 'CHANGE':     $this->cmdChange($arguments);     break;
                case 'PAUSE':      $this->cmdPause($arguments);      break;
                case 'RESUME':     $this->cmdResume($arguments);     break;
                case 'CANCEL':     $this->cmdCancel($arguments);     break;
                case 'USAGE':      $this->cmdUsage($arguments);      break;
                case 'APPLY':      $this->cmdApply($arguments);      break;
                case 'PAY':        $this->cmdPay($arguments);        break;
                case 'REFUND':     $this->cmdRefund($arguments);     break;
                case 'INVOICE':    $this->cmdInvoice($arguments);    break;
                case 'SUB':        $this->cmdSub($arguments);        break;
                case 'PREVIEW':    $this->cmdPreview($arguments);    break;
                case 'STATEMENT':  $this->cmdStatement($arguments);  break;
                case 'LEDGER':     $this->cmdLedger($arguments);     break;
                case 'MRR':        $this->cmdMrr();                  break;
                case 'AGING':      $this->cmdAging();                break;
                case 'DUNNING':    $this->cmdDunning();              break;
                case 'REVENUE':    $this->cmdRevenue();              break;
                case 'EVENTS':     $this->cmdEvents($arguments);     break;
            }
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }

    public function printOutput(): void
    {
        if ($this->output) {
            echo implode("\n", $this->output), "\n";
        }
    }
}

$numberOfCommands = (int) trim((string) fgets(STDIN));
$billing = new BillingService();
for ($i = 0; $i < $numberOfCommands; ++$i) {
    $billing->execute(trim((string) fgets(STDIN)));
}
$billing->printOutput();
