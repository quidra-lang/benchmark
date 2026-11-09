#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_PERSONS 200
#define MAX_RECORDS 1000
#define TERM_SIZE 1600
#define RELATION_SIZE 2400
#define SCALE INT64_C(137438953472)

typedef struct {
    char id[11], name[21], sex;
    int active, birth, death, parent_count, parents[2];
} Person;

typedef struct {
    int first, second, start, end, status, died;
} Marriage;

enum { CURRENT, DIVORCED, WIDOWED };

typedef struct {
    Person persons[MAX_PERSONS];
    Marriage marriages[MAX_RECORDS];
    int record_count;
} Family;

typedef struct {
    Family *family;
    char line[201];
} Snapshot;

typedef struct {
    int person, da, db, shares;
} Apex;
typedef struct {
    int count;
    char terms[13][TERM_SIZE];
} Relationships;
typedef struct {
    int year, rank, counterpart;
    char text[64];
} Event;

static Family *sort_family;
static int sort_mode, *sort_scores;
static int64_t phi_memo[MAX_PERSONS][MAX_PERSONS];

static char *status_name(int status) {
    return status == CURRENT ? "current" : status == DIVORCED ? "divorced" : "widowed";
}

static char *gendered(char sex, char *male, char *female, char *neutral) {
    return sex == 'M' ? male : sex == 'F' ? female : neutral;
}

static int sex_rank(char sex) {
    return sex == 'M' ? 0 : sex == 'F' ? 1 : 2;
}

static int compare_people(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    Person *pa = &sort_family->persons[a], *pb = &sort_family->persons[b];
    if (sort_mode == 1 && pa->birth != pb->birth)
        return pa->birth < pb->birth ? -1 : 1;
    if (sort_mode == 2 && sort_scores[a] != sort_scores[b])
        return sort_scores[a] < sort_scores[b] ? -1 : 1;
    if (sort_mode == 3 && sex_rank(pa->sex) != sex_rank(pb->sex))
        return sex_rank(pa->sex) - sex_rank(pb->sex);
    return strcmp(pa->id, pb->id);
}

static void order_people(Family *family, int ids[], int count, int mode, int scores[]) {
    sort_family = family;
    sort_mode = mode;
    sort_scores = scores;
    qsort(ids, (size_t)count, sizeof(ids[0]), compare_people);
}

static int all_people(Family *family, int ids[], int age_order) {
    int count = 0;
    for (int i = 0; i < MAX_PERSONS; ++i)
        if (family->persons[i].active)
            ids[count++] = i;
    order_people(family, ids, count, age_order, NULL);
    return count;
}

static int find_person(Family *family, char *id) {
    for (int i = 0; i < MAX_PERSONS; ++i)
        if (family->persons[i].active && strcmp(family->persons[i].id, id) == 0)
            return i;
    return -1;
}

static int checked_person(Family *family, char *id) {
    int result = find_person(family, id);
    if (result < 0)
        printf("ERROR UNKNOWN PERSON %s\n", id);
    return result;
}

static int has_parent(Family *family, int child, int parent) {
    Person *person = &family->persons[child];
    for (int i = 0; i < person->parent_count; ++i)
        if (person->parents[i] == parent)
            return 1;
    return 0;
}

static int children(Family *family, int parent, int ids[]) {
    int count = 0;
    for (int i = 0; i < MAX_PERSONS; ++i)
        if (family->persons[i].active && has_parent(family, i, parent))
            ids[count++] = i;
    return count;
}

static int common_parents(Family *family, int a, int b) {
    int count = 0;
    for (int i = 0; i < family->persons[a].parent_count; ++i)
        count += has_parent(family, b, family->persons[a].parents[i]);
    return count;
}

static int siblings(Family *family, int a, int b) {
    return a != b && common_parents(family, a, b) > 0;
}

static int contains(Marriage *record, int id) {
    return record->first == id || record->second == id;
}

static int other(Marriage *record, int id) {
    return record->first == id ? record->second : record->first;
}

static int current_record(Family *family, int id) {
    for (int i = 0; i < family->record_count; ++i)
        if (family->marriages[i].status == CURRENT && contains(&family->marriages[i], id))
            return i;
    return -1;
}

static int spouse(Family *family, int id) {
    int record = current_record(family, id);
    return record < 0 ? -1 : other(&family->marriages[record], id);
}

static int last_record(Family *family, int a, int b) {
    int last = -1;
    for (int i = 0; i < family->record_count; ++i)
        if (contains(&family->marriages[i], a) && contains(&family->marriages[i], b))
            last = i;
    return last;
}

static int partners(Family *family, int a, int b) {
    int index = last_record(family, a, b);
    return a != b && index >= 0 && family->marriages[index].status != DIVORCED;
}

static void distances(Family *family, int start, int upward, int result[]) {
    int queue[MAX_PERSONS], head = 0, tail = 0;
    for (int i = 0; i < MAX_PERSONS; ++i)
        result[i] = -1;
    result[start] = 0;
    queue[tail++] = start;
    while (head < tail) {
        int current = queue[head++], next[MAX_PERSONS], count;
        if (upward) {
            count = family->persons[current].parent_count;
            for (int i = 0; i < count; ++i)
                next[i] = family->persons[current].parents[i];
        } else {
            count = children(family, current, next);
        }
        for (int i = 0; i < count; ++i) {
            int target = next[i];
            if (result[target] < 0) {
                result[target] = result[current] + 1;
                queue[tail++] = target;
            }
        }
    }
}

static int ancestor(Family *family, int a, int b) {
    int depths[MAX_PERSONS];
    distances(family, b, 1, depths);
    return a != b && depths[a] >= 0;
}

