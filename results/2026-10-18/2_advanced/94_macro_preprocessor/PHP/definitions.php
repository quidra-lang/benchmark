<?php

const BUILTINS = ['__LINE__', '__FILE__', '__COUNTER__'];

const VARIADIC_NAME = '__VA_ARGS__';

const VARIADIC_ERROR = '"__VA_ARGS__" can only appear in the expansion of a variadic macro';

final class DefinitionError extends RuntimeException {}

final class Macro
{
    public int $expanded = 0, $tested = 0;

    public function __construct(
        public string $name,
        public ?array $parameters,
        public bool $variadic,
        public array $replacement,
        public array $position,
        public bool $mainFile,
    ) {}

    public function signature(): string
    {
        if ($this->parameters === null)
            return $this->name;
        $p = $this->parameters;
        if ($this->variadic)
            $p[count($p) - 1] = '...';
        return $this->name . '(' . implode(', ', $p) . ')';
    }

    public function identical(self $other): bool
    {
        if (
            $this->parameters !== $other->parameters
            || $this->variadic !== $other->variadic
            || count($this->replacement) !== count($other->replacement)
        )
            return false;
        foreach ($this->replacement as $i => $t)
            if (
                $t->spelling !== $other->replacement[$i]->spelling
                || $t->space !== $other->replacement[$i]->space
            )
                return false;
        return true;
    }
}

function checkName(array $tokens, string $directive): ?string
{
    if (!$tokens)
        return "no macro name given in #$directive directive";
    if ($tokens[0]->kind !== 'identifier')
        return 'macro names must be identifiers';
    $name = $tokens[0]->spelling;
    if ($name === 'defined')
        return '"defined" cannot be used as a macro name';
    if (in_array($name, BUILTINS, true))
        return (
            'cannot ' . ($directive === 'define' ? 'redefine' : 'undefine') . ' builtin macro "' . $name . '"'
        );
    return null;
}

function parseDefinition(array $tokens, array $position, bool $mainFile): Macro
{
    $error = checkName($tokens, 'define');
    if ($error !== null)
        throw new DefinitionError($error);
    $name = $tokens[0]->spelling;
    if ($name === VARIADIC_NAME)
        throw new DefinitionError(VARIADIC_ERROR);
    $parameters = null;
    $variadic = false;
    $i = 1;
    if (isset($tokens[1]) && $tokens[1]->spelling === '(' && !$tokens[1]->space) {
        $parameters = [];
        $i = 2;
        if (!isset($tokens[$i]))
            throw new DefinitionError("missing ')' in macro parameter list");
        if ($tokens[$i]->spelling === ')')
            ++$i;
        else
            while (true) {
                if (!isset($tokens[$i]))
                    throw new DefinitionError("missing ')' in macro parameter list");
                $t = $tokens[$i++];
                if ($t->spelling === '...') {
                    $parameters[] = VARIADIC_NAME;
                    $variadic = true;
                } elseif ($t->kind === 'identifier') {
                    if ($t->spelling === VARIADIC_NAME)
                        throw new DefinitionError(VARIADIC_ERROR);
                    if (in_array($t->spelling, $parameters, true))
                        throw new DefinitionError('duplicate macro parameter "' . $t->spelling . '"');
                    $parameters[] = $t->spelling;
                } else
                    throw new DefinitionError('expected parameter name, found "' . $t->spelling . '"');
                if (!isset($tokens[$i]))
                    throw new DefinitionError("missing ')' in macro parameter list");
                $s = $tokens[$i++]->spelling;
                if ($s === ')')
                    break;
                if ($variadic)
                    throw new DefinitionError('expected \')\' after "...", found "' . $s . '"');
                if ($s !== ',')
                    throw new DefinitionError('expected \',\' or \')\', found "' . $s . '"');
            }
    }
    $replacement = array_slice($tokens, $i);
    if ($replacement) {
        $replacement[0] = $replacement[0]->changed(space: false);
        if ($replacement[0]->spelling === '##' || $replacement[count($replacement) - 1]->spelling === '##')
            throw new DefinitionError("'##' cannot appear at either end of a macro expansion");
    }
    foreach ($replacement as $j => $t) {
        if ($t->kind === 'identifier' && $t->spelling === VARIADIC_NAME && !$variadic)
            throw new DefinitionError(VARIADIC_ERROR);
        if (
            $t->spelling === '#'
            && $parameters !== null
            && (
                !isset($replacement[$j + 1])
                || $replacement[$j + 1]->kind !== 'identifier'
                || !in_array($replacement[$j + 1]->spelling, $parameters, true)
            )
        )
            throw new DefinitionError("'#' is not followed by a macro parameter");
    }
    return new Macro($name, $parameters, $variadic, $replacement, $position, $mainFile);
}
