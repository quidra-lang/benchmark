<?php
declare(strict_types=1);

function read_lines(string $filename): array
{
    return file($filename, FILE_IGNORE_NEW_LINES);
}

function belongs(string $name, string $prefix): bool
{
    return $name === $prefix || str_starts_with($name, $prefix . '.');
}

function is_nobits(string $name): bool
{
    return belongs($name, '.bss');
}

final class Section
{
    public string $kind = 'section';
    public bool $nobits, $string;
    public string $data;
    public array $relocations = [], $merged_positions = [];
    public ?string $discarded = null;
    public ?OutputSection $output = null;
    public ?object $merged = null;
    public bool $live = false;
    public int $address = 0;

    public function __construct(public ObjectFile $object, public string $name,
        public int $alignment, public int $size)
    {
        $this->nobits = is_nobits($name);
        $this->string = belongs($name, '.rodata.str');
        $this->data = str_repeat("\0", $this->nobits ? 0 : $size);
    }
}

final class SymbolEntry
{
    public function __construct(public ObjectFile $object, public string $name, public string $binding,
        public string $kind, public ?Section $section = null, public int $offset = 0,
        public int $size = 0, public int $alignment = 1) {}
}

final readonly class Relocation
{
    public function __construct(public Section $section, public int $offset, public string $type,
        public SymbolEntry $symbol, public int $addend) {}
}

final class ObjectFile
{
    public array $sections = [], $section_names = [], $symbols = [], $symbol_names = [];
    public array $comdats = [], $relocations = [];
    public int $rank = -1;

    public function __construct(public string $name) {}
}

function parse_object(array $lines, int $start, string $name): array
{
    $object = new ObjectFile($name);
    $current = null;
    $data_offset = 0;
    for ($index = $start; $index < count($lines); ++$index) {
        $words = explode(' ', $lines[$index]);
        switch ($words[0]) {
            case 'end':
                return [$object, $index + 1];
            case 'section':
                $current = new Section($object, $words[1], (int)$words[2], (int)$words[3]);
                $object->sections[] = $current;
                $object->section_names[$current->name] = $current;
                $data_offset = 0;
                break;
            case 'data':
                $bytes = hex2bin($words[1]);
                $current->data = substr_replace($current->data, $bytes, $data_offset, strlen($bytes));
                $data_offset += strlen($bytes);
                break;
            case 'comdat':
                $sections = array_map(static fn(string $section): Section => $object->section_names[$section], array_slice($words, 2));
                $object->comdats[] = (object)['signature' => $words[1], 'sections' => $sections];
                break;
            case 'symbol':
                if ($words[3] === 'undef') {
                    $symbol = new SymbolEntry($object, $words[1], $words[2], 'undef');
                } elseif ($words[3] === 'common') {
                    $symbol = new SymbolEntry($object, $words[1], $words[2], 'common', null, 0, (int)$words[4], (int)$words[5]);
                } else {
                    $symbol = new SymbolEntry($object, $words[1], $words[2], 'defined', $object->section_names[$words[3]], (int)$words[4]);
                }
                $object->symbols[] = $symbol;
                $object->symbol_names[$symbol->name] = $symbol;
                break;
            case 'reloc':
                $section = $object->section_names[$words[1]];
                $relocation = new Relocation($section, (int)$words[2], $words[3], $object->symbol_names[$words[4]], (int)$words[5]);
                $section->relocations[] = $relocation;
                $object->relocations[] = $relocation;
                break;
        }
    }
    return [$object, count($lines)];
}

function read_object(string $filename): ObjectFile
{
    return parse_object(read_lines('input/' . $filename), 0, $filename)[0];
}
