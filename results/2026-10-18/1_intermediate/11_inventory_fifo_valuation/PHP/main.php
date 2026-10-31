<?php
declare(strict_types=1);

const CATEGORIES = [
    'received', 'returned', 'adjusted-in', 'adjusted-out',
    'shipped', 'written-down', 'expired', 'recalled',
];

function cents(string $text): int {
    return (int)str_replace('.', '', $text);
}

function money(int $cents): string {
    $sign = $cents < 0 ? '-' : '';
    $value = abs($cents);
    return $sign . intdiv($value, 100) . '.' . str_pad((string)($value % 100), 2, '0', STR_PAD_LEFT);
}

function signedQuantity(int $quantity): string {
    return ($quantity > 0 ? '+' : '') . $quantity;
}

function signedMoney(int $amount): string {
    return ($amount > 0 ? '+' : '') . money($amount);
}

function marginText(int $profit, int $revenue): string {
    if ($revenue === 0) {
        return 'n/a';
    }
    $tenths = intdiv(abs($profit) * 1000, $revenue);
    return ($profit < 0 && $tenths !== 0 ? '-' : '')
        . intdiv($tenths, 10) . '.' . ($tenths % 10) . '%';
}

function stockQuantity(array $stocks): int {
    $total = 0;
    foreach ($stocks as $stock) {
        $total += $stock->quantity;
    }
    return $total;
}

function stockValue(array $stocks): int {
    $total = 0;
    foreach ($stocks as $stock) {
        $total += $stock->quantity * $stock->cost;
    }
    return $total;
}

class CommandError extends RuntimeException {}

class Inventory {
    private int $day = 1;
    private array $stock = [];
    private array $items = [];
    private array $lots = [];
    private array $orders = [];
    private array $totals = [];
    private array $output = [];

    public function __construct() {
        foreach (CATEGORIES as $category) {
            $this->totals[$category] = (object)['quantity' => 0, 'value' => 0];
        }
    }

    private function emit(int $indent, ...$parts): void {
        $this->output[] = str_repeat(' ', $indent) . implode(' ', array_map('strval', $parts));
    }

    private function warehouse(string $code): string {
        if (!array_key_exists($code, $this->stock)) {
            throw new CommandError("unknown warehouse $code");
        }
        return $code;
    }

    private function item(string $code): object {
        if (!isset($this->items[$code])) {
            throw new CommandError("unknown item $code");
        }
        return $this->items[$code];
    }

    private function pair(string $warehouse, string $code): object {
        $this->warehouse($warehouse);
        return $this->item($code);
    }

    private function order(string $text): object {
        $number = (int)$text;
        if ($number < 1 || $number > count($this->orders)) {
            throw new CommandError("unknown order $text");
        }
        return $this->orders[$number - 1];
    }

    private function lot(string $text): object {
        $number = (int)$text;
        if ($number < 1 || $number > count($this->lots)) {
            throw new CommandError("unknown lot $text");
        }
        return $this->lots[$number - 1];
    }

    private function requireQuantity(int $quantity): void {
        if ($quantity === 0) {
            throw new CommandError('invalid quantity');
        }
    }

    private function holdings(string $warehouse, string $code): array {
        return $this->stock[$warehouse][$code] ?? [];
    }

    private function fifo(string $warehouse, string $code): array {
        $stocks = array_values($this->holdings($warehouse, $code));
        usort($stocks, static fn($a, $b) =>
            ($a->lot->day <=> $b->lot->day) ?: ($a->lot->number <=> $b->lot->number));
        return $stocks;
    }

    private function quantity(string $warehouse, string $code): int {
        return stockQuantity($this->holdings($warehouse, $code));
    }

    private function totalQuantity(string $code): int {
        $quantity = 0;
        foreach (array_keys($this->stock) as $warehouse) {
            $quantity += $this->quantity($warehouse, $code);
        }
        return $quantity;
    }

    private function backorder(string $code): int {
        $quantity = 0;
        foreach ($this->orders as $order) {
            if ($order->item === $code) {
                $quantity += $order->backorder;
            }
        }
        return $quantity;
    }

