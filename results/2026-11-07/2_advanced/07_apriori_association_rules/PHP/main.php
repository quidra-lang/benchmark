<?php
require __DIR__ . '/baskets.php';
require __DIR__ . '/apriori.php';
require __DIR__ . '/fpgrowth.php';
require __DIR__ . '/rules.php';
require __DIR__ . '/report.php';

function names(array $map): array { $names = array_keys($map); usort($names,fn($a,$b) => strcmp((string)$a,(string)$b)); return $names; }
function read_params(): array {
    $params = [];
    foreach (file('input/params.txt',FILE_IGNORE_NEW_LINES) as $line) { [$key,$value] = explode(' ',$line); $params[$key] = str_contains($value,'/') ? Fraction::parse($value) : (int)$value; }
    return $params;
}
class Data {
    public array $errors = [], $products = [], $transactions = [], $baskets = [], $sets = [], $extended = [], $taxonomy = [], $categories = [], $customers = [];
    public int $itemRows, $transactionLines, $adopted = 0, $rejected = 0, $duplicates = 0, $firstDay, $lastDay;
    public function __construct() {
        $rows = read_records('items.csv'); $this->itemRows = count($rows);
        foreach ($rows as $index => [$name,$category,$price]) {
            $reason = isset($this->products[$name]) ? "duplicate item $name" : ((int)$price === 0 ? "bad price $price" : null);
            if ($reason !== null) $this->errors[] = 'items.csv line ' . ($index + 2) . ": $reason"; else { $this->products[$name] = new Product($name,$category,(int)$price); $this->taxonomy[$name] = $category; $this->categories[$category] = true; }
        }
        $rows = read_records('transactions.csv'); $this->transactionLines = count($rows); $seen = []; $current = null;
        foreach ($rows as $index => [$tid,$customer,$day,$item]) {
            $reason = null; $day = (int)$day;
            if ($current !== null && $current->tid !== $tid && isset($seen[$tid])) $reason = "tid $tid not contiguous";
            else {
                if (!isset($seen[$tid])) { $current = new Transaction($tid,$customer,$day); $seen[$tid] = true; $this->transactions[] = $current; }
                if ($current->customer !== $customer) $reason = "tid $tid customer $customer differs from $current->customer";
                elseif ($current->day !== $day) $reason = "tid $tid day $day differs from $current->day";
                elseif (!isset($this->products[$item])) $reason = "unknown item $item";
            }
            if ($reason !== null) { $this->errors[] = 'transactions.csv line ' . ($index + 2) . ": $reason"; $this->rejected++; }
            else { $this->adopted++; if ($current->add($item)) $this->duplicates++; }
        }
        foreach ($this->transactions as $transaction) if ($transaction->counts) {
            $this->baskets[] = $transaction; $this->sets[] = array_fill_keys($transaction->products(),true); $this->extended[] = extended_basket($transaction->products(),$this->taxonomy); $this->customers[$transaction->customer][] = $transaction;
        }
        $days = array_map(fn($basket) => $basket->day,$this->baskets); $this->firstDay = min($days); $this->lastDay = max($days);
    }
}
function apriori(array $baskets, array $universe, int $minimum, int $maximum, ?array $taxonomy = null): array {
    sort($universe,SORT_STRING); $candidates = array_map(fn($item) => [$item],$universe); $levels = []; $frequent = [];
    for ($size = 1; $size <= $maximum; $size++) {
        if ($size === 1) { $joined = count($universe); $excluded = $pruned = 0; }
        else { if (!$previous) break; [$joined,$excluded,$pruned,$candidates] = generate_candidates($previous,$size,$taxonomy); }
        $counts = count_supports($baskets,$candidates); $level = []; $previous = [];
        foreach ($candidates as $items) { $key = set_key($items); if ($counts[$key] >= $minimum) { $level[$key] = [$items,$counts[$key]]; $frequent[$key] = [$items,$counts[$key]]; $previous[] = $items; } }
        uasort($level,fn($a,$b) => compare_sets($a[0],$b[0])); $levels[] = ['size' => $size,'candidates' => $joined,'excluded' => $excluded,'pruned' => $pruned,'counted' => count($candidates),'frequent' => $level];
    }
    return compact('levels','frequent');
}
function subsets(array $items): array {
    $result = [];
    for ($mask = 0; $mask < (1 << count($items)); $mask++) { $subset = []; foreach ($items as $i => $item) if ($mask & (1 << $i)) $subset[] = $item; $result[] = $subset; }
    return $result;
}
function count_in(array $frequent, array $items, int $total): int { return $items ? $frequent[set_key($items)][1] : $total; }
function make_rules(array $result, int $total, array $params, ?array $products = null): array {
    $frequent = $result['frequent']; $generated = 0; $rules = [];
    foreach ($frequent as [$items,$count]) {
        if (count($items) < 2 || ($products !== null && count(array_filter($items,fn($item) => !isset($products[$item]))) === 0)) continue;
        foreach (subsets($items) as $first) {
            if (!$first || count($first) === count($items)) continue; $generated++; $second = array_values(array_diff($items,$first));
            $rule = new Rule($items,$first,$second,$count,$total,count_in($frequent,$first,$total),count_in($frequent,$second,$total));
            if (!meets_thresholds($rule->confidence,$rule->lift,$params)) continue;
            $best = new Fraction(0);
            foreach (subsets($first) as $subset) {
                if (count($subset) === count($first)) continue; $union = [...$subset,...$second]; sort($union,SORT_STRING);
                $confidence = new Fraction(count_in($frequent,$union,$total),count_in($frequent,$subset,$total)); if ($confidence->compare($best) > 0) $best = $confidence;
            }
            $rule->improvement = $rule->confidence->subtract($best); $rules[] = $rule;
        }
    }
    usort($rules,'compare_rules'); foreach ($rules as $index => $rule) $rule->rank = $index + 1;
    return ['generated' => $generated,'rules' => $rules,'productive' => count(array_filter($rules,fn($rule) => $rule->improvement->numerator > 0))];
}
function classifications(array $frequent, int $total): array {
    $closed = $maximal = array_fill_keys(array_keys($frequent),true); $generators = [];
    foreach ($frequent as [$items,$count]) {
        $generator = true;
        foreach (subsets($items) as $subset) {
            if (count($subset) === count($items)) continue;
            if (count_in($frequent,$subset,$total) === $count) $generator = false;
            if (!$subset) continue; $key = set_key($subset); $maximal[$key] = false; if ($frequent[$key][1] === $count) $closed[$key] = false;
        }
        if ($generator) $generators[set_key($items)] = [$items,$count];
    }
    $select = fn($flags) => array_filter($frequent,fn($key) => $flags[$key],ARRAY_FILTER_USE_KEY);
    return ['closed' => $select($closed),'maximal' => $select($maximal),'generators' => $generators];
}
function median(array $values): Fraction { sort($values,SORT_NUMERIC); $middle = intdiv(count($values),2); return count($values) % 2 ? new Fraction($values[$middle]) : new Fraction($values[$middle - 1] + $values[$middle],2); }
function purchase_patterns(Data $data, array $params): array {
    $days = []; $buyers = array_fill_keys(array_keys($data->products),0); $multiDay = 0;
    foreach ($data->customers as $customer => $baskets) {
        $customerDays = [];
        foreach ($baskets as $basket) { $customerDays[$basket->day] = true; foreach ($basket->counts as $item => $_) $days[$customer][$item][$basket->day] = true; }
        if (count($customerDays) >= 2) $multiDay++;
        foreach ($days[$customer] as $item => $set) { $list = array_keys($set); sort($list,SORT_NUMERIC); $days[$customer][$item] = $list; $buyers[$item]++; }
    }
    $pairs = $intervals = $repeatCustomers = [];
    foreach ($days as $purchases) {
        foreach ($purchases as $first => $firstDays) {
            if (count($firstDays) >= 2) { $repeatCustomers[$first] = ($repeatCustomers[$first] ?? 0) + 1; for ($i = 1; $i < count($firstDays); $i++) $intervals[$first][] = $firstDays[$i] - $firstDays[$i - 1]; }
            foreach ($purchases as $second => $secondDays) {
                if ($firstDays[0] >= $secondDays[count($secondDays) - 1]) continue; $gap = $secondDays[count($secondDays) - 1] - $firstDays[0]; $j = 0;
                foreach ($firstDays as $day) { while ($j < count($secondDays) && $secondDays[$j] <= $day) $j++; if ($j < count($secondDays)) $gap = min($gap,$secondDays[$j] - $day); }
                $key = "$first+$second"; if (!isset($pairs[$key])) $pairs[$key] = [$first,$second,[]]; $pairs[$key][2][] = $gap;
            }
        }
    }
    $sequences = [];
    foreach ($pairs as [$first,$second,$gaps]) {
        $count = count($gaps); if ($count < $params['sequence_min_support']) continue;
        $sequences[] = ['first' => $first,'second' => $second,'count' => $count,'base' => $buyers[$first],'confidence' => new Fraction($count,$buyers[$first]),'lift' => new Fraction($count * count($data->customers),$buyers[$first] * $buyers[$second]),'gap' => median($gaps)];
    }
    usort($sequences,fn($a,$b) => ($b['count'] <=> $a['count']) ?: $b['confidence']->compare($a['confidence']) ?: strcmp($a['first'],$b['first']) ?: strcmp($a['second'],$b['second']));
    $repeats = [];
    foreach ($intervals as $item => $list) $repeats[] = ['item' => $item,'customers' => $repeatCustomers[$item],'count' => count($list),'min' => min($list),'max' => max($list),'mean' => new Fraction(array_sum($list),count($list)),'median' => median($list)];
    usort($repeats,fn($a,$b) => $a['mean']->compare($b['mean']) ?: strcmp($a['item'],$b['item']));
    return ['buyers' => $buyers,'pairs' => count($pairs),'multiDay' => $multiDay,'sequences' => $sequences,'repeats' => $repeats];
}
class SupportCounter {
    public array $cache = [];
    public function __construct(public array $baskets) {}
    public function count(array $items): int { if (!$items) return count($this->baskets); sort($items,SORT_STRING); $key = set_key($items); if (!isset($this->cache[$key])) { $count = 0; foreach ($this->baskets as $basket) if (contains($basket,$items)) $count++; $this->cache[$key] = $count; } return $this->cache[$key]; }
}
function recommend(array $atHand, array $candidates, int $top): array {
    $selected = [];
    foreach ($candidates as $item) if (!isset($atHand[$item]) && !in_array($item,$selected,true)) { $selected[] = $item; if (count($selected) === $top) break; }
    return $selected;
}
function rule_recommendation(array $atHand, array $rules, int $top): array { $candidates = []; foreach ($rules as $rule) if (count($rule->consequent) === 1 && contains($atHand,$rule->antecedent)) $candidates[] = $rule->consequent[0]; return recommend($atHand,$candidates,$top); }
function validate_periods(Data $data, array $params): array {
    $train = $test = [];
    foreach ($data->baskets as $index => $basket) { if ($basket->day <= $params['split_day']) $train[] = $data->sets[$index]; else $test[] = $data->sets[$index]; }
    $universe = names($data->products); $training = apriori($train,$universe,$params['train_min_support'],$params['max_size']); $testing = apriori($test,$universe,$params['test_min_support'],$params['max_size']);
    $trainRules = make_rules($training,count($train),$params)['rules']; $testRules = make_rules($testing,count($test),$params)['rules']; $testCounter = new SupportCounter($test); $trainCounter = new SupportCounter($train);
    $verdicts = $known = []; $totals = ['HOLD' => 0,'FAIL' => 0,'UNSEEN' => 0];
    foreach ($trainRules as $rule) {
        $a = $testCounter->count($rule->antecedent); $b = $testCounter->count($rule->consequent); $c = $testCounter->count($rule->itemset); $confidence = $lift = null;
        if ($a === 0 || $b === 0) $verdict = 'UNSEEN'; else { $confidence = new Fraction($c,$a); $lift = new Fraction(count($test) * $c,$a * $b); $verdict = meets_thresholds($confidence,$lift,$params) ? 'HOLD' : 'FAIL'; }
        $totals[$verdict]++; $verdicts[] = [$rule,$a,$c,$confidence,$lift,$verdict]; $known[set_key($rule->antecedent) . '>' . set_key($rule->consequent)] = true;
    }
    $emerging = array_values(array_filter($testRules,fn($rule) => !isset($known[set_key($rule->antecedent) . '>' . set_key($rule->consequent)])));
    $popular = $universe; usort($popular,fn($a,$b) => ($trainCounter->count([$b]) <=> $trainCounter->count([$a])) ?: strcmp($a,$b));
    $evaluations = []; $held = $hits = array_fill_keys($universe,0); $total = [0,0,0,0,0];
    foreach ($test as $basket) {
        $size = count($basket); if ($size < 2) continue;
        foreach ($basket as $item => $_) {
            $atHand = $basket; unset($atHand[$item]); $recommendation = rule_recommendation($atHand,$trainRules,$params['recommend_top']); $baseline = recommend($atHand,$popular,$params['recommend_top']);
            $case = [1,$recommendation ? 1 : 0,($recommendation[0] ?? null) === $item ? 1 : 0,in_array($item,$recommendation,true) ? 1 : 0,in_array($item,$baseline,true) ? 1 : 0];
            $held[$item]++; $hits[$item] += $case[3]; if (!isset($evaluations[$size])) $evaluations[$size] = [0,0,0,0,0]; foreach ($case as $i => $value) { $evaluations[$size][$i] += $value; $total[$i] += $value; }
        }
    }
    ksort($evaluations,SORT_NUMERIC);
    return compact('train','test','training','trainRules','verdicts','totals','emerging','evaluations','total','held','hits');
}
function product_statistics(Data $data, array $params, array $main, array $rules, SupportCounter $counter): array {
    $stats = []; foreach ($data->products as $item => $product) $stats[$item] = ['units' => 0,'revenue' => 0,'support' => $counter->count([$item]),'itemsets' => 0,'partner' => null,'best' => null];
    foreach ($data->baskets as $basket) foreach ($basket->counts as $item => $quantity) { $stats[$item]['units'] += $quantity; $stats[$item]['revenue'] += $quantity * $data->products[$item]->price; }
    $graph = array_fill_keys(array_keys($data->products),[]);
    foreach ($main['frequent'] as [$items,$count]) {
        foreach ($items as $item) $stats[$item]['itemsets']++;
        if (count($items) !== 2) continue; [$first,$second] = $items; $lift = new Fraction(count($data->baskets) * $count,$stats[$first]['support'] * $stats[$second]['support']);
        foreach ([[$first,$second],[$second,$first]] as [$item,$other]) {
            $old = $stats[$item]['partner'];
            if ($old === null || $lift->compare($old[2]) > 0 || ($lift->compare($old[2]) === 0 && ($count > $old[1] || ($count === $old[1] && strcmp($other,$old[0]) < 0)))) $stats[$item]['partner'] = [$other,$count,$lift];
        }
        if ($lift->compare($params['group_min_lift']) >= 0) { $graph[$first][] = $second; $graph[$second][] = $first; }
    }
    foreach ($rules as $rule) foreach ($rule->itemset as $item) if ($stats[$item]['best'] === null) $stats[$item]['best'] = $rule;
    $groups = []; $visited = [];
    foreach (names($data->products) as $start) {
        if (isset($visited[$start]) || !$graph[$start]) continue; $stack = [$start]; $members = []; $visited[$start] = true;
        while ($stack) { $item = array_pop($stack); $members[] = $item; foreach ($graph[$item] as $other) if (!isset($visited[$other])) { $visited[$other] = true; $stack[] = $other; } }
        sort($members,SORT_STRING); $cores = $members; usort($cores,fn($a,$b) => (count($graph[$b]) <=> count($graph[$a])) ?: ($stats[$b]['support'] <=> $stats[$a]['support']) ?: strcmp($a,$b));
        $edges = $revenue = 0; foreach ($members as $item) { $edges += count($graph[$item]); $revenue += $stats[$item]['revenue']; }
        $groups[] = ['members' => $members,'edges' => intdiv($edges,2),'core' => $cores[0],'revenue' => $revenue];
    }
    usort($groups,fn($a,$b) => (count($b['members']) <=> count($a['members'])) ?: strcmp($a['members'][0],$b['members'][0]));
    $singletons = []; foreach ($main['frequent'] as [$items]) if (count($items) === 1) $singletons[] = $items[0]; sort($singletons,SORT_STRING); $substitutes = []; $total = count($data->baskets);
    foreach ($singletons as $i => $first) for ($j = $i + 1; $j < count($singletons); $j++) {
        $second = $singletons[$j]; $product = $stats[$first]['support'] * $stats[$second]['support']; if ($product < $params['negative_min_expected'] * $total) continue;
        $count = $counter->count([$first,$second]); $lift = new Fraction($total * $count,$product);
        if ($lift->compare($params['negative_max_lift']) <= 0) $substitutes[] = [$first,$second,$count,new Fraction($product,$total),$lift];
    }
    usort($substitutes,fn($a,$b) => $a[4]->compare($b[4]) ?: $b[3]->compare($a[3]) ?: strcmp($a[0],$b[0]) ?: strcmp($a[1],$b[1]));
    return compact('stats','groups','substitutes');
}
function weekly_trends(Data $data, array $params): array {
    $weeks = intdiv($data->lastDay - 1,7) + 1; $series = []; foreach ([...names($data->categories),...names($data->products)] as $name) $series[$name] = array_fill(0,$weeks,0);
    $baskets = $units = array_fill(0,$weeks,0); $customers = array_fill(0,$weeks,[]);
    foreach ($data->baskets as $basket) {
        $week = intdiv($basket->day - 1,7); $baskets[$week]++; $units[$week] += $basket->units(); $customers[$week][$basket->customer] = true;
        foreach ($basket->counts as $item => $quantity) { $series[$item][$week] += $quantity; $series[$data->taxonomy[$item]][$week] += $quantity; }
    }
    $sumW = $sumSquares = 0; for ($week = 1; $week <= $weeks; $week++) { $sumW += $week; $sumSquares += $week * $week; }
    $denominator = $weeks * $sumSquares - $sumW * $sumW; $trends = [];
    foreach ($series as $name => $values) {
        $sum = array_sum($values); $weighted = 0; foreach ($values as $i => $value) $weighted += ($i + 1) * $value;
        $slope = new Fraction($weeks * $weighted - $sumW * $sum,$denominator); $relative = $sum > 0 ? $slope->times($weeks,$sum) : null;
        $negative = new Fraction(-$params['trend_threshold']->numerator,$params['trend_threshold']->denominator);
        $verdict = $relative === null ? 'NONE' : ($relative->compare($params['trend_threshold']) >= 0 ? 'RISING' : ($relative->compare($negative) <= 0 ? 'FALLING' : 'FLAT'));
        $trends[] = compact('name','sum','slope','relative','verdict');
    }
    usort($trends,fn($a,$b) => $a['relative'] === null ? ($b['relative'] === null ? strcmp($a['name'],$b['name']) : 1) : ($b['relative'] === null ? -1 : ($b['relative']->compare($a['relative']) ?: strcmp($a['name'],$b['name'])));
    return ['weeks' => $weeks,'series' => $series,'baskets' => $baskets,'units' => $units,'customers' => array_map('count',$customers),'trends' => $trends];
}
function analyze(): array {
    $params = read_params(); $data = new Data(); $universe = names($data->products); $total = count($data->baskets);
    $main = apriori($data->sets,$universe,$params['min_support'],$params['max_size']); $classification = classifications($main['frequent'],$total);
    $base = array_map(fn($basket) => [$basket->products(),1],$data->baskets); $growth = fp_growth($base,$params['min_support'],$params['max_size']); $match = $main['frequent'] == $growth['itemsets'];
    $mainRules = make_rules($main,$total,$params); $category = apriori($data->extended,[...$universe,...names($data->categories)],$params['category_min_support'],$params['max_size'],$data->taxonomy); $categoryRules = make_rules($category,$total,$params,$data->products);
    $patterns = purchase_patterns($data,$params); $validation = validate_periods($data,$params); $counter = new SupportCounter($data->sets); $extendedCounter = new SupportCounter($data->extended);
    $products = product_statistics($data,$params,$main,$mainRules['rules'],$counter); $trends = weekly_trends($data,$params);
    return compact('params','data','main','classification','growth','match','mainRules','category','categoryRules','patterns','validation','counter','extendedCounter','products','trends');
}
function ordered_itemsets(array $itemsets): array { $list = array_values($itemsets); usort($list,fn($a,$b) => size_order($a[0],$b[0])); return $list; }
function summary_lines(array $a): array {
    $d = $a['data']; $total = count($d->baskets); $sizes = array_map(fn($basket) => count($basket->counts),$d->baskets); $largest = max($sizes); $lines = array_map(fn($error) => "ERROR $error",$d->errors);
    $lines[] = "ITEMS rows $d->itemRows adopted " . count($d->products) . ' categories ' . count($d->categories);
    $lines[] = "TRANSACTIONS lines $d->transactionLines adopted $d->adopted rejected $d->rejected duplicates $d->duplicates transactions " . count($d->transactions) . ' empty ' . (count($d->transactions) - $total);
    $lines[] = "BASKETS count $total customers " . count($d->customers) . " first_day $d->firstDay last_day $d->lastDay average_size " . fraction_text(new Fraction(array_sum($sizes),$total)) . " largest $largest";
    for ($size = 1; $size <= $largest; $size++) { $count = count(array_filter($sizes,fn($value) => $value === $size)); $lines[] = "SIZE $size baskets $count share " . percent_text($count,$total); }
    $c = $a['classification']; $lines[] = 'FREQUENT itemsets ' . count($a['main']['frequent']) . ' closed ' . count($c['closed']) . ' maximal ' . count($c['maximal']) . ' generators ' . count($c['generators']) . ' levels ' . count($a['main']['levels']);
    $g = $a['growth']; $lines[] = "FPGROWTH header {$g['header']} nodes {$g['nodes']} conditional_trees {$g['conditionalTrees']} conditional_nodes {$g['conditionalNodes']} itemsets " . count($g['itemsets']) . ' ' . ($a['match'] ? 'MATCH' : 'MISMATCH');
    if (!$a['match']) foreach ([['ONLY_APRIORI',$a['main']['frequent'],$g['itemsets']],['ONLY_FPGROWTH',$g['itemsets'],$a['main']['frequent']]] as [$label,$first,$second]) foreach (ordered_itemsets($first) as [$items,$count]) if (!isset($second[set_key($items)]) || $second[set_key($items)][1] !== $count) $lines[] = "$label " . set_key($items) . " $count";
    $rules = $a['mainRules']; $lines[] = "RULES generated {$rules['generated']} passed " . count($rules['rules']) . " productive {$rules['productive']}";
    foreach ($a['category']['levels'] as $level) $lines[] = "CATEGORY_LEVEL {$level['size']} candidates {$level['candidates']} taxonomy {$level['excluded']} pruned {$level['pruned']} counted {$level['counted']} frequent " . count($level['frequent']);
    $rules = $a['categoryRules']; $lines[] = 'CATEGORY_RULES itemsets ' . count($a['category']['frequent']) . " generated {$rules['generated']} passed " . count($rules['rules']) . " productive {$rules['productive']}";
    $p = $a['patterns']; $lines[] = 'SEQUENCES customers ' . count($d->customers) . " multi_day {$p['multiDay']} pairs {$p['pairs']} frequent " . count($p['sequences']);
    return $lines;
}
function itemset_lines(array $main): array {
    $lines = [];
    foreach ($main['levels'] as $level) { $lines[] = "LEVEL {$level['size']} candidates {$level['candidates']} pruned {$level['pruned']} counted {$level['counted']} frequent " . count($level['frequent']); foreach ($level['frequent'] as [$items,$count]) $lines[] = set_key($items) . " $count"; }
    return $lines;
}
function classification_lines(array $classification): array { $lines = []; foreach (['closed' => 'CLOSED','maximal' => 'MAXIMAL','generators' => 'GENERATOR'] as $kind => $label) foreach (ordered_itemsets($classification[$kind]) as [$items,$count]) $lines[] = "$label " . set_key($items) . " $count"; return $lines; }
function sequence_lines(array $patterns): array {
    $lines = [];
    foreach ($patterns['sequences'] as $index => $p) $lines[] = 'SEQ ' . ($index + 1) . " {$p['first']} -> {$p['second']} customers {$p['count']} base {$p['base']} confidence " . fraction_text($p['confidence']) . ' lift ' . fraction_text($p['lift']) . ' gap ' . fraction_text($p['gap']);
    foreach ($patterns['repeats'] as $p) $lines[] = "REPEAT {$p['item']} customers {$p['customers']} intervals {$p['count']} min {$p['min']} max {$p['max']} mean " . fraction_text($p['mean']) . ' median ' . fraction_text($p['median']);
    return $lines;
}
function evaluation_line(string $label, array $counts): string { [$cases,$covered,$hit1,$hit,$baseline] = $counts; return "RECOMMEND $label cases $cases covered $covered hit1 $hit1 hit $hit rate " . fraction_text(new Fraction($hit,$cases)) . " baseline $baseline rate " . fraction_text(new Fraction($baseline,$cases)); }
function validation_lines(array $v): array {
    $lines = [];
    foreach ($v['verdicts'] as [$rule,$a,$c,$confidence,$lift,$verdict]) $lines[] = "RULE $rule->rank " . rule_arrow($rule) . " train $rule->count confidence " . fraction_text($rule->confidence) . ' lift ' . fraction_text($rule->lift) . " test $c of $a confidence " . ($confidence === null ? '-' : fraction_text($confidence)) . ' lift ' . ($lift === null ? '-' : fraction_text($lift)) . " $verdict";
    foreach ($v['emerging'] as $rule) $lines[] = "EMERGING $rule->rank " . rule_arrow($rule) . " test $rule->count confidence " . fraction_text($rule->confidence) . ' lift ' . fraction_text($rule->lift);
    $t = $v['totals']; $lines[] = 'VALIDATION train ' . count($v['train']) . ' test ' . count($v['test']) . ' itemsets ' . count($v['training']['frequent']) . ' rules ' . count($v['trainRules']) . " hold {$t['HOLD']} fail {$t['FAIL']} unseen {$t['UNSEEN']} emerging " . count($v['emerging']);
    foreach ($v['evaluations'] as $size => $counts) $lines[] = evaluation_line("size $size",$counts); $lines[] = evaluation_line('total',$v['total']); return $lines;
}
function matrix_lines(string $label, array $items, SupportCounter $counter): array {
    $lines = []; foreach ($items as $index => $item) $lines[] = "$label " . ($index + 1) . " $item baskets " . $counter->count([$item]);
    $header = str_repeat(' ',4); for ($i = 1; $i <= count($items); $i++) $header .= str_pad((string)$i,7,' ',STR_PAD_LEFT); $lines[] = $header;
    foreach ($items as $i => $first) {
        $line = str_pad((string)($i + 1),4,' ',STR_PAD_LEFT);
        foreach ($items as $j => $second) { $value = $i === $j ? '-' : (string)intdiv(100 * count($counter->baskets) * $counter->count([$first,$second]),$counter->count([$first]) * $counter->count([$second])); $line .= str_pad($value,7,' ',STR_PAD_LEFT); }
        $lines[] = $line;
    }
    return $lines;
}
function product_lines(array $a): array {
    $data = $a['data']; $stats = $a['products']['stats']; $total = count($data->baskets); $revenue = array_sum(array_column($stats,'revenue')); $units = array_sum(array_column($stats,'units')); $lines = [];
    $order = names($data->products); usort($order,fn($first,$second) => ($stats[$second]['revenue'] <=> $stats[$first]['revenue']) ?: strcmp($first,$second));
    foreach ($order as $index => $item) {
        $product = $data->products[$item]; $p = $stats[$item]; $partner = $p['partner'] === null ? 'none' : $p['partner'][0] . ' ' . fraction_text($p['partner'][2]); $best = $p['best'] === null ? 'none' : $p['best']->rank . ' ' . rule_arrow($p['best']);
        $lines[] = 'ITEM ' . ($index + 1) . " $item $product->category price " . money_text($product->price) . " units {$p['units']} revenue " . money_text($p['revenue']) . ' share ' . percent_text($p['revenue'],$revenue) . " baskets {$p['support']} support " . fraction_text(new Fraction($p['support'],$total)) . " customers {$a['patterns']['buyers'][$item]} itemsets {$p['itemsets']} heldout {$a['validation']['held'][$item]} hits {$a['validation']['hits'][$item]} partner $partner best $best";
    }
    $categories = [];
    foreach ($data->products as $item => $product) {
        $category = $product->category; if (!isset($categories[$category])) $categories[$category] = ['items' => 0,'units' => 0,'revenue' => 0];
        $categories[$category]['items']++; $categories[$category]['units'] += $stats[$item]['units']; $categories[$category]['revenue'] += $stats[$item]['revenue'];
    }
    $order = names($categories); usort($order,fn($first,$second) => ($categories[$second]['revenue'] <=> $categories[$first]['revenue']) ?: strcmp($first,$second));
    foreach ($order as $category) {
        $p = $categories[$category]; $count = $a['extendedCounter']->count([$category]);
        $lines[] = "CATEGORY $category items {$p['items']} units {$p['units']} revenue " . money_text($p['revenue']) . ' share ' . percent_text($p['revenue'],$revenue) . " baskets $count support " . fraction_text(new Fraction($count,$total));
    }
    $lines[] = 'TOTAL items ' . count($data->products) . " units $units revenue " . money_text($revenue) . " baskets $total customers " . count($data->customers);
    foreach ($a['products']['groups'] as $index => $group) $lines[] = 'GROUP ' . ($index + 1) . ' items ' . count($group['members']) . " edges {$group['edges']} core {$group['core']} revenue " . money_text($group['revenue']) . ' share ' . percent_text($group['revenue'],$revenue) . ' members ' . set_key($group['members']);
    foreach ($a['products']['substitutes'] as [$first,$second,$count,$expected,$lift]) $lines[] = "SUBSTITUTE $first $second count $count expected " . fraction_text($expected) . ' lift ' . fraction_text($lift);
    $order = names($data->products); usort($order,fn($first,$second) => ($a['counter']->count([$second]) <=> $a['counter']->count([$first])) ?: strcmp($first,$second));
    array_push($lines,...matrix_lines('MATRIX',array_slice($order,0,$a['params']['matrix_size']),$a['counter']));
    $order = names($data->categories); usort($order,fn($first,$second) => ($a['extendedCounter']->count([$second]) <=> $a['extendedCounter']->count([$first])) ?: strcmp($first,$second));
    array_push($lines,...matrix_lines('CATEGORY_MATRIX',$order,$a['extendedCounter'])); return $lines;
}
function trend_lines(array $trends): array {
    $lines = []; $rows = ['WEEK' => range(1,$trends['weeks']),'BASKETS' => $trends['baskets'],'UNITS' => $trends['units'],'CUSTOMERS' => $trends['customers'],...$trends['series']];
    foreach ($rows as $label => $values) $lines[] = str_pad($label,17) . implode('',array_map(fn($value) => str_pad((string)$value,6,' ',STR_PAD_LEFT),$values));
    foreach ($trends['trends'] as $trend) $lines[] = "TREND {$trend['name']} units {$trend['sum']} slope " . fraction_text($trend['slope']) . ' relative ' . ($trend['relative'] === null ? '-' : fraction_text($trend['relative'])) . " {$trend['verdict']}";
    return $lines;
}
function customer_lines(array $a): array {
    $d = $a['data']; $lines = []; $segments = ['NEW' => [0,0],'LOYAL' => [0,0],'AT_RISK' => [0,0],'REGULAR' => [0,0]]; $totalRevenue = array_sum(array_column($a['products']['stats'],'revenue'));
    foreach (names($d->customers) as $customer) {
        $baskets = $d->customers[$customer]; $days = $history = $categories = []; $units = $revenue = 0;
        foreach ($baskets as $basket) {
            $days[$basket->day] = true;
            foreach ($basket->counts as $item => $quantity) { $history[$item] = true; $units += $quantity; $product = $d->products[$item]; $revenue += $quantity * $product->price; $categories[$product->category] = ($categories[$product->category] ?? 0) + $quantity; }
        }
        $first = min(array_keys($days)); $last = max(array_keys($days)); $count = count($baskets); $favorite = names($categories); usort($favorite,fn($first,$second) => ($categories[$second] <=> $categories[$first]) ?: strcmp($first,$second));
        $segment = $first > $d->lastDay - 28 ? 'NEW' : ($count >= 4 && $d->lastDay - $last <= 14 ? 'LOYAL' : ($d->lastDay - $last > 28 ? 'AT_RISK' : 'REGULAR'));
        $offer = rule_recommendation($history,$a['mainRules']['rules'],$a['params']['recommend_top']); $segments[$segment][0]++; $segments[$segment][1] += $revenue;
        $lines[] = "CUSTOMER $customer baskets $count days " . count($days) . " first $first last $last items " . count($history) . " units $units revenue " . money_text($revenue) . ' average ' . money_text(intdiv($revenue,$count)) . " favorite {$favorite[0]} segment $segment offer " . ($offer ? set_key($offer) : 'none');
    }
    foreach ($segments as $segment => [$count,$revenue]) $lines[] = "SEGMENT $segment customers $count revenue " . money_text($revenue) . ' share ' . percent_text($revenue,$totalRevenue); return $lines;
}

$analysis = analyze();
foreach (['summary.txt' => summary_lines($analysis),'itemsets.txt' => itemset_lines($analysis['main']),'closed_maximal.txt' => classification_lines($analysis['classification']),'rules.csv' => rules_csv($analysis['mainRules']['rules']),'category_rules.csv' => rules_csv($analysis['categoryRules']['rules']),'sequences.txt' => sequence_lines($analysis['patterns']),'validation.txt' => validation_lines($analysis['validation']),'items_report.txt' => product_lines($analysis),'trends.txt' => trend_lines($analysis['trends']),'customers.txt' => customer_lines($analysis)] as $name => $lines) write_report($name,$lines);
