<?php

foreach (['molecule', 'smiles_parser', 'rings_aromatic', 'canonical', 'search'] as $module)
    require_once __DIR__ . "/$module.php";
const ARGUMENT_COUNTS = [
    'MATCH' => [1, 1],
    'CONTAINS' => [2, 2],
    'MATRIX' => [2, 12],
    'NEAREST' => [2, 2],
    'WITHIN' => [2, 2],
    'COMPARE' => [2, 2],
    'CLUSTER' => [1, 1],
];

const SYSTEM_KINDS = ['isolated', 'fused', 'spiro', 'bridged'];

function dataLines(string $name): array
{
    $result = [];
    foreach (file('input/' . $name, FILE_IGNORE_NEW_LINES) as $i => $line)
        if ($line !== '' && $line[0] !== '#')
            $result[] = [$i + 1, $line];
    return $result;
}

function validName(string $text): bool
{
    return (bool) preg_match('/\A[A-Za-z0-9_-]{1,32}\z/', $text);
}

function validNumber(string $text, int $lo, int $hi): bool
{
    return (
        preg_match('/\A(?:0|[1-9][0-9]*)\z/', $text)
        && strlen($text) <= strlen((string) $hi)
        && (int) $text >= $lo
        && (int) $text <= $hi
    );
}

function readThreshold(string $text): ?array
{
    $parts = explode('/', $text);
    if (
        count($parts) !== 2
        || !validNumber($parts[0], 0, 99)
        || !validNumber($parts[1], 1, 99)
        || (int) $parts[0] > (int) $parts[1]
    )
        return null;
    return [(int) $parts[0], (int) $parts[1]];
}

function fractionText(array $f): string
{
    [$a, $b] = $f;
    $x = $a;
    $y = $b;
    while ($y)
        [$x, $y] = [$y, $x % $y];
    return intdiv($a, $x) . '/' . intdiv($b, $x);
}

function fractionCompare(array $a, array $b): int
{
    return ($a[0] * $b[1]) <=> ($b[0] * $a[1]);
}

function atomNumbers(array $numbers, string $separator = ','): string
{
    return implode($separator, array_map(fn($i) => $i + 1, $numbers));
}

function memberNames(array $molecules): string
{
    return implode(',', array_map(fn($m) => $m->name, $molecules));
}

function increment(array &$counts, string|int $key, int $amount = 1): void
{
    $counts[$key] = ($counts[$key] ?? 0) + $amount;
}

function analyze(Molecule $m): void
{
    findRings($m);
    foreach ($m->bonds as $b) {
        if ($b->symbol !== null)
            $b->kind = BOND_TYPES[$b->symbol];
        else {
            [$a, $c] = $b->ends;
            $b->kind = $m->atoms[$a]->aromatic && $m->atoms[$c]->aromatic && $b->ring ? 4 : 1;
        }
    }
    $needing = [];
    foreach ($m->atoms as $i => $a)
        if (needsPi($m, $i))
            $needing[] = $i;
    kekulize($m, $needing);
    foreach ($m->atoms as $i => $a) {
        $total = $m->bondTotal($i);
        if ($a->bracket) {
            if (($total + $a->hydrogens) > (max($a->element->valences) + abs($a->charge)))
                throw new AnalysisError('bad valence', $a->column);
        } else {
            $h = organicHydrogens($a, $total);
            if ($h === null)
                throw new AnalysisError('bad valence', $a->column);
            $a->hydrogens = $h;
        }
    }
}

