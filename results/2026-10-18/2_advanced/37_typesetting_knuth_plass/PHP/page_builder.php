<?php

function preparePages(array $blocks, array $parameters): object
{
    $lines = [];
    $breaks = [];
    foreach ($blocks as $index => $block) {
        if ($index > 0) {
            $previous = $blocks[$index - 1];
            $end = count($lines);
            if (!$previous->list || !$block->list) {
                $lines[] = (object) ['text' => '', 'footnotes' => [], 'marks' => []];
            }
            if ($block->pageBreak || $previous->type !== 'heading') {
                $breaks[] = (object) ['end' => $end, 'next' => count($lines), 'forced' => $block->pageBreak];
            }
        }
        $start = count($lines);
        foreach ($block->lines as $line) $lines[] = $line;
        if ($block->type === 'flow') {
            for ($count = 1; $count < count($block->lines); $count++) {
                if ($count >= $parameters['orphan_lines'] && count($block->lines) - $count >= $parameters['widow_lines']) {
                    $breaks[] = (object) ['end' => $start + $count, 'next' => $start + $count, 'forced' => false];
                }
            }
        }
    }
    if ($lines) $breaks[] = (object) ['end' => count($lines), 'next' => count($lines), 'forced' => true];
    return (object) compact('lines', 'breaks');
}

function choosePages(array $blocks, int $height, array $parameters, array $footnotes): array
{
    $prepared = preparePages($blocks, $parameters);
    $pages = [];
    $start = 0;
    $firstBreak = 0;
    while ($start < count($prepared->lines)) {
        $notes = [];
        $noteHeight = 0;
        $examined = $start;
        $best = null;
        for ($index = $firstBreak; $index < count($prepared->breaks); $index++) {
            $candidate = $prepared->breaks[$index];
            while ($examined < $candidate->end) {
                foreach ($prepared->lines[$examined]->footnotes as $number) {
                    if (!isset($notes[$number])) {
                        $notes[$number] = true;
                        $noteHeight += count($footnotes[$number]->lines);
                    }
                }
                $examined++;
            }
            $used = $candidate->end - $start + ($notes ? 1 + $noteHeight : 0);
            if ($used <= $height) {
                $numbers = array_keys($notes);
                sort($numbers, SORT_NUMERIC);
                $best = (object) ['candidate' => $candidate, 'index' => $index, 'height' => $used, 'notes' => $numbers];
            }
            if ($candidate->forced) break;
        }
        $candidate = $best->candidate;
        $pages[] = (object) ['content' => array_slice($prepared->lines, $start, $candidate->end - $start), 'footnotes' => $best->notes,
            'height' => $best->height, 'endsByForce' => $candidate->forced, 'blank' => false];
        $start = $candidate->next;
        $firstBreak = $best->index + 1;
    }
    return $pages;
}
