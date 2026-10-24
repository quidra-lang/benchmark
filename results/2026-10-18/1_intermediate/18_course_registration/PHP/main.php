<?php

declare(strict_types=1);

const DAYS = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const GRADE_POINTS = ['A' => 4, 'B' => 3, 'C' => 2, 'D' => 1, 'F' => 0];

final class CommandError extends RuntimeException {}

function timeText(int $minutes): string
{
    return sprintf('%02d:%02d', intdiv($minutes, 60), $minutes % 60);
}

function rateText(int $enrolled, int $capacity): string
{
    return $capacity > 0 ? intdiv(100 * $enrolled, $capacity) . '%' : 'n/a';
}

function overlapping(array $first, array $second): bool
{
    return $first['day'] === $second['day']
        && $first['start'] < $second['end']
        && $second['start'] < $first['end'];
}

function weeklyTime(Course $course): int
{
    $minutes = 0;
    foreach ($course->slots as $slot) {
        $minutes += $slot['end'] - $slot['start'];
    }
    return $minutes;
}

function parseSlots(string $timetable): array
{
    if ($timetable === '-') {
        return [];
    }

    $slots = [];
    foreach (explode(',', $timetable) as $raw) {
        $day = substr($raw, 0, 2);
        $startHour = (int) substr($raw, 2, 2);
        $startMinute = (int) substr($raw, 4, 2);
        $endHour = (int) substr($raw, 7, 2);
        $endMinute = (int) substr($raw, 9, 2);
        $start = $startHour * 60 + $startMinute;
        $end = $endHour * 60 + $endMinute;
        if (!in_array($day, DAYS, true)
            || $startHour > 23 || $startMinute > 59
            || $endHour > 23 || $endMinute > 59 || $start >= $end) {
            throw new CommandError("invalid slot $raw");
        }
        $slots[] = ['day' => $day, 'start' => $start, 'end' => $end, 'raw' => $raw];
    }

    for ($i = 0; $i < count($slots); ++$i) {
        for ($j = $i + 1; $j < count($slots); ++$j) {
            if (overlapping($slots[$i], $slots[$j])) {
                throw new CommandError(
                    'overlapping slots ' . $slots[$i]['raw'] . ' ' . $slots[$j]['raw']
                );
            }
        }
    }
    return $slots;
}

function combineNode(string $kind, array $nodes): array
{
    $children = [];
    foreach ($nodes as $node) {
        if ($node['kind'] === $kind) {
            foreach ($node['children'] as $child) {
                $children[] = $child;
            }
        } else {
            $children[] = $node;
        }
    }
    return count($children) === 1
        ? $children[0]
        : ['kind' => $kind, 'children' => $children, 'word' => ''];
}

function canonical(?array $node): string
{
    if ($node === null) {
        return '-';
    }
    if ($node['kind'] === 'leaf') {
        return $node['word'];
    }
    $parts = [];
    foreach ($node['children'] as $child) {
        $value = canonical($child);
        if ($node['kind'] === 'and' && $child['kind'] === 'or') {
            $value = '(' . $value . ')';
        }
        $parts[] = $value;
    }
    return implode($node['kind'] === 'and' ? '&' : '|', $parts);
}

function containsCondition(?array $node, string $code): bool
{
    if ($node === null) {
        return false;
    }
    if ($node['kind'] === 'leaf') {
        return $node['word'] === $code;
    }
    foreach ($node['children'] as $child) {
        if (containsCondition($child, $code)) {
            return true;
        }
    }
    return false;
}

final class PrerequisiteParser
{
    private array $tokens;
    private int $position = 0;
    private string $course;

    public function __construct(string $course, string $text)
    {
        $this->course = $course;
        preg_match_all('/[A-Z0-9]+|[&|()]/', $text, $matches);
        $this->tokens = $matches[0];
        if (implode('', $this->tokens) !== $text) {
            $this->invalid();
        }
        foreach ($this->tokens as $token) {
            if (in_array($token, ['&', '|', '(', ')'], true)) {
                continue;
            }
            if (!preg_match('/^(?:[A-Z]{2,4}[0-9]{3}|Y[1-9])$/D', $token)) {
                $this->invalid();
            }
        }
    }

