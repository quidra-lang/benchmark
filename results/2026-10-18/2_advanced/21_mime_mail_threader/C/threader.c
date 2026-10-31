#include "mail.h"

static void append(Containers *list, Container *container) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? 2 * list->capacity : 16;
        Container **items = allocate((size_t)capacity * sizeof(*items));
        if (list->count) memcpy(items, list->items, (size_t)list->count * sizeof(*items));
        list->items = items;
        list->capacity = capacity;
    }
    list->items[list->count++] = container;
}
static Container *new_container(char *id) { Container *container = allocate(sizeof(*container)); container->id = id; return container; }
static Container *container_of(Containers *all, char *id) {
    for (int i = 0; i < all->count; ++i) if (all->items[i]->id[0] && !strcmp(all->items[i]->id, id)) return all->items[i];
    Container *container = new_container(id);
    append(all, container);
    return container;
}
static bool ancestor(const Container *first, const Container *second) {
    while (second) { if (first == second) return true; second = second->parent; }
    return false;
}
static void adopt(Container *parent, Container *child) { child->parent = parent; append(&parent->children, child); }
static Containers prune(Containers containers, bool at_root) {
    Containers result = {0};
    for (int i = 0; i < containers.count; ++i) {
        Container *container = containers.items[i];
        container->children = prune(container->children, false);
        if (container->message || (at_root && container->children.count >= 2)) append(&result, container);
        else for (int j = 0; j < container->children.count; ++j) {
            Container *child = container->children.items[j];
            child->parent = at_root ? NULL : container->parent;
            append(&result, child);
        }
    }
    return result;
}
int compare_messages(const Message *first, const Message *second) {
    if (first->date.valid != second->date.valid) return first->date.valid ? -1 : 1;
    if (first->date.valid && first->date.seconds != second->date.seconds) return first->date.seconds < second->date.seconds ? -1 : 1;
    int id_order = strcmp(first->id, second->id);
    return id_order ? id_order : first->number - second->number;
}
static Message *key(const Container *container) {
    if (container->message) return container->message;
    Message *minimum = NULL;
    for (int i = 0; i < container->children.count; ++i) {
        Message *candidate = key(container->children.items[i]);
        if (!minimum || compare_messages(candidate, minimum) < 0) minimum = candidate;
    }
    return minimum;
}
static int container_order(const void *first, const void *second) {
    const Container *a = *(Container *const *)first, *b = *(Container *const *)second;
    return compare_messages(key(a), key(b));
}
static void sort_containers(Containers containers) {
    for (int i = 0; i < containers.count; ++i) sort_containers(containers.items[i]->children);
    if (containers.count > 1) qsort(containers.items, (size_t)containers.count, sizeof(*containers.items), container_order);
}
char *root_subject(const Container *root) {
    return root->message ? root->message->base_subject : root->children.items[0]->message->base_subject;
}
static Containers merge_subjects(Containers roots) {
    Containers result = {0};
    bool *handled = allocate((size_t)roots.count * sizeof(bool));
    for (int i = 0; i < roots.count; ++i) {
        if (handled[i]) continue;
        char *subject = root_subject(roots.items[i]);
        Containers group = {0};
        for (int j = i; j < roots.count; ++j) if (j == i || (subject[0] && !strcmp(subject, root_subject(roots.items[j])))) {
            handled[j] = true;
            append(&group, roots.items[j]);
        }
        if (group.count == 1) { append(&result, group.items[0]); continue; }
        Container *target = NULL, *original = NULL;
        int originals = 0;
        for (int j = 0; j < group.count; ++j) {
            Container *container = group.items[j];
            if (!container->message && !target) target = container;
            if (container->message && !container->message->reply) { original = container; ++originals; }
        }
        if (!target && originals == 1) target = original;
        if (!target) { target = new_container(""); target->subject = subject; }
        for (int j = 0; j < group.count; ++j) {
            Container *container = group.items[j];
            if (container == target) continue;
            if (container->message) adopt(target, container);
            else for (int k = 0; k < container->children.count; ++k) adopt(target, container->children.items[k]);
        }
        append(&result, target);
    }
    return result;
}

Containers build_threads(Message *messages, int count) {
    Containers all = {0};
    for (int i = 0; i < count; ++i) {
        Message *message = &messages[i];
        Container *container;
        if (message->id[0]) container = container_of(&all, message->id);
        else { container = new_container(""); append(&all, container); }
        container->message = message;
        int reference_count = message->references.count;
        Container **references = allocate((size_t)reference_count * sizeof(Container *));
        for (int j = 0; j < reference_count; ++j) references[j] = container_of(&all, message->references.items[j]);
        for (int j = 0; j + 1 < reference_count; ++j) {
            Container *first = references[j], *second = references[j + 1];
            if (!second->parent && !ancestor(second, first)) adopt(first, second);
        }
        if (container->parent) {
            Containers *siblings = &container->parent->children;
            for (int j = 0; j < siblings->count; ++j) if (siblings->items[j] == container) {
                memmove(siblings->items + j, siblings->items + j + 1, (size_t)(siblings->count - j - 1) * sizeof(Container *));
                --siblings->count;
                break;
            }
            container->parent = NULL;
        }
        if (reference_count && !ancestor(container, references[reference_count - 1])) adopt(references[reference_count - 1], container);
    }
    Containers roots = {0};
    for (int i = 0; i < all.count; ++i) if (!all.items[i]->parent) append(&roots, all.items[i]);
    roots = prune(roots, true);
    sort_containers(roots);
    roots = merge_subjects(roots);
    sort_containers(roots);
    return roots;
}
