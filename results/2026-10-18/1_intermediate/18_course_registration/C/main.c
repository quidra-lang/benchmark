#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char text[96]; } Text;
typedef enum { WORD, AND, OR } NodeKind;
typedef struct Node {
    NodeKind kind;
    char word[8];
    struct Node *left, *right;
} Node;
typedef struct { const char *text; int position; } Parser;
typedef struct { char text[12]; int day, start, end; } Slot;
typedef struct { char code[8], grade; int credits; } Grade;
typedef struct { int command; char event[40]; } History;
typedef struct Course Course;
typedef struct Student Student;
struct Course {
    char code[8], prereq_text[61];
    int credits, capacity, slot_count, enrolled_count, waiting_count;
    Slot slots[6];
    Node *prereq;
    bool open;
    Student *enrolled[100], *waiting[100];
};
struct Student {
    char id[9];
    int year, limit, grade_count, course_count, history_count, history_capacity;
    Grade grades[20];
    Course *courses[50];
    History *history;
};
typedef enum { REASON, ELIGIBLE, ENROLL, WAITLIST } Decision;
typedef struct { Decision decision; const char *reason; char extra[32]; int position; } Judgment;
typedef struct { Slot slot; const char *code; } Meeting;

static const char *day_names[] = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" };
static Course *courses[50];
static Student *students[100];
static int course_count, student_count, command_number;

static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
static bool upper(char ch) { return ch >= 'A' && ch <= 'Z'; }
static bool digit(char ch) { return ch >= '0' && ch <= '9'; }
static int minimum(int a, int b) { return a < b ? a : b; }
static int maximum(int a, int b) { return a > b ? a : b; }

static void *allocate(size_t size) {
    void *data = calloc(1, size);
    if (!data) exit(EXIT_FAILURE);
    return data;
}

static bool fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("ERROR ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    return false;
}

static Text time_text(int minutes) {
    Text result;
    snprintf(result.text, sizeof result.text, "%02d:%02d", minutes / 60, minutes % 60);
    return result;
}

static Text rate(int count, int capacity) {
    Text result;
    if (!capacity) strcpy(result.text, "n/a");
    else snprintf(result.text, sizeof result.text, "%d%%", count * 100 / capacity);
    return result;
}

static int course_order(const void *left, const void *right) {
    const Course *a = *(Course *const *)left, *b = *(Course *const *)right;
    return strcmp(a->code, b->code);
}

static int student_order(const void *left, const void *right) {
    const Student *a = *(Student *const *)left, *b = *(Student *const *)right;
    return strcmp(a->id, b->id);
}

static int grade_order(const void *left, const void *right) {
    const Grade *a = left, *b = right;
    return strcmp(a->code, b->code);
}

static Course *find_course(const char *code) {
    for (int i = 0; i < course_count; ++i) if (equal(courses[i]->code, code)) return courses[i];
    return NULL;
}

static Student *find_student(const char *id) {
    for (int i = 0; i < student_count; ++i) if (equal(students[i]->id, id)) return students[i];
    return NULL;
}

static Course *course(const char *code) {
    Course *c = find_course(code);
    if (!c) fail("unknown course %s", code);
    return c;
}

static Student *student(const char *id) {
    Student *s = find_student(id);
    if (!s) fail("unknown student %s", id);
    return s;
}

static char passed(const Student *s, const char *code) {
    for (int i = 0; i < s->grade_count; ++i)
        if (equal(s->grades[i].code, code) && s->grades[i].grade <= 'C') return s->grades[i].grade;
    return '\0';
}

static int credits(const Student *s, const Course *excluded) {
    int total = 0;
    for (int i = 0; i < s->course_count; ++i) if (s->courses[i] != excluded) total += s->courses[i]->credits;
    return total;
}

static int earned(const Student *s) {
    int total = 0;
    for (int i = 0; i < s->grade_count; ++i) if (s->grades[i].grade != 'F') total += s->grades[i].credits;
    return total;
}

