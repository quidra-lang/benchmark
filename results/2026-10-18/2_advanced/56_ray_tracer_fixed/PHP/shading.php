<?php

function baseColor(object $material, array $point): array
{
    if ($material->checker === null) {
        return $material->color;
    }
    $parity = 0;
    foreach ($point as $value) {
        $parity += floorDiv($value, $material->checker->size);
    }
    return $parity % 2 !== 0 ? $material->checker->color : $material->color;
}

function components(object $material, array $normal, array $light, array $view, int $ndl, int $intensity): object
{
    $diffuse = mul(mul($material->kd, $ndl), $intensity);
    $reflected = vecSub(vecScale($normal, 2 * $ndl), $light);
    $rv = vecDot($reflected, $view);
    $specular = 0;
    if ($rv > 0) {
        $power = S;
        for ($i = 0; $i < $material->exponent; $i++) {
            $power = mul($power, $rv);
        }
        $specular = mul(mul($material->ks, $power), $intensity);
    }
    return (object) compact('diffuse', 'specular');
}

function reflection(array $direction, array $normal): array
{
    return vecNormalize(vecSub($direction, vecScale($normal, 2 * vecDot($direction, $normal))));
}

function refraction(array $direction, array $normal, bool $front, object $material): object
{
    $wr = $material->kr;
    $wt = $material->kt;
    $transmitted = null;
    $totalInternal = false;
    if ($material->kt > 0) {
        $eta = $front ? floorDiv(S * S, $material->ior) : $material->ior;
        $cn = -vecDot($direction, $normal);
        $discriminant = S * S - floorDiv(mul($eta, $eta) * (S * S - $cn * $cn), S);
        if ($discriminant < 0) {
            $wr += $wt;
            $wt = 0;
            $totalInternal = true;
        } else {
            $transmitted = vecNormalize(vecAdd(vecScale($direction, $eta), vecScale($normal, mul($eta, $cn) - integerSqrt($discriminant))));
            $r0 = floorDiv(($material->ior - S) * S, $material->ior + S);
            $R0 = mul($r0, $r0);
            $x = S - min($cn, S);
            $power = S;
            for ($i = 0; $i < 5; $i++) {
                $power = mul($power, $x);
            }
            $fresnel = $R0 + mul(S - $R0, $power);
            $extra = mul($material->kt, $fresnel);
            $wr += $extra;
            $wt -= $extra;
        }
    }
    return (object) compact('wr', 'wt', 'transmitted', 'totalInternal');
}

function mix(array $colors, array $weights): array
{
    $result = [0, 0, 0];
    for ($axis = 0; $axis < 3; $axis++) {
        foreach ($colors as $index => $color) {
            $result[$axis] += mul($color[$axis], $weights[$index]);
        }
    }
    return $result;
}
