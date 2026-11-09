<?php
class Element
{
    public array $children = [];
    public array $overrides = [];
    public array $style = [];
    public array $margin = [];
    public array $padding = [];
    public array $border = [];
    public bool $displayed = false;
    public int $cw = 0;
    public int $ch = 0;
    public int $natural = 0;
    public int $rx = 0;
    public int $ry = 0;
    public int $x = 0;
    public int $y = 0;
    public array $lines = [];
    public ?int $maximum = null;
    public ?int $contribution = null;
    public ?Element $containing = null;

    public function __construct(public string $type, public string $id, public array $classes, public ?string $text, public ?Element $parent, public int $depth, public int $index)
    {
    }

    public function frame(bool $horizontal): int
    {
        $sides = $horizontal ? [1, 3] : [0, 2];
        return $this->padding[$sides[0]] + $this->padding[$sides[1]] + $this->border[$sides[0]] + $this->border[$sides[1]];
    }

    public function margins(bool $horizontal): int
    {
        return $horizontal ? $this->margin[1] + $this->margin[3] : $this->margin[0] + $this->margin[2];
    }

    public function width(): int
    {
        return $this->cw + $this->frame(true);
    }

    public function height(): int
    {
        return $this->ch + $this->frame(false);
    }
}

class BoxLayout
{
    private const SIDES = ['top', 'right', 'bottom', 'left'];
    private const CHOICES = [
        'display' => ['block', 'flex', 'grid', 'none'],
        'position' => ['static', 'relative', 'absolute'],
        'box-sizing' => ['content-box', 'border-box'],
        'flex-direction' => ['row', 'row-reverse', 'column', 'column-reverse'],
        'flex-wrap' => ['nowrap', 'wrap'],
        'justify-content' => ['start', 'end', 'center', 'space-between', 'space-around', 'space-evenly'],
        'align-items' => ['stretch', 'start', 'end', 'center'],
        'align-self' => ['auto', 'stretch', 'start', 'end', 'center']
    ];
    private array $ids = [];

    public function __construct(private int $width, private int $height, private array $rules, private array $elements)
    {
        foreach ($elements as $element) {
            $this->ids[$element->id] = $element;
        }
        $this->relayout();
    }

    private static function defaults(): array
    {
        $values = [
            'display' => 'block', 'position' => 'static', 'box-sizing' => 'content-box',
            'width' => 'auto', 'height' => 'auto', 'min-width' => '0', 'min-height' => '0',
            'max-width' => 'none', 'max-height' => 'none', 'top' => 'auto', 'right' => 'auto',
            'bottom' => 'auto', 'left' => 'auto', 'flex-direction' => 'row', 'flex-wrap' => 'nowrap',
            'justify-content' => 'start', 'align-items' => 'stretch', 'align-self' => 'auto',
            'row-gap' => '0', 'column-gap' => '0', 'order' => '0', 'flex-grow' => '0',
            'flex-shrink' => '1', 'flex-basis' => 'auto', 'grid-template-columns' => 'none',
            'grid-template-rows' => 'none', 'grid-column' => 'auto', 'grid-row' => 'auto'
        ];
        foreach (['margin', 'padding', 'border'] as $prefix) {
            foreach (self::SIDES as $side) {
                $values["$prefix-$side"] = '0';
            }
        }
        return $values;
    }

    private static function integer(string $text): bool
    {
        return preg_match('/\A[0-9]{1,3}\z/D', $text) === 1;
    }

    private static function positive(string $text): bool
    {
        return self::integer($text) && (int)$text > 0;
    }

    private static function signed(string $text): bool
    {
        return self::integer($text) || (str_starts_with($text, '-') && self::integer(substr($text, 1)));
    }

    private static function percentage(string $text): bool
    {
        return str_ends_with($text, '%') && self::integer(substr($text, 0, -1));
    }

    private static function fraction(string $text): bool
    {
        return str_ends_with($text, 'fr') && self::positive(substr($text, 0, -2));
    }

    public static function known(string $property): bool
    {
        return isset(self::defaults()[$property]) || in_array($property, ['margin', 'padding', 'border', 'gap'], true);
    }