    private function invalid(): never
    {
        throw new CommandError('invalid prereq ' . $this->course);
    }

    private function peek(): ?string
    {
        return $this->tokens[$this->position] ?? null;
    }

    private function factor(): array
    {
        $token = $this->peek();
        ++$this->position;
        if ($token === '(') {
            $inner = $this->expression();
            if ($this->peek() !== ')') {
                $this->invalid();
            }
            ++$this->position;
            return $inner;
        }
        if ($token === null || in_array($token, ['&', '|', ')'], true)) {
            $this->invalid();
        }
        return ['kind' => 'leaf', 'word' => $token, 'children' => []];
    }

    private function term(): array
    {
        $nodes = [$this->factor()];
        while ($this->peek() === '&') {
            ++$this->position;
            $nodes[] = $this->factor();
        }
        return combineNode('and', $nodes);
    }

    private function expression(): array
    {
        $nodes = [$this->term()];
        while ($this->peek() === '|') {
            ++$this->position;
            $nodes[] = $this->term();
        }
        return combineNode('or', $nodes);
    }

    public function parse(): array
    {
        $node = $this->expression();
        if ($this->position !== count($this->tokens)) {
            $this->invalid();
        }
        if (containsCondition($node, $this->course)) {
            throw new CommandError('self prereq ' . $this->course);
        }
        return $node;
    }
}

function prerequisite(string $course, string $text): ?array
{
    return $text === '-' ? null : (new PrerequisiteParser($course, $text))->parse();
}

final class Course
{
    public bool $open = true;
    public array $enrolled = [];
    public array $waiting = [];

    public function __construct(
        public string $code,
        public int $credits,
        public int $capacity,
        public array $slots,
        public ?array $prerequisite
    ) {}

    public function status(): string
    {
        return $this->open ? 'open' : 'closed';
    }

    public function department(): string
    {
        return substr($this->code, 0, -3);
    }
}

final class Student
{
    public array $taking = [];
    public array $history = [];

    public function __construct(
        public string $id,
        public int $year,
        public int $limit,
        public array $grades
    ) {}

    public function passed(string $code): ?string
    {
        foreach ($this->grades as $record) {
            if ($record['code'] === $code && in_array($record['grade'], ['A', 'B', 'C'], true)) {
                return $record['grade'];
            }
        }
        return null;
    }

    public function earned(): int
    {
        $credits = 0;
        foreach ($this->grades as $record) {
            if ($record['grade'] !== 'F') {
                $credits += $record['credits'];
            }
        }
        return $credits;
    }

    public function gpa(): string
    {
        if (!$this->grades) {
            return 'n/a';
        }
        $points = 0;
        $credits = 0;
        foreach ($this->grades as $record) {
            $points += GRADE_POINTS[$record['grade']] * $record['credits'];
            $credits += $record['credits'];
        }
        $hundredths = intdiv(200 * $points + $credits, 2 * $credits);
        return sprintf('%d.%02d', intdiv($hundredths, 100), $hundredths % 100);
    }
}

function satisfies(?array $node, Student $student): bool
{
    if ($node === null) {
        return true;
    }
    if ($node['kind'] === 'leaf') {
        $word = $node['word'];
        if (preg_match('/^Y[1-9]$/D', $word)) {
            return $student->year >= (int) substr($word, 1);
        }
        return $student->passed($word) !== null;
    }
    if ($node['kind'] === 'and') {
        foreach ($node['children'] as $child) {
            if (!satisfies($child, $student)) {
                return false;
            }
        }
        return true;
    }
    foreach ($node['children'] as $child) {
        if (satisfies($child, $student)) {
            return true;
        }
    }
    return false;
}

final class Registrar
{
    private array $courses = [];
    private array $students = [];
    private array $output = [];
    private int $commandNumber = 0;

    private function emit(int $indent, string|int ...$parts): void
    {
        $this->output[] = str_repeat(' ', $indent) . implode(' ', $parts);
    }

