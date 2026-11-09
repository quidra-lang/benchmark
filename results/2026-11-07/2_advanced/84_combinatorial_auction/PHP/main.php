<?php

foreach (['report', 'bids_io', 'wdp_solver', 'payments', 'auctions'] as $module)
    require_once __DIR__ . "/$module.php";
const FORMATS = ['first_price', 'second_price', 'english', 'dutch', 'all_pay'];

const OUTCOMES = ['vcg', 'greedy', 'critical', 'saa'];

function allocation(array $bids, array $items, array $reserves): object
{
    usort($bids, fn($a, $b) => $a->number <=> $b->number);
    $owners = [];
    $accepted = 0;
    foreach ($bids as $b) {
        $accepted += $b->amount;
        foreach ($items as $i)
            if ($b->bundle & (1 << $i))
                $owners[$i] = $b->bidder;
    }
    $unsold = array_values(array_filter($items, fn($i) => !isset($owners[$i])));
    $retained = array_sum(array_map(fn($i) => $reserves[$i], $unsold));
    return (object) [
        'winning' => $bids,
        'owners' => $owners,
        'unsold' => $unsold,
        'accepted' => $accepted,
        'retained' => $retained,
        'welfare' => $accepted + $retained,
    ];
}

function duplicateName(array $participants): ?string
{
    $seen = [];
    foreach ($participants as $p) {
        if (isset($seen[$p['name']]))
            return $p['name'];
        $seen[$p['name']] = true;
    }
    return null;
}

function bidError(string $text, object $bidder, array $items, array $indices, array $params): array
{
    if (!preg_match('/\A[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})\z/', $text))
        return ['malformed bid', null, null];
    [$bundleText, $amountText] = explode(':', $text);
    $parts = explode('+', $bundleText);
    $mask = 0;
    foreach ($parts as $name) {
        if (!isset($indices[$name]))
            return ['unknown item ' . $name, null, null];
        $i = $indices[$name];
        if (!in_array($i, $items, true))
            return ['item not offered ' . $name, null, null];
        if ($mask & (1 << $i))
            return ['duplicate item ' . $name, null, null];
        $mask |= 1 << $i;
    }
    if (count($parts) > $params['max_bundle_size'])
        return ['bundle too large', null, null];
    $amount = (int) $amountText;
    if (!$amount)
        return ['zero value', null, null];
    foreach ($bidder->valid as $earlier)
        if ($earlier->bundle === $mask)
            return ['duplicate bundle ' . $earlier->number, null, null];
    if (count($bidder->valid) >= $params['max_bids_per_bidder'])
        return ['too many bids', null, null];
    return [null, $mask, $amount];
}

