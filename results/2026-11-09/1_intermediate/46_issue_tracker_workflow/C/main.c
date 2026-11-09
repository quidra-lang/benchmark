#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { BUG, TASK, STORY };
enum { OPEN, TRIAGED, IN_PROGRESS, REVIEW, RESOLVED, CLOSED, REOPENED, DONE, BACKLOG, READY };
enum { PLANNED, ACTIVE, ENDED };
enum {
    ID,
    TYPE,
    STATUS,
    PRIORITY,
    ASSIGNEE,
    REVIEWER,
    ESTIMATE,
    SPRINT,
    COMMENTS,
    BLOCKED,
    FINISHED,
    TITLE
};

static char *type_names[] = {"BUG", "TASK", "STORY"};
static char *priorities[] = {"LOW", "MEDIUM", "HIGH", "CRITICAL"};
static char *state_names[] = {"OPEN",   "TRIAGED",  "IN_PROGRESS", "REVIEW",  "RESOLVED",
                              "CLOSED", "REOPENED", "DONE",        "BACKLOG", "READY"};
static char *phase_names[] = {"PLANNED", "ACTIVE", "ENDED"};
static int workflows[3][7] = {{OPEN, TRIAGED, IN_PROGRESS, REVIEW, RESOLVED, CLOSED, REOPENED},
                              {OPEN, IN_PROGRESS, DONE},
                              {BACKLOG, READY, IN_PROGRESS, REVIEW, DONE}};
static int state_counts[] = {7, 3, 5};

typedef struct {
    int number, type, priority, state, assignee, reviewer, estimate, sprint, comments, duplicate;
    char title[41];
    int blocks[100];
    char **history;
    int history_count, history_capacity;
} Issue;

typedef struct {
    char name[11];
    int phase, start, end, velocity, records[366];
} Sprint;

typedef struct {
    int day, issue_count, user_count, sprint_count;
    Issue issues[100];
    char users[20][11];
    Sprint sprints[20];
} Tracker;

typedef struct {
    int field, number;
    char operation[3], value[101];
} Condition;
typedef struct {
    char tokens[101][101];
    Condition conditions[101];
    int count, position;
} Query;

static Tracker *order_tracker;

static int name_index(char *names[], int count, char *name) {
    for (int i = 0; i < count; ++i)
        if (strcmp(names[i], name) == 0)
            return i;
    return -1;
}

static int issue_index(Tracker *tracker, int number) {
    for (int i = 0; i < tracker->issue_count; ++i)
        if (tracker->issues[i].number == number)
            return i;
    return -1;
}

static int user_index(Tracker *tracker, char *name) {
    for (int i = 0; i < tracker->user_count; ++i)
        if (strcmp(tracker->users[i], name) == 0)
            return i;
    return -1;
}

static int sprint_index(Tracker *tracker, char *name) {
    for (int i = 0; i < tracker->sprint_count; ++i)
        if (strcmp(tracker->sprints[i].name, name) == 0)
            return i;
    return -1;
}

static int compare_issues(const void *a, const void *b) {
    int left = order_tracker->issues[*(const int *)a].number;
    int right = order_tracker->issues[*(const int *)b].number;
    return (left > right) - (left < right);
}

static void ordered_issues(Tracker *tracker, int ids[]) {
    for (int i = 0; i < tracker->issue_count; ++i)
        ids[i] = i;
    order_tracker = tracker;
    qsort(ids, (size_t)tracker->issue_count, sizeof(ids[0]), compare_issues);
}

static int done(Issue *issue) {
    return issue->state == RESOLVED || issue->state == CLOSED || issue->state == DONE;
}
static int points(Issue *issue) {
    return issue->estimate < 0 ? 0 : issue->estimate;
}
static char *user_name(Tracker *tracker, int user) {
    return user < 0 ? "-" : tracker->users[user];
}
static char *sprint_name(Tracker *tracker, int sprint) {
    return sprint < 0 ? "-" : tracker->sprints[sprint].name;
}

static void print_optional(int number) {
    if (number < 0)
        putchar('-');
    else
        printf("%d", number);
}

static int unfinished_blocker(Tracker *tracker, int issue) {
    int result = -1;
    for (int i = 0; i < tracker->issue_count; ++i)
        if (tracker->issues[i].blocks[issue] && !done(&tracker->issues[i]) &&
            (result < 0 || tracker->issues[i].number < tracker->issues[result].number))
            result = i;
    return result;
}