static Apex apex(Family *family, int a, int b) {
    int da[MAX_PERSONS], db[MAX_PERSONS];
    distances(family, a, 1, da);
    distances(family, b, 1, db);
    if (db[a] >= 0)
        return (Apex){a, 0, db[a], 0};
    if (da[b] >= 0)
        return (Apex){b, da[b], 0, 0};
    Apex result = {-1, 0, 0, 0};
    for (int i = 0; i < MAX_PERSONS; ++i) {
        if (da[i] < 0 || db[i] < 0)
            continue;
        if (result.person < 0 || da[i] + db[i] < result.da + result.db ||
            (da[i] + db[i] == result.da + result.db &&
             (da[i] < result.da ||
              (da[i] == result.da &&
               strcmp(family->persons[i].id, family->persons[result.person].id) < 0)))) {
            result.person = i;
            result.da = da[i];
            result.db = db[i];
        }
    }
    if (result.person >= 0)
        for (int i = 0; i < MAX_PERSONS; ++i)
            if (da[i] == result.da && db[i] == result.db)
                ++result.shares;
    return result;
}

static void generation_prefix(int generation, char output[]) {
    output[0] = '\0';
    if (generation == 1)
        return;
    for (int i = 2; i < generation; ++i)
        strcat(output, "great-");
    strcat(output, "grand");
}

static void kinship_term(int da, int db, char sex, char output[]) {
    char prefix[TERM_SIZE];
    if (da == 0 && db == 0) {
        strcpy(output, "self");
    } else if (da == 0) {
        generation_prefix(db, prefix);
        snprintf(output, TERM_SIZE, "%s%s", prefix, gendered(sex, "father", "mother", "parent"));
    } else if (db == 0) {
        generation_prefix(da, prefix);
        snprintf(output, TERM_SIZE, "%s%s", prefix, gendered(sex, "son", "daughter", "child"));
    } else if (da == 1 && db == 1) {
        strcpy(output, gendered(sex, "brother", "sister", "sibling"));
    } else if (da == 1) {
        generation_prefix(db - 1, prefix);
        snprintf(output, TERM_SIZE, "%s%s", prefix, gendered(sex, "uncle", "aunt", "pibling"));
    } else if (db == 1) {
        generation_prefix(da - 1, prefix);
        snprintf(output, TERM_SIZE, "%s%s", prefix, gendered(sex, "nephew", "niece", "nibling"));
    } else {
        char ordinal[32], removal[48] = "";
        char *ordinals[] = {"first", "second",  "third",  "fourth", "fifth",
                            "sixth", "seventh", "eighth", "ninth",  "tenth"};
        int degree = (da < db ? da : db) - 1, difference = abs(da - db);
        if (degree <= 10) {
            strcpy(ordinal, ordinals[degree - 1]);
        } else {
            char *suffix = "th";
            if (degree % 100 < 11 || degree % 100 > 13) {
                if (degree % 10 == 1)
                    suffix = "st";
                else if (degree % 10 == 2)
                    suffix = "nd";
                else if (degree % 10 == 3)
                    suffix = "rd";
            }
            snprintf(ordinal, sizeof(ordinal), "%d%s", degree, suffix);
        }
        if (difference == 1)
            strcpy(removal, " once removed");
        else if (difference == 2)
            strcpy(removal, " twice removed");
        else if (difference >= 3)
            snprintf(removal, sizeof(removal), " %d times removed", difference);
        snprintf(output, TERM_SIZE, "%s cousin%s", ordinal, removal);
    }
}

static void blood_term(Apex common, char sex, char output[]) {
    char term[TERM_SIZE];
    kinship_term(common.da, common.db, sex, term);
    snprintf(output, TERM_SIZE, "%s%s",
             common.shares == 1   ? "half-"
             : common.shares >= 4 ? "double "
                                  : "",
             term);
}

static void add_relationship(Relationships *result, char *term) {
    snprintf(result->terms[result->count++], TERM_SIZE, "%s", term);
}

static int step_siblings(Family *family, int a, int b) {
    for (int i = 0; i < family->persons[a].parent_count; ++i)
        for (int j = 0; j < family->persons[b].parent_count; ++j)
            if (partners(family, family->persons[a].parents[i], family->persons[b].parents[j]))
                return 1;
    return 0;
}