function prepareAuction(object $raw, array $reserves, array $indices, array $params): object
{
    $a = (object) [
        'name' => $raw->name,
        'items' => $raw->items,
        'bidders' => [],
        'valid' => [],
        'eligible' => [],
        'below' => [],
        'rejected' => [],
        'bidCount' => 0,
    ];
    $seen = [];
    foreach ($raw->lines as [$name, $language, $strings]) {
        $error = isset($seen[$name]) ? 'duplicate bidder' : null;
        $seen[$name] = true;
        if ($error === null && !in_array($language, ['XOR', 'OR'], true))
            $error = 'bad language ' . $language;
        $bidder = null;
        if ($error === null) {
            $bidder = (object) ['name' => $name, 'language' => $language, 'valid' => [], 'eligible' => []];
            $a->bidders[] = $bidder;
        }
        foreach ($strings as $text) {
            ++$a->bidCount;
            if ($error !== null) {
                $a->rejected[] = [$a->bidCount, $name, $error];
                continue;
            }
            [$message, $mask, $amount] = bidError($text, $bidder, $raw->items, $indices, $params);
            if ($message !== null) {
                $a->rejected[] = [$a->bidCount, $name, $message];
                continue;
            }
            $bid = new Bid($a->bidCount, $name, $mask, $amount, $language === 'XOR');
            $bidder->valid[] = $bid;
            $a->valid[] = $bid;
            $reserve = bundleReserve($mask, $reserves);
            if ($amount >= $reserve) {
                $bidder->eligible[] = $bid;
                $a->eligible[] = $bid;
            } else
                $a->below[] = [$bid, $reserve];
        }
    }
    $a->names = array_map(fn($b) => $b->name, $a->bidders);
    $a->optimal = solveWDP($a->items, $reserves, $a->eligible);
    $a->exact = allocation($a->optimal->winning, $a->items, $reserves);
    $a->order = greedyOrder($a->eligible);
    $a->greedy = allocation(greedySelect($a->order), $a->items, $reserves);
    $a->critical = criticalPayments($a->order, $a->greedy->winning, $reserves);
    $a->vcgDetails = vcgPayments($a->items, $reserves, $a->eligible, $a->optimal, $a->names);
    $a->values =
        $a->greedyValues = $a->vcgPaid = $a->vcgUtilities = $a->criticalPaid = $a->criticalUtilities = [];
    foreach ($a->names as $name) {
        $a->values[$name] = array_sum(array_map(fn($b) => $b->bidder === $name
            ? $b->amount
            : 0, $a->exact->winning));
        $a->greedyValues[$name] = array_sum(array_map(fn($b) => $b->bidder === $name
            ? $b->amount
            : 0, $a->greedy->winning));
        $a->vcgPaid[$name] = $a->vcgDetails[$name][0] ?? 0;
        $a->vcgUtilities[$name] = $a->values[$name] - $a->vcgPaid[$name];
        $a->criticalPaid[$name] = array_sum(array_map(fn($b) => $b->bidder === $name
            ? $a->critical[$b->number][0]
            : 0, $a->greedy->winning));
        $a->criticalUtilities[$name] = $a->greedyValues[$name] - $a->criticalPaid[$name];
    }
    $a->vcgRevenue = array_sum($a->vcgPaid);
    $a->criticalRevenue = array_sum($a->criticalPaid);
    return $a;
}

