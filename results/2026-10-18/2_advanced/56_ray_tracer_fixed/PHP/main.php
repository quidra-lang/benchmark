<?php

require_once __DIR__ . '/fixed_point.php';
require_once __DIR__ . '/vector3.php';
require_once __DIR__ . '/scene.php';
require_once __DIR__ . '/intersect.php';
require_once __DIR__ . '/shading.php';

const KINDS = ['primary', 'reflection', 'refraction', 'shadow'];

function triple(array $values): string
{
    return implode(' ', $values);
}

function readLines(string $path): array
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function writeLines(string $name, array $lines): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    file_put_contents('output/' . $name, count($lines) ? implode("\n", $lines) . "\n" : '');
}

function unionBox(array $objects): object
{
    $lo = $objects[0]->bounds->lo;
    $hi = $objects[0]->bounds->hi;
    foreach ($objects as $object) {
        for ($axis = 0; $axis < 3; $axis++) {
            $lo[$axis] = min($lo[$axis], $object->bounds->lo[$axis]);
            $hi[$axis] = max($hi[$axis], $object->bounds->hi[$axis]);
        }
    }
    return (object) compact('lo', 'hi');
}

function area(array $objects): int
{
    $box = unionBox($objects);
    [$dx, $dy, $dz] = vecSub($box->hi, $box->lo);
    return $dx * $dy + $dy * $dz + $dz * $dx;
}

function buildBVH(array $objects, int $depth, array &$nodes): object
{
    $box = unionBox($objects);
    $node = (object) ['lo' => $box->lo, 'hi' => $box->hi, 'depth' => $depth, 'visits' => 0, 'objects' => null, 'left' => null, 'right' => null];
    $nodes[] = $node;
    if (count($objects) <= 2) {
        usort($objects, fn($a, $b) => $a->number <=> $b->number);
        $node->objects = $objects;
        foreach ($objects as $object) {
            $object->leaf = $node;
        }
        return $node;
    }
    $best = null;
    for ($axis = 0; $axis < 3; $axis++) {
        $ordered = $objects;
        usort($ordered, fn($a, $b) => (floorDiv($a->bounds->lo[$axis] + $a->bounds->hi[$axis], 2)
            <=> floorDiv($b->bounds->lo[$axis] + $b->bounds->hi[$axis], 2)) ?: ($a->number <=> $b->number));
        for ($i = 1; $i < count($ordered); $i++) {
            $left = array_slice($ordered, 0, $i);
            $right = array_slice($ordered, $i);
            $cost = area($left) * count($left) + area($right) * count($right);
            if ($best === null || $cost < $best->cost) {
                $best = (object) compact('cost', 'left', 'right');
            }
        }
    }
    $node->left = buildBVH($best->left, $depth + 1, $nodes);
    $node->right = buildBVH($best->right, $depth + 1, $nodes);
    return $node;
}

function readSettings(): object
{
    $values = [];
    foreach (readLines('input/render.txt') as $line) {
        $fields = explode(' ', $line);
        array_shift($fields);
        $values[] = array_map('intval', $fields);
    }
    return (object) ['width' => $values[0][0], 'height' => $values[0][1], 'contrast' => $values[1][0], 'depth' => $values[2][0],
        'far' => $values[3][0], 'epsilon' => $values[4][0], 'pad' => $values[5][0]];
}

class Renderer
{
    public object $scene;
    public object $settings;
    public array $nodes = [];
    public array $rays = [];
    public array $misses = [];
    public array $depthCounts;
    public array $tests = [];
    public int $totalInternal = 0;
    public int $clamped = 0;
    public int $supersampled = 0;
    public ?object $root;
    public array $planes;
    public array $pixels = [];

    public function __construct(object $scene, object $settings)
    {
        $this->scene = $scene;
        $this->settings = $settings;
        foreach (KINDS as $kind) {
            $this->rays[$kind] = 0;
            $this->tests[$kind] = (object) ['nodes' => 0, 'objects' => 0];
            if ($kind !== 'shadow') {
                $this->misses[$kind] = 0;
            }
        }
        $this->depthCounts = array_fill(0, $settings->depth + 1, 0);
        $bounded = [];
        $this->planes = [];
        foreach ($scene->objects as $object) {
            $object->bounds = bounds($object, $settings->pad);
            $object->counts = (object) ['primary' => 0, 'secondary' => 0, 'shadow' => 0];
            if ($object->bounds !== null) {
                $bounded[] = $object;
            } else {
                $this->planes[] = $object;
            }
        }
        foreach ($scene->lights as $light) {
            $light->counts = (object) ['pixels' => 0, 'shadowRays' => 0, 'blocked' => 0, 'attenuated' => 0, 'backfacing' => 0, 'outside' => 0];
        }
        $this->root = count($bounded) ? buildBVH($bounded, 0, $this->nodes) : null;
    }