static Text gpa(const Student *s) {
    Text result;
    if (!s->grade_count) { strcpy(result.text, "n/a"); return result; }
    int points = 0, total = 0;
    for (int i = 0; i < s->grade_count; ++i) {
        Grade r = s->grades[i];
        points += (r.grade == 'F' ? 0 : 'E' - r.grade) * r.credits;
        total += r.credits;
    }
    int value = (200 * points + total) / (2 * total);
    snprintf(result.text, sizeof result.text, "%d.%02d", value / 100, value % 100);
    return result;
}

static void free_node(Node *node) {
    if (!node) return;
    free_node(node->left);
    free_node(node->right);
    free(node);
}

static Node *parse_expression(Parser *parser);

static Node *parse_factor(Parser *p) {
    if (p->text[p->position] == '(') {
        ++p->position;
        Node *node = parse_expression(p);
        if (!node || p->text[p->position] != ')') { free_node(node); return NULL; }
        ++p->position;
        return node;
    }
    int start = p->position;
    while (upper(p->text[p->position]) || digit(p->text[p->position])) ++p->position;
    int length = p->position - start, letters = 0;
    const char *word = p->text + start;
    while (letters < length && upper(word[letters])) ++letters;
    bool code = letters >= 2 && letters <= 4 && length == letters + 3;
    for (int i = letters; i < length; ++i) if (!digit(word[i])) code = false;
    bool year = length == 2 && word[0] == 'Y' && word[1] >= '1' && word[1] <= '9';
    if (!code && !year) return NULL;
    Node *node = allocate(sizeof *node);
    node->kind = WORD;
    memcpy(node->word, word, (size_t)length);
    return node;
}

static Node *parse_term(Parser *p) {
    Node *left = parse_factor(p);
    if (!left) return NULL;
    while (p->text[p->position] == '&') {
        ++p->position;
        Node *right = parse_factor(p);
        if (!right) { free_node(left); return NULL; }
        Node *parent = allocate(sizeof *parent);
        parent->kind = AND;
        parent->left = left;
        parent->right = right;
        left = parent;
    }
    return left;
}

static Node *parse_expression(Parser *p) {
    Node *left = parse_term(p);
    if (!left) return NULL;
    while (p->text[p->position] == '|') {
        ++p->position;
        Node *right = parse_term(p);
        if (!right) { free_node(left); return NULL; }
        Node *parent = allocate(sizeof *parent);
        parent->kind = OR;
        parent->left = left;
        parent->right = right;
        left = parent;
    }
    return left;
}

static bool contains(const Node *node, const char *code) {
    if (!node) return false;
    if (node->kind == WORD) return equal(node->word, code);
    return contains(node->left, code) || contains(node->right, code);
}

static bool satisfied(const Node *node, const Student *s) {
    if (!node) return true;
    if (node->kind == AND) return satisfied(node->left, s) && satisfied(node->right, s);
    if (node->kind == OR) return satisfied(node->left, s) || satisfied(node->right, s);
    return strlen(node->word) == 2 ? s->year >= node->word[1] - '0' : passed(s, node->word) != '\0';
}

static void write_node(const Node *node, bool within_and, char *text, int *length) {
    bool parens = within_and && node->kind == OR;
    if (parens) text[(*length)++] = '(';
    if (node->kind == WORD) {
        int size = (int)strlen(node->word);
        memcpy(text + *length, node->word, (size_t)size);
        *length += size;
    } else {
        write_node(node->left, node->kind == AND, text, length);
        text[(*length)++] = node->kind == AND ? '&' : '|';
        write_node(node->right, node->kind == AND, text, length);
    }
    if (parens) text[(*length)++] = ')';
}