function ascending(object $a, array $reserves, array $names, array $params): object
{
    $increment = $params['saa_increment'];
    $choices = $eligibility = [];
    $prices = $holders = [];
    foreach ($a->bidders as $b) {
        $choices[$b->name] = auctionCandidates($b->valid, $b->language === 'XOR');
        $sizes = array_map(fn($c) => bitCount($c['bundle']), $choices[$b->name]);
        $eligibility[$b->name] = $sizes ? max($sizes) : 0;
    }
    foreach ($a->items as $i) {
        $prices[$i] = $reserves[$i];
        $holders[$i] = null;
    }
    $bidCounts = $bidRounds = $lastRounds = [];
    $state = $params['seed'];
    $lines = ["AUCTION {$a->name} increment $increment"];
    for ($round = 1; $round <= $params['round_cap']; ++$round) {
        $activities = $newByBidder = [];
        $newByItem = array_fill_keys($a->items, []);
        foreach ($a->names as $name) {
            $held = 0;
            $asking = [];
            foreach ($a->items as $i) {
                if ($holders[$i] === $name)
                    $held |= 1 << $i;
                $asking[$i] =
                    $prices[$i] + ($holders[$i] !== null && $holders[$i] !== $name ? $increment : 0);
            }
            $demanded = 0;
            $bestSurplus = 0;
            foreach ($choices[$name] as $c)
                if (bitCount($c['bundle'] | $held) <= $eligibility[$name]) {
                    $cost = 0;
                    foreach ($a->items as $i)
                        if ($c['bundle'] & (1 << $i))
                            $cost += $asking[$i];
                    $surplus = $c['value'] - $cost;
                    if ($surplus > $bestSurplus) {
                        $bestSurplus = $surplus;
                        $demanded = $c['bundle'];
                    }
                }
            $activities[$name] = bitCount($demanded | $held);
            $newByBidder[$name] = $demanded & ~$held;
            foreach ($a->items as $i)
                if ($newByBidder[$name] & (1 << $i))
                    $newByItem[$i][] = $name;
        }
        $demand = array_sum(array_map(bitCount(...), $newByBidder));
        if ($demand) {
            $text = "ROUND $round demand $demand";
            foreach ($a->names as $name)
                if ($newByBidder[$name])
                    $text .= ' ' . $name . ':' . bundleText($newByBidder[$name], $names);
            $lines[] = $text;
            foreach ($a->items as $i) {
                $bidders = $newByItem[$i];
                $n = count($bidders);
                if (!$n)
                    continue;
                if ($n >= 2) {
                    $state = (48271 * $state) % 2147483647;
                    $winner = $bidders[$state % $n];
                } else
                    $winner = $bidders[0];
                if ($holders[$i] !== null)
                    $prices[$i] += $increment;
                $holders[$i] = $winner;
                $bidCounts[$i] = ($bidCounts[$i] ?? 0) + $n;
                $bidRounds[$i] = ($bidRounds[$i] ?? 0) + 1;
                $lastRounds[$i] = $round;
            }
            $text = 'STANDING';
            foreach ($a->items as $i)
                $text .= ' ' . $names[$i] . '=' . $prices[$i] . '@' . ($holders[$i] ?? '-');
            $lines[] = $text;
        } else
            $lines[] = "ROUND $round none";
        $changed = [];
        foreach ($a->names as $name)
            if ($activities[$name] < $eligibility[$name]) {
                $eligibility[$name] = $activities[$name];
                $changed[] = $name . '=' . $eligibility[$name];
            }
        if ($changed)
            $lines[] = 'ELIGIBILITY ' . implode(' ', $changed);
        if (!$demand || $round === $params['round_cap']) {
            $reason = $demand ? 'cap' : 'quiet';
            break;
        }
    }
    $lines[] = "END rounds $round $reason";
    foreach ($a->items as $i)
        $lines[] = $holders[$i] === null
            ? "ITEM {$names[$i]} unsold reserve {$reserves[$i]}"
            : "ITEM {$names[$i]} price {$prices[$i]} holder {$holders[$i]} bids {$bidCounts[$i]} rounds {$bidRounds[$i]} last {$lastRounds[$i]}";
    $payments = $utilities = [];
    $values = $exposure = $exposed = 0;
    foreach ($a->names as $name) {
        $won = $paid = 0;
        foreach ($a->items as $i)
            if ($holders[$i] === $name) {
                $won |= 1 << $i;
                $paid += $prices[$i];
            }
        $value = valueOf($choices[$name], $won);
        $utility = $value - $paid;
        $payments[$name] = $paid;
        $utilities[$name] = $utility;
        $values += $value;
        if ($utility < 0) {
            $exposure -= $utility;
            ++$exposed;
        }
        $lines[] =
            "BIDDER $name won "
            . bundleText($won, $names)
            . " paid $paid value $value utility $utility eligibility {$eligibility[$name]}"
            . ($utility < 0 ? ' exposed' : '');
    }
    $revenue = array_sum($payments);
    $retained = 0;
    foreach ($a->items as $i)
        if ($holders[$i] === null)
            $retained += $reserves[$i];
    $welfare = $values + $retained;
    $efficiency = new Rational($welfare, $a->exact->welfare);
    $lines[] = "TOTAL revenue $revenue welfare $welfare efficiency $efficiency exposure $exposure exposed $exposed";
    return (object) [
        'lines' => $lines,
        'payments' => $payments,
        'utilities' => $utilities,
        'revenue' => $revenue,
        'retained' => $retained,
        'welfare' => $welfare,
        'rounds' => $round,
        'reason' => $reason,
        'exposure' => $exposure,
        'exposed' => $exposed,
    ];
}