    private function allStocks(): array {
        $stocks = [];
        foreach ($this->stock as $items) {
            foreach ($items as $holdings) {
                array_push($stocks, ...array_values($holdings));
            }
        }
        return $stocks;
    }

    private function requireStock(string $warehouse, string $code, int $quantity): void {
        $held = $this->quantity($warehouse, $code);
        if ($held < $quantity) {
            throw new CommandError("insufficient stock $warehouse $code $held");
        }
    }

    private function cardEntry(string $code, string $kind, string $warehouse, int $quantity, int $value): void {
        $this->items[$code]->card[] = (object)[
            'day' => $this->day, 'kind' => $kind, 'warehouse' => $warehouse,
            'quantity' => $quantity, 'value' => $value,
        ];
    }

    private function accumulate(string $category, int $quantity, int $value): void {
        $this->totals[$category]->quantity += $quantity;
        $this->totals[$category]->value += $value;
    }

    private function addStock(string $warehouse, object $lot, int $quantity, int $cost): void {
        $this->stock[$warehouse][$lot->item] ??= [];
        if (isset($this->stock[$warehouse][$lot->item][$lot->number])) {
            $this->stock[$warehouse][$lot->item][$lot->number]->quantity += $quantity;
        } else {
            $this->stock[$warehouse][$lot->item][$lot->number] = (object)[
                'lot' => $lot, 'quantity' => $quantity, 'cost' => $cost,
            ];
        }
    }

    private function createLot(
        string $warehouse, string $code, int $day, int $quantity, int $cost, string $kind
    ): object {
        $lot = (object)[
            'number' => count($this->lots) + 1, 'item' => $code,
            'day' => $day, 'initialQuantity' => $quantity, 'initialCost' => $cost,
            'warehouse' => $warehouse, 'kind' => $kind, 'removed' => 0,
        ];
        $this->lots[] = $lot;
        $this->addStock($warehouse, $lot, $quantity, $cost);
        return $lot;
    }

    private function issue(string $warehouse, string $code, int $quantity): array {
        $parts = [];
        $cost = 0;
        foreach ($this->fifo($warehouse, $code) as $stock) {
            if ($quantity === 0) {
                break;
            }
            $taken = min($quantity, $stock->quantity);
            $parts[] = (object)['lot' => $stock->lot, 'quantity' => $taken, 'cost' => $stock->cost];
            $cost += $taken * $stock->cost;
            $stock->quantity -= $taken;
            $quantity -= $taken;
            if ($stock->quantity === 0) {
                unset($this->stock[$warehouse][$code][$stock->lot->number]);
            }
        }
        return [$parts, $cost];
    }

    private function fulfil(object $order, int $quantity, string $kind): int {
        if ($quantity === 0) {
            return 0;
        }
        [$parts, $cost] = $this->issue($order->warehouse, $order->item, $quantity);
        $order->shipped += $quantity;
        $order->backorder -= $quantity;
        $order->revenue += $quantity * $order->price;
        $order->cogs += $cost;
        array_push($order->issues, ...$parts);
        $this->accumulate('shipped', $quantity, $cost);
        $this->cardEntry($order->item, $kind, $order->warehouse, -$quantity, -$cost);
        return $cost;
    }

    private function allocate(string $warehouse, string $code): void {
        $available = $this->quantity($warehouse, $code);
        foreach ($this->orders as $order) {
            if ($available === 0) {
                break;
            }
            if ($order->warehouse !== $warehouse || $order->item !== $code || $order->backorder === 0) {
                continue;
            }
            $quantity = min($available, $order->backorder);
            $cost = $this->fulfil($order, $quantity, 'fill');
            $revenue = $quantity * $order->price;
            $available -= $quantity;
            $this->emit(2, 'FILL', 'order', $order->number, 'qty', $quantity,
                'revenue', money($revenue), 'cogs', money($cost), 'profit',
                money($revenue - $cost), 'backorder', $order->backorder);
        }
    }