static int blocked(Tracker *tracker, int issue) {
    return !done(&tracker->issues[issue]) && unfinished_blocker(tracker, issue) >= 0;
}

static int wip(Tracker *tracker, int user) {
    int count = 0;
    for (int i = 0; i < tracker->issue_count; ++i)
        count += tracker->issues[i].assignee == user && tracker->issues[i].state == IN_PROGRESS;
    return count;
}

static int active_sprint(Tracker *tracker) {
    for (int i = 0; i < tracker->sprint_count; ++i)
        if (tracker->sprints[i].phase == ACTIVE)
            return i;
    return -1;
}

static int remaining(Tracker *tracker, int sprint) {
    int total = 0;
    for (int i = 0; i < tracker->issue_count; ++i)
        if (tracker->issues[i].sprint == sprint && !done(&tracker->issues[i]))
            total += points(&tracker->issues[i]);
    return total;
}

static void print_summary(Tracker *tracker, int sprint) {
    int count = 0, total = 0;
    for (int i = 0; i < tracker->issue_count; ++i)
        if (tracker->issues[i].sprint == sprint) {
            ++count;
            total += points(&tracker->issues[i]);
        }
    printf("issues %d points %d", count, total);
}

static void record(Tracker *tracker, int index, char *format, ...) {
    Issue *issue = &tracker->issues[index];
    char content[128], line[160];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(content, sizeof(content), format, arguments);
    va_end(arguments);
    snprintf(line, sizeof(line), "day %d %s", tracker->day, content);
    if (issue->history_count == issue->history_capacity) {
        int capacity = issue->history_capacity ? issue->history_capacity * 2 : 8;
        char **grown = realloc(issue->history, (size_t)capacity * sizeof(*grown));
        if (!grown)
            exit(EXIT_FAILURE);
        issue->history = grown;
        issue->history_capacity = capacity;
    }
    char *copy = malloc(strlen(line) + 1);
    if (!copy)
        exit(EXIT_FAILURE);
    strcpy(copy, line);
    issue->history[issue->history_count++] = copy;
}

static void notify(Tracker *tracker, int issue, int before) {
    int after = blocked(tracker, issue);
    if (after != before)
        printf("%s %d\n", after ? "BLOCKED" : "UNBLOCKED", tracker->issues[issue].number);
}

static void change_state(Tracker *tracker, int index, int target) {
    Issue *issue = &tracker->issues[index];
    int before[100], ids[100];
    ordered_issues(tracker, ids);
    for (int i = 0; i < tracker->issue_count; ++i)
        before[i] = blocked(tracker, i);
    printf("MOVE %d %s %s\n", issue->number, state_names[issue->state], state_names[target]);
    record(tracker, index, "MOVE %s %s", state_names[issue->state], state_names[target]);
    issue->state = target;
    for (int i = 0; i < tracker->issue_count; ++i)
        if (issue->blocks[ids[i]])
            notify(tracker, ids[i], before[ids[i]]);
}

static int reaches(Tracker *tracker, int start, int goal) {
    int queue[100], head = 0, tail = 0, seen[100] = {0};
    queue[tail++] = start;
    seen[start] = 1;
    while (head < tail) {
        int current = queue[head++];
        if (current == goal)
            return 1;
        for (int i = 0; i < tracker->issue_count; ++i)
            if (tracker->issues[current].blocks[i] && !seen[i]) {
                seen[i] = 1;
                queue[tail++] = i;
            }
    }
    return 0;
}

static int transition(int type, int from, int target) {
    static int edges[][3] = {
        {BUG, OPEN, TRIAGED},         {BUG, TRIAGED, IN_PROGRESS},  {BUG, IN_PROGRESS, REVIEW},
        {BUG, REVIEW, IN_PROGRESS},   {BUG, REVIEW, RESOLVED},      {BUG, RESOLVED, CLOSED},
        {BUG, RESOLVED, REOPENED},    {BUG, CLOSED, REOPENED},      {BUG, REOPENED, IN_PROGRESS},
        {TASK, OPEN, IN_PROGRESS},    {TASK, IN_PROGRESS, OPEN},    {TASK, IN_PROGRESS, DONE},
        {STORY, BACKLOG, READY},      {STORY, READY, BACKLOG},      {STORY, READY, IN_PROGRESS},
        {STORY, IN_PROGRESS, REVIEW}, {STORY, REVIEW, IN_PROGRESS}, {STORY, REVIEW, DONE}};
    for (size_t i = 0; i < sizeof(edges) / sizeof(edges[0]); ++i)
        if (edges[i][0] == type && edges[i][1] == from && edges[i][2] == target)
            return 1;
    return 0;
}