static bool prerequisite(const char *code, const char *text, Node **root, char *canonical) {
    if (equal(text, "-")) { *root = NULL; strcpy(canonical, "-"); return true; }
    Parser parser = { .text = text };
    Node *node = parse_expression(&parser);
    if (!node || text[parser.position]) { free_node(node); return fail("invalid prereq %s", code); }
    if (contains(node, code)) { free_node(node); return fail("self prereq %s", code); }
    int length = 0;
    write_node(node, false, canonical, &length);
    canonical[length] = '\0';
    *root = node;
    return true;
}

static int day_index(const char *text) {
    for (int i = 0; i < 7; ++i) if (equal(day_names[i], text)) return i;
    return -1;
}

static bool overlaps(Slot a, Slot b) { return a.day == b.day && a.start < b.end && b.start < a.end; }

static bool parse_slots(const char *text, Slot *slots, int *count) {
    *count = 0;
    if (equal(text, "-")) return true;
    char copy[72];
    strcpy(copy, text);
    for (char *part = strtok(copy, ","); part; part = strtok(NULL, ",")) {
        Slot slot = { 0 };
        strcpy(slot.text, part);
        char day[3] = { part[0], part[1], '\0' };
        slot.day = day_index(day);
        int h1 = (part[2] - '0') * 10 + part[3] - '0', m1 = (part[4] - '0') * 10 + part[5] - '0';
        int h2 = (part[7] - '0') * 10 + part[8] - '0', m2 = (part[9] - '0') * 10 + part[10] - '0';
        slot.start = h1 * 60 + m1;
        slot.end = h2 * 60 + m2;
        if (slot.day < 0 || h1 > 23 || h2 > 23 || m1 > 59 || m2 > 59 || slot.start >= slot.end)
            return fail("invalid slot %s", part);
        slots[(*count)++] = slot;
    }
    for (int i = 0; i < *count; ++i)
        for (int j = i + 1; j < *count; ++j)
            if (overlaps(slots[i], slots[j])) return fail("overlapping slots %s %s", slots[i].text, slots[j].text);
    return true;
}

static bool parse_grades(const char *id, const char *text, Grade *grades, int *count) {
    *count = 0;
    if (equal(text, "-")) return true;
    char copy[240];
    strcpy(copy, text);
    for (char *part = strtok(copy, ","); part; part = strtok(NULL, ",")) {
        char *colon = strchr(part, ':');
        Grade grade = { .grade = colon[1], .credits = colon[3] - '0' };
        *colon = '\0';
        strcpy(grade.code, part);
        if (!strchr("ABCDF", grade.grade)) return fail("invalid grade %s %s %c", id, grade.code, grade.grade);
        for (int i = 0; i < *count; ++i)
            if (equal(grades[i].code, grade.code)) return fail("duplicate record %s %s", id, grade.code);
        grades[(*count)++] = grade;
    }
    qsort(grades, (size_t)*count, sizeof *grades, grade_order);
    return true;
}

static int weekly(const Course *c) {
    int total = 0;
    for (int i = 0; i < c->slot_count; ++i) total += c->slots[i].end - c->slots[i].start;
    return total;
}

static bool conflicts(const Course *a, const Course *b) {
    for (int i = 0; i < a->slot_count; ++i)
        for (int j = 0; j < b->slot_count; ++j) if (overlaps(a->slots[i], b->slots[j])) return true;
    return false;
}

static Course *conflict(const Student *s, const Course *c, const Course *excluded) {
    for (int i = 0; i < s->course_count; ++i)
        if (s->courses[i] != excluded && conflicts(s->courses[i], c)) return s->courses[i];
    return NULL;
}

static int enrolled_index(const Student *s, const Course *c) {
    for (int i = 0; i < s->course_count; ++i) if (s->courses[i] == c) return i;
    return -1;
}

static int waiting_index(const Course *c, const Student *s) {
    for (int i = 0; i < c->waiting_count; ++i) if (c->waiting[i] == s) return i;
    return -1;
}

static int wait_count(const Student *s) {
    int count = 0;
    for (int i = 0; i < course_count; ++i) count += waiting_index(courses[i], s) >= 0;
    return count;
}