    private function removeParts(array $parts): void {
        foreach ($parts as $part) {
            $part->lot->removed += $part->quantity;
        }
    }

    private function sales(): array {
        $rows = [];
        foreach ($this->orders as $order) {
            if (!isset($rows[$order->item])) {
                $rows[$order->item] = (object)['quantity' => 0, 'revenue' => 0, 'cogs' => 0];
            }
            $row = $rows[$order->item];
            $row->quantity += $order->shipped - $order->returned;
            $row->revenue += $order->revenue;
            $row->cogs += $order->cogs;
        }
        return $rows;
    }

    private function marginLine(string $label, object $row): void {
        $profit = $row->revenue - $row->cogs;
        $this->emit(2, $label, 'sold', $row->quantity, 'revenue', money($row->revenue),
            'cogs', money($row->cogs), 'profit', money($profit),
            'margin', marginText($profit, $row->revenue));
    }

    private function agingLine(string $label, array $buckets, bool $monetary = false): void {
        $names = ['0-30', '31-60', '61-90', '91+'];
        $parts = [$label];
        for ($i = 0; $i < 4; ++$i) {
            $parts[] = $names[$i];
            $parts[] = $monetary ? money($buckets[$i]) : $buckets[$i];
        }
        $this->emit(2, ...$parts);
    }

    private function sortedWarehouses(): array {
        $names = array_keys($this->stock);
        sort($names, SORT_STRING);
        return $names;
    }

    private function sortedItems(): array {
        $names = array_keys($this->items);
        sort($names, SORT_STRING);
        return $names;
    }

