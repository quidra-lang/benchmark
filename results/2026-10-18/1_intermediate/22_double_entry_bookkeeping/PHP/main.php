<?php
declare(strict_types=1);

final class CommandError extends RuntimeException {}

enum AccountType: string
{
    case Asset = 'ASSET';
    case Liability = 'LIABILITY';
    case Equity = 'EQUITY';
    case Revenue = 'REVENUE';
    case Expense = 'EXPENSE';
    case ContraAsset = 'CONTRA_ASSET';

    public function sign(): int { return $this === self::Asset || $this === self::Expense ? 1 : -1; }
    public function group(): self { return $this === self::ContraAsset ? self::Asset : $this; }
}

enum EntryKind: string
{
    case Journal = 'journal';
    case Recurring = 'recurring';
    case Reversal = 'reversal';
    case Closing = 'closing';
    case Reopen = 'reopen';
    case Depreciation = 'depreciation';
    case Interest = 'interest';
    case Writeoff = 'writeoff';
}

function money(int $cents): string
{
    $absolute = abs($cents);
    return ($cents < 0 ? '-' : '') . sprintf('%d.%02d', intdiv($absolute, 100), $absolute % 100);
}

function parseMoney(string $text): int { return (int)substr($text, 0, -3) * 100 + (int)substr($text, -2); }

final readonly class BookDate
{
    public const LAST_NUMBER = 36524;
    private const MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    public function __construct(public int $year, public int $month, public int $day) {}

    public static function daysInMonth(int $year, int $month): int
    {
        $leap = $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
        return self::MONTH_LENGTHS[$month - 1] + ($month === 2 && $leap ? 1 : 0);
    }

    public static function parse(string $text): self
    {
        $year = (int)substr($text, 0, 4);
        $month = (int)substr($text, 5, 2);
        $day = (int)substr($text, 8, 2);
        if ($year < 2000 || $year > 2099 || $month < 1 || $month > 12 || $day < 1 || $day > self::daysInMonth($year, $month)) {
            throw new CommandError("invalid date $text");
        }
        return new self($year, $month, $day);
    }

    public function number(): int
    {
        $prior = $this->year - 1;
        $result = 365 * ($this->year - 2000) + intdiv($prior, 4) - intdiv(1999, 4)
            - intdiv($prior, 100) + intdiv(1999, 100) + intdiv($prior, 400) - intdiv(1999, 400);
        for ($month = 1; $month < $this->month; $month++) $result += self::daysInMonth($this->year, $month);
        return $result + $this->day - 1;
    }

    public function addMonths(int $count): self
    {
        $offset = $this->month - 1 + $count;
        $year = $this->year + intdiv($offset, 12);
        $month = $offset % 12 + 1;
        return new self($year, $month, min($this->day, self::daysInMonth($year, $month)));
    }

    public function __toString(): string { return sprintf('%04d-%02d-%02d', $this->year, $this->month, $this->day); }
}

final class Account
{
    public bool $active = true;
    public function __construct(public readonly string $code, public readonly AccountType $type, public readonly string $name) {}
}

final readonly class Line
{
    public function __construct(public bool $debit, public string $code, public int $amount, public ?string $partner = null) {}
    public function difference(): int { return $this->debit ? $this->amount : -$this->amount; }
    public function side(): string { return $this->debit ? 'DR' : 'CR'; }
    public function reversed(): self { return new self(!$this->debit, $this->code, $this->amount, $this->partner); }
}

final class Entry
{
    public ?string $reversedBy = null;
    public ?string $reverses = null;
    public function __construct(
        public readonly string $id,
        public readonly BookDate $date,
        public readonly EntryKind $kind,
        public readonly string $memo,
        public readonly array $lines,
        public readonly int $sequence,
    ) {}

    public function amount(): int
    {
        $total = 0;
        foreach ($this->lines as $line) if ($line->debit) $total += $line->amount;
        return $total;
    }
}

final class Template
{
    public int $uses = 0;
    public function __construct(public readonly string $name, public readonly string $memo, public readonly array $lines) {}
}

final class Draft
{
    public array $lines = [];
    public function __construct(public readonly bool $journal, public readonly string $key, public readonly ?string $date, public readonly string $memo) {}
    public function kind(): string { return $this->journal ? 'journal' : 'template'; }
}

