<?php

require_once __DIR__ . '/enrolment.php';
require_once __DIR__ . '/conflict_graph.php';
require_once __DIR__ . '/coloring.php';
require_once __DIR__ . '/rooms.php';
require_once __DIR__ . '/report.php';

const RELATIONS = ['back_to_back', 'same_day', 'overnight'];
const EXCHANGE_VERDICTS = ['fixed', 'invalid', 'worse', 'applied'];
const SWAP_VERDICTS = ['fixed', 'invalid', 'rooms', 'worse', 'applied'];

function read_lines(string $name): array
{
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function ceil_div(int $numerator, int $denominator): int
{
    return intdiv($numerator + $denominator - 1, $denominator);
}

function verdict_counts(array $tally, array $verdicts): string
{
    return implode(' ', array_map(fn($verdict) => $verdict . ' ' . $tally[$verdict], $verdicts));
}

class Calendar
{
    public int $days;
    public array $lengths;
    public int $periods;
    public int $limit;
    public array $weights;
    public int $frontCount;
    public int $deadline;
    public int $ratio;
    public int $slotCount;
    public array $closed = [];
    public array $unavailable = [];
    public array $fixed = [];
    public array $orders = [];
    public array $arrows = [];

    public function __construct(array $lines)
    {
        $settings = array_map(fn($line) => array_map('intval', array_slice(explode(' ', $line), 1)), array_slice($lines, 0, 6));
        $this->days = $settings[0][0];
        $this->lengths = $settings[1];
        $this->periods = count($this->lengths);
        $this->limit = $settings[2][0];
        $this->weights = $settings[3];
        [$this->frontCount, $this->deadline] = $settings[4];
        $this->ratio = $settings[5][0];
        $this->slotCount = $this->days * $this->periods;
    }

    public function slots(): array
    {
        return range(1, $this->slotCount);
    }

    public function slotAt(string $dayText, string $periodText): ?int
    {
        $day = (int) $dayText;
        $period = (int) $periodText;
        return $day >= 1 && $day <= $this->days && $period >= 1 && $period <= $this->periods
            ? ($day - 1) * $this->periods + $period : null;
    }

    public function dayOf(int $slot): int
    {
        return intdiv($slot - 1, $this->periods) + 1;
    }

    public function name(int $slot): string
    {
        return 'D' . $this->dayOf($slot) . 'P' . (($slot - 1) % $this->periods + 1);
    }

    public function length(int $slot): int
    {
        return $this->lengths[($slot - 1) % $this->periods];
    }

    public function relation(int $first, int $second): ?int
    {
        $low = min($first, $second);
        $high = max($first, $second);
        if ($this->dayOf($low) === $this->dayOf($high)) {
            if ($high - $low === 1) {
                return 0;
            }
            if ($high - $low >= 2) {
                return 1;
            }
        } elseif ($high - $low === 1) {
            return 2;
        }
        return null;
    }
}

class Breakdown
{
    public int $total;

    public function __construct(public array $counts, public int $late, array $weights)
    {
        $this->total = $weights[3] * $late;
        foreach ($counts as $relation => $count) {
            $this->total += $weights[$relation] * $count;
        }
    }

    public function text(): string
    {
        return sprintf('back_to_back %d same_day %d overnight %d front_load %d penalty %d',
            $this->counts[0], $this->counts[1], $this->counts[2], $this->late, $this->total);
    }
}

class Scheduler
{
    public int $largestRoom;
    public array $empty = [];
    public array $oversized = [];
    public array $schedulable = [];
    public ConflictGraph $graph;
    public array $edges;
    public array $frontLoad;
    public array $openSlots = [];
    public array $fixedSlots = [];
    public array $assignment = [];
    public int $penalty = 0;
    public array $attempts = [];
    public array $assignmentOrder = [];
    public array $excluded = [];
    public array $insertions = [];
    public array $reasons = [];
    public ?Breakdown $initial = null;
    public ?Breakdown $exchanged = null;
    public array $exchangeLog = [];
    public array $swapLog = [];
    public array $placements = [];
    public array $slotPlacements = [];

    public function __construct(
        public array $courses,
        public array $studentCourses,
        public array $rooms,
        public Calendar $calendar,
        public array $errors
    ) {
        $this->largestRoom = max(array_map(fn($room) => $room->capacity, $rooms));
        $vertices = [];
        foreach (sorted_ids($courses) as $id) {
            $size = $courses[id_key($id)]->size();
            if ($size === 0) {
                $this->empty[] = $id;
            } elseif ($size > $this->largestRoom) {
                $this->oversized[] = $id;
            } else {
                $this->schedulable[] = $id;
            }
            if ($size > 0) {
                $vertices[] = $id;
            }
        }
        $this->graph = new ConflictGraph($vertices, $studentCourses);
        $this->edges = $this->graph->edges();
        $this->frontLoad = array_slice($this->bySize($this->schedulable), 0, $calendar->frontCount);
    }

    public function bySize(array $ids): array
    {
        usort($ids, fn($a, $b) => $this->courses[id_key($b)]->size() <=> $this->courses[id_key($a)]->size() ?: strcmp($a, $b));
        return $ids;
    }

    public function byDegree(array $ids): array
    {
        usort($ids, fn($a, $b) => $this->graph->degree($b) <=> $this->graph->degree($a) ?: strcmp($a, $b));
        return $ids;
    }

    public function blockedStudents(Course $course, int $slot): array
    {
        return array_values(array_filter($course->students,
            fn($student) => isset($this->calendar->unavailable[id_key($student)][$slot])));
    }

    public function suitable(Course $course, int $slot): bool
    {
        return $this->calendar->length($slot) >= $course->duration && !$this->blockedStudents($course, $slot);
    }

    public function packs(array $ids): bool
    {
        return pack_courses($this->rooms, array_map(fn($id) => $this->courses[id_key($id)], $ids)) !== null;
    }

    public function outside(string $day, string $period): string
    {
        return "slot $day $period outside calendar";
    }

    public function validateCalendar(array $lines): void
    {
        $handlers = ['closed' => 'acceptClosed', 'unavailable' => 'acceptUnavailable', 'fixed' => 'acceptFixed', 'after' => 'acceptAfter'];
        foreach (array_slice($lines, 6) as $index => $line) {
            $fields = explode(' ', $line);
            $kind = array_shift($fields);
            $message = $this->{$handlers[$kind]}($fields);
            if ($message !== null) {
                $this->errors[] = 'calendar.txt line ' . ($index + 7) . ': ' . $message;
            }
        }
        $this->openSlots = array_values(array_filter($this->calendar->slots(), fn($slot) => !isset($this->calendar->closed[$slot])));
        $this->fixedSlots = array_fill_keys(array_values($this->calendar->fixed), true);
    }

    public function acceptClosed(array $fields): ?string
    {
        [$day, $period] = $fields;
        $slot = $this->calendar->slotAt($day, $period);
        if ($slot === null) {
            return $this->outside($day, $period);
        }
        if (isset($this->calendar->closed[$slot])) {
            return 'duplicate closed ' . $this->calendar->name($slot);
        }
        $this->calendar->closed[$slot] = true;
        return null;
    }

    public function acceptUnavailable(array $fields): ?string
    {
        [$student, $day, $period] = $fields;
        $key = id_key($student);
        if (!isset($this->studentCourses[$key])) {
            return "unknown student $student";
        }
        $slot = $this->calendar->slotAt($day, $period);
        if ($slot === null) {
            return $this->outside($day, $period);
        }
        if (isset($this->calendar->unavailable[$key][$slot])) {
            return "duplicate unavailable $student " . $this->calendar->name($slot);
        }
        $this->calendar->unavailable[$key][$slot] = true;
        return null;
    }

    public function acceptFixed(array $fields): ?string
    {
        [$id, $day, $period] = $fields;
        $key = id_key($id);
        if (!isset($this->courses[$key])) {
            return "unknown course $id";
        }
        if (!in_array($id, $this->schedulable, true)) {
            return "course $id not schedulable";
        }
        $slot = $this->calendar->slotAt($day, $period);
        if ($slot === null) {
            return $this->outside($day, $period);
        }
        $name = $this->calendar->name($slot);
        if (isset($this->calendar->closed[$slot])) {
            return "slot $name closed";
        }
        if (!$this->suitable($this->courses[$key], $slot)) {
            return "slot $name unsuitable for $id";
        }
        if (isset($this->calendar->fixed[$key])) {
            return "duplicate fixed $id";
        }
        $group = $this->coursesAt($this->calendar->fixed, $slot);
        $neighbours = $this->graph->neighbours($id);
        foreach ($group as $other) {
            if (isset($neighbours[id_key($other)])) {
                return "conflict $id $other";
            }
        }
        $group[] = $id;
        if (!$this->packs($group)) {
            return "rooms full $name";
        }
        $this->calendar->fixed[$key] = $slot;
        return null;
    }

    public function acceptAfter(array $fields): ?string
    {
        [$later, $earlier] = $fields;
        foreach ($fields as $id) {
            if (!isset($this->courses[id_key($id)])) {
                return "unknown course $id";
            }
        }
        foreach ($fields as $id) {
            if (!in_array($id, $this->schedulable, true)) {
                return "course $id not schedulable";
            }
        }
        if ($later === $earlier) {
            return "bad order $later $earlier";
        }
        if (in_array([$later, $earlier], $this->calendar->orders, true)) {
            return "duplicate order $later $earlier";
        }
        if (reachable($this->calendar->arrows, $earlier, $later)) {
            return "cycle $later $earlier";
        }
        $fixed = $this->calendar->fixed;
        if (isset($fixed[id_key($later)], $fixed[id_key($earlier)]) && $fixed[id_key($later)] <= $fixed[id_key($earlier)]) {
            return "fixed order $later $earlier";
        }
        $this->calendar->orders[] = [$later, $earlier];
        $this->calendar->arrows[id_key($later)][] = $earlier;
        return null;
    }

    public function coursesAt(array $assignment, int $slot): array
    {
        return sorted_ids(array_filter($assignment, fn($other) => $other === $slot));
    }

    public function orderConflicts(string $id, int $slot, array $assignment): array
    {
        $conflicts = [];
        foreach ($this->calendar->orders as [$later, $earlier]) {
            if ($later === $id && isset($assignment[id_key($earlier)]) && $slot <= $assignment[id_key($earlier)]) {
                $conflicts[] = $earlier;
            } elseif ($earlier === $id && isset($assignment[id_key($later)]) && $slot >= $assignment[id_key($later)]) {
                $conflicts[] = $later;
            }
        }
        return $conflicts;
    }

    public function ordersSatisfied(array $assignment): bool
    {
        foreach ($this->calendar->orders as [$later, $earlier]) {
            if (isset($assignment[id_key($later)], $assignment[id_key($earlier)])
                && $assignment[id_key($later)] <= $assignment[id_key($earlier)]) {
                return false;
            }
        }
        return true;
    }

    public function candidateSlots(string $id, array $assignment): array
    {
        $candidates = [];
        foreach ($this->openSlots as $slot) {
            if (!$this->suitable($this->courses[id_key($id)], $slot)) {
                continue;
            }
            foreach ($this->graph->neighbours($id) as $key => $shared) {
                if (($assignment[$key] ?? null) === $slot) {
                    continue 2;
                }
            }
            if ($this->orderConflicts($id, $slot, $assignment)) {
                continue;
            }
            if ($this->packs([...$this->coursesAt($assignment, $slot), $id])) {
                $candidates[] = $slot;
            }
        }
        return $candidates;
    }

    public function buildTimetable(): void
    {
        while (true) {
            $pending = array_values(array_filter($this->schedulable,
                fn($id) => !isset($this->calendar->fixed[id_key($id)]) && !in_array($id, $this->excluded, true)));
            $assignment = $this->calendar->fixed;
            $attempt = new Attempt($pending, $this->graph, $this->calendar->limit,
                fn($id, $trial) => $this->candidateSlots($id, $trial));
            $succeeded = $attempt->search($assignment);
            $failedCourse = $succeeded ? null : $attempt->deadEndCourse;
            $this->attempts[] = [count($pending), $attempt->deadEnds, $failedCourse];
            if ($succeeded) {
                break;
            }
            $this->excluded[] = $failedCourse;
        }
        $this->assignment = $assignment;
        foreach ($attempt->chosen as [$id, $saturation]) {
            $this->assignmentOrder[] = [$id, $assignment[id_key($id)], $saturation];
        }
    }

    public function penaltyPairs(array $assignment): array
    {
        $pairs = [];
        foreach ($this->edges as [$first, $second, $shared]) {
            if (isset($assignment[id_key($first)], $assignment[id_key($second)])) {
                $relation = $this->calendar->relation($assignment[id_key($first)], $assignment[id_key($second)]);
                if ($relation !== null) {
                    $pairs[] = [$first, $second, $relation, $shared];
                }
            }
        }
        return $pairs;
    }

    public function lateCourses(array $assignment): array
    {
        return array_values(array_filter($this->frontLoad,
            fn($id) => isset($assignment[id_key($id)]) && $assignment[id_key($id)] > $this->calendar->deadline));
    }

    public function breakdown(array $assignment): Breakdown
    {
        $counts = [0, 0, 0];
        foreach ($this->penaltyPairs($assignment) as [$first, $second, $relation, $shared]) {
            $counts[$relation] += $shared;
        }
        return new Breakdown($counts, count($this->lateCourses($assignment)), $this->calendar->weights);
    }

    public function contributions(): array
    {
        $result = array_fill_keys(array_keys($this->assignment), 0);
        foreach ($this->penaltyPairs($this->assignment) as [$first, $second, $relation, $shared]) {
            $amount = $this->calendar->weights[$relation] * $shared;
            $result[id_key($first)] += $amount;
            $result[id_key($second)] += $amount;
        }
        foreach ($this->lateCourses($this->assignment) as $id) {
            $result[id_key($id)] += $this->calendar->weights[3];
        }
        return $result;
    }

    public function blockingReason(string $id, int $slot): string
    {
        $course = $this->courses[id_key($id)];
        if (isset($this->calendar->closed[$slot])) {
            return 'closed';
        }
        if ($this->calendar->length($slot) < $course->duration) {
            return 'too_short';
        }
        $blocked = $this->blockedStudents($course, $slot);
        if ($blocked) {
            return 'unavailable ' . $blocked[0];
        }
        $clashes = [];
        foreach ($this->graph->neighbours($id) as $key => $shared) {
            if (($this->assignment[$key] ?? null) === $slot) {
                $clashes[] = [substr($key, 1), $shared];
            }
        }
        if ($clashes) {
            usort($clashes, fn($a, $b) => $b[1] <=> $a[1] ?: strcmp($a[0], $b[0]));
            return 'conflict ' . $clashes[0][0] . ' shared ' . $clashes[0][1];
        }
        $conflicts = $this->orderConflicts($id, $slot, $this->assignment);
        if ($conflicts) {
            sort($conflicts, SORT_STRING);
            return 'order ' . $conflicts[0];
        }
        return 'rooms';
    }

    public function insertExcluded(): void
    {
        $excluded = $this->excluded;
        sort($excluded, SORT_STRING);
        foreach ($excluded as $id) {
            $slots = $this->candidateSlots($id, $this->assignment);
            if (!$slots) {
                $this->reasons[id_key($id)] = array_map(fn($slot) => $this->blockingReason($id, $slot), $this->calendar->slots());
                continue;
            }
            $before = $this->breakdown($this->assignment)->total;
            $best = null;
            $total = null;
            foreach ($slots as $slot) {
                $trial = $this->assignment;
                $trial[id_key($id)] = $slot;
                $value = $this->breakdown($trial)->total;
                if ($best === null || $value < $total) {
                    $best = $slot;
                    $total = $value;
                }
            }
            $this->assignment[id_key($id)] = $best;
            $this->insertions[] = [$id, $best, $total - $before];
        }
        $this->initial = $this->breakdown($this->assignment);
        $this->penalty = $this->initial->total;
    }

    public function unscheduled(): array
    {
        $missing = array_values(array_filter($this->excluded, fn($id) => !isset($this->assignment[id_key($id)])));
        $result = array_merge($missing, $this->oversized);
        sort($result, SORT_STRING);
        return $result;
    }

    public function validTrial(array $trial, array $moved): bool
    {
        foreach ($moved as $id) {
            if (!$this->suitable($this->courses[id_key($id)], $trial[id_key($id)])) {
                return false;
            }
        }
        return $this->ordersSatisfied($trial);
    }

    public function movedCourses(array $trial): array
    {
        return sorted_ids(array_filter($trial, fn($slot, $key) => $slot !== $this->assignment[$key], ARRAY_FILTER_USE_BOTH));
    }

    public function exchangeTrial(int $first, int $second): array
    {
        if (isset($this->fixedSlots[$first]) || isset($this->fixedSlots[$second])) {
            return ['fixed', null, null];
        }
        $trial = $this->assignment;
        foreach ($this->assignment as $key => $slot) {
            if ($slot === $first) {
                $trial[$key] = $second;
            } elseif ($slot === $second) {
                $trial[$key] = $first;
            }
        }
        if (!$this->validTrial($trial, $this->movedCourses($trial))) {
            return ['invalid', null, null];
        }
        $total = $this->breakdown($trial)->total;
        if ($total >= $this->penalty) {
            return ['worse', null, null];
        }
        return ['applied', $trial, $total];
    }

    public function exchangeSlots(): void
    {
        $round = 0;
        $serial = 0;
        while (true) {
            $round++;
            $tally = array_fill_keys(EXCHANGE_VERDICTS, 0);
            $records = [];
            $pairs = 0;
            foreach ($this->openSlots as $index => $first) {
                foreach (array_slice($this->openSlots, $index + 1) as $second) {
                    $pairs++;
                    [$verdict, $trial, $total] = $this->exchangeTrial($first, $second);
                    $tally[$verdict]++;
                    if ($verdict === 'applied') {
                        $serial++;
                        $records[] = sprintf('EXCHANGE %d %s %s penalty %d -> %d', $serial,
                            $this->calendar->name($first), $this->calendar->name($second), $this->penalty, $total);
                        $this->assignment = $trial;
                        $this->penalty = $total;
                    }
                }
            }
            $this->exchangeLog[] = "ROUND $round pairs $pairs " . verdict_counts($tally, EXCHANGE_VERDICTS);
            array_push($this->exchangeLog, ...$records);
            if ($tally['applied'] === 0) {
                break;
            }
        }
        $this->exchanged = $this->breakdown($this->assignment);
    }

    public function swapTrial(string $id, int $home, int $target): array
    {
        $chain = $this->graph->kempeChain($this->assignment, $id, $home, $target);
        foreach ($chain as $member) {
            if (isset($this->calendar->fixed[id_key($member)])) {
                return ['fixed', null, null];
            }
        }
        $trial = $this->assignment;
        foreach ($chain as $member) {
            $key = id_key($member);
            $trial[$key] = $this->assignment[$key] === $home ? $target : $home;
        }
        if (!$this->validTrial($trial, $chain)) {
            return ['invalid', null, null];
        }
        if (!$this->packs($this->coursesAt($trial, $home)) || !$this->packs($this->coursesAt($trial, $target))) {
            return ['rooms', null, null];
        }
        $total = $this->breakdown($trial)->total;
        if ($total >= $this->penalty) {
            return ['worse', null, null];
        }
        return ['applied', $trial, $total];
    }

    public function swapChains(): void
    {
        $pass = 0;
        $serial = 0;
        while (true) {
            $pass++;
            $tally = array_fill_keys(SWAP_VERDICTS, 0);
            $records = [];
            $candidates = 0;
            $movable = array_values(array_filter(sorted_ids($this->assignment), fn($id) => !isset($this->calendar->fixed[id_key($id)])));
            foreach ($movable as $id) {
                $home = $this->assignment[id_key($id)];
                foreach ($this->openSlots as $target) {
                    if ($target === $home) {
                        continue;
                    }
                    $candidates++;
                    [$verdict, $trial, $total] = $this->swapTrial($id, $home, $target);
                    $tally[$verdict]++;
                    if ($verdict !== 'applied') {
                        continue;
                    }
                    $serial++;
                    $chain = $this->movedCourses($trial);
                    $records[] = sprintf('SWAP %d %s %s %s chain %d penalty %d -> %d', $serial,
                        $id, $this->calendar->name($home), $this->calendar->name($target), count($chain), $this->penalty, $total);
                    foreach ($chain as $member) {
                        $key = id_key($member);
                        $records[] = sprintf('  MOVE %s %s -> %s', $member,
                            $this->calendar->name($this->assignment[$key]), $this->calendar->name($trial[$key]));
                    }
                    $this->assignment = $trial;
                    $this->penalty = $total;
                    break;
                }
            }
            $this->swapLog[] = "PASS $pass candidates $candidates " . verdict_counts($tally, SWAP_VERDICTS);
            array_push($this->swapLog, ...$records);
            if ($tally['applied'] === 0) {
                break;
            }
        }
    }

    public function assignRooms(): void
    {
        foreach ($this->openSlots as $slot) {
            $group = array_map(fn($id) => $this->courses[id_key($id)], $this->coursesAt($this->assignment, $slot));
            $placements = pack_courses($this->rooms, $group);
            $this->slotPlacements[$slot] = $placements;
            foreach ($placements as $placement) {
                $this->placements[id_key($placement->course->id)] = $placement;
            }
        }
    }

    public function roomGroups(int $slot): array
    {
        $groups = [];
        foreach ($this->rooms as $room) {
            $placed = array_values(array_filter($this->slotPlacements[$slot], fn($placement) => $placement->room === $room));
            if ($placed) {
                $groups[] = [$room, $placed];
            }
        }
        return $groups;
    }

    public function invigilators(int $slot): int
    {
        $total = 0;
        foreach ($this->roomGroups($slot) as [$room, $placed]) {
            $total += ceil_div(array_sum(array_map(fn($p) => $p->course->size(), $placed)), $this->calendar->ratio);
        }
        return $total;
    }

    public function slotLoad(int $slot): array
    {
        $ids = $this->coursesAt($this->assignment, $slot);
        return [count($ids), array_sum(array_map(fn($id) => $this->courses[id_key($id)]->size(), $ids))];
    }

    public function studentAssignments(string $student): array
    {
        $assigned = [];
        foreach ($this->studentCourses[id_key($student)] as $id) {
            if (isset($this->assignment[id_key($id)])) {
                $assigned[] = [$this->assignment[id_key($id)], $id];
            }
        }
        usort($assigned, fn($a, $b) => $a[0] <=> $b[0] ?: strcmp($a[1], $b[1]));
        return $assigned;
    }

    public function studentPairs(string $student): array
    {
        $assigned = $this->studentAssignments($student);
        $pairs = [];
        foreach ($assigned as $index => [$lowSlot, $lowCourse]) {
            foreach (array_slice($assigned, $index + 1) as [$highSlot, $highCourse]) {
                $relation = $this->calendar->relation($lowSlot, $highSlot);
                if ($relation !== null) {
                    $pairs[] = [$relation, $lowSlot, $lowCourse, $highSlot, $highCourse];
                }
            }
        }
        return $pairs;
    }

    public function studentPenalty(string $student): array
    {
        $counts = [0, 0, 0];
        foreach ($this->studentPairs($student) as [$relation, $lowSlot, $lowCourse, $highSlot, $highCourse]) {
            $counts[$relation]++;
        }
        $penalty = 0;
        foreach ($counts as $relation => $count) {
            $penalty += $this->calendar->weights[$relation] * $count;
        }
        return [$counts, $penalty];
    }

    public function timetableLines(): array
    {
        $calendar = $this->calendar;
        $lines = [sprintf('TIMETABLE days %d periods %d open %d courses %d scheduled %d unscheduled %d empty %d',
            $calendar->days, $calendar->periods, count($this->openSlots), count($this->courses), count($this->assignment),
            count($this->unscheduled()), count($this->empty))];
        $header = array_map(fn($period) => 'P' . $period, range(1, $calendar->periods));
        $header[] = 'TOTAL';
        $lines[] = fixed_width_line('DAY', $header, 4, 10);
        for ($day = 1; $day <= $calendar->days; $day++) {
            $cells = [];
            $dayExams = 0;
            $dayStudents = 0;
            for ($period = 1; $period <= $calendar->periods; $period++) {
                $slot = ($day - 1) * $calendar->periods + $period;
                if (isset($calendar->closed[$slot])) {
                    $cells[] = 'closed';
                    continue;
                }
                [$exams, $students] = $this->slotLoad($slot);
                $cells[] = "$exams/$students";
                $dayExams += $exams;
                $dayStudents += $students;
            }
            $cells[] = "$dayExams/$dayStudents";
            $lines[] = fixed_width_line('D' . $day, $cells, 4, 10);
        }
        foreach ($calendar->slots() as $slot) {
            $prefix = sprintf('SLOT %d %s minutes %d', $slot, $calendar->name($slot), $calendar->length($slot));
            if (isset($calendar->closed[$slot])) {
                $lines[] = $prefix . ' closed';
                continue;
            }
            [$exams, $students] = $this->slotLoad($slot);
            $groups = $this->roomGroups($slot);
            $seats = array_sum(array_map(fn($group) => $group[0]->capacity, $groups));
            $lines[] = sprintf('%s exams %d students %d rooms %d seats %d invigilators %d',
                $prefix, $exams, $students, count($groups), $seats, $this->invigilators($slot));
            foreach ($this->slotPlacements[$slot] as $placement) {
                $course = $placement->course;
                $marker = isset($calendar->fixed[id_key($course->id)]) ? ' fixed' : '';
                $lines[] = sprintf('  %s %dmin students %d room %s seats %d-%d%s %s',
                    $course->id, $course->duration, $course->size(), $placement->room->id,
                    $placement->firstSeat, $placement->lastSeat, $marker, $course->name);
            }
        }
        foreach ($this->rooms as $room) {
            $slotsUsed = 0;
            $exams = 0;
            $seated = 0;
            foreach ($this->openSlots as $slot) {
                foreach ($this->roomGroups($slot) as [$groupRoom, $placed]) {
                    if ($groupRoom === $room) {
                        $slotsUsed++;
                        $exams += count($placed);
                        $seated += array_sum(array_map(fn($p) => $p->course->size(), $placed));
                    }
                }
            }
            $utilization = rounded_percent($seated, $room->capacity * count($this->openSlots));
            $lines[] = sprintf('ROOM %s capacity %d slots %d exams %d seated %d utilization %d',
                $room->id, $room->capacity, $slotsUsed, $exams, $seated, $utilization);
        }
        $total = array_sum(array_map(fn($slot) => $this->invigilators($slot), $this->openSlots));
        $lines[] = "INVIGILATORS total $total ratio $calendar->ratio";
        return $lines;
    }

    public function roomLines(): array
    {
        $lines = ['slot,room,course,students,first_seat,last_seat'];
        foreach ($this->openSlots as $slot) {
            foreach ($this->roomGroups($slot) as [$room, $placed]) {
                foreach ($placed as $placement) {
                    $lines[] = implode(',', [$this->calendar->name($slot), $room->id, $placement->course->id,
                        $placement->course->size(), $placement->firstSeat, $placement->lastSeat]);
                }
            }
        }
        return $lines;
    }

    public function studentStatistics(): array
    {
        $histogram = [];
        $gaps = [];
        $dayLoads = [];
        $ranking = [];
        foreach (sorted_ids($this->studentCourses) as $student) {
            [$counts, $penalty] = $this->studentPenalty($student);
            $histogram[$penalty] = ($histogram[$penalty] ?? 0) + 1;
            $ranking[] = [$student, $penalty, $counts];
            $assigned = $this->studentAssignments($student);
            for ($index = 1; $index < count($assigned); $index++) {
                $gap = $assigned[$index][0] - $assigned[$index - 1][0];
                $gaps[$gap] = ($gaps[$gap] ?? 0) + 1;
            }
            if ($assigned) {
                $perDay = [];
                foreach ($assigned as [$slot, $id]) {
                    $day = $this->calendar->dayOf($slot);
                    $perDay[$day] = ($perDay[$day] ?? 0) + 1;
                }
                $maximum = max($perDay);
                $dayLoads[$maximum] = ($dayLoads[$maximum] ?? 0) + 1;
            }
        }
        ksort($histogram, SORT_NUMERIC);
        ksort($gaps, SORT_NUMERIC);
        ksort($dayLoads, SORT_NUMERIC);
        $lines = [];
        foreach ($histogram as $value => $frequency) {
            $lines[] = "HISTOGRAM $value $frequency";
        }
        foreach ($gaps as $value => $frequency) {
            $lines[] = "GAP $value $frequency";
        }
        foreach ($dayLoads as $value => $frequency) {
            $lines[] = "DAYLOAD $value $frequency";
        }
        usort($ranking, fn($a, $b) => $b[1] <=> $a[1] ?: strcmp($a[0], $b[0]));
        foreach (array_slice($ranking, 0, 5) as [$student, $penalty, $counts]) {
            if ($penalty > 0) {
                $lines[] = sprintf('WORST %s penalty %d back_to_back %d same_day %d overnight %d',
                    $student, $penalty, $counts[0], $counts[1], $counts[2]);
            }
        }
        return $lines;
    }

    public function penaltyLines(): array
    {
        $calendar = $this->calendar;
        $weights = $calendar->weights;
        $final = $this->breakdown($this->assignment);
        $lines = [
            sprintf('WEIGHTS back_to_back %d same_day %d overnight %d front_load %d', $weights[0], $weights[1], $weights[2], $weights[3]),
            'FRONT_LOAD courses ' . count($this->frontLoad) . ' last_slot ' . $calendar->name($calendar->deadline),
            'INITIAL ' . $this->initial->text(),
        ];
        array_push($lines, ...$this->exchangeLog);
        $lines[] = 'EXCHANGED ' . $this->exchanged->text();
        array_push($lines, ...$this->swapLog);
        $lines[] = 'FINAL ' . $final->text();
        $lines[] = 'SAVED ' . ($this->initial->total - $final->total);
        $daily = array_fill(1, $calendar->days, [0, 0, 0]);
        foreach ($this->penaltyPairs($this->assignment) as [$first, $second, $relation, $shared]) {
            $day = $calendar->dayOf(min($this->assignment[id_key($first)], $this->assignment[id_key($second)]));
            $daily[$day][$relation] += $shared;
        }
        foreach ($daily as $day => $counts) {
            $lines[] = sprintf('DAY D%d back_to_back %d same_day %d overnight %d', $day, $counts[0], $counts[1], $counts[2]);
        }
        foreach ($this->lateCourses($this->assignment) as $id) {
            $lines[] = sprintf('LATE %s %s students %d', $id, $calendar->name($this->assignment[id_key($id)]), $this->courses[id_key($id)]->size());
        }
        $contributions = $this->contributions();
        $ranked = sorted_ids($contributions);
        usort($ranked, fn($a, $b) => $contributions[id_key($b)] <=> $contributions[id_key($a)] ?: strcmp($a, $b));
        foreach (array_slice($ranked, 0, 10) as $id) {
            if ($contributions[id_key($id)] > 0) {
                $lines[] = sprintf('COURSE %s %s penalty %d', $id, $calendar->name($this->assignment[id_key($id)]), $contributions[id_key($id)]);
            }
        }
        array_push($lines, ...$this->studentStatistics());
        return $lines;
    }

    public function scheduleLines(array $queries): array
    {
        $lines = [];
        foreach ($queries as $student) {
            $studentKey = id_key($student);
            if (!isset($this->studentCourses[$studentKey])) {
                $lines[] = "STUDENT $student not found";
                continue;
            }
            $ids = $this->studentCourses[$studentKey];
            $assigned = $this->studentAssignments($student);
            [$counts, $penalty] = $this->studentPenalty($student);
            $lines[] = sprintf('STUDENT %s exams %d scheduled %d penalty %d', $student, count($ids), count($assigned), $penalty);
            foreach ($assigned as [$slot, $id]) {
                $placement = $this->placements[id_key($id)];
                $course = $placement->course;
                $seat = $placement->firstSeat + array_search($student, $course->students, true);
                $lines[] = sprintf('  %s %s room %s seat %d %s', $this->calendar->name($slot),
                    $id, $placement->room->id, $seat, $course->name);
            }
            foreach ($ids as $id) {
                if (!isset($this->assignment[id_key($id)])) {
                    $lines[] = '  UNSCHEDULED ' . $id . ' ' . $this->courses[id_key($id)]->name;
                }
            }
            foreach ($this->studentPairs($student) as [$relation, $lowSlot, $lowCourse, $highSlot, $highCourse]) {
                $lines[] = sprintf('  %s %s %s %s %s', strtoupper(RELATIONS[$relation]),
                    $this->calendar->name($lowSlot), $lowCourse, $this->calendar->name($highSlot), $highCourse);
            }
            $blocked = array_keys($this->calendar->unavailable[$studentKey] ?? []);
            sort($blocked, SORT_NUMERIC);
            foreach ($blocked as $slot) {
                $lines[] = '  UNAVAILABLE ' . $this->calendar->name($slot);
            }
        }
        return $lines;
    }

    public function statusLines(): array
    {
        $contributions = $this->contributions();
        $lines = ['course,status,slot,students,minutes,degree,penalty'];
        foreach (sorted_ids($this->courses) as $id) {
            $key = id_key($id);
            $course = $this->courses[$key];
            if (isset($this->calendar->fixed[$key])) {
                $status = 'fixed';
            } elseif (isset($this->assignment[$key])) {
                $status = 'scheduled';
            } elseif (in_array($id, $this->oversized, true)) {
                $status = 'too_large';
            } elseif (in_array($id, $this->empty, true)) {
                $status = 'empty';
            } else {
                $status = 'no_slot';
            }
            $slot = isset($this->assignment[$key]) ? $this->calendar->name($this->assignment[$key]) : '-';
            $lines[] = implode(',', [$id, $status, $slot, $course->size(), $course->duration,
                $this->graph->degree($id), $contributions[$key] ?? 0]);
        }
        return $lines;
    }

    public function graphLines(): array
    {
        $graph = $this->graph;
        $vertices = count($graph->vertices);
        $edgeCount = count($this->edges);
        $shared = array_sum(array_column($this->edges, 2));
        $density = $vertices >= 2 ? intdiv(2000 * $edgeCount, $vertices * ($vertices - 1)) : 0;
        $lines = ["GRAPH courses $vertices edges $edgeCount shared $shared density $density"];
        foreach (array_slice($this->byDegree($graph->vertices), 0, 5) as $id) {
            $lines[] = sprintf('DEGREE %s neighbours %d shared %d students %d', $id,
                $graph->degree($id), $graph->sharedTotal($id), $this->courses[id_key($id)]->size());
        }
        $components = $graph->components();
        $lines[] = 'COMPONENTS ' . count($components);
        foreach ($components as $index => $component) {
            $lines[] = sprintf('COMPONENT %d size %d first %s', $index + 1, count($component), $component[0]);
        }
        $clique = $graph->greedyClique($this->schedulable);
        $lines[] = implode(' ', ['CLIQUE', 'size', count($clique), ...$clique]);
        return $lines;
    }

    public function capacityLines(): array
    {
        $loads = array_map('count', $this->studentCourses);
        $most = max($loads);
        $attaining = count(array_filter($loads, fn($load) => $load === $most));
        $demand = array_sum(array_map(fn($id) => $this->courses[id_key($id)]->size(), $this->schedulable));
        $capacity = array_sum(array_map(fn($room) => $room->capacity, $this->rooms));
        $degreeSlots = greedy_numbering($this->byDegree($this->schedulable), $this->graph);
        $sizeSlots = greedy_numbering($this->bySize($this->schedulable), $this->graph);
        $lines = [
            "LOAD max_exams $most students $attaining",
            "SEATS demand $demand capacity $capacity min_slots " . ceil_div($demand, $capacity),
            "HEURISTIC largest_degree slots $degreeSlots",
            "HEURISTIC largest_enrolment slots $sizeSlots",
        ];
        $table = array_slice($this->bySize($this->graph->vertices), 0, 8);
        $lines[] = fixed_width_line('MATRIX', $table, 9, 9);
        foreach ($table as $row) {
            $neighbours = $this->graph->neighbours($row);
            $cells = array_map(fn($column) => $column === $row ? '-' : (string) ($neighbours[id_key($column)] ?? 0), $table);
            $lines[] = fixed_width_line($row, $cells, 9, 9);
        }
        return $lines;
    }

    public function reportLines(): array
    {
        $calendar = $this->calendar;
        $enrolments = array_sum(array_map('count', $this->studentCourses));
        $lines = [sprintf('INPUT courses %d enrolments %d rooms %d students %d errors %d', count($this->courses),
            $enrolments, count($this->rooms), count($this->studentCourses), count($this->errors))];
        foreach ($this->errors as $error) {
            $lines[] = 'ERROR ' . $error;
        }
        array_push($lines, ...$this->graphLines());
        array_push($lines, ...$this->capacityLines());
        foreach ($this->empty as $id) {
            $lines[] = 'EMPTY ' . $id;
        }
        foreach ($this->oversized as $id) {
            $lines[] = sprintf('TOO_LARGE %s students %d largest_room %d', $id, $this->courses[id_key($id)]->size(), $this->largestRoom);
        }
        $closed = array_keys($calendar->closed);
        sort($closed, SORT_NUMERIC);
        foreach ($closed as $slot) {
            $lines[] = 'CLOSED ' . $calendar->name($slot);
        }
        foreach (sorted_ids($calendar->fixed) as $id) {
            $lines[] = 'FIXED ' . $id . ' ' . $calendar->name($calendar->fixed[id_key($id)]);
        }
        foreach ($calendar->orders as [$later, $earlier]) {
            $lines[] = "AFTER $later $earlier";
        }
        foreach ($this->attempts as $index => [$size, $deadEnds, $failedCourse]) {
            $result = $failedCourse === null ? 'success' : 'failed ' . $failedCourse;
            $lines[] = sprintf('ATTEMPT %d courses %d backtracks %d %s', $index + 1, $size, $deadEnds, $result);
        }
        foreach ($this->assignmentOrder as $index => [$id, $slot, $saturation]) {
            $lines[] = sprintf('ORDER %d %s %s saturation %d degree %d', $index + 1, $id,
                $calendar->name($slot), $saturation, $this->graph->degree($id));
        }
        foreach ($this->insertions as [$id, $slot, $increase]) {
            $lines[] = sprintf('INSERTED %s %s penalty %d', $id, $calendar->name($slot), $increase);
        }
        $unscheduled = $this->unscheduled();
        foreach ($unscheduled as $id) {
            $reason = in_array($id, $this->oversized, true) ? 'too_large' : 'no_slot';
            $lines[] = sprintf('UNSCHEDULED %s reason %s students %d', $id, $reason, $this->courses[id_key($id)]->size());
            foreach ($this->reasons[id_key($id)] ?? [] as $index => $slotReason) {
                $lines[] = '  ' . $calendar->name($index + 1) . ' ' . $slotReason;
            }
        }
        $slotsUsed = count(array_unique(array_values($this->assignment), SORT_NUMERIC));
        $lines[] = sprintf('SUMMARY scheduled %d unscheduled %d slots_used %d penalty %d', count($this->assignment),
            count($unscheduled), $slotsUsed, $this->penalty);
        return $lines;
    }
}

function main(): void
{
    $errors = [];
    $courses = load_courses('input/courses.csv', $errors);
    $studentCourses = load_enrolments('input/enrolments.csv', $courses, $errors);
    $rooms = load_rooms('input/rooms.csv', $errors);
    $calendarLines = read_lines('calendar.txt');
    $scheduler = new Scheduler($courses, $studentCourses, $rooms, new Calendar($calendarLines), $errors);
    $scheduler->validateCalendar($calendarLines);
    $scheduler->buildTimetable();
    $scheduler->insertExcluded();
    $scheduler->exchangeSlots();
    $scheduler->swapChains();
    $scheduler->assignRooms();
    $queries = read_lines('queries.txt');
    write_files('output', [
        'timetable.txt' => $scheduler->timetableLines(),
        'rooms.csv' => $scheduler->roomLines(),
        'penalties.txt' => $scheduler->penaltyLines(),
        'student_schedules.txt' => $scheduler->scheduleLines($queries),
        'course_status.csv' => $scheduler->statusLines(),
        'report.txt' => $scheduler->reportLines(),
    ]);
}

main();
