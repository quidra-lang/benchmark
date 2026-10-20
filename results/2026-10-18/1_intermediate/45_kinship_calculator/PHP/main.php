<?php
declare(strict_types=1);

const SCALE = 137438953472;
const SEX_INDEX = ['M' => 0, 'F' => 1, 'X' => 2];
const ORDINALS = ['first', 'second', 'third', 'fourth', 'fifth',
    'sixth', 'seventh', 'eighth', 'ninth', 'tenth'];
const TERMS = [
    'parent' => ['father', 'mother', 'parent'],
    'child' => ['son', 'daughter', 'child'],
    'sibling' => ['brother', 'sister', 'sibling'],
    'pibling' => ['uncle', 'aunt', 'pibling'],
    'nibling' => ['nephew', 'niece', 'nibling'],
    'spouse' => ['husband', 'wife', 'spouse'],
    'late' => ['late husband', 'late wife', 'late spouse'],
    'survivor' => ['widower', 'widow', 'surviving spouse'],
    'ex' => ['ex-husband', 'ex-wife', 'ex-spouse'],
    'stepparent' => ['stepfather', 'stepmother', 'stepparent'],
    'stepchild' => ['stepson', 'stepdaughter', 'stepchild'],
    'stepsibling' => ['stepbrother', 'stepsister', 'stepsibling'],
    'stepgrandparent' => ['stepgrandfather', 'stepgrandmother', 'stepgrandparent'],
    'stepgrandchild' => ['stepgrandson', 'stepgranddaughter', 'stepgrandchild'],
    'parent-in-law' => ['father-in-law', 'mother-in-law', 'parent-in-law'],
    'child-in-law' => ['son-in-law', 'daughter-in-law', 'child-in-law'],
    'sibling-in-law' => ['brother-in-law', 'sister-in-law', 'sibling-in-law'],
];
const STEPS = [
    'parent' => ['parent', null], 'father' => ['parent', 'M'], 'mother' => ['parent', 'F'],
    'child' => ['child', null], 'son' => ['child', 'M'], 'daughter' => ['child', 'F'],
    'sibling' => ['sibling', null], 'brother' => ['sibling', 'M'], 'sister' => ['sibling', 'F'],
    'spouse' => ['spouse', null], 'husband' => ['spouse', 'M'], 'wife' => ['spouse', 'F'],
];
const MODIFYING = ['PERSON', 'DEATH', 'REMOVE', 'PARENT', 'UNPARENT', 'SPOUSE', 'DIVORCE'];

class CommandError extends RuntimeException {}

function gendered(string $kind, string $sex): string
{
    return TERMS[$kind][SEX_INDEX[$sex]];
}

function generationPrefix(int $g): string
{
    return $g === 1 ? '' : str_repeat('great-', $g - 2) . 'grand';
}

function ordinal(int $number): string
{
    if ($number <= 10) {
        return ORDINALS[$number - 1];
    }
    $suffix = in_array($number % 100, [11, 12, 13], true)
        ? 'th' : ([1 => 'st', 2 => 'nd', 3 => 'rd'][$number % 10] ?? 'th');
    return $number . $suffix;
}

function kinshipTerm(int $da, int $db, string $sex): string
{
    if ($da === 0 && $db === 0) {
        return 'self';
    }
    if ($da === 0) {
        return generationPrefix($db) . gendered('parent', $sex);
    }
    if ($db === 0) {
        return generationPrefix($da) . gendered('child', $sex);
    }
    if ($da === 1 && $db === 1) {
        return gendered('sibling', $sex);
    }
    if ($da === 1) {
        return generationPrefix($db - 1) . gendered('pibling', $sex);
    }
    if ($db === 1) {
        return generationPrefix($da - 1) . gendered('nibling', $sex);
    }
    $distance = abs($da - $db);
    $removal = match ($distance) {
        0 => '', 1 => ' once removed', 2 => ' twice removed',
        default => " $distance times removed",
    };
    return ordinal(min($da, $db) - 1) . ' cousin' . $removal;
}

function bloodTerm(array $apex, string $sex): string
{
    $prefix = $apex['shares'] === 1 ? 'half-' : ($apex['shares'] >= 4 ? 'double ' : '');
    return $prefix . kinshipTerm($apex['da'], $apex['db'], $sex);
}

function lifeYears(array $person): string
{
    return $person['birth'] . '-' . ($person['death'] ?? '');
}

function fractionText(int $value): string
{
    $a = $value;
    $b = SCALE;
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return intdiv($value, $a) . '/' . intdiv(SCALE, $a);
}