final class Totals
{
    public int $debit = 0;
    public int $credit = 0;
    public function difference(): int { return $this->debit - $this->credit; }
    public function add(Line $line): void
    {
        if ($line->debit) $this->debit += $line->amount;
        else $this->credit += $line->amount;
    }
}

final class OpenItem
{
    public function __construct(public readonly Entry $entry, public readonly int $original, public int $remaining) {}
}

final class Settlement
{
    public array $items = [];
    public int $head = 0;
    public int $unapplied = 0;
    public function open(): array { return array_slice($this->items, $this->head); }
}

final readonly class CloseRecord
{
    public function __construct(public BookDate $date, public ?Entry $entry) {}
}

final class Books
{
    private array $accounts = [];
    private array $entries = [];
    private array $entryIds = [];
    private array $templates = [];
    private array $closes = [];
    private ?Draft $draft = null;
    private int $closeCount = 0;
    private int $depreciationCount = 0;
    private int $interestCount = 0;
    private int $writeoffCount = 0;
    private array $output = [];

    private function emit(string $format, mixed ...$arguments): void { $this->output[] = sprintf($format, ...$arguments); }
    public function render(): string { return $this->output === [] ? '' : implode("\n", $this->output) . "\n"; }
    private function account(string $code): Account { return $this->accounts[$code] ?? throw new CommandError("unknown account $code"); }
    private function entry(string $id): Entry { return $this->entryIds[$id] ?? throw new CommandError("unknown entry $id"); }

    private function requireType(string $code, AccountType $type): Account
    {
        $account = $this->account($code);
        if ($account->type !== $type) throw new CommandError("wrong type $code {$type->value}");
        return $account;
    }

    private function active(array $accounts): void
    {
        foreach ($accounts as $account) if (!$account->active) throw new CommandError("inactive account {$account->code}");
    }

    private function activeLines(array $lines): void
    {
        foreach ($lines as $line) $this->active([$this->accounts[$line->code]]);
    }

    private function closed(): string { return $this->closes === [] ? 'none' : (string)$this->closes[count($this->closes) - 1]->date; }

    private function checkClosed(BookDate $date): void
    {
        if ($this->closes !== [] && $date->number() <= $this->closes[count($this->closes) - 1]->date->number()) {
            throw new CommandError("period closed $date");
        }
    }

    private function range(string $start, string $end): array
    {
        $first = BookDate::parse($start);
        $last = BookDate::parse($end);
        if ($first->number() > $last->number()) throw new CommandError("invalid range $start $end");
        return [$first, $last];
    }

    private function orderedAccounts(): array
    {
        $result = array_values($this->accounts);
        usort($result, static fn(Account $a, Account $b): int => strcmp($a->code, $b->code));
        return $result;
    }

    private function orderedEntries(int $start = 0, int $end = BookDate::LAST_NUMBER): array
    {
        $result = array_values(array_filter($this->entries, static fn(Entry $entry): bool => $entry->date->number() >= $start && $entry->date->number() <= $end));
        usort($result, static fn(Entry $a, Entry $b): int => ($a->date->number() <=> $b->date->number()) ?: ($a->sequence <=> $b->sequence));
        return $result;
    }

    private function aggregate(int $start = 0, int $end = BookDate::LAST_NUMBER, bool $operating = false): array
    {
        $result = [];
        foreach ($this->entries as $entry) {
            if ($entry->date->number() < $start || $entry->date->number() > $end ||
                $operating && in_array($entry->kind, [EntryKind::Closing, EntryKind::Reopen], true)) continue;
            foreach ($entry->lines as $line) {
                $result[$line->code] ??= new Totals();
                $result[$line->code]->add($line);
            }
        }
        return $result;
    }

    private function balance(Account $account, int $end = BookDate::LAST_NUMBER): int
    {
        $difference = 0;
        foreach ($this->entries as $entry) {
            if ($entry->date->number() > $end) continue;
            foreach ($entry->lines as $line) if ($line->code === $account->code) $difference += $line->difference();
        }
        return $difference * $account->type->sign();
    }