static Judgment eligible(Student *s, Course *c, Course *excluded) {
    Judgment j = { .decision = REASON };
    if (!c->open) j.reason = "course closed";
    else if (enrolled_index(s, c) >= 0) j.reason = "already enrolled";
    else if (waiting_index(c, s) >= 0) j.reason = "already waitlisted";
    else if (passed(s, c->code)) {
        j.reason = "already completed";
        snprintf(j.extra, sizeof j.extra, "%c", passed(s, c->code));
    } else if (!satisfied(c->prereq, s)) j.reason = "prereq not met";
    else {
        Course *other = conflict(s, c, excluded);
        int attempted = credits(s, excluded) + c->credits;
        if (other) { j.reason = "time conflict"; strcpy(j.extra, other->code); }
        else if (attempted > s->limit) {
            j.reason = "credit limit";
            snprintf(j.extra, sizeof j.extra, "%d %d", attempted, s->limit);
        } else j.decision = ELIGIBLE;
    }
    return j;
}

static Judgment judge(Student *s, Course *c) {
    Judgment j = eligible(s, c, NULL);
    if (j.decision == REASON) return j;
    if (c->enrolled_count < c->capacity) j.decision = ENROLL;
    else if (wait_count(s) >= 3) { j.decision = REASON; j.reason = "waitlist limit"; }
    else {
        j.decision = WAITLIST;
        j.position = 1;
        for (int i = 0; i < c->waiting_count; ++i) j.position += c->waiting[i]->year >= s->year;
    }
    return j;
}

static Text judgment_text(Judgment j) {
    Text text;
    if (j.decision == ENROLL) strcpy(text.text, "enroll");
    else if (j.decision == WAITLIST) snprintf(text.text, sizeof text.text, "waitlist %d", j.position);
    else if (j.decision == ELIGIBLE) strcpy(text.text, "OK");
    else snprintf(text.text, sizeof text.text, "%s%s%s", j.reason, j.extra[0] ? " " : "", j.extra);
    return text;
}

static void reject(Judgment j, Student *s, Course *c) {
    fail("%s %s %s%s%s", j.reason, s->id, c->code, j.extra[0] ? " " : "", j.extra);
}

static void history(Student *s, const char *format, ...) {
    if (s->history_count == s->history_capacity) {
        int capacity = s->history_capacity ? s->history_capacity * 2 : 8;
        History *items = realloc(s->history, (size_t)capacity * sizeof *items);
        if (!items) exit(EXIT_FAILURE);
        s->history = items;
        s->history_capacity = capacity;
    }
    History *h = &s->history[s->history_count++];
    h->command = command_number;
    va_list args;
    va_start(args, format);
    vsnprintf(h->event, sizeof h->event, format, args);
    va_end(args);
}

static void enroll(Student *s, Course *c) {
    s->courses[s->course_count++] = c;
    qsort(s->courses, (size_t)s->course_count, sizeof *s->courses, course_order);
    c->enrolled[c->enrolled_count++] = s;
    qsort(c->enrolled, (size_t)c->enrolled_count, sizeof *c->enrolled, student_order);
}

static void remove_enrollment(Student *s, Course *c) {
    int i = enrolled_index(s, c);
    --s->course_count;
    memmove(s->courses + i, s->courses + i + 1, (size_t)(s->course_count - i) * sizeof *s->courses);
    i = 0;
    while (c->enrolled[i] != s) ++i;
    --c->enrolled_count;
    memmove(c->enrolled + i, c->enrolled + i + 1, (size_t)(c->enrolled_count - i) * sizeof *c->enrolled);
}

static Student *remove_waiting(Course *c, int index) {
    Student *s = c->waiting[index];
    --c->waiting_count;
    memmove(c->waiting + index, c->waiting + index + 1, (size_t)(c->waiting_count - index) * sizeof *c->waiting);
    return s;
}