function wdpLines(object $a, array $names, array $reserves): array
{
    $lines = [
        "AUCTION {$a->name} items "
            . count($a->items)
            . ' bidders '
            . count($a->bidders)
            . " bids {$a->bidCount} valid "
            . count($a->valid)
            . ' eligible '
            . count($a->eligible),
    ];
    foreach ($a->bidders as $b)
        $lines[] =
            "BIDDER {$b->name} {$b->language} valid " . count($b->valid) . ' eligible ' . count($b->eligible);
    foreach ($a->rejected as [$number, $name, $reason])
        $lines[] = "REJECT $number $name $reason";
    foreach ($a->below as [$b, $reserve])
        $lines[] = "BELOW_RESERVE {$b->number} {$b->bidder} value {$b->amount} reserve $reserve";
    foreach ($a->optimal->shares as [$i, $share, $source])
        $lines[] = "SHARE {$names[$i]} $share " . ($source === null ? 'reserve' : 'bid ' . $source);
    $lines[] = 'ROOT_BOUND ' . $a->optimal->bound;
    foreach ($a->optimal->improvements as [$nodes, $welfare, $numbers])
        $lines[] = "IMPROVE $nodes welfare $welfare bids " . numberList($numbers);
    foreach ([['OPTIMAL', 'WIN', 'UNSOLD', $a->exact], ['GREEDY', 'GWIN', 'GUNSOLD', $a->greedy]] as [
        $prefix,
        $win,
        $unsold,
        $r,
    ]) {
        if ($prefix === 'GREEDY') {
            $s = $a->optimal;
            $lines[] =
                "SEARCH nodes {$s->nodes} pruned {$s->pruned} leaves {$s->leaves} improvements "
                . count($s->improvements);
            $lines[] =
                'GREEDY_ORDER '
                . ($a->order ? implode(' ', array_map(fn($b) => $b->number, $a->order)) : '-');
        }
        $line =
            "$prefix welfare {$r->welfare} accepted {$r->accepted} retained {$r->retained} winners "
            . count($r->winning);
        if ($prefix === 'GREEDY')
            $line .= ' efficiency ' . new Rational($r->welfare, $a->exact->welfare);
        $lines[] = $line;
        foreach ($r->winning as $b) {
            $line = "$win {$b->number} {$b->bidder} " . bundleText($b->bundle, $names) . " {$b->amount}";
            if ($prefix === 'GREEDY') {
                [$critical, $rival] = $a->critical[$b->number];
                $line .= " critical $critical against " . ($rival?->number ?? '-');
            }
            $lines[] = $line;
        }
        $lines[] =
            $unsold . ' ' . ($r->unsold ? implode(' ', array_map(fn($i) => $names[$i], $r->unsold)) : '-');
    }
    foreach ($a->items as $i) {
        $demand = count(array_filter($a->eligible, fn($b) => (bool) ($b->bundle & (1 << $i))));
        $lines[] =
            "ITEM {$names[$i]} reserve {$reserves[$i]} demand $demand optimal "
            . ($a->exact->owners[$i] ?? '-')
            . ' greedy '
            . ($a->greedy->owners[$i] ?? '-');
    }
    return $lines;
}

function vcgLines(object $a): array
{
    $lines = ["AUCTION {$a->name} welfare {$a->exact->welfare}"];
    foreach ($a->names as $name) {
        if (!isset($a->vcgDetails[$name])) {
            $lines[] = "BIDDER $name lost";
            continue;
        }
        [$paid, $alternative] = $a->vcgDetails[$name];
        $won = array_map(
            fn($b) => $b->number,
            array_filter($a->exact->winning, fn($b) => $b->bidder === $name),
        );
        $lines[] =
            "BIDDER $name won "
            . numberList($won)
            . " value {$a->values[$name]} without {$alternative->welfare} alternative "
            . numberList($alternative->numbers)
            . " payment $paid utility {$a->vcgUtilities[$name]}";
    }
    $seller = $a->vcgRevenue + $a->exact->retained;
    $utilities = array_sum($a->vcgUtilities);
    $lines[] = "TOTAL revenue {$a->vcgRevenue} pay_as_bid {$a->exact->accepted} retained {$a->exact->retained} seller $seller bidders $utilities";
    foreach ($a->names as $name)
        $lines[] = "PAYMENTS $name vcg {$a->vcgPaid[$name]} pay_as_bid {$a->values[$name]} greedy {$a->greedyValues[$name]} critical {$a->criticalPaid[$name]} saa {$a->saa->payments[$name]}";
    foreach ($a->names as $name)
        $lines[] = "UTILITIES $name vcg {$a->vcgUtilities[$name]} critical {$a->criticalUtilities[$name]} saa {$a->saa->utilities[$name]}";
    return $lines;
}

