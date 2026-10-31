<?php

final class Settings
{
    public string $distance;
    public string $standardize;
    public array $linkages;
    public array $cutHeights;
    public array $cutCounts;
    public int $inconsistencyDepth;
    public string $inconsistencyDepthText;
    public int $inconsistencyCount;
    public int $gapMaxK;
    public int $listSize;
    public int $width;
    public string $compareLinkage;
    public int $replicates;
    public int $percent;
    public int $seed;
    public int $refineIterations;

    public function __construct(array $rows)
    {
        $this->distance = $rows['DISTANCE'][0];
        $this->standardize = $rows['STANDARDIZE'][0];
        $this->linkages = $rows['LINKAGES'];
        $this->cutHeights = array_map('floatval', $rows['CUT_HEIGHTS']);
        $this->cutCounts = array_map('intval', $rows['CUT_K']);
        $this->inconsistencyDepthText = $rows['INCONSISTENCY'][0];
        $this->inconsistencyDepth = strlen($this->inconsistencyDepthText) > 3 ? 120 : min(120, (int)$this->inconsistencyDepthText);
        $this->inconsistencyCount = (int)$rows['INCONSISTENCY'][1];
        $this->gapMaxK = (int)$rows['GAP_MAX_K'][0];
        $this->listSize = (int)$rows['LIST_SIZE'][0];
        $this->width = (int)$rows['DENDROGRAM_WIDTH'][0];
        $this->compareLinkage = $rows['COMPARE_LINKAGE'][0];
        [$this->replicates, $this->percent, $this->seed] = array_map('intval', $rows['SUBSAMPLES']);
        $this->refineIterations = (int)$rows['REFINE_ITERATIONS'][0];
    }
}

function readLines(string $path): array
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function readObservations(string $path): array
{
    $lines = readLines($path);
    $names = array_slice(explode(',', $lines[0]), 2);
    $observations = [];
    foreach (array_slice($lines, 1) as $line) {
        $fields = explode(',', $line);
        $observations[] = ['ident' => $fields[0], 'label' => $fields[1], 'values' => array_map('floatval', array_slice($fields, 2))];
    }
    return [$names, $observations];
}

function readSettings(string $path): Settings
{
    $entries = [];
    foreach (readLines($path) as $line) {
        $fields = explode(' ', $line);
        $entries[array_shift($fields)] = $fields;
    }
    return new Settings($entries);
}

function writeLines(string $path, array $lines): void
{
    file_put_contents($path, $lines === [] ? '' : implode("\n", $lines) . "\n");
}