function containsPerson(array $record, string $id): bool
{
    return $record['first'] === $id || $record['second'] === $id;
}

function otherPerson(array $record, string $id): string
{
    return $record['first'] === $id ? $record['second'] : $record['first'];
}

class Family
{
    public array $persons = [];
    public array $marriages = [];
    private array $distances = [];
    private array $children = [];
    private array $partners = [];
    private array $coefficients = [];

    public function resetCache(): void
    {
        $this->distances = [];
        $this->children = [];
        $this->partners = [];
        $this->coefficients = [];
    }

    public function person(string $id): array
    {
        if (!isset($this->persons[$id])) {
            throw new CommandError("UNKNOWN PERSON $id");
        }
        return $this->persons[$id];
    }

    public function sex(string $id): string
    {
        return $this->persons[$id]['sex'];
    }

    public function ageCompare(string $a, string $b): int
    {
        return ($this->persons[$a]['birth'] <=> $this->persons[$b]['birth']) ?: strcmp($a, $b);
    }

    public function ageOrder(array $ids): array
    {
        usort($ids, $this->ageCompare(...));
        return $ids;
    }

    public function personList(array $ids): string
    {
        return $ids === [] ? '-' : implode(' ', $this->ageOrder($ids));
    }

    public function parents(string $id): array
    {
        return $this->persons[$id]['parents'];
    }

    public function children(string $id): array
    {
        return $this->children[$id] ??= array_values(array_filter(
            array_keys($this->persons), fn($child) => in_array($id, $this->parents($child), true)
        ));
    }

    public function commonParents(string $a, string $b): int
    {
        return count(array_intersect($this->parents($a), $this->parents($b)));
    }

    public function areSiblings(string $a, string $b): bool
    {
        return $a !== $b && $this->commonParents($a, $b) > 0;
    }

    public function siblings(string $id): array
    {
        return array_values(array_filter(array_keys($this->persons), fn($other) => $this->areSiblings($id, $other)));
    }

    public function recordsOf(string $id): array
    {
        return array_values(array_filter($this->marriages, fn($record) => containsPerson($record, $id)));
    }

    public function currentIndex(string $id): ?int
    {
        foreach ($this->marriages as $index => $record) {
            if ($record['status'] === 'current' && containsPerson($record, $id)) {
                return $index;
            }
        }
        return null;
    }

    public function spouse(string $id): ?string
    {
        $index = $this->currentIndex($id);
        return $index === null ? null : otherPerson($this->marriages[$index], $id);
    }

    public function lastRecord(string $a, string $b): ?array
    {
        foreach (array_reverse($this->recordsOf($a)) as $record) {
            if (containsPerson($record, $b)) {
                return $record;
            }
        }
        return null;
    }

    public function partners(string $id): array
    {
        if (!isset($this->partners[$id])) {
            $latest = [];
            foreach ($this->recordsOf($id) as $record) {
                $latest[otherPerson($record, $id)] = $record;
            }
            $this->partners[$id] = array_keys(array_filter($latest, fn($record) => $record['status'] !== 'divorced'));
        }
        return $this->partners[$id];
    }

    public function stepRelated(string $a, string $b): bool
    {
        foreach ($this->parents($a) as $parent) {
            if (array_intersect($this->partners($parent), $this->parents($b)) !== []) {
                return true;
            }
        }
        return false;
    }

    public function distances(string $start, bool $upward): array
    {
        $key = ($upward ? 'up:' : 'down:') . $start;
        if (isset($this->distances[$key])) {
            return $this->distances[$key];
        }
        $distances = [$start => 0];
        $queue = [$start];
        for ($index = 0; $index < count($queue); ++$index) {
            $id = $queue[$index];
            foreach ($upward ? $this->parents($id) : $this->children($id) as $other) {
                if (!isset($distances[$other])) {
                    $distances[$other] = $distances[$id] + 1;
                    $queue[] = $other;
                }
            }
        }
        return $this->distances[$key] = $distances;
    }

    public function lineage(string $id, bool $upward): array
    {
        $entries = [];
        foreach ($this->distances($id, $upward) as $other => $distance) {
            if ($other !== $id) {
                $entries[] = [$distance, $other];
            }
        }
        usort($entries, fn($a, $b) => ($a[0] <=> $b[0]) ?: strcmp($a[1], $b[1]));
        return $entries;
    }

    public function ancestor(string $a, string $b): bool
    {
        return $a !== $b && isset($this->distances($b, true)[$a]);
    }