    private function student(string $id): Student
    {
        if (!isset($this->students[$id])) {
            throw new CommandError('unknown student ' . $id);
        }
        return $this->students[$id];
    }

    private function course(string $code): Course
    {
        if (!isset($this->courses[$code])) {
            throw new CommandError('unknown course ' . $code);
        }
        return $this->courses[$code];
    }

    private function sortedCourses(): array
    {
        $courses = $this->courses;
        ksort($courses, SORT_STRING);
        return array_values($courses);
    }

    private function taking(Student $student, ?string $excluded = null): array
    {
        $codes = array_keys($student->taking);
        sort($codes, SORT_STRING);
        $result = [];
        foreach ($codes as $code) {
            if ($code !== $excluded) {
                $result[] = $this->courses[$code];
            }
        }
        return $result;
    }

    private function credits(Student $student, ?string $excluded = null): int
    {
        $result = 0;
        foreach ($this->taking($student, $excluded) as $course) {
            $result += $course->credits;
        }
        return $result;
    }

    private function waitlists(Student $student): array
    {
        $result = [];
        foreach ($this->sortedCourses() as $course) {
            if (in_array($student->id, $course->waiting, true)) {
                $result[] = $course;
            }
        }
        return $result;
    }

    private function conflict(Student $student, Course $target, ?string $excluded = null): ?Course
    {
        foreach ($this->taking($student, $excluded) as $course) {
            foreach ($course->slots as $first) {
                foreach ($target->slots as $second) {
                    if (overlapping($first, $second)) {
                        return $course;
                    }
                }
            }
        }
        return null;
    }

    private function eligible(Student $student, Course $course, ?string $excluded = null): array
    {
        if (!$course->open) {
            return ['course closed', []];
        }
        if (isset($course->enrolled[$student->id])) {
            return ['already enrolled', []];
        }
        if (in_array($student->id, $course->waiting, true)) {
            return ['already waitlisted', []];
        }
        $grade = $student->passed($course->code);
        if ($grade !== null) {
            return ['already completed', [$grade]];
        }
        if (!satisfies($course->prerequisite, $student)) {
            return ['prereq not met', []];
        }
        $conflicting = $this->conflict($student, $course, $excluded);
        if ($conflicting !== null) {
            return ['time conflict', [$conflicting->code]];
        }
        $credits = $this->credits($student, $excluded) + $course->credits;
        if ($credits > $student->limit) {
            return ['credit limit', [$credits, $student->limit]];
        }
        return ['OK', []];
    }

    private function waitPosition(Student $student, Course $course): int
    {
        $count = 0;
        foreach ($course->waiting as $id) {
            if ($this->students[$id]->year >= $student->year) {
                ++$count;
            }
        }
        return $count + 1;
    }

    private function judgment(Student $student, Course $course): array
    {
        [$word, $extra] = $this->eligible($student, $course);
        if ($word !== 'OK') {
            return [$word, $extra];
        }
        if (count($course->enrolled) < $course->capacity) {
            return ['enroll', []];
        }
        if (count($this->waitlists($student)) >= 3) {
            return ['waitlist limit', []];
        }
        return ['waitlist', [$this->waitPosition($student, $course)]];
    }

    private function record(Student $student, string $event): void
    {
        $student->history[] = [$this->commandNumber, $event];
    }

    private function reject(Student $student, Course $course, array $judgment): never
    {
        [$word, $extra] = $judgment;
        $parts = array_merge([$word, $student->id, $course->code], $extra);
        throw new CommandError(implode(' ', $parts));
    }

    private function enroll(Student $student, Course $course): void
    {
        $course->enrolled[$student->id] = true;
        $student->taking[$course->code] = true;
    }

    private function withdraw(Student $student, Course $course): void
    {
        unset($course->enrolled[$student->id], $student->taking[$course->code]);
    }

    private function enrollmentLine(string $label, Student $student, Course $course, int $indent = 0): void
    {
        $this->emit($indent, $label, $student->id, $course->code,
            'enrolled', count($course->enrolled) . '/' . $course->capacity,
            'credits', $this->credits($student) . '/' . $student->limit);
    }

