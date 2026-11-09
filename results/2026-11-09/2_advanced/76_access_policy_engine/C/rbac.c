#include "policy.h"
Roles bit(int role) { return UINT64_C(1) << role; }
int cardinality(Roles roles) {
    int count = 0;
    while (roles) {
        roles &= roles - 1;
        ++count;
    }
    return count;
}
int find_role(const RBAC *r, const char *name) {
    for (int i = 0; i < r->role_count; ++i)
        if (!strcmp(r->roles[i], name))
            return i;
    return -1;
}
Roles closure(const RBAC *r, Roles source) {
    Roles previous;
    do {
        previous = source;
        for (int i = 0; i < r->role_count; ++i)
            if (source & bit(i))
                source |= r->inherits[i];
    } while (source != previous);
    return source;
}
Roles assigned(const RBAC *r, const char *user, int day) {
    Roles source = 0;
    for (int i = 0; i < r->assignment_count; ++i) {
        Assignment a = r->assignments[i];
        if (!strcmp(a.user, user) && a.first <= day && day <= a.last)
            source |= bit(a.role);
    }
    return source;
}
Roles authorized(const RBAC *r, const char *user, int day) {
    return closure(r, assigned(r, user, day));
}
static int compare_names(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}
Names role_names(const RBAC *r, Roles source) {
    Names out = {0};
    for (int i = 0; i < r->role_count; ++i)
        if (source & bit(i))
            Names_add(&out, r->roles[i]);
    qsort(out.items, out.count, sizeof(char *), compare_names);
    return out;
}
bool permits(const RBAC *r, int role, const char *action, const char *type) {
    for (int i = 0; i < r->grant_count; ++i) {
        Grant g = r->grants[i];
        if (g.role == role && !strcmp(g.action, action) && !strcmp(g.type, type))
            return true;
    }
    return false;
}
static char *path(const RBAC *r, int from, int to) {
    if (from == to)
        return r->roles[to];
    Names names = role_names(r, r->inherits[from]);
    for (size_t i = 0; i < names.count; ++i) {
        int junior = find_role(r, names.items[i]);
        if (closure(r, bit(junior)) & bit(to))
            return format("%s > %s", r->roles[from], path(r, junior, to));
    }
    return "";
}
static char *accept(RBAC *r, Names f) {
    char **s = f.items, *keyword = s[0];
    if (!strcmp(keyword, "ROLE")) {
        if (find_role(r, s[1]) >= 0)
            return format("duplicate role %s", s[1]);
        r->roles[r->role_count++] = s[1];
    } else if (!strcmp(keyword, "INHERITS")) {
        int senior = find_role(r, s[1]), junior = find_role(r, s[2]);
        if (senior < 0)
            return format("unknown role %s", s[1]);
        if (junior < 0)
            return format("unknown role %s", s[2]);
        if (r->inherits[senior] & bit(junior))
            return format("duplicate inheritance %s %s", s[1], s[2]);
        if (closure(r, bit(junior)) & bit(senior))
            return format("cycle %s > %s", s[1], path(r, junior, senior));
        r->inherits[senior] |= bit(junior);
    } else if (!strcmp(keyword, "PERMIT")) {
        int role = find_role(r, s[1]);
        if (role < 0)
            return format("unknown role %s", s[1]);
        if (permits(r, role, s[2], s[3]))
            return format("duplicate permission %s %s %s", s[1], s[2], s[3]);
        r->grants[r->grant_count++] = (Grant){role, s[2], s[3]};
    } else if (!strcmp(keyword, "SSD") || !strcmp(keyword, "DSD")) {
        bool is_ssd = !strcmp(keyword, "SSD");
        Constraint *constraints = is_ssd ? r->ssd : r->dsd;
        int *count = is_ssd ? &r->ssd_count : &r->dsd_count;
        for (int i = 0; i < *count; ++i)
            if (!strcmp(constraints[i].name, s[1]))
                return format("duplicate constraint %s", s[1]);
        Names names = split(s[3], ",");
        Roles mask = 0;
        for (size_t i = 0; i < names.count; ++i) {
            int role = find_role(r, names.items[i]);
            if (role < 0)
                return format("unknown role %s", names.items[i]);
            mask |= bit(role);
        }
        int n = atoi(s[2]);
        if (n < 2 || n > (int)names.count)
            return format("bad cardinality %s %d", s[1], n);
        constraints[(*count)++] = (Constraint){s[1], n, mask};
    } else {
        int role = find_role(r, s[2]);
        if (role < 0)
            return format("unknown role %s", s[2]);
        int first = atoi(s[3]), last = atoi(s[4]);
        if (!(1 <= first && first <= last && last <= 365))
            return format("bad range %d %d", first, last);
        for (int i = 0; i < r->ssd_count; ++i)
            for (int day = first; day <= last; ++day) {
                Constraint c = r->ssd[i];
                Roles intersection = c.roles & closure(r, assigned(r, s[1], day) | bit(role));
                if (cardinality(intersection) >= c.cardinality)
                    return format("ssd %s day %d roles %s", c.name, day,
                                  join(role_names(r, intersection), ","));
            }
        r->assignments[r->assignment_count++] = (Assignment){s[1], role, first, last};
    }
    return NULL;
}
static int diagnostic_order(const void *a, const void *b) {
    return ((const Diagnostic *)a)->number - ((const Diagnostic *)b)->number;
}
void read_rbac(RBAC *r) {
    Names lines = read_lines("input/rbac.txt");
    const char *keywords[] = {"ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN"};
    for (int k = 0; k < 6; ++k)
        for (size_t i = 0; i < lines.count; ++i) {
            Names f = split(lines.items[i], " ");
            if (strcmp(f.items[0], keywords[k]))
                continue;
            char *error = accept(r, f);
            if (error)
                r->diagnostics[r->diagnostic_count++] = (Diagnostic){(int)i + 1, f.items[0], error};
        }
    qsort(r->diagnostics, (size_t)r->diagnostic_count, sizeof(Diagnostic), diagnostic_order);
}