function coreLines(object $a, array $reserves, array $params): array
{
    $lines = ["AUCTION {$a->name} bidders " . count($a->bidders)];
    $counts = array_fill_keys(['checked', 'skipped', ...OUTCOMES], 0);
    if (count($a->bidders) > $params['core_max_bidders']) {
        $lines[] = 'SKIPPED';
        $counts['skipped'] = 1;
        return [$lines, $counts];
    }
    $counts['checked'] = 1;
    $coalitions = coalitionWelfares($a->items, $reserves, $a->eligible, $a->names);
    $lines[] = 'COALITIONS ' . count($coalitions);
    $outcomes = [
        ['vcg', $a->vcgRevenue + $a->exact->retained, $a->vcgUtilities],
        ['greedy', $a->greedy->welfare, array_fill_keys($a->names, 0)],
        ['critical', $a->criticalRevenue + $a->greedy->retained, $a->criticalUtilities],
        ['saa', $a->saa->revenue + $a->saa->retained, $a->saa->utilities],
    ];
    foreach ($outcomes as [$name, $seller, $utilities]) {
        $lines[] =
            "OUTCOME $name seller $seller utilities "
            . implode(' ', array_map(fn($n) => $utilities[$n], $a->names));
        [$blocking, $minimal] = blockingCoalitions($coalitions, $seller, $utilities);
        foreach ($minimal as $r) {
            $c = $r->coalition;
            $members = $c->members ? implode('+', $c->members) : '-';
            $lines[] =
                "BLOCK $members welfare {$c->welfare} payoff {$r->payoff} deficit {$r->deficit} bids "
                . numberList($c->numbers);
        }
        if (!$blocking) {
            $lines[] = 'RESULT core';
            ++$counts[$name];
        } else {
            $worst = $blocking[0];
            foreach ($blocking as $r)
                if ($r->deficit > $worst->deficit)
                    $worst = $r;
            $members = $worst->coalition->members ? implode('+', $worst->coalition->members) : '-';
            $lines[] =
                'RESULT blocked '
                . count($blocking)
                . ' minimal '
                . count($minimal)
                . " max_deficit {$worst->deficit} by $members";
        }
    }
    return [$lines, $counts];
}

function summaryRow(
    string $name,
    string $format,
    int|Rational $revenue,
    int|Rational $welfare,
    int|Rational $efficiency,
): string {
    return "$name/$format,$revenue,$welfare,$efficiency";
}