    public function testNode(object $node, array $origin, array $direction, string $kind, object $context): ?object
    {
        if ($context->render) {
            $this->tests[$kind]->nodes++;
            $node->visits++;
        }
        return slab($node->lo, $node->hi, $origin, $direction);
    }

    public function testObject(object $object, array $origin, array $direction, string $kind, object $context): ?object
    {
        if ($context->render) {
            $this->tests[$kind]->objects++;
        }
        return candidate($object, $origin, $direction, $this->settings->epsilon);
    }

    public function nearest(array $origin, array $direction, string $kind, object $context): ?object
    {
        $best = null;
        foreach ($this->planes as $plane) {
            $this->consider($plane, $origin, $direction, $kind, $context, $best);
        }
        if ($this->root !== null) {
            $this->visitNearest($this->root, $origin, $direction, $kind, $context, $best);
        }
        return $best;
    }

    private function consider(object $object, array $origin, array $direction, string $kind, object $context, ?object &$best): void
    {
        $result = $this->testObject($object, $origin, $direction, $kind, $context);
        if ($result !== null && $result->t <= $this->settings->far && ($best === null || $result->t < $best->t
            || ($result->t === $best->t && $object->number < $best->object->number))) {
            $result->object = $object;
            $best = $result;
        }
    }

    private function visitNearest(object $node, array $origin, array $direction, string $kind, object $context, ?object &$best): void
    {
        $result = $this->testNode($node, $origin, $direction, $kind, $context);
        if ($result === null || $result->far <= $this->settings->epsilon || $result->near > $this->settings->far
            || ($best !== null && $result->near > $best->t)) {
            return;
        }
        if ($node->objects !== null) {
            foreach ($node->objects as $object) {
                $this->consider($object, $origin, $direction, $kind, $context, $best);
            }
        } else {
            $this->visitNearest($node->left, $origin, $direction, $kind, $context, $best);
            $this->visitNearest($node->right, $origin, $direction, $kind, $context, $best);
        }
    }

    public function occluders(array $origin, array $direction, int $distance, object $context): array
    {
        $result = [];
        foreach ($this->planes as $plane) {
            $this->considerOccluder($plane, $origin, $direction, $distance, $context, $result);
        }
        if ($this->root !== null) {
            $this->visitOccluders($this->root, $origin, $direction, $distance, $context, $result);
        }
        usort($result, fn($a, $b) => $a->number <=> $b->number);
        if ($context->render) {
            foreach ($result as $object) {
                $object->counts->shadow++;
            }
        }
        return $result;
    }

    private function considerOccluder(object $object, array $origin, array $direction, int $distance, object $context, array &$result): void
    {
        $hit = $this->testObject($object, $origin, $direction, 'shadow', $context);
        if ($hit !== null && $hit->t < $distance) {
            $result[] = $object;
        }
    }

    private function visitOccluders(object $node, array $origin, array $direction, int $distance, object $context, array &$result): void
    {
        $hit = $this->testNode($node, $origin, $direction, 'shadow', $context);
        if ($hit === null || $hit->far <= $this->settings->epsilon || $hit->near >= $distance) {
            return;
        }
        if ($node->objects !== null) {
            foreach ($node->objects as $object) {
                $this->considerOccluder($object, $origin, $direction, $distance, $context, $result);
            }
        } else {
            $this->visitOccluders($node->left, $origin, $direction, $distance, $context, $result);
            $this->visitOccluders($node->right, $origin, $direction, $distance, $context, $result);
        }
    }

    public function camera(int $qx, int $qy): array
    {
        $width = $this->settings->width;
        $height = $this->settings->height;
        $u = floorDiv(($qx - 2 * $width) * $this->scene->view[0], 2 * $width);
        $v = floorDiv((2 * $height - $qy) * $this->scene->view[1], 2 * $height);
        return vecNormalize(vecAdd(vecAdd($this->scene->forward, vecScale($this->scene->right, $u)), vecScale($this->scene->up, $v)));
    }

