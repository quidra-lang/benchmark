<?php

function readScene(string $path): object
{
    $scene = (object) ['materials' => [], 'objects' => [], 'lights' => [], 'fog' => null];
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }
        $tokens = explode(' ', $line);
        $kind = array_shift($tokens);
        if ($kind === 'material') {
            $name = array_shift($tokens);
            $v = array_map('intval', $tokens);
            $scene->materials[$name] = (object) ['name' => $name, 'color' => array_slice($v, 0, 3), 'kd' => $v[3], 'ks' => $v[4], 'exponent' => $v[5],
                'kr' => $v[6], 'kt' => $v[7], 'ior' => $v[8], 'checker' => null];
        } elseif ($kind === 'checker') {
            $name = array_shift($tokens);
            $v = array_map('intval', $tokens);
            $scene->materials[$name]->checker = (object) ['color' => array_slice($v, 0, 3), 'size' => $v[3]];
        } elseif (in_array($kind, ['sphere', 'plane', 'box'], true)) {
            $label = array_shift($tokens);
            $name = array_shift($tokens);
            $v = array_map('intval', $tokens);
            $object = (object) ['kind' => $kind, 'label' => $label, 'material' => $scene->materials[$name], 'number' => count($scene->objects) + 1];
            if ($kind === 'sphere') {
                $object->center = array_slice($v, 0, 3);
                $object->radius = $v[3];
            } elseif ($kind === 'plane') {
                $object->point = array_slice($v, 0, 3);
                $object->normal = vecNormalize(array_slice($v, 3, 3));
            } else {
                $object->lo = array_slice($v, 0, 3);
                $object->hi = array_slice($v, 3, 3);
            }
            $scene->objects[] = $object;
        } elseif (in_array($kind, ['point', 'spot', 'sun', 'area'], true)) {
            $v = array_map('intval', $tokens);
            $light = (object) ['kind' => $kind, 'number' => count($scene->lights) + 1, 'samples' => 1];
            if ($kind === 'sun') {
                $light->direction = vecNormalize(vecNeg(array_slice($v, 0, 3)));
                $light->intensity = $v[3];
            } else {
                $light->position = array_slice($v, 0, 3);
                if ($kind === 'point') {
                    $light->intensity = $v[3];
                } elseif ($kind === 'spot') {
                    $light->direction = vecNormalize(array_slice($v, 3, 3));
                    $light->outer = $v[6];
                    $light->inner = $v[7];
                    $light->intensity = $v[8];
                } else {
                    $light->u = array_slice($v, 3, 3);
                    $light->v = array_slice($v, 6, 3);
                    $light->divisions = $v[9];
                    $light->samples = $v[9] * $v[9];
                    $light->intensity = $v[10];
                }
            }
            $scene->lights[] = $light;
        } else {
            $v = array_map('intval', $tokens);
            if ($kind === 'fog') {
                $scene->fog = (object) ['color' => array_slice($v, 0, 3), 'start' => $v[3], 'end' => $v[4]];
            } else {
                $scene->$kind = $kind === 'ambient' ? $v[0] : $v;
            }
        }
    }
    return $scene;
}
