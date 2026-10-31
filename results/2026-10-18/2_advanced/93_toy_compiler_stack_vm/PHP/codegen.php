<?php

const BINARY = [
    '+' => 'ADD',
    '-' => 'SUB',
    '*' => 'MUL',
    '/' => 'DIV',
    '%' => 'MOD',
    '<' => 'LT',
    '<=' => 'LE',
    '>' => 'GT',
    '>=' => 'GE',
    '==' => 'EQ',
    '!=' => 'NE',
];

const JUMPS = ['JUMP', 'JUMPF', 'JUMPT'];

const CONDITIONAL = ['JUMPF', 'JUMPT'];

const TRANSFERS = ['JUMP', 'RET', 'RETV', 'HALT'];

const NEGATED = ['LT' => 'GE', 'LE' => 'GT', 'GT' => 'LE', 'GE' => 'LT', 'EQ' => 'NE', 'NE' => 'EQ'];

const INVERSE = ['JUMPF' => 'JUMPT', 'JUMPT' => 'JUMPF'];

final readonly class Instruction
{
    public function __construct(
        public string $op,
        public array $args,
        public array $position,
    ) {}
}

final class Label
{
    public ?int $position = null;
}

final class Unit
{
    public array $after = [], $blocks = [];
    public int $beforeStart = 0, $afterStart = 0, $depth = 0;
    public bool $recursive = false;

    public function __construct(
        public string $name,
        public ?object $function,
        public array $slots,
        public array $before,
    ) {}
}

final class CodeGenerator
{
    private array $code = [], $loops = [];

    public function emit(string $op, array $p, mixed ...$args): void
    {
        $this->code[] = new Instruction($op, $args, $p);
    }

    private function mark(Label $label): void
    {
        $label->position = count($this->code);
    }

    public function finish(): array
    {
        return array_map(
            fn($i) => new Instruction(
                $i->op,
                in_array($i->op, JUMPS, true) ? [$i->args[0]->position] : $i->args,
                $i->position,
            ),
            $this->code,
        );
    }

    public function expression(object $n): void
    {
        $p = $n->position;
        switch ($n->kind) {
            case 'integer':
            case 'boolean':
                $this->emit('PUSH', $p, (int) $n->value);
                break;
            case 'variable':
                $r = $n->referent;
                $this->emit(
                    $r->kind === 'global' ? 'LOADG' : 'LOADL',
                    $p,
                    $r->kind === 'global' ? $r->address : $r->slot,
                );
                break;
            case 'array':
                $this->expression($n->index);
                $this->emit('LOADA', $p, $n->referent->address, $n->referent->size);
                break;
            case 'read':
                $this->emit('READ', $p);
                break;
            case 'call':
                foreach ($n->arguments as $a)
                    $this->expression($a);
                $this->emit('CALL', $p, $n->referent->name, count($n->arguments));
                break;
            case 'unary':
                $this->expression($n->operand);
                $this->emit($n->operator === '-' ? 'NEG' : 'NOT', $p);
                break;
            case 'binary':
                if ($n->operator === '&&' || $n->operator === '||') {
                    $shortcut = new Label();
                    $end = new Label();
                    $this->expression($n->left);
                    $this->emit($n->operator === '&&' ? 'JUMPF' : 'JUMPT', $p, $shortcut);
                    $this->expression($n->right);
                    $this->emit('JUMP', $p, $end);
                    $this->mark($shortcut);
                    $this->emit('PUSH', $p, (int) ($n->operator === '||'));
                    $this->mark($end);
                } else {
                    $this->expression($n->left);
                    $this->expression($n->right);
                    $this->emit(BINARY[$n->operator], $p);
                }
                break;
        }
    }