static void relationship(Family *family, int a, int b, char sex, Relationships *result) {
    result->count = 0;
    if (a == b) {
        add_relationship(result, "self");
        return;
    }
    Apex common = apex(family, a, b);
    char term[TERM_SIZE];
    if (common.person >= 0) {
        blood_term(common, sex, term);
        add_relationship(result, term);
    }
    int last = last_record(family, a, b);
    if (last >= 0) {
        Marriage *record = &family->marriages[last];
        if (record->status == CURRENT)
            add_relationship(result, gendered(sex, "husband", "wife", "spouse"));
        else if (record->status == DIVORCED)
            add_relationship(result, gendered(sex, "ex-husband", "ex-wife", "ex-spouse"));
        else if (record->died == a)
            add_relationship(result, gendered(sex, "late husband", "late wife", "late spouse"));
        else
            add_relationship(result, gendered(sex, "widower", "widow", "surviving spouse"));
    } else {
        for (int i = 0; i < MAX_PERSONS; ++i)
            if (family->persons[i].active && has_parent(family, i, a) && has_parent(family, i, b)) {
                add_relationship(result, "co-parent");
                break;
            }
    }
    Person *pa = &family->persons[a], *pb = &family->persons[b];
    int step_parent = 0, step_child = 0, grand_parent = 0, grand_child = 0;
    for (int i = 0; i < pb->parent_count; ++i)
        step_parent |= partners(family, a, pb->parents[i]);
    for (int i = 0; i < pa->parent_count; ++i)
        step_child |= partners(family, b, pa->parents[i]);
    if (!has_parent(family, b, a) && step_parent)
        add_relationship(result, gendered(sex, "stepfather", "stepmother", "stepparent"));
    if (!has_parent(family, a, b) && step_child)
        add_relationship(result, gendered(sex, "stepson", "stepdaughter", "stepchild"));
    if (common_parents(family, a, b) == 0 && step_siblings(family, a, b))
        add_relationship(result, gendered(sex, "stepbrother", "stepsister", "stepsibling"));
    int up_a[MAX_PERSONS], up_b[MAX_PERSONS];
    distances(family, a, 1, up_a);
    distances(family, b, 1, up_b);
    for (int i = 0; i < MAX_PERSONS; ++i) {
        if (up_b[i] == 2 && partners(family, a, i))
            grand_parent = 1;
        if (up_a[i] == 2 && partners(family, b, i))
            grand_child = 1;
    }
    if (!ancestor(family, a, b) && grand_parent)
        add_relationship(result,
                         gendered(sex, "stepgrandfather", "stepgrandmother", "stepgrandparent"));
    if (!ancestor(family, b, a) && grand_child)
        add_relationship(result,
                         gendered(sex, "stepgrandson", "stepgranddaughter", "stepgrandchild"));
    int parent_law = 0, child_law = 0, sibling_law = 0;
    for (int i = 0; i < MAX_PERSONS; ++i) {
        if (!family->persons[i].active)
            continue;
        if (partners(family, b, i)) {
            parent_law |= has_parent(family, i, a);
            sibling_law |= siblings(family, a, i);
        }
        if (partners(family, a, i)) {
            child_law |= has_parent(family, i, b);
            sibling_law |= siblings(family, i, b);
        }
    }
    if (parent_law)
        add_relationship(result, gendered(sex, "father-in-law", "mother-in-law", "parent-in-law"));
    if (child_law)
        add_relationship(result, gendered(sex, "son-in-law", "daughter-in-law", "child-in-law"));
    if (sibling_law)
        add_relationship(result,
                         gendered(sex, "brother-in-law", "sister-in-law", "sibling-in-law"));
}

static void relationship_text(Family *family, int a, int b, char output[]) {
    Relationships result;
    relationship(family, a, b, family->persons[a].sex, &result);
    strcpy(output, result.count ? "" : "no relation");
    for (int i = 0; i < result.count; ++i) {
        if (i)
            strcat(output, ", ");
        strcat(output, result.terms[i]);
    }
}

static int64_t coefficient(Family *family, int a, int b) {
    if (phi_memo[a][b] >= 0)
        return phi_memo[a][b];
    int64_t result = 0;
    Person *first = &family->persons[a], *second = &family->persons[b];
    if (a == b) {
        int64_t inbred = first->parent_count == 2
                             ? coefficient(family, first->parents[0], first->parents[1])
                             : 0;
        result = (SCALE + inbred) / 2;
    } else {
        int x = first->birth >= second->birth ? a : b, y = x == a ? b : a;
        for (int i = 0; i < family->persons[x].parent_count; ++i)
            result += coefficient(family, family->persons[x].parents[i], y);
        result /= 2;
    }
    phi_memo[a][b] = phi_memo[b][a] = result;
    return result;
}

static int64_t inbreeding(Family *family, int id) {
    Person *person = &family->persons[id];
    return person->parent_count == 2 ? coefficient(family, person->parents[0], person->parents[1])
                                     : 0;
}

static void print_fraction(int64_t numerator) {
    int64_t denominator = SCALE;
    while (denominator > 1 && numerator % 2 == 0) {
        numerator /= 2;
        denominator /= 2;
    }
    printf("%" PRId64 "/%" PRId64, numerator, denominator);
}

static void print_life(Person *person) {
    printf("%d-", person->birth);
    if (person->death)
        printf("%d", person->death);
}

static void print_person_list(Family *family, int ids[], int count) {
    order_people(family, ids, count, 1, NULL);
    if (!count)
        printf("-");
    for (int i = 0; i < count; ++i)
        printf("%s%s", i ? " " : "", family->persons[ids[i]].id);
    putchar('\n');
}

