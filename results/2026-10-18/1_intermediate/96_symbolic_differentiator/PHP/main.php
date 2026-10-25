<?php
final readonly class Rational {
    public int $p;
    public int $q;
    public function __construct(int $p, int $q = 1) {
        if ($q === 0) throw new RuntimeException('division by zero');
        if ($q<0) {
            $p = -$p;
            $q = -$q;
        }
        $a = abs($p);
        $b = $q;
        while ($b) {
            [$a, $b] = [$b, $a%$b];
        }
        $this->p = intdiv($p, $a);
        $this->q = intdiv($q, $a);
    }
    public function plus(self $b): self {
        return new self($this->p*$b->q+$b->p*$this->q, $this->q*$b->q);
    }
    public function times(self $b): self {
        return new self($this->p*$b->p, $this->q*$b->q);
    }
    public function negative(): self {
        return new self(-$this->p, $this->q);
    }
}
final readonly class Expr {
    public function __construct(public int $kind, public Rational $q, public string $name, public array $args) {
    }
}
function num(int|Rational $p, int $q = 1): Expr {
    return new Expr(5, $p instanceof Rational?$p:new Rational($p, $q), '', []);
}
function node(int $k, array $a = [], string $s = ''): Expr {
    return new Expr($k, new Rational(0), $s, $a);
}
const FUNCTIONS = ['sin', 'cos', 'tan', 'exp', 'ln', 'sqrt'];
$zero = num(0);
$one = num(1);
$minus = num(-1);
$half = num(1, 2);
function compare(Expr $a, Expr $b): int {
    if ($a->kind !== $b->kind) return $a->kind <=> $b->kind;
    if ($a->kind === 5) return ($a->q->p*$b->q->q) <=> ($b->q->p*$a->q->q);
    if ($a->name !== $b->name) return strcmp($a->name, $b->name);
    for ($i = 0; $i<min(count($a->args), count($b->args)); $i++) {
        $c = compare($a->args[$i], $b->args[$i]);
        if ($c) return $c;
    }
    return count($a->args) <=> count($b->args);
}
function integerForm(Expr $f): bool {
    return $f->kind === 5 && $f->q->q === 1;
}
function negativePower(Expr $f): bool {
    return $f->kind === 3 && $f->args[1]->kind === 5 && $f->args[1]->q->p<0;
}
function baseOf(Expr $f): Expr {
    return $f->kind === 3?$f->args[0]:$f;
}
function exponentOf(Expr $f): Expr {
    global $one;
    return $f->kind === 3?$f->args[1]:$one;
}
function coefficient(Expr $f): array {
    if ($f->kind === 5) return [$f->q, []];
    if ($f->kind === 2) return $f->args[0]->kind === 5?[$f->args[0]->q, array_slice($f->args, 1)]:[new Rational(1), $f->args];
    return [new Rational(1), [$f]];
}
function product(Rational $c, array $a): Expr {
    if (!$a) return num($c);
    if ($c->p !== $c->q) array_unshift($a, num($c));
    return count($a) === 1?$a[0]:node(2, $a);
}
function exponentCompare(Expr $a, Expr $b): int {
    if ($a->kind === 5 && $b->kind !== 5) return -1;
    if ($a->kind !== 5 && $b->kind === 5) return 1;
    return compare($a, $b);
}
function termCompare(Expr $a, Expr $b): int {
    global $zero;
    $x = coefficient($a)[1];
    $y = coefficient($b)[1];
    $bases = [];
    foreach ([...$x, ...$y] as $f) {
        $b = baseOf($f);
        if (!in_array($b, $bases))$bases[] = $b;
    }
    usort($bases, 'compare');
    foreach ($bases as $b) {
        $u = $v = $zero;
        foreach ($x as $t) if (baseOf($t) == $b)$u = exponentOf($t);
        foreach ($y as $t) if (baseOf($t) == $b)$v = exponentOf($t);
        $c = exponentCompare($v, $u);
        if ($c) return $c;
    }
    return 0;
}
function add(Expr ...$operands): Expr {
    global $zero;
    $terms = [];
    foreach ($operands as $f) {
        if ($f->kind === 1) array_push($terms, ...$f->args);
        elseif($f->kind === 2 && count($f->args) === 2 && $f->args[0]->kind === 5 && $f->args[1]->kind === 1) foreach ($f->args[1]->args as $t)$terms[] = multiply($f->args[0], $t);
        else $terms[] = $f;
    }
    $keys = [];
    $values = [];
    foreach ($terms as $f) {
        [$c, $m] = coefficient($f);
        $i = array_search($m, $keys);
        if ($i === false) {
            $keys[] = $m;
            $values[] = $c;
        } else $values[$i] = $values[$i]->plus($c);
    }
    $built = [];
    foreach ($keys as $i => $m) if ($values[$i]->p)$built[] = product($values[$i], $m);
    usort($built, 'termCompare');
    return !$built?$zero:(count($built) === 1?$built[0]:node(1, $built));
}
function multiply(Expr ...$operands): Expr {
    global $zero;
    $c = new Rational(1);
    $bases = [];
    $groups = [];
    $factors = [];
    foreach ($operands as $f) array_push($factors, ...($f->kind === 2?$f->args:[$f]));
    foreach ($factors as $f) {
        if ($f->kind === 5)$c = $c->times($f->q);
        else {
            $b = baseOf($f);
            $i = array_search($b, $bases);
            if ($i === false) {
                $bases[] = $b;
                $groups[] = [$f];
            } else $groups[$i][] = $f;
        }
    }
    if (!$c->p) return $zero;
    $r = [];
    foreach ($groups as $i => $g)$r[] = count($g) === 1?$g[0]:power($bases[$i], add(...array_map('exponentOf', $g)));
    $regroup = false;
    $seen = [];
    foreach ($r as $f) {
        $b = baseOf($f);
        if (in_array($f->kind, [2, 5]) || in_array($b, $seen))$regroup = true;
        $seen[] = $b;
    }
    if ($regroup) return multiply(num($c), ...$r);
    usort($r, fn($a, $b) => compare(baseOf($a), baseOf($b)));
    return product($c, $r);
}
function integerRoot(int $v, int $d): ?int {
    if ($v === 1) return 1;
    if ($d>20) return null;
    $r = (int) round($v**(1/$d));
    for ($s = max(0, $r-1); $s <= $r+1; $s++) {
        $a = 1;
        for ($i = 0; $i<$d && $a <= $v; $i++)$a *= $s;
        if ($a === $v) return $s;
    }
    return null;
}
function rationalPower(Rational $b, int $n): Expr {
    if ($n<0) {
        $b = new Rational($b->q, $b->p);
        $n = -$n;
    }
    $r = new Rational(1);
    while ($n) {
        if ($n%2)$r = $r->times($b);
        $n = intdiv($n, 2);
        if ($n)$b = $b->times($b);
    }
    return num($r);
}
function power(Expr $b, Expr $x): Expr {
    global $zero, $one;
    if ($x == $zero) return $one;
    if ($x == $one) return $b;
    if ($b->kind === 5) {
        if ($b == $one) return $one;
        if ($x->kind !== 5) return node(3, [$b, $x]);
        if (!$b->q->p) {
            if ($x->q->p>0) return $zero;
            throw new RuntimeException('division by zero');
        }
        if (integerForm($x)) return rationalPower($b->q, $x->q->p);
        if ($b->q->p>0) {
            $s = integerRoot($b->q->p, $x->q->q);
            $t = integerRoot($b->q->q, $x->q->q);
            if ($s !== null && $t !== null) return rationalPower(new Rational($s, $t), $x->q->p);
        }
    }
    elseif(integerForm($x)) {
        if ($b->kind === 3) return power($b->args[0], multiply($b->args[1], $x));
        if ($b->kind === 2) return multiply(...array_map(fn($f) => power($f, $x), $b->args));
    }
    return node(3, [$b, $x]);
}
function applyFunction(string $s, Expr $a): Expr {
    global $zero, $one, $minus, $half;
    if ($s === 'sqrt') return power($a, $half);
    if ($a == $zero && in_array($s, ['sin', 'tan'])) return $zero;
    if ($a == $zero && in_array($s, ['cos', 'exp'])) return $one;
    if ($a == $one && $s === 'ln') return $zero;
    if (in_array($s, ['sin', 'cos', 'tan']) && coefficient($a)[0]->p<0) {
        $r = applyFunction($s, multiply($minus, $a));
        return $s === 'cos'?$r:multiply($minus, $r);
    }
    if ($a->kind === 4 && (($s === 'exp' && $a->name === 'ln') || ($s === 'ln' && $a->name === 'exp'))) return $a->args[0];
    return node(4, [$a], $s);
}
function variables(Expr $f): array {
    $r = $f->kind === 0?[$f->name]:[];
    foreach ($f->args as $a) array_push($r, ...variables($a));
    $r = array_values(array_unique($r));
    sort($r, SORT_STRING);
    return $r;
}
function derivative(Expr $f, string $v): Expr {
    global $zero, $one, $minus;
    if ($f->kind === 5) return $zero;
    if ($f->kind === 0) return $f->name === $v?$one:$zero;
    if ($f->kind === 1) return add(...array_map(fn($t) => derivative($t, $v), $f->args));
    if ($f->kind === 2) {
        $r = [];
        foreach ($f->args as $i => $t) {
            $a = $f->args;
            $a[$i] = derivative($t, $v);
            $r[] = multiply(...$a);
        }
        return add(...$r);
    }
    if ($f->kind === 3) {
        [$b, $x] = $f->args;
        if (!in_array($v, variables($x))) return multiply($x, power($b, add($x, $minus)), derivative($b, $v));
        if (!in_array($v, variables($b))) return multiply($f, applyFunction('ln', $b), derivative($x, $v));
        return multiply($f, add(multiply(derivative($x, $v), applyFunction('ln', $b)), multiply($x, derivative($b, $v), power($b, $minus))));
    }
    $a = $f->args[0];
    $h = match($f->name) {
        'sin' => applyFunction('cos', $a), 'cos' => multiply($minus, applyFunction('sin', $a)), 'tan' => power(applyFunction('cos', $a), num(-2)), 'exp' => $f, default => power($a, $minus)
    };
    return multiply($h, derivative($a, $v));
}
function rebuild(Expr $f, array $a): Expr {
    return match($f->kind) {
        1 => add(...$a), 2 => multiply(...$a), 3 => power(...$a), default => applyFunction($f->name, $a[0])
    };
}
function substitute(Expr $f, array $m): Expr {
    if ($f->kind === 0) return $m[$f->name] ?? $f;
    if ($f->kind === 5) return $f;
    return rebuild($f, array_map(fn($t) => substitute($t, $m), $f->args));
}
function terms(Expr $f): array {
    return $f->kind === 1?$f->args:[$f];
}
function distribute(Expr $a, Expr $b): Expr {
    $r = [];
    foreach (terms($a) as $x) foreach (terms($b) as $y)$r[] = multiply($x, $y);
    return add(...$r);
}
function expandForm(Expr $f): Expr {
    if (in_array($f->kind, [0, 5])) return $f;
    $a = array_map('expandForm', $f->args);
    if ($f->kind === 2) {
        $r = $a[0];
        foreach (array_slice($a, 1) as $t)$r = distribute($r, $t);
        return $r;
    }
    if ($f->kind === 3 && $a[0]->kind === 1 && integerForm($a[1]) && $a[1]->q->p>0) {
        $r = $a[0];
        for ($i = 1; $i<$a[1]->q->p; $i++)$r = distribute($r, $a[0]);
        return $r;
    }
    return rebuild($f, $a);
}
function numeric(Expr $f): float {
    global $half;
    if ($f->kind === 5) return $f->q->p/$f->q->q;
    if ($f->kind === 1 || $f->kind === 2) {
        $r = $f->kind === 1?0.0:1.0;
        foreach ($f->args as $a) {
            $v = numeric($a);
            $r = $f->kind === 1?$r+$v:$r*$v;
        }
        return $r;
    }
    if ($f->kind === 3) {
        $u = numeric($f->args[0]);
        $z = numeric($f->args[1]);
        $integral = $f->args[1]->kind === 5?integerForm($f->args[1]):$z === floor($z);
        if ($u<0 && !$integral) throw new RuntimeException('domain error');
        return $f->args[1] == $half?sqrt($u):$u**$z;
    }
    $a = numeric($f->args[0]);
    if ($f->name === 'ln' && $a <= 0) throw new RuntimeException('domain error');
    return match($f->name) {
        'ln' => log($a), 'sin' => sin($a), 'cos' => cos($a), 'tan' => tan($a), default => exp($a)
    };
}
function atomic(Expr $f): bool {
    global $half;
    return in_array($f->kind, [0, 4]) || (integerForm($f) && $f->q->p >= 0) || ($f->kind === 3 && $f->args[1] == $half);
}
function atom(Expr $f): string {
    return atomic($f)?show($f):'('.show($f).')';
}
function showPower(Expr $b, Expr $x): string {
    global $half;
    return $x == $half?'sqrt('.show($b).')':atom($b).'^'.atom($x);
}
function factor(Expr $f): string {
    return $f->kind === 1?'('.show($f).')':($f->kind === 3?showPower(...$f->args):show($f));
}
function quotient(Rational $c, array $a): string {
    $p = abs($c->p);
    $top = $p === 1?[]:[(string)$p];
    $bottom = $c->q === 1?[]:[(string)$c->q];
    foreach ($a as $f) if (negativePower($f)) {
        $r = num($f->args[1]->q->negative());
        $bottom[] = $r->q->p === $r->q->q?factor($f->args[0]):showPower($f->args[0], $r);
    } else $top[] = factor($f);
    $s = $top?implode('*', $top):'1';
    if (count($bottom) === 1)$s. = '/'.$bottom[0];
    elseif($bottom)$s. = '/('.implode('*', $bottom).')';
    return ($c->p<0?'-':'').$s;
}
function show(Expr $f): string {
    if ($f->kind === 5) return $f->q->p.($f->q->q === 1?'':'/'.$f->q->q);
    if ($f->kind === 0) return $f->name;
    if ($f->kind === 4) return $f->name.'('.show($f->args[0]).')';
    if ($f->kind === 3) return negativePower($f)?quotient(new Rational(1), [$f]):showPower(...$f->args);
    if ($f->kind === 2) return quotient(...coefficient($f));
    $s = show($f->args[0]);
    foreach (array_slice($f->args, 1) as $a) {
        $t = show($a);
        $s. = $t[0] === '-'?' - '.substr($t, 1):' + '.$t;
    }
    return $s;
}
final readonly class Syntax {
    public function __construct(public string $op, public ?Expr $value, public array $args = []) {
    }
}
final class Parser {
    private array $tokens = [];
    private int $position = 0;
    public function __construct(string $text, private array $names) {
        preg_match_all('~[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|.~', $text, $m);
        foreach ($m[0] as $t) {
            if ($t[0] === ' ') continue;
            if (!preg_match('~\A[a-zA-Z0-9+*/^()-]+\z~', $t)) throw new RuntimeException("invalid character '$t'");
            $this->tokens[] = $t;
        }
    }
    private function peek(): string {
        return $this->tokens[$this->position] ?? '';
    }
    private function unexpected(): never {
        $t = $this->peek();
        throw new RuntimeException($t === ''?'unexpected end of expression':"unexpected '$t'");
    }
    private function accept(string $s): bool {
        if ($this->peek() !== $s) return false;
        $this->position++;
        return true;
    }
    private function expect(string $s): void {
        if (!$this->accept($s))$this->unexpected();
    }
    private function atomTree(): Syntax {
        $t = $this->peek();
        if ($t === '')$this->unexpected();
        if ($this->accept('(')) {
            $a = $this->expression();
            $this->expect(')');
            return $a;
        }
        if (!ctype_alnum($t[0]))$this->unexpected();
        $this->position++;
        if (ctype_digit($t[0])) return new Syntax('', num((int)$t));
        if (ctype_upper($t[0])) {
            if (!isset($this->names[$t])) throw new RuntimeException("undefined name '$t'");
            return new Syntax('', $this->names[$t]);
        }
        if (!in_array($t, FUNCTIONS)) return new Syntax('', node(0, [], $t));
        $this->expect('(');
        $a = $this->expression();
        $this->expect(')');
        return new Syntax($t, null, [$a]);
    }
    private function unary(): Syntax {
        if ($this->accept('-')) return new Syntax('neg', null, [$this->unary()]);
        $a = $this->atomTree();
        return $this->accept('^')?new Syntax('^', null, [$a, $this->unary()]):$a;
    }
    private function term(): Syntax {
        $a = $this->unary();
        while (in_array($this->peek(), ['*', '/'])) {
            $op = $this->tokens[$this->position++];
            $a = new Syntax($op, null, [$a, $this->unary()]);
        }
        return $a;
    }
    private function expression(): Syntax {
        $a = $this->term();
        while (in_array($this->peek(), ['+', '-'])) {
            $op = $this->tokens[$this->position++];
            $a = new Syntax($op, null, [$a, $this->term()]);
        }
        return $a;
    }
    private function evaluate(Syntax $t): Expr {
        global $minus;
        if ($t->value !== null) return $t->value;
        $a = array_map(fn($s) => $this->evaluate($s), $t->args);
        return match($t->op) {
            '+' => add(...$a), '-' => add($a[0], multiply($minus, $a[1])), '*' => multiply(...$a), '/' => multiply($a[0], power($a[1], $minus)), '^' => power(...$a), 'neg' => multiply($minus, $a[0]), default => applyFunction($t->op, $a[0])
        };
    }
    public function parse(): Expr {
        $t = $this->expression();
        if ($this->position<count($this->tokens))$this->unexpected();
        return $this->evaluate($t);
    }
}
function variableName(string $s): bool {
    return (bool) preg_match('~\A[a-z][a-z0-9]*\z~', $s) && !in_array($s, FUNCTIONS);
}
function rationalLiteral(string $s): bool {
    return (bool) preg_match('~\A-?[0-9]+(?:/[0-9]+)?\z~', $s);
}
function literal(string $s): Expr {
    if (!rationalLiteral($s)) throw new RuntimeException("invalid number '$s'");
    $a = explode('/', $s);
    return num((int)$a[0], isset($a[1])?(int)$a[1]:1);
}
const SIGNATURES = ['SIMPLIFY' => 'e', 'EXPAND' => 'e', 'DIFF' => 'ev', 'DIFFN' => 'evn', 'GRAD' => 'e', 'HESSIAN' => 'e', 'IMPLICIT' => 'evv', 'SUBST' => 'eve', 'EVAL' => 'ea', 'TANGENT' => 'evc', 'LIMIT' => 'evc', 'TAYLOR' => 'evcn'];
function command(string $line, array &$names): array {
    global $zero, $minus;
    $parts = explode(' ', $line, 2);
    $c = $parts[0];
    $arg = $parts[1] ?? '';
    if ($c === 'LET') {
        if (!str_contains($arg, '=')) throw new RuntimeException('wrong number of arguments');
        [$s, $text] = explode('=', $arg, 2);
        $s = trim($s, ' ');
        if (!preg_match('~\A[A-Z][A-Z0-9]*\z~', $s)) throw new RuntimeException("invalid name '$s'");
        $f = (new Parser(trim($text, ' '), $names))->parse();
        $names[$s] = $f;
        return ["$s = ".show($f)];
    }
    if (!isset(SIGNATURES[$c])) throw new RuntimeException("unknown command $c");
    $fields = isset($parts[1])?array_map(fn($s) => trim($s, ' '), explode(';', $arg)):[];
    $sig = SIGNATURES[$c];
    if ($c === 'EVAL'?!in_array(count($fields), [1, 2]):count($fields) !== strlen($sig)) throw new RuntimeException('wrong number of arguments');
    $a = [];
    foreach ($fields as $i => $s) {
        switch ($sig[$i]) {
            case 'e':$a[] = (new Parser($s, $names))->parse();
            break;
            case 'v':if (!variableName($s)) throw new RuntimeException("invalid variable '$s'");
            $a[] = $s;
            break;
            case 'n':if (!preg_match('~\A[1-8]\z~', $s)) throw new RuntimeException("invalid order '$s'");
            $a[] = (int)$s;
            break;
            case 'c':$a[] = literal($s);
            break;
            default:$a[] = $s;
        }
    }
    $f = $a[0];
    $v = $a[1] ?? '';
    $x = $a[2] ?? $zero;
    $out = [];
    if ($c === 'SIMPLIFY') return ['simplified: '.show($f)];
    if ($c === 'EXPAND') return ['expanded: '.show(expandForm($f))];
    if ($c === 'DIFF') return ["d/d$v = ".show(derivative($f, $v))];
    if ($c === 'DIFFN') {
        for ($k = 1; $k <= $x; $k++) {
            $f = derivative($f, $v);
            $out[] = "d^$k/d$v^$k = ".show($f);
        }
        return $out;
    }
    if ($c === 'GRAD' || $c === 'HESSIAN') {
        $vs = variables($f);
        if (!$vs) return ['no variables'];
        foreach ($vs as $i => $s) {
            $d = derivative($f, $s);
            if ($c === 'GRAD')$out[] = "d/d$s = ".show($d);
            else foreach (array_slice($vs, $i) as $t)$out[] = "d2/d{$s}d$t = ".show(derivative($d, $t));
        }
        return $out;
    }
    if ($c === 'IMPLICIT') {
        if ($v === $x) throw new RuntimeException('same variable');
        return ["d$x/d$v = ".show(multiply($minus, derivative($f, $v), power(derivative($f, $x), $minus)))];
    }
    if ($c === 'SUBST') return ['substituted: '.show(substitute($f, [$v => $x]))];
    if ($c === 'EVAL') {
        $values = [];
        foreach (array_filter(explode(' ', $v), fn($s) => $s !== '') as $word) {
            $pair = explode('=', $word, 2);
            $s = $pair[0];
            $text = $pair[1] ?? '';
            if (count($pair) !== 2 || !variableName($s) || !rationalLiteral($text)) throw new RuntimeException("invalid assignment '$word'");
            $q = literal($text);
            if (isset($values[$s])) throw new RuntimeException("duplicate variable $s");
            $values[$s] = $q;
        }
        foreach (variables($f) as $s) if (!isset($values[$s])) throw new RuntimeException("no value for $s");
        $r = substitute($f, $values);
        return [$r->kind === 5?'exact: '.show($r):'approx: '.number_format(numeric($r), 6, '.', '')];
    }
    $point = [$v => $x];
    if ($c === 'TANGENT') {
        $m = substitute(derivative($f, $v), $point);
        $y = substitute($f, $point);
        $z = node(0, [], $v);
        $t = 'tangent: y = '.show(add(multiply($m, $z), $y, multiply(num($x->q->negative()), $m)));
        if ($m == $zero) return [$t, "normal: $v = ".show($x)];
        $k = power($m, $minus);
        return [$t, 'normal: y = '.show(add(multiply($minus, $k, $z), $y, multiply($x, $k)))];
    }
    if ($c === 'LIMIT') {
        $top = [];
        $bottom = [];
        foreach ($f->kind === 2?$f->args:[$f] as $t) if (negativePower($t))$bottom[] = power($t->args[0], num($t->args[1]->q->negative()));
        else $top[] = $t;
        $g = multiply(...$top);
        $h = multiply(...$bottom);
        for ($i = 0; $i <= 5; $i++) {
            $u = substitute($g, $point);
            $b = substitute($h, $point);
            if ($b != $zero) return ['limit: '.show(multiply($u, power($b, $minus)))];
            if ($u != $zero) return ['limit: unbounded'];
            if ($i<5) {
                $g = derivative($g, $v);
                $h = derivative($h, $v);
            }
        }
        return ['limit: unknown'];
    }
    $n = $a[3];
    $ds = [$f];
    for ($i = 0; $i<$n; $i++)$ds[] = derivative($ds[count($ds)-1], $v);
    $ps = [];
    $fac = 1;
    for ($i = 0; $i <= $n; $i++) {
        if ($i)$fac *= $i;
        $co = multiply(substitute($ds[$i], $point), num(1, $fac));
        $ps[] = multiply($co, power(add(node(0, [], $v), num($x->q->negative())), num($i)));
    }
    return ['taylor: '.show(expandForm(add(...$ps)))];
}
$names = [];
$count = (int) trim(fgets(STDIN));
for ($i = 0; $i<$count; $i++) {
    try {
        foreach (command(rtrim(fgets(STDIN), "\r\n"), $names) as $line) echo $line, "\n";
    } catch (RuntimeException $e) {
        echo 'error: ', $e->getMessage(), "\n";
    }
}
