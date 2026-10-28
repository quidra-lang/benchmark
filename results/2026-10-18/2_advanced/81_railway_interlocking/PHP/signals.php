<?php

function signalAspects(Interlocking $interlocking, callable $occupied): array
{
    $layout = $interlocking->layout;
    $cleared = [];
    foreach ($layout->signals as $signal) {
        $cleared[$signal->name] = null;
        foreach ($interlocking->routes as $route) {
            if ($route->start !== $signal->name || $route->state !== 'LOCKED')
                continue;
            $detected = true;
            foreach ($route->requirements as [$name, $position]) {
                $p = $layout->points[$name];
                if ($p->moving || $p->failed || $p->position !== $position) {
                    $detected = false;
                    break;
                }
            }
            if ($detected && !array_any([...$route->sections, ...$route->overlap], $occupied)) {
                $cleared[$signal->name] = $route;
                break;
            }
        }
    }
    $result = [];
    foreach ($layout->signals as $signal) {
        $route = $cleared[$signal->name];
        if ($route === null)
            $aspect = 'RED';
        elseif (isset($layout->signals[$route->finish]))
            $aspect = $cleared[$route->finish] !== null ? 'GREEN' : 'YELLOW';
        else
            $aspect = isset($layout->buffers[$route->finish]) ? 'YELLOW' : 'GREEN';
        $result[] = [$signal, $aspect];
    }
    return $result;
}