function molecularProperties(Molecule $m): array
{
    $counts = [];
    $hydrogens = $weight = $heavy = $donors = $acceptors = $charge = 0;
    $heavyDegrees = $triple = [];
    foreach ($m->atoms as $i => $a) {
        increment($counts, $a->element->symbol);
        $hydrogens += $a->hydrogens;
        $weight += $a->mass ? $a->mass * 1000 : $a->element->weight;
        $heavy += (int) ($a->element->symbol !== 'H');
        $charge += $a->charge;
        $heavyDegrees[$i] = count(array_filter(
            array_keys($m->neighbors[$i]),
            fn($j) => $m->atoms[$j]->element->symbol !== 'H',
        ));
        if ($a->element->symbol === 'N' || $a->element->symbol === 'O') {
            ++$acceptors;
            $attached = $a->hydrogens;
            foreach ($m->neighbors[$i] as $j => $b)
                $attached += (int) ($m->atoms[$j]->element->symbol === 'H');
            $donors += (int) ($attached >= 1);
        }
    }
    increment($counts, 'H', $hydrogens);
    $weight += $hydrogens * $m->elements['H']->weight;
    $symbols = array_keys(array_filter($counts));
    usort($symbols, strcmp(...));
    if ($counts['C'] ?? 0) {
        $symbols = array_values(array_diff($symbols, ['C', 'H']));
        $symbols = $counts['H'] ?? 0 ? ['C', 'H', ...$symbols] : ['C', ...$symbols];
    }
    $formula = '';
    foreach ($symbols as $symbol)
        $formula .= $symbol . ($counts[$symbol] === 1 ? '' : $counts[$symbol]);
    foreach ($m->bonds as $b)
        if ($b->multiplicity === 3)
            foreach ($b->ends as $i)
                $triple[$i] = true;
    $rotatable = 0;
    foreach ($m->bonds as $b) {
        [$a, $c] = $b->ends;
        if (
            $b->multiplicity === 1
            && !$b->ring
            && $heavyDegrees[$a] >= 2
            && $heavyDegrees[$c] >= 2
            && !isset($triple[$a])
            && !isset($triple[$c])
        )
            ++$rotatable;
    }
    $violations = (int) ($weight > 500000) + (int) ($donors > 5) + (int) ($acceptors > 10);
    return [
        'formula' => $formula,
        'weight' => $weight,
        'heavy' => $heavy,
        'rotatable' => $rotatable,
        'donors' => $donors,
        'acceptors' => $acceptors,
        'lipinski' => $violations <= 1 ? 'pass' : 'fail',
        'charge' => $charge,
    ];
}

function scaffoldMolecule(Molecule $m): ?Molecule
{
    if (!$m->rings)
        return null;
    $remaining = array_fill_keys(array_keys($m->atoms), true);
    while (true) {
        $leaf = null;
        foreach ($m->atoms as $i => $a)
            if (
                isset($remaining[$i])
                && !isset($m->ringAtoms[$i])
                && count(array_intersect_key($m->neighbors[$i], $remaining)) === 1
            ) {
                $leaf = $i;
                break;
            }
        if ($leaf === null)
            break;
        unset($remaining[$leaf]);
    }
    $kept = $remaining;
    foreach ($remaining as $i => $unused)
        foreach ($m->neighbors[$i] as $j => $b)
            if (!isset($remaining[$j]) && $b->kind === 2)
                $kept[$j] = true;
    $scaffold = new Molecule($m->elements);
    $renumber = [];
    foreach ($m->atoms as $i => $a)
        if (isset($kept[$i])) {
            $added = 0;
            foreach ($m->neighbors[$i] as $j => $b)
                if (!isset($kept[$j]))
                    $added += $b->multiplicity;
            $renumber[$i] = $scaffold->addAtom(
                new Atom(
                    $a->element,
                    $a->aromatic,
                    $a->mass,
                    $a->charge,
                    $a->hydrogens + $added,
                    $a->bracket,
                    $a->column,
                ),
            );
        }
    foreach ($m->orderedBonds() as $b) {
        [$a, $c] = $b->ends;
        if (isset($kept[$a], $kept[$c])) {
            $copy = $scaffold->addBond($renumber[$a], $renumber[$c], $b->symbol);
            $copy->kind = $b->kind;
            $copy->multiplicity = $b->multiplicity;
            $copy->ring = $b->ring;
        }
    }
    foreach ($m->rings as $ring)
        $scaffold->rings[] = array_map(fn($i) => $renumber[$i], $ring);
    foreach ($m->ringAtoms as $i => $unused)
        $scaffold->ringAtoms[$renumber[$i]] = true;
    return $scaffold;
}