static int modify(Family *family, char *words[]) {
    char *command = words[0], *aid = words[1];
    if (strcmp(command, "PERSON") == 0) {
        if (find_person(family, aid) >= 0) {
            printf("ERROR DUPLICATE PERSON %s\n", aid);
            return 0;
        }
        int slot = 0;
        while (family->persons[slot].active)
            ++slot;
        Person person = {0};
        person.active = 1;
        strcpy(person.id, aid);
        person.sex = words[2][0];
        person.birth = atoi(words[3]);
        strcpy(person.name, words[4]);
        family->persons[slot] = person;
        printf("ADDED %s %s %c %d\n", aid, person.name, person.sex, person.birth);
        return 1;
    }
    int a = checked_person(family, aid);
    if (a < 0)
        return 0;
    Person *first = &family->persons[a];
    if (strcmp(command, "DEATH") == 0) {
        int year = atoi(words[2]);
        if (first->death) {
            printf("ERROR ALREADY DECEASED %s\n", aid);
            return 0;
        }
        int bad_year = year < first->birth;
        for (int i = 0; i < family->record_count; ++i) {
            Marriage *record = &family->marriages[i];
            if (contains(record, a) && (year < record->start || year < record->end))
                bad_year = 1;
        }
        if (bad_year) {
            printf("ERROR BAD YEAR %s\n", aid);
            return 0;
        }
        int offspring[MAX_PERSONS], count = children(family, a, offspring);
        order_people(family, offspring, count, 0, NULL);
        for (int i = 0; i < count; ++i)
            if (family->persons[offspring[i]].birth > year + 1) {
                printf("ERROR AFTER DEATH %s %s\n", family->persons[offspring[i]].id, aid);
                return 0;
            }
        first->death = year;
        int index = current_record(family, a);
        printf("DIED %s %d", aid, year);
        if (index >= 0) {
            Marriage *record = &family->marriages[index];
            record->end = year;
            record->status = WIDOWED;
            record->died = a;
            printf(" spouse=%s", family->persons[other(record, a)].id);
        }
        putchar('\n');
        return 1;
    }
    if (strcmp(command, "REMOVE") == 0) {
        for (int i = 0; i < MAX_PERSONS; ++i) {
            Person *person = &family->persons[i];
            int kept = 0;
            for (int j = 0; j < person->parent_count; ++j)
                if (person->parents[j] != a)
                    person->parents[kept++] = person->parents[j];
            person->parent_count = kept;
        }
        int kept = 0;
        for (int i = 0; i < family->record_count; ++i)
            if (!contains(&family->marriages[i], a))
                family->marriages[kept++] = family->marriages[i];
        family->record_count = kept;
        first->active = 0;
        printf("REMOVED %s\n", aid);
        return 1;
    }
    char *bid = words[2];
    int b = checked_person(family, bid);
    if (b < 0)
        return 0;
    Person *second = &family->persons[b];
    if (strcmp(command, "PARENT") == 0) {
        char *reason = NULL;
        if (a == b)
            reason = "SAME PERSON";
        else if (has_parent(family, a, b))
            reason = "ALREADY PARENT";
        else if (first->parent_count == 2)
            reason = "TOO MANY PARENTS";
        else if (ancestor(family, a, b))
            reason = "CYCLE";
        else if (second->birth + 12 > first->birth)
            reason = "AGE GAP";
        else if (second->death && second->death + 1 < first->birth)
            reason = "AFTER DEATH";
        if (reason) {
            printf("ERROR %s %s", reason, aid);
            if (strcmp(reason, "SAME PERSON") != 0 && strcmp(reason, "TOO MANY PARENTS") != 0)
                printf(" %s", bid);
            putchar('\n');
            return 0;
        }
        first->parents[first->parent_count++] = b;
        printf("LINKED %s %s %s\n", aid, bid, gendered(second->sex, "father", "mother", "parent"));
        return 1;
    }
    if (strcmp(command, "UNPARENT") == 0) {
        if (!has_parent(family, a, b)) {
            printf("ERROR NOT PARENT %s %s\n", aid, bid);
            return 0;
        }
        int kept = 0;
        for (int i = 0; i < first->parent_count; ++i)
            if (first->parents[i] != b)
                first->parents[kept++] = first->parents[i];
        first->parent_count = kept;
        printf("UNLINKED %s %s\n", aid, bid);
        return 1;
    }
    int year = atoi(words[3]);
    if (strcmp(command, "SPOUSE") == 0) {
        if (a == b) {
            printf("ERROR SAME PERSON %s\n", aid);
            return 0;
        }
        int couple[] = {a, b};
        for (int i = 0; i < 2; ++i)
            if (family->persons[couple[i]].death) {
                printf("ERROR DECEASED %s\n", family->persons[couple[i]].id);
                return 0;
            }
        for (int i = 0; i < 2; ++i)
            if (spouse(family, couple[i]) >= 0) {
                printf("ERROR ALREADY MARRIED %s\n", family->persons[couple[i]].id);
                return 0;
            }
        if (ancestor(family, a, b) || ancestor(family, b, a) || siblings(family, a, b)) {
            printf("ERROR CLOSE KIN %s %s\n", aid, bid);
            return 0;
        }
        for (int i = 0; i < 2; ++i)
            if (year < family->persons[couple[i]].birth + 16) {
                printf("ERROR TOO YOUNG %s\n", family->persons[couple[i]].id);
                return 0;
            }
        for (int i = 0; i < 2; ++i)
            for (int j = 0; j < family->record_count; ++j) {
                Marriage *record = &family->marriages[j];
                if (contains(record, couple[i]) && record->end && record->end >= year) {
                    printf("ERROR BAD YEAR %s\n", family->persons[couple[i]].id);
                    return 0;
                }
            }
        family->marriages[family->record_count++] = (Marriage){a, b, year, 0, CURRENT, -1};
        printf("MARRIED %s %s %d\n", aid, bid, year);
        return 1;
    }
    if (spouse(family, a) != b) {
        printf("ERROR NOT MARRIED %s %s\n", aid, bid);
        return 0;
    }
    Marriage *record = &family->marriages[current_record(family, a)];
    if (year <= record->start) {
        printf("ERROR BAD YEAR %s\n", aid);
        return 0;
    }
    record->end = year;
    record->status = DIVORCED;
    printf("DIVORCED %s %s %d\n", aid, bid, year);
    return 1;
}

static void tree_visit(Family *family, int id, int depth, int visited[]) {
    printf("%*s%s", 2 * (depth + 1), "", family->persons[id].id);
    if (visited[id]) {
        printf(" (see above)\n");
        return;
    }
    visited[id] = 1;
    printf(" %s ", family->persons[id].name);
    print_life(&family->persons[id]);
    int partner = spouse(family, id);
    if (partner >= 0)
        printf(" = %s", family->persons[partner].id);
    putchar('\n');
    int offspring[MAX_PERSONS], count = children(family, id, offspring);
    order_people(family, offspring, count, 1, NULL);
    for (int i = 0; i < count; ++i)
        tree_visit(family, offspring[i], depth + 1, visited);
}