    public function samples(object $light, array $point): array
    {
        if ($light->kind === 'sun') {
            return [(object) ['direction' => $light->direction, 'distance' => $this->settings->far, 'intensity' => $light->intensity]];
        }
        $positions = [];
        if ($light->kind === 'area') {
            $k = $light->divisions;
            for ($j = 0; $j < $k; $j++) {
                for ($i = 0; $i < $k; $i++) {
                    $position = [];
                    for ($axis = 0; $axis < 3; $axis++) {
                        $position[] = $light->position[$axis] + floorDiv((2 * $i + 1) * $light->u[$axis], 2 * $k)
                            + floorDiv((2 * $j + 1) * $light->v[$axis], 2 * $k);
                    }
                    $positions[] = $position;
                }
            }
        } else {
            $positions[] = $light->position;
        }
        $samples = [];
        foreach ($positions as $position) {
            $relative = vecSub($position, $point);
            $samples[] = (object) ['direction' => vecNormalize($relative), 'distance' => vecLength($relative),
                'intensity' => floorDiv($light->intensity, $light->samples)];
        }
        return $samples;
    }

    public function cone(object $light, array $direction): int
    {
        if ($light->kind !== 'spot') {
            return S;
        }
        $cosine = -vecDot($direction, $light->direction);
        if ($cosine <= $light->outer) {
            return 0;
        }
        if ($cosine >= $light->inner) {
            return S;
        }
        return floorDiv(($cosine - $light->outer) * S, $light->inner - $light->outer);
    }

    public function countRay(string $kind, int $depth, object $context): void
    {
        if (!$context->render) {
            return;
        }
        $this->rays[$kind]++;
        $context->pixel->rays++;
        if ($kind !== 'shadow') {
            $this->depthCounts[$depth]++;
            $context->pixel->rayDepth = max($context->pixel->rayDepth, $depth);
        }
    }

    public function localColor(object $hit, array $direction, object $context): object
    {
        $lightResults = [];
        $view = vecNeg($direction);
        $material = $hit->object->material;
        $diffuse = 0;
        $specular = 0;
        foreach ($this->scene->lights as $light) {
            $result = (object) ['number' => $light->number, 'samples' => $light->samples, 'lit' => 0, 'diffuse' => 0, 'specular' => 0];
            foreach ($this->samples($light, $hit->point) as $sample) {
                $ndl = vecDot($hit->normal, $sample->direction);
                if ($ndl <= 0) {
                    if ($context->render) {
                        $light->counts->backfacing++;
                    }
                    continue;
                }
                $cone = $this->cone($light, $sample->direction);
                if ($cone === 0) {
                    if ($context->render) {
                        $light->counts->outside++;
                    }
                    continue;
                }
                $this->countRay('shadow', 0, $context);
                if ($context->render) {
                    $light->counts->shadowRays++;
                }
                $blockers = $this->occluders($hit->point, $sample->direction, $sample->distance, $context);
                $factor = $cone;
                foreach ($blockers as $object) {
                    $factor = mul($factor, $object->material->kt);
                }
                if ($factor === 0) {
                    if ($context->render) {
                        $light->counts->blocked++;
                    }
                    continue;
                }
                if ($context->render && count($blockers)) {
                    $light->counts->attenuated++;
                }
                $result->lit++;
                $parts = components($material, $hit->normal, $sample->direction, $view, $ndl, mul($sample->intensity, $factor));
                $result->diffuse += $parts->diffuse;
                $result->specular += $parts->specular;
            }
            $lightResults[] = $result;
            $diffuse += $result->diffuse;
            $specular += $result->specular;
        }
        $local = [];
        foreach ($hit->base as $value) {
            $raw = floorDiv($value * ($this->scene->ambient + $diffuse), S) + floorDiv(255 * $specular, S);
            if ($context->render && $raw > 255) {
                $this->clamped++;
            }
            $local[] = min($raw, 255);
        }
        $illumination = count(array_filter($lightResults, fn($result) => $result->lit > 0));
        return (object) compact('local', 'lightResults', 'illumination');
    }

