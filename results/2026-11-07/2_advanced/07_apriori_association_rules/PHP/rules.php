<?php
class Fraction {
    public int $numerator, $denominator;
    public function __construct(int $numerator, int $denominator = 1) {
        if ($denominator < 0) { $numerator = -$numerator; $denominator = -$denominator; }
        $a = abs($numerator); $b = $denominator; while ($b !== 0) { [$a,$b] = [$b,$a % $b]; }
        $this->numerator = intdiv($numerator,$a); $this->denominator = intdiv($denominator,$a);
    }
    public static function parse(string $text): self { $parts = explode('/',$text); return new self((int)$parts[0],(int)$parts[1]); }
    public function compare(self $other): int { return ($this->numerator * $other->denominator) <=> ($other->numerator * $this->denominator); }
    public function subtract(self $other): self { return new self($this->numerator * $other->denominator - $other->numerator * $this->denominator,$this->denominator * $other->denominator); }
    public function times(int $numerator, int $denominator = 1): self { return new self($this->numerator * $numerator,$this->denominator * $denominator); }
}
class Rule {
    public Fraction $support, $confidence, $lift, $leverage, $improvement;
    public ?Fraction $conviction;
    public int $rank = 0;
    public function __construct(public array $itemset, public array $antecedent, public array $consequent, public int $count, int $total, int $first, int $second) {
        $this->support = new Fraction($count,$total); $this->confidence = new Fraction($count,$first); $this->lift = new Fraction($total * $count,$first * $second);
        $this->leverage = new Fraction($total * $count - $first * $second,$total * $total); $this->conviction = $first === $count ? null : new Fraction(($total - $second) * $first,$total * ($first - $count)); $this->improvement = new Fraction(0);
    }
}
function meets_thresholds(Fraction $confidence, Fraction $lift, array $params): bool { return $confidence->compare($params['min_confidence']) >= 0 && $lift->compare($params['min_lift']) >= 0; }
function compare_rules(Rule $a, Rule $b): int { return $b->confidence->compare($a->confidence) ?: $b->lift->compare($a->lift) ?: ($b->count <=> $a->count) ?: compare_sets($a->antecedent,$b->antecedent) ?: compare_sets($a->consequent,$b->consequent); }
