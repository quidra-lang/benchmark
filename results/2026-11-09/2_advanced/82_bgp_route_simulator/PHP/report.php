<?php

function pathText(array $path): string
{
    return implode(',', $path);
}

function attributeText(RouteAttributes $a): string
{
    return (
        'path '
        . pathText($a->path)
        . " origin {$a->origin} med {$a->med} comm "
        . communitiesText($a->communities)
    );
}

function routeText(?Route $route): string
{
    if ($route === null)
        return 'NONE';
    $communities = communitiesText($route->communities);
    if ($route->local())
        return "LOCAL origin {$route->origin} comm $communities";
    return (
        'next '
        . $route->neighbor()
        . ' path '
        . pathText($route->path)
        . " link {$route->link->name} lp {$route->localPref} med {$route->med} origin {$route->origin} comm $communities"
    );
}

function writeReports(array $reports): void
{
    if (!is_dir('output'))
        mkdir('output');
    foreach ($reports as $name => $lines)
        file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
}
