<?php

const GREEK = [
    'alpha',
    'beta',
    'gamma',
    'delta',
    'epsilon',
    'zeta',
    'eta',
    'theta',
    'iota',
    'kappa',
    'lambda',
    'mu',
    'nu',
    'xi',
    'pi',
    'rho',
    'sigma',
    'tau',
    'upsilon',
    'phi',
    'chi',
    'psi',
    'omega',
    'Gamma',
    'Delta',
    'Theta',
    'Lambda',
    'Xi',
    'Pi',
    'Sigma',
    'Upsilon',
    'Phi',
    'Psi',
    'Omega',
];

const FUNCTIONS = ['sin', 'cos', 'tan', 'log', 'ln', 'exp', 'det', 'lim', 'max', 'min'];

const LARGE_OPERATORS = ['sum', 'prod', 'int'];

const ACCENTS = ['overline', 'hat', 'vec', 'dot', 'tilde', 'overbrace', 'underbrace'];

const CONSTRUCTS = ['frac', 'binom', 'overset', 'underset', 'sqrt', 'left', 'right'];

const RAW_COMMANDS = ['text', 'begin', 'end', 'tag', 'label', 'eqref'];

const ENVIRONMENTS = ['matrix', 'pmatrix', 'bmatrix', 'vmatrix', 'cases'];

function symbolCommands(): array
{
    static $table = null;
    if ($table !== null)
        return $table;
    $table = [];
    foreach (GREEK as $name)
        $table['\\' . $name] = [$name, 'ordinary'];
    foreach ([...FUNCTIONS, ...LARGE_OPERATORS] as $name)
        $table['\\' . $name] = [$name, 'operator'];
    return $table += [
        '\\cdot' => ['*', 'binary'],
        '\\times' => ['x', 'binary'],
        '\\pm' => ['+-', 'binary'],
        '\\mp' => ['-+', 'binary'],
        '\\leq' => ['<=', 'relation'],
        '\\geq' => ['>=', 'relation'],
        '\\neq' => ['!=', 'relation'],
        '\\approx' => ['~=', 'relation'],
        '\\to' => ['->', 'relation'],
        '\\infty' => ['oo', 'ordinary'],
        '\\ldots' => ['...', 'ordinary'],
        '\\cdots' => ['...', 'ordinary'],
        '\\quad' => ['  ', 'ordinary'],
        '\\,' => [' ', 'ordinary'],
        '\\{' => ['{', 'open'],
        '\\}' => ['}', 'close'],
    ];
}

final class FormulaError extends RuntimeException
{
    public function __construct(
        public int $column,
        string $message,
    ) {
        parent::__construct($message);
    }
}

final readonly class Token
{
    public function __construct(
        public string $kind,
        public string $value,
        public int $column,
    ) {}
}

function letter(string $ch): bool
{
    return $ch >= 'A' && $ch <= 'Z' || $ch >= 'a' && $ch <= 'z';
}

function digit(string $ch): bool
{
    return $ch >= '0' && $ch <= '9';
}

function tokenize(string $line): array
{
    $tokens = [];
    $i = 0;
    $n = strlen($line);
    $symbols = "+-*/=<>:()[],;.!|'";
    $commands = symbolCommands();
    while ($i < $n) {
        $ch = $line[$i];
        $column = $i + 1;
        if ($ch === ' ') {
            ++$i;
            continue;
        }
        if (letter($ch)) {
            $start = $i++;
            while ($i < $n && letter($line[$i]))
                ++$i;
            $tokens[] = new Token('identifier', substr($line, $start, $i - $start), $column);
            continue;
        }
        if (digit($ch)) {
            $start = $i++;
            while ($i < $n && digit($line[$i]))
                ++$i;
            if (($i + 1) < $n && $line[$i] === '.' && digit($line[$i + 1])) {
                $i += 2;
                while ($i < $n && digit($line[$i]))
                    ++$i;
            }
            $tokens[] = new Token('number', substr($line, $start, $i - $start), $column);
            continue;
        }
        if (str_contains($symbols, $ch) || str_contains('{}^_&', $ch)) {
            $tokens[] = new Token(str_contains($symbols, $ch) ? 'symbol' : $ch, $ch, $column);
            ++$i;
            continue;
        }
        if ($ch !== '\\')
            throw new FormulaError($column, 'invalid character ' . $ch);
        ++$i;
        if ($i < $n && str_contains('\\{},', $line[$i])) {
            $escaped = $line[$i++];
            $tokens[] = new Token($escaped === '\\' ? 'newline' : 'command', '\\' . $escaped, $column);
            continue;
        }
        $start = $i;
        while ($i < $n && letter($line[$i]))
            ++$i;
        $name = substr($line, $start, $i - $start);
        if ($name === '')
            throw new FormulaError($column, 'invalid command');
        if (in_array($name, RAW_COMMANDS, true)) {
            while ($i < $n && $line[$i] === ' ')
                ++$i;
            if ($i === $n || $line[$i] !== '{')
                throw new FormulaError($i + 1, 'expected {');
            $end = strpos($line, '}', $i + 1);
            if ($end === false)
                throw new FormulaError($column, 'unterminated argument');
            $argument = substr($line, $i + 1, $end - $i - 1);
            if (($name === 'begin' || $name === 'end') && !in_array($argument, ENVIRONMENTS, true))
                throw new FormulaError($column, 'unknown environment "' . $argument . '"');
            $tokens[] = new Token($name, $argument, $column);
            $i = $end + 1;
        } elseif (isset($commands['\\' . $name]))
            $tokens[] = new Token('command', '\\' . $name, $column);
        elseif (in_array($name, ACCENTS, true))
            $tokens[] = new Token('accent', $name, $column);
        elseif (in_array($name, CONSTRUCTS, true))
            $tokens[] = new Token($name, $name, $column);
        else
            throw new FormulaError($column, 'unknown command \\' . $name);
    }
    $tokens[] = new Token('eof', '', $n + 1);
    return $tokens;
}