    private function command(string $command, array $a): void {
        switch ($command) {
            case 'DAY':
                $day = (int)$a[0];
                if ($day <= $this->day) {
                    throw new CommandError("invalid day $a[0]");
                }
                $this->day = $day;
                $this->emit(0, 'DAY', $day);
                return;

            case 'WAREHOUSE':
                $warehouse = $a[0];
                if (array_key_exists($warehouse, $this->stock)) {
                    throw new CommandError("duplicate warehouse $warehouse");
                }
                $this->stock[$warehouse] = [];
                $this->emit(0, 'WAREHOUSE', $warehouse);
                return;

            case 'ITEM':
                [$code, $level, $name] = $a;
                if (isset($this->items[$code])) {
                    $item = $this->items[$code];
                    $item->level = (int)$level;
                    $item->name = $name;
                    $action = 'updated';
                } else {
                    $this->items[$code] = (object)[
                        'code' => $code, 'level' => (int)$level, 'name' => $name,
                        'lastCost' => null, 'card' => [],
                    ];
                    $action = 'added';
                }
                $this->emit(0, 'ITEM', $code, $action, $name, 'level', (int)$level);
                return;

            case 'RECEIVE':
                [$warehouse, $code] = $a;
                $item = $this->pair($warehouse, $code);
                $quantity = (int)$a[2];
                $cost = cents($a[3]);
                $day = (int)$a[4];
                $this->requireQuantity($quantity);
                if ($day > $this->day) {
                    throw new CommandError("future day $a[4]");
                }
                $lot = $this->createLot($warehouse, $code, $day, $quantity, $cost, 'receive');
                $item->lastCost = $cost;
                $amount = $quantity * $cost;
                $this->accumulate('received', $quantity, $amount);
                $this->cardEntry($code, 'receive', $warehouse, $quantity, $amount);
                $this->emit(0, 'RECEIVE', $warehouse, $code, 'lot', $lot->number, 'qty',
                    $quantity, 'cost', money($cost), 'day', $day, 'value', money($amount));
                $this->allocate($warehouse, $code);
                return;

            case 'SHIP':
                [$warehouse, $code] = $a;
                $this->pair($warehouse, $code);
                $quantity = (int)$a[2];
                $this->requireQuantity($quantity);
                $order = (object)[
                    'number' => count($this->orders) + 1, 'warehouse' => $warehouse,
                    'item' => $code, 'day' => $this->day, 'price' => cents($a[3]),
                    'ordered' => $quantity, 'shipped' => 0, 'backorder' => $quantity,
                    'cancelled' => 0, 'returned' => 0, 'revenue' => 0, 'cogs' => 0,
                    'issues' => [],
                ];
                $this->orders[] = $order;
                $filled = min($quantity, $this->quantity($warehouse, $code));
                $cost = $this->fulfil($order, $filled, 'ship');
                $this->emit(0, 'SHIP', 'order', $order->number, $warehouse, $code, 'shipped',
                    $filled, 'revenue', money($order->revenue), 'cogs', money($cost),
                    'profit', money($order->revenue - $cost), 'backorder', $order->backorder);
                return;

            case 'CANCEL':
                $order = $this->order($a[0]);
                if ($order->backorder === 0) {
                    throw new CommandError("no backorder $a[0]");
                }
                $order->cancelled += $order->backorder;
                $order->backorder = 0;
                $this->emit(0, 'CANCEL', 'order', $order->number, 'qty', $order->cancelled);
                return;

            case 'TRANSFER':
                [$source, $destination, $code] = $a;
                $this->warehouse($source);
                $this->warehouse($destination);
                if ($source === $destination) {
                    throw new CommandError("same warehouse $source");
                }
                $this->item($code);
                $quantity = (int)$a[3];
                $this->requireQuantity($quantity);
                $this->requireStock($source, $code, $quantity);
                [$parts, $cost] = $this->issue($source, $code, $quantity);
                foreach ($parts as $part) {
                    $this->addStock($destination, $part->lot, $part->quantity, $part->cost);
                }
                $this->cardEntry($code, 'transfer-out', $source, -$quantity, -$cost);
                $this->cardEntry($code, 'transfer-in', $destination, $quantity, $cost);
                $this->emit(0, 'TRANSFER', $source, '->', $destination, $code, 'qty',
                    $quantity, 'value', money($cost), 'lots', count($parts));
                $this->allocate($destination, $code);
                return;

            case 'ADJUST':
                [$warehouse, $code, $change] = $a;
                $this->pair($warehouse, $code);
                $quantity = (int)substr($change, 1);
                $this->requireQuantity($quantity);
                if ($change[0] === '+') {
                    $cost = cents($a[3]);
                    $amount = $quantity * $cost;
                    $lot = $this->createLot($warehouse, $code, $this->day, $quantity, $cost, 'adjust');
                    $this->accumulate('adjusted-in', $quantity, $amount);
                    $this->cardEntry($code, 'adjust', $warehouse, $quantity, $amount);
                    $this->emit(0, 'ADJUST', $warehouse, $code, "+$quantity",
                        'lot', $lot->number, 'value', money($amount));
                    $this->allocate($warehouse, $code);
                } else {
                    $this->requireStock($warehouse, $code, $quantity);
                    [$parts, $cost] = $this->issue($warehouse, $code, $quantity);
                    $this->removeParts($parts);
                    $this->accumulate('adjusted-out', $quantity, $cost);
                    $this->cardEntry($code, 'adjust', $warehouse, -$quantity, -$cost);
                    $this->emit(0, 'ADJUST', $warehouse, $code, "-$quantity", 'value', money($cost));
                }
                return;

            case 'RETURN':
                $order = $this->order($a[0]);
                $quantity = (int)$a[1];
                $cost = cents($a[2]);
                $this->requireQuantity($quantity);
                $available = $order->shipped - $order->returned;
                if ($quantity > $available) {
                    throw new CommandError("return exceeds shipped $a[0] $available");
                }
                $lot = $this->createLot($order->warehouse, $order->item,
                    $this->day, $quantity, $cost, 'return');
                $amount = $quantity * $cost;
                $refund = $quantity * $order->price;
                $order->returned += $quantity;
                $order->revenue -= $refund;
                $order->cogs -= $amount;
                $this->accumulate('returned', $quantity, $amount);
                $this->cardEntry($order->item, 'return', $order->warehouse, $quantity, $amount);
                $this->emit(0, 'RETURN', 'order', $order->number, $order->warehouse, $order->item,
                    'qty', $quantity, 'lot', $lot->number, 'refund', money($refund), 'value', money($amount));
                $this->allocate($order->warehouse, $order->item);
                return;

            case 'COUNT':
                [$warehouse, $code] = $a;
                $item = $this->pair($warehouse, $code);
                $actual = (int)$a[2];
                $held = $this->quantity($warehouse, $code);
                if ($actual === $held) {
                    $this->emit(0, 'COUNT', $warehouse, $code, 'qty', $actual, 'ok');
                } elseif ($actual < $held) {
                    $quantity = $held - $actual;
                    [$parts, $cost] = $this->issue($warehouse, $code, $quantity);
                    $this->removeParts($parts);
                    $this->accumulate('adjusted-out', $quantity, $cost);
                    $this->cardEntry($code, 'count', $warehouse, -$quantity, -$cost);
                    $this->emit(0, 'COUNT', $warehouse, $code, 'qty', $held, '->', $actual,
                        'shortage', $quantity, 'value', money($cost));
                } else {
                    $quantity = $actual - $held;
                    $cost = $item->lastCost ?? 0;
                    $amount = $quantity * $cost;
                    $lot = $this->createLot($warehouse, $code, $this->day, $quantity, $cost, 'count');
                    $this->accumulate('adjusted-in', $quantity, $amount);
                    $this->cardEntry($code, 'count', $warehouse, $quantity, $amount);
                    $this->emit(0, 'COUNT', $warehouse, $code, 'qty', $held, '->', $actual,
                        'surplus', $quantity, 'lot', $lot->number, 'value', money($amount));
                    $this->allocate($warehouse, $code);
                }
                return;

            case 'MARKET':
                $this->item($a[0]);
                $price = cents($a[1]);
                $changed = 0;
                $quantity = 0;
                $loss = 0;
                foreach ($this->sortedWarehouses() as $warehouse) {
                    $warehouseLoss = 0;
                    foreach ($this->holdings($warehouse, $a[0]) as $stock) {
                        if ($stock->cost <= $price) {
                            continue;
                        }
                        $warehouseLoss += $stock->quantity * ($stock->cost - $price);
                        ++$changed;
                        $quantity += $stock->quantity;
                        $stock->cost = $price;
                    }
                    if ($warehouseLoss > 0) {
                        $this->cardEntry($a[0], 'writedown', $warehouse, 0, -$warehouseLoss);
                    }
                    $loss += $warehouseLoss;
                }
                $this->accumulate('written-down', $quantity, $loss);
                $this->emit(0, 'MARKET', $a[0], 'price', money($price),
                    'lots', $changed, 'qty', $quantity, 'loss', money($loss));
                return;

            case 'RECALL':
                $lot = $this->lot($a[0]);
                $held = [];
                foreach ($this->sortedWarehouses() as $warehouse) {
                    $stock = $this->stock[$warehouse][$lot->item][$lot->number] ?? null;
                    if ($stock !== null) {
                        $held[] = (object)['warehouse' => $warehouse, 'stock' => $stock];
                    }
                }
                if (!$held) {
                    throw new CommandError("nothing to recall $a[0]");
                }
                $quantity = 0;
                $amount = 0;
                foreach ($held as $entry) {
                    $quantity += $entry->stock->quantity;
                    $amount += $entry->stock->quantity * $entry->stock->cost;
                    unset($this->stock[$entry->warehouse][$lot->item][$lot->number]);
                    $this->cardEntry($lot->item, 'recall', $entry->warehouse,
                        -$entry->stock->quantity, -$entry->stock->quantity * $entry->stock->cost);
                }
                $lot->removed += $quantity;
                $this->accumulate('recalled', $quantity, $amount);
                $this->emit(0, 'RECALL', 'lot', $lot->number, $lot->item, 'qty', $quantity, 'value', money($amount));
                foreach ($held as $entry) {
                    $this->emit(2, $entry->warehouse, 'qty', $entry->stock->quantity,
                        'value', money($entry->stock->quantity * $entry->stock->cost));
                }
                return;

            case 'EXPIRE':
                $days = (int)$a[0];
                $this->emit(0, 'EXPIRE', $days);
                $totalQuantity = 0;
                $totalValue = 0;
                foreach ($this->sortedItems() as $code) {
                    foreach ($this->sortedWarehouses() as $warehouse) {
                        $expired = array_filter($this->holdings($warehouse, $code),
                            fn($stock) => $this->day - $stock->lot->day > $days);
                        if (!$expired) {
                            continue;
                        }
                        $quantity = stockQuantity($expired);
                        $value = stockValue($expired);
                        foreach ($expired as $stock) {
                            $stock->lot->removed += $stock->quantity;
                            unset($this->stock[$warehouse][$code][$stock->lot->number]);
                        }
                        $this->accumulate('expired', $quantity, $value);
                        $this->cardEntry($code, 'expire', $warehouse, -$quantity, -$value);
                        $totalQuantity += $quantity;
                        $totalValue += $value;
                        $this->emit(2, $code, $warehouse, 'lots', count($expired),
                            'qty', $quantity, 'value', money($value));
                    }
                }
                $this->emit(2, 'total', 'qty', $totalQuantity, 'value', money($totalValue));
                return;

            case 'VALUE':
            case 'AGING':
                $warehouses = $a ? [$this->warehouse($a[0])] : $this->sortedWarehouses();
                if ($command === 'VALUE') {
                    $this->emit(0, 'VALUE', ...$a);
                } else {
                    $this->emit(0, 'AGING', ...array_merge($a, ['day', $this->day]));
                }
                $totalQuantity = 0;
                $totalValue = 0;
                $bucketQuantity = [0, 0, 0, 0];
                $bucketValue = [0, 0, 0, 0];
                foreach ($this->sortedItems() as $code) {
                    $stocks = [];
                    $rows = [];
                    foreach ($warehouses as $warehouse) {
                        $held = array_values($this->holdings($warehouse, $code));
                        $rows[$warehouse] = $held;
                        array_push($stocks, ...$held);
                    }
                    $quantity = stockQuantity($stocks);
                    if ($quantity === 0) {
                        continue;
                    }
                    $value = stockValue($stocks);
                    if ($command === 'VALUE') {
                        $this->emit(2, $code, 'qty', $quantity, 'value', money($value),
                            'avg', money(intdiv($value, $quantity)));
                        if (!$a) {
                            foreach ($rows as $warehouse => $held) {
                                $warehouseQuantity = stockQuantity($held);
                                if ($warehouseQuantity !== 0) {
                                    $this->emit(4, $warehouse, 'qty', $warehouseQuantity,
                                        'value', money(stockValue($held)));
                                }
                            }
                        }
                    } else {
                        $itemBuckets = [0, 0, 0, 0];
                        foreach ($stocks as $stock) {
                            $age = $this->day - $stock->lot->day;
                            $bucket = $age <= 30 ? 0 : ($age <= 60 ? 1 : ($age <= 90 ? 2 : 3));
                            $itemBuckets[$bucket] += $stock->quantity;
                            $bucketQuantity[$bucket] += $stock->quantity;
                            $bucketValue[$bucket] += $stock->quantity * $stock->cost;
                        }
                        $this->agingLine($code, $itemBuckets);
                    }
                    $totalQuantity += $quantity;
                    $totalValue += $value;
                }
                if ($command === 'VALUE') {
                    $this->emit(2, 'total', 'qty', $totalQuantity, 'value', money($totalValue));
                } else {
                    $this->agingLine('total', $bucketQuantity);
                    $this->agingLine('value', $bucketValue, true);
                }
                return;

            case 'LOTS':
                [$warehouse, $code] = $a;
                $this->pair($warehouse, $code);
                $this->emit(0, 'LOTS', $warehouse, $code);
                $stocks = $this->fifo($warehouse, $code);
                $backorders = array_filter($this->orders,
                    fn($order) => $order->warehouse === $warehouse && $order->item === $code && $order->backorder > 0);
                foreach ($stocks as $stock) {
                    $this->emit(2, 'lot', $stock->lot->number, 'day', $stock->lot->day,
                        'qty', $stock->quantity, 'cost', money($stock->cost),
                        'value', money($stock->quantity * $stock->cost),
                        'age', $this->day - $stock->lot->day);
                }
                foreach ($backorders as $order) {
                    $this->emit(2, 'backorder', 'order', $order->number, 'qty', $order->backorder);
                }
                if (!$stocks && !$backorders) {
                    $this->emit(2, '(none)');
                }
                return;

            case 'REORDER':
            case 'ITEMS':
                $this->emit(0, $command);
                $found = false;
                foreach ($this->sortedItems() as $code) {
                    $item = $this->items[$code];
                    $quantity = $this->totalQuantity($code);
                    $backorder = $this->backorder($code);
                    if ($command === 'REORDER') {
                        if ($quantity - $backorder > $item->level) {
                            continue;
                        }
                        $this->emit(2, $code, $item->name, 'onhand', $quantity,
                            'backorder', $backorder, 'level', $item->level);
                    } else {
                        $this->emit(2, $code, $item->name, 'level', $item->level,
                            'onhand', $quantity, 'backorder', $backorder, 'cost',
                            $item->lastCost === null ? 'none' : money($item->lastCost));
                    }
                    $found = true;
                }
                if (!$found) {
                    $this->emit(2, '(none)');
                }
                return;

            case 'MARGIN':
            case 'TOP':
                $rows = $this->sales();
                if ($command === 'MARGIN') {
                    $this->emit(0, 'MARGIN');
                    $total = (object)['quantity' => 0, 'revenue' => 0, 'cogs' => 0];
                    $codes = array_keys($rows);
                    sort($codes, SORT_STRING);
                    foreach ($codes as $code) {
                        $row = $rows[$code];
                        $this->marginLine($code, $row);
                        $total->quantity += $row->quantity;
                        $total->revenue += $row->revenue;
                        $total->cogs += $row->cogs;
                    }
                    $this->marginLine('total', $total);
                } else {
                    $this->emit(0, 'TOP', (int)$a[0]);
                    $codes = array_keys($rows);
                    usort($codes, static function ($a, $b) use ($rows) {
                        $left = $rows[$a];
                        $right = $rows[$b];
                        return (($right->revenue - $right->cogs) <=> ($left->revenue - $left->cogs))
                            ?: ($right->revenue <=> $left->revenue) ?: strcmp($a, $b);
                    });
                    $limit = min(count($codes), (int)$a[0]);
                    for ($i = 0; $i < $limit; ++$i) {
                        $row = $rows[$codes[$i]];
                        $profit = $row->revenue - $row->cogs;
                        $this->emit(2, $i + 1, $codes[$i], 'profit', money($profit),
                            'revenue', money($row->revenue), 'margin', marginText($profit, $row->revenue));
                    }
                    if (!$codes) {
                        $this->emit(2, '(none)');
                    }
                }
                return;

            case 'BACKORDERS':
                $this->emit(0, 'BACKORDERS');
                $backorders = array_filter($this->orders, static fn($order) => $order->backorder > 0);
                foreach ($backorders as $order) {
                    $this->emit(2, 'order', $order->number, $order->warehouse, $order->item,
                        'qty', $order->backorder, 'day', $order->day, 'price', money($order->price));
                }
                if (!$backorders) {
                    $this->emit(2, '(none)');
                }
                return;

            case 'ORDER':
                $order = $this->order($a[0]);
                $this->emit(0, 'ORDER', $order->number, $order->warehouse, $order->item,
                    'day', $order->day, 'price', money($order->price));
                $this->emit(2, 'ordered', $order->ordered, 'shipped', $order->shipped,
                    'backorder', $order->backorder, 'cancelled', $order->cancelled, 'returned', $order->returned);
                foreach ($order->issues as $part) {
                    $this->emit(2, 'lot', $part->lot->number, 'qty', $part->quantity, 'cost', money($part->cost));
                }
                $this->emit(2, 'revenue', money($order->revenue), 'cogs', money($order->cogs),
                    'profit', money($order->revenue - $order->cogs));
                return;

            case 'TRACE':
                $lot = $this->lot($a[0]);
                $this->emit(0, 'TRACE', 'lot', $lot->number, $lot->item, $lot->kind,
                    $lot->warehouse, 'day', $lot->day, 'qty', $lot->initialQuantity,
                    'cost', money($lot->initialCost));
                foreach ($this->sortedWarehouses() as $warehouse) {
                    $stock = $this->stock[$warehouse][$lot->item][$lot->number] ?? null;
                    if ($stock !== null) {
                        $this->emit(2, 'held', $warehouse, 'qty', $stock->quantity, 'cost', money($stock->cost));
                    }
                }
                foreach ($this->orders as $order) {
                    $quantity = 0;
                    foreach ($order->issues as $part) {
                        if ($part->lot->number === $lot->number) {
                            $quantity += $part->quantity;
                        }
                    }
                    if ($quantity > 0) {
                        $this->emit(2, 'order', $order->number, 'qty', $quantity);
                    }
                }
                if ($lot->removed !== 0) {
                    $this->emit(2, 'removed', 'qty', $lot->removed);
                }
                return;

            case 'CARD':
                $item = $this->item($a[0]);
                $this->emit(0, 'CARD', $item->code, $item->name);
                $quantity = 0;
                $value = 0;
                foreach ($item->card as $entry) {
                    $quantity += $entry->quantity;
                    $value += $entry->value;
                    $this->emit(2, 'day', $entry->day, $entry->kind, $entry->warehouse,
                        signedQuantity($entry->quantity), signedMoney($entry->value),
                        'balance', $quantity, money($value));
                }
                if (!$item->card) {
                    $this->emit(2, '(none)');
                }
                return;

            case 'STATUS':
                $this->emit(0, 'STATUS');
                foreach ($this->sortedWarehouses() as $warehouse) {
                    $skus = 0;
                    $stocks = [];
                    foreach ($this->stock[$warehouse] as $holdings) {
                        if ($holdings) {
                            ++$skus;
                        }
                        array_push($stocks, ...array_values($holdings));
                    }
                    $backorder = 0;
                    foreach ($this->orders as $order) {
                        if ($order->warehouse === $warehouse) {
                            $backorder += $order->backorder;
                        }
                    }
                    $this->emit(2, $warehouse, 'skus', $skus, 'qty', stockQuantity($stocks),
                        'value', money(stockValue($stocks)), 'backorder', $backorder);
                }
                if (!$this->stock) {
                    $this->emit(2, '(none)');
                }
                return;

            case 'SUMMARY':
                $this->emit(0, 'SUMMARY');
                foreach (CATEGORIES as $category) {
                    $total = $this->totals[$category];
                    $this->emit(2, $category, 'qty', $total->quantity, 'value', money($total->value));
                }
                $stocks = $this->allStocks();
                $this->emit(2, 'on-hand', 'qty', stockQuantity($stocks), 'value', money(stockValue($stocks)));
                $open = 0;
                $backorder = 0;
                foreach ($this->orders as $order) {
                    if ($order->backorder > 0) {
                        ++$open;
                    }
                    $backorder += $order->backorder;
                }
                $this->emit(2, 'orders', count($this->orders), 'open', $open, 'backorder', $backorder);
                return;
        }
    }

    public function execute(string $line): void {
        $parts = explode(' ', $line);
        $command = array_shift($parts);
        try {
            $this->command($command, $parts);
        } catch (CommandError $error) {
            $this->emit(0, 'ERROR', $error->getMessage());
        }
    }

    public function result(): string {
        return implode("\n", $this->output) . "\n";
    }
}

$number = (int)trim(fgets(STDIN));
$inventory = new Inventory();
for ($i = 0; $i < $number; ++$i) {
    $inventory->execute(rtrim((string)fgets(STDIN), "\r\n"));
}
echo $inventory->result();