    private function dailySum(Account $account, int $start, int $end): int
    {
        $total = 0;
        foreach ($this->entries as $entry) {
            if ($entry->date->number() > $end) continue;
            $change = 0;
            foreach ($entry->lines as $line) if ($line->code === $account->code) $change += $line->difference();
            $total += $change * $account->type->sign() * ($end - max($start, $entry->date->number()) + 1);
        }
        return $total;
    }

    private function parent(Account $account): ?Account
    {
        $parent = null;
        foreach ($this->accounts as $other) {
            if ($other->code !== $account->code && str_starts_with($account->code, $other->code) &&
                ($parent === null || strlen($other->code) > strlen($parent->code))) $parent = $other;
        }
        return $parent;
    }

    private function top(Account $account): Account
    {
        $root = $account;
        foreach ($this->accounts as $other) {
            if (strlen($other->code) < strlen($root->code) && str_starts_with($account->code, $other->code)) $root = $other;
        }
        return $root;
    }

    private function post(string $id, BookDate $date, EntryKind $kind, string $memo, array $lines): Entry
    {
        $entry = new Entry($id, $date, $kind, $memo, $lines, count($this->entries) + 1);
        $this->entries[] = $entry;
        $this->entryIds[$id] = $entry;
        return $entry;
    }

    private function reverse(Entry $original, BookDate $date, EntryKind $kind, string $memo): Entry
    {
        $entry = $this->post($original->id . '-R', $date, $kind, $memo, array_map(static fn(Line $line): Line => $line->reversed(), $original->lines));
        $original->reversedBy = $entry->id;
        $entry->reverses = $original->id;
        return $entry;
    }

    private function lineTotals(array $lines): Totals
    {
        $totals = new Totals();
        foreach ($lines as $line) $totals->add($line);
        return $totals;
    }

    private function settlements(Account $account, int $date): array
    {
        $result = [];
        foreach ($this->orderedEntries(end: $date) as $entry) {
            foreach ($entry->lines as $line) {
                if ($line->code !== $account->code || $line->partner === null) continue;
                $settlement = $result[$line->partner] ??= new Settlement();
                $signed = $line->difference() * $account->type->sign();
                if ($signed > 0) {
                    $applied = min($signed, $settlement->unapplied);
                    $settlement->unapplied -= $applied;
                    if ($signed > $applied) $settlement->items[] = new OpenItem($entry, $signed, $signed - $applied);
                } else {
                    $remaining = -$signed;
                    while ($remaining > 0 && $settlement->head < count($settlement->items)) {
                        $item = $settlement->items[$settlement->head];
                        $applied = min($remaining, $item->remaining);
                        $item->remaining -= $applied;
                        $remaining -= $applied;
                        if ($item->remaining === 0) $settlement->head++;
                    }
                    $settlement->unapplied += $remaining;
                }
            }
        }
        ksort($result, SORT_STRING);
        return $result;
    }

    private function section(string $heading, array $types, int $sign, array $totals, ?int $earnings = null): int
    {
        $groups = [];
        $total = $earnings ?? 0;
        foreach ($this->orderedAccounts() as $account) {
            if (!in_array($account->type, $types, true)) continue;
            $root = $this->top($account);
            $groups[$root->code] ??= ['root' => $root, 'members' => [], 'total' => 0, 'visible' => false];
            $amount = ($totals[$account->code] ?? new Totals())->difference() * $sign;
            $groups[$root->code]['members'][] = [$account, $amount];
            $groups[$root->code]['total'] += $amount;
            $groups[$root->code]['visible'] = $groups[$root->code]['visible'] || $amount !== 0;
            $total += $amount;
        }
        ksort($groups, SORT_STRING);
        $this->emit('  %s %s', $heading, money($total));
        foreach ($groups as $group) {
            if (!$group['visible']) continue;
            $root = $group['root'];
            $this->emit('    %s %s %s', $root->code, $root->name, money($group['total']));
            foreach ($group['members'] as [$account, $amount]) {
                if ($amount !== 0) $this->emit('      %s %s %s', $account->code, $account->name, money($amount));
            }
        }
        if ($earnings !== null) $this->emit('    current earnings %s', money($earnings));
        return $total;
    }

