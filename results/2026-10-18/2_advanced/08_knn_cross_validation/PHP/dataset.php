<?php
final class DataRow {
    public function __construct(public string $id, public array $values, public ?string $label, public ?float $target) {}
}
final class Settings {
    public array $scalings, $kValues, $metrics, $weightings, $curve, $bins;
    public int $folds, $editK, $top;
    public function __construct(string $path) {
        $entries = [];
        foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
            $parts = explode(' ', $line); $entries[array_shift($parts)] = $parts;
        }
        $this->scalings = $entries['SCALINGS']; $this->metrics = $entries['METRICS']; $this->weightings = $entries['WEIGHTINGS'];
        $this->kValues = array_map('intval', $entries['K_VALUES']); $this->curve = array_map('intval', $entries['CURVE']); $this->bins = array_map('floatval', $entries['BINS']);
        $this->folds = (int)$entries['FOLDS'][0]; $this->editK = (int)$entries['EDIT_K'][0]; $this->top = (int)$entries['TOP'][0];
    }
}
function readRows(string $name): array {
    $lines = file('input/' . $name, FILE_IGNORE_NEW_LINES); $header = explode(',', array_shift($lines)); $rows = [];
    foreach ($lines as $line) {
        $parts = explode(',', $line); $target = array_pop($parts); $label = array_pop($parts); $id = array_shift($parts);
        $rows[] = new DataRow($id, array_map('floatval', $parts), $label === '' ? null : $label, $target === '' ? null : (float)$target);
    }
    return [array_slice($header, 1, -2), $rows];
}