function ringSystems(Molecule $m): array
{
    $sets = array_map(fn($r) => array_fill_keys($r, true), $m->rings);
    $connections = array_fill(0, count($sets), []);
    $relations = [];
    for ($i = 0; $i < count($sets); ++$i)
        for ($j = $i + 1; $j < count($sets); ++$j) {
            $shared = array_keys(array_intersect_key($sets[$i], $sets[$j]));
            $n = count($shared);
            if (!$n)
                continue;
            $connections[$i][$j] = $connections[$j][$i] = true;
            if ($n === 1)
                $kind = 'spiro';
            elseif ($n === 2)
                $kind = isset($m->neighbors[$shared[0]][$shared[1]]) ? 'fused' : 'bridged';
            else
                $kind = 'bridged';
            $relations[] = [$i, $j, $kind];
        }
    $unseen = array_fill_keys(array_keys($sets), true);
    $systems = [];
    while ($unseen) {
        $start = min(array_keys($unseen));
        unset($unseen[$start]);
        $component = [$start => true];
        $queue = [$start];
        for ($i = 0; $i < count($queue); ++$i)
            foreach ($connections[$queue[$i]] as $j => $unused)
                if (isset($unseen[$j])) {
                    unset($unseen[$j]);
                    $component[$j] = true;
                    $queue[] = $j;
                }
        $kinds = [];
        foreach ($relations as [$i, $j, $kind])
            if (isset($component[$i], $component[$j]))
                $kinds[$kind] = true;
        $kind = count($component) === 1
            ? 'isolated'
            : (isset($kinds['bridged']) ? 'bridged' : (isset($kinds['fused']) ? 'fused' : 'spiro'));
        $atoms = [];
        foreach ($component as $i => $unused)
            $atoms += $sets[$i];
        $rings = array_keys($component);
        sort($rings, SORT_NUMERIC);
        $systems[] = ['rings' => $rings, 'atoms' => count($atoms), 'kind' => $kind];
    }
    return $systems;
}

function prepareMolecules(array $molecules): void
{
    foreach ($molecules as $m) {
        $m->properties = molecularProperties($m);
        [$m->canonical, $m->classes] = canonicalize($m);
        $scaffold = scaffoldMolecule($m);
        $m->scaffold = $scaffold === null ? null : canonicalize($scaffold)[0];
        $m->systems = ringSystems($m);
        foreach ($m->rings as $ring)
            $m->aromaticRings[] = array_all($ring, fn($i) => $m->atoms[$i]->aromatic);
        [$m->bits, $m->paths] = fingerprint($m);
    }
}

function checkQuery(array &$q, array $elements, array $byName): ?string
{
    $kind = $q['type'];
    $arguments = $q['arguments'];
    [$lo, $hi] = ARGUMENT_COUNTS[$kind];
    if (count($arguments) < $lo || count($arguments) > $hi)
        return 'bad arguments';
    if ($kind === 'MATCH') {
        try {
            $q['pattern'] = parseSmiles($arguments[0], $elements, true);
        } catch (AnalysisError $e) {
            return "bad pattern {$e->reason} at column {$e->column}";
        }
    } elseif ($kind === 'CLUSTER') {
        $q['threshold'] = readThreshold($arguments[0]);
        if ($q['threshold'] === null)
            return 'bad threshold';
    } elseif (in_array($kind, ['CONTAINS', 'MATRIX', 'COMPARE'], true)) {
        foreach ($arguments as $name)
            if (!isset($byName[$name]))
                return 'unknown molecule ' . $name;
        if (count(array_unique($arguments, SORT_STRING)) !== count($arguments))
            return 'repeated molecule';
    } else {
        if (!isset($byName[$arguments[0]]))
            return 'unknown molecule ' . $arguments[0];
        if ($kind === 'NEAREST') {
            if (!validNumber($arguments[1], 1, 99))
                return 'bad count';
            $q['count'] = (int) $arguments[1];
        } else {
            $q['threshold'] = readThreshold($arguments[1]);
            if ($q['threshold'] === null)
                return 'bad threshold';
        }
    }
    return null;
}