function lotGroup(object $group, array $params): array
{
    $p = $group->participants;
    $reserve = (int) $group->arguments[0];
    $first = $efficient = null;
    $optimum = $reserve;
    $secondPrice = $reserve;
    foreach ($p as $i => $participant) {
        if ($participant['bid'] >= $reserve && ($first === null || $participant['bid'] > $p[$first]['bid']))
            $first = $i;
        if (
            $participant['value'] >= $reserve
            && ($efficient === null || $participant['value'] > $p[$efficient]['value'])
        )
            $efficient = $i;
        $optimum = max($optimum, $participant['value']);
    }
    if ($efficient !== null)
        foreach ($p as $i => $participant)
            if ($i !== $efficient)
                $secondPrice = max($secondPrice, $participant['value']);
    $ascending = englishAuction($p, $reserve, $params['english_increment']);
    $descending = dutchAuction($p, $reserve, $params['dutch_start'], $params['dutch_decrement']);
    $firstPrice = $first === null ? 0 : $p[$first]['bid'];
    $mechanisms = [
        [$first, $firstPrice, null],
        [$efficient, $efficient === null ? 0 : $secondPrice, null],
        [$ascending->winner, $ascending->price, $ascending->steps],
        [$descending->winner, $descending->price, $descending->steps],
        [$first, $firstPrice, null],
    ];
    $lines = [
        "LOT {$group->name} reserve $reserve bidders "
            . count($p)
            . ' efficient '
            . ($efficient === null ? '-' : $p[$efficient]['name'])
            . " optimum $optimum",
    ];
    $rows = $results = [];
    foreach (FORMATS as $index => $name) {
        [$winner, $price, $steps] = $mechanisms[$index];
        $utilities = array_fill(0, count($p), 0);
        $revenue = $price;
        if ($name === 'all_pay') {
            $revenue = 0;
            foreach ($p as $i => $participant)
                if ($participant['bid'] >= $reserve) {
                    $utilities[$i] = -$participant['bid'];
                    $revenue += $participant['bid'];
                }
        }
        if ($winner === null) {
            $welfare = $reserve;
            $line = strtoupper($name) . ' unsold';
        } else {
            $utilities[$winner] = $p[$winner]['value'] - $price;
            $welfare = $p[$winner]['value'];
            $line =
                strtoupper($name)
                . " winner {$p[$winner]['name']} price $price utility {$utilities[$winner]}";
        }
        if ($steps !== null)
            $line .= " steps $steps";
        $efficiency = new Rational($welfare, $optimum);
        $lines[] = $line . " revenue $revenue welfare $welfare efficiency $efficiency";
        if ($name === 'english') {
            $text = 'ENGLISH_DROPS';
            foreach ($p as $i => $participant)
                $text .= ' ' . $participant['name'] . '=' . ($ascending->drops[$i] ?? '-');
            $lines[] = $text;
        }
        $results[] = ['name' => $name, 'utilities' => $utilities, 'revenue' => $revenue, 'index' => $index];
        $rows[] = summaryRow($group->name, $name, $revenue, $welfare, $efficiency);
    }
    foreach ($p as $i => $participant)
        $lines[] =
            'UTILITY '
            . $participant['name']
            . ' '
            . implode(' ', array_map(fn($r) => $r['utilities'][$i], $results));
    usort($results, fn($a, $b) => $b['revenue'] <=> $a['revenue'] ?: $a['index'] <=> $b['index']);
    $lines[] = 'RANKING ' . implode(' ', array_column($results, 'name'));
    return [$lines, $rows];
}

