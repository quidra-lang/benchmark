#include "bgp.h"
#include <stdlib.h>
#include <string.h>
uint32_t community(const char *text) {
    if (strcmp(text, "NO_EXPORT") == 0)
        return NO_EXPORT;
    return (uint32_t)strtoul(text, NULL, 10) * UINT32_C(65536) +
           (uint32_t)strtoul(strchr(text, ':') + 1, NULL, 10);
}
char *community_text(uint32_t value) {
    return value == NO_EXPORT
               ? copy_text("NO_EXPORT")
               : format_text("%u:%u", (unsigned)(value >> 16), (unsigned)(value & 65535));
}
bool community_has(const Communities *values, uint32_t value) {
    for (size_t i = 0; i < values->count; ++i)
        if (values->items[i] == value)
            return true;
    return false;
}
void community_add(Communities *values, uint32_t value) {
    size_t at = 0;
    while (at < values->count && values->items[at] < value)
        ++at;
    if (at < values->count && values->items[at] == value)
        return;
    values->items = resize(values->items, (values->count + 1) * sizeof(uint32_t));
    memmove(values->items + at + 1, values->items + at, (values->count - at) * sizeof(uint32_t));
    values->items[at] = value;
    ++values->count;
}
void community_remove(Communities *values, uint32_t value) {
    for (size_t i = 0; i < values->count; ++i)
        if (values->items[i] == value) {
            memmove(values->items + i, values->items + i + 1,
                    (values->count - i - 1) * sizeof(uint32_t));
            --values->count;
            return;
        }
}
Communities communities_copy(const Communities *values) {
    Communities result = {.count = values->count};
    if (result.count) {
        result.items = allocate(result.count * sizeof(uint32_t));
        memcpy(result.items, values->items, result.count * sizeof(uint32_t));
    }
    return result;
}
Communities parse_communities(const Words *words, size_t start) {
    Communities result = {0};
    for (size_t i = start; i < words->count; ++i)
        community_add(&result, community(words->items[i]));
    return result;
}
char *communities_text(const Communities *values) {
    if (!values->count)
        return copy_text("-");
    Text text = {0};
    for (size_t i = 0; i < values->count; ++i) {
        if (i)
            text_add(&text, ",");
        char *value = community_text(values->items[i]);
        text_add(&text, value);
        free(value);
    }
    return text_take(&text);
}
void edit_communities(Communities *values, const Rule *rule) {
    for (size_t i = 0; i < rule->edit_count; ++i)
        if (rule->edits[i].add)
            community_add(values, rule->edits[i].community);
        else
            community_remove(values, rule->edits[i].community);
}
static PrefixList *find_list(Policies *p, const char *name, bool create) {
    for (size_t i = 0; i < p->list_count; ++i)
        if (strcmp(p->lists[i].name, name) == 0)
            return &p->lists[i];
    if (!create)
        abort();
    p->lists = resize(p->lists, (p->list_count + 1) * sizeof(PrefixList));
    PrefixList *list = &p->lists[p->list_count++];
    *list = (PrefixList){0};
    strcpy(list->name, name);
    return list;
}
static bool permitted(Policies *p, const char *name, Prefix value) {
    PrefixList *list = find_list(p, name, false);
    for (size_t i = 0; i < list->count; ++i) {
        PrefixEntry entry = list->entries[i];
        if (entry.low <= value.length && value.length <= entry.high &&
            contains(entry.prefix, value.address))
            return entry.permit;
    }
    return false;
}
Rule *rule_named(Policies *p, const char *name) {
    for (int i = 0; i < p->rule_count; ++i)
        if (strcmp(p->rules[i].name, name) == 0)
            return &p->rules[i];
    abort();
}
Rule *applied(Policies *p, bool importing, Session *session, Prefix prefix,
              const Attribute *attribute) {
    for (int i = 0; i < p->rule_count; ++i) {
        Rule *rule = &p->rules[i];
        if (!rule->active || rule->owner != session->owner->number || rule->importing != importing)
            continue;
        char neighbor[16];
        snprintf(neighbor, sizeof(neighbor), "%d", other(session->link, session->owner)->number);
        if (strcmp(rule->target, "*") && strcmp(rule->target, neighbor) &&
            strcmp(rule->target, session->link->name))
            continue;
        bool match = true;
        for (size_t j = 0; j < rule->condition_count; ++j) {
            Condition c = rule->conditions[j];
            if (c.kind == CONDITION_PREFIX)
                match = permitted(p, c.name, prefix);
            else if (c.kind == CONDITION_CONTAINS) {
                match = false;
                for (size_t k = 0; k < attribute->path_count; ++k)
                    if (attribute->path[k] == c.low)
                        match = true;
            } else if (c.kind == CONDITION_ORIGINAS)
                match = (attribute->path_count ? attribute->path[attribute->path_count - 1]
                                               : session->owner->number) == c.low;
            else if (c.kind == CONDITION_LENGTH)
                match = c.low <= (int)attribute->path_count && (int)attribute->path_count <= c.high;
            else
                match = community_has(&attribute->communities, c.community);
            if (!match)
                break;
        }
        if (match)
            return rule;
    }
    return NULL;
}
void read_policies(Policies *p) {
    memset(p, 0, sizeof(*p));
    FILE *file = open_file("input/policies.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        Words a = words(line);
        if (strcmp(a.items[0], "PLIST") == 0) {
            Prefix value = parse_prefix(a.items[3]);
            PrefixEntry entry = {strcmp(a.items[2], "PERMIT") == 0, value, value.length,
                                 value.length};
            bool ge = false, le = false;
            for (size_t i = 4; i < a.count; i += 2)
                if (strcmp(a.items[i], "GE") == 0) {
                    entry.low = atoi(a.items[i + 1]);
                    ge = true;
                } else {
                    entry.high = atoi(a.items[i + 1]);
                    le = true;
                }
            if (ge && !le)
                entry.high = 32;
            PrefixList *list = find_list(p, a.items[1], true);
            list->entries = resize(list->entries, (list->count + 1) * sizeof(PrefixEntry));
            list->entries[list->count++] = entry;
        } else {
            Rule *r = &p->rules[p->rule_count++];
            strcpy(r->name, a.items[1]);
            r->active = strcmp(a.items[2], "ON") == 0;
            r->owner = atoi(a.items[3]);
            r->importing = strcmp(a.items[4], "IMPORT") == 0;
            strcpy(r->target, a.items[5]);
            size_t i = 6;
            while (strcmp(a.items[i], "THEN") != 0) {
                Condition c = {0};
                const char *kind = a.items[i++], *value = a.items[i++];
                if (strcmp(kind, "PREFIX") == 0) {
                    c.kind = CONDITION_PREFIX;
                    strcpy(c.name, value);
                } else if (strcmp(kind, "CONTAINS") == 0) {
                    c.kind = CONDITION_CONTAINS;
                    c.low = atoi(value);
                } else if (strcmp(kind, "ORIGINAS") == 0) {
                    c.kind = CONDITION_ORIGINAS;
                    c.low = atoi(value);
                } else if (strcmp(kind, "LENGTH") == 0) {
                    c.kind = CONDITION_LENGTH;
                    c.low = atoi(value);
                    c.high = atoi(strchr(value, '-') + 1);
                } else {
                    c.kind = CONDITION_COMMUNITY;
                    c.community = community(value);
                }
                r->conditions = resize(r->conditions, (r->condition_count + 1) * sizeof(Condition));
                r->conditions[r->condition_count++] = c;
            }
            ++i;
            while (i < a.count) {
                char *kind = a.items[i++];
                if (strcmp(kind, "DENY") == 0)
                    r->deny = true;
                else if (strcmp(kind, "ALLOW") == 0)
                    r->allow = true;
                else if (strcmp(kind, "LOCALPREF") == 0) {
                    r->has_preference = true;
                    r->preference = atoi(a.items[i++]);
                } else if (strcmp(kind, "MED") == 0) {
                    r->has_med = true;
                    r->med = atoi(a.items[i++]);
                } else if (strcmp(kind, "PREPEND") == 0)
                    r->prepend = atoi(a.items[i++]);
                else {
                    r->edits = resize(r->edits, (r->edit_count + 1) * sizeof(Edit));
                    r->edits[r->edit_count++] =
                        (Edit){strcmp(kind, "ADD") == 0, community(a.items[i++])};
                }
            }
        }
        words_free(&a);
        free(line);
    }
    fclose(file);
}
void policies_free(Policies *p) {
    for (size_t i = 0; i < p->list_count; ++i)
        free(p->lists[i].entries);
    free(p->lists);
    for (int i = 0; i < p->rule_count; ++i) {
        free(p->rules[i].conditions);
        free(p->rules[i].edits);
    }
}