    public function trace(array $origin, array $direction, string $kind, int $depth, object $context): object
    {
        $this->countRay($kind, $depth, $context);
        if ($context->record !== null) {
            $context->record[] = 'ray ' . $kind . ' ' . $depth . ' origin ' . triple($origin) . ' direction ' . triple($direction);
        }
        $hit = $this->nearest($origin, $direction, $kind, $context);
        if ($hit === null) {
            if ($context->render) {
                $this->misses[$kind]++;
            }
            if ($context->record !== null) {
                $context->record[] = 'miss';
                $context->record[] = 'color ' . triple($this->scene->background);
            }
            return (object) ['color' => $this->scene->background, 'hit' => null];
        }
        $point = vecAdd($origin, vecScale($direction, $hit->t));
        $outward = outwardNormal($hit->object, $point, $direction, $hit);
        $front = vecDot($outward, $direction) <= 0;
        $normal = $front ? $outward : vecNeg($outward);
        $hit->point = $point;
        $hit->normal = $normal;
        $hit->front = $front;
        $hit->base = baseColor($hit->object->material, $point);
        if ($context->render) {
            $field = $kind === 'primary' ? 'primary' : 'secondary';
            $hit->object->counts->$field++;
        }
        if ($context->record !== null) {
            $context->record[] = 'hit ' . $hit->object->label . ' t ' . $hit->t . ' point ' . triple($point)
                . ' normal ' . triple($normal) . ' base ' . triple($hit->base);
        }
        $lighting = $this->localColor($hit, $direction, $context);
        $hit->local = $lighting->local;
        $hit->lightResults = $lighting->lightResults;
        $hit->illumination = $lighting->illumination;
        if ($context->record !== null) {
            foreach ($hit->lightResults as $light) {
                $context->record[] = 'light ' . $light->number . ' lit ' . $light->lit . ' of ' . $light->samples
                    . ' diffuse ' . $light->diffuse . ' specular ' . $light->specular;
            }
            $context->record[] = 'local ' . triple($hit->local);
        }
        $color = $hit->local;
        $material = $hit->object->material;
        if ($depth < $this->settings->depth && ($material->kr > 0 || $material->kt > 0)) {
            $weights = refraction($direction, $normal, $front, $material);
            if ($weights->totalInternal) {
                if ($context->render) {
                    $this->totalInternal++;
                }
                if ($context->record !== null) {
                    $context->record[] = 'total_internal_reflection';
                }
            }
            if ($context->record !== null) {
                $context->record[] = 'weights ' . (S - $material->kr - $material->kt) . ' ' . $weights->wr . ' ' . $weights->wt;
            }
            $reflected = [0, 0, 0];
            $refracted = [0, 0, 0];
            if ($weights->wr > 0) {
                $reflected = $this->trace($point, reflection($direction, $normal), 'reflection', $depth + 1, $context)->color;
            }
            if ($weights->wt > 0) {
                $refracted = $this->trace($point, $weights->transmitted, 'refraction', $depth + 1, $context)->color;
            }
            $color = mix([$hit->local, $reflected, $refracted], [S - $material->kr - $material->kt, $weights->wr, $weights->wt]);
        }
        if ($this->scene->fog !== null) {
            $fog = $this->scene->fog;
            $factor = $hit->t <= $fog->start ? 0 : ($hit->t >= $fog->end ? S : floorDiv(($hit->t - $fog->start) * S, $fog->end - $fog->start));
            $color = mix([$color, $fog->color], [S - $factor, $factor]);
        }
        if ($context->record !== null) {
            $context->record[] = 'color ' . triple($color);
        }
        return (object) compact('color', 'hit');
    }

