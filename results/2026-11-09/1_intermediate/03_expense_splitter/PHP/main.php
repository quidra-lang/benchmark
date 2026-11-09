<?php
function fail(string $message): never
{
    throw new InvalidArgumentException($message);
}

function amount_text(int $value): string
{
    return sprintf('%d.%02d', intdiv($value, 100), $value % 100);
}

function signed_text(int $value): string
{
    return $value === 0 ? '0.00' : ($value > 0 ? '+' : '-') . amount_text(abs($value));
}

function rate_text(int $value): string
{
    return sprintf('%d.%04d', intdiv($value, 10000), $value % 10000);
}

function percentage(int $part, int $whole): string
{
    return amount_text(intdiv($part * 10000, $whole)) . '%';
}

function registered_names(array $state): array
{
    $names = array_keys($state['members']);
    sort($names, SORT_STRING);
    return $names;
}

function active_names(array $state): array
{
    return array_values(array_filter(registered_names($state), fn($name) => $state['members'][$name]['active']));
}

function expense_names(array $expense): array
{
    return array_values(array_unique([...$expense['payers'], ...$expense['participants']]));
}

function expense_has(array $expense, string $name): bool
{
    return in_array($name, $expense['payers'], true) || in_array($name, $expense['participants'], true);
}

function currency_note(array $record): string
{
    return $record['currency'] === '' ? '' : ' [' . amount_text($record['amount']) . ' ' . $record['currency'] . ']';
}

function chronological(array $state): array
{
    $expenses = $state['expenses'];
    usort($expenses, fn($a, $b) => [$a['day'], $a['record']] <=> [$b['day'], $b['record']]);
    return $expenses;
}

function parse_amount(string $text): int
{
    [$whole, $fraction] = array_map('intval', explode('.', $text));
    return $whole * 100 + $fraction;
}

function amount_spec(string $text): array
{
    $parts = explode('@', $text);
    return [parse_amount($parts[0]), $parts[1] ?? ''];
}

function converted(array $state, int $amount, string $currency): int
{
    if ($currency === '') {
        return $amount;
    }
    if (!isset($state['currencies'][$currency])) {
        fail("unknown currency $currency");
    }
    return intdiv($amount * $state['currencies'][$currency] + 5000, 10000);
}

function check_member(array $state, string $name, bool $active = true): void
{
    if (!isset($state['members'][$name])) {
        fail("unknown member $name");
    }
    if ($active && !$state['members'][$name]['active']) {
        fail("inactive member $name");
    }
}

function expense_ref(array $state, string $id, bool $unfrozen = false): array
{
    if (!isset($state['expenses'][$id])) {
        fail("unknown expense $id");
    }
    $expense = $state['expenses'][$id];
    if ($unfrozen) {
        foreach ([...$expense['payers'], ...$expense['participants']] as $name) {
            if (!$state['members'][$name]['active']) {
                fail("inactive member $name");
            }
        }
    }
    return $expense;
}

function equal_distribution(int $total, int $k): array
{
    $result = [];
    for ($i = 0; $i < $k; ++$i) {
        $result[] = intdiv($total, $k) + ($i < $total % $k ? 1 : 0);
    }
    return $result;
}

function largest_remainder(int $total, array $weights): array
{
    $whole = array_sum($weights);
    $result = array_map(fn($weight) => intdiv($total * $weight, $whole), $weights);
    $order = array_keys($weights);
    usort($order, function($a, $b) use ($total, $weights, $whole) {
        $ra = $total * $weights[$a] % $whole;
        $rb = $total * $weights[$b] % $whole;
        return $ra === $rb ? $a <=> $b : $rb <=> $ra;
    });
    $remaining = $total - array_sum($result);
    for ($i = 0; $i < $remaining; ++$i) {
        ++$result[$order[$i]];
    }
    return $result;
}

function portions(array $expense): array
{
    $values = $expense['values'];
    if ($expense['mode'] === 'EQUAL') {
        return equal_distribution($expense['amount'], count($values));
    }
    if ($expense['mode'] === 'EXACT') {
        return $values;
    }
    if (in_array($expense['mode'], ['PERCENT', 'SHARES'], true)) {
        return largest_remainder($expense['amount'], $values);
    }
    $base = equal_distribution($expense['amount'] - array_sum($values), count($values));
    return array_map(fn($a, $b) => $a + $b, $base, $values);
}