    public function grandparents(string $id): array
    {
        return array_keys(array_filter($this->distances($id, true), fn($distance) => $distance === 2));
    }

    public function apex(string $a, string $b): ?array
    {
        $upA = $this->distances($a, true);
        $upB = $this->distances($b, true);
        if (isset($upB[$a])) {
            return ['person' => $a, 'da' => 0, 'db' => $upB[$a], 'shares' => 0];
        }
        if (isset($upA[$b])) {
            return ['person' => $b, 'da' => $upA[$b], 'db' => 0, 'shares' => 0];
        }
        $common = array_keys(array_intersect_key($upA, $upB));
        if ($common === []) {
            return null;
        }
        usort($common, fn($c, $d) => (($upA[$c] + $upB[$c]) <=> ($upA[$d] + $upB[$d]))
            ?: ($upA[$c] <=> $upA[$d]) ?: strcmp($c, $d));
        $chosen = $common[0];
        $da = $upA[$chosen];
        $db = $upB[$chosen];
        $shares = count(array_filter($common, fn($id) => $upA[$id] === $da && $upB[$id] === $db));
        return ['person' => $chosen, 'da' => $da, 'db' => $db, 'shares' => $shares];
    }

    public function relationship(string $a, string $b, ?string $sex = null): array
    {
        if ($a === $b) {
            return ['self'];
        }
        $sex ??= $this->sex($a);
        $terms = [];
        $apex = $this->apex($a, $b);
        if ($apex !== null) {
            $terms[] = bloodTerm($apex, $sex);
        }
        $record = $this->lastRecord($a, $b);
        if ($record === null) {
            foreach ($this->persons as $person) {
                if (in_array($a, $person['parents'], true) && in_array($b, $person['parents'], true)) {
                    $terms[] = 'co-parent';
                    break;
                }
            }
        } elseif ($record['status'] === 'current') {
            $terms[] = gendered('spouse', $sex);
        } elseif ($record['status'] === 'widowed') {
            $terms[] = gendered($record['died'] === $a ? 'late' : 'survivor', $sex);
        } else {
            $terms[] = gendered('ex', $sex);
        }
        $pa = $this->parents($a);
        $pb = $this->parents($b);
        $qa = $this->partners($a);
        $qb = $this->partners($b);
        if (!in_array($a, $pb, true) && array_intersect($qa, $pb) !== []) {
            $terms[] = gendered('stepparent', $sex);
        }
        if (!in_array($b, $pa, true) && array_intersect($qb, $pa) !== []) {
            $terms[] = gendered('stepchild', $sex);
        }
        if ($this->commonParents($a, $b) === 0 && $this->stepRelated($a, $b)) {
            $terms[] = gendered('stepsibling', $sex);
        }
        if (!$this->ancestor($a, $b) && array_intersect($qa, $this->grandparents($b)) !== []) {
            $terms[] = gendered('stepgrandparent', $sex);
        }
        if (!$this->ancestor($b, $a) && array_intersect($qb, $this->grandparents($a)) !== []) {
            $terms[] = gendered('stepgrandchild', $sex);
        }
        if (array_any($qb, fn($partner) => in_array($a, $this->parents($partner), true))) {
            $terms[] = gendered('parent-in-law', $sex);
        }
        if (array_any($qa, fn($partner) => in_array($b, $this->parents($partner), true))) {
            $terms[] = gendered('child-in-law', $sex);
        }
        if (array_any($qb, fn($partner) => $this->areSiblings($a, $partner))
            || array_any($qa, fn($partner) => $this->areSiblings($partner, $b))) {
            $terms[] = gendered('sibling-in-law', $sex);
        }
        return $terms;
    }

    public function relationshipText(string $a, string $b): string
    {
        $terms = $this->relationship($a, $b);
        return $terms === [] ? 'no relation' : implode(', ', $terms);
    }

    public function coefficient(string $a, string $b): int
    {
        $key = strcmp($a, $b) <= 0 ? "$a:$b" : "$b:$a";
        if (isset($this->coefficients[$key])) {
            return $this->coefficients[$key];
        }
        if ($a === $b) {
            $value = intdiv(SCALE + $this->inbreeding($a), 2);
        } else {
            [$x, $y] = $this->persons[$a]['birth'] >= $this->persons[$b]['birth'] ? [$a, $b] : [$b, $a];
            $sum = 0;
            foreach ($this->parents($x) as $parent) {
                $sum += $this->coefficient($parent, $y);
            }
            $value = intdiv($sum, 2);
        }
        return $this->coefficients[$key] = $value;
    }