    public function render(): void
    {
        $width = $this->settings->width;
        $height = $this->settings->height;
        $contrast = $this->settings->contrast;
        for ($y = 0; $y < $height; $y++) {
            for ($x = 0; $x < $width; $x++) {
                $pixel = (object) ['x' => $x, 'y' => $y, 'rays' => 0, 'rayDepth' => 0, 'samples' => 1];
                $context = (object) ['render' => true, 'pixel' => $pixel, 'record' => null];
                $result = $this->trace($this->scene->eye, $this->camera(4 * $x + 2, 4 * $y + 2), 'primary', 0, $context);
                $pixel->center = $result->color;
                $pixel->color = $result->color;
                $pixel->hit = $result->hit;
                $pixel->label = $result->hit !== null ? $result->hit->object->label : '.';
                if ($result->hit !== null) {
                    foreach ($result->hit->lightResults as $light) {
                        if ($light->lit > 0) {
                            $this->scene->lights[$light->number - 1]->counts->pixels++;
                        }
                    }
                }
                $this->pixels[] = $pixel;
            }
        }
        foreach ($this->pixels as $pixel) {
            $subsample = false;
            foreach ([[$pixel->x, $pixel->y - 1], [$pixel->x, $pixel->y + 1], [$pixel->x - 1, $pixel->y], [$pixel->x + 1, $pixel->y]] as [$x, $y]) {
                if ($x < 0 || $x >= $width || $y < 0 || $y >= $height) {
                    continue;
                }
                $other = $this->pixels[$y * $width + $x];
                $difference = 0;
                for ($axis = 0; $axis < 3; $axis++) {
                    $difference = max($difference, abs($pixel->center[$axis] - $other->center[$axis]));
                }
                if ($other->label !== $pixel->label || $difference > $contrast) {
                    $subsample = true;
                    break;
                }
            }
            if (!$subsample) {
                continue;
            }
            $this->supersampled++;
            $pixel->samples = 4;
            $sum = [0, 0, 0];
            $context = (object) ['render' => true, 'pixel' => $pixel, 'record' => null];
            foreach ([[1, 1], [3, 1], [1, 3], [3, 3]] as [$dx, $dy]) {
                $result = $this->trace($this->scene->eye, $this->camera(4 * $pixel->x + $dx, 4 * $pixel->y + $dy), 'primary', 0, $context);
                for ($axis = 0; $axis < 3; $axis++) {
                    $sum[$axis] += $result->color[$axis];
                }
            }
            $pixel->color = array_map(fn($value) => floorDiv($value, 4), $sum);
        }
    }
}

function meanColor(array $pixels): array
{
    $sum = [0, 0, 0];
    foreach ($pixels as $pixel) {
        for ($axis = 0; $axis < 3; $axis++) {
            $sum[$axis] += $pixel->color[$axis];
        }
    }
    return array_map(fn($value) => floorDiv($value, count($pixels)), $sum);
}

function imageFile(string $name, string $format, int $width, int $height, array $pixels): void
{
    $rows = [$format, $width . ' ' . $height, '255'];
    for ($y = 0; $y < $height; $y++) {
        $row = [];
        for ($x = 0; $x < $width; $x++) {
            $value = $pixels[$y * $width + $x];
            if ($format === 'P3') {
                foreach ($value as $component) {
                    $row[] = $component;
                }
            } else {
                $row[] = $value;
            }
        }
        $rows[] = implode(' ', $row);
    }
    writeLines($name, $rows);
}

function renderingSummary(Renderer $renderer): object
{
    $minimum = null;
    $maximum = null;
    $maxRays = 0;
    $histogram = array_fill(0, 8, 0);
    foreach ($renderer->pixels as $pixel) {
        if ($pixel->hit !== null) {
            $minimum = $minimum === null ? $pixel->hit->t : min($minimum, $pixel->hit->t);
            $maximum = $maximum === null ? $pixel->hit->t : max($maximum, $pixel->hit->t);
        }
        $maxRays = max($maxRays, $pixel->rays);
        [$r, $g, $b] = $pixel->color;
        $brightness = floorDiv(299 * $r + 587 * $g + 114 * $b, 1000);
        $histogram[floorDiv($brightness, 32)]++;
    }
    $mean = meanColor($renderer->pixels);
    return (object) compact('minimum', 'maximum', 'maxRays', 'mean', 'histogram');
}