function recompute(array $state, array $expense): array
{
    $expense['total'] = converted($state, $expense['amount'], $expense['currency']);
    $expense['shares'] = largest_remainder($expense['total'], portions($expense));
    $expense['contributions'] = largest_remainder($expense['total'], $expense['payments']);
    return $expense;
}

function build_expense(array $state, string $id, string $payer, string $spec, string $category, string $mode, array $parts): array
{
    check_member($state, $payer);
    [$amount, $currency] = amount_spec($spec);
    $total = converted($state, $amount, $currency);
    if ($amount === 0 || $total === 0) {
        fail('invalid amount');
    }
    $names = [];
    $values = [];
    if ($mode === 'EQUAL' && $parts === ['ALL']) {
        $names = active_names($state);
        $values = array_fill(0, count($names), 0);
    } else {
        foreach ($parts as $part) {
            $pieces = explode(':', $part);
            $name = $pieces[0];
            check_member($state, $name);
            if (in_array($name, $names, true)) {
                fail("duplicate member $name");
            }
            $value = 0;
            if (isset($pieces[1])) {
                $value = in_array($mode, ['EXACT', 'ADJUST'], true) ? parse_amount($pieces[1]) : (int) $pieces[1];
            }
            $names[] = $name;
            $values[] = $value;
        }
    }
    $sum = array_sum($values);
    $valid = match ($mode) {
        'EXACT' => $sum === $amount,
        'PERCENT' => $sum === 10000,
        'SHARES' => $sum >= 1,
        'ADJUST' => $sum <= $amount,
        default => true
    };
    if (!$valid) {
        fail('splits do not add up');
    }
    return recompute($state, ['id' => $id, 'day' => $state['day'], 'record' => 0, 'payers' => [$payer],
        'payments' => [$amount], 'amount' => $amount, 'currency' => $currency, 'category' => $category,
        'mode' => $mode, 'participants' => $names, 'values' => $values, 'total' => $total, 'shares' => [],
        'contributions' => [], 'interval' => 0, 'next' => 0, 'copies' => 0]);
}

function balances(array $state): array
{
    $result = array_fill_keys(registered_names($state), 0);
    foreach ($state['expenses'] as $expense) {
        foreach ($expense['payers'] as $i => $name) {
            $result[$name] += $expense['contributions'][$i];
        }
        foreach ($expense['participants'] as $i => $name) {
            $result[$name] -= $expense['shares'][$i];
        }
    }
    foreach ($state['settlements'] as $settlement) {
        $result[$settlement['sender']] += $settlement['total'];
        $result[$settlement['receiver']] -= $settlement['total'];
    }
    return $result;
}

function expense_net(array $expense): array
{
    $result = array_fill_keys(expense_names($expense), 0);
    foreach ($expense['payers'] as $i => $name) {
        $result[$name] += $expense['contributions'][$i];
    }
    foreach ($expense['participants'] as $i => $name) {
        $result[$name] -= $expense['shares'][$i];
    }
    return $result;
}

function greedy_transfers(array $names, array $original): array
{
    $remaining = array_combine($names,array_map(fn($name) => $original[$name],$names));
    $output = [];
    while ($remaining !== [] && min($remaining) < 0) {
        $sender = array_search(min($remaining),$remaining,true);
        $receiver = array_search(max($remaining),$remaining,true);
        $amount = min(-$remaining[$sender], $remaining[$receiver]);
        $output[] = [$sender, $receiver, $amount];
        $remaining[$sender] += $amount;
        $remaining[$receiver] -= $amount;
    }
    return $output;
}

