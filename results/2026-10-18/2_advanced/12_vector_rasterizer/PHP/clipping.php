<?php
declare(strict_types=1);

function regionCode(array $p, array $clip): int { return ($p[0] < $clip[0] ? 1 : 0) | ($p[0] > $clip[2] ? 2 : 0) | ($p[1] < $clip[1] ? 4 : 0) | ($p[1] > $clip[3] ? 8 : 0); }
function clipSegment(array $start, array $end, array $clip): ?array {
    [$x0,$y0,$x1,$y1] = $clip;
    while (true) { $sc = regionCode($start,$clip); $ec = regionCode($end,$clip); if (($sc | $ec) === 0) return [$start,$end]; if (($sc & $ec) !== 0) return null; $code = $sc ?: $ec; [$ax,$ay] = $sc ? $start : $end; [$bx,$by] = $sc ? $end : $start;
        if ($code & 4) $point = [$ax + roundRatio(($bx-$ax)*($y0-$ay),$by-$ay),$y0];
        elseif ($code & 8) $point = [$ax + roundRatio(($bx-$ax)*($y1-$ay),$by-$ay),$y1];
        elseif ($code & 2) $point = [$x1,$ay + roundRatio(($by-$ay)*($x1-$ax),$bx-$ax)];
        else $point = [$x0,$ay + roundRatio(($by-$ay)*($x0-$ax),$bx-$ax)];
        if ($sc) $start = $point; else $end = $point;
    }
}
function boundaryInside(array $point, int $axis, int $limit, bool $minimum): bool { return $minimum ? $point[$axis] >= $limit : $point[$axis] <= $limit; }
function boundaryIntersection(array $start, array $end, int $axis, int $limit): array {
    [$sx,$sy] = $start; [$ex,$ey] = $end; return $axis === 0 ? [$limit,$sy + roundRatio(($limit-$sx)*($ey-$sy),$ex-$sx)] : [$sx + roundRatio(($limit-$sy)*($ex-$sx),$ey-$sy),$limit];
}
function clipPolygon(array $vertices, array $clip): array {
    foreach ([[0,$clip[0],true],[0,$clip[2]+1,false],[1,$clip[1],true],[1,$clip[3]+1,false]] as [$axis,$limit,$minimum]) {
        $output = []; $n = count($vertices); foreach ($vertices as $i => $end) { $start = $vertices[($i+$n-1)%$n]; $si = boundaryInside($start,$axis,$limit,$minimum); $ei = boundaryInside($end,$axis,$limit,$minimum); if ($ei) { if (!$si) $output[] = boundaryIntersection($start,$end,$axis,$limit); $output[] = $end; } elseif ($si) $output[] = boundaryIntersection($start,$end,$axis,$limit); } $vertices = $output;
    } return $vertices;
}
