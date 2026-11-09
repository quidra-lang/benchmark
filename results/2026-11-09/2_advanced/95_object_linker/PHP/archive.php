<?php
declare(strict_types=1);

require_once __DIR__ . '/object_parser.php';

function read_archive(string $filename): object
{
    $lines = read_lines('input/' . $filename);
    $members = [];
    $index = 0;
    while ($index < count($lines)) {
        $words = explode(' ', $lines[$index]);
        [$object, $index] = parse_object($lines, $index + 1, "$filename({$words[1]})");
        $members[] = (object)['object' => $object, 'exports' => array_slice($words, 2), 'loaded' => false];
    }
    return (object)['name' => $filename, 'members' => $members];
}

function scan_archive(object $archive, callable $is_undefined, callable $extract): int
{
    $total = 0;
    do {
        $count = 0;
        foreach ($archive->members as $member) {
            if ($member->loaded) {
                continue;
            }
            foreach ($member->exports as $name) {
                if ($is_undefined($name)) {
                    $member->loaded = true;
                    $extract($member->object, $name);
                    ++$count;
                    ++$total;
                    break;
                }
            }
        }
    } while ($count !== 0);
    return $total;
}