function debts(array $state): array
{
    $result = [];
    foreach ($state['expenses'] as $expense) {
        $net = expense_net($expense);
        $borrowers = array_keys(array_filter($net, fn($value) => $value < 0));
        $lenders = array_keys(array_filter($net, fn($value) => $value > 0));
        sort($borrowers, SORT_STRING);
        sort($lenders, SORT_STRING);
        $i = 0;
        $j = 0;
        while ($i < count($borrowers) && $j < count($lenders)) {
            $sender = $borrowers[$i];
            $receiver = $lenders[$j];
            $amount = min(-$net[$sender], $net[$receiver]);
            $result[$sender][$receiver] = ($result[$sender][$receiver] ?? 0) + $amount;
            $net[$sender] += $amount;
            $net[$receiver] -= $amount;
            if ($net[$sender] === 0) {
                ++$i;
            }
            if ($net[$receiver] === 0) {
                ++$j;
            }
        }
    }
    foreach ($state['settlements'] as $settlement) {
        $a = $settlement['sender'];
        $b = $settlement['receiver'];
        $result[$a][$b] = ($result[$a][$b] ?? 0) - $settlement['total'];
    }
    return $result;
}

function net_debt(array $table, string $a, string $b): int
{
    return ($table[$a][$b] ?? 0) - ($table[$b][$a] ?? 0);
}

function category_totals(array $state): array
{
    $totals = [];
    foreach ($state['expenses'] as $expense) {
        $category = $expense['category'];
        $totals[$category] = ($totals[$category] ?? 0) + $expense['total'];
    }
    return $totals;
}

function budget_warning(array $state, string $category): array
{
    if (!isset($state['budgets'][$category])) {
        return [];
    }
    $spent = category_totals($state)[$category] ?? 0;
    $over = $spent - $state['budgets'][$category];
    return $over > 0 ? ['  WARNING ' . $category . ' over budget by ' . amount_text($over)] : [];
}

function expense_line(string $command, array $expense, bool $payers = false): string
{
    $names = $payers ? $expense['payers'] : $expense['participants'];
    $amounts = $payers ? $expense['contributions'] : $expense['shares'];
    $parts = array_map(fn($name,$amount) => $name.' '.amount_text($amount),$names,$amounts);
    return "$command $expense[id] " . amount_text($expense['total']) . currency_note($expense) . ' = ' . implode(' + ', $parts);
}

function advance_day(array &$state, int $day): array
{
    if ($day <= $state['day']) {
        fail("invalid day $day");
    }
    $output = ["DAY $day"];
    while (true) {
        $due = array_values(array_filter($state['expenses'], fn($e) => $e['interval'] > 0 && $e['next'] <= $day));
        if ($due === []) {
            break;
        }
        usort($due, fn($a, $b) => [$a['next'], $a['record']] <=> [$b['next'], $b['record']]);
        $template = $due[0];
        $id = $template['id'];
        $active = array_all(expense_names($template),fn($name) => $state['members'][$name]['active']);
        if (!$active || converted($state, $template['amount'], $template['currency']) === 0) {
            $state['expenses'][$id]['interval'] = 0;
            $state['expenses'][$id]['next'] = 0;
            $output[] = "  CANCEL $id";
            continue;
        }
        $copyId = $id . '#' . ($template['copies'] + 2);
        $copy = $template;
        $copy['id'] = $copyId;
        $copy['day'] = $template['next'];
        $copy['record'] = ++$state['serial'];
        $copy['interval'] = 0;
        $copy['next'] = 0;
        $copy['copies'] = 0;
        $copy = recompute($state, $copy);
        $state['expenses'][$copyId] = $copy;
        $state['used'][$copyId] = true;
        ++$state['expenses'][$id]['copies'];
        $state['expenses'][$id]['next'] += $template['interval'];
        $output[] = "  RECUR $copyId " . amount_text($copy['total']);
        $output = [...$output, ...budget_warning($state, $copy['category'])];
    }
    $state['day'] = $day;
    return $output;
}

function vector_less(array $a, array $b): bool
{
    for ($i = 0; $i < min(count($a), count($b)); ++$i) {
        if ($a[$i] !== $b[$i]) {
            return $a[$i] < $b[$i];
        }
    }
    return count($a) < count($b);
}