    public static function declaration(string $property, string $value): ?array
    {
        if (!self::known($property)) {
            return null;
        }
        $tokens = explode(' ', $value);
        if (in_array($property, ['margin', 'padding', 'border'], true)) {
            if (count($tokens) < 1 || count($tokens) > 4) {
                return null;
            }
            foreach ($tokens as $token) {
                if ($property === 'border' ? !in_array($token, ['0', '1'], true) : !self::integer($token)) {
                    return null;
                }
            }
            $expanded = [$tokens[0], $tokens[1] ?? $tokens[0], $tokens[2] ?? $tokens[0], $tokens[3] ?? $tokens[1] ?? $tokens[0]];
            $result = [];
            foreach (self::SIDES as $i => $side) {
                $result[] = ["$property-$side", $expanded[$i]];
            }
            return $result;
        }
        if ($property === 'gap') {
            if (count($tokens) > 2) {
                return null;
            }
            foreach ($tokens as $token) {
                if (!self::integer($token)) {
                    return null;
                }
            }
            return [['row-gap', $tokens[0]], ['column-gap', $tokens[count($tokens) - 1]]];
        }
        $valid = false;
        if ($property === 'grid-template-columns' || $property === 'grid-template-rows') {
            $valid = $value === 'none';
            if (!$valid) {
                $valid = true;
                foreach ($tokens as $token) {
                    if ($token !== 'auto' && !self::integer($token) && !self::fraction($token)) {
                        $valid = false;
                    }
                }
            }
        } elseif ($property === 'grid-column' || $property === 'grid-row') {
            $valid = $value === 'auto'
                || (count($tokens) === 1 && self::positive($tokens[0]))
                || (count($tokens) === 2 && $tokens[0] === 'span' && self::positive($tokens[1]))
                || (count($tokens) === 3 && self::positive($tokens[0]) && $tokens[1] === '/' && self::positive($tokens[2]) && (int)$tokens[0] < (int)$tokens[2])
                || (count($tokens) === 4 && self::positive($tokens[0]) && $tokens[1] === '/' && $tokens[2] === 'span' && self::positive($tokens[3]));
        } elseif (count($tokens) === 1) {
            if (isset(self::CHOICES[$property])) {
                $valid = in_array($value, self::CHOICES[$property], true);
            } elseif (in_array($property, ['width', 'height', 'flex-basis'], true)) {
                $valid = $value === 'auto' || self::integer($value) || self::percentage($value);
            } elseif (in_array($property, ['min-width', 'min-height'], true)) {
                $valid = self::integer($value) || self::percentage($value);
            } elseif (in_array($property, ['max-width', 'max-height'], true)) {
                $valid = $value === 'none' || self::integer($value) || self::percentage($value);
            } elseif (in_array($property, ['top', 'right', 'bottom', 'left'], true)) {
                $valid = $value === 'auto' || self::signed($value);
            } elseif ($property === 'order') {
                $valid = self::signed($value);
            } elseif (str_starts_with($property, 'border-')) {
                $valid = in_array($value, ['0', '1'], true);
            } else {
                $valid = self::integer($value);
            }
        }
        return $valid ? [[$property, $value]] : null;
    }

    private function children(Element $element, bool $ordered = false): array
    {
        $result = array_values(array_filter($element->children, fn($e) => $e->displayed && $e->style['position'] !== 'absolute'));
        if ($ordered) {
            usort($result, fn($a, $b) => [(int)$a->style['order'], $a->index] <=> [(int)$b->style['order'], $b->index]);
        }
        return $result;
    }

    private function align(Element $parent, Element $child): string
    {
        return $child->style['align-self'] === 'auto' ? $parent->style['align-items'] : $child->style['align-self'];
    }

    private function resolve(Element $element, string $property, ?int $reference, bool $horizontal): ?int
    {
        $value = $element->style[$property];
        if ($value === 'auto' || $value === 'none' || (str_ends_with($value, '%') && $reference === null)) {
            return null;
        }
        $result = str_ends_with($value, '%') ? intdiv($reference * (int)$value, 100) : (int)$value;
        return $element->style['box-sizing'] === 'border-box' ? max(0, $result - $element->frame($horizontal)) : $result;
    }

    private function clamp(Element $element, int $value, ?int $reference, bool $horizontal): int
    {
        $axis = $horizontal ? 'width' : 'height';
        $lower = $this->resolve($element, 'min-' . $axis, $reference, $horizontal) ?? 0;
        $upper = $this->resolve($element, 'max-' . $axis, $reference, $horizontal);
        if ($upper !== null) {
            $value = min($value, $upper);
        }
        return max($value, $lower);
    }

    private function distribute(int $total, array $weights): array
    {
        $sum = array_sum($weights);
        $result = array_fill(0, count($weights), 0);
        if ($sum === 0) {
            return $result;
        }
        foreach ($weights as $i => $weight) {
            $result[$i] = intdiv($total * $weight, $sum);
        }
        $remainder = $total - array_sum($result);
        foreach ($weights as $i => $weight) {
            if ($remainder === 0) {
                break;
            }
            if ($weight > 0) {
                $result[$i]++;
                $remainder--;
            }
        }
        return $result;
    }

    private function gridPosition(string $value): array
    {
        $tokens = explode(' ', $value);
        if ($value === 'auto') {
            return [0, 1];
        }
        if ($tokens[0] === 'span') {
            return [0, (int)$tokens[1]];
        }
        $start = (int)$tokens[0];
        return [$start, count($tokens) === 1 ? 1 : ($tokens[2] === 'span' ? (int)$tokens[3] : (int)$tokens[2] - $start)];
    }