    public function inbreeding(string $id): int
    {
        $parents = $this->parents($id);
        return count($parents) === 2 ? $this->coefficient($parents[0], $parents[1]) : 0;
    }

    public function lineageLength(string $id, array &$memo): int
    {
        if (!isset($memo[$id])) {
            $longest = 0;
            foreach ($this->parents($id) as $parent) {
                $longest = max($longest, $this->lineageLength($parent, $memo));
            }
            $memo[$id] = $longest + 1;
        }
        return $memo[$id];
    }

    public function upwardPath(string $start, string $apex): array
    {
        $path = [$start];
        while (end($path) !== $apex) {
            $current = end($path);
            $distance = $this->distances($current, true)[$apex];
            $candidates = array_values(array_filter($this->parents($current),
                fn($parent) => ($this->distances($parent, true)[$apex] ?? -1) === $distance - 1));
            sort($candidates, SORT_STRING);
            $path[] = $candidates[0];
        }
        return $path;
    }

    public function censusStatus(string $id, int $year): string
    {
        foreach (array_reverse($this->recordsOf($id)) as $record) {
            if ($record['start'] <= $year) {
                return $record['end'] === null || $record['end'] > $year
                    ? 'married ' . otherPerson($record, $id) : $record['status'];
            }
        }
        return 'single';
    }

    public function stepTargets(string $id, string $kind): array
    {
        return match ($kind) {
            'parent' => $this->parents($id), 'child' => $this->children($id),
            'sibling' => $this->siblings($id),
            'spouse' => $this->spouse($id) === null ? [] : [$this->spouse($id)],
        };
    }
}

class KinshipCalculator
{
    private Family $family;
    private array $history = [];

    public function __construct()
    {
        $this->family = new Family();
    }

    private function checked(string ...$ids): void
    {
        foreach ($ids as $id) {
            $this->family->person($id);
        }
    }

    public function execute(string $line): array
    {
        $words = explode(' ', $line);
        $command = array_shift($words);
        $this->family->resetCache();
        $modifying = in_array($command, MODIFYING, true);
        $saved = $modifying ? [$this->family->persons, $this->family->marriages] : null;
        try {
            $lines = $this->process($command, $words);
            if ($modifying) {
                $this->history[] = [$line, $saved];
            }
            return $lines;
        } catch (CommandError $error) {
            return ['ERROR ' . $error->getMessage()];
        }
    }

    private function process(string $command, array $args): array
    {
        switch ($command) {
            case 'PERSON': return $this->addPerson(...$args);
            case 'DEATH': return $this->recordDeath(...$args);
            case 'REMOVE': return $this->removePerson(...$args);
            case 'PARENT': return $this->linkParent(...$args);
            case 'UNPARENT': return $this->unlinkParent(...$args);
            case 'SPOUSE': return $this->marry(...$args);
            case 'DIVORCE': return $this->divorce(...$args);
            case 'UNDO':
                if ($this->history === []) {
                    throw new CommandError('NOTHING TO UNDO');
                }
                [$line, $saved] = array_pop($this->history);
                [$this->family->persons, $this->family->marriages] = $saved;
                return ["UNDONE $line"];
            case 'INFO': return $this->info($args[0]);
            case 'RELATION':
                [$a, $b] = $args;
                $this->checked($a, $b);
                return ["RELATION $a $b: " . $this->family->relationshipText($a, $b)];
            case 'RELATIVES': return $this->relatives($args[0]);
            case 'WHO':
                $id = array_shift($args);
                return $this->who($id, implode(' ', $args));
            case 'PATH': return $this->path(...$args);
            case 'COMMON': return $this->common(...$args);
            case 'ANCESTORS': return $this->lineage($args[0], true);
            case 'DESCENDANTS': return $this->lineage($args[0], false);
            case 'COUSINS': return $this->cousins($args[0], (int)$args[1]);
            case 'SIBLINGS': return $this->siblings($args[0]);
            case 'GENERATIONS': return $this->generations($args[0]);
            case 'TREE': return $this->tree($args[0]);
            case 'PEDIGREE': return $this->pedigree($args[0], (int)$args[1]);
            case 'TIMELINE': return $this->timeline($args[0]);
            case 'CENSUS': return $this->census((int)$args[0]);
            case 'KINSHIP':
                [$a, $b] = $args;
                $this->checked($a, $b);
                return ["KINSHIP $a $b " . fractionText($this->family->coefficient($a, $b))];
            case 'FIND': return $this->find(...$args);
            case 'TERM':
                [$da, $db, $sex] = $args;
                return ["TERM $da $db $sex " . kinshipTerm((int)$da, (int)$db, $sex)];
            case 'STATS': return $this->stats();
            case 'AUDIT': return $this->audit();
        }
        return [];
    }

