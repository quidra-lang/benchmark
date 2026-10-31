<?php

function slab(array $lo, array $hi, array $origin, array $direction): ?object
{
    $near = PHP_INT_MIN;
    $far = PHP_INT_MAX;
    $nearAxis = -1;
    $farAxis = -1;
    for ($axis = 0; $axis < 3; $axis++) {
        if ($direction[$axis] === 0) {
            if ($origin[$axis] < $lo[$axis] || $origin[$axis] > $hi[$axis]) {
                return null;
            }
            continue;
        }
        $a = floorDiv(($lo[$axis] - $origin[$axis]) * S, $direction[$axis]);
        $b = floorDiv(($hi[$axis] - $origin[$axis]) * S, $direction[$axis]);
        $entry = min($a, $b);
        $exit = max($a, $b);
        if ($entry > $near) {
            $near = $entry;
            $nearAxis = $axis;
        }
        if ($exit < $far) {
            $far = $exit;
            $farAxis = $axis;
        }
    }
    return $near > $far ? null : (object) compact('near', 'far', 'nearAxis', 'farAxis');
}

function candidate(object $object, array $origin, array $direction, int $epsilon): ?object
{
    if ($object->kind === 'sphere') {
        $oc = vecSub($origin, $object->center);
        $b = vecDot($oc, $direction);
        $center = floorDiv(-$b * S, vecDot($direction, $direction));
        $h = vecAdd($oc, vecScale($direction, $center));
        $q = floorDiv($object->radius * $object->radius, S) - vecDot($h, $h);
        if ($q < 0) {
            return null;
        }
        $half = floorDiv(integerSqrt($q * S) * S, vecLength($direction));
        $first = $center - $half;
        $second = $center + $half;
        if ($first > $epsilon) {
            return (object) ['t' => $first];
        }
        return $second > $epsilon ? (object) ['t' => $second] : null;
    }
    if ($object->kind === 'plane') {
        $denominator = vecDot($direction, $object->normal);
        if ($denominator === 0) {
            return null;
        }
        $t = floorDiv(vecDot(vecSub($object->point, $origin), $object->normal) * S, $denominator);
        return $t > $epsilon ? (object) ['t' => $t] : null;
    }
    $hit = slab($object->lo, $object->hi, $origin, $direction);
    if ($hit === null) {
        return null;
    }
    if ($hit->near > $epsilon) {
        return (object) ['t' => $hit->near, 'entering' => true, 'axis' => $hit->nearAxis];
    }
    return $hit->far > $epsilon ? (object) ['t' => $hit->far, 'entering' => false, 'axis' => $hit->farAxis] : null;
}

function outwardNormal(object $object, array $point, array $direction, object $hit): array
{
    if ($object->kind === 'sphere') {
        return vecNormalize(vecSub($point, $object->center));
    }
    if ($object->kind === 'plane') {
        return $object->normal;
    }
    $normal = [0, 0, 0];
    $sign = $direction[$hit->axis] > 0 ? 1 : -1;
    $normal[$hit->axis] = ($hit->entering ? -$sign : $sign) * S;
    return $normal;
}

function bounds(object $object, int $margin): ?object
{
    if ($object->kind === 'plane') {
        return null;
    }
    if ($object->kind === 'sphere') {
        return (object) ['lo' => array_map(fn($value) => $value - $object->radius - $margin, $object->center),
            'hi' => array_map(fn($value) => $value + $object->radius + $margin, $object->center)];
    }
    return (object) ['lo' => array_map(fn($value) => $value - $margin, $object->lo),
        'hi' => array_map(fn($value) => $value + $margin, $object->hi)];
}