    private function placement(Element $element): array
    {
        $columns = $element->style['grid-template-columns'] === 'none' ? ['auto'] : explode(' ', $element->style['grid-template-columns']);
        $rows = $element->style['grid-template-rows'] === 'none' ? [] : explode(' ', $element->style['grid-template-rows']);
        $items = [];
        $nc = count($columns);
        foreach ($this->children($element, true) as $child) {
            [$column, $cs] = $this->gridPosition($child->style['grid-column']);
            [$row, $rs] = $this->gridPosition($child->style['grid-row']);
            $items[] = ['element' => $child, 'column' => $column, 'row' => $row, 'cs' => $cs, 'rs' => $rs];
            $nc = max($nc, $column === 0 ? $cs : $column + $cs - 1);
        }
        $occupied = [];
        $overlaps = function (array $item, int $row, int $column) use (&$occupied): bool {
            for ($r = $row; $r < $row + $item['rs']; $r++) {
                for ($c = $column; $c < $column + $item['cs']; $c++) {
                    if (isset($occupied["$r,$c"])) {
                        return true;
                    }
                }
            }
            return false;
        };
        $occupy = function (array $item) use (&$occupied): void {
            for ($r = $item['row']; $r < $item['row'] + $item['rs']; $r++) {
                for ($c = $item['column']; $c < $item['column'] + $item['cs']; $c++) {
                    $occupied["$r,$c"] = true;
                }
            }
        };
        foreach ($items as $item) {
            if ($item['row'] > 0 && $item['column'] > 0) {
                $occupy($item);
            }
        }
        $cr = $cc = 1;
        foreach ($items as &$item) {
            if ($item['row'] > 0 && $item['column'] > 0) {
                continue;
            }
            if ($item['row'] > 0) {
                $column = 1;
                while ($column + $item['cs'] - 1 <= $nc && $overlaps($item, $item['row'], $column)) {
                    $column++;
                }
                $item['column'] = $column + $item['cs'] - 1 <= $nc ? $column : 1;
            } elseif ($item['column'] > 0) {
                if ($item['column'] < $cc) {
                    $cr++;
                }
                $row = $cr;
                while ($overlaps($item, $row, $item['column'])) {
                    $row++;
                }
                $item['row'] = $cr = $row;
                $cc = $item['column'] + $item['cs'];
            } else {
                $row = $cr;
                $column = $cc;
                while (true) {
                    if ($column + $item['cs'] - 1 > $nc) {
                        $row++;
                        $column = 1;
                    } elseif ($overlaps($item, $row, $column)) {
                        $column++;
                    } else {
                        break;
                    }
                }
                $item['row'] = $cr = $row;
                $item['column'] = $column;
                $cc = $column + $item['cs'];
            }
            $occupy($item);
        }
        unset($item);
        $nr = count($rows);
        foreach ($items as $item) {
            $nr = max($nr, $item['row'] + $item['rs'] - 1);
        }
        return ['items' => $items, 'columns' => array_pad($columns, $nc, 'auto'), 'rows' => array_pad($rows, $nr, 'auto')];
    }

    private function trackSizes(array $grid, bool $horizontal, ?int $available, int $gap, array $contributions): array
    {
        $specifications = $grid[$horizontal ? 'columns' : 'rows'];
        $fractional = false;
        foreach ($specifications as $specification) {
            $fractional = $fractional || self::fraction($specification);
        }
        $weights = $sizes = [];
        foreach ($specifications as $i => $specification) {
            $weights[] = $fractional ? (self::fraction($specification) ? (int)$specification : 0) : ($specification === 'auto' ? 1 : 0);
            $size = 0;
            if (self::integer($specification)) {
                $size = (int)$specification;
            } elseif ($specification === 'auto' || $available === null) {
                foreach ($grid['items'] as $j => $item) {
                    if ($item[$horizontal ? 'column' : 'row'] === $i + 1 && $item[$horizontal ? 'cs' : 'rs'] === 1) {
                        $size = max($size, $contributions[$j]);
                    }
                }
            }
            $sizes[] = $size;
        }
        if ($available !== null) {
            $leftover = $available - array_sum($sizes) - $gap * (count($sizes) - 1);
            $additions = $this->distribute(max($leftover, 0), $weights);
            foreach ($additions as $i => $addition) {
                $sizes[$i] += $addition;
            }
        }
        return $sizes;
    }

    private function maxContent(Element $element): int
    {
        if ($element->maximum !== null) {
            return $element->maximum;
        }
        $items = $this->children($element);
        if ($element->text !== null) {
            $value = strlen($element->text);
        } elseif ($element->style['display'] === 'flex' && str_starts_with($element->style['flex-direction'], 'row')) {
            $value = array_sum(array_map(fn($child) => $this->contribution($child), $items)) + (int)$element->style['column-gap'] * max(0, count($items) - 1);
        } elseif ($element->style['display'] === 'grid') {
            $grid = $this->placement($element);
            $values = array_map(fn($item) => $this->contribution($item['element']), $grid['items']);
            $value = array_sum($this->trackSizes($grid, true, null, (int)$element->style['column-gap'], $values)) + (int)$element->style['column-gap'] * (count($grid['columns']) - 1);
        } else {
            $value = $items === [] ? 0 : max(array_map(fn($child) => $this->contribution($child), $items));
        }
        return $element->maximum = $value;
    }