    private function addPerson(string $id, string $sex, string $birth, string $name): array
    {
        if (isset($this->family->persons[$id])) {
            throw new CommandError("DUPLICATE PERSON $id");
        }
        $this->family->persons[$id] = ['sex' => $sex, 'birth' => (int)$birth,
            'name' => $name, 'death' => null, 'parents' => []];
        return ["ADDED $id $name $sex $birth"];
    }

    private function recordDeath(string $id, string $yearText): array
    {
        $year = (int)$yearText;
        $person = $this->family->person($id);
        if ($person['death'] !== null) {
            throw new CommandError("ALREADY DECEASED $id");
        }
        $years = [$person['birth']];
        foreach ($this->family->recordsOf($id) as $record) {
            $years[] = $record['start'];
            if ($record['end'] !== null) {
                $years[] = $record['end'];
            }
        }
        if ($year < max($years)) {
            throw new CommandError("BAD YEAR $id");
        }
        $late = array_values(array_filter($this->family->children($id),
            fn($child) => $this->family->persons[$child]['birth'] > $year + 1));
        sort($late, SORT_STRING);
        if ($late !== []) {
            throw new CommandError("AFTER DEATH {$late[0]} $id");
        }
        $this->family->persons[$id]['death'] = $year;
        $index = $this->family->currentIndex($id);
        if ($index === null) {
            return ["DIED $id $year"];
        }
        $other = otherPerson($this->family->marriages[$index], $id);
        $this->family->marriages[$index]['end'] = $year;
        $this->family->marriages[$index]['status'] = 'widowed';
        $this->family->marriages[$index]['died'] = $id;
        return ["DIED $id $year spouse=$other"];
    }

    private function removePerson(string $id): array
    {
        $this->checked($id);
        foreach (array_keys($this->family->persons) as $other) {
            $this->family->persons[$other]['parents'] = array_values(array_diff($this->family->parents($other), [$id]));
        }
        $this->family->marriages = array_values(array_filter($this->family->marriages,
            fn($record) => !containsPerson($record, $id)));
        unset($this->family->persons[$id]);
        return ["REMOVED $id"];
    }

    private function linkParent(string $childId, string $parentId): array
    {
        $child = $this->family->person($childId);
        $parent = $this->family->person($parentId);
        if ($childId === $parentId) {
            throw new CommandError("SAME PERSON $childId");
        }
        if (in_array($parentId, $child['parents'], true)) {
            throw new CommandError("ALREADY PARENT $childId $parentId");
        }
        if (count($child['parents']) === 2) {
            throw new CommandError("TOO MANY PARENTS $childId");
        }
        if ($this->family->ancestor($childId, $parentId)) {
            throw new CommandError("CYCLE $childId $parentId");
        }
        if ($parent['birth'] + 12 > $child['birth']) {
            throw new CommandError("AGE GAP $childId $parentId");
        }
        if ($parent['death'] !== null && $parent['death'] + 1 < $child['birth']) {
            throw new CommandError("AFTER DEATH $childId $parentId");
        }
        $this->family->persons[$childId]['parents'][] = $parentId;
        return ["LINKED $childId $parentId " . gendered('parent', $parent['sex'])];
    }

    private function unlinkParent(string $childId, string $parentId): array
    {
        $this->checked($childId, $parentId);
        $parents = $this->family->parents($childId);
        if (!in_array($parentId, $parents, true)) {
            throw new CommandError("NOT PARENT $childId $parentId");
        }
        $this->family->persons[$childId]['parents'] = array_values(array_diff($parents, [$parentId]));
        return ["UNLINKED $childId $parentId"];
    }

    private function marry(string $a, string $b, string $yearText): array
    {
        $this->checked($a, $b);
        $year = (int)$yearText;
        if ($a === $b) {
            throw new CommandError("SAME PERSON $a");
        }
        foreach ([$a, $b] as $id) {
            if ($this->family->persons[$id]['death'] !== null) {
                throw new CommandError("DECEASED $id");
            }
        }
        foreach ([$a, $b] as $id) {
            if ($this->family->spouse($id) !== null) {
                throw new CommandError("ALREADY MARRIED $id");
            }
        }
        if ($this->family->ancestor($a, $b) || $this->family->ancestor($b, $a) || $this->family->areSiblings($a, $b)) {
            throw new CommandError("CLOSE KIN $a $b");
        }
        foreach ([$a, $b] as $id) {
            if ($year < $this->family->persons[$id]['birth'] + 16) {
                throw new CommandError("TOO YOUNG $id");
            }
        }
        foreach ([$a, $b] as $id) {
            if (array_any($this->family->recordsOf($id), fn($record) => $record['end'] !== null && $record['end'] >= $year)) {
                throw new CommandError("BAD YEAR $id");
            }
        }
        $this->family->marriages[] = ['first' => $a, 'second' => $b, 'start' => $year,
            'end' => null, 'status' => 'current', 'died' => null];
        return ["MARRIED $a $b $year"];
    }