static void lowercase(char *source, char *output) {
    do {
        *output++ = (char)tolower((unsigned char)*source);
    } while (*source++);
}

static int numeric_text(char *text) {
    size_t size = strlen(text);
    if (!size || size > 6)
        return 0;
    for (size_t i = 0; i < size; ++i)
        if (!isdigit((unsigned char)text[i]))
            return 0;
    return 1;
}

static int check_condition(Tracker *tracker, char *token, Condition *result) {
    char field[101], *operations[] = {">=", "<=", "!=", "=", "<", ">", "~"};
    int length = 0;
    while ('a' <= token[length] && token[length] <= 'z')
        ++length;
    memcpy(field, token, (size_t)length);
    field[length] = '\0';
    char *rest = token + length, *operation = NULL;
    for (int i = 0; i < 7; ++i)
        if (strncmp(rest, operations[i], strlen(operations[i])) == 0) {
            operation = operations[i];
            break;
        }
    char *value = operation ? rest + strlen(operation) : rest;
    if (!length || !operation || !*value) {
        printf("ERROR syntax near %s\n", token);
        return 0;
    }
    char *fields[] = {"id",       "type",   "status",   "priority", "assignee", "reviewer",
                      "estimate", "sprint", "comments", "blocked",  "done",     "title"};
    int field_id = name_index(fields, 12, field);
    if (field_id < 0) {
        printf("ERROR unknown field %s\n", field);
        return 0;
    }
    int equality = strcmp(operation, "=") == 0 || strcmp(operation, "!=") == 0;
    int ordered =
        field_id == ID || field_id == PRIORITY || field_id == ESTIMATE || field_id == COMMENTS;
    if ((field_id == TITLE && strcmp(operation, "~") != 0) ||
        (ordered && strcmp(operation, "~") == 0) || (!ordered && field_id != TITLE && !equality)) {
        printf("ERROR bad operator %s\n", token);
        return 0;
    }
    result->field = field_id;
    result->number = -1;
    strcpy(result->operation, operation);
    strcpy(result->value, value);
    if (strcmp(value, "-") == 0 && equality &&
        (field_id == ASSIGNEE || field_id == REVIEWER || field_id == ESTIMATE ||
         field_id == SPRINT))
        return 1;
    if ((field_id == ID || field_id == ESTIMATE || field_id == COMMENTS) && numeric_text(value)) {
        result->number = atoi(value);
        return 1;
    }
    if (field_id == PRIORITY && (result->number = name_index(priorities, 4, value)) >= 0)
        return 1;
    if ((field_id == TYPE && name_index(type_names, 3, value) >= 0) ||
        (field_id == STATUS && name_index(state_names, 10, value) >= 0) ||
        ((field_id == ASSIGNEE || field_id == REVIEWER) && user_index(tracker, value) >= 0) ||
        (field_id == SPRINT && sprint_index(tracker, value) >= 0) ||
        ((field_id == BLOCKED || field_id == FINISHED) &&
         (strcmp(value, "yes") == 0 || strcmp(value, "no") == 0)))
        return 1;
    if (field_id == TITLE) {
        lowercase(value, result->value);
        return 1;
    }
    printf("ERROR bad value %s\n", token);
    return 0;
}

static int check_query(Tracker *tracker, char *text, Query *query) {
    query->count = query->position = 0;
    for (int position = 0; text[position];) {
        if (text[position] == ' ') {
            ++position;
            continue;
        }
        char *token = query->tokens[query->count++];
        int size = 0;
        if (text[position] == '(' || text[position] == ')')
            token[size++] = text[position++];
        else
            while (text[position] && text[position] != ' ' && text[position] != '(' &&
                   text[position] != ')')
                token[size++] = text[position++];
        token[size] = '\0';
    }
    int operand = 1, depth = 0;
    for (int i = 0; i < query->count; ++i) {
        char *token = query->tokens[i];
        if (operand) {
            if (strcmp(token, "(") == 0)
                ++depth;
            else if (strcmp(token, "AND") == 0 || strcmp(token, "OR") == 0 ||
                     strcmp(token, ")") == 0) {
                printf("ERROR syntax near %s\n", token);
                return 0;
            } else if (strcmp(token, "NOT") != 0) {
                if (!check_condition(tracker, token, &query->conditions[i]))
                    return 0;
                operand = 0;
            }
        } else if (strcmp(token, "AND") == 0 || strcmp(token, "OR") == 0)
            operand = 1;
        else if (strcmp(token, ")") == 0 && depth > 0)
            --depth;
        else {
            printf("ERROR syntax near %s\n", token);
            return 0;
        }
    }
    if (operand || depth) {
        puts("ERROR syntax at end");
        return 0;
    }
    return 1;
}