function optimal_groups(array $names, array $bal): array
{
    $n = count($names);
    $limit = 1 << $n;
    $sums = array_fill(0, $limit, 0);
    $bitIndex = [];
    for ($i = 0; $i < $n; ++$i) {
        $bitIndex[1 << $i] = $i;
    }
    for ($mask = 1; $mask < $limit; ++$mask) {
        $bit = $mask & -$mask;
        $sums[$mask] = $sums[$mask ^ $bit] + $bal[$names[$bitIndex[$bit]]];
    }
    $memo = array_fill(0, $limit, -1);
    $memo[0] = 0;
    $best = function($mask) use (&$best, &$memo, $sums) {
        if ($memo[$mask] >= 0) {
            return $memo[$mask];
        }
        $first = $mask & -$mask;
        $value = 0;
        for ($subset = $mask; $subset !== 0; $subset = ($subset - 1) & $mask) {
            if (($subset & $first) !== 0 && $sums[$subset] === 0) {
                $value = max($value, 1 + $best($mask ^ $subset));
            }
        }
        return $memo[$mask] = $value;
    };
    $groups = [];
    $mask = $limit - 1;
    while ($mask !== 0) {
        $first = $mask & -$mask;
        $selected = 0;
        $selectedIndices = [];
        $target = $best($mask);
        for ($subset = $mask; $subset !== 0; $subset = ($subset - 1) & $mask) {
            if (($subset & $first) !== 0 && $sums[$subset] === 0 && 1 + $best($mask ^ $subset) === $target) {
                $indices = [];
                for ($i = 0; $i < $n; ++$i) {
                    if (($subset & (1 << $i)) !== 0) {
                        $indices[] = $i;
                    }
                }
                if ($selected === 0 || vector_less($indices, $selectedIndices)) {
                    $selected = $subset;
                    $selectedIndices = $indices;
                }
            }
        }
        $groups[] = array_map(fn($i) => $names[$i], $selectedIndices);
        $mask ^= $selected;
    }
    return $groups;
}

