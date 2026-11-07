<?php

class Annotation
{
    public int $sample;
    public string $label;
    public ?Beat $beat = null;

    public function __construct(int $sample, string $label)
    {
        $this->sample = $sample;
        $this->label = $label;
    }
}

function readInput(): array
{
    $ecgLines = file('input/ecg.csv', FILE_IGNORE_NEW_LINES);
    $ecg = [];
    foreach (array_slice($ecgLines, 1) as $line) {
        [, $value] = explode(',', $line);
        $ecg[] = (int) $value;
    }
    $annotationLines = file('input/annotations.csv', FILE_IGNORE_NEW_LINES);
    $annotations = [];
    foreach (array_slice($annotationLines, 1) as $line) {
        [$sample, $label] = explode(',', $line);
        $annotations[] = new Annotation((int) $sample, $label);
    }
    $parameters = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$name, $value] = explode(' ', $line);
        $parameters[$name] = (int) $value;
    }
    return [$ecg, $annotations, $parameters];
}

function writeLines(string $name, array $lines): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
