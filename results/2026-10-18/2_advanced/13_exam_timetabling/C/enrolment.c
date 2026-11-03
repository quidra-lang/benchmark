#include "timetable.h"

int find_course(const Scheduler *scheduler, const char *id) {
    for (int i = 0; i < scheduler->course_count; ++i)
        if (!strcmp(scheduler->courses[i].id, id)) return i;
    return -1;
}
int find_student(const Scheduler *scheduler, const char *id) {
    for (int i = 0; i < scheduler->student_count; ++i)
        if (!strcmp(scheduler->students[i].id, id)) return i;
    return -1;
}
static int course_compare(const void *first, const void *second) {
    return strcmp(((const Course *)first)->id, ((const Course *)second)->id);
}
static int student_compare(const void *first, const void *second) {
    return strcmp(((const Student *)first)->id, ((const Student *)second)->id);
}
void sort_courses(const Scheduler *scheduler, Courses *courses, const int *values) {
    for (int i = 1; i < courses->count; ++i) {
        int chosen = courses->items[i], j = i;
        while (j > 0) {
            int previous = courses->items[j - 1];
            int a = values ? values[chosen] : scheduler->courses[chosen].size;
            int b = values ? values[previous] : scheduler->courses[previous].size;
            if (a < b || (a == b && chosen > previous)) break;
            courses->items[j--] = previous;
        }
        courses->items[j] = chosen;
    }
}
void load_courses(Scheduler *scheduler) {
    Lines lines = read_lines("input/courses.csv");
    for (int i = 1; i < lines.count; ++i) {
        char *id = lines.items[i], *duration = strchr(id, ',');
        *duration++ = '\0';
        char *name = strchr(duration, ',');
        *name++ = '\0';
        if (find_course(scheduler, id) >= 0)
            add_line(&scheduler->errors, "courses.csv line %d: duplicate course %s", i + 1, id);
        else {
            Course *course = &scheduler->courses[scheduler->course_count++];
            strcpy(course->id, id); strcpy(course->name, name); course->duration = atoi(duration);
        }
    }
    qsort(scheduler->courses, (size_t)scheduler->course_count, sizeof(Course), course_compare);
}
void load_enrolments(Scheduler *scheduler) {
    Lines lines = read_lines("input/enrolments.csv");
    for (int i = 1; i < lines.count; ++i) {
        char *student_id = lines.items[i], *course_id = strchr(student_id, ',');
        *course_id++ = '\0';
        int course = find_course(scheduler, course_id);
        if (course < 0) {
            add_line(&scheduler->errors, "enrolments.csv line %d: unknown course %s", i + 1, course_id);
            continue;
        }
        int student = find_student(scheduler, student_id);
        bool duplicate = false;
        if (student >= 0)
            for (int j = 0; j < scheduler->students[student].count; ++j)
                if (scheduler->students[student].courses[j] == course) duplicate = true;
        if (duplicate) {
            add_line(&scheduler->errors, "enrolments.csv line %d: duplicate enrolment %s %s", i + 1, student_id, course_id);
            continue;
        }
        if (student < 0) {
            student = scheduler->student_count++;
            strcpy(scheduler->students[student].id, student_id);
        }
        Student *record = &scheduler->students[student];
        int j = record->count++;
        while (j > 0 && record->courses[j - 1] > course) { record->courses[j] = record->courses[j - 1]; --j; }
        record->courses[j] = course;
        ++scheduler->enrolment_count;
    }
    qsort(scheduler->students, (size_t)scheduler->student_count, sizeof(Student), student_compare);
    for (int i = 0; i < scheduler->student_count; ++i)
        for (int j = 0; j < scheduler->students[i].count; ++j) {
            Course *course = &scheduler->courses[scheduler->students[i].courses[j]];
            course->students[course->size++] = i;
        }
}
