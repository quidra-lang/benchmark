<?php
final class Scaling {
    public array $centers = [], $scales = [];
    public function __construct(array $rows, string $method) {
        for ($j = 0; $j < count($rows[0]->values); $j++) {
            if ($method === 'standard') {
                $sum = 0.0; foreach ($rows as $row) $sum += $row->values[$j]; $center = $sum / count($rows);
                $squares = 0.0; foreach ($rows as $row) { $difference = $row->values[$j] - $center; $squares += $difference * $difference; }
                $scale = count($rows) === 1 ? 0.0 : sqrt($squares / (count($rows) - 1));
            } else {
                $center = $rows[0]->values[$j]; $highest = $center;
                foreach ($rows as $row) { $center = min($center, $row->values[$j]); $highest = max($highest, $row->values[$j]); }
                $scale = $highest - $center;
            }
            $this->centers[] = $center; $this->scales[] = $scale;
        }
    }
    public function transform(array $values, array $features): array {
        $vector = []; foreach ($features as $j) $vector[] = $this->scales[$j] > 0 ? ($values[$j] - $this->centers[$j]) / $this->scales[$j] : 0.0;
        return $vector;
    }
}
