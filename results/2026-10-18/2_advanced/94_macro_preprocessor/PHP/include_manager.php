<?php

const STARTS = ['if', 'ifdef', 'ifndef'];

const BRANCHES = ['elif', 'elifdef', 'elifndef', 'else'];

function directiveName(array $tokens): ?string
{
    return count($tokens) >= 2 && $tokens[0]->spelling === '#' && $tokens[1]->kind === 'identifier'
        ? $tokens[1]->spelling
        : null;
}

function detectGuard(array $lines): ?string
{
    $nonempty = [];
    foreach ($lines as $l)
        if ($l->tokens)
            $nonempty[] = $l->tokens;
    if (!$nonempty)
        return null;
    $first = $nonempty[0];
    $last = $nonempty[count($nonempty) - 1];
    if (
        count($first) !== 3
        || directiveName($first) !== 'ifndef'
        || $first[2]->kind !== 'identifier'
        || count($last) !== 2
        || directiveName($last) !== 'endif'
    )
        return null;
    $depth = 0;
    foreach ($nonempty as $i => $tokens) {
        $name = directiveName($tokens);
        if (in_array($name, BRANCHES, true) && $depth === 1)
            return null;
        if (in_array($name, STARTS, true))
            ++$depth;
        elseif ($name === 'endif')
            --$depth;
        if ($depth === 0 && $i !== (count($nonempty) - 1))
            return null;
    }
    return $depth === 0 ? $first[2]->spelling : null;
}

final class SourceFile
{
    public array $lines;
    public ?string $guard;
    public int $physicalLines, $entered = 0, $skipped = 0, $outputLines = 0, $skippedLines = 0;
    public bool $once = false;

    public function __construct(
        public string $path,
        string $contents,
    ) {
        $this->physicalLines = substr_count($contents, "\n");
        $this->lines = lexSource($contents);
        $this->guard = detectGuard($this->lines);
    }
}

final class IncludeManager
{
    public array $files = [];

    public function search(string $name, bool $quoted): ?string
    {
        foreach ($quoted ? [$name, 'include/' . $name] : ['include/' . $name] as $path)
            if (is_file('input/' . $path))
                return $path;
        return null;
    }

    public function load(string $path): SourceFile
    {
        return $this->files[$path] ??= new SourceFile($path, file_get_contents('input/' . $path));
    }
}