static void pedigree_visit(Family *family, int id, int number, int generation, int depth, int emit,
                           int *entries, int seen[]) {
    ++*entries;
    seen[id] = 1;
    if (emit) {
        printf("%*s%d %s %s ", 2 * (generation + 1), "", number, family->persons[id].id,
               family->persons[id].name);
        print_life(&family->persons[id]);
        putchar('\n');
    }
    if (generation == depth)
        return;
    int up[2], count = family->persons[id].parent_count;
    for (int i = 0; i < count; ++i)
        up[i] = family->persons[id].parents[i];
    order_people(family, up, count, 3, NULL);
    for (int i = 0; i < count; ++i)
        pedigree_visit(family, up[i], 2 * number + i, generation + 1, depth, emit, entries, seen);
}

static int lineage_length(Family *family, int id, int memo[]) {
    if (memo[id])
        return memo[id];
    int result = 1;
    for (int i = 0; i < family->persons[id].parent_count; ++i) {
        int length = 1 + lineage_length(family, family->persons[id].parents[i], memo);
        if (length > result)
            result = length;
    }
    return memo[id] = result;
}

static int compare_events(const void *left, const void *right) {
    const Event *a = left, *b = right;
    if (a->year != b->year)
        return a->year < b->year ? -1 : 1;
    if (a->rank != b->rank)
        return a->rank - b->rank;
    if (a->counterpart < 0 || b->counterpart < 0)
        return 0;
    return strcmp(sort_family->persons[a->counterpart].id, sort_family->persons[b->counterpart].id);
}

static void timeline(Family *family, int id) {
    Event events[2600];
    int count = 0;
    Person *person = &family->persons[id];
    events[count++] = (Event){person->birth, 0, -1, "born"};
    for (int i = 0; i < family->record_count; ++i) {
        Marriage *record = &family->marriages[i];
        if (!contains(record, id))
            continue;
        int counterpart = other(record, id);
        events[count] = (Event){record->start, 1, counterpart, ""};
        snprintf(events[count++].text, sizeof(events[0].text), "married %s",
                 family->persons[counterpart].id);
        if (record->status == DIVORCED ||
            (record->status == WIDOWED && record->died == counterpart)) {
            events[count] =
                (Event){record->end, record->status == DIVORCED ? 3 : 4, counterpart, ""};
            snprintf(events[count++].text, sizeof(events[0].text), "%s %s",
                     record->status == DIVORCED ? "divorced" : "widowed",
                     family->persons[counterpart].id);
        }
    }
    int offspring[MAX_PERSONS], child_count = children(family, id, offspring);
    for (int i = 0; i < child_count; ++i) {
        int child = offspring[i];
        events[count] = (Event){family->persons[child].birth, 2, child, ""};
        snprintf(events[count++].text, sizeof(events[0].text), "child %s",
                 family->persons[child].id);
    }
    for (int group = 0; group < 2; ++group) {
        int relative_count = group ? child_count : person->parent_count;
        for (int i = 0; i < relative_count; ++i) {
            int relative = group ? offspring[i] : person->parents[i];
            int death = family->persons[relative].death;
            if (death && death >= person->birth && (!person->death || death <= person->death)) {
                events[count] = (Event){death, 5, relative, ""};
                snprintf(events[count++].text, sizeof(events[0].text), "lost %s %s",
                         group ? "child" : "parent", family->persons[relative].id);
            }
        }
    }
    if (person->death)
        events[count++] = (Event){person->death, 6, -1, "died"};
    sort_family = family;
    qsort(events, (size_t)count, sizeof(events[0]), compare_events);
    printf("TIMELINE %s %d\n", person->id, count);
    for (int i = 0; i < count; ++i)
        printf("  %d %s\n", events[i].year, events[i].text);
}

static void census(Family *family, int year) {
    int people[MAX_PERSONS], count = all_people(family, people, 1), residents = 0;
    for (int i = 0; i < count; ++i) {
        Person *person = &family->persons[people[i]];
        if (person->birth <= year && (!person->death || person->death > year))
            ++residents;
    }
    printf("CENSUS %d %d\n", year, residents);
    for (int i = 0; i < count; ++i) {
        int id = people[i];
        Person *person = &family->persons[id];
        if (person->birth > year || (person->death && person->death <= year))
            continue;
        int last = -1;
        for (int j = 0; j < family->record_count; ++j)
            if (contains(&family->marriages[j], id) && family->marriages[j].start <= year)
                last = j;
        printf("  %s %d ", person->id, year - person->birth);
        if (last < 0)
            printf("single");
        else {
            Marriage *record = &family->marriages[last];
            if (!record->end || record->end > year)
                printf("married %s", family->persons[other(record, id)].id);
            else
                printf("%s", status_name(record->status));
        }
        putchar('\n');
    }
}