    private function contribution(Element $element): int
    {
        return $element->contribution ??= $this->clamp($element, $this->resolve($element, 'width', null, true) ?? $this->maxContent($element), null, true) + $element->frame(true) + $element->margins(true);
    }

    private function positionChild(Element $parent, Element $child, int $x, int $y): void
    {
        $child->rx = $parent->border[3] + $parent->padding[3] + $x;
        $child->ry = $parent->border[0] + $parent->padding[0] + $y;
    }

    private function layout(Element $element, int $cwReference, ?int $chReference, ?int $fw = null, ?int $fh = null): int
    {
        $element->cw = $fw ?? $this->clamp($element, $this->resolve($element, 'width', $cwReference, true) ?? max(0, $cwReference - $element->frame(true) - $element->margins(true)), $cwReference, true);
        if ($fh === null) {
            $height = $this->resolve($element, 'height', $chReference, false);
            if ($height !== null) {
                $fh = $this->clamp($element, $height, $chReference, false);
            }
        }
        if ($element->text !== null) {
            $element->lines = [];
            foreach (explode(' ', $element->text) as $word) {
                $last = count($element->lines) - 1;
                if ($last >= 0 && strlen($element->lines[$last]) + 1 + strlen($word) <= $element->cw) {
                    $element->lines[$last] .= ' ' . $word;
                } else {
                    $element->lines[] = $word;
                }
            }
            $natural = count($element->lines);
        } elseif ($element->style['display'] === 'flex') {
            $natural = $this->flex($element, $fh, $chReference);
        } elseif ($element->style['display'] === 'grid') {
            $natural = $this->gridLayout($element, $fh);
        } else {
            $natural = $this->block($element, $fh);
        }
        $element->natural = $natural;
        $element->ch = $fh ?? $this->clamp($element, $natural, $chReference, false);
        return $natural;
    }

    private function block(Element $element, ?int $reference): int
    {
        $bottom = 0;
        $previous = null;
        foreach ($this->children($element) as $child) {
            $this->layout($child, $element->cw, $reference);
            $y = $bottom + ($previous === null ? $child->margin[0] : max($previous->margin[2], $child->margin[0]));
            $this->positionChild($element, $child, $child->margin[3], $y);
            $bottom = $y + $child->height();
            $previous = $child;
        }
        return $previous === null ? 0 : $bottom + $previous->margin[2];
    }