function writeImages(Renderer $renderer, object $summary): void
{
    $width = $renderer->settings->width;
    $height = $renderer->settings->height;
    $pixels = $renderer->pixels;
    $image = $depth = $normal = $albedo = $cost = [];
    foreach ($pixels as $pixel) {
        $image[] = $pixel->color;
        $depth[] = $pixel->hit === null ? 0 : ($summary->maximum === $summary->minimum ? 255
            : 255 - floorDiv(235 * ($pixel->hit->t - $summary->minimum), $summary->maximum - $summary->minimum));
        $normal[] = $pixel->hit === null ? [0, 0, 0] : array_map(fn($value) => min(255, max(0, floorDiv(($value + S) * 255, 2 * S))), $pixel->hit->normal);
        $albedo[] = $pixel->hit === null ? [0, 0, 0] : $pixel->hit->base;
        $cost[] = floorDiv(255 * $pixel->rays, $summary->maxRays);
    }
    imageFile('image.ppm', 'P3', $width, $height, $image);
    imageFile('depth.pgm', 'P2', $width, $height, $depth);
    imageFile('normal.ppm', 'P3', $width, $height, $normal);
    imageFile('albedo.ppm', 'P3', $width, $height, $albedo);
    imageFile('cost.pgm', 'P2', $width, $height, $cost);
    $maps = [
        'object_map.txt' => fn($pixel) => $pixel->label,
        'light_map.txt' => fn($pixel) => $pixel->hit === null ? '.' : (string) $pixel->hit->illumination,
        'ray_depth.txt' => fn($pixel) => (string) $pixel->rayDepth,
    ];
    foreach ($maps as $name => $value) {
        $rows = [];
        for ($y = 0; $y < $height; $y++) {
            $row = '';
            for ($x = 0; $x < $width; $x++) {
                $row .= $value($pixels[$y * $width + $x]);
            }
            $rows[] = $row;
        }
        writeLines($name, $rows);
    }
}

function statsLines(Renderer $renderer, object $summary): array
{
    $width = $renderer->settings->width;
    $height = $renderer->settings->height;
    $r = $renderer->rays;
    $m = $renderer->misses;
    $rows = ['image ' . $width . ' ' . $height, 'supersampled ' . $renderer->supersampled,
        'rays primary ' . $r['primary'] . ' reflection ' . $r['reflection'] . ' refraction ' . $r['refraction'] . ' shadow ' . $r['shadow'] . ' total ' . array_sum($r),
        'misses primary ' . $m['primary'] . ' reflection ' . $m['reflection'] . ' refraction ' . $m['refraction'],
        'depth ' . implode(' ', $renderer->depthCounts)];
    foreach (KINDS as $kind) {
        $rows[] = 'tests ' . $kind . ' nodes ' . $renderer->tests[$kind]->nodes . ' objects ' . $renderer->tests[$kind]->objects;
    }
    $rows[] = 'total_internal_reflection ' . $renderer->totalInternal;
    $rows[] = 'clamped ' . $renderer->clamped;
    $rows[] = $summary->minimum === null ? 'distance none' : 'distance ' . $summary->minimum . ' ' . $summary->maximum;
    $rows[] = 'max_pixel_rays ' . $summary->maxRays;
    $rows[] = 'mean ' . triple($summary->mean);
    $rows[] = 'histogram ' . implode(' ', $summary->histogram);
    foreach ($renderer->nodes as $node) {
        $description = 'inner';
        if ($node->objects !== null) {
            $description = 'leaf ' . implode('', array_map(fn($object) => $object->label, $node->objects));
        }
        $rows[] = 'node ' . $node->depth . ' ' . $description . ' box ' . triple($node->lo) . ' ' . triple($node->hi) . ' visits ' . $node->visits;
    }
    foreach ($renderer->scene->objects as $object) {
        $selected = array_values(array_filter($renderer->pixels, fn($pixel) => $pixel->label === $object->label));
        $c = $object->counts;
        $suffix = 'box none color none';
        if (count($selected)) {
            $xs = array_map(fn($pixel) => $pixel->x, $selected);
            $ys = array_map(fn($pixel) => $pixel->y, $selected);
            $suffix = 'box ' . min($xs) . ' ' . min($ys) . ' ' . max($xs) . ' ' . max($ys) . ' color ' . triple(meanColor($selected));
        }
        $rows[] = 'object ' . $object->label . ' ' . $object->kind . ' primary ' . $c->primary . ' secondary ' . $c->secondary
            . ' shadow ' . $c->shadow . ' pixels ' . count($selected) . ' ' . $suffix;
    }
    foreach ($renderer->scene->lights as $light) {
        $c = $light->counts;
        $rows[] = 'light ' . $light->number . ' ' . $light->kind . ' samples ' . $light->samples . ' pixels ' . $c->pixels
            . ' shadow_rays ' . $c->shadowRays . ' blocked ' . $c->blocked . ' attenuated ' . $c->attenuated
            . ' backfacing ' . $c->backfacing . ' outside ' . $c->outside;
    }
    return $rows;
}