    private function divorce(string $a, string $b, string $yearText): array
    {
        $this->checked($a, $b);
        $year = (int)$yearText;
        if ($this->family->spouse($a) !== $b) {
            throw new CommandError("NOT MARRIED $a $b");
        }
        $index = $this->family->currentIndex($a);
        if ($year <= $this->family->marriages[$index]['start']) {
            throw new CommandError("BAD YEAR $a");
        }
        $this->family->marriages[$index]['end'] = $year;
        $this->family->marriages[$index]['status'] = 'divorced';
        return ["DIVORCED $a $b $year"];
    }

    private function info(string $id): array
    {
        $person = $this->family->person($id);
        $lines = ["INFO $id {$person['name']} {$person['sex']} " . lifeYears($person),
            '  parents: ' . $this->family->personList($person['parents'])];
        foreach ($this->family->recordsOf($id) as $record) {
            $lines[] = '  marriage: ' . otherPerson($record, $id) . " {$record['start']}-"
                . ($record['end'] ?? '') . " {$record['status']}";
        }
        $lines[] = '  children: ' . $this->family->personList($this->family->children($id));
        $lines[] = '  siblings: ' . $this->family->personList($this->family->siblings($id));
        $lines[] = '  inbreeding: ' . fractionText($this->family->inbreeding($id));
        return $lines;
    }

    private function relatives(string $id): array
    {
        $this->checked($id);
        $lines = [];
        $ids = array_keys($this->family->persons);
        sort($ids, SORT_STRING);
        foreach ($ids as $other) {
            if ($other === $id) {
                continue;
            }
            $terms = $this->family->relationship($other, $id);
            if ($terms !== []) {
                $lines[] = "  $other: " . implode(', ', $terms);
            }
        }
        return array_merge(["RELATIVES $id " . count($lines)], $lines);
    }

    private function who(string $id, string $query): array
    {
        $this->checked($id);
        $lines = [];
        $ids = array_keys($this->family->persons);
        sort($ids, SORT_STRING);
        foreach ($ids as $other) {
            if ($other === $id) {
                continue;
            }
            $terms = $this->family->relationship($other, $id);
            $neutral = $this->family->relationship($other, $id, 'X');
            foreach ($terms as $index => $term) {
                if ($term === $query || $neutral[$index] === $query) {
                    $lines[] = "  $other: $term";
                    break;
                }
            }
        }
        return array_merge(["WHO $id $query " . count($lines)], $lines);
    }

    private function path(string $a, string $b): array
    {
        $this->checked($a, $b);
        $apex = $this->family->apex($a, $b);
        if ($apex === null) {
            return ["PATH $a $b none"];
        }
        $up = $this->family->upwardPath($a, $apex['person']);
        $down = $this->family->upwardPath($b, $apex['person']);
        array_pop($down);
        $route = array_merge($up, array_reverse($down));
        return ["PATH $a $b " . ($apex['da'] + $apex['db']) . ': ' . implode(' ', $route)];
    }

    private function common(string $a, string $b): array
    {
        $this->checked($a, $b);
        $upA = $this->family->distances($a, true);
        $upB = $this->family->distances($b, true);
        $shared = array_keys(array_intersect_key($upA, $upB));
        $nearest = array_values(array_filter($shared,
            fn($id) => array_intersect($this->family->children($id), $shared) === []));
        usort($nearest, fn($c, $d) => (($upA[$c] + $upB[$c]) <=> ($upA[$d] + $upB[$d])) ?: strcmp($c, $d));
        $lines = array_map(fn($id) => "  $id {$upA[$id]} {$upB[$id]}", $nearest);
        return array_merge(["COMMON $a $b " . count($nearest)], $lines);
    }