    private function flex(Element $element, ?int $reference, ?int $heightReference): int
    {
        $horizontal = str_starts_with($element->style['flex-direction'], 'row');
        $reverse = str_ends_with($element->style['flex-direction'], 'reverse');
        $mainReference = $horizontal ? $element->cw : $reference;
        $gap = (int)$element->style[$horizontal ? 'column-gap' : 'row-gap'];
        $lineGap = (int)$element->style['row-gap'];
        $items = [];
        foreach ($this->children($element, true) as $child) {
            $alignment = $this->align($element, $child);
            $cross = null;
            if (!$horizontal) {
                $room = max(0, $element->cw - $child->frame(true) - $child->margins(true));
                $cross = $this->resolve($child, 'width', $element->cw, true) ?? ($alignment === 'stretch' ? $room : min($this->maxContent($child), $room));
                $cross = $this->clamp($child, $cross, $element->cw, true);
            }
            $base = $this->resolve($child, 'flex-basis', $mainReference, $horizontal) ?? $this->resolve($child, $horizontal ? 'width' : 'height', $mainReference, $horizontal);
            $base ??= $horizontal ? $this->maxContent($child) : $this->layout($child, $element->cw, $reference, $cross);
            $hypothetical = $this->clamp($child, $base, $mainReference, $horizontal);
            $items[] = ['element' => $child, 'align' => $alignment, 'cross' => $cross, 'base' => $base, 'hypothetical' => $hypothetical, 'outer' => $child->frame($horizontal) + $child->margins($horizontal)];
        }
        $mainLength = $horizontal ? $element->cw : $reference;
        if ($mainLength === null) {
            $natural = array_sum(array_map(fn($item) => $item['hypothetical'] + $item['outer'], $items)) + $gap * max(0, count($items) - 1);
            $mainLength = $this->clamp($element, $natural, $heightReference, false);
        }
        $lines = [];
        foreach ($items as $item) {
            $last = count($lines) - 1;
            $currentLength = $last < 0 ? 0 : array_sum(array_map(fn($i) => $i['hypothetical'] + $i['outer'], $lines[$last])) + $gap * count($lines[$last]);
            if ($last < 0 || ($horizontal && $element->style['flex-wrap'] === 'wrap' && $currentLength + $item['hypothetical'] + $item['outer'] > $mainLength)) {
                $lines[] = [];
                $last++;
            }
            $lines[$last][] = $item;
        }
        $crossStart = 0;
        foreach ($lines as $line) {
            $totalGap = $gap * (count($line) - 1);
            $growing = array_sum(array_map(fn($i) => $i['hypothetical'] + $i['outer'], $line)) + $totalGap < $mainLength;
            foreach ($line as &$item) {
                $child = $item['element'];
                $item['weight'] = $growing ? (int)$child->style['flex-grow'] : (int)$child->style['flex-shrink'] * $item['base'];
                $item['size'] = $item['hypothetical'];
                $item['frozen'] = $item['weight'] === 0 || ($growing ? $item['base'] > $item['hypothetical'] : $item['base'] < $item['hypothetical']);
            }
            unset($item);
            while (true) {
                $active = [];
                $free = $mainLength - $totalGap;
                foreach ($line as $i => $item) {
                    $free -= ($item['frozen'] ? $item['size'] : $item['base']) + $item['outer'];
                    if (!$item['frozen']) {
                        $active[] = $i;
                    }
                }
                if ($active === []) {
                    break;
                }
                $assigned = $this->distribute(max(0, $growing ? $free : -$free), array_map(fn($i) => $line[$i]['weight'], $active));
                $violation = 0;
                foreach ($active as $j => $i) {
                    $tentative = $line[$i]['base'] + ($growing ? $assigned[$j] : -$assigned[$j]);
                    $line[$i]['size'] = $this->clamp($line[$i]['element'], $tentative, $mainReference, $horizontal);
                    $line[$i]['violation'] = $line[$i]['size'] - $tentative;
                    $violation += $line[$i]['violation'];
                }
                foreach ($active as $i) {
                    if ($violation === 0 || ($violation > 0 ? $line[$i]['violation'] > 0 : $line[$i]['violation'] < 0)) {
                        $line[$i]['frozen'] = true;
                    }
                }
            }
            if ($horizontal) {
                foreach ($line as &$item) {
                    $this->layout($item['element'], $element->cw, $reference, $item['size']);
                    $item['cross'] = $item['element']->ch;
                }
                unset($item);
            }
            $outerCross = max(array_map(fn($i) => $i['cross'] + $i['element']->frame(!$horizontal) + $i['element']->margins(!$horizontal), $line));
            $lineCross = !$horizontal ? $element->cw : (count($lines) === 1 ? ($reference ?? $this->clamp($element, $outerCross, $heightReference, false)) : $outerCross);
            $remaining = $mainLength - $totalGap - array_sum(array_map(fn($i) => $i['size'] + $i['outer'], $line));
            $spaces = array_fill(0, count($line), 0);
            if ($remaining > 0) {
                $kind = $element->style['justify-content'];
                if ($kind === 'end') {
                    $spaces[0] = $remaining;
                } elseif ($kind === 'center') {
                    $spaces[0] = intdiv($remaining, 2);
                } elseif (in_array($kind, ['space-between', 'space-around', 'space-evenly'], true)) {
                    $weights = [];
                    for ($i = 0; $i <= count($line); $i++) {
                        $weights[] = $kind === 'space-evenly' ? 1 : (($i === 0 || $i === count($line)) ? ($kind === 'space-between' ? 0 : 1) : ($kind === 'space-between' ? 1 : 2));
                    }
                    $spaces = array_slice($this->distribute($remaining, $weights), 0, count($line));
                }
            }
            $cursor = 0;
            foreach ($line as $i => $item) {
                $child = $item['element'];
                $cross = $item['cross'];
                if ($horizontal) {
                    if ($item['align'] === 'stretch' && $child->style['height'] === 'auto') {
                        $cross = $this->clamp($child, max(0, $lineCross - $child->frame(false) - $child->margins(false)), $reference, false);
                        $this->layout($child, $element->cw, $reference, $item['size'], $cross);
                    } else {
                        $this->layout($child, $element->cw, $reference, $item['size']);
                    }
                } else {
                    $this->layout($child, $element->cw, $reference, $cross, $item['size']);
                }
                $room = $lineCross - $cross - $child->frame(!$horizontal) - $child->margins(!$horizontal);
                $offset = $room > 0 ? ($item['align'] === 'end' ? $room : ($item['align'] === 'center' ? intdiv($room, 2) : 0)) : 0;
                $cursor += $spaces[$i];
                $size = $item['size'] + $item['outer'];
                $main = ($reverse ? $mainLength - $cursor - $size : $cursor) + $child->margin[$horizontal ? 3 : 0];
                $crossPosition = $crossStart + $offset + $child->margin[$horizontal ? 0 : 3];
                $this->positionChild($element, $child, $horizontal ? $main : $crossPosition, $horizontal ? $crossPosition : $main);
                $cursor += $size + $gap;
            }
            $crossStart += $lineCross + $lineGap;
        }
        return $horizontal ? ($lines === [] ? 0 : $crossStart - $lineGap) : $mainLength;
    }