static void enrollment_line(const char *label, Student *s, Course *c) {
    printf("%s %s %s enrolled %d/%d credits %d/%d\n", label, s->id, c->code, c->enrolled_count, c->capacity, credits(s, NULL), s->limit);
}

static void promote(void) {
    for (int i = 0; i < course_count; ++i) {
        Course *c = courses[i];
        if (!c->open) continue;
        while (c->enrolled_count < c->capacity) {
            int j = 0;
            while (j < c->waiting_count) {
                Student *s = c->waiting[j];
                if (!conflict(s, c, NULL) && credits(s, NULL) + c->credits <= s->limit) break;
                ++j;
            }
            if (j == c->waiting_count) break;
            Student *s = remove_waiting(c, j);
            enroll(s, c);
            history(s, "promote %s", c->code);
            enrollment_line("  PROMOTE", s, c);
        }
    }
}

static int slot_order(const void *left, const void *right) {
    const Slot *a = left, *b = right;
    return a->day != b->day ? a->day - b->day : a->start - b->start;
}

static int meeting_order(const void *left, const void *right) {
    const Meeting *a = left, *b = right;
    return slot_order(&a->slot, &b->slot);
}

static void schedule(Student *s) {
    Meeting meetings[300];
    int count = 0, minutes = 0;
    for (int i = 0; i < s->course_count; ++i) {
        Course *c = s->courses[i];
        minutes += weekly(c);
        for (int j = 0; j < c->slot_count; ++j) meetings[count++] = (Meeting){ c->slots[j], c->code };
    }
    qsort(meetings, (size_t)count, sizeof *meetings, meeting_order);
    printf("SCHEDULE %s courses %d credits %d weekly %s\n", s->id, s->course_count, credits(s, NULL), time_text(minutes).text);
    for (int day = 0; day < 7; ++day) {
        bool found = false;
        for (int i = 0; i < count; ++i) {
            Slot slot = meetings[i].slot;
            if (slot.day != day) continue;
            if (!found) printf("  %s", day_names[day]);
            found = true;
            printf(" %s-%s %s", time_text(slot.start).text, time_text(slot.end).text, meetings[i].code);
        }
        if (found) putchar('\n');
    }
    bool tba = false;
    for (int i = 0; i < s->course_count; ++i) {
        if (s->courses[i]->slot_count) continue;
        if (!tba) fputs("  TBA", stdout);
        tba = true;
        printf(" %s", s->courses[i]->code);
    }
    if (tba) putchar('\n');
}

static void free_time(Student *s, const char *name) {
    int day = day_index(name);
    if (day < 0) { fail("invalid day %s", name); return; }
    bool available[840];
    for (int i = 0; i < 840; ++i) available[i] = true;
    for (int i = 0; i < s->course_count; ++i) {
        Course *c = s->courses[i];
        for (int j = 0; j < c->slot_count; ++j) {
            Slot slot = c->slots[j];
            if (slot.day != day) continue;
            for (int minute = maximum(480, slot.start); minute < minimum(1320, slot.end); ++minute)
                available[minute - 480] = false;
        }
    }
    int total = 0;
    for (int i = 0; i < 840; ++i) total += available[i];
    printf("FREE %s %s total %s", s->id, name, time_text(total).text);
    int i = 0;
    while (i < 840) {
        if (!available[i]) { ++i; continue; }
        int first = i;
        while (i < 840 && available[i]) ++i;
        printf(" %s-%s", time_text(first + 480).text, time_text(i + 480).text);
    }
    putchar('\n');
}

static Text department(const Course *c) {
    Text result = { 0 };
    memcpy(result.text, c->code, strlen(c->code) - 3);
    return result;
}