function ledger_summary(string $command, array $args, string $line, array $state): array
{
    $output = [$command];
    $names = registered_names($state);
    $expenses = chronological($state);
    if ($command === 'BALANCES') {
        $bal = balances($state);
        foreach (active_names($state) as $name) {
            $output[] = '  ' . $name . ' ' . signed_text($bal[$name]);
        }
    } elseif ($command === 'OWES') {
        $name = $args[0];
        check_member($state, $name, false);
        $output[0] = "OWES $name";
        $table = debts($state);
        foreach ($names as $other) {
            if ($other === $name) {
                continue;
            }
            $amount = net_debt($table, $name, $other);
            if ($amount > 0) {
                $output[] = "  $name owes $other " . amount_text($amount);
            } elseif ($amount < 0) {
                $output[] = "  $other owes $name " . amount_text(-$amount);
            }
        }
    } elseif ($command === 'HISTORY') {
        $name = $args[0];
        check_member($state, $name, false);
        $output[0] = "HISTORY $name";
        $records = [];
        foreach ($expenses as $expense) {
            if (expense_has($expense, $name)) {
                $records[] = [$expense['day'], $expense['record'], $expense['id'], expense_net($expense)[$name]];
            }
        }
        foreach ($state['settlements'] as $s) {
            if ($name === $s['sender'] || $name === $s['receiver']) {
                $records[] = [$s['day'], $s['record'], $s['sender'] . '->' . $s['receiver'], $name === $s['sender'] ? $s['total'] : -$s['total']];
            }
        }
        usort($records, fn($a, $b) => [$a[0], $a[1]] <=> [$b[0], $b[1]]);
        $running = 0;
        foreach ($records as [$day, $record, $label, $change]) {
            $running += $change;
            $output[] = "  day $day $label " . signed_text($change) . ' balance ' . signed_text($running);
        }
    } elseif ($command === 'MATRIX') {
        $active = active_names($state);
        if ($active === []) {
            return ['MATRIX', '  (none)'];
        }
        $table = debts($state);
        $cells = [];
        $left = max(array_map('strlen', $active));
        $width = $left;
        foreach ($active as $a) {
            $row = [];
            foreach ($active as $b) {
                $cell = $a === $b ? '-' : amount_text(max(0, net_debt($table, $a, $b)));
                $width = max($width, strlen($cell));
                $row[] = $cell;
            }
            $cells[] = $row;
        }
        $output[] = str_repeat(' ', $left) . implode('', array_map(fn($name) => '  ' . str_pad($name, $width, ' ', STR_PAD_LEFT), $active));
        foreach ($active as $i => $name) {
            $output[] = str_pad($name, $left) . implode('', array_map(fn($cell) => '  ' . str_pad($cell, $width, ' ', STR_PAD_LEFT), $cells[$i]));
        }
    } elseif ($command === 'CATEGORY') {
        $totals = category_totals($state);
        $whole = array_sum($totals);
        $categories = array_keys($totals);
        usort($categories, fn($a, $b) => $totals[$a] === $totals[$b] ? strcmp($a, $b) : $totals[$b] <=> $totals[$a]);
        foreach ($categories as $category) {
            $total = $totals[$category];
            $output[] = "  $category " . amount_text($total) . ' ' . percentage($total, $whole);
            $shares = array_fill_keys($names, 0);
            foreach ($expenses as $expense) {
                if ($expense['category'] === $category) {
                    foreach ($expense['participants'] as $i => $name) {
                        $shares[$name] += $expense['shares'][$i];
                    }
                }
            }
            $people = array_keys(array_filter($shares, fn($value) => $value > 0));
            usort($people, fn($a, $b) => $shares[$a] === $shares[$b] ? strcmp($a, $b) : $shares[$b] <=> $shares[$a]);
            foreach ($people as $name) {
                $output[] = "    $name " . amount_text($shares[$name]) . ' ' . percentage($shares[$name], $total);
            }
        }
    } elseif ($command === 'BUDGETS') {
        $totals = category_totals($state);
        $categories = array_keys($state['budgets']);
        sort($categories, SORT_STRING);
        foreach ($categories as $category) {
            $spent = $totals[$category] ?? 0;
            $budget = $state['budgets'][$category];
            $label = $spent <= $budget ? 'left' : 'over';
            $output[] = "  $category spent " . amount_text($spent) . ' budget ' . amount_text($budget) . ' used ' . percentage($spent, $budget) . " $label " . amount_text(abs($budget - $spent));
        }
    } elseif ($command === 'TOTALS') {
        foreach ($names as $name) {
            $paid = 0;
            $share = 0;
            $sent = 0;
            $received = 0;
            foreach ($expenses as $expense) {
                $payer = array_search($name,$expense['payers'],true);
                $participant = array_search($name,$expense['participants'],true);
                if ($payer !== false) $paid += $expense['contributions'][$payer];
                if ($participant !== false) $share += $expense['shares'][$participant];
            }
            foreach ($state['settlements'] as $s) {
                if ($s['sender'] === $name) {
                    $sent += $s['total'];
                }
                if ($s['receiver'] === $name) {
                    $received += $s['total'];
                }
            }
            $output[] = "  $name paid " . amount_text($paid) . ' share ' . amount_text($share) . ' sent ' . amount_text($sent) . ' received ' . amount_text($received);
        }
        $currencies = array_values(array_unique(array_filter(array_column($expenses, 'currency'), fn($code) => $code !== '')));
        sort($currencies, SORT_STRING);
        foreach ($currencies as $currency) {
            $selected = array_filter($expenses, fn($e) => $e['currency'] === $currency);
            $output[] = "  currency $currency expenses " . count($selected) . ' amount ' . amount_text(array_sum(array_column($selected, 'amount'))) . ' base ' . amount_text(array_sum(array_column($selected, 'total')));
        }
        $output[] = '  expenses ' . count($expenses) . ' total ' . amount_text(array_sum(array_column($expenses, 'total'))) . ' settlements ' . count($state['settlements']) . ' total ' . amount_text(array_sum(array_column($state['settlements'], 'total')));
    } elseif ($command === 'MEMBERS') {
        foreach ($names as $name) {
            $member = $state['members'][$name];
            $status = $member['active'] ? 'active' : 'left';
            $count = count(array_filter($expenses, fn($e) => expense_has($e, $name)));
            $output[] = "  $name $status day $member[day] expenses $count";
        }
    } elseif ($command === 'EXPENSES') {
        $output[0] = $line;
        $mode = $args[0];
        if ($mode === 'MEMBER') {
            check_member($state, $args[1], false);
        }
        $selected = array_values(array_filter($expenses, function($e) use ($mode, $args) {
            return match ($mode) {
                'ALL' => true,
                'CATEGORY' => $e['category'] === $args[1],
                'MEMBER' => expense_has($e, $args[1]),
                'DAYS' => $e['day'] >= (int) $args[1] && $e['day'] <= (int) $args[2]
            };
        }));
        foreach ($selected as $e) {
            $output[] = "  day $e[day] $e[id] $e[category] " . amount_text($e['total']) . ' by ' . implode(',', $e['payers']);
        }
        $output[] = '  count ' . count($selected) . ' total ' . amount_text(array_sum(array_column($selected, 'total')));
    } elseif ($command === 'PERIODS') {
        $k = (int) $args[0];
        $output[0] = "PERIODS $k";
        $groups = [];
        foreach ($expenses as $e) {
            $groups[intdiv($e['day'] - 1, $k)][] = $e;
        }
        ksort($groups, SORT_NUMERIC);
        foreach ($groups as $i => $group) {
            $output[] = '  days ' . ($i * $k + 1) . '-' . ($i * $k + $k) . ' expenses ' . count($group) . ' total ' . amount_text(array_sum(array_column($group, 'total')));
        }
    } elseif ($command === 'SHOW') {
        $e = expense_ref($state, $args[0]);
        $output[0] = "SHOW $e[id]";
        $output[] = "  day $e[day] category $e[category] mode $e[mode] total " . amount_text($e['total']) . currency_note($e);
        foreach ($e['payers'] as $i => $name) {
            $output[] = "  paid $name " . amount_text($e['contributions'][$i]);
        }
        foreach ($e['participants'] as $i => $name) {
            $value = $e['values'][$i];
            $suffix = match ($e['mode']) {
                'EXACT' => ' ' . amount_text($value),
                'PERCENT' => ' ' . amount_text($value) . '%',
                'SHARES' => " $value/" . array_sum($e['values']),
                'ADJUST' => ' +' . amount_text($value),
                default => ''
            };
            $output[] = "  share $name " . amount_text($e['shares'][$i]) . $suffix;
        }
        if ($e['interval'] > 0) {
            $output[] = "  recurring interval $e[interval] next $e[next]";
        }
    } elseif ($command === 'SIMPLIFY') {
        $bal = balances($state);
        $selected = array_values(array_filter($names, fn($name) => $bal[$name] !== 0));
        if ($args[0] === 'GREEDY') {
            $transfers = greedy_transfers($selected, $bal);
            $output[0] = 'SIMPLIFY GREEDY transfers ' . count($transfers);
            foreach ($transfers as [$sender, $receiver, $value]) {
                $output[] = "  $sender -> $receiver " . amount_text($value);
            }
        } else {
            if (count($selected) > 12) {
                fail('too many members');
            }
            $groups = optimal_groups($selected, $bal);
            $transfers = array_map(fn($group) => greedy_transfers($group, $bal), $groups);
            $count = array_sum(array_map('count', $transfers));
            $output[0] = "SIMPLIFY OPTIMAL transfers $count groups " . count($groups);
            foreach ($groups as $i => $group) {
                $output[] = '  group ' . implode(' ', $group);
                foreach ($transfers[$i] as [$sender, $receiver, $value]) {
                    $output[] = "    $sender -> $receiver " . amount_text($value);
                }
            }
        }
    }
    if (in_array($command, ['BALANCES', 'OWES', 'HISTORY', 'CATEGORY', 'BUDGETS', 'MEMBERS', 'PERIODS'], true) && count($output) === 1) {
        $output[] = '  (none)';
    }
    return $output;
}