function readMolecules(array $elements, array &$causes): array
{
    $molecules = $errors = $reserved = [];
    $lines = dataLines('molecules.smi');
    foreach ($lines as [$lineNumber, $line]) {
        $tokens = explode(' ', $line);
        if (count($tokens) !== 2 || $tokens[0] === '' || !validName($tokens[1])) {
            $errors[] = "line $lineNumber: bad line";
            increment($causes, 'bad line');
            continue;
        }
        [$smiles, $name] = $tokens;
        if (isset($reserved[$name])) {
            $errors[] = "line $lineNumber $name: duplicate name";
            increment($causes, 'duplicate name');
            continue;
        }
        $reserved[$name] = true;
        try {
            $m = parseSmiles($smiles, $elements);
            analyze($m);
        } catch (AnalysisError $e) {
            $errors[] = "line $lineNumber $name: {$e->reason} at column {$e->column}";
            increment($causes, $e->reason);
            continue;
        }
        $m->name = $name;
        $m->order = count($molecules);
        $molecules[] = $m;
    }
    return [
        $molecules,
        [
            'MOLECULES lines=' . count($lines) . ' valid=' . count($molecules) . ' errors=' . count($errors),
            ...$errors,
        ],
    ];
}

function readQueries(array $elements, array $byName, array &$causes): array
{
    $queries = $errors = $reserved = [];
    $lines = dataLines('queries.txt');
    foreach ($lines as [$number, $line]) {
        $tokens = explode(' ', $line);
        $kind = $tokens[0];
        $id = $tokens[1] ?? null;
        if (!isset(ARGUMENT_COUNTS[$kind]))
            $reason = 'unknown query';
        elseif ($id === null || !validName($id))
            $reason = 'bad id';
        elseif (isset($reserved[$id]))
            $reason = 'duplicate id';
        else {
            $reserved[$id] = true;
            $q = ['type' => $kind, 'id' => $id, 'arguments' => array_slice($tokens, 2)];
            $reason = checkQuery($q, $elements, $byName);
            if ($reason === null) {
                $queries[] = $q;
                continue;
            }
        }
        $errors[] = $reason === 'unknown query'
            ? "line $number: unknown query"
            : ($reason === 'bad id' ? "line $number $kind: bad id" : "line $number $kind $id: $reason");
        $cause = str_starts_with($reason, 'bad pattern ')
            ? 'bad pattern'
            : (str_starts_with($reason, 'unknown molecule ') ? 'unknown molecule' : $reason);
        increment($causes, $cause);
    }
    return [
        $queries,
        [
            'QUERIES lines=' . count($lines) . ' valid=' . count($queries) . ' errors=' . count($errors),
            ...$errors,
        ],
    ];
}

function propertiesLines(array $molecules): array
{
    $lines = ['name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski'];
    foreach ($molecules as $m) {
        $p = $m->properties;
        $weight = intdiv($p['weight'], 1000) . '.' . sprintf('%03d', $p['weight'] % 1000);
        $lines[] = implode(',', [
            $m->name,
            $p['formula'],
            $weight,
            $p['heavy'],
            count($m->rings),
            $p['rotatable'],
            $p['donors'],
            $p['acceptors'],
            $p['lipinski'],
        ]);
    }
    return $lines;
}

