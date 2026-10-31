<?php

function validName(string $s): bool
{
    return preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/D', $s) === 1;
}

function validFilename(string $s): bool
{
    return preg_match('/^[A-Za-z0-9_-][A-Za-z0-9._-]*$/D', $s) === 1;
}

final class Operand
{
    public int $records = 0;

    public function __construct(
        public string $kind,
        public string $name,
        public ?string $value = null,
    ) {}
}

function parseArguments(array $lines): array
{
    $options = $operands = [];
    foreach ($lines as $line) {
        if (str_starts_with($line, '-F '))
            $options[] = ['FS', substr($line, 3)];
        elseif (str_starts_with($line, '-v '))
            $options[] = explode('=', substr($line, 3), 2);
        else {
            $equal = strpos($line, '=');
            if ($equal !== false && validName(substr($line, 0, $equal)))
                $operands[] = new Operand('assignment', substr($line, 0, $equal), substr($line, $equal + 1));
            else
                $operands[] = new Operand('file', $line);
        }
    }
    return [$options, $operands];
}

function readRecords(string $name): array
{
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

final class OutputStream
{
    public string $content = '';
    public bool $open = false;
    public int $writes = 0;

    public function append(string $text): void
    {
        $this->content .= $text;
        ++$this->writes;
    }
}

final class GetlineInput
{
    public bool $open = false, $everOpened = false;
    public array $lines = [];
    public int $position = 0, $reads = 0;
}

final class Streams
{
    public OutputStream $stdout;
    public array $outputs = [], $inputs = [];

    public function __construct()
    {
        $this->stdout = new OutputStream();
    }

    public function write(
        string $text,
        ?string $name = null,
        ?string $mode = null,
        ?array $position = null,
    ): void {
        if ($name === null) {
            $this->stdout->append($text);
            return;
        }
        if (!validFilename($name) || in_array($name, ['stdout.txt', 'stats.txt'], true))
            throw new RuntimeIssue($position, 'invalid output file name');
        $o = $this->outputs[$name] ??= new OutputStream();
        if (!$o->open) {
            $o->open = true;
            if ($mode === '>')
                $o->content = '';
        }
        $o->append($text);
    }

    public function getline(string $name): array
    {
        $s = $this->inputs[$name] ??= new GetlineInput();
        if (!$s->open) {
            if (!validFilename($name) || !is_file('input/' . $name))
                return [-1, null];
            $s->lines = readRecords($name);
            $s->position = 0;
            $s->open = $s->everOpened = true;
        }
        if ($s->position === count($s->lines))
            return [0, null];
        $line = $s->lines[$s->position++];
        ++$s->reads;
        return [1, $line];
    }

    public function close(string $name): int
    {
        $closed = false;
        foreach ([$this->outputs, $this->inputs] as $table)
            if (isset($table[$name]) && $table[$name]->open) {
                $table[$name]->open = false;
                $closed = true;
            }
        return $closed ? 0 : -1;
    }

    public function save(): void
    {
        if (!is_dir('output'))
            mkdir('output');
        file_put_contents('output/stdout.txt', $this->stdout->content);
        foreach ($this->outputs as $name => $s)
            file_put_contents('output/' . $name, $s->content);
    }
}