    private function postDraft(): void
    {
        $block = $this->draft ?? throw new CommandError('no open entry');
        $this->draft = null;
        $date = null;
        if ($block->journal) {
            if (isset($this->entryIds[$block->key])) throw new CommandError("duplicate entry {$block->key}");
            $date = BookDate::parse($block->date);
            $this->checkClosed($date);
        } elseif (isset($this->templates[$block->key])) {
            throw new CommandError("duplicate template {$block->key}");
        }
        if (count($block->lines) < 2) throw new CommandError("too few lines {$block->key}");
        foreach ($block->lines as $line) {
            $account = $this->account($line->code);
            if ($block->journal && !$account->active) throw new CommandError("inactive account {$line->code}");
            if ($line->amount === 0) throw new CommandError("zero amount {$line->code}");
        }
        $totals = $this->lineTotals($block->lines);
        if ($totals->debit !== $totals->credit) {
            throw new CommandError(sprintf('unbalanced %s debit %s credit %s', $block->key, money($totals->debit), money($totals->credit)));
        }
        if ($block->journal) {
            $entry = $this->post($block->key, $date, EntryKind::Journal, $block->memo, $block->lines);
            $this->emit('POST %s %s lines %d amount %s', $entry->id, $date, count($entry->lines), money($entry->amount()));
        } else {
            $this->templates[$block->key] = new Template($block->key, $block->memo, $block->lines);
            $this->emit('TEMPLATE %s lines %d amount %s', $block->key, count($block->lines), money($totals->debit));
        }
    }

    private function close(BookDate $date, string $code): void
    {
        $this->checkClosed($date);
        $equity = $this->requireType($code, AccountType::Equity);
        $this->active([$equity]);
        $totals = $this->aggregate(end: $date->number());
        $targets = array_filter($this->orderedAccounts(), static fn(Account $account): bool =>
            in_array($account->type, [AccountType::Revenue, AccountType::Expense], true) && ($totals[$account->code] ?? new Totals())->difference() !== 0);
        $this->active($targets);
        $lines = [];
        $income = 0;
        foreach ($targets as $account) {
            $difference = $totals[$account->code]->difference();
            $lines[] = new Line($difference < 0, $account->code, abs($difference));
            $income -= $difference;
        }
        if ($income !== 0) $lines[] = new Line($income < 0, $code, abs($income));
        $this->closeCount++;
        $entry = $lines === [] ? null : $this->post('CLOSE-' . $this->closeCount, $date, EntryKind::Closing, 'closing', $lines);
        $this->closes[] = new CloseRecord($date, $entry);
        if ($entry === null) $this->emit('CLOSE %s no entry', $date);
        else $this->emit('CLOSE %s entry %s lines %d net income %s', $date, $entry->id, count($lines), money($income));
    }

    private function ledger(Account $account, BookDate $start, BookDate $end): void
    {
        $running = $this->balance($account, $start->number() - 1);
        $totals = new Totals();
        $this->emit('LEDGER %s %s %s %s', $account->code, $account->name, $start, $end);
        $this->emit('  opening %s', money($running));
        foreach ($this->orderedEntries($start->number(), $end->number()) as $entry) {
            foreach ($entry->lines as $line) {
                if ($line->code !== $account->code) continue;
                $running += $line->difference() * $account->type->sign();
                $totals->add($line);
                $this->emit('  %s %s %s %s balance %s %s', $entry->date, $entry->id, $line->side(), money($line->amount), money($running), $entry->memo);
            }
        }
        $days = $end->number() - $start->number() + 1;
        $this->emit('  ending %s debits %s credits %s days %d average %s', money($running), money($totals->debit), money($totals->credit),
            $days, money(intdiv($this->dailySum($account, $start->number(), $end->number()), $days)));
    }

    private function agingLine(string $name, array $values): void
    {
        $balance = $values[0] + $values[1] + $values[2] + $values[3] - $values[4];
        $this->emit('  %s 0-30 %s 31-60 %s 61-90 %s 91+ %s unapplied %s balance %s', $name,
            money($values[0]), money($values[1]), money($values[2]), money($values[3]), money($values[4]), money($balance));
    }