static int matches(Tracker *tracker, int id, Condition *condition) {
    Issue *issue = &tracker->issues[id];
    int field = condition->field;
    if (field == ID || field == PRIORITY || field == ESTIMATE || field == COMMENTS) {
        int actual = field == ID         ? issue->number
                     : field == PRIORITY ? issue->priority
                     : field == ESTIMATE ? issue->estimate
                                         : issue->comments;
        int expected = condition->number;
        char *operation = condition->operation;
        if (strcmp(operation, "=") == 0)
            return actual == expected;
        if (strcmp(operation, "!=") == 0)
            return actual != expected;
        if (actual < 0)
            return 0;
        if (strcmp(operation, "<") == 0)
            return actual < expected;
        if (strcmp(operation, "<=") == 0)
            return actual <= expected;
        if (strcmp(operation, ">") == 0)
            return actual > expected;
        return actual >= expected;
    }
    char title[41], *actual;
    if (field == TYPE)
        actual = type_names[issue->type];
    else if (field == STATUS)
        actual = state_names[issue->state];
    else if (field == ASSIGNEE)
        actual = user_name(tracker, issue->assignee);
    else if (field == REVIEWER)
        actual = user_name(tracker, issue->reviewer);
    else if (field == SPRINT)
        actual = sprint_name(tracker, issue->sprint);
    else if (field == BLOCKED)
        actual = blocked(tracker, id) ? "yes" : "no";
    else if (field == FINISHED)
        actual = done(issue) ? "yes" : "no";
    else {
        lowercase(issue->title, title);
        actual = title;
    }
    if (field == TITLE)
        return strstr(actual, condition->value) != NULL;
    int equal = strcmp(actual, condition->value) == 0;
    return strcmp(condition->operation, "=") == 0 ? equal : !equal;
}

static int query_expression(Tracker *tracker, Query *query, int issue);

static int query_factor(Tracker *tracker, Query *query, int issue) {
    char *token = query->tokens[query->position++];
    if (strcmp(token, "NOT") == 0)
        return !query_factor(tracker, query, issue);
    if (strcmp(token, "(") == 0) {
        int result = query_expression(tracker, query, issue);
        ++query->position;
        return result;
    }
    return matches(tracker, issue, &query->conditions[query->position - 1]);
}

static int query_term(Tracker *tracker, Query *query, int issue) {
    int result = query_factor(tracker, query, issue);
    while (query->position < query->count && strcmp(query->tokens[query->position], "AND") == 0) {
        ++query->position;
        int right = query_factor(tracker, query, issue);
        result = result && right;
    }
    return result;
}

static int query_expression(Tracker *tracker, Query *query, int issue) {
    int result = query_term(tracker, query, issue);
    while (query->position < query->count && strcmp(query->tokens[query->position], "OR") == 0) {
        ++query->position;
        int right = query_term(tracker, query, issue);
        result = result || right;
    }
    return result;
}

static void print_links(Tracker *tracker, int issue, int kind) {
    int ids[100], count = 0;
    ordered_issues(tracker, ids);
    for (int i = 0; i < tracker->issue_count; ++i) {
        int id = ids[i];
        int included = kind == 0   ? tracker->issues[issue].blocks[id]
                       : kind == 1 ? tracker->issues[id].blocks[issue]
                                   : tracker->issues[id].duplicate == issue;
        if (included) {
            printf("%s%d", count ? "," : "", tracker->issues[id].number);
            ++count;
        }
    }
    if (!count)
        putchar('-');
}

static void join_words(char *words[], int begin, int count, char *output) {
    output[0] = '\0';
    for (int i = begin; i < count; ++i) {
        if (i > begin)
            strcat(output, " ");
        strcat(output, words[i]);
    }
}

#define REJECT(...)                                                                                \
    do {                                                                                           \
        printf("ERROR ");                                                                          \
        printf(__VA_ARGS__);                                                                       \
        putchar('\n');                                                                             \
        return;                                                                                    \
    } while (0)

