<?php
require __DIR__ . '/items.php';
require __DIR__ . '/bom.php';
require __DIR__ . '/lot_sizing.php';
require __DIR__ . '/capacity.php';
require __DIR__ . '/costing.php';
require __DIR__ . '/report.php';

const DEMAND_KINDS = ['MPS', 'ORDER', 'DEPENDENT'];
const ROOT_KINDS = ['MPS', 'ORDER', 'SAFETY'];
const SUPPLY_KINDS = ['STOCK', 'RECEIPT', 'ORDER'];
const MESSAGE_KINDS = ['BELOW_SAFETY', 'PAST_DUE', 'RELEASE', 'EXPEDITE', 'DEFER', 'CANCEL', 'NO_ROUTING', 'NO_DEMAND', 'OVERLOAD'];
function sorted_ids(array $map): array { $ids = array_keys($map); usort($ids, fn($a, $b) => strcmp((string)$a, (string)$b)); return $ids; }
class ScheduleRow {
    public string $item;
    public int $week, $quantity;
    public function __construct(array $fields, public int $line) { $this->item = $fields[0]; $this->week = (int)$fields[1]; $this->quantity = (int)$fields[2]; }
}
class Inquiry {
    public string $id, $item;
    public int $quantity, $week;
    public function __construct(array $fields, public int $line) { $this->id = $fields[0]; $this->item = $fields[1]; $this->quantity = (int)$fields[2]; $this->week = (int)$fields[3]; }
}
class Demand {
    public function __construct(public string $item, public string $kind, public int $week, public int $quantity, public string $orderId = '', public int $line = 0, public string $parent = '', public int $parentNumber = 0) {}
    public function text(): string {
        return match ($this->kind) { 'SAFETY' => "SAFETY $this->item", 'MPS' => "MPS $this->item week $this->week", 'ORDER' => "ORDER $this->orderId $this->item week $this->week", default => "$this->parent order $this->parentNumber week $this->week" };
    }
    public function rootKey(): string { return json_encode([$this->item, array_search($this->kind, ROOT_KINDS, true), $this->week, $this->orderId]); }
}
function compare_demands(Demand $a, Demand $b): int {
    return ($a->week <=> $b->week) ?: (array_search($a->kind, DEMAND_KINDS, true) <=> array_search($b->kind, DEMAND_KINDS, true)) ?: ($a->line <=> $b->line) ?: strcmp($a->parent, $b->parent) ?: ($a->parentNumber <=> $b->parentNumber);
}
function compare_roots(Demand $a, Demand $b): int {
    return strcmp($a->item, $b->item) ?: (array_search($a->kind, ROOT_KINDS, true) <=> array_search($b->kind, ROOT_KINDS, true)) ?: ($a->week <=> $b->week) ?: strcmp($a->orderId, $b->orderId);
}
class PlannedOrder {
    public int $originalRelease, $release;
    public function __construct(public string $item, public int $number, public int $receipt, public int $quantity, int $lead) { $this->originalRelease = $receipt - $lead; $this->release = max(1, $this->originalRelease); }
}
class Supply {
    public int $remaining;
    public array $allocations = [], $roots = [];
    public function __construct(public string $kind, public int $week, public int $quantity, public int $line = 0, public ?PlannedOrder $order = null) { $this->remaining = $quantity; }
    public function header(): string {
        if ($this->kind === 'STOCK') return "STOCK quantity $this->quantity";
        if ($this->kind === 'RECEIPT') return "RECEIPT line $this->line week $this->week quantity $this->quantity";
        $order = $this->order; return "ORDER $order->number receipt $order->receipt release $order->release quantity $order->quantity";
    }
    public function serves(string $orderId): bool { foreach ($this->roots as $root) if ($root->kind === 'ORDER' && $root->orderId === $orderId) return true; return false; }
}
class ItemPlan {
    public array $demands = [], $gross, $onHand, $net, $plannedReceipts, $plannedReleases, $orders = [], $supplies = [], $orderSupplies = [];
    public function __construct(public Item $item, int $horizon, public array $receipts) {
        $this->gross = $this->onHand = $this->net = $this->plannedReceipts = $this->plannedReleases = array_fill(0, $horizon + 1, 0);
        $this->onHand[0] = $item->onHand;
    }
    public function pastDue(): int { $total = 0; foreach ($this->orders as $order) if ($order->originalRelease < 1) $total += $order->quantity; return $total; }
}
class Plan {
    public array $overloads = [];
    public function __construct(public array $items, public array $loads, array $centers) {
        foreach ($loads as $id => $weeks) $this->overloads[$id] = array_map(fn($load) => max(0, $load - $centers[$id]->available), $weeks);
    }
}
class Promise {
    public int $week = 0, $materialWeek = 0;
    public string $reason = '';
    public function __construct(public Inquiry $inquiry) {}
    public function status(): string { return $this->week === 0 ? 'rejected' : ($this->week === $this->inquiry->week ? 'on_time' : 'late'); }
}
function schedule_error(ScheduleRow|Inquiry $row, array $items, int $horizon): ?string {
    if (!isset($items[$row->item])) return "unknown item $row->item";
    if ($row->week < 1 || $row->week > $horizon) return "week $row->week outside horizon";
    if ($row->quantity < 1) return "bad quantity $row->quantity";
    return null;
}
function read_schedule(string $name, array $items, int $horizon, array &$errors, bool $unique): array {
    $rows = $seen = [];
    foreach (read_rows($name) as [$number, $fields]) {
        $row = new ScheduleRow($fields, $number); $reason = schedule_error($row, $items, $horizon); $key = $row->item . "\0" . $row->week;
        if ($reason === null && $unique && isset($seen[$key])) $reason = "duplicate $row->item week $row->week";
        if ($reason !== null) $errors[] = "$name line $number: $reason"; else { $rows[] = $row; $seen[$key] = true; }
    }
    return $rows;
}
class PlanningData {
    public array $errors = [], $peg = [], $items, $centers, $routings, $inquiries = [], $mps = [], $codes = [], $cumulative = [], $order, $centerOrder, $weeks, $receipts, $scheduled;
    public int $horizon = 0, $treeQuantity = 0;
    public Bom $bom;
    public function __construct() {
        foreach (explode("\n", rtrim(file_get_contents('input/params.txt'), "\n")) as $line) {
            $words = explode(' ', $line); $kind = array_shift($words);
            if ($kind === 'horizon') $this->horizon = (int)$words[0]; elseif ($kind === 'peg') $this->peg = $words; else $this->treeQuantity = (int)$words[0];
        }
        $this->items = read_items($this->errors); $this->bom = read_bom($this->items, $this->errors); $this->centers = read_centers($this->errors);
        $this->routings = read_routings($this->items, $this->centers, $this->bom, $this->errors);
        $mps = read_schedule('mps.csv', $this->items, $this->horizon, $this->errors, true);
        $receipts = read_schedule('receipts.csv', $this->items, $this->horizon, $this->errors, false); $seen = [];
        foreach (read_rows('orders.csv') as [$number, $fields]) {
            $inquiry = new Inquiry($fields, $number);
            $reason = isset($seen[$inquiry->id]) ? "duplicate order $inquiry->id" : schedule_error($inquiry, $this->items, $this->horizon);
            if ($reason !== null) $this->errors[] = "orders.csv line $number: $reason"; else { $this->inquiries[] = $inquiry; $seen[$inquiry->id] = true; }
        }
        foreach ($mps as $row) $this->mps[] = new Demand($row->item, 'MPS', $row->week, $row->quantity);
        foreach ($this->items as $id => $_) { $this->bom->code((string)$id, $this->codes); $this->bom->cumulative((string)$id, $this->items, $this->cumulative); }
        $this->order = sorted_ids($this->items); usort($this->order, fn($a, $b) => ($this->codes[$a] <=> $this->codes[$b]) ?: strcmp((string)$a, (string)$b));
        $this->centerOrder = sorted_ids($this->centers); $this->weeks = range(1, $this->horizon);
        $this->receipts = array_fill_keys(array_keys($this->items), []); $this->scheduled = array_fill_keys(array_keys($this->items), array_fill(0, $this->horizon + 1, 0));
        usort($receipts, fn($a, $b) => ($a->week <=> $b->week) ?: ($a->line <=> $b->line));
        foreach ($receipts as $row) { $this->receipts[$row->item][] = $row; $this->scheduled[$row->item][$row->week] += $row->quantity; }
    }
}
function run_mrp(PlanningData $data, array $orders): Plan {
    $plans = []; foreach ($data->order as $id) $plans[$id] = new ItemPlan($data->items[$id], $data->horizon, $data->scheduled[$id]);
    foreach ([...$data->mps, ...$orders] as $demand) $plans[$demand->item]->demands[] = $demand;
    foreach ($data->order as $id) {
        $plan = $plans[$id]; $item = $plan->item;
        foreach ($plan->demands as $demand) $plan->gross[$demand->week] += $demand->quantity;
        $projected = $item->onHand;
        foreach ($data->weeks as $week) {
            $projected += $plan->receipts[$week] - $plan->gross[$week];
            if ($projected < $item->safety) {
                $quantity = lot_size($item, $week, $projected, $plan->receipts, $plan->gross, $data->horizon);
                $order = new PlannedOrder($item->id, count($plan->orders) + 1, $week, $quantity, $item->lead); $plan->orders[] = $order;
                $plan->net[$week] = $item->safety - $projected; $plan->plannedReceipts[$week] = $quantity; $plan->plannedReleases[$order->release] += $quantity; $projected += $quantity;
            }
            $plan->onHand[$week] = $projected;
        }
        foreach ($plan->orders as $order) foreach ($data->bom->children[$id] as $row) $plans[$row->child]->demands[] = new Demand($row->child, 'DEPENDENT', $order->release, need($row, $order->quantity), parent: $order->item, parentNumber: $order->number);
    }
    $loads = array_fill_keys(array_keys($data->centers), array_fill(0, $data->horizon + 1, 0));
    foreach ($data->routings as $id => $operations) foreach ($plans[$id]->orders as $order) foreach ($operations as $index => $operation) $loads[$operation->center][operation_week($order->receipt, $data->items[$id]->lead, $index, count($operations))] += $operation->minutes($order->quantity);
    return new Plan($plans, $loads, $data->centers);
}
function promise_inquiries(PlanningData $data, Plan $base): array {
    $current = $base; $promised = $promises = [];
    foreach ($data->inquiries as $inquiry) {
        $promise = new Promise($inquiry);
        for ($week = $inquiry->week; $week <= $data->horizon; $week++) {
            $demand = new Demand($inquiry->item, 'ORDER', $week, $inquiry->quantity, $inquiry->id, $inquiry->line);
            $trial = run_mrp($data, [...$promised, $demand]); $reason = null;
            foreach ($data->order as $id) if ($trial->items[$id]->pastDue() > $current->items[$id]->pastDue()) { $reason = (string)$id; break; }
            if ($reason === null) {
                if ($promise->materialWeek === 0) $promise->materialWeek = $week;
                foreach ($data->centerOrder as $id) foreach ($data->weeks as $w) if ($trial->overloads[$id][$w] > $current->overloads[$id][$w]) { $reason = "$id week $w"; break 2; }
            }
            if ($reason === null) { $promise->week = $week; $promised[] = $demand; $current = $trial; break; }
            if ($week === $inquiry->week) $promise->reason = $reason;
        }
        $promises[] = $promise;
    }
    return [$promises, $current];
}
function parent_supply(Plan $plan, Demand $demand): Supply { return $plan->items[$demand->parent]->orderSupplies[$demand->parentNumber - 1]; }
function peg_plan(PlanningData $data, Plan $plan): void {
    foreach ($data->order as $id) {
        $itemPlan = $plan->items[$id]; $item = $itemPlan->item; $demands = $itemPlan->demands; usort($demands, 'compare_demands');
        if ($item->safety > 0) array_unshift($demands, new Demand($item->id, 'SAFETY', 0, $item->safety));
        $supplies = [];
        if ($item->onHand > 0) $supplies[] = new Supply('STOCK', 0, $item->onHand);
        foreach ($data->receipts[$id] as $receipt) $supplies[] = new Supply('RECEIPT', $receipt->week, $receipt->quantity, $receipt->line);
        foreach ($itemPlan->orders as $order) $supplies[] = new Supply('ORDER', $order->receipt, $order->quantity, order: $order);
        usort($supplies, fn($a, $b) => ($a->week <=> $b->week) ?: (array_search($a->kind, SUPPLY_KINDS, true) <=> array_search($b->kind, SUPPLY_KINDS, true)) ?: ($a->line <=> $b->line));
        $index = 0;
        foreach ($demands as $demand) {
            $remaining = $demand->quantity;
            while ($remaining > 0) {
                while ($supplies[$index]->remaining === 0) $index++;
                $supply = $supplies[$index]; $share = min($remaining, $supply->remaining); $supply->allocations[] = [$demand, $share]; $supply->remaining -= $share; $remaining -= $share;
            }
        }
        $itemPlan->supplies = $supplies; $itemPlan->orderSupplies = array_values(array_filter($supplies, fn($supply) => $supply->kind === 'ORDER'));
        foreach ($itemPlan->orderSupplies as $supply) {
            $roots = [];
            foreach ($supply->allocations as [$demand]) foreach ($demand->kind === 'DEPENDENT' ? parent_supply($plan, $demand)->roots : [$demand] as $root) $roots[$root->rootKey()] = $root;
            $supply->roots = array_values($roots); usort($supply->roots, 'compare_roots');
        }
    }
}
function depth_label(int $depth): string { return str_repeat('.', $depth) . $depth; }
function grid_lines(PlanningData $data, Plan $plan): array {
    $lines = [];
    foreach ($data->order as $id) {
        $p = $plan->items[$id]; $item = $p->item;
        $lines[] = "ITEM $id LLC {$data->codes[$id]} LT $item->lead LOT " . $item->lotLabel() . " SS $item->safety OH $item->onHand $item->description";
        $lines[] = table_row('WEEK', $data->weeks, 6);
        foreach (['GROSS' => $p->gross, 'RECEIPTS' => $p->receipts, 'ON_HAND' => $p->onHand, 'NET' => $p->net, 'PLAN_RCPT' => $p->plannedReceipts, 'PLAN_REL' => $p->plannedReleases] as $label => $values) $lines[] = table_row($label, array_slice($values, 1), 6);
        $lines[] = 'TOTAL gross ' . array_sum($p->gross) . ' receipts ' . array_sum($p->receipts) . ' planned ' . array_sum($p->plannedReceipts) . ' orders ' . count($p->orders) . ' ending ' . $p->onHand[$data->horizon];
    }
    return $lines;
}
function where_used(Bom $bom, string $id, int $depth, int $extension, array &$lines): void {
    foreach ($bom->parents[$id] as $row) { $next = $extension * $row->quantity; $lines[] = depth_label($depth) . " $row->parent qty $row->quantity ext $next"; where_used($bom, $row->parent, $depth + 1, $next, $lines); }
}
function allocation_lines(Plan $plan, Supply $supply, int $depth, array &$lines): void {
    foreach ($supply->allocations as [$demand, $share]) {
        $lines[] = str_repeat(' ', 2 * $depth) . "ALLOC $share " . $demand->text();
        if ($supply->kind === 'ORDER' && $demand->kind === 'DEPENDENT') allocation_lines($plan, parent_supply($plan, $demand), $depth + 1, $lines);
    }
}
function pegging_lines(PlanningData $data, Plan $plan): array {
    $lines = [];
    foreach ($data->peg as $id) {
        $p = $plan->items[$id]; $lines[] = "PEG $id orders " . count($p->orders); where_used($data->bom, $id, 1, 1, $lines);
        foreach (SUPPLY_KINDS as $kind) foreach ($p->supplies as $supply) if ($supply->kind === $kind) {
            $lines[] = $supply->header(); allocation_lines($plan, $supply, 1, $lines);
            if ($supply->remaining > 0) $lines[] = "  EXCESS $supply->remaining";
            foreach ($supply->roots as $root) $lines[] = '  ROOT ' . $root->text();
        }
    }
    return $lines;
}
function explode_lines(PlanningData $data, string $id, int $gross, int $extension, int $depth, array &$lines, array &$totals): void {
    foreach ($data->bom->children[$id] as $row) {
        $child = $data->items[$row->child]; $next = $extension * $row->quantity; $quantity = need($row, $gross); $totals[$row->child] = ($totals[$row->child] ?? 0) + $quantity;
        $lines[] = depth_label($depth) . " $row->child qty $row->quantity scrap $row->scrap ext $next gross $quantity lt $child->lead cum {$data->cumulative[$row->child]} $child->description";
        explode_lines($data, $row->child, $quantity, $next, $depth + 1, $lines, $totals);
    }
}
function bom_tree_lines(PlanningData $data): array {
    $lines = [];
    foreach (sorted_ids($data->items) as $id) {
        if (!$data->bom->manufactured((string)$id) || $data->bom->parents[$id]) continue;
        $item = $data->items[$id]; $lines[] = "TREE $id quantity $data->treeQuantity"; $lines[] = "0 $id ext 1 gross $data->treeQuantity lt $item->lead cum {$data->cumulative[$id]} $item->description";
        $totals = []; explode_lines($data, (string)$id, $data->treeQuantity, 1, 1, $lines, $totals);
        foreach (sorted_ids($totals) as $child) $lines[] = "SUM $child $totals[$child]";
        $path = [(string)$id]; $current = (string)$id;
        while ($data->bom->manufactured($current)) {
            $best = $data->bom->children[$current][0]; foreach ($data->bom->children[$current] as $row) if ($data->cumulative[$row->child] > $data->cumulative[$best->child]) $best = $row;
            $path[] = $current = $best->child;
        }
        $lines[] = 'CRITICAL ' . implode(' -> ', $path) . " cum {$data->cumulative[$id]}";
    }
    return $lines;
}
function cost_lines(PlanningData $data, Plan $plan, array $costs): array {
    $usage = $values = []; foreach ($data->items as $id => $_) { $usage[$id] = array_sum($plan->items[$id]->gross); $values[$id] = $usage[$id] * $costs[$id][2]; }
    $classes = abc_classes($values); $lines = ['item,material,labor,total,usage,value,class'];
    foreach (sorted_ids($data->items) as $id) $lines[] = implode(',', [$id, money($costs[$id][0]), money($costs[$id][1]), money($costs[$id][2]), $usage[$id], money($values[$id]), $classes[$id]]);
    return $lines;
}
function exception_lines(PlanningData $data, Plan $plan): array {
    $messages = [];
    foreach ($data->order as $id) {
        $p = $plan->items[$id]; $item = $p->item;
        if ($item->onHand < $item->safety) $messages[] = "BELOW_SAFETY $id on hand $item->onHand safety $item->safety";
        foreach ($p->orders as $order) {
            if ($order->originalRelease < 1) $messages[] = "PAST_DUE $id order $order->number receipt $order->receipt release $order->originalRelease late " . (1 - $order->originalRelease) . " quantity $order->quantity";
            elseif ($order->originalRelease === 1) $messages[] = "RELEASE $id order $order->number receipt $order->receipt quantity $order->quantity";
        }
        $balances = []; $balance = $item->onHand; foreach ($data->weeks as $week) { $balance -= $p->gross[$week]; $balances[$week] = $balance; }
        $covered = 0;
        foreach ($data->receipts[$id] as $receipt) {
            $needed = 0; foreach ($data->weeks as $week) if ($balances[$week] + $covered < $item->safety) { $needed = $week; break; }
            $text = "$id receipt line $receipt->line week $receipt->week quantity $receipt->quantity";
            if ($needed === 0) $messages[] = "CANCEL $text"; elseif ($needed < $receipt->week) $messages[] = "EXPEDITE $text to $needed"; elseif ($needed > $receipt->week) $messages[] = "DEFER $text to $needed";
            $covered += $receipt->quantity;
        }
        if ($data->bom->manufactured((string)$id) && !isset($data->routings[$id])) $messages[] = "NO_ROUTING $id";
        if (array_sum($p->gross) === 0 && $item->onHand > 0) $messages[] = "NO_DEMAND $id on hand $item->onHand";
    }
    foreach ($data->centerOrder as $id) foreach ($data->weeks as $week) if ($plan->overloads[$id][$week] > 0) $messages[] = "OVERLOAD $id week $week load {$plan->loads[$id][$week]} available {$data->centers[$id]->available}";
    $counts = array_fill_keys(MESSAGE_KINDS, 0); foreach ($messages as $message) $counts[explode(' ', $message, 2)[0]]++;
    $parts = ['SUMMARY errors ' . count($data->errors)]; foreach ($counts as $kind => $count) $parts[] = strtolower($kind) . " $count";
    return [...array_map(fn($error) => "ERROR $error", $data->errors), ...$messages, implode(' ', $parts)];
}
function capacity_lines(PlanningData $data, Plan $plan): array {
    $lines = $totals = [];
    foreach ($data->centerOrder as $id) {
        $center = $data->centers[$id]; $loads = array_slice($plan->loads[$id], 1); $overloads = array_slice($plan->overloads[$id], 1); $leveled = level_loads($plan->loads[$id], $center->available);
        $total = $totals[$id] = array_sum($loads); $capacity = $center->available * $data->horizon; $peak = $total > 0 ? array_search(max($loads), $loads, true) + 1 : 0; $overloaded = count(array_filter($overloads, fn($over) => $over > 0)); $backlog = max(0, $leveled[1] - $center->available);
        $lines[] = "CENTER $id minutes $center->minutes efficiency $center->efficiency available $center->available $center->description";
        foreach (['WEEK' => $data->weeks, 'LOAD' => $loads, 'UTIL' => array_map(fn($load) => percent($load, $center->available), $loads), 'OVER' => $overloads, 'LEVELED' => array_slice($leveled, 1)] as $label => $values) $lines[] = table_row($label, $values, 7);
        $lines[] = "TOTAL load $total available $capacity utilization " . percent($total, $capacity) . " overloaded $overloaded peak $peak backlog $backlog";
    }
    $ranked = $data->centerOrder; usort($ranked, fn($a, $b) => ($totals[$b] * $data->centers[$a]->available <=> $totals[$a] * $data->centers[$b]->available) ?: strcmp((string)$a, (string)$b));
    foreach ($ranked as $index => $id) $lines[] = 'RANK ' . ($index + 1) . " $id load $totals[$id] utilization " . percent($totals[$id], $data->centers[$id]->available * $data->horizon);
    return $lines;
}
function promise_lines(PlanningData $data, array $promises, Plan $base, Plan $final): array {
    $lines = []; $counts = ['on_time' => 0, 'late' => 0, 'rejected' => 0];
    foreach ($promises as $promise) {
        $inquiry = $promise->inquiry; $status = $promise->status(); $counts[$status]++; $head = "ORDER $inquiry->id $inquiry->item quantity $inquiry->quantity requested $inquiry->week"; $material = $promise->materialWeek > 0 ? (string)$promise->materialWeek : 'none';
        if ($status === 'rejected') { $lines[] = "$head rejected material $material reason $promise->reason"; continue; }
        $lines[] = $status === 'on_time' ? "$head promised $promise->week" : "$head promised $promise->week late " . ($promise->week - $inquiry->week) . " material $material reason $promise->reason";
        foreach ($data->order as $id) foreach ($final->items[$id]->orderSupplies as $supply) if ($supply->serves($inquiry->id)) { $order = $supply->order; $lines[] = "  SUPPLY $id order $order->number receipt $order->receipt release $order->release quantity $order->quantity"; }
    }
    foreach ($data->order as $id) {
        $before = $base->items[$id]; $after = $final->items[$id]; $changed = 0;
        foreach ($data->weeks as $week) if ($before->plannedReceipts[$week] !== $after->plannedReceipts[$week]) { $changed = $week; break; }
        if ($changed > 0) $lines[] = "CHANGE $id from $changed planned " . array_sum($before->plannedReceipts) . ' -> ' . array_sum($after->plannedReceipts) . ' orders ' . count($before->orders) . ' -> ' . count($after->orders);
    }
    $lines[] = 'SUMMARY orders ' . count($promises) . " on_time {$counts['on_time']} late {$counts['late']} rejected {$counts['rejected']}";
    return $lines;
}
function release_lines(PlanningData $data, Plan $plan): array {
    $orders = []; foreach ($data->order as $id) foreach ($plan->items[$id]->orders as $order) if ($order->release === 1) $orders[] = $order;
    usort($orders, fn($a, $b) => ($a->originalRelease <=> $b->originalRelease) ?: strcmp($a->item, $b->item) ?: ($a->number <=> $b->number));
    $available = []; foreach ($data->items as $id => $item) $available[$id] = $item->onHand + $data->scheduled[$id][1];
    $lines = []; $made = $readyCount = $bought = $purchase = 0;
    foreach ($orders as $order) {
        $id = $order->item; $item = $data->items[$id]; $late = $order->originalRelease < 1 ? ' late ' . (1 - $order->originalRelease) : ''; $head = "$id order $order->number receipt $order->receipt quantity $order->quantity";
        if (!$data->bom->manufactured($id)) { $value = $order->quantity * $item->material; $bought++; $purchase += $value; $lines[] = "BUY $head$late value " . money($value); continue; }
        $ready = true; $picks = [];
        foreach ($data->bom->children[$id] as $row) { $quantity = need($row, $order->quantity); $have = $available[$row->child]; if ($quantity > $have) $ready = false; $picks[] = [$row->child, $quantity, $have]; }
        $made++; if ($ready) $readyCount++; $lines[] = "MAKE $head$late " . ($ready ? 'READY' : 'SHORT');
        foreach ($picks as [$child, $quantity, $have]) { $lines[] = "  PICK $child need $quantity available $have short " . max(0, $quantity - $have); if ($ready) $available[$child] -= $quantity; }
        $operations = $data->routings[$id] ?? [];
        foreach ($operations as $index => $operation) $lines[] = "  OPERATION $operation->number $operation->center week " . operation_week($order->receipt, $item->lead, $index, count($operations)) . ' minutes ' . $operation->minutes($order->quantity);
    }
    $lines[] = "SUMMARY make $made ready $readyCount short " . ($made - $readyCount) . " buy $bought value " . money($purchase);
    return $lines;
}
function value_lines(PlanningData $data, Plan $plan, array $costs): array {
    $lines = ['week,inventory,purchases,labor'];
    foreach ($data->weeks as $week) {
        $inventory = $purchases = $labor = 0;
        foreach ($data->order as $id) { $p = $plan->items[$id]; $released = $p->plannedReleases[$week]; $inventory += $p->onHand[$week] * $costs[$id][2]; if ($data->bom->manufactured((string)$id)) $labor += $released * $p->item->labor; else $purchases += $released * $p->item->material; }
        $lines[] = "$week," . money($inventory) . ',' . money($purchases) . ',' . money($labor);
    }
    return $lines;
}

$data = new PlanningData(); $base = run_mrp($data, []); [$promises, $final] = promise_inquiries($data, $base); peg_plan($data, $final);
$costs = standard_costs($data->items, $data->bom, $data->order);
foreach (['mrp_grid.txt' => grid_lines($data, $final), 'pegging.txt' => pegging_lines($data, $final), 'bom_tree.txt' => bom_tree_lines($data), 'cost_rollup.csv' => cost_lines($data, $final, $costs),
    'exceptions.txt' => exception_lines($data, $final), 'capacity.txt' => capacity_lines($data, $final), 'promises.txt' => promise_lines($data, $promises, $base, $final), 'releases.txt' => release_lines($data, $final), 'value_plan.csv' => value_lines($data, $final, $costs)] as $name => $lines) write_report($name, $lines);