function canonicalParagraphs(array $molecules): array
{
    $canonicalGroups = $formulaGroups = $scaffoldGroups = [];
    $acyclic = 0;
    foreach ($molecules as $m) {
        $canonicalGroups[$m->canonical][] = $m;
        $formulaGroups[$m->properties['formula']][] = $m;
        if ($m->scaffold === null)
            ++$acyclic;
        else
            $scaffoldGroups[$m->scaffold][] = $m;
    }
    $canonical = ['CANONICAL molecules=' . count($molecules) . ' unique=' . count($canonicalGroups)];
    foreach ($molecules as $m) {
        $charge = $m->properties['charge'];
        $canonical[] =
            "{$m->name} {$m->canonical} classes={$m->classes} charge=" . ($charge > 0 ? '+' : '') . $charge;
    }
    $groups = array_filter($canonicalGroups, fn($members) => count($members) >= 2);
    $count = array_sum(array_map(count(...), $groups));
    $duplicates = ['DUPLICATES groups=' . count($groups) . " molecules=$count"];
    $i = 0;
    foreach ($groups as $smiles => $members)
        $duplicates[] = 'group ' . ++$i . " $smiles members=" . memberNames($members);
    $groups = [];
    foreach ($formulaGroups as $formula => $members) {
        $forms = count(array_unique(array_map(fn($m) => $m->canonical, $members), SORT_STRING));
        if ($forms >= 2)
            $groups[] = [$formula, $members, $forms];
    }
    $isomers = ['ISOMERS groups=' . count($groups)];
    foreach ($groups as $i => [$formula, $members, $forms])
        $isomers[] = 'isomer ' . ($i + 1) . " $formula forms=$forms members=" . memberNames($members);
    $scaffolds = ['SCAFFOLDS distinct=' . count($scaffoldGroups) . " acyclic=$acyclic"];
    $keys = array_keys($scaffoldGroups);
    usort(
        $keys,
        fn($a, $b) => (
            count($scaffoldGroups[$b]) <=> count($scaffoldGroups[$a]) ?: strcmp((string) $a, (string) $b)
        ),
    );
    foreach ($keys as $i => $smiles)
        $scaffolds[] =
            'scaffold '
            . ($i + 1)
            . " $smiles count="
            . count($scaffoldGroups[$smiles])
            . ' members='
            . memberNames($scaffoldGroups[$smiles]);
    return [$canonical, $duplicates, $isomers, $scaffolds];
}

function ringParagraphs(array $molecules): array
{
    $paragraphs = $sizes = [];
    $kinds = array_fill_keys(SYSTEM_KINDS, 0);
    $totalAromatic = $totalRings = 0;
    foreach ($molecules as $m) {
        if (!$m->rings)
            continue;
        $aromatic = count(array_filter($m->aromaticRings));
        $totalAromatic += $aromatic;
        $totalRings += count($m->rings);
        $ringBonds = count(array_filter($m->bonds, fn($b) => $b->ring));
        $p = [
            "MOLECULE {$m->name} atoms="
                . count($m->atoms)
                . ' bonds='
                . count($m->bonds)
                . ' rings='
                . count($m->rings)
                . " aromatic=$aromatic systems="
                . count($m->systems)
                . ' ring_atoms='
                . count($m->ringAtoms)
                . " ring_bonds=$ringBonds",
        ];
        foreach ($m->rings as $i => $ring) {
            $hetero = count(array_filter($ring, fn($a) => $m->atoms[$a]->element->symbol !== 'C'));
            $flag = $m->aromaticRings[$i] ? 'yes' : 'no';
            $p[] =
                'ring '
                . ($i + 1)
                . ' size='
                . count($ring)
                . " aromatic=$flag hetero=$hetero atoms="
                . atomNumbers($ring, '-');
            increment($sizes, count($ring));
        }
        foreach ($m->systems as $i => $s) {
            ++$kinds[$s['kind']];
            $p[] =
                'system '
                . ($i + 1)
                . " kind={$s['kind']} rings="
                . atomNumbers($s['rings'])
                . " atoms={$s['atoms']}";
        }
        $doubles = [];
        foreach ($m->orderedBonds() as $b)
            if ($b->kind === 4 && $b->multiplicity === 2)
                $doubles[] = atomNumbers($b->ends, '=');
        $p[] = 'kekule ' . ($doubles ? implode(' ', $doubles) : '-');
        $paragraphs[] = $p;
    }
    $summary = [
        'SUMMARY molecules='
            . count($molecules)
            . ' cyclic='
            . count($paragraphs)
            . " rings=$totalRings aromatic=$totalAromatic",
    ];
    $parts = [];
    ksort($sizes, SORT_NUMERIC);
    foreach ($sizes as $size => $n)
        $parts[] = "$size=$n";
    $summary[] = 'sizes ' . ($parts ? implode(' ', $parts) : '-');
    $parts = [];
    foreach (SYSTEM_KINDS as $kind)
        $parts[] = $kind . '=' . $kinds[$kind];
    $summary[] = 'systems ' . implode(' ', $parts);
    $paragraphs[] = $summary;
    return $paragraphs;
}