    private function gridLayout(Element $element, ?int $reference): int
    {
        $grid = $this->placement($element);
        $columnGap = (int)$element->style['column-gap'];
        $rowGap = (int)$element->style['row-gap'];
        $columns = $this->trackSizes($grid, true, $element->cw, $columnGap, array_map(fn($i) => $this->contribution($i['element']), $grid['items']));
        foreach ($grid['items'] as &$item) {
            $child = $item['element'];
            $start = $item['column'] - 1;
            $item['aw'] = array_sum(array_slice($columns, $start, $item['cs'])) + $columnGap * ($item['cs'] - 1);
            $item['ax'] = array_sum(array_slice($columns, 0, $start)) + $columnGap * $start;
            $item['gw'] = $this->clamp($child, $this->resolve($child, 'width', $item['aw'], true) ?? max(0, $item['aw'] - $child->frame(true) - $child->margins(true)), $item['aw'], true);
            $this->layout($child, $item['aw'], null, $item['gw']);
            $item['rowContribution'] = $child->height() + $child->margins(false);
        }
        unset($item);
        $rows = $this->trackSizes($grid, false, $reference, $rowGap, array_column($grid['items'], 'rowContribution'));
        foreach ($grid['items'] as $item) {
            $child = $item['element'];
            $start = $item['row'] - 1;
            $areaHeight = array_sum(array_slice($rows, $start, $item['rs'])) + $rowGap * ($item['rs'] - 1);
            $areaY = array_sum(array_slice($rows, 0, $start)) + $rowGap * $start;
            $alignment = $this->align($element, $child);
            $height = $alignment === 'stretch' && $child->style['height'] === 'auto' ? $this->clamp($child, max(0, $areaHeight - $child->frame(false) - $child->margins(false)), $areaHeight, false) : null;
            $this->layout($child, $item['aw'], $areaHeight, $item['gw'], $height);
            $room = $areaHeight - $child->height() - $child->margins(false);
            $offset = $room > 0 ? ($alignment === 'end' ? $room : ($alignment === 'center' ? intdiv($room, 2) : 0)) : 0;
            $this->positionChild($element, $child, $item['ax'] + $child->margin[3], $areaY + $offset + $child->margin[0]);
        }
        return $rows === [] ? 0 : array_sum($rows) + $rowGap * (count($rows) - 1);
    }

    private function relayout(): void
    {
        foreach ($this->elements as $element) {
            $element->style = self::defaults();
            $priorities = [];
            foreach ($this->rules as [$selectors, $declarations]) {
                $specificity = -1;
                foreach ($selectors as $selector) {
                    if ($selector[0] === '#') {
                        $match = substr($selector, 1) === $element->id ? 2 : -1;
                    } elseif ($selector[0] === '.') {
                        $match = in_array(substr($selector, 1), $element->classes, true) ? 1 : -1;
                    } else {
                        $match = $selector === $element->type ? 0 : -1;
                    }
                    $specificity = max($specificity, $match);
                }
                if ($specificity < 0) {
                    continue;
                }
                foreach ($declarations as [$property, $value]) {
                    if (!isset($priorities[$property]) || $specificity >= $priorities[$property]) {
                        $element->style[$property] = $value;
                        $priorities[$property] = $specificity;
                    }
                }
            }
            $element->style = array_replace($element->style, $element->overrides);
            $element->margin = $element->padding = $element->border = [];
            foreach (self::SIDES as $side) {
                $element->margin[] = (int)$element->style["margin-$side"];
                $element->padding[] = (int)$element->style["padding-$side"];
                $element->border[] = (int)$element->style["border-$side"];
            }
            $element->displayed = $element->style['display'] !== 'none' && ($element->parent === null || $element->parent->displayed);
            $element->maximum = $element->contribution = null;
            $element->lines = [];
            $element->containing = null;
        }
        $root = $this->elements[0];
        if ($root->displayed && $root->style['position'] !== 'absolute') {
            $this->layout($root, $this->width, $this->height);
            $root->rx = $root->margin[3];
            $root->ry = $root->margin[0];
        }
        foreach ($this->elements as $element) {
            if (!$element->displayed || $element->style['position'] !== 'absolute') {
                continue;
            }
            $ancestor = $element->parent;
            while ($ancestor !== null && $ancestor->style['position'] === 'static') {
                $ancestor = $ancestor->parent;
            }
            $element->containing = $ancestor;
            $cbw = $ancestor === null ? $this->width : $ancestor->cw + $ancestor->padding[1] + $ancestor->padding[3];
            $cbh = $ancestor === null ? $this->height : $ancestor->ch + $ancestor->padding[0] + $ancestor->padding[2];
            $offsets = array_map(fn($p) => $element->style[$p] === 'auto' ? null : (int)$element->style[$p], ['left', 'right', 'top', 'bottom']);
            [$left, $right, $top, $bottom] = $offsets;
            $width = $this->resolve($element, 'width', $cbw, true);
            if ($width === null) {
                $room = max(0, $cbw - ($left ?? 0) - ($right ?? 0) - $element->margins(true) - $element->frame(true));
                $width = $left !== null && $right !== null ? $room : min($this->maxContent($element), $room);
            }
            $fw = $this->clamp($element, $width, $cbw, true);
            $fh = $element->style['height'] === 'auto' && $top !== null && $bottom !== null ? $this->clamp($element, max(0, $cbh - $top - $bottom - $element->margins(false) - $element->frame(false)), $cbh, false) : null;
            $this->layout($element, $cbw, $cbh, $fw, $fh);
            $element->rx = $left !== null ? $left + $element->margin[3] : ($right !== null ? $cbw - $right - $element->margin[1] - $element->width() : $element->margin[3]);
            $element->ry = $top !== null ? $top + $element->margin[0] : ($bottom !== null ? $cbh - $bottom - $element->margin[2] - $element->height() : $element->margin[0]);
        }
        foreach ($this->elements as $element) {
            if (!$element->displayed) {
                continue;
            }
            $reference = $element->style['position'] === 'absolute' ? $element->containing : $element->parent;
            $x = $reference?->x ?? 0;
            $y = $reference?->y ?? 0;
            if ($element->style['position'] === 'absolute' && $reference !== null) {
                $x += $reference->border[3];
                $y += $reference->border[0];
            }
            $element->x = $x + $element->rx;
            $element->y = $y + $element->ry;
            if ($element->style['position'] === 'relative') {
                [$left, $right, $top, $bottom] = array_map(fn($p) => $element->style[$p] === 'auto' ? null : (int)$element->style[$p], ['left', 'right', 'top', 'bottom']);
                $element->x += $left ?? ($right === null ? 0 : -$right);
                $element->y += $top ?? ($bottom === null ? 0 : -$bottom);
            }
        }
    }