    public function statement(object $n): void
    {
        $p = $n->position;
        switch ($n->kind) {
            case 'declaration':
                if ($n->initializer === null)
                    $this->emit('PUSH', $n->namePosition, 0);
                else
                    $this->expression($n->initializer);
                $this->emit('STOREL', $n->namePosition, $n->slot);
                break;
            case 'assignment':
                if ($n->index !== null)
                    $this->expression($n->index);
                $this->expression($n->value);
                $r = $n->referent;
                if ($n->index !== null)
                    $this->emit('STOREA', $p, $r->address, $r->size);
                else
                    $this->emit(
                        $r->kind === 'global' ? 'STOREG' : 'STOREL',
                        $p,
                        $r->kind === 'global' ? $r->address : $r->slot,
                    );
                break;
            case 'call_statement':
                $this->expression($n->expression);
                if ($n->expression->type !== 'void')
                    $this->emit('POP', $p);
                break;
            case 'print':
                foreach ($n->arguments as $a)
                    $this->expression($a);
                $this->emit('PRINT', $p, count($n->arguments));
                break;
            case 'if':
                $alternative = new Label();
                $end = new Label();
                $this->expression($n->condition);
                $this->emit('JUMPF', $p, $alternative);
                $this->statement($n->then);
                if ($n->otherwise === null)
                    $this->mark($alternative);
                else {
                    $this->emit('JUMP', $p, $end);
                    $this->mark($alternative);
                    $this->statement($n->otherwise);
                    $this->mark($end);
                }
                break;
            case 'while':
                $start = new Label();
                $end = new Label();
                $this->mark($start);
                $this->expression($n->condition);
                $this->emit('JUMPF', $p, $end);
                $this->loops[] = [$end, $start];
                $this->statement($n->body);
                array_pop($this->loops);
                $this->emit('JUMP', $p, $start);
                $this->mark($end);
                break;
            case 'for':
                $start = new Label();
                $update = new Label();
                $end = new Label();
                if ($n->initial !== null)
                    $this->statement($n->initial);
                $this->mark($start);
                if ($n->condition !== null) {
                    $this->expression($n->condition);
                    $this->emit('JUMPF', $p, $end);
                }
                $this->loops[] = [$end, $update];
                $this->statement($n->body);
                array_pop($this->loops);
                $this->mark($update);
                if ($n->update !== null)
                    $this->statement($n->update);
                $this->emit('JUMP', $p, $start);
                $this->mark($end);
                break;
            case 'break':
            case 'continue':
                $this->emit(
                    'JUMP',
                    $p,
                    $this->loops[count($this->loops) - 1][$n->kind === 'continue' ? 1 : 0],
                );
                break;
            case 'return':
                if ($n->value === null)
                    $this->emit('RET', $p);
                else {
                    $this->expression($n->value);
                    $this->emit('RETV', $p);
                }
                break;
            case 'block':
                foreach ($n->statements as $s)
                    $this->statement($s);
                break;
        }
    }
}

function assignSlots(object $function): array
{
    $decls = [];
    $pending = [$function->body];
    while ($pending) {
        $n = array_pop($pending);
        if ($n->kind === 'declaration')
            $decls[] = $n;
        array_push($pending, ...statementChildren($n));
    }
    usort($decls, fn($a, $b) => $a->namePosition <=> $b->namePosition);
    $slots = [...$function->parameters, ...$decls];
    foreach ($slots as $i => $d)
        $d->slot = $i;
    return $slots;
}

function generate(array $globals, array $functions, object $main): array
{
    $address = 0;
    foreach ($globals as $v) {
        $v->address = $address;
        $address += $v->size ?? 1;
    }
    $g = new CodeGenerator();
    foreach ($globals as $v)
        if ($v->initializer !== null) {
            $g->expression($v->initializer);
            $g->emit('STOREG', $v->namePosition, $v->address);
        }
    $g->emit('CALL', $main->namePosition, 'main', 0);
    $g->emit('HALT', $main->namePosition);
    $units = [new Unit('<init>', null, [], $g->finish())];
    foreach ($functions as $function) {
        $slots = assignSlots($function);
        $g = new CodeGenerator();
        $g->emit('ENTER', $function->namePosition, count($slots));
        $g->statement($function->body);
        if ($function->type === 'void')
            $g->emit('RET', $function->body->endPosition);
        $units[] = new Unit($function->name, $function, $slots, $g->finish());
    }
    return [$units, $address];
}