    private function promote(): void
    {
        foreach ($this->sortedCourses() as $course) {
            if (!$course->open) {
                continue;
            }
            while (count($course->enrolled) < $course->capacity) {
                $selected = null;
                foreach ($course->waiting as $index => $id) {
                    $student = $this->students[$id];
                    if ($this->conflict($student, $course) === null
                        && $this->credits($student) + $course->credits <= $student->limit) {
                        $selected = $index;
                        break;
                    }
                }
                if ($selected === null) {
                    break;
                }
                $id = $course->waiting[$selected];
                array_splice($course->waiting, $selected, 1);
                $student = $this->students[$id];
                $this->enroll($student, $course);
                $this->record($student, 'promote ' . $course->code);
                $this->enrollmentLine('PROMOTE', $student, $course, 2);
            }
        }
    }

    private function schedule(Student $student): void
    {
        $taking = $this->taking($student);
        $weekly = 0;
        foreach ($taking as $course) {
            $weekly += weeklyTime($course);
        }
        $this->emit(0, 'SCHEDULE', $student->id, 'courses', count($taking),
            'credits', $this->credits($student), 'weekly', timeText($weekly));

        foreach (DAYS as $day) {
            $meetings = [];
            foreach ($taking as $course) {
                foreach ($course->slots as $slot) {
                    if ($slot['day'] === $day) {
                        $meetings[] = ['slot' => $slot, 'code' => $course->code];
                    }
                }
            }
            usort($meetings, static fn(array $a, array $b): int =>
                $a['slot']['start'] <=> $b['slot']['start']);
            if (!$meetings) {
                continue;
            }
            $parts = [$day];
            foreach ($meetings as $meeting) {
                $slot = $meeting['slot'];
                $parts[] = timeText($slot['start']) . '-' . timeText($slot['end']);
                $parts[] = $meeting['code'];
            }
            $this->emit(2, ...$parts);
        }
        $tba = [];
        foreach ($taking as $course) {
            if (!$course->slots) {
                $tba[] = $course->code;
            }
        }
        if ($tba) {
            $this->emit(2, 'TBA', ...$tba);
        }
    }