function substructureParagraphs(array $queries, array $molecules, array $byName): array
{
    $paragraphs = [];
    $patterns = $hits = $contains = $found = 0;
    foreach ($queries as $q) {
        $kind = $q['type'];
        $id = $q['id'];
        $args = $q['arguments'];
        if ($kind === 'MATCH') {
            ++$patterns;
            $pattern = $q['pattern'];
            $matches = [];
            $total = 0;
            foreach ($molecules as $m) {
                [$count, $unique, $mapping] = embeddings($pattern, $m);
                if ($count) {
                    $matches[] = [$m, $count, $unique, $mapping];
                    $total += $count;
                }
            }
            $hits += count($matches);
            $p = [
                "MATCH $id {$args[0]} atoms="
                    . count($pattern->atoms)
                    . ' bonds='
                    . count($pattern->bonds)
                    . ' hits='
                    . count($matches)
                    . " embeddings=$total",
            ];
            $top = null;
            foreach ($matches as [$m, $count, $unique, $mapping]) {
                $p[] = "{$m->name} count=$count unique=$unique map=" . atomNumbers($mapping);
                if ($top === null || $count > $top[1])
                    $top = [$m, $count];
            }
            if ($top !== null)
                $p[] = "top {$top[0]->name} count={$top[1]}";
            $paragraphs[] = $p;
        } elseif ($kind === 'CONTAINS') {
            ++$contains;
            $a = $byName[$args[0]];
            $b = $byName[$args[1]];
            [$count, $unique, $mapping] = embeddings(moleculePattern($a), $b);
            $text = "CONTAINS $id {$a->name} {$b->name} result=";
            if ($count) {
                ++$found;
                $text .= "yes count=$count unique=$unique map=" . atomNumbers($mapping);
            } else
                $text .= 'no';
            $paragraphs[] = [$text];
        }
    }
    $paragraphs[] = ["SUMMARY patterns=$patterns hits=$hits contains=$contains found=$found"];
    return $paragraphs;
}

final class Similarities
{
    private array $cache = [];

    public function get(Molecule $a, Molecule $b): array
    {
        $key = min($a->order, $b->order) . ':' . max($a->order, $b->order);
        return $this->cache[$key] ??= tanimoto($a->bits, $b->bits);
    }
}