    private function lineage(string $id, bool $upward): array
    {
        $this->checked($id);
        $entries = $this->family->lineage($id, $upward);
        $command = $upward ? 'ANCESTORS' : 'DESCENDANTS';
        $lines = ["$command $id " . count($entries)];
        foreach ($entries as [$distance, $other]) {
            [$da, $db] = $upward ? [0, $distance] : [$distance, 0];
            $lines[] = "  $distance $other " . kinshipTerm($da, $db, $this->family->sex($other));
        }
        return $lines;
    }

    private function cousins(string $id, int $degree): array
    {
        $this->checked($id);
        $entries = [];
        foreach (array_keys($this->family->persons) as $other) {
            if ($other === $id) {
                continue;
            }
            $apex = $this->family->apex($other, $id);
            if ($apex !== null && $apex['da'] >= 2 && $apex['db'] >= 2 && min($apex['da'], $apex['db']) - 1 === $degree) {
                $entries[] = [abs($apex['da'] - $apex['db']), $other, bloodTerm($apex, $this->family->sex($other))];
            }
        }
        usort($entries, fn($a, $b) => ($a[0] <=> $b[0]) ?: strcmp($a[1], $b[1]));
        $lines = array_map(fn($entry) => "  {$entry[1]} {$entry[2]}", $entries);
        return array_merge(["COUSINS $id $degree " . count($entries)], $lines);
    }

    private function siblings(string $id): array
    {
        $this->checked($id);
        $lines = [];
        $earlier = 0;
        foreach ($this->family->ageOrder(array_keys($this->family->persons)) as $other) {
            if ($other === $id) {
                continue;
            }
            $shared = $this->family->commonParents($id, $other);
            $kind = $shared === 2 ? 'full' : ($shared === 1 ? 'half' : ($this->family->stepRelated($id, $other) ? 'step' : null));
            if ($kind === null) {
                continue;
            }
            if ($kind !== 'step' && $this->family->ageCompare($other, $id) < 0) {
                ++$earlier;
            }
            $lines[] = "  $other $kind {$this->family->persons[$other]['birth']}";
        }
        return array_merge(["SIBLINGS $id " . count($lines) . ' order=' . ($earlier + 1)], $lines);
    }

    private function generations(string $id): array
    {
        $this->checked($id);
        $groups = [];
        foreach ($this->family->lineage($id, false) as [$distance, $other]) {
            $groups[$distance][] = $this->family->persons[$other];
        }
        ksort($groups, SORT_NUMERIC);
        $lines = ["GENERATIONS $id " . count($groups)];
        foreach ($groups as $distance => $people) {
            $births = array_column($people, 'birth');
            $living = count(array_filter($people, fn($person) => $person['death'] === null));
            $lines[] = "  $distance " . count($people) . " $living " . min($births) . '-' . max($births);
        }
        return $lines;
    }

    private function tree(string $id): array
    {
        $this->checked($id);
        $lines = ["TREE $id " . count($this->family->lineage($id, false))];
        $visited = [];
        $this->visit($id, 0, $lines, $visited);
        return $lines;
    }

    private function visit(string $id, int $depth, array &$lines, array &$visited): void
    {
        $indent = str_repeat('  ', $depth + 1);
        if (isset($visited[$id])) {
            $lines[] = "$indent$id (see above)";
            return;
        }
        $visited[$id] = true;
        $person = $this->family->persons[$id];
        $line = "$indent$id {$person['name']} " . lifeYears($person);
        $spouse = $this->family->spouse($id);
        if ($spouse !== null) {
            $line .= " = $spouse";
        }
        $lines[] = $line;
        foreach ($this->family->ageOrder($this->family->children($id)) as $child) {
            $this->visit($child, $depth + 1, $lines, $visited);
        }
    }

    private function pedigree(string $id, int $depth): array
    {
        $this->checked($id);
        $lines = [];
        $entered = [];
        $this->enter($id, 1, 0, $depth, $lines, $entered);
        return array_merge(["PEDIGREE $id $depth entries=" . count($lines) . ' distinct=' . count($entered)], $lines);
    }

    private function enter(string $id, int $number, int $generation, int $depth, array &$lines, array &$entered): void
    {
        $person = $this->family->persons[$id];
        $lines[] = str_repeat('  ', $generation + 1) . "$number $id {$person['name']} " . lifeYears($person);
        $entered[$id] = true;
        if ($generation >= $depth) {
            return;
        }
        $parents = $person['parents'];
        usort($parents, fn($a, $b) => (SEX_INDEX[$this->family->sex($a)] <=> SEX_INDEX[$this->family->sex($b)]) ?: strcmp($a, $b));
        foreach ($parents as $index => $parent) {
            $this->enter($parent, 2 * $number + $index, $generation + 1, $depth, $lines, $entered);
        }
    }

