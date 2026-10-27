<?php

function readMaterials(): array
{
    $result = [];
    foreach (file('input/materials.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$code, $name, $k, $rho, $cp] = explode(' ', $line);
        $result[] = (object) ['code' => $code, 'name' => $name, 'k' => (float) $k, 'rho' => (float) $rho, 'cp' => (float) $cp, 'cells' => []];
    }
    return $result;
}

function capacity(object $material, float $dx, float $depth): float
{
    return $material->rho * $material->cp * $dx * $dx * $depth;
}

function interior(float $kp, float $kq, float $depth): float
{
    return 2 * $kp * $kq / ($kp + $kq) * $depth;
}

function fixedConductance(float $k, float $depth): float
{
    return 2 * $k * $depth;
}

function convective(float $k, float $h, float $dx, float $depth): float
{
    return 1 / (1 / ($h * $dx * $depth) + 1 / (2 * $k * $depth));
}