    private function boxes(Element $element): array
    {
        [$x, $y, $w, $h] = [$element->x, $element->y, $element->width(), $element->height()];
        [$m, $b, $p] = [$element->margin, $element->border, $element->padding];
        return [
            [$x - $m[3], $y - $m[0], $w + $m[1] + $m[3], $h + $m[0] + $m[2]],
            [$x, $y, $w, $h],
            [$x + $b[3], $y + $b[0], $w - $b[1] - $b[3], $h - $b[0] - $b[2]],
            [$x + $b[3] + $p[3], $y + $b[0] + $p[0], $element->cw, $element->ch]
        ];
    }

    private function snapshot(): array
    {
        return array_map(fn($e) => $e->displayed ? [$e->x, $e->y, $e->width(), $e->height()] : null, $this->elements);
    }

    private function changes(array $before): string
    {
        $after = $this->snapshot();
        $changed = [];
        foreach ($this->elements as $i => $element) {
            if ($before[$i] !== $after[$i]) {
                $changed[] = $element->id;
            }
        }
        return $changed === [] ? 'no change' : implode(' ', $changed);
    }

    private function render(): void
    {
        $screen = array_fill(0, $this->height, str_repeat('.', $this->width));
        foreach ($this->elements as $element) {
            if (!$element->displayed) {
                continue;
            }
            [$x, $y, $w, $h] = $this->boxes($element)[1];
            for ($row = max($y, 0); $row < min($y + $h, $this->height); $row++) {
                for ($column = max($x, 0); $column < min($x + $w, $this->width); $column++) {
                    $horizontal = ($element->border[0] === 1 && $row === $y) || ($element->border[2] === 1 && $row === $y + $h - 1);
                    $vertical = ($element->border[3] === 1 && $column === $x) || ($element->border[1] === 1 && $column === $x + $w - 1);
                    $screen[$row][$column] = $horizontal && $vertical ? '+' : ($horizontal ? '-' : ($vertical ? '|' : ' '));
                }
            }
            if ($element->text !== null) {
                [$cx, $cy] = $this->boxes($element)[3];
                foreach ($element->lines as $i => $line) {
                    $row = $cy + $i;
                    if ($row < 0 || $row >= $this->height) {
                        continue;
                    }
                    for ($j = 0; $j < strlen($line); $j++) {
                        if ($cx + $j >= 0 && $cx + $j < $this->width) {
                            $screen[$row][$cx + $j] = $line[$j];
                        }
                    }
                }
            }
        }
        $edge = str_repeat('#', $this->width + 2);
        echo "render {$this->width}x{$this->height}\n$edge\n";
        foreach ($screen as $row) {
            echo '#', $row, "#\n";
        }
        echo $edge, "\n";
    }

