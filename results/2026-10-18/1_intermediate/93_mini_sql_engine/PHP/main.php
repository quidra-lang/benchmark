<?php
const RESERVED = 'SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT';
const AGGREGATES = ['COUNT', 'SUM', 'MIN', 'MAX', 'AVG'];
const COMPARISONS = ['=', '<>', '!=', '<', '<=', '>', '>='];
final class SqlError extends Exception {
}
function fail(string $s): never {
    throw new SqlError($s);
}
final class Expr {
    public ?string $table = null;
    public string $column = '', $text = '';
    public int $index = -1;
    public bool $distinct = false, $negated = false;
    public function __construct(public string $kind, public string $op = '', public array $args = [], public int|string|null $value = null) {
    }
}
function tokenize(string $text): array {
    $reserved = array_flip(explode(' ', RESERVED));
    $tokens = [];
    $i = 0;
    while ($i<strlen($text)) {
        $rest = substr($text, $i);
        if (preg_match('/^(?:[ \n]+|--[^\n]*)/', $rest, $m)) {
            $i += strlen($m[0]);
            continue;
        }
        if (preg_match("/^'([^']*)'/", $rest, $m)) {
            $kind = 'string';
            $value = $m[1];
        }
        elseif(preg_match('/^[0-9]+/', $rest, $m)) {
            $kind = 'integer';
            $value = (int)$m[0];
        }
        elseif(preg_match('/^[A-Za-z_][A-Za-z0-9_]*/', $rest, $m)) {
            $upper = strtoupper($m[0]);
            $kind = isset($reserved[$upper])?'keyword':'name';
            $value = $kind === 'keyword'?$upper:$m[0];
        }
        elseif(preg_match('/^(?:<>|!=|<=|>=|\|\||[(),.;*\/%+\-=<>])/', $rest, $m)) {
            $kind = 'symbol';
            $value = $m[0];
        }
        else fail("unexpected character '".$text[$i]."'");
        $tokens[] = ['kind' => $kind, 'value' => $value, 'text' => $m[0]];
        $i += strlen($m[0]);
    }
    return $tokens;
}
final class Parser {
    private int $position = 0;
    public function __construct(private array $tokens) {
    }
    private function peek(): array {
        return $this->tokens[$this->position];
    }
    private function take(): array {
        return $this->tokens[$this->position++];
    }
    private function at(string $word): bool {
        $t = $this->peek();
        return in_array($t['kind'], ['symbol', 'keyword'], true) && $t['value'] === $word;
    }
    private function accept(string $word): bool {
        if (!$this->at($word)) return false;
        $this->position++;
        return true;
    }
    private function syntax(): never {
        fail("syntax error at '".$this->peek()['text']."'");
    }
    private function expect(string $word): void {
        if (!$this->accept($word))$this->syntax();
    }
    private function kind(string $kind): mixed {
        if ($this->peek()['kind'] !== $kind)$this->syntax();
        return $this->take()['value'];
    }
    private function comma(Closure $read): array {
        $a = [$read()];
        while ($this->accept(','))$a[] = $read();
        return $a;
    }
    private function parens(Closure $read): array {
        $this->expect('(');
        $a = $this->comma($read);
        $this->expect(')');
        return $a;
    }
    private function alias(): ?string {
        if ($this->accept('AS')) return $this->kind('name');
        return $this->peek()['kind'] === 'name'?$this->take()['value']:null;
    }
    private function table(): array {
        $name = $this->kind('name');
        return ['name' => $name, 'alias' => $this->alias() ?? $name];
    }
    private function reference(): Expr {
        $name = $this->kind('name');
        $e = new Expr('ref');
        if ($this->accept('.')) {
            $e->table = $name;
            $e->column = $this->kind('name');
            $e->text = $name.'.'.$e->column;
        } else $e->text = $e->column = $name;
        return $e;
    }
    private function expression(int $level = 0): Expr {
        if ($level === 2 && $this->accept('NOT')) return new Expr('unary', 'NOT', [$this->expression(2)]);
        if ($level === 6 && $this->accept('-')) return new Expr('unary', '-', [$this->expression(6)]);
        if ($level === 7) return $this->primary();
        $left = $this->expression($level+1);
        if ($level === 3) {
            if ($this->peek()['kind'] === 'symbol' && in_array($this->peek()['value'], COMPARISONS, true)) {
                $op = $this->take()['value'];
                return new Expr('binary', $op, [$left, $this->expression(4)]);
            }
            if ($this->accept('IS')) {
                $neg = $this->accept('NOT');
                $this->expect('NULL');
                $e = new Expr('isnull', '', [$left]);
                $e->negated = $neg;
                return $e;
            }
            $neg = $this->accept('NOT');
            $e = null;
            if ($this->accept('IN'))$e = new Expr('in', '', [$left, ...$this->parens(fn() => $this->expression())]);
            elseif($this->accept('BETWEEN')) {
                $low = $this->expression(4);
                $this->expect('AND');
                $e = new Expr('between', '', [$left, $low, $this->expression(4)]);
            }
            elseif($this->accept('LIKE'))$e = new Expr('like', '', [$left, $this->expression(4)]);
            elseif($neg)$this->syntax();
            if ($e) {
                $e->negated = $neg;
                return $e;
            }
            return $left;
        }
        $ops = [0 => ['OR'], 1 => ['AND'], 2 => [], 4 => ['+', '-', '||'], 5 => ['*', '/', '%'], 6 => []][$level];
        while (in_array($this->peek()['kind'], ['keyword', 'symbol'], true) && in_array($this->peek()['value'], $ops, true)) {
            $op = $this->take()['value'];
            $left = new Expr('binary', $op, [$left, $this->expression($level+1)]);
        }
        return $left;
    }
    private function primary(): Expr {
        $t = $this->peek();
        if (in_array($t['kind'], ['integer', 'string'], true)) {
            $this->take();
            return new Expr('literal', value:$t['value']);
        }
        if ($this->accept('NULL')) return new Expr('literal');
        if ($t['kind'] === 'name') return $this->reference();
        if ($t['kind'] === 'keyword' && in_array($t['value'], AGGREGATES, true)) {
            $name = $this->take()['value'];
            $e = new Expr('aggregate', $name);
            $this->expect('(');
            if (!($name === 'COUNT' && $this->accept('*'))) {
                $e->distinct = $this->accept('DISTINCT');
                $e->args = [$this->expression()];
            }
            $this->expect(')');
            return $e;
        }
        if ($this->accept('(')) {
            $e = $this->expression();
            $this->expect(')');
            return new Expr('group', '', [$e]);
        }
        $this->syntax();
    }
    private function clause(string $word): ?Expr {
        return $this->accept($word)?$this->expression():null;
    }
    private function item(): array {
        $start = $this->position;
        $e = $this->expression();
        $ts = array_slice($this->tokens, $start, $this->position-$start);
        $alias = $this->alias();
        $heading = $alias;
        if ($heading === null) {
            if ($e->kind === 'ref')$heading = $e->column;
            else {
                $heading = '';
                foreach ($ts as $i => $t) {
                    if ($i>0 && $t['kind'] !== 'symbol' && $ts[$i-1]['kind'] !== 'symbol')$heading. = ' ';
                    $heading. = $t['text'];
                }
            }
        }
        return ['expr' => $e, 'alias' => $alias, 'heading' => $heading];
    }
    private function orderItem(): array {
        $start = $this->position;
        $e = $this->expression();
        $single = $this->position === $start+1;
        $t = $this->tokens[$start];
        $desc = $this->accept('DESC');
        if (!$desc)$this->accept('ASC');
        return ['expr' => $e, 'desc' => $desc, 'ordinal' => $single && $t['kind'] === 'integer'?$t['value']:null, 'alias' => $single && $t['kind'] === 'name'?$t['value']:null];
    }
    private function query(): array {
        $q = ['kind' => 'select', 'distinct' => $this->accept('DISTINCT'), 'star' => $this->accept('*'), 'joins' => [], 'group' => null, 'order' => [], 'limit' => null, 'offset' => 0];
        $q['items'] = $q['star']?[]:$this->comma(fn() => $this->item());
        $this->expect('FROM');
        $q['source'] = $this->table();
        while ($this->at('JOIN') || $this->at('INNER') || $this->at('LEFT')) {
            $left = $this->accept('LEFT');
            if ($left)$this->accept('OUTER');
            else $this->accept('INNER');
            $this->expect('JOIN');
            $t = $this->table();
            $this->expect('ON');
            $q['joins'][] = ['table' => $t, 'left' => $left, 'condition' => $this->expression()];
        }
        $q['where'] = $this->clause('WHERE');
        if ($this->accept('GROUP')) {
            $this->expect('BY');
            $q['group'] = $this->comma(fn() => $this->reference());
        }
        $q['having'] = $this->clause('HAVING');
        if ($this->accept('ORDER')) {
            $this->expect('BY');
            $q['order'] = $this->comma(fn() => $this->orderItem());
        }
        if ($this->accept('LIMIT')) {
            $q['limit'] = $this->kind('integer');
            if ($this->accept('OFFSET'))$q['offset'] = $this->kind('integer');
        }
        return $q;
    }
    public function statement(): ?array {
        $s = null;
        if ($this->accept('CREATE')) {
            $this->expect('TABLE');
            $name = $this->kind('name');
            $columns = $this->parens(function() {
                $n = $this->kind('name');
                if (!$this->at('INT') && !$this->at('TEXT'))$this->syntax();
                $type = $this->take()['value'];
                $pk = 0;
                $nn = false;
                while (true) {
                    if ($this->accept('PRIMARY')) {
                        $this->expect('KEY');
                        $pk++;
                        $nn = true;
                    } elseif($this->accept('NOT')) {
                        $this->expect('NULL');
                        $nn = true;
                    } else break;
                }
                return ['name' => $n, 'type' => $type, 'primary' => $pk, 'notNull' => $nn];
            });
            $s = ['kind' => 'create', 'name' => $name, 'columns' => $columns];
        }
        elseif($this->accept('DROP')) {
            $this->expect('TABLE');
            $s = ['kind' => 'drop', 'name' => $this->kind('name')];
        }
        elseif($this->accept('INSERT')) {
            $this->expect('INTO');
            $name = $this->kind('name');
            $names = $this->at('(')?$this->parens(fn() => $this->kind('name')):null;
            $this->expect('VALUES');
            $s = ['kind' => 'insert', 'name' => $name, 'names' => $names, 'tuples' => $this->comma(fn() => $this->parens(fn() => $this->expression()))];
        }
        elseif($this->accept('UPDATE')) {
            $name = $this->kind('name');
            $this->expect('SET');
            $as = $this->comma(function() {
                $n = $this->kind('name');
                $this->expect('=');
                return [$n, $this->expression()];
            });
            $s = ['kind' => 'update', 'name' => $name, 'assignments' => $as, 'where' => $this->clause('WHERE')];
        }
        elseif($this->accept('DELETE')) {
            $this->expect('FROM');
            $s = ['kind' => 'delete', 'name' => $this->kind('name'), 'where' => $this->clause('WHERE')];
        }
        elseif($this->accept('SELECT'))$s = $this->query();
        elseif($this->accept('EXIT'))$s = ['kind' => 'exit'];
        $this->expect(';');
        return $s;
    }
}
final class Table {
    public array $rows = [];
    public function __construct(public string $name, public array $columns, public ?int $primary = null) {
    }
    public function column(string $name): ?int {
        foreach ($this->columns as $i => $c) if ($c['name'] === $name) return $i;
        return null;
    }
}
final class Scope {
    public array $entries = [];
    public int $width = 0;
    public function add(string $name, Table $table): void {
        foreach ($this->entries as $entry) if ($entry['name'] === $name) fail('duplicate table name '.$name);
        $this->entries[] = ['name' => $name, 'table' => $table, 'offset' => $this->width];
        $this->width += count($table->columns);
    }
    public function resolve(Expr $e): string {
        $found = [];
        $seen = false;
        foreach ($this->entries as $entry) if ($e->table === null || $e->table === $entry['name']) {
            $seen = true;
            $i = $entry['table']->column($e->column);
            if ($i !== null)$found[] = [$entry['offset']+$i, $entry['table']->columns[$i]['type']];
        }
        if ($e->table !== null && !$seen) fail('unknown table '.$e->table);
        if (!$found) fail('unknown column '.$e->text);
        if (count($found)>1) fail('ambiguous column '.$e->column);
        $e->index = $found[0][0];
        return $found[0][1];
    }
}
function compatible(string $a, string $b): bool {
    return $a === $b || $a === 'NULL' || $b === 'NULL';
}
function requireType(string $a, string $b, string $op): void {
    if (!compatible($a, $b)) fail('type mismatch for '.$op);
}
function check(Expr $e, Scope $scope, bool $allow = false, ?array $grouped = null, bool $inside = false): string {
    if ($e->kind === 'literal') return $e->value === null?'NULL':(is_int($e->value)?'INT':'TEXT');
    if ($e->kind === 'ref') {
        $t = $scope->resolve($e);
        if ($grouped !== null && !$inside && !in_array($e->index, $grouped, true)) fail('column '.$e->text.' is not grouped');
        return $t;
    }
    if ($e->kind === 'aggregate') {
        if (!$allow || $inside) fail('misuse of aggregate '.$e->op);
        if (!$e->args) return 'INT';
        $t = check($e->args[0], $scope, $allow, $grouped, true);
        if (in_array($e->op, ['SUM', 'AVG'], true)) requireType($t, 'INT', $e->op);
        return in_array($e->op, ['MIN', 'MAX'], true)?$t:'INT';
    }
    $types = [];
    foreach ($e->args as $a)$types[] = check($a, $scope, $allow, $grouped, $inside);
    if ($e->kind === 'group') return $types[0];
    if ($e->kind === 'isnull') return 'INT';
    if ($e->kind === 'binary' && in_array($e->op, COMPARISONS, true)) {
        requireType($types[0], $types[1], $e->op);
        return 'INT';
    }
    if ($e->kind === 'in' || $e->kind === 'between') {
        foreach (array_slice($types, 1) as $t) requireType($t, $types[0], $e->kind === 'in'?'IN':'BETWEEN');
        return 'INT';
    }
    $op = $e->kind === 'like'?'LIKE':$e->op;
    $type = in_array($op, ['LIKE', '||'], true)?'TEXT':'INT';
    foreach ($types as $t) requireType($t, $type, $op);
    return $op === '||'?'TEXT':'INT';
}
function condition(?Expr $e, Scope $s, string $name, bool $allow = false, ?array $grouped = null): void {
    if ($e !== null) requireType(check($e, $s, $allow, $grouped), 'INT', $name);
}
function hasAggregate(Expr $e): bool {
    if ($e->kind === 'aggregate') return true;
    foreach ($e->args as $a) if (hasAggregate($a)) return true;
    return false;
}
function truth(int|string|null $v): bool {
    return $v !== null && $v !== 0;
}
function inverse(?int $v): ?int {
    return $v === null?null:($v === 0?1:0);
}
function operate(string $op, int|string|null $a, int|string|null $b): int|string|null {
    if ($op === 'AND') return $a === 0 || $b === 0?0:($a === null || $b === null?null:1);
    if ($op === 'OR') return truth($a) || truth($b)?1:($a === null || $b === null?null:0);
    if ($a === null || $b === null) return null;
    return match($op) {
        '+' => $a+$b, '-' => $a-$b, '*' => $a*$b, '||' => $a.$b, '/' => $b === 0?null:intdiv($a, $b), '%' => $b === 0?null:$a-$b*intdiv($a, $b), '=' => $a === $b?1:0, '<>', '!=' => $a !== $b?1:0, '<' => compareValues($a, $b)<0?1:0, '<=' => compareValues($a, $b) <= 0?1:0, '>' => compareValues($a, $b)>0?1:0, '>=' => compareValues($a, $b) >= 0?1:0
    };
}
function likeMatch(string $text, string $pattern): int {
    $dp = array_fill(0, strlen($text)+1, false);
    $dp[0] = true;
    for ($j = 0; $j<strlen($pattern); $j++) {
        $c = $pattern[$j];
        if ($c === '%') {
            for ($i = 1; $i <= strlen($text); $i++)$dp[$i] = $dp[$i] || $dp[$i-1];
        } else {
            for ($i = strlen($text); $i>0; $i--)$dp[$i] = $dp[$i-1] && ($c === '_' || $c === $text[$i-1]);
            $dp[0] = false;
        }
    }
    return $dp[strlen($text)]?1:0;
}
function evaluate(Expr $e, array $row, ?array $group = null): int|string|null {
    if ($e->kind === 'literal') return $e->value;
    if ($e->kind === 'ref') return $row[$e->index];
    if ($e->kind === 'aggregate') {
        if (!$e->args) return count($group);
        $values = [];
        foreach ($group as $r) {
            $v = evaluate($e->args[0], $r);
            if ($v !== null && (!$e->distinct || !in_array($v, $values, true)))$values[] = $v;
        }
        if ($e->op === 'COUNT') return count($values);
        if (!$values) return null;
        return match($e->op) {
            'SUM' => array_sum($values), 'AVG' => intdiv(array_sum($values), count($values)), 'MIN' => array_reduce(array_slice($values, 1), fn($a, $b) => compareValues($a, $b) <= 0?$a:$b, $values[0]), 'MAX' => array_reduce(array_slice($values, 1), fn($a, $b) => compareValues($a, $b) >= 0?$a:$b, $values[0])
        };
    }
    $a = [];
    foreach ($e->args as $arg)$a[] = evaluate($arg, $row, $group);
    if ($e->kind === 'group') return $a[0];
    if ($e->kind === 'unary') return $e->op === 'NOT'?inverse($a[0]):($a[0] === null?null:-$a[0]);
    if ($e->kind === 'binary') return operate($e->op, $a[0], $a[1]);
    if ($e->kind === 'isnull') return (($a[0] === null) !== $e->negated)?1:0;
    $result = match($e->kind) {
        'in' => $a[0] === null?null:(in_array($a[0], array_slice($a, 1), true)?1:(in_array(null, array_slice($a, 1), true)?null:0)), 'between' => operate('AND', operate('>=', $a[0], $a[1]), operate('<=', $a[0], $a[2])), 'like' => $a[0] === null || $a[1] === null?null:likeMatch($a[0], $a[1])
    };
    return $e->negated?inverse($result):$result;
}
function satisfies(?Expr $e, array $row, ?array $group = null): bool {
    return $e === null || truth(evaluate($e, $row, $group));
}
function rowCount(int $n): string {
    return $n.($n === 1?' row':' rows');
}
function written(int|string|null $v): string {
    return $v === null?'NULL':(string)$v;
}
function compareValues(int|string|null $a, int|string|null $b): int {
    if ($a === $b) return 0;
    if ($a === null) return -1;
    if ($b === null) return 1;
    return is_string($a)?strcmp($a, $b):($a <=> $b);
}
function printTable(array $items, array $types, array $rows): void {
    $headings = array_column($items, 'heading');
    $cells = array_map(fn($r) => array_map('written', $r), $rows);
    $widths = array_map('strlen', $headings);
    foreach ($cells as $r) foreach ($r as $i => $v)$widths[$i] = max($widths[$i], strlen($v));
    $sep = '+';
    foreach ($widths as $w)$sep. = str_repeat('-', $w+2).'+';
    $render = function($row, $header) use($widths, $types) {
        $s = '|';
        foreach ($row as $i => $v)$s. = ' '.str_pad($v, $widths[$i], ' ', !$header && $types[$i] === 'INT'?STR_PAD_LEFT:STR_PAD_RIGHT).' |';
        return $s;
    };
    echo $sep, "\n", $render($headings, true), "\n", $sep, "\n";
    foreach ($cells as $r) echo $render($r, false), "\n";
    echo $sep, "\n(", rowCount(count($rows)), ")\n";
}
final class Database {
    private array $tables = [];
    private function table(string $name): Table {
        if (!isset($this->tables[$name])) fail('unknown table '.$name);
        return $this->tables[$name];
    }
    private function targets(Table $t, array $names): array {
        $result = [];
        foreach ($names as $n) {
            $i = $t->column($n);
            if ($i === null) fail('unknown column '.$n);
            if (in_array($i, $result, true)) fail('duplicate column '.$n);
            $result[] = $i;
        }
        return $result;
    }
    private function constraints(Table $t, array $rows, array $checked): void {
        foreach ($checked as $i) {
            foreach ($t->columns as $j => $c) if ($c['notNull'] && $rows[$i][$j] === null) fail('NULL value in column '.$c['name']);
            if ($t->primary !== null) foreach ($rows as $j => $r) if ($i !== $j && $r[$t->primary] === $rows[$i][$t->primary]) fail('duplicate primary key '.written($r[$t->primary]));
        }
    }
    public function execute(array $s): void {
        if ($s['kind'] === 'select') {
            $this->select($s);
            return;
        }
        if ($s['kind'] === 'create') {
            if (isset($this->tables[$s['name']])) fail('table '.$s['name'].' already exists');
            $seen = [];
            $primary = 0;
            $key = null;
            foreach ($s['columns'] as $i => $c) {
                if (isset($seen[$c['name']])) fail('duplicate column '.$c['name']);
                $seen[$c['name']] = true;
                $primary += $c['primary'];
                if ($primary >= 2) fail('multiple primary keys');
                if ($c['primary']>0)$key = $i;
            }
            $this->tables[$s['name']] = new Table($s['name'], $s['columns'], $key);
            echo 'Table ', $s['name'], " created.\n";
            return;
        }
        $t = $this->table($s['name']);
        if ($s['kind'] === 'drop') {
            unset($this->tables[$s['name']]);
            echo 'Table ', $s['name'], " dropped.\n";
            return;
        }
        $rows = [];
        $checked = [];
        $count = 0;
        if ($s['kind'] === 'insert') {
            $targets = $s['names'] === null?array_keys($t->columns):$this->targets($t, $s['names']);
            foreach ($s['tuples'] as $tuple) {
                if (count($tuple) !== count($targets)) fail('expected '.count($targets).' values, got '.count($tuple));
                foreach ($tuple as $i => $e) {
                    $c = $t->columns[$targets[$i]];
                    requireType(check($e, new Scope()), $c['type'], 'column '.$c['name']);
                }
            }
            $rows = $t->rows;
            foreach ($s['tuples'] as $tuple) {
                $row = array_fill(0, count($t->columns), null);
                foreach ($tuple as $i => $e)$row[$targets[$i]] = evaluate($e, []);
                $checked[] = count($rows);
                $rows[] = $row;
            }
            $this->constraints($t, $rows, $checked);
            $count = count($s['tuples']);
        } elseif($s['kind'] === 'update') {
            $targets = $this->targets($t, array_column($s['assignments'], 0));
            $scope = new Scope();
            $scope->add($t->name, $t);
            foreach ($s['assignments'] as $i => $a) {
                $c = $t->columns[$targets[$i]];
                requireType(check($a[1], $scope), $c['type'], 'column '.$c['name']);
            }
            condition($s['where'], $scope, 'WHERE');
            foreach ($t->rows as $i => $row) {
                $next = $row;
                if (satisfies($s['where'], $row)) {
                    foreach ($s['assignments'] as $j => $a)$next[$targets[$j]] = evaluate($a[1], $row);
                    $checked[] = $i;
                    $count++;
                }
                $rows[] = $next;
            }
            $this->constraints($t, $rows, $checked);
        } else {
            $scope = new Scope();
            $scope->add($t->name, $t);
            condition($s['where'], $scope, 'WHERE');
            foreach ($t->rows as $row) if (satisfies($s['where'], $row))$count++;
            else $rows[] = $row;
        }
        $t->rows = $rows;
        echo rowCount($count), match($s['kind']) {
            'insert' => ' inserted.', 'update' => ' updated.', 'delete' => ' deleted.'
        }, "\n";
    }
    private function select(array $q): void {
        $scope = new Scope();
        $scope->add($q['source']['alias'], $this->table($q['source']['name']));
        foreach ($q['joins'] as $j) {
            $scope->add($j['table']['alias'], $this->table($j['table']['name']));
            condition($j['condition'], $scope, 'ON');
        }
        condition($q['where'], $scope, 'WHERE');
        $grouping = [];
        foreach ($q['group'] ?? [] as $ref) {
            $scope->resolve($ref);
            $grouping[] = $ref->index;
        }
        $items = $q['items'];
        if ($q['star']) foreach ($scope->entries as $entry) foreach ($entry['table']->columns as $c) {
            $e = new Expr('ref');
            $e->table = $entry['name'];
            $e->column = $e->text = $c['name'];
            $items[] = ['expr' => $e, 'heading' => $c['name'], 'alias' => null];
        }
        $aggregate = $q['group'] !== null || $q['having'] !== null;
        foreach ([...$items, ...$q['order']] as $i)$aggregate = $aggregate || hasAggregate($i['expr']);
        $grouped = $aggregate?$grouping:null;
        $types = [];
        foreach ($items as $i)$types[] = check($i['expr'], $scope, true, $grouped);
        condition($q['having'], $scope, 'HAVING', true, $grouped);
        $keys = [];
        foreach ($q['order'] as $o) {
            $key = null;
            if ($o['ordinal'] !== null) {
                $k = $o['ordinal'];
                if ($k<1 || $k>count($items)) fail('ORDER BY position '.$k.' is out of range');
                $key = $items[$k-1]['expr'];
            } elseif($o['alias'] !== null) foreach ($items as $i) if ($i['alias'] === $o['alias']) {
                $key = $i['expr'];
                break;
            }
            if ($key === null) {
                check($o['expr'], $scope, true, $grouped);
                $key = $o['expr'];
            }
            $keys[] = $key;
        }
        $rows = $scope->entries[0]['table']->rows;
        foreach ($q['joins'] as $ji => $join) {
            $t = $scope->entries[$ji+1]['table'];
            $next = [];
            foreach ($rows as $left) {
                $found = false;
                foreach ($t->rows as $right) {
                    $combined = [...$left, ...$right];
                    if (satisfies($join['condition'], $combined)) {
                        $next[] = $combined;
                        $found = true;
                    }
                }
                if ($join['left'] && !$found)$next[] = [...$left, ...array_fill(0, count($t->columns), null)];
            }
            $rows = $next;
        }
        $rows = array_values(array_filter($rows, fn($r) => satisfies($q['where'], $r)));
        $groups = [];
        if (!$aggregate) foreach ($rows as $r)$groups[] = [$r];
        elseif($q['group'] === null)$groups = [$rows];
        else {
            $groupKeys = [];
            foreach ($rows as $r) {
                $key = array_map(fn($i) => $r[$i], $grouping);
                $at = array_search($key, $groupKeys, true);
                if ($at === false) {
                    $at = count($groups);
                    $groups[] = [];
                    $groupKeys[] = $key;
                }
                $groups[$at][] = $r;
            }
        }
        $results = [];
        foreach ($groups as $g) {
            $row = $g[0] ?? [];
            $context = $aggregate?$g:null;
            if (!satisfies($q['having'], $row, $context)) continue;
            $values = [];
            $sort = [];
            foreach ($items as $i)$values[] = evaluate($i['expr'], $row, $context);
            foreach ($keys as $key)$sort[] = evaluate($key, $row, $context);
            $results[] = ['values' => $values, 'keys' => $sort, 'position' => count($results)];
        }
        usort($results, function($a, $b) use($q) {
            foreach ($q['order'] as $i => $o) {
                $c = compareValues($a['keys'][$i], $b['keys'][$i]);
                if ($c !== 0) return $o['desc']?-$c:$c;
            }
            return $a['position'] <=> $b['position'];
        });
        $unique = [];
        foreach ($results as $r) if (!$q['distinct'] || !in_array($r['values'], $unique, true))$unique[] = $r['values'];
        $rows = array_slice($unique, $q['offset'], $q['limit']);
        printTable($items, $types, $rows);
    }
}
$source = stream_get_contents(STDIN);
$start = 0;
$segments = [];
for ($i = 0; $i<strlen($source); $i++) {
    if ($source[$i] === "'")$i = strpos($source, "'", $i+1);
    elseif(substr($source, $i, 2) === '--') {
        $end = strpos($source, "\n", $i);
        $i = $end === false?strlen($source):$end;
    } elseif($source[$i] === ';') {
        $segments[] = substr($source, $start, $i-$start+1);
        $start = $i+1;
    }
}
$db = new Database();
foreach ($segments as $text) {
    try {
        $s = (new Parser(tokenize($text)))->statement();
        if ($s !== null && $s['kind'] === 'exit') break;
        if ($s !== null)$db->execute($s);
    } catch (SqlError $err) {
        echo 'ERROR: ', $err->getMessage(), "\n";
    }
}