static void execute(Tracker *tracker, char *words[], int word_count) {
    char *command = words[0];
    int ids[100];
    ordered_issues(tracker, ids);
    if (strcmp(command, "DAY") == 0) {
        int day = atoi(words[1]);
        if (day < tracker->day)
            REJECT("day backwards");
        tracker->day = day;
        printf("DAY %d\n", day);
        return;
    }
    if (strcmp(command, "USER") == 0) {
        if (user_index(tracker, words[1]) >= 0)
            REJECT("user exists");
        strcpy(tracker->users[tracker->user_count++], words[1]);
        printf("USER %s\n", words[1]);
        return;
    }
    if (strcmp(command, "CREATE") == 0) {
        int number = atoi(words[1]), type = name_index(type_names, 3, words[2]),
            priority = name_index(priorities, 4, words[3]);
        if (issue_index(tracker, number) >= 0)
            REJECT("issue exists");
        if (type < 0)
            REJECT("bad type");
        if (priority < 0)
            REJECT("bad priority");
        int index = tracker->issue_count++;
        Issue *issue = &tracker->issues[index];
        issue->number = number;
        issue->type = type;
        issue->priority = priority;
        issue->state = workflows[type][0];
        issue->assignee = issue->reviewer = issue->estimate = issue->sprint = issue->duplicate = -1;
        join_words(words, 4, word_count, issue->title);
        record(tracker, index, "CREATE %s %s", words[2], words[3]);
        printf("CREATE %d %s %s %s\n", number, words[2], words[3], state_names[issue->state]);
        return;
    }
    if (strcmp(command, "QUERY") == 0) {
        char text[101];
        Query query;
        join_words(words, 1, word_count, text);
        if (!check_query(tracker, text, &query))
            return;
        int result[100], count = 0;
        for (int priority = 3; priority >= 0; --priority)
            for (int i = 0; i < tracker->issue_count; ++i) {
                int id = ids[i];
                query.position = 0;
                if (tracker->issues[id].priority == priority &&
                    query_expression(tracker, &query, id))
                    result[count++] = id;
            }
        printf("QUERY %d\n", count);
        for (int i = 0; i < count; ++i) {
            Issue *issue = &tracker->issues[result[i]];
            printf("%d %s %s %s %s ", issue->number, type_names[issue->type],
                   priorities[issue->priority], state_names[issue->state],
                   user_name(tracker, issue->assignee));
            print_optional(issue->estimate);
            printf(" %s\n", issue->title);
        }
        return;
    }
    if (strcmp(command, "BOARD") == 0) {
        puts("BOARD");
        int finished = 0;
        for (int type = 0; type < 3; ++type) {
            printf("%s", type_names[type]);
            for (int state = 0; state < state_counts[type]; ++state) {
                int count = 0;
                for (int i = 0; i < tracker->issue_count; ++i)
                    count += tracker->issues[i].type == type &&
                             tracker->issues[i].state == workflows[type][state];
                printf(" %s %d", state_names[workflows[type][state]], count);
            }
            putchar('\n');
        }
        for (int i = 0; i < tracker->issue_count; ++i)
            finished += done(&tracker->issues[i]);
        printf("TOTAL %d open %d done %d\n", tracker->issue_count, tracker->issue_count - finished,
               finished);
        return;
    }
    if (strcmp(command, "WORKLOAD") == 0) {
        int users[20];
        for (int i = 0; i < tracker->user_count; ++i)
            users[i] = i;
        for (int i = 1; i < tracker->user_count; ++i)
            for (int j = i;
                 j > 0 && strcmp(tracker->users[users[j]], tracker->users[users[j - 1]]) < 0; --j) {
                int temporary = users[j];
                users[j] = users[j - 1];
                users[j - 1] = temporary;
            }
        printf("WORKLOAD %d\n", tracker->user_count);
        for (int i = 0; i < tracker->user_count; ++i) {
            int user = users[i], assigned = 0, progressing = 0, review = 0, reviewing = 0,
                total = 0;
            for (int j = 0; j < tracker->issue_count; ++j) {
                Issue *issue = &tracker->issues[j];
                if (issue->assignee == user && !done(issue)) {
                    ++assigned;
                    total += points(issue);
                    progressing += issue->state == IN_PROGRESS;
                    review += issue->state == REVIEW;
                }
                reviewing += issue->reviewer == user && issue->state == REVIEW;
            }
            printf("%s assigned %d in_progress %d review %d reviewing %d points %d\n",
                   tracker->users[user], assigned, progressing, review, reviewing, total);
        }
        return;
    }
    if (strcmp(command, "SPRINTS") == 0) {
        printf("SPRINTS %d\n", tracker->sprint_count);
        for (int i = 0; i < tracker->sprint_count; ++i) {
            Sprint *sprint = &tracker->sprints[i];
            printf("%s %s", sprint->name, phase_names[sprint->phase]);
            if (sprint->phase == ENDED)
                printf(" start %d end %d velocity %d", sprint->start, sprint->end,
                       sprint->velocity);
            else {
                if (sprint->phase == ACTIVE)
                    printf(" start %d", sprint->start);
                putchar(' ');
                print_summary(tracker, i);
                if (sprint->phase == ACTIVE)
                    printf(" remaining %d", remaining(tracker, i));
            }
            putchar('\n');
        }
        return;
    }
    if (strcmp(command, "BURNDOWN") == 0 || strcmp(command, "SPRINT") == 0) {
        int burndown = strcmp(command, "BURNDOWN") == 0;
        char *name = words[burndown ? 1 : 2], *action = burndown ? "" : words[1];
        int index = sprint_index(tracker, name);
        if (!burndown && strcmp(action, "NEW") == 0) {
            if (index >= 0)
                REJECT("sprint exists");
            Sprint *sprint = &tracker->sprints[tracker->sprint_count++];
            strcpy(sprint->name, name);
            for (int i = 0; i < 366; ++i)
                sprint->records[i] = -1;
            printf("SPRINT NEW %s\n", name);
            return;
        }
        if (index < 0)
            REJECT("unknown sprint");
        Sprint *sprint = &tracker->sprints[index];
        if (burndown) {
            if (sprint->phase == PLANNED)
                REJECT("sprint not started");
            int last = sprint->phase == ACTIVE ? tracker->day : sprint->end, value = 0;
            printf("BURNDOWN %s %s days %d\n", name, phase_names[sprint->phase],
                   last - sprint->start + 1);
            for (int day = sprint->start; day <= last; ++day) {
                if (sprint->records[day] >= 0)
                    value = sprint->records[day];
                printf("day %d %d\n", day, value);
            }
        } else if (strcmp(action, "ADD") == 0 || strcmp(action, "REMOVE") == 0) {
            int id = issue_index(tracker, atoi(words[3]));
            if (id < 0)
                REJECT("unknown issue");
            Issue *issue = &tracker->issues[id];
            if (sprint->phase == ENDED)
                REJECT("sprint ended");
            if (strcmp(action, "ADD") == 0) {
                if (done(issue))
                    REJECT("issue done");
                if (issue->sprint >= 0 && tracker->sprints[issue->sprint].phase != ENDED)
                    REJECT("in sprint %s", tracker->sprints[issue->sprint].name);
                if (issue->state == BACKLOG)
                    REJECT("not ready");
                issue->sprint = index;
            } else {
                if (issue->sprint != index)
                    REJECT("not in sprint");
                if (done(issue))
                    REJECT("issue done");
                issue->sprint = -1;
            }
            record(tracker, id, "SPRINT %s %s", action, name);
            printf("SPRINT %s %s %d ", action, name, issue->number);
            print_summary(tracker, index);
            putchar('\n');
        } else if (strcmp(action, "START") == 0) {
            if (sprint->phase != PLANNED)
                REJECT("sprint not planned");
            int active = active_sprint(tracker), count = 0;
            if (active >= 0)
                REJECT("sprint active %s", tracker->sprints[active].name);
            for (int i = 0; i < tracker->issue_count; ++i)
                count += tracker->issues[i].sprint == index;
            if (!count)
                REJECT("sprint empty");
            sprint->phase = ACTIVE;
            sprint->start = tracker->day;
            sprint->records[tracker->day] = remaining(tracker, index);
            printf("SPRINT START %s day %d ", name, tracker->day);
            print_summary(tracker, index);
            printf(" remaining %d\n", remaining(tracker, index));
        } else {
            if (sprint->phase != ACTIVE)
                REJECT("sprint not active");
            sprint->records[tracker->day] = remaining(tracker, index);
            int finished = 0, returned = 0;
            for (int i = 0; i < tracker->issue_count; ++i)
                if (tracker->issues[i].sprint == index) {
                    if (done(&tracker->issues[i])) {
                        ++finished;
                        sprint->velocity += points(&tracker->issues[i]);
                    } else
                        ++returned;
                }
            sprint->phase = ENDED;
            sprint->end = tracker->day;
            printf("SPRINT END %s day %d velocity %d done %d returned %d\n", name, tracker->day,
                   sprint->velocity, finished, returned);
            for (int i = 0; i < tracker->issue_count; ++i) {
                int id = ids[i];
                if (tracker->issues[id].sprint == index && !done(&tracker->issues[id])) {
                    tracker->issues[id].sprint = -1;
                    record(tracker, id, "SPRINT RETURN %s", name);
                    printf("RETURNED %d\n", tracker->issues[id].number);
                }
            }
        }
        return;
    }
    if (strcmp(command, "LINK") == 0 || strcmp(command, "UNLINK") == 0) {
        int unlink = strcmp(command, "UNLINK") == 0, blocks = strcmp(words[2], "BLOCKS") == 0;
        if ((!blocks && unlink) || (!blocks && strcmp(words[2], "DUPLICATES") != 0))
            REJECT("bad link");
        int a = issue_index(tracker, atoi(words[1])), b = issue_index(tracker, atoi(words[3]));
        if (a < 0 || b < 0)
            REJECT("unknown issue");
        Issue *source = &tracker->issues[a], *target = &tracker->issues[b];
        if (!unlink && a == b)
            REJECT("self link");
        int before = blocked(tracker, b);
        if (unlink) {
            if (!source->blocks[b])
                REJECT("no link");
            source->blocks[b] = 0;
        } else if (blocks) {
            if (source->blocks[b])
                REJECT("link exists");
            if (reaches(tracker, b, a))
                REJECT("cycle");
            if (done(target))
                REJECT("issue done");
            source->blocks[b] = 1;
        } else {
            if (source->type != target->type)
                REJECT("type mismatch");
            if (done(source))
                REJECT("issue done");
            if (target->duplicate >= 0)
                REJECT("target is duplicate");
            source->duplicate = b;
        }
        record(tracker, a, "%s %s %d", command, words[2], target->number);
        record(tracker, b, "%s %s %d", command, blocks ? "BLOCKED_BY" : "DUPLICATED_BY",
               source->number);
        printf("%s %d %s %d\n", command, source->number, words[2], target->number);
        if (blocks)
            notify(tracker, b, before);
        else {
            change_state(tracker, a, source->type == BUG ? CLOSED : DONE);
            if (source->sprint >= 0 && tracker->sprints[source->sprint].phase != ENDED) {
                record(tracker, a, "SPRINT REMOVE %s", tracker->sprints[source->sprint].name);
                source->sprint = -1;
            }
        }
        return;
    }
    int index = issue_index(tracker, atoi(words[1]));
    if (index < 0)
        REJECT("unknown issue");
    Issue *issue = &tracker->issues[index];
    int number = issue->number;
    if (strcmp(command, "SHOW") == 0) {
        printf("ISSUE %d %s %s %s blocked %s\nTITLE %s\n", number, type_names[issue->type],
               priorities[issue->priority], state_names[issue->state],
               blocked(tracker, index) ? "yes" : "no", issue->title);
        printf("PEOPLE assignee %s reviewer %s\nPLAN estimate ",
               user_name(tracker, issue->assignee), user_name(tracker, issue->reviewer));
        print_optional(issue->estimate);
        printf(" sprint %s comments %d\nLINKS blocks ", sprint_name(tracker, issue->sprint),
               issue->comments);
        print_links(tracker, index, 0);
        printf(" blocked_by ");
        print_links(tracker, index, 1);
        printf(" duplicate_of ");
        print_optional(issue->duplicate < 0 ? -1 : tracker->issues[issue->duplicate].number);
        printf(" duplicated_by ");
        print_links(tracker, index, 2);
        putchar('\n');
    } else if (strcmp(command, "HISTORY") == 0) {
        printf("HISTORY %d %d\n", number, issue->history_count);
        for (int i = 0; i < issue->history_count; ++i)
            puts(issue->history[i]);
    } else if (strcmp(command, "COMMENT") == 0) {
        if (user_index(tracker, words[2]) < 0)
            REJECT("unknown user");
        char text[61];
        join_words(words, 3, word_count, text);
        ++issue->comments;
        record(tracker, index, "COMMENT %s %s", words[2], text);
        printf("COMMENT %d %d\n", number, issue->comments);
    } else if (strcmp(command, "PRIORITY") == 0) {
        int priority = name_index(priorities, 4, words[2]);
        if (priority < 0)
            REJECT("bad priority");
        if (done(issue))
            REJECT("issue done");
        if (priority == issue->priority)
            REJECT("no change");
        printf("PRIORITY %d %s %s\n", number, priorities[issue->priority], words[2]);
        record(tracker, index, "PRIORITY %s %s", priorities[issue->priority], words[2]);
        issue->priority = priority;
    } else if (strcmp(command, "ASSIGN") == 0 || strcmp(command, "REVIEWER") == 0) {
        int user = user_index(tracker, words[2]), assign = strcmp(command, "ASSIGN") == 0;
        if (user < 0 && strcmp(words[2], "-") != 0)
            REJECT("unknown user");
        if (done(issue))
            REJECT("issue done");
        if (user == (assign ? issue->assignee : issue->reviewer))
            REJECT("no change");
        if (assign) {
            if (user < 0 && (issue->state == IN_PROGRESS || issue->state == REVIEW))
                REJECT("assignee required");
            if (issue->state == IN_PROGRESS && wip(tracker, user) >= 3)
                REJECT("wip limit %s", words[2]);
            if (issue->state == REVIEW && user == issue->reviewer)
                REJECT("reviewer is assignee");
            issue->assignee = user;
        } else {
            if (user < 0 && issue->state == REVIEW)
                REJECT("reviewer required");
            if (issue->state == REVIEW && user == issue->assignee)
                REJECT("reviewer is assignee");
            issue->reviewer = user;
        }
        record(tracker, index, "%s %s", command, words[2]);
        printf("%s %d %s\n", command, number, words[2]);
    } else if (strcmp(command, "ESTIMATE") == 0) {
        int estimate = atoi(words[2]);
        if (estimate != 0 && estimate != 1 && estimate != 2 && estimate != 3 && estimate != 5 &&
            estimate != 8 && estimate != 13 && estimate != 21)
            REJECT("bad estimate");
        if (done(issue))
            REJECT("issue done");
        if (estimate == issue->estimate)
            REJECT("no change");
        char previous[16];
        if (issue->estimate < 0)
            strcpy(previous, "-");
        else
            snprintf(previous, sizeof(previous), "%d", issue->estimate);
        issue->estimate = estimate;
        record(tracker, index, "ESTIMATE %s %d", previous, estimate);
        printf("ESTIMATE %d %s %d\n", number, previous, estimate);
    } else {
        int target = name_index(state_names, 10, words[2]), valid = 0;
        if (issue->duplicate >= 0)
            REJECT("duplicate of %d", tracker->issues[issue->duplicate].number);
        for (int i = 0; i < state_counts[issue->type]; ++i)
            valid |= workflows[issue->type][i] == target;
        if (!valid)
            REJECT("bad state");
        if (!transition(issue->type, issue->state, target))
            REJECT("cannot move %s to %s", state_names[issue->state], words[2]);
        if (target == IN_PROGRESS) {
            int active = active_sprint(tracker);
            if (issue->type == STORY && (active < 0 || issue->sprint != active))
                REJECT("not in active sprint");
            if (issue->assignee < 0)
                REJECT("no assignee");
            if (wip(tracker, issue->assignee) >= 3)
                REJECT("wip limit %s", user_name(tracker, issue->assignee));
        }
        if (target == REVIEW) {
            if (issue->reviewer < 0)
                REJECT("no reviewer");
            if (issue->reviewer == issue->assignee)
                REJECT("reviewer is assignee");
        }
        int blocker = unfinished_blocker(tracker, index);
        if ((target == DONE || target == RESOLVED) && blocker >= 0)
            REJECT("blocked by %d", tracker->issues[blocker].number);
        if (target == READY && issue->estimate < 0)
            REJECT("no estimate");
        change_state(tracker, index, target);
    }
}

int main(void) {
    Tracker *tracker = calloc(1, sizeof(*tracker));
    if (!tracker)
        return 1;
    tracker->day = 1;
    char line[256];
    if (!fgets(line, sizeof(line), stdin)) {
        free(tracker);
        return 0;
    }
    int count = atoi(line);
    for (int command = 0; command < count; ++command) {
        if (!fgets(line, sizeof(line), stdin))
            break;
        line[strcspn(line, "\r\n")] = '\0';
        char *words[128], *token = strtok(line, " ");
        int word_count = 0;
        while (token) {
            words[word_count++] = token;
            token = strtok(NULL, " ");
        }
        execute(tracker, words, word_count);
        int active = active_sprint(tracker);
        if (active >= 0)
            tracker->sprints[active].records[tracker->day] = remaining(tracker, active);
    }
    for (int i = 0; i < tracker->issue_count; ++i) {
        for (int j = 0; j < tracker->issues[i].history_count; ++j)
            free(tracker->issues[i].history[j]);
        free(tracker->issues[i].history);
    }
    free(tracker);
    return 0;
}