static void report(void) {
    int enrolled = 0, capacity = 0, waiting = 0;
    for (int i = 0; i < course_count; ++i) {
        enrolled += courses[i]->enrolled_count;
        capacity += courses[i]->capacity;
        waiting += courses[i]->waiting_count;
    }
    printf("REPORT courses %d enrolled %d/%d rate %s waitlisted %d\n", course_count, enrolled, capacity, rate(enrolled, capacity).text, waiting);
    for (int i = 0; i < course_count; ++i) {
        Course *c = courses[i];
        printf("  %s %s %d/%d %s waitlist %d\n", c->code, c->open ? "open" : "closed", c->enrolled_count, c->capacity, rate(c->enrolled_count, c->capacity).text, c->waiting_count);
    }
    int i = 0;
    while (i < course_count) {
        Text name = department(courses[i]);
        int count = 0;
        enrolled = capacity = waiting = 0;
        while (i < course_count && equal(name.text, department(courses[i]).text)) {
            Course *c = courses[i++];
            ++count;
            enrolled += c->enrolled_count;
            capacity += c->capacity;
            waiting += c->waiting_count;
        }
        printf("  dept %s courses %d enrolled %d/%d rate %s waitlisted %d\n", name.text, count, enrolled, capacity, rate(enrolled, capacity).text, waiting);
    }
}