function slotsGroup(object $group, array $rates): array
{
    $bids = $values = $group->participants;
    foreach ($bids as $i => &$p)
        $p['index'] = $i;
    unset($p);
    $values = $bids;
    usort($bids, fn($a, $b) => $b['bid'] <=> $a['bid'] ?: $a['index'] <=> $b['index']);
    usort($values, fn($a, $b) => $b['value'] <=> $a['value'] ?: $a['index'] <=> $b['index']);
    $n = count($bids);
    $k = count($rates);
    $lines = ["SLOTS {$group->name} slots $k advertisers $n"];
    $gspRevenue = $gspWelfare = $vcgRevenue = $optimum = new Rational();
    for ($rank = 0; $rank < min($n, $k); ++$rank) {
        $p = $bids[$rank];
        $rate = $rates[$rank];
        $price = gspPrice($bids, $rank);
        $payment = $rate->mul($price);
        $utility = $rate->mul($p['value'] - $price);
        $gspRevenue = $gspRevenue->add($payment);
        $gspWelfare = $gspWelfare->add($rate->mul($p['value']));
        $optimum = $optimum->add($rate->mul($values[$rank]['value']));
        $s = $rank + 1;
        $lines[] = "GSP $s {$p['name']} ctr $rate bid {$p['bid']} price $price payment $payment utility $utility";
    }
    $efficiency = $gspWelfare->div($optimum);
    $lines[] = "GSP_TOTAL revenue $gspRevenue welfare $gspWelfare efficiency $efficiency";
    for ($rank = 0; $rank < min($n, $k); ++$rank) {
        $p = $values[$rank];
        $rate = $rates[$rank];
        $payment = slotVCGPayment($values, $rates, $rank);
        $vcgRevenue = $vcgRevenue->add($payment);
        $utility = $rate->mul($p['value'])->sub($payment);
        $price = $payment->div($rate);
        $s = $rank + 1;
        $lines[] = "VCG $s {$p['name']} ctr $rate value {$p['value']} payment $payment price $price utility $utility";
    }
    $lines[] = "VCG_TOTAL revenue $vcgRevenue welfare $optimum efficiency 1";
    $violations = $deviations = 0;
    for ($rank = 1; $rank < min($n, $k + 1); ++$rank) {
        $p = $bids[$rank];
        $rate = $rates[$rank] ?? new Rational();
        $stay = $rate->mul($p['value'] - gspPrice($bids, $rank));
        $swap = $rates[$rank - 1]->mul($p['value'] - $p['bid']);
        $violated = $stay->cmp($swap) < 0;
        $violations += (int) $violated;
        $s = $rank + 1;
        $lines[] = "ENVY $s {$p['name']} stay $stay swap $swap " . ($violated ? 'violated' : 'ok');
    }
    $lines[] = $violations ? "ENVY_FREE no violations $violations" : 'ENVY_FREE yes';
    foreach ($bids as $rank => $p) {
        $current = ($rates[$rank] ?? new Rational())->mul($p['value'] - gspPrice($bids, $rank));
        for ($target = 0; $target < $k; ++$target)
            if ($target !== $rank) {
                $price = $target < $rank ? $bids[$target]['bid'] ?? 0 : gspPrice($bids, $target);
                $payoff = $rates[$target]->mul($p['value'] - $price);
                if ($payoff->cmp($current) > 0) {
                    ++$deviations;
                    $s = $rank + 1;
                    $t = $target + 1;
                    $gain = $payoff->sub($current);
                    $lines[] = "DEVIATE {$p['name']} from $s to $t gain $gain";
                }
            }
    }
    $lines[] = $deviations ? "NASH no deviations $deviations" : 'NASH yes';
    $equilibrium = !$violations && !$deviations;
    $lines[] = 'EQUILIBRIUM ' . ($equilibrium ? 'yes' : 'no');
    return [
        $lines,
        [
            summaryRow($group->name, 'gsp', $gspRevenue, $gspWelfare, $efficiency),
            summaryRow($group->name, 'vcg', $vcgRevenue, $optimum, 1),
        ],
        ['envy_free' => (int) !$violations, 'nash' => (int) !$deviations, 'equilibria' => (int) $equilibrium],
    ];
}

function addCounts(array &$totals, array $counts): void
{
    foreach ($counts as $k => $v)
        $totals[$k] = ($totals[$k] ?? 0) + $v;
}

function totalLine(string $prefix, array $keys, array $totals): string
{
    foreach ($keys as $k)
        $prefix .= ' ' . $k . ' ' . ($totals[$k] ?? 0);
    return $prefix;
}