static void query(Family *family, char *words[], int word_count) {
    char *command = words[0];
    int people[MAX_PERSONS], people_count = all_people(family, people, 0);
    for (int i = 0; i < MAX_PERSONS; ++i)
        for (int j = 0; j < MAX_PERSONS; ++j)
            phi_memo[i][j] = -1;
    if (strcmp(command, "TERM") == 0) {
        int da = atoi(words[1]), db = atoi(words[2]);
        char term[TERM_SIZE];
        kinship_term(da, db, words[3][0], term);
        printf("TERM %d %d %s %s\n", da, db, words[3], term);
        return;
    }
    if (strcmp(command, "CENSUS") == 0) {
        census(family, atoi(words[1]));
        return;
    }
    if (strcmp(command, "STATS") == 0) {
        int living = 0, links = 0, founders = 0, couples = 0, generations = 0,
            memo[MAX_PERSONS] = {0};
        for (int i = 0; i < people_count; ++i) {
            Person *person = &family->persons[people[i]];
            living += !person->death;
            links += person->parent_count;
            founders += person->parent_count == 0;
            int length = lineage_length(family, people[i], memo);
            if (length > generations)
                generations = length;
        }
        for (int i = 0; i < family->record_count; ++i)
            couples += family->marriages[i].status == CURRENT;
        printf("STATS persons=%d living=%d links=%d couples=%d founders=%d generations=%d\n",
               people_count, living, links, couples, founders, generations);
        return;
    }
    if (strcmp(command, "AUDIT") == 0) {
        int marriages[MAX_RECORDS], marriage_count = 0, inbred_ids[MAX_PERSONS], inbred_count = 0;
        for (int i = 0; i < family->record_count; ++i) {
            Marriage *record = &family->marriages[i];
            if (apex(family, record->first, record->second).person >= 0)
                marriages[marriage_count++] = i;
        }
        for (int i = 0; i < people_count; ++i)
            if (inbreeding(family, people[i]))
                inbred_ids[inbred_count++] = people[i];
        printf("AUDIT %d\n", marriage_count + inbred_count);
        for (int i = 0; i < marriage_count; ++i) {
            Marriage *record = &family->marriages[marriages[i]];
            char term[TERM_SIZE];
            blood_term(apex(family, record->first, record->second),
                       family->persons[record->first].sex, term);
            printf("  marriage %s %s %s\n", family->persons[record->first].id,
                   family->persons[record->second].id, term);
        }
        for (int i = 0; i < inbred_count; ++i) {
            printf("  inbred %s ", family->persons[inbred_ids[i]].id);
            print_fraction(inbreeding(family, inbred_ids[i]));
            putchar('\n');
        }
        return;
    }
    int a = checked_person(family, words[1]);
    if (a < 0)
        return;
    Person *first = &family->persons[a];
    if (strcmp(command, "INFO") == 0) {
        printf("INFO %s %s %c ", first->id, first->name, first->sex);
        print_life(first);
        printf("\n  parents: ");
        int ids[MAX_PERSONS], count = first->parent_count;
        for (int i = 0; i < count; ++i)
            ids[i] = first->parents[i];
        print_person_list(family, ids, count);
        for (int i = 0; i < family->record_count; ++i) {
            Marriage *record = &family->marriages[i];
            if (!contains(record, a))
                continue;
            printf("  marriage: %s %d-", family->persons[other(record, a)].id, record->start);
            if (record->end)
                printf("%d", record->end);
            printf(" %s\n", status_name(record->status));
        }
        count = children(family, a, ids);
        printf("  children: ");
        print_person_list(family, ids, count);
        count = 0;
        for (int i = 0; i < people_count; ++i)
            if (siblings(family, a, people[i]))
                ids[count++] = people[i];
        printf("  siblings: ");
        print_person_list(family, ids, count);
        printf("  inbreeding: ");
        print_fraction(inbreeding(family, a));
        putchar('\n');
        return;
    }
    if (strcmp(command, "RELATION") == 0 || strcmp(command, "KINSHIP") == 0 ||
        strcmp(command, "PATH") == 0 || strcmp(command, "COMMON") == 0) {
        int b = checked_person(family, words[2]);
        if (b < 0)
            return;
        if (strcmp(command, "RELATION") == 0) {
            char text[RELATION_SIZE];
            relationship_text(family, a, b, text);
            printf("RELATION %s %s: %s\n", first->id, family->persons[b].id, text);
        } else if (strcmp(command, "KINSHIP") == 0) {
            printf("KINSHIP %s %s ", first->id, family->persons[b].id);
            print_fraction(coefficient(family, a, b));
            putchar('\n');
        } else if (strcmp(command, "PATH") == 0) {
            Apex common = apex(family, a, b);
            printf("PATH %s %s ", first->id, family->persons[b].id);
            if (common.person < 0) {
                printf("none\n");
                return;
            }
            int depths[MAX_PERSONS], routes[2][MAX_PERSONS], counts[2] = {0}, starts[] = {a, b};
            distances(family, common.person, 0, depths);
            for (int side = 0; side < 2; ++side) {
                int current = starts[side];
                routes[side][counts[side]++] = current;
                while (current != common.person) {
                    int up[2], count = family->persons[current].parent_count;
                    for (int i = 0; i < count; ++i)
                        up[i] = family->persons[current].parents[i];
                    order_people(family, up, count, 0, NULL);
                    for (int i = 0; i < count; ++i)
                        if (depths[up[i]] == depths[current] - 1) {
                            current = up[i];
                            routes[side][counts[side]++] = current;
                            break;
                        }
                }
            }
            printf("%d:", common.da + common.db);
            for (int i = 0; i < counts[0]; ++i)
                printf(" %s", family->persons[routes[0][i]].id);
            for (int i = counts[1] - 2; i >= 0; --i)
                printf(" %s", family->persons[routes[1][i]].id);
            putchar('\n');
        } else {
            int da[MAX_PERSONS], db[MAX_PERSONS], ids[MAX_PERSONS], scores[MAX_PERSONS], count = 0;
            distances(family, a, 1, da);
            distances(family, b, 1, db);
            for (int i = 0; i < people_count; ++i) {
                int id = people[i];
                if (da[id] < 0 || db[id] < 0)
                    continue;
                int offspring[MAX_PERSONS], child_count = children(family, id, offspring),
                                            nearest = 1;
                for (int j = 0; j < child_count; ++j)
                    if (da[offspring[j]] >= 0 && db[offspring[j]] >= 0)
                        nearest = 0;
                if (nearest) {
                    ids[count++] = id;
                    scores[id] = da[id] + db[id];
                }
            }
            order_people(family, ids, count, 2, scores);
            printf("COMMON %s %s %d\n", first->id, family->persons[b].id, count);
            for (int i = 0; i < count; ++i)
                printf("  %s %d %d\n", family->persons[ids[i]].id, da[ids[i]], db[ids[i]]);
        }
        return;
    }
    if (strcmp(command, "RELATIVES") == 0 || strcmp(command, "WHO") == 0) {
        int matches[MAX_PERSONS], count = 0;
        char terms[MAX_PERSONS][RELATION_SIZE], sought[201] = "";
        int who = strcmp(command, "WHO") == 0;
        if (who)
            for (int i = 2; i < word_count; ++i) {
                if (i > 2)
                    strcat(sought, " ");
                strcat(sought, words[i]);
            }
        for (int i = 0; i < people_count; ++i) {
            int id = people[i];
            if (id == a)
                continue;
            Relationships actual;
            relationship(family, id, a, family->persons[id].sex, &actual);
            if (!who) {
                if (!actual.count)
                    continue;
                matches[count] = id;
                relationship_text(family, id, a, terms[count++]);
            } else {
                Relationships neutral;
                relationship(family, id, a, 'X', &neutral);
                for (int j = 0; j < actual.count; ++j)
                    if (strcmp(sought, actual.terms[j]) == 0 ||
                        strcmp(sought, neutral.terms[j]) == 0) {
                        matches[count] = id;
                        strcpy(terms[count++], actual.terms[j]);
                        break;
                    }
            }
        }
        printf("%s %s", command, first->id);
        if (who)
            printf(" %s", sought);
        printf(" %d\n", count);
        for (int i = 0; i < count; ++i)
            printf("  %s: %s\n", family->persons[matches[i]].id, terms[i]);
        return;
    }
    if (strcmp(command, "ANCESTORS") == 0 || strcmp(command, "DESCENDANTS") == 0 ||
        strcmp(command, "GENERATIONS") == 0 || strcmp(command, "TREE") == 0) {
        int depths[MAX_PERSONS], ids[MAX_PERSONS], count = 0;
        int upward = strcmp(command, "ANCESTORS") == 0;
        distances(family, a, upward, depths);
        for (int i = 0; i < people_count; ++i)
            if (people[i] != a && depths[people[i]] >= 0)
                ids[count++] = people[i];
        if (strcmp(command, "TREE") == 0) {
            int seen[MAX_PERSONS] = {0};
            printf("TREE %s %d\n", first->id, count);
            tree_visit(family, a, 0, seen);
        } else if (strcmp(command, "GENERATIONS") == 0) {
            int groups = 0;
            for (int g = 1; g <= 19; ++g) {
                int exists = 0;
                for (int i = 0; i < count; ++i)
                    exists |= depths[ids[i]] == g;
                groups += exists;
            }
            printf("GENERATIONS %s %d\n", first->id, groups);
            for (int g = 1; g <= 19; ++g) {
                int members = 0, living = 0, earliest = 2025, latest = 1800;
                for (int i = 0; i < count; ++i) {
                    Person *person = &family->persons[ids[i]];
                    if (depths[ids[i]] != g)
                        continue;
                    ++members;
                    living += !person->death;
                    if (person->birth < earliest)
                        earliest = person->birth;
                    if (person->birth > latest)
                        latest = person->birth;
                }
                if (members)
                    printf("  %d %d %d %d-%d\n", g, members, living, earliest, latest);
            }
        } else {
            order_people(family, ids, count, 2, depths);
            printf("%s %s %d\n", command, first->id, count);
            for (int i = 0; i < count; ++i) {
                int id = ids[i], generation = depths[id];
                char term[TERM_SIZE];
                kinship_term(upward ? 0 : generation, upward ? generation : 0,
                             family->persons[id].sex, term);
                printf("  %d %s %s\n", generation, family->persons[id].id, term);
            }
        }
        return;
    }
    if (strcmp(command, "COUSINS") == 0) {
        int degree = atoi(words[2]), ids[MAX_PERSONS], scores[MAX_PERSONS], count = 0;
        for (int i = 0; i < people_count; ++i) {
            int id = people[i];
            if (id == a)
                continue;
            Apex common = apex(family, id, a);
            if (common.person >= 0 && common.da >= 2 && common.db >= 2 &&
                (common.da < common.db ? common.da : common.db) - 1 == degree) {
                ids[count++] = id;
                scores[id] = abs(common.da - common.db);
            }
        }
        order_people(family, ids, count, 2, scores);
        printf("COUSINS %s %d %d\n", first->id, degree, count);
        for (int i = 0; i < count; ++i) {
            char term[TERM_SIZE];
            blood_term(apex(family, ids[i], a), family->persons[ids[i]].sex, term);
            printf("  %s %s\n", family->persons[ids[i]].id, term);
        }
        return;
    }
    if (strcmp(command, "SIBLINGS") == 0) {
        int ids[MAX_PERSONS], classes[MAX_PERSONS], count = 0, earlier = 0;
        all_people(family, people, 1);
        for (int i = 0; i < people_count; ++i) {
            int id = people[i];
            if (id == a)
                continue;
            int shared = common_parents(family, a, id);
            int kind = shared == 2 ? 0 : shared == 1 ? 1 : step_siblings(family, a, id) ? 2 : -1;
            if (kind < 0)
                continue;
            ids[count] = id;
            classes[count++] = kind;
            if (kind != 2 && (family->persons[id].birth < first->birth ||
                              (family->persons[id].birth == first->birth &&
                               strcmp(family->persons[id].id, first->id) < 0)))
                ++earlier;
        }
        printf("SIBLINGS %s %d order=%d\n", first->id, count, earlier + 1);
        char *names[] = {"full", "half", "step"};
        for (int i = 0; i < count; ++i)
            printf("  %s %s %d\n", family->persons[ids[i]].id, names[classes[i]],
                   family->persons[ids[i]].birth);
        return;
    }
    if (strcmp(command, "PEDIGREE") == 0) {
        int depth = atoi(words[2]), entries = 0, seen[MAX_PERSONS] = {0}, distinct = 0;
        pedigree_visit(family, a, 1, 0, depth, 0, &entries, seen);
        for (int i = 0; i < MAX_PERSONS; ++i)
            distinct += seen[i];
        printf("PEDIGREE %s %d entries=%d distinct=%d\n", first->id, depth, entries, distinct);
        entries = 0;
        pedigree_visit(family, a, 1, 0, depth, 1, &entries, seen);
        return;
    }
    if (strcmp(command, "TIMELINE") == 0) {
        timeline(family, a);
        return;
    }
    char route[201];
    strcpy(route, words[2]);
    int selected[MAX_PERSONS] = {0};
    selected[a] = 1;
    char *step = strtok(route, ".");
    while (step) {
        char sex = 0;
        int kind;
        if (strcmp(step, "parent") == 0 || strcmp(step, "father") == 0 ||
            strcmp(step, "mother") == 0) {
            kind = 0;
            if (strcmp(step, "father") == 0)
                sex = 'M';
            if (strcmp(step, "mother") == 0)
                sex = 'F';
        } else if (strcmp(step, "child") == 0 || strcmp(step, "son") == 0 ||
                   strcmp(step, "daughter") == 0) {
            kind = 1;
            if (strcmp(step, "son") == 0)
                sex = 'M';
            if (strcmp(step, "daughter") == 0)
                sex = 'F';
        } else if (strcmp(step, "sibling") == 0 || strcmp(step, "brother") == 0 ||
                   strcmp(step, "sister") == 0) {
            kind = 2;
            if (strcmp(step, "brother") == 0)
                sex = 'M';
            if (strcmp(step, "sister") == 0)
                sex = 'F';
        } else {
            kind = 3;
            if (strcmp(step, "husband") == 0)
                sex = 'M';
            if (strcmp(step, "wife") == 0)
                sex = 'F';
        }
        int next[MAX_PERSONS] = {0};
        for (int i = 0; i < people_count; ++i) {
            int from = people[i];
            if (!selected[from])
                continue;
            for (int j = 0; j < people_count; ++j) {
                int target = people[j];
                if (sex && family->persons[target].sex != sex)
                    continue;
                int match = kind == 0   ? has_parent(family, from, target)
                            : kind == 1 ? has_parent(family, target, from)
                            : kind == 2 ? siblings(family, from, target)
                                        : spouse(family, from) == target;
                if (match)
                    next[target] = 1;
            }
        }
        memcpy(selected, next, sizeof(selected));
        step = strtok(NULL, ".");
    }
    selected[a] = 0;
    int count = 0;
    for (int i = 0; i < people_count; ++i)
        count += selected[people[i]];
    printf("FIND %s %s %d\n", first->id, words[2], count);
    for (int i = 0; i < people_count; ++i)
        if (selected[people[i]]) {
            char text[RELATION_SIZE];
            relationship_text(family, people[i], a, text);
            printf("  %s: %s\n", family->persons[people[i]].id, text);
        }
}