    private function timeline(string $id): array
    {
        $person = $this->family->person($id);
        $events = [[$person['birth'], 0, '', 'born']];
        foreach ($this->family->recordsOf($id) as $record) {
            $other = otherPerson($record, $id);
            $events[] = [$record['start'], 1, $other, "married $other"];
            if ($record['status'] === 'divorced') {
                $events[] = [$record['end'], 3, $other, "divorced $other"];
            } elseif ($record['status'] === 'widowed' && $record['died'] === $other) {
                $events[] = [$record['end'], 4, $other, "widowed $other"];
            }
        }
        $children = $this->family->children($id);
        foreach ($children as $child) {
            $events[] = [$this->family->persons[$child]['birth'], 2, $child, "child $child"];
        }
        foreach (['parent' => $person['parents'], 'child' => $children] as $label => $relatives) {
            foreach ($relatives as $other) {
                $death = $this->family->persons[$other]['death'];
                if ($death !== null && $death >= $person['birth'] && ($person['death'] === null || $death <= $person['death'])) {
                    $events[] = [$death, 5, $other, "lost $label $other"];
                }
            }
        }
        if ($person['death'] !== null) {
            $events[] = [$person['death'], 6, '', 'died'];
        }
        usort($events, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]) ?: strcmp($a[2], $b[2]));
        $lines = array_map(fn($event) => "  {$event[0]} {$event[3]}", $events);
        return array_merge(["TIMELINE $id " . count($events)], $lines);
    }

    private function census(int $year): array
    {
        $residents = array_values(array_filter(array_keys($this->family->persons), function ($id) use ($year) {
            $person = $this->family->persons[$id];
            return $person['birth'] <= $year && ($person['death'] === null || $person['death'] > $year);
        }));
        $lines = ["CENSUS $year " . count($residents)];
        foreach ($this->family->ageOrder($residents) as $id) {
            $lines[] = "  $id " . ($year - $this->family->persons[$id]['birth']) . ' ' . $this->family->censusStatus($id, $year);
        }
        return $lines;
    }

    private function find(string $id, string $route): array
    {
        $this->checked($id);
        $current = [$id];
        foreach (explode('.', $route) as $step) {
            [$kind, $sex] = STEPS[$step];
            $collected = [];
            foreach ($current as $other) {
                foreach ($this->family->stepTargets($other, $kind) as $target) {
                    if ($sex === null || $this->family->sex($target) === $sex) {
                        $collected[$target] = true;
                    }
                }
            }
            $current = array_keys($collected);
        }
        $current = array_values(array_diff($current, [$id]));
        sort($current, SORT_STRING);
        $lines = array_map(fn($other) => "  $other: " . $this->family->relationshipText($other, $id), $current);
        return array_merge(["FIND $id $route " . count($current)], $lines);
    }

    private function stats(): array
    {
        $living = 0;
        $links = 0;
        $founders = 0;
        $longest = 0;
        $memo = [];
        foreach ($this->family->persons as $id => $person) {
            $living += (int)($person['death'] === null);
            $links += count($person['parents']);
            $founders += (int)($person['parents'] === []);
            $longest = max($longest, $this->family->lineageLength($id, $memo));
        }
        $couples = count(array_filter($this->family->marriages, fn($record) => $record['status'] === 'current'));
        $persons = count($this->family->persons);
        return ["STATS persons=$persons living=$living links=$links couples=$couples founders=$founders generations=$longest"];
    }

    private function audit(): array
    {
        $lines = [];
        foreach ($this->family->marriages as $record) {
            $apex = $this->family->apex($record['first'], $record['second']);
            if ($apex !== null) {
                $lines[] = "  marriage {$record['first']} {$record['second']} "
                    . bloodTerm($apex, $this->family->sex($record['first']));
            }
        }
        $ids = array_keys($this->family->persons);
        sort($ids, SORT_STRING);
        foreach ($ids as $id) {
            $coefficient = $this->family->inbreeding($id);
            if ($coefficient !== 0) {
                $lines[] = "  inbred $id " . fractionText($coefficient);
            }
        }
        return array_merge(['AUDIT ' . count($lines)], $lines);
    }
}

$calculator = new KinshipCalculator();
$count = (int)fgets(STDIN);
for ($index = 0; $index < $count; ++$index) {
    $line = rtrim(fgets(STDIN), "\r\n");
    foreach ($calculator->execute($line) as $output) {
        echo $output, "\n";
    }
}