function main(): void
{
    [$names, $reserves, $indices, $raw, $groups, $params] = readInputs();
    $wdp = $vcg = $core = $ascending = $single = [];
    $summary = ['mechanism,revenue,welfare,efficiency'];
    $wt = $vt = $ct = $at = $gt = [];
    foreach ($params['run'] as $name) {
        $a = prepareAuction($raw[$name], $reserves, $indices, $params);
        $a->saa = ascending($a, $reserves, $names, $params);
        array_push($wdp, ...wdpLines($a, $names, $reserves));
        array_push($vcg, ...vcgLines($a));
        [$coreLines, $counts] = coreLines($a, $reserves, $params);
        array_push($core, ...$coreLines);
        addCounts($ct, $counts);
        array_push($ascending, ...$a->saa->lines);
        addCounts($wt, [
            'auctions' => 1,
            'bids' => $a->bidCount,
            'valid' => count($a->valid),
            'eligible' => count($a->eligible),
            'nodes' => $a->optimal->nodes,
            'greedy_optimal' => (int) ($a->greedy->welfare === $a->exact->welfare),
        ]);
        $revenues = [
            'vcg' => $a->vcgRevenue,
            'pay_as_bid' => $a->exact->accepted,
            'greedy' => $a->greedy->accepted,
            'critical' => $a->criticalRevenue,
            'saa' => $a->saa->revenue,
        ];
        addCounts($vt, $revenues);
        addCounts($at, [
            'auctions' => 1,
            'rounds' => $a->saa->rounds,
            'capped' => (int) ($a->saa->reason === 'cap'),
            'exposed' => $a->saa->exposed,
            'exposure' => $a->saa->exposure,
        ]);
        foreach ($revenues as $format => $revenue) {
            $welfare = match ($format) {
                'vcg', 'pay_as_bid' => $a->exact->welfare,
                'saa' => $a->saa->welfare,
                default => $a->greedy->welfare,
            };
            $summary[] = summaryRow(
                $name,
                $format,
                $revenue,
                $welfare,
                new Rational($welfare, $a->exact->welfare),
            );
        }
    }
    foreach ($groups as $group) {
        addCounts($gt, [$group->kind === 'lot' ? 'lots' : 'slot_groups' => 1]);
        $p = $group->participants;
        $error = null;
        $rates = [];
        if ($group->kind === 'slots')
            foreach ($group->arguments as $text) {
                if (!preg_match('/\A[1-9][0-9]*\/[1-9][0-9]*\z/', $text)) {
                    $error = 'bad ctr ' . $text;
                    break;
                }
                [$n, $d] = array_map(intval(...), explode('/', $text));
                $rate = new Rational($n, $d);
                if ($rate->cmp(1) > 0 || $rates && $rate->cmp($rates[count($rates) - 1]) >= 0) {
                    $error = 'bad ctr ' . $text;
                    break;
                }
                $rates[] = $rate;
            }
        if ($error === null && !$p)
            $error = $group->kind === 'lot' ? 'no bidders' : 'no advertisers';
        if ($error === null && ($duplicate = duplicateName($p)) !== null)
            $error = ($group->kind === 'lot' ? 'duplicate bidder ' : 'duplicate advertiser ') . $duplicate;
        if ($error === null && $group->kind === 'lot')
            foreach ($p as $participant)
                if ($participant['bid'] > $participant['value']) {
                    $error = 'bid above value ' . $participant['name'];
                    break;
                }
        if ($error !== null) {
            $single[] = strtoupper($group->kind) . ' ' . $group->name . ' ERROR ' . $error;
            addCounts($gt, ['errors' => 1]);
            continue;
        }
        if ($group->kind === 'lot')
            [$lines, $rows] = lotGroup($group, $params);
        else {
            [$lines, $rows, $counts] = slotsGroup($group, $rates);
            addCounts($gt, $counts);
        }
        array_push($single, ...$lines);
        array_push($summary, ...$rows);
    }
    $wdp[] = totalLine('TOTAL', ['auctions', 'bids', 'valid', 'eligible', 'nodes', 'greedy_optimal'], $wt);
    $vcg[] = totalLine('OVERALL', ['vcg', 'pay_as_bid', 'greedy', 'critical', 'saa'], $vt);
    $core[] = totalLine('SUMMARY', ['checked', 'skipped', ...OUTCOMES], $ct);
    $ascending[] = totalLine('SUMMARY', ['auctions', 'rounds', 'capped', 'exposed', 'exposure'], $at);
    $single[] = totalLine(
        'SUMMARY',
        ['lots', 'slot_groups', 'errors', 'envy_free', 'nash', 'equilibria'],
        $gt,
    );
    writeReports([
        'wdp.txt' => $wdp,
        'vcg.txt' => $vcg,
        'core_check.txt' => $core,
        'ascending_log.txt' => $ascending,
        'single_item.txt' => $single,
        'summary.csv' => $summary,
    ]);
}

main();