    private function command(string $command, array $a): void
    {
        switch ($command) {
            case 'COURSE':
                if (isset($this->courses[$a[0]])) {
                    throw new CommandError('duplicate course ' . $a[0]);
                }
                $slots = parseSlots($a[3]);
                $tree = prerequisite($a[0], $a[4]);
                $course = new Course($a[0], (int) $a[1], (int) $a[2], $slots, $tree);
                $this->courses[$course->code] = $course;
                $this->emit(0, 'COURSE', $course->code, 'credits', $course->credits,
                    'capacity', $course->capacity, 'meetings', count($slots),
                    'weekly', timeText(weeklyTime($course)), 'prereq', canonical($tree));
                return;

            case 'STUDENT':
                if (isset($this->students[$a[0]])) {
                    throw new CommandError('duplicate student ' . $a[0]);
                }
                $grades = [];
                $seen = [];
                foreach ($a[3] === '-' ? [] : explode(',', $a[3]) as $token) {
                    [$code, $grade, $credits] = explode(':', $token);
                    if (!array_key_exists($grade, GRADE_POINTS)) {
                        throw new CommandError("invalid grade $a[0] $code $grade");
                    }
                    if (isset($seen[$code])) {
                        throw new CommandError("duplicate record $a[0] $code");
                    }
                    $seen[$code] = true;
                    $grades[] = ['code' => $code, 'grade' => $grade, 'credits' => (int) $credits];
                }
                $student = new Student($a[0], (int) $a[1], (int) $a[2], $grades);
                $this->students[$student->id] = $student;
                $this->emit(0, 'STUDENT', $student->id, 'year', $student->year,
                    'limit', $student->limit, 'records', count($grades),
                    'earned', $student->earned(), 'gpa', $student->gpa());
                return;

            case 'ENROLL':
            case 'CHECK':
                $student = $this->student($a[0]);
                $course = $this->course($a[1]);
                $decision = $this->judgment($student, $course);
                [$word, $extra] = $decision;
                if ($command === 'CHECK') {
                    $this->emit(0, 'CHECK', $student->id, $course->code, $word, ...$extra);
                } elseif ($word === 'enroll') {
                    $this->enroll($student, $course);
                    $this->record($student, 'enroll ' . $course->code);
                    $this->enrollmentLine('ENROLL', $student, $course);
                } elseif ($word === 'waitlist') {
                    $position = (int) $extra[0];
                    array_splice($course->waiting, $position - 1, 0, [$student->id]);
                    $this->record($student, 'waitlist ' . $course->code . ' ' . $position);
                    $this->emit(0, 'ENROLL', $student->id, $course->code, 'waitlist', $position);
                } else {
                    $this->reject($student, $course, $decision);
                }
                return;

            case 'OPTIONS':
                $student = $this->student($a[0]);
                $this->emit(0, 'OPTIONS', $student->id, 'courses', count($this->courses));
                foreach ($this->sortedCourses() as $course) {
                    [$word, $extra] = $this->judgment($student, $course);
                    $this->emit(2, $course->code, $word, ...$extra);
                }
                return;

            case 'DROP':
                $student = $this->student($a[0]);
                $course = $this->course($a[1]);
                $position = array_search($student->id, $course->waiting, true);
                if (isset($course->enrolled[$student->id])) {
                    $this->withdraw($student, $course);
                    $this->record($student, 'drop ' . $course->code);
                    $this->enrollmentLine('DROP', $student, $course);
                } elseif ($position !== false) {
                    array_splice($course->waiting, $position, 1);
                    $this->record($student, 'drop ' . $course->code . ' waitlist');
                    $this->emit(0, 'DROP', $student->id, $course->code, 'waitlist', 'removed');
                } else {
                    throw new CommandError("not registered $student->id $course->code");
                }
                $this->promote();
                return;

            case 'SWAP':
                $student = $this->student($a[0]);
                $old = $this->course($a[1]);
                $next = $this->course($a[2]);
                if (!isset($old->enrolled[$student->id])) {
                    throw new CommandError("not enrolled $student->id $old->code");
                }
                if ($old === $next) {
                    throw new CommandError('same course ' . $old->code);
                }
                $decision = $this->eligible($student, $next, $old->code);
                if ($decision[0] !== 'OK') {
                    $this->reject($student, $next, $decision);
                }
                if (count($next->enrolled) >= $next->capacity) {
                    throw new CommandError('course full ' . $next->code);
                }
                $this->withdraw($student, $old);
                $this->enroll($student, $next);
                $this->record($student, 'swap ' . $old->code . ' ' . $next->code);
                $this->emit(0, 'SWAP', $student->id, $old->code, '->', $next->code,
                    'credits', $this->credits($student) . '/' . $student->limit);
                $this->promote();
                return;

            case 'CLOSE':
            case 'OPEN':
                $course = $this->course($a[0]);
                if ($course->open === ($command === 'OPEN')) {
                    throw new CommandError('already ' . ($command === 'OPEN' ? 'open ' : 'closed ') . $course->code);
                }
                $course->open = $command === 'OPEN';
                $this->emit(0, $command, $course->code, 'enrolled',
                    count($course->enrolled) . '/' . $course->capacity,
                    'waitlist', count($course->waiting));
                if ($command === 'OPEN') {
                    $this->promote();
                }
                return;

            case 'CAPACITY':
                $course = $this->course($a[0]);
                $capacity = (int) $a[1];
                if ($capacity < count($course->enrolled)) {
                    throw new CommandError(
                        'capacity below enrollment ' . $course->code . ' ' . count($course->enrolled)
                    );
                }
                $previous = $course->capacity;
                $course->capacity = $capacity;
                $this->emit(0, 'CAPACITY', $course->code, $previous, '->', $capacity);
                $this->promote();
                return;

            case 'LIMIT':
                $student = $this->student($a[0]);
                $limit = (int) $a[1];
                $credits = $this->credits($student);
                if ($limit < $credits) {
                    throw new CommandError("limit below enrolled $student->id $credits");
                }
                $previous = $student->limit;
                $student->limit = $limit;
                $this->emit(0, 'LIMIT', $student->id, $previous, '->', $limit);
                $this->promote();
                return;

            case 'PREREQ':
                $course = $this->course($a[0]);
                $tree = prerequisite($course->code, $a[1]);
                $course->prerequisite = $tree;
                $this->emit(0, 'PREREQ', $course->code, canonical($tree));
                $remaining = [];
                foreach ($course->waiting as $id) {
                    $student = $this->students[$id];
                    if (satisfies($tree, $student)) {
                        $remaining[] = $id;
                    } else {
                        $this->record($student, 'unlist ' . $course->code);
                        $this->emit(2, 'UNLIST', $student->id, $course->code);
                    }
                }
                $course->waiting = $remaining;
                return;

            case 'CANCEL':
                $course = $this->course($a[0]);
                $this->emit(0, 'CANCEL', $course->code,
                    'enrolled', count($course->enrolled), 'waitlist', count($course->waiting));
                foreach (array_keys($course->enrolled) as $id) {
                    $student = $this->students[$id];
                    unset($student->taking[$course->code]);
                    $this->record($student, 'cancel ' . $course->code);
                }
                foreach ($course->waiting as $id) {
                    $this->record($this->students[$id], 'cancel ' . $course->code . ' waitlist');
                }
                unset($this->courses[$course->code]);
                $this->promote();
                return;

            case 'ROSTER':
                $course = $this->course($a[0]);
                $this->emit(0, 'ROSTER', $course->code, $course->status(),
                    'enrolled', count($course->enrolled) . '/' . $course->capacity,
                    'waitlist', count($course->waiting));
                $ids = array_keys($course->enrolled);
                sort($ids, SORT_STRING);
                foreach ($ids as $id) {
                    $this->emit(2, 'enrolled', $id, 'year', $this->students[$id]->year);
                }
                foreach ($course->waiting as $position => $id) {
                    $this->emit(2, 'waitlist', $position + 1, $id, 'year', $this->students[$id]->year);
                }
                return;

            case 'SCHEDULE':
                $this->schedule($this->student($a[0]));
                return;

            case 'FREE':
                $student = $this->student($a[0]);
                $day = $a[1];
                if (!in_array($day, DAYS, true)) {
                    throw new CommandError('invalid day ' . $day);
                }
                $meetings = [];
                foreach ($this->taking($student) as $course) {
                    foreach ($course->slots as $slot) {
                        if ($slot['day'] === $day && $slot['start'] < 1320 && $slot['end'] > 480) {
                            $meetings[] = $slot;
                        }
                    }
                }
                usort($meetings, static fn(array $a, array $b): int =>
                    $a['start'] <=> $b['start']);
                $ranges = [];
                $cursor = 480;
                foreach ($meetings as $slot) {
                    $start = max($slot['start'], 480);
                    if ($start > $cursor) {
                        $ranges[] = [$cursor, $start];
                    }
                    $cursor = max($cursor, min($slot['end'], 1320));
                }
                if ($cursor < 1320) {
                    $ranges[] = [$cursor, 1320];
                }
                $minutes = 0;
                $parts = ['FREE', $student->id, $day, 'total'];
                foreach ($ranges as [$first, $last]) {
                    $minutes += $last - $first;
                }
                $parts[] = timeText($minutes);
                foreach ($ranges as [$first, $last]) {
                    $parts[] = timeText($first) . '-' . timeText($last);
                }
                $this->emit(0, ...$parts);
                return;

            case 'INFO':
                $course = $this->course($a[0]);
                $this->emit(0, 'INFO', $course->code, $course->status(),
                    'credits', $course->credits, 'capacity', $course->capacity,
                    'prereq', canonical($course->prerequisite));
                $slots = $course->slots;
                usort($slots, static fn(array $a, array $b): int =>
                    (array_search($a['day'], DAYS, true) <=> array_search($b['day'], DAYS, true))
                    ?: ($a['start'] <=> $b['start']));
                if (!$slots) {
                    $this->emit(2, 'meet', 'TBA');
                } else {
                    foreach ($slots as $slot) {
                        $this->emit(2, 'meet', $slot['day'],
                            timeText($slot['start']) . '-' . timeText($slot['end']));
                    }
                }
                $required = [];
                foreach ($this->sortedCourses() as $other) {
                    if (containsCondition($other->prerequisite, $course->code)) {
                        $required[] = $other->code;
                    }
                }
                $this->emit(2, 'required', 'by', ...($required ?: ['none']));
                return;

            case 'AUDIT':
                $student = $this->student($a[0]);
                $this->emit(0, 'AUDIT', $student->id, 'year', $student->year, 'limit', $student->limit);
                $grades = $student->grades;
                usort($grades, static fn(array $a, array $b): int => strcmp($a['code'], $b['code']));
                foreach ($grades as $grade) {
                    $this->emit(2, 'record', $grade['code'], $grade['grade'], $grade['credits']);
                }
                $this->emit(2, 'earned', $student->earned(), 'gpa', $student->gpa());
                foreach ($this->taking($student) as $course) {
                    $this->emit(2, 'enrolled', $course->code, $course->credits);
                }
                $credits = $this->credits($student);
                $this->emit(2, 'credits', $credits, 'remaining', $student->limit - $credits);
                foreach ($this->waitlists($student) as $course) {
                    $position = array_search($student->id, $course->waiting, true) + 1;
                    $this->emit(2, 'waitlist', $course->code, $position);
                }
                return;

            case 'HISTORY':
                $student = $this->student($a[0]);
                $this->emit(0, 'HISTORY', $student->id, 'events', count($student->history));
                foreach ($student->history as [$number, $event]) {
                    $this->emit(2, $number, $event);
                }
                return;

            case 'STUDENTS':
                $students = $this->students;
                ksort($students, SORT_STRING);
                $this->emit(0, 'STUDENTS', count($students));
                foreach ($students as $student) {
                    $this->emit(2, $student->id, 'year', $student->year,
                        'credits', $this->credits($student) . '/' . $student->limit,
                        'courses', count($student->taking),
                        'waitlists', count($this->waitlists($student)));
                }
                return;

            case 'REPORT':
                $courses = $this->sortedCourses();
                $enrolled = 0;
                $capacity = 0;
                $waiting = 0;
                $departments = [];
                foreach ($courses as $course) {
                    $enrolled += count($course->enrolled);
                    $capacity += $course->capacity;
                    $waiting += count($course->waiting);
                    $departments[$course->department()][] = $course;
                }
                $this->emit(0, 'REPORT', 'courses', count($courses), 'enrolled',
                    $enrolled . '/' . $capacity, 'rate', rateText($enrolled, $capacity),
                    'waitlisted', $waiting);
                foreach ($courses as $course) {
                    $count = count($course->enrolled);
                    $this->emit(2, $course->code, $course->status(),
                        $count . '/' . $course->capacity, rateText($count, $course->capacity),
                        'waitlist', count($course->waiting));
                }
                ksort($departments, SORT_STRING);
                foreach ($departments as $department => $group) {
                    $count = 0;
                    $seats = 0;
                    $queued = 0;
                    foreach ($group as $course) {
                        $count += count($course->enrolled);
                        $seats += $course->capacity;
                        $queued += count($course->waiting);
                    }
                    $this->emit(2, 'dept', $department, 'courses', count($group),
                        'enrolled', $count . '/' . $seats,
                        'rate', rateText($count, $seats), 'waitlisted', $queued);
                }
                return;
        }
    }

    public function execute(string $line): void
    {
        ++$this->commandNumber;
        $tokens = explode(' ', $line);
        $command = array_shift($tokens);
        try {
            $this->command($command, $tokens);
        } catch (CommandError $error) {
            $this->emit(0, 'ERROR', $error->getMessage());
        }
    }

    public function output(): string
    {
        return $this->output ? implode("\n", $this->output) . "\n" : '';
    }
}

$count = (int) trim((string) fgets(STDIN));
$registrar = new Registrar();
for ($i = 0; $i < $count; ++$i) {
    $registrar->execute(rtrim((string) fgets(STDIN), "\r\n"));
}
echo $registrar->output();