function similarityParagraphs(array $queries, array $molecules, array $byName): array
{
    $fingerprints = ['FINGERPRINTS molecules=' . count($molecules) . ' size=1024 depth=5'];
    foreach ($molecules as $m)
        $fingerprints[] = "{$m->name} bits=" . count($m->bits) . " paths={$m->paths}";
    $paragraphs = [$fingerprints];
    $similarities = new Similarities();
    foreach ($queries as $q) {
        $kind = $q['type'];
        $id = $q['id'];
        $args = $q['arguments'];
        $p = [];
        if ($kind === 'MATRIX') {
            $selected = array_map(fn($name) => $byName[$name], $args);
            $p = ["MATRIX $id size=" . count($selected)];
            foreach ($selected as $a)
                $p[] =
                    'row '
                    . $a->name
                    . ' '
                    . implode(' ', array_map(fn($b) => fractionText($similarities->get($a, $b)), $selected));
            $best = null;
            $first = $second = null;
            foreach ($selected as $i => $a)
                for ($j = $i + 1; $j < count($selected); ++$j) {
                    $value = $similarities->get($a, $selected[$j]);
                    if ($best === null || fractionCompare($value, $best) > 0) {
                        $first = $a;
                        $second = $selected[$j];
                        $best = $value;
                    }
                }
            $p[] = "best {$first->name} {$second->name} " . fractionText($best);
        } elseif ($kind === 'NEAREST' || $kind === 'WITHIN') {
            $source = $byName[$args[0]];
            $neighbors = [];
            foreach ($molecules as $m)
                if ($m !== $source)
                    $neighbors[] = [$m, $similarities->get($source, $m)];
            usort($neighbors, fn($a, $b) => fractionCompare($b[1], $a[1]) ?: $a[0]->order <=> $b[0]->order);
            if ($kind === 'NEAREST') {
                $neighbors = array_slice($neighbors, 0, $q['count']);
                $heading = "NEAREST $id {$source->name} count=" . count($neighbors);
            } else {
                $neighbors = array_values(array_filter(
                    $neighbors,
                    fn($r) => fractionCompare($r[1], $q['threshold']) >= 0,
                ));
                $heading =
                    "WITHIN $id {$source->name} threshold="
                    . fractionText($q['threshold'])
                    . ' count='
                    . count($neighbors);
            }
            $p = [$heading];
            foreach ($neighbors as $i => [$m, $value])
                $p[] = ($i + 1) . " {$m->name} " . fractionText($value) . " common={$value[0]}";
        } elseif ($kind === 'COMPARE') {
            $a = $byName[$args[0]];
            $b = $byName[$args[1]];
            $value = $similarities->get($a, $b);
            $p[] =
                "COMPARE $id {$a->name} {$b->name} bits="
                . count($a->bits)
                . ','
                . count($b->bits)
                . " common={$value[0]} union={$value[1]} tanimoto="
                . fractionText($value)
                . ' identical='
                . ($a->canonical === $b->canonical ? 'yes' : 'no');
        } elseif ($kind === 'CLUSTER') {
            $neighbors = [];
            foreach ($molecules as $i => $a) {
                $neighbors[$i] = [];
                foreach ($molecules as $j => $b)
                    if ($i !== $j && fractionCompare($similarities->get($a, $b), $q['threshold']) >= 0)
                        $neighbors[$i][] = $j;
            }
            $order = array_keys($molecules);
            usort($order, fn($a, $b) => count($neighbors[$b]) <=> count($neighbors[$a]) ?: $a <=> $b);
            $assigned = $clusters = [];
            foreach ($order as $center)
                if (!isset($assigned[$center])) {
                    $members = [$center];
                    foreach ($neighbors[$center] as $j)
                        if (!isset($assigned[$j]))
                            $members[] = $j;
                    foreach ($members as $j)
                        $assigned[$j] = true;
                    $clusters[] = $members;
                }
            $singletons = count(array_filter($clusters, fn($r) => count($r) === 1));
            $p = [
                "CLUSTER $id threshold="
                    . fractionText($q['threshold'])
                    . ' clusters='
                    . count($clusters)
                    . " singletons=$singletons",
            ];
            $number = 0;
            foreach ($clusters as $members)
                if (count($members) >= 2) {
                    $selected = array_map(fn($i) => $molecules[$i], $members);
                    $p[] =
                        'cluster '
                        . ++$number
                        . " centroid={$selected[0]->name} size="
                        . count($selected)
                        . ' members='
                        . memberNames($selected);
                }
        } else
            continue;
        $paragraphs[] = $p;
    }
    return $paragraphs;
}

function paragraphsText(array $paragraphs): string
{
    return implode("\n\n", array_map(fn($p) => implode("\n", $p), $paragraphs)) . "\n";
}

function main(): void
{
    $elements = readElements();
    $causes = [];
    [$molecules, $moleculeErrors] = readMolecules($elements, $causes);
    prepareMolecules($molecules);
    $byName = [];
    foreach ($molecules as $m)
        $byName[$m->name] = $m;
    [$queries, $queryErrors] = readQueries($elements, $byName, $causes);
    $causeLines = ['CAUSES kinds=' . count($causes)];
    $reasons = array_keys($causes);
    usort($reasons, fn($a, $b) => $causes[$b] <=> $causes[$a] ?: strcmp($a, $b));
    foreach ($reasons as $reason)
        $causeLines[] = $reason . '=' . $causes[$reason];
    $outputs = [
        'properties.csv' => implode("\n", propertiesLines($molecules)) . "\n",
        'canonical.txt' => paragraphsText(canonicalParagraphs($molecules)),
        'rings.txt' => paragraphsText(ringParagraphs($molecules)),
        'substructure.txt' => paragraphsText(substructureParagraphs($queries, $molecules, $byName)),
        'similarity.txt' => paragraphsText(similarityParagraphs($queries, $molecules, $byName)),
        'errors.txt' => paragraphsText([$moleculeErrors, $queryErrors, $causeLines]),
    ];
    if (!is_dir('output'))
        mkdir('output');
    foreach ($outputs as $name => $text)
        file_put_contents('output/' . $name, $text);
}

main();
