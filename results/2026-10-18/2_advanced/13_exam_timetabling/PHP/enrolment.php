<?php

function id_key(string $id): string
{
    return '#' . $id;
}

function sorted_ids(array $map): array
{
    $ids = array_map(fn($key) => substr($key, 1), array_keys($map));
    sort($ids, SORT_STRING);
    return $ids;
}

class Course
{
    public array $students = [];

    public function __construct(public string $id, public int $duration, public string $name)
    {
    }

    public function size(): int
    {
        return count($this->students);
    }
}

function read_records(string $path): array
{
    $records = [];
    foreach (array_slice(file($path, FILE_IGNORE_NEW_LINES), 1) as $index => $line) {
        $records[] = [$index + 2, explode(',', $line)];
    }
    return $records;
}

function load_courses(string $path, array &$errors): array
{
    $courses = [];
    foreach (read_records($path) as [$number, [$id, $duration, $name]]) {
        $key = id_key($id);
        if (isset($courses[$key])) {
            $errors[] = "courses.csv line $number: duplicate course $id";
        } else {
            $courses[$key] = new Course($id, (int) $duration, $name);
        }
    }
    return $courses;
}

function load_enrolments(string $path, array $courses, array &$errors): array
{
    $accepted = [];
    $studentCourses = [];
    foreach (read_records($path) as [$number, [$student, $id]]) {
        $key = id_key($id);
        $studentKey = id_key($student);
        $pair = $student . ',' . $id;
        if (!isset($courses[$key])) {
            $errors[] = "enrolments.csv line $number: unknown course $id";
        } elseif (isset($accepted[$pair])) {
            $errors[] = "enrolments.csv line $number: duplicate enrolment $student $id";
        } else {
            $accepted[$pair] = true;
            $courses[$key]->students[] = $student;
            $studentCourses[$studentKey][] = $id;
        }
    }
    foreach ($courses as $course) {
        sort($course->students, SORT_STRING);
    }
    foreach ($studentCourses as &$list) {
        sort($list, SORT_STRING);
    }
    unset($list);
    return $studentCourses;
}