    public function execute(string $text): void
    {
        $words = explode(' ', $text);
        switch ($words[0]) {
            case 'ACCOUNT':
                $code = $words[1];
                if (isset($this->accounts[$code])) throw new CommandError("duplicate account $code");
                $type = AccountType::from($words[2]);
                foreach ($this->orderedAccounts() as $other) {
                    if ((str_starts_with($code, $other->code) || str_starts_with($other->code, $code)) && $type->group() !== $other->type->group()) {
                        throw new CommandError("class mismatch $code {$other->code}");
                    }
                }
                $account = new Account($code, $type, $words[3]);
                $this->accounts[$code] = $account;
                $this->emit('ACCOUNT %s %s %s parent %s', $code, $type->value, $account->name, $this->parent($account)?->code ?? 'none');
                return;
            case 'DEACTIVATE':
                $account = $this->account($words[1]);
                if (!$account->active) throw new CommandError("already inactive {$account->code}");
                $balance = $this->balance($account);
                if ($balance !== 0) throw new CommandError("nonzero balance {$account->code} " . money($balance));
                $account->active = false;
                $this->emit('DEACTIVATE %s %s', $account->code, $account->name);
                return;
            case 'JOURNAL':
            case 'TEMPLATE':
                if ($this->draft !== null) $this->emit('DISCARD %s lines %d', $this->draft->key, count($this->draft->lines));
                $this->draft = $words[0] === 'JOURNAL' ? new Draft(true, $words[1], $words[2], $words[3]) : new Draft(false, $words[1], null, $words[2]);
                return;
            case 'DR':
            case 'CR':
                $block = $this->draft ?? throw new CommandError('no open entry');
                $block->lines[] = new Line($words[0] === 'DR', $words[1], parseMoney($words[2]), $words[3] ?? null);
                return;
            case 'POST':
                $this->postDraft();
                return;
            case 'DRAFT':
                $block = $this->draft ?? throw new CommandError('no open entry');
                $totals = $this->lineTotals($block->lines);
                $this->emit('DRAFT %s %s lines %d debit %s credit %s difference %s', $block->kind(), $block->key, count($block->lines), money($totals->debit), money($totals->credit), money($totals->difference()));
                return;
            case 'REVERSE':
                $original = $this->entry($words[1]);
                if (in_array($original->kind, [EntryKind::Reversal, EntryKind::Closing, EntryKind::Reopen], true)) throw new CommandError("cannot reverse {$original->id}");
                if ($original->reversedBy !== null) throw new CommandError("already reversed {$original->id}");
                $date = BookDate::parse($words[2]);
                if ($date->number() < $original->date->number()) throw new CommandError("reverse before entry {$original->id} {$original->date}");
                $this->checkClosed($date);
                $this->activeLines($original->lines);
                $entry = $this->reverse($original, $date, EntryKind::Reversal, $original->memo);
                $this->emit('REVERSE %s entry %s %s amount %s', $original->id, $entry->id, $date, money($entry->amount()));
                return;
            case 'RECUR':
                $template = $this->templates[$words[1]] ?? throw new CommandError("unknown template {$words[1]}");
                $date = BookDate::parse($words[2]);
                $count = (int)$words[3];
                if ($count === 0) throw new CommandError('invalid count');
                $this->checkClosed($date);
                $this->activeLines($template->lines);
                $this->emit('RECUR %s count %d', $template->name, $count);
                for ($month = 0; $month < $count; $month++) {
                    $entry = $this->post($template->name . '-' . ++$template->uses, $date->addMonths($month), EntryKind::Recurring, $template->memo, $template->lines);
                    $this->emit('  POST %s %s lines %d amount %s', $entry->id, $entry->date, count($entry->lines), money($entry->amount()));
                }
                return;
            case 'DEPRECIATE':
                $date = BookDate::parse($words[1]);
                $this->checkClosed($date);
                $asset = $this->requireType($words[2], AccountType::Asset);
                $contra = $this->requireType($words[3], AccountType::ContraAsset);
                $expense = $this->requireType($words[4], AccountType::Expense);
                $this->active([$contra, $expense]);
                $cost = $this->balance($asset, $date->number());
                $accumulated = $this->balance($contra, $date->number());
                $amount = $cost > 0 ? min(intdiv($cost, (int)$words[5]), $cost - $accumulated) : 0;
                if ($amount <= 0) throw new CommandError("nothing to depreciate {$asset->code}");
                $entry = $this->post('DEP-' . ++$this->depreciationCount, $date, EntryKind::Depreciation, 'depreciation',
                    [new Line(true, $expense->code, $amount), new Line(false, $contra->code, $amount)]);
                $this->emit('DEPRECIATE %s entry %s %s amount %s accumulated %s book %s', $asset->code, $entry->id, $date, money($amount), money($accumulated + $amount), money($cost - $accumulated - $amount));
                return;
            case 'INTEREST':
                $account = $this->account($words[1]);
                if (!in_array($account->type, [AccountType::Asset, AccountType::Liability], true)) throw new CommandError("not interest bearing {$account->code}");
                $offset = $this->requireType($words[2], $account->type === AccountType::Asset ? AccountType::Revenue : AccountType::Expense);
                [$start, $end] = $this->range($words[3], $words[4]);
                $this->checkClosed($end);
                $this->active([$account, $offset]);
                $sum = $this->dailySum($account, $start->number(), $end->number());
                $amount = intdiv($sum * (int)$words[5], 3650000);
                if ($amount <= 0) throw new CommandError("no interest {$account->code}");
                $debit = $account->type === AccountType::Asset ? $account->code : $offset->code;
                $credit = $account->type === AccountType::Asset ? $offset->code : $account->code;
                $entry = $this->post('INT-' . ++$this->interestCount, $end, EntryKind::Interest, 'interest', [new Line(true, $debit, $amount), new Line(false, $credit, $amount)]);
                $days = $end->number() - $start->number() + 1;
                $this->emit('INTEREST %s entry %s %s days %d average %s amount %s', $account->code, $entry->id, $end, $days, money(intdiv($sum, $days)), money($amount));
                return;
            case 'WRITEOFF':
                $date = BookDate::parse($words[1]);
                $this->checkClosed($date);
                $account = $this->requireType($words[2], AccountType::Asset);
                $expense = $this->requireType($words[3], AccountType::Expense);
                $this->active([$account, $expense]);
                $targets = [];
                $total = 0;
                foreach ($this->settlements($account, $date->number()) as $partner => $settlement) {
                    $amount = 0;
                    foreach ($settlement->open() as $item) if ($date->number() - $item->entry->date->number() > (int)$words[4]) $amount += $item->remaining;
                    if ($amount > 0) { $targets[$partner] = $amount; $total += $amount; }
                }
                if ($total === 0) throw new CommandError("nothing to write off {$account->code}");
                $lines = [new Line(true, $expense->code, $total)];
                foreach ($targets as $partner => $amount) $lines[] = new Line(false, $account->code, $amount, $partner);
                $entry = $this->post('WO-' . ++$this->writeoffCount, $date, EntryKind::Writeoff, 'writeoff', $lines);
                $this->emit('WRITEOFF %s entry %s %s partners %d amount %s', $account->code, $entry->id, $date, count($targets), money($total));
                foreach ($targets as $partner => $amount) $this->emit('  %s %s', $partner, money($amount));
                return;
            case 'CLOSE':
                $this->close(BookDate::parse($words[1]), $words[2]);
                return;
            case 'REOPEN':
                if ($this->closes === []) throw new CommandError('nothing to reopen');
                $record = $this->closes[count($this->closes) - 1];
                $detail = 'no entry';
                if ($record->entry !== null) {
                    $this->activeLines($record->entry->lines);
                    $detail = 'entry ' . $this->reverse($record->entry, $record->date, EntryKind::Reopen, 'reopen')->id;
                }
                array_pop($this->closes);
                $this->emit('REOPEN %s %s closed %s', $record->date, $detail, $this->closed());
                return;
            case 'LEDGER':
                $account = $this->account($words[1]);
                [$start, $end] = $this->range($words[2], $words[3]);
                $this->ledger($account, $start, $end);
                return;
            case 'ACTIVITY':
                $account = $this->account($words[1]);
                $year = (int)$words[2];
                $debit = $credit = 0;
                $this->emit('ACTIVITY %s %s %d', $account->code, $account->name, $year);
                for ($month = 1; $month <= 12; $month++) {
                    $start = (new BookDate($year, $month, 1))->number();
                    $end = (new BookDate($year, $month, BookDate::daysInMonth($year, $month)))->number();
                    $totals = $this->aggregate($start, $end)[$account->code] ?? new Totals();
                    $debit += $totals->debit;
                    $credit += $totals->credit;
                    $this->emit('  %04d-%02d debit %s credit %s balance %s', $year, $month, money($totals->debit), money($totals->credit), money($this->balance($account, $end)));
                }
                $this->emit('  total debit %s credit %s', money($debit), money($credit));
                return;
            case 'TRIAL':
                $date = BookDate::parse($words[1]);
                $totals = $this->aggregate(end: $date->number());
                $debit = $credit = 0;
                $this->emit('TRIAL %s', $date);
                foreach ($this->orderedAccounts() as $account) {
                    $difference = ($totals[$account->code] ?? new Totals())->difference();
                    if ($difference === 0) continue;
                    if ($difference > 0) $debit += $difference; else $credit -= $difference;
                    $this->emit('  %s %s %s %s', $account->code, $account->name, $difference > 0 ? 'debit' : 'credit', money(abs($difference)));
                }
                $this->emit('  total debit %s credit %s', money($debit), money($credit));
                return;
            case 'INCOME':
                [$start, $end] = $this->range($words[1], $words[2]);
                $totals = $this->aggregate($start->number(), $end->number(), operating: true);
                $this->emit('INCOME %s %s', $start, $end);
                $revenue = $this->section('REVENUE', [AccountType::Revenue], -1, $totals);
                $expense = $this->section('EXPENSE', [AccountType::Expense], 1, $totals);
                $this->emit('  NET INCOME %s', money($revenue - $expense));
                return;
            case 'BALANCE':
                $date = BookDate::parse($words[1]);
                $totals = $this->aggregate(end: $date->number());
                $earnings = 0;
                foreach ($this->accounts as $account) {
                    if (in_array($account->type, [AccountType::Revenue, AccountType::Expense], true)) $earnings -= ($totals[$account->code] ?? new Totals())->difference();
                }
                $this->emit('BALANCE %s', $date);
                $assets = $this->section('ASSETS', [AccountType::Asset, AccountType::ContraAsset], 1, $totals);
                $liabilities = $this->section('LIABILITIES', [AccountType::Liability], -1, $totals);
                $equity = $this->section('EQUITY', [AccountType::Equity], -1, $totals, $earnings);
                if ($assets === $liabilities + $equity) $this->emit('  check ok');
                else $this->emit('  check mismatch %s', money($assets - $liabilities - $equity));
                return;
            case 'ROLLUP':
                $date = BookDate::parse($words[2]);
                $targets = array_values(array_filter($this->orderedAccounts(), static fn(Account $account): bool => str_starts_with($account->code, $words[1])));
                $this->emit('ROLLUP %s %s', $words[1], $date);
                if ($targets === []) { $this->emit('  (none)'); return; }
                $totals = $this->aggregate(end: $date->number());
                $debit = $credit = 0;
                foreach ($targets as $account) {
                    $depth = $subtotal = 0;
                    foreach ($targets as $other) {
                        if ($other->code !== $account->code && str_starts_with($account->code, $other->code)) $depth++;
                        if (str_starts_with($other->code, $account->code)) $subtotal += ($totals[$other->code] ?? new Totals())->difference();
                    }
                    $own = $totals[$account->code] ?? new Totals();
                    $debit += $own->debit;
                    $credit += $own->credit;
                    $this->emit('%s%s %s own %s total %s', str_repeat(' ', 2 * (1 + $depth)), $account->code, $account->name, money($own->difference() * $account->type->sign()), money($subtotal * $account->type->sign()));
                }
                $this->emit('  postings debit %s credit %s', money($debit), money($credit));
                return;
            case 'AGING':
                $account = $this->account($words[1]);
                $date = BookDate::parse($words[2]);
                $total = array_fill(0, 5, 0);
                $this->emit('AGING %s %s %s', $account->code, $account->name, $date);
                foreach ($this->settlements($account, $date->number()) as $partner => $settlement) {
                    $items = $settlement->open();
                    if ($items === [] && $settlement->unapplied === 0) continue;
                    $values = array_fill(0, 5, 0);
                    foreach ($items as $item) {
                        $age = $date->number() - $item->entry->date->number();
                        $values[$age <= 30 ? 0 : ($age <= 60 ? 1 : ($age <= 90 ? 2 : 3))] += $item->remaining;
                    }
                    $values[4] = $settlement->unapplied;
                    for ($i = 0; $i < 5; $i++) $total[$i] += $values[$i];
                    $this->agingLine($partner, $values);
                }
                $this->agingLine('total', $total);
                return;
            case 'ITEMS':
                $account = $this->account($words[1]);
                $date = BookDate::parse($words[3]);
                $settlement = $this->settlements($account, $date->number())[$words[2]] ?? new Settlement();
                $this->emit('ITEMS %s %s %s %s', $account->code, $account->name, $words[2], $date);
                $remaining = 0;
                foreach ($settlement->open() as $item) {
                    $remaining += $item->remaining;
                    $this->emit('  %s %s amount %s open %s age %d', $item->entry->date, $item->entry->id, money($item->original), money($item->remaining), $date->number() - $item->entry->date->number());
                }
                $this->emit('  unapplied %s balance %s', money($settlement->unapplied), money($remaining - $settlement->unapplied));
                return;
            case 'ENTRY':
                $entry = $this->entry($words[1]);
                $this->emit('ENTRY %s %s %s %s', $entry->id, $entry->date, $entry->kind->value, $entry->memo);
                foreach ($entry->lines as $line) {
                    $this->emit('  %s %s %s %s%s', $line->side(), $line->code, $this->accounts[$line->code]->name, money($line->amount), $line->partner === null ? '' : ' ' . $line->partner);
                }
                $this->emit('  total %s', money($entry->amount()));
                if ($entry->reverses !== null) $this->emit('  reverses %s', $entry->reverses);
                if ($entry->reversedBy !== null) $this->emit('  reversed by %s', $entry->reversedBy);
                return;
            case 'DAYBOOK':
                [$start, $end] = $this->range($words[1], $words[2]);
                $selected = $this->orderedEntries($start->number(), $end->number());
                $this->emit('DAYBOOK %s %s', $start, $end);
                $total = 0;
                foreach ($selected as $entry) {
                    $total += $entry->amount();
                    $this->emit('  %s %s %s %s %s', $entry->date, $entry->id, $entry->kind->value, money($entry->amount()), $entry->memo);
                }
                $this->emit('  total entries %d amount %s', count($selected), money($total));
                return;
            case 'ACCOUNTS':
                $totals = $this->aggregate();
                $this->emit('ACCOUNTS');
                foreach ($this->orderedAccounts() as $account) {
                    $this->emit('  %s %s %s parent %s balance %s %s', $account->code, $account->type->value, $account->name,
                        $this->parent($account)?->code ?? 'none', money(($totals[$account->code] ?? new Totals())->difference() * $account->type->sign()), $account->active ? 'active' : 'inactive');
                }
                if ($this->accounts === []) $this->emit('  (none)');
                return;
            case 'TEMPLATES':
                $selected = $this->templates;
                ksort($selected, SORT_STRING);
                $this->emit('TEMPLATES');
                foreach ($selected as $template) $this->emit('  %s %s lines %d amount %s used %d', $template->name, $template->memo, count($template->lines), money($this->lineTotals($template->lines)->debit), $template->uses);
                if ($selected === []) $this->emit('  (none)');
                return;
            case 'STATUS':
                $inactive = count(array_filter($this->accounts, static fn(Account $account): bool => !$account->active));
                $this->emit('STATUS accounts %d inactive %d entries %d templates %d closed %s open %s', count($this->accounts), $inactive, count($this->entries), count($this->templates), $this->closed(), $this->draft?->key ?? 'none');
                return;
        }
    }

    public function process(string $line): void
    {
        try { $this->execute($line); }
        catch (CommandError $error) { $this->emit('ERROR %s', $error->getMessage()); }
    }
}

$count = (int)fgets(STDIN);
$books = new Books();
for ($i = 0; $i < $count; $i++) $books->process(rtrim((string)fgets(STDIN), "\r\n"));
echo $books->render();