function execute(string $line, array &$state): array
{
    $tokens = explode(' ', $line);
    $command = array_shift($tokens);
    $args = $tokens;
    if ($command === 'DAY') {
        return advance_day($state, (int) $args[0]);
    }
    if ($command === 'MEMBER') {
        $name = $args[0];
        if (isset($state['members'][$name]) && $state['members'][$name]['active']) {
            fail("duplicate member $name");
        }
        $label = isset($state['members'][$name]) ? 'rejoined' : 'joined';
        $state['members'][$name] = ['active' => true, 'day' => $state['day']];
        return ["MEMBER $name $label"];
    }
    if ($command === 'LEAVE') {
        $name = $args[0];
        check_member($state, $name);
        if (balances($state)[$name] !== 0) {
            fail("member has a balance $name");
        }
        $state['members'][$name] = ['active' => false, 'day' => $state['day']];
        return ["LEAVE $name"];
    }
    if ($command === 'CURRENCY') {
        [$currency, $rate] = [$args[0], (int) $args[1]];
        $suffix = isset($state['currencies'][$currency]) ? ' was ' . rate_text($state['currencies'][$currency]) : '';
        $state['currencies'][$currency] = $rate;
        return ["CURRENCY $currency " . rate_text($rate) . $suffix];
    }
    if ($command === 'EXPENSE' || $command === 'EDIT') {
        [$id, $payer, $spec, $category, $mode] = array_slice($args, 0, 5);
        if ($command === 'EXPENSE') {
            if (isset($state['used'][$id])) {
                fail("duplicate id $id");
            }
        } else {
            $original = expense_ref($state, $id, true);
        }
        $expense = build_expense($state, $id, $payer, $spec, $category, $mode, array_slice($args, 5));
        if ($command === 'EDIT') {
            foreach (['day', 'record', 'interval', 'next', 'copies'] as $key) {
                $expense[$key] = $original[$key];
            }
        } else {
            $expense['record'] = ++$state['serial'];
            $state['used'][$id] = true;
        }
        $state['expenses'][$id] = $expense;
        return [expense_line($command, $expense), ...budget_warning($state, $category)];
    }
    if ($command === 'PAYERS') {
        $expense = expense_ref($state, $args[0], true);
        $names = [];
        $payments = [];
        foreach (array_slice($args, 1) as $part) {
            [$name, $amount] = explode(':', $part);
            check_member($state, $name);
            if (in_array($name, $names, true)) {
                fail("duplicate member $name");
            }
            $names[] = $name;
            $payments[] = parse_amount($amount);
        }
        if (array_sum($payments) !== $expense['amount']) {
            fail('payers do not add up');
        }
        $expense['payers'] = $names;
        $expense['payments'] = $payments;
        $expense['contributions'] = largest_remainder($expense['total'], $payments);
        $state['expenses'][$expense['id']] = $expense;
        return [expense_line($command, $expense, true)];
    }
    if ($command === 'DELETE') {
        expense_ref($state, $args[0], true);
        unset($state['expenses'][$args[0]]);
        return ["DELETE $args[0]"];
    }
    if ($command === 'RECURRING') {
        $expense = expense_ref($state, $args[0]);
        $interval = (int) $args[1];
        $expense['interval'] = $interval;
        $expense['next'] = $interval === 0 ? 0 : $state['day'] + $interval;
        $state['expenses'][$expense['id']] = $expense;
        return [$interval === 0 ? "RECURRING $expense[id] stopped" : "RECURRING $expense[id] interval $interval next $expense[next]"];
    }
    if ($command === 'SETTLE') {
        [$sender, $receiver, $spec] = $args;
        check_member($state, $sender);
        check_member($state, $receiver);
        if ($sender === $receiver) {
            fail("same member $sender");
        }
        [$amount, $currency] = amount_spec($spec);
        $total = converted($state, $amount, $currency);
        if ($amount === 0 || $total === 0) {
            fail('invalid amount');
        }
        $settlement = ['day' => $state['day'], 'record' => ++$state['serial'], 'sender' => $sender,
            'receiver' => $receiver, 'amount' => $amount, 'currency' => $currency, 'total' => $total];
        $state['settlements'][] = $settlement;
        return ["SETTLE $sender -> $receiver " . amount_text($total) . currency_note($settlement)];
    }
    if ($command === 'BUDGET') {
        $category = $args[0];
        $amount = parse_amount($args[1]);
        if ($amount === 0) {
            unset($state['budgets'][$category]);
            return ["BUDGET $category removed"];
        }
        $state['budgets'][$category] = $amount;
        return ["BUDGET $category " . amount_text($amount)];
    }
    return ledger_summary($command, $args, $line, $state);
}

$state = ['day' => 1, 'serial' => 0, 'members' => [], 'currencies' => [], 'expenses' => [],
    'used' => [], 'settlements' => [], 'budgets' => []];
$count = (int) fgets(STDIN);
for ($i = 0; $i < $count; ++$i) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        foreach (execute($line, $state) as $output) {
            echo $output, "\n";
        }
    } catch (InvalidArgumentException $exception) {
        echo 'ERROR ', $exception->getMessage(), "\n";
    }
}