    public function execute(string $line): void
    {
        $args = explode(' ', $line);
        $command = array_shift($args);
        switch ($command) {
            case 'LAYOUT':
                echo "layout {$this->width}x{$this->height}\n";
                foreach ($this->elements as $e) {
                    echo str_repeat('  ', $e->depth), $e->id, $e->displayed ? " {$e->x} {$e->y} " . $e->width() . ' ' . $e->height() : ' none', "\n";
                }
                break;
            case 'BOX':
                $element = $this->ids[$args[0]] ?? null;
                if ($element === null) {
                    echo "error: unknown element {$args[0]}\n";
                } elseif (!$element->displayed) {
                    echo "box {$element->id}: none\n";
                } else {
                    echo "box {$element->id}\n";
                    $boxes = $this->boxes($element);
                    foreach (['margin', 'border', 'padding', 'content'] as $i => $name) {
                        echo $name, ' ', implode(' ', $boxes[$i]), "\n";
                    }
                }
                break;
            case 'RENDER':
                $this->render();
                break;
            case 'HIT':
                [$x, $y] = array_map('intval', $args);
                if ($x >= $this->width || $y >= $this->height) {
                    echo "error: point $x $y outside viewport\n";
                } else {
                    $found = null;
                    foreach ($this->elements as $e) {
                        if ($e->displayed && $e->x <= $x && $x < $e->x + $e->width() && $e->y <= $y && $y < $e->y + $e->height()) {
                            $found = $e;
                        }
                    }
                    $path = [];
                    while ($found !== null) {
                        array_unshift($path, $found->id);
                        $found = $found->parent;
                    }
                    echo "hit $x $y: ", $path === [] ? 'none' : implode(' > ', $path), "\n";
                }
                break;
            case 'SET':
                [$id, $property] = array_slice($args, 0, 2);
                $value = implode(' ', array_slice($args, 2));
                if (!isset($this->ids[$id])) {
                    echo "error: unknown element $id\n";
                } elseif (!self::known($property)) {
                    echo "error: unknown property $property\n";
                } elseif (($declarations = self::declaration($property, $value)) === null) {
                    echo "error: invalid value for $property: $value\n";
                } else {
                    $before = $this->snapshot();
                    foreach ($declarations as [$p, $v]) {
                        $this->ids[$id]->overrides[$p] = $v;
                    }
                    $this->relayout();
                    echo "set $id $property $value: ", $this->changes($before), "\n";
                }
                break;
            case 'VIEWPORT':
                [$width, $height] = array_map('intval', $args);
                if ($width < 1 || $width > 80 || $height < 1 || $height > 40) {
                    echo "error: invalid viewport $width $height\n";
                } else {
                    $before = $this->snapshot();
                    $this->width = $width;
                    $this->height = $height;
                    $this->relayout();
                    echo "viewport $width $height: ", $this->changes($before), "\n";
                }
                break;
            case 'OVERFLOW':
                $overflow = [];
                foreach ($this->elements as $e) {
                    if (!$e->displayed) {
                        continue;
                    }
                    if ($e->text !== null) {
                        $over = max(array_map('strlen', $e->lines)) > $e->cw || count($e->lines) > $e->ch;
                    } else {
                        [$cx, $cy, $cw, $ch] = $this->boxes($e)[3];
                        $over = false;
                        foreach ($this->children($e) as $child) {
                            [$x, $y, $w, $h] = $this->boxes($child)[0];
                            if ($x < $cx || $y < $cy || $x + $w > $cx + $cw || $y + $h > $cy + $ch) {
                                $over = true;
                            }
                        }
                    }
                    if ($over) {
                        $overflow[] = $e->id;
                    }
                }
                echo 'overflow: ', $overflow === [] ? 'none' : implode(' ', $overflow), "\n";
                break;
            default:
                echo "error: unknown command $command\n";
        }
    }
}

$input = array_map(fn($line) => rtrim($line, "\r\n"), file('php://stdin'));
[$width, $height] = array_map('intval', explode(' ', $input[0]));
$i = 1;
$rules = [];
while ($input[$i] !== '---') {
    [$selectors, $body] = explode(' { ', $input[$i++], 2);
    $declarations = [];
    foreach (explode('; ', substr($body, 0, -2)) as $text) {
        [$property, $value] = explode(': ', $text, 2);
        $declarations = array_merge($declarations, BoxLayout::declaration($property, $value) ?? []);
    }
    $rules[] = [explode(', ', $selectors), $declarations];
}
$i++;
$elements = $stack = [];
while ($input[$i] !== '===') {
    $line = $input[$i++];
    $depth = intdiv(strspn($line, ' '), 2);
    $parts = explode(' ', ltrim($line, ' '), 2);
    [$type, $rest] = explode('#', $parts[0], 2);
    $classes = explode('.', $rest);
    $id = array_shift($classes);
    $parent = $depth === 0 ? null : $stack[$depth - 1];
    $text = isset($parts[1]) ? substr($parts[1], 1, -1) : null;
    $element = new Element($type, $id, $classes, $text, $parent, $depth, count($elements));
    if ($parent !== null) {
        $parent->children[] = $element;
    }
    $elements[] = $element;
    $stack[$depth] = $element;
}
$i++;
$layout = new BoxLayout($width, $height, $rules, $elements);
while ($input[$i] !== 'END') {
    $layout->execute($input[$i++]);
}
