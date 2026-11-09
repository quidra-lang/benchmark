<?php

require_once __DIR__ . '/kernels.php';

class Trainer
{
    public $points, $labels, $Q, $C, $kernel, $params, $alpha, $errors, $b;
    public $full = 0, $nonbound = 0, $examined = 0, $steps = 0;
    public $choice = ['heuristic' => 0, 'nonbound_loop' => 0, 'full_loop' => 0];
    public $clipping = ['none' => 0, 'lower' => 0, 'upper' => 0];
    public $records = [], $converged = false;

    public function __construct($points, $labels, $Q, $C, $kernel, $params)
    {
        $this->points = $points; $this->labels = $labels; $this->Q = $Q;
        $this->C = $C; $this->kernel = $kernel; $this->params = $params;
        $this->alpha = array_fill(0, count($points), 0.0);
        $this->errors = [];
        foreach ($labels as $label) $this->errors[] = -$label;
        $this->b = 0.0;
    }

    public function non_bound($a) { return $a > 0 && $a < $this->C; }

    public function snap($a)
    {
        return $a < 0.00000001 ? 0.0 : ($a > $this->C - 0.00000001 ? $this->C : $a);
    }

    public function take($i1, $i2)
    {
        if ($i1 === $i2) return false;
        $a1Old = $this->alpha[$i1]; $a2Old = $this->alpha[$i2];
        $y1 = $this->labels[$i1]; $y2 = $this->labels[$i2];
        $e1 = $this->errors[$i1]; $e2 = $this->errors[$i2]; $C = $this->C;
        $lo = $y1 !== $y2 ? max(0.0, $a2Old - $a1Old) : max(0.0, $a2Old + $a1Old - $C);
        $hi = $y1 !== $y2 ? min($C, $C + $a2Old - $a1Old) : min($C, $a2Old + $a1Old);
        if ($lo == $hi) return false;
        $k11 = $this->Q[$i1][$i1]; $k12 = $this->Q[$i1][$i2]; $k22 = $this->Q[$i2][$i2];
        $eta = $k11 + $k22 - 2 * $k12;
        if ($eta <= 0) return false;
        $a2 = $a2Old + $y2 * ($e1 - $e2) / $eta;
        $clipping = 'none';
        if ($a2 < $lo) { $a2 = $lo; $clipping = 'lower'; }
        elseif ($a2 > $hi) { $a2 = $hi; $clipping = 'upper'; }
        $a2 = $this->snap($a2);
        if (abs($a2 - $a2Old) < $this->params['eps'] * ($a2 + $a2Old + $this->params['eps'])) return false;
        $a1 = $this->snap($a1Old + $y1 * $y2 * ($a2Old - $a2));
        $t1 = $y1 * ($a1 - $a1Old); $t2 = $y2 * ($a2 - $a2Old);
        $b1 = $e1 + $t1 * $k11 + $t2 * $k12 + $this->b;
        $b2 = $e2 + $t1 * $k12 + $t2 * $k22 + $this->b;
        $bNew = $this->non_bound($a1) ? $b1 : ($this->non_bound($a2) ? $b2 : ($b1 + $b2) / 2);
        $delta = $bNew - $this->b;
        for ($i = 0; $i < count($this->points); $i++) {
            $this->errors[$i] = $this->errors[$i] + ($t1 * $this->Q[$i1][$i] + $t2 * $this->Q[$i2][$i] - $delta);
        }
        if ($this->non_bound($a1)) $this->errors[$i1] = 0.0;
        if ($this->non_bound($a2)) $this->errors[$i2] = 0.0;
        $this->alpha[$i1] = $a1; $this->alpha[$i2] = $a2; $this->b = $bNew;
        $this->steps++; $this->clipping[$clipping]++;
        return true;
    }

    public function examine($i2)
    {
        $this->examined++;
        $r2 = $this->errors[$i2] * $this->labels[$i2]; $a2 = $this->alpha[$i2];
        if (!(($r2 < -$this->params['tau'] && $a2 < $this->C) || ($r2 > $this->params['tau'] && $a2 > 0))) return 0;
        $partner = -1; $largest = -1.0;
        for ($i = 0; $i < count($this->points); $i++) if ($i !== $i2 && $this->non_bound($this->alpha[$i])) {
            $difference = abs($this->errors[$i] - $this->errors[$i2]);
            if ($difference > $largest) { $partner = $i; $largest = $difference; }
        }
        if ($partner >= 0 && $this->take($partner, $i2)) { $this->choice['heuristic']++; return 1; }
        for ($i = 0; $i < count($this->points); $i++) {
            if ($this->non_bound($this->alpha[$i]) && $this->take($i, $i2)) { $this->choice['nonbound_loop']++; return 1; }
        }
        for ($i = 0; $i < count($this->points); $i++) {
            if ($this->take($i, $i2)) { $this->choice['full_loop']++; return 1; }
        }
        return 0;
    }

    public function run()
    {
        $all = true;
        while (true) {
            $before = $this->examined;
            $changed = 0;
            for ($i = 0; $i < count($this->points); $i++) if ($all || $this->non_bound($this->alpha[$i])) $changed += $this->examine($i);
            if ($all) $this->full++; else $this->nonbound++;
            $record = ['number' => $this->full + $this->nonbound, 'kind' => $all ? 'full' : 'nonbound',
                'examined' => $this->examined - $before, 'changed' => $changed];
            if ($all) $record['alpha'] = $this->alpha;
            $this->records[] = $record;
            if ($all && $changed === 0) { $this->converged = true; break; }
            if ($this->full + $this->nonbound === $this->params['maxPasses']) break;
            if ($all) $all = false; elseif ($changed === 0) $all = true;
        }
        return $this;
    }
}

function smo_train($points, $labels, $Q, $C, $kernel, $params)
{
    return (new Trainer($points, $labels, $Q, $C, $kernel, $params))->run();
}

function decision($model, $point)
{
    $sum = 0.0;
    foreach ($model->alpha as $j => $alpha) if ($alpha > 0) $sum += $alpha * $model->labels[$j] * kernel_value($model->kernel, $model->points[$j], $point);
    return $sum - $model->b;
}

function training_sums($model, $alpha = null)
{
    $alpha = $alpha ?? $model->alpha;
    $result = [];
    foreach ($model->points as $i => $point) {
        $sum = 0.0;
        foreach ($alpha as $j => $value) if ($value > 0) $sum += $value * $model->labels[$j] * $model->Q[$i][$j];
        $result[] = $sum;
    }
    return $result;
}