function queryLines(Renderer $renderer, array $queries): array
{
    $rows = [];
    $scene = $renderer->scene;
    $settings = $renderer->settings;
    $pixels = $renderer->pixels;
    foreach ($queries as $q => $line) {
        $tokens = explode(' ', $line);
        $kind = array_shift($tokens);
        $values = array_map('intval', $tokens);
        $context = (object) ['render' => false, 'record' => null, 'pixel' => null];
        $rows[] = 'query ' . ($q + 1) . ' ' . $line;
        if ($kind === 'pixel') {
            $pixel = $pixels[$values[1] * $settings->width + $values[0]];
            $rows[] = 'label ' . $pixel->label . ' distance ' . ($pixel->hit === null ? 'none' : $pixel->hit->t)
                . ' color ' . triple($pixel->color) . ' samples ' . $pixel->samples . ' rays ' . $pixel->rays;
        } elseif ($kind === 'trace' || $kind === 'ray') {
            $origin = $kind === 'trace' ? $scene->eye : array_slice($values, 0, 3);
            $direction = $kind === 'trace' ? $renderer->camera(4 * $values[0] + 2, 4 * $values[1] + 2) : vecNormalize(array_slice($values, 3, 3));
            $context->record = [];
            $renderer->trace($origin, $direction, 'primary', 0, $context);
            $rows = array_merge($rows, $context->record);
        } elseif ($kind === 'object') {
            $object = null;
            foreach ($scene->objects as $value) {
                if ($value->label === $tokens[0]) {
                    $object = $value;
                    break;
                }
            }
            $box = $object->bounds === null ? 'none leaf none'
                : triple($object->bounds->lo) . ' ' . triple($object->bounds->hi) . ' leaf ' . $object->leaf->depth;
            $rows[] = $object->kind . ' material ' . $object->material->name . ' bounds ' . $box;
        } elseif ($kind === 'visible') {
            $relative = vecSub($values, $scene->eye);
            $direction = vecNormalize($relative);
            $blockers = $renderer->occluders($scene->eye, $direction, vecLength($relative) - $settings->epsilon, $context);
            $first = $renderer->nearest($scene->eye, $direction, 'primary', $context);
            $rows[] = (count($blockers) ? 'no' : 'yes') . ' first '
                . ($first === null ? 'none' : $first->object->label . ' t ' . $first->t);
        } elseif ($kind === 'shadow') {
            foreach ($scene->lights as $light) {
                $factor = 0;
                $union = [];
                foreach ($renderer->samples($light, $values) as $sample) {
                    $transmission = $renderer->cone($light, $sample->direction);
                    $blockers = $renderer->occluders($values, $sample->direction, $sample->distance, $context);
                    foreach ($blockers as $object) {
                        $transmission = mul($transmission, $object->material->kt);
                        $union[$object->number] = true;
                    }
                    $factor += $transmission;
                }
                $labels = '';
                foreach ($scene->objects as $object) {
                    if (isset($union[$object->number])) {
                        $labels .= $object->label;
                    }
                }
                $rows[] = 'light ' . $light->number . ' factor ' . $factor . ' occluders ' . ($labels === '' ? 'none' : $labels);
            }
        } elseif ($kind === 'region') {
            [$x0, $y0, $x1, $y1] = $values;
            $selected = [];
            for ($y = $y0; $y <= $y1; $y++) {
                for ($x = $x0; $x <= $x1; $x++) {
                    $selected[] = $pixels[$y * $settings->width + $x];
                }
            }
            $rows[] = 'pixels ' . count($selected) . ' mean ' . triple(meanColor($selected));
            $labels = array_map(fn($object) => $object->label, $scene->objects);
            $labels[] = '.';
            foreach ($labels as $label) {
                $count = count(array_filter($selected, fn($pixel) => $pixel->label === $label));
                if ($count) {
                    $rows[] = 'label ' . $label . ' ' . $count;
                }
            }
        }
    }
    return $rows;
}

function main(): void
{
    $scene = readScene('input/scene.txt');
    $settings = readSettings();
    $queries = readLines('input/queries.txt');
    $renderer = new Renderer($scene, $settings);
    $renderer->render();
    $summary = renderingSummary($renderer);
    writeImages($renderer, $summary);
    writeLines('stats.txt', statsLines($renderer, $summary));
    writeLines('queries.txt', queryLines($renderer, $queries));
}

main();