int main(void) {
    Family *family = calloc(1, sizeof(*family));
    Snapshot history[1000];
    int history_count = 0, command_count;
    char line[256];
    if (!family || !fgets(line, sizeof(line), stdin)) {
        free(family);
        return 1;
    }
    command_count = atoi(line);
    for (int command_index = 0; command_index < command_count; ++command_index) {
        if (!fgets(line, sizeof(line), stdin))
            break;
        line[strcspn(line, "\r\n")] = '\0';
        char parsed[256], *words[32];
        strcpy(parsed, line);
        int word_count = 0;
        char *word = strtok(parsed, " ");
        while (word) {
            words[word_count++] = word;
            word = strtok(NULL, " ");
        }
        if (strcmp(words[0], "UNDO") == 0) {
            if (!history_count)
                printf("ERROR NOTHING TO UNDO\n");
            else {
                Snapshot *saved = &history[--history_count];
                *family = *saved->family;
                printf("UNDONE %s\n", saved->line);
                free(saved->family);
            }
        } else if (strcmp(words[0], "PERSON") == 0 || strcmp(words[0], "DEATH") == 0 ||
                   strcmp(words[0], "REMOVE") == 0 || strcmp(words[0], "PARENT") == 0 ||
                   strcmp(words[0], "UNPARENT") == 0 || strcmp(words[0], "SPOUSE") == 0 ||
                   strcmp(words[0], "DIVORCE") == 0) {
            Family *before = malloc(sizeof(*before));
            if (!before) {
                for (int i = 0; i < history_count; ++i)
                    free(history[i].family);
                free(family);
                return 1;
            }
            *before = *family;
            if (modify(family, words)) {
                history[history_count].family = before;
                strcpy(history[history_count++].line, line);
            } else
                free(before);
        } else
            query(family, words, word_count);
    }
    for (int i = 0; i < history_count; ++i)
        free(history[i].family);
    free(family);
    return 0;
}