static void execute(char **a) {
    const char *op = a[0];
    if (equal(op, "COURSE")) {
        if (find_course(a[1])) { fail("duplicate course %s", a[1]); return; }
        Course data = { .credits = atoi(a[2]), .capacity = atoi(a[3]), .open = true };
        strcpy(data.code, a[1]);
        if (!parse_slots(a[4], data.slots, &data.slot_count)) return;
        if (!prerequisite(a[1], a[5], &data.prereq, data.prereq_text)) return;
        Course *c = allocate(sizeof *c);
        *c = data;
        courses[course_count++] = c;
        qsort(courses, (size_t)course_count, sizeof *courses, course_order);
        printf("COURSE %s credits %d capacity %d meetings %d weekly %s prereq %s\n", c->code, c->credits, c->capacity, c->slot_count, time_text(weekly(c)).text, c->prereq_text);
    } else if (equal(op, "STUDENT")) {
        if (find_student(a[1])) { fail("duplicate student %s", a[1]); return; }
        Student data = { .year = atoi(a[2]), .limit = atoi(a[3]) };
        strcpy(data.id, a[1]);
        if (!parse_grades(a[1], a[4], data.grades, &data.grade_count)) return;
        Student *s = allocate(sizeof *s);
        *s = data;
        students[student_count++] = s;
        qsort(students, (size_t)student_count, sizeof *students, student_order);
        printf("STUDENT %s year %d limit %d records %d earned %d gpa %s\n", s->id, s->year, s->limit, s->grade_count, earned(s), gpa(s).text);
    } else if (equal(op, "STUDENTS")) {
        printf("STUDENTS %d\n", student_count);
        for (int i = 0; i < student_count; ++i) {
            Student *s = students[i];
            printf("  %s year %d credits %d/%d courses %d waitlists %d\n", s->id, s->year, credits(s, NULL), s->limit, s->course_count, wait_count(s));
        }
    } else if (equal(op, "REPORT")) {
        report();
    } else if (equal(op, "ENROLL") || equal(op, "CHECK") || equal(op, "OPTIONS") || equal(op, "DROP") || equal(op, "SWAP") ||
               equal(op, "LIMIT") || equal(op, "SCHEDULE") || equal(op, "FREE") || equal(op, "AUDIT") || equal(op, "HISTORY")) {
        Student *s = student(a[1]);
        if (!s) return;
        if (equal(op, "ENROLL") || equal(op, "CHECK")) {
            Course *c = course(a[2]);
            if (!c) return;
            Judgment j = judge(s, c);
            if (equal(op, "CHECK")) printf("CHECK %s %s %s\n", s->id, c->code, judgment_text(j).text);
            else if (j.decision == REASON) reject(j, s, c);
            else if (j.decision == ENROLL) {
                enroll(s, c);
                history(s, "enroll %s", c->code);
                enrollment_line("ENROLL", s, c);
            } else {
                int i = j.position - 1;
                memmove(c->waiting + i + 1, c->waiting + i, (size_t)(c->waiting_count - i) * sizeof *c->waiting);
                c->waiting[i] = s;
                ++c->waiting_count;
                history(s, "waitlist %s %d", c->code, j.position);
                printf("ENROLL %s %s waitlist %d\n", s->id, c->code, j.position);
            }
        } else if (equal(op, "OPTIONS")) {
            printf("OPTIONS %s courses %d\n", s->id, course_count);
            for (int i = 0; i < course_count; ++i) printf("  %s %s\n", courses[i]->code, judgment_text(judge(s, courses[i])).text);
        } else if (equal(op, "DROP")) {
            Course *c = course(a[2]);
            if (!c) return;
            int waiting = waiting_index(c, s);
            if (enrolled_index(s, c) >= 0) {
                remove_enrollment(s, c);
                history(s, "drop %s", c->code);
                enrollment_line("DROP", s, c);
            } else if (waiting >= 0) {
                remove_waiting(c, waiting);
                history(s, "drop %s waitlist", c->code);
                printf("DROP %s %s waitlist removed\n", s->id, c->code);
            } else { fail("not registered %s %s", s->id, c->code); return; }
            promote();
        } else if (equal(op, "SWAP")) {
            Course *from = course(a[2]);
            if (!from) return;
            Course *to = course(a[3]);
            if (!to) return;
            if (enrolled_index(s, from) < 0) { fail("not enrolled %s %s", s->id, from->code); return; }
            if (from == to) { fail("same course %s", from->code); return; }
            Judgment j = eligible(s, to, from);
            if (j.decision == REASON) { reject(j, s, to); return; }
            if (to->enrolled_count == to->capacity) { fail("course full %s", to->code); return; }
            remove_enrollment(s, from);
            enroll(s, to);
            history(s, "swap %s %s", from->code, to->code);
            printf("SWAP %s %s -> %s credits %d/%d\n", s->id, from->code, to->code, credits(s, NULL), s->limit);
            promote();
        } else if (equal(op, "LIMIT")) {
            int limit = atoi(a[2]);
            if (limit < credits(s, NULL)) { fail("limit below enrolled %s %d", s->id, credits(s, NULL)); return; }
            int old = s->limit;
            s->limit = limit;
            printf("LIMIT %s %d -> %d\n", s->id, old, limit);
            promote();
        } else if (equal(op, "SCHEDULE")) schedule(s);
        else if (equal(op, "FREE")) free_time(s, a[2]);
        else if (equal(op, "AUDIT")) {
            printf("AUDIT %s year %d limit %d\n", s->id, s->year, s->limit);
            for (int i = 0; i < s->grade_count; ++i) printf("  record %s %c %d\n", s->grades[i].code, s->grades[i].grade, s->grades[i].credits);
            printf("  earned %d gpa %s\n", earned(s), gpa(s).text);
            for (int i = 0; i < s->course_count; ++i) printf("  enrolled %s %d\n", s->courses[i]->code, s->courses[i]->credits);
            printf("  credits %d remaining %d\n", credits(s, NULL), s->limit - credits(s, NULL));
            for (int i = 0; i < course_count; ++i) {
                int position = waiting_index(courses[i], s);
                if (position >= 0) printf("  waitlist %s %d\n", courses[i]->code, position + 1);
            }
        } else if (equal(op, "HISTORY")) {
            printf("HISTORY %s events %d\n", s->id, s->history_count);
            for (int i = 0; i < s->history_count; ++i) printf("  %d %s\n", s->history[i].command, s->history[i].event);
        }
    } else {
        Course *c = course(a[1]);
        if (!c) return;
        if (equal(op, "CLOSE") || equal(op, "OPEN")) {
            bool open = equal(op, "OPEN");
            if (c->open == open) { fail("already %s %s", open ? "open" : "closed", c->code); return; }
            c->open = open;
            printf("%s %s enrolled %d/%d waitlist %d\n", op, c->code, c->enrolled_count, c->capacity, c->waiting_count);
            if (open) promote();
        } else if (equal(op, "CAPACITY")) {
            int capacity = atoi(a[2]);
            if (capacity < c->enrolled_count) { fail("capacity below enrollment %s %d", c->code, c->enrolled_count); return; }
            int old = c->capacity;
            c->capacity = capacity;
            printf("CAPACITY %s %d -> %d\n", c->code, old, capacity);
            promote();
        } else if (equal(op, "PREREQ")) {
            Node *root;
            char canonical[61];
            if (!prerequisite(c->code, a[2], &root, canonical)) return;
            free_node(c->prereq);
            c->prereq = root;
            strcpy(c->prereq_text, canonical);
            printf("PREREQ %s %s\n", c->code, canonical);
            int i = 0;
            while (i < c->waiting_count) {
                Student *s = c->waiting[i];
                if (satisfied(root, s)) { ++i; continue; }
                remove_waiting(c, i);
                history(s, "unlist %s", c->code);
                printf("  UNLIST %s %s\n", s->id, c->code);
            }
        } else if (equal(op, "CANCEL")) {
            printf("CANCEL %s enrolled %d waitlist %d\n", c->code, c->enrolled_count, c->waiting_count);
            while (c->enrolled_count) {
                Student *s = c->enrolled[0];
                history(s, "cancel %s", c->code);
                remove_enrollment(s, c);
            }
            for (int i = 0; i < c->waiting_count; ++i) history(c->waiting[i], "cancel %s waitlist", c->code);
            int i = 0;
            while (courses[i] != c) ++i;
            --course_count;
            memmove(courses + i, courses + i + 1, (size_t)(course_count - i) * sizeof *courses);
            free_node(c->prereq);
            free(c);
            promote();
        } else if (equal(op, "ROSTER")) {
            printf("ROSTER %s %s enrolled %d/%d waitlist %d\n", c->code, c->open ? "open" : "closed", c->enrolled_count, c->capacity, c->waiting_count);
            for (int i = 0; i < c->enrolled_count; ++i) printf("  enrolled %s year %d\n", c->enrolled[i]->id, c->enrolled[i]->year);
            for (int i = 0; i < c->waiting_count; ++i) printf("  waitlist %d %s year %d\n", i + 1, c->waiting[i]->id, c->waiting[i]->year);
        } else if (equal(op, "INFO")) {
            printf("INFO %s %s credits %d capacity %d prereq %s\n", c->code, c->open ? "open" : "closed", c->credits, c->capacity, c->prereq_text);
            Slot slots[6];
            memcpy(slots, c->slots, (size_t)c->slot_count * sizeof *slots);
            qsort(slots, (size_t)c->slot_count, sizeof *slots, slot_order);
            for (int i = 0; i < c->slot_count; ++i) printf("  meet %s %s-%s\n", day_names[slots[i].day], time_text(slots[i].start).text, time_text(slots[i].end).text);
            if (!c->slot_count) puts("  meet TBA");
            fputs("  required by", stdout);
            bool found = false;
            for (int i = 0; i < course_count; ++i) {
                if (!contains(courses[i]->prereq, c->code)) continue;
                found = true;
                printf(" %s", courses[i]->code);
            }
            if (!found) fputs(" none", stdout);
            putchar('\n');
        }
    }
}

int main(void) {
    char line[512];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (command_number = 1; command_number <= count; ++command_number) {
        if (!fgets(line, sizeof line, stdin)) return EXIT_FAILURE;
        char *args[6];
        int length = 0;
        for (char *word = strtok(line, " \n"); word; word = strtok(NULL, " \n")) args[length++] = word;
        execute(args);
    }
    for (int i = 0; i < course_count; ++i) { free_node(courses[i]->prereq); free(courses[i]); }
    for (int i = 0; i < student_count; ++i) { free(students[i]->history); free(students[i]); }
    return 0;
}
