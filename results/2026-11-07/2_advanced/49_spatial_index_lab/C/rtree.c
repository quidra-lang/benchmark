#include "spatial.h"
Integer area(Box b) {
    return (b.x2 - b.x1) * (b.y2 - b.y1);
}
Box mbr(Box a, Box b) {
    return (Box){a.x1 < b.x1 ? a.x1 : b.x1, a.y1 < b.y1 ? a.y1 : b.y1, a.x2 > b.x2 ? a.x2 : b.x2,
                 a.y2 > b.y2 ? a.y2 : b.y2};
}
Integer enlargement(Box a, Box b) {
    return area(mbr(a, b)) - area(a);
}
bool intersects(Box a, Box b) {
    return a.x1 <= b.x2 && b.x1 <= a.x2 && a.y1 <= b.y2 && b.y1 <= a.y2;
}
bool contains(Box a, Box b) {
    return a.x1 <= b.x1 && b.x2 <= a.x2 && a.y1 <= b.y1 && b.y2 <= a.y2;
}
Integer overlap(Box a, Box b) {
    const Integer w = (a.x2 < b.x2 ? a.x2 : b.x2) - (a.x1 > b.x1 ? a.x1 : b.x1),
                  h = (a.y2 < b.y2 ? a.y2 : b.y2) - (a.y1 > b.y1 ? a.y1 : b.y1);
    return w > 0 && h > 0 ? w * h : 0;
}
Integer distance(Integer x, Integer y, Box b) {
    const Integer dx = x < b.x1   ? b.x1 - x
                       : x > b.x2 ? x - b.x2
                                  : 0,
                  dy = y < b.y1   ? b.y1 - y
                       : y > b.y2 ? y - b.y2
                                  : 0;
    return dx * dx + dy * dy;
}
Box node_box(const RNode *node) {
    Box out = node->entries[0].box;
    for (int i = 1; i < node->n; ++i)
        out = mbr(out, node->entries[i].box);
    return out;
}
RTree rtree_new(int maximum, int minimum) {
    return (RTree){calloc(1, sizeof(RNode)), maximum, minimum};
}
static RNode *split_node(RTree *tree, RNode *node) {
    Entry old[65];
    memcpy(old, node->entries, (size_t)node->n * sizeof *old);
    const int n = node->n;
    int first = 0, second = 1;
    Integer largest = area(mbr(old[0].box, old[1].box)) - area(old[0].box) - area(old[1].box);
    for (int i = 0; i < n - 1; ++i)
        for (int j = i + 1; j < n; ++j) {
            const Integer value = area(mbr(old[i].box, old[j].box)) - area(old[i].box) - area(old[j].box);
            if (value > largest) {
                largest = value;
                first = i;
                second = j;
            }
        }
    Entry a[65] = {old[first]}, b[65] = {old[second]}, rest[65];
    int na = 1, nb = 1, nrest = 0;
    for (int i = 0; i < n; ++i)
        if (i != first && i != second)
            rest[nrest++] = old[i];
    Box ba = a[0].box, bb = b[0].box;
    while (nrest) {
        if (na + nrest == tree->minimum) {
            memcpy(a + na, rest, (size_t)nrest * sizeof *rest);
            na += nrest;
            break;
        }
        if (nb + nrest == tree->minimum) {
            memcpy(b + nb, rest, (size_t)nrest * sizeof *rest);
            nb += nrest;
            break;
        }
        int chosen = 0;
        Integer difference = -1;
        for (int i = 0; i < nrest; ++i) {
            const Integer x = enlargement(ba, rest[i].box), y = enlargement(bb, rest[i].box),
                          value = x > y ? x - y : y - x;
            if (value > difference) {
                difference = value;
                chosen = i;
            }
        }
        const Entry entry = rest[chosen];
        memmove(rest + chosen, rest + chosen + 1, (size_t)(nrest - chosen - 1) * sizeof *rest);
        --nrest;
        const Integer d1 = enlargement(ba, entry.box), d2 = enlargement(bb, entry.box);
        const bool left =
            d1 < d2 || (d1 == d2 && (area(ba) < area(bb) || (area(ba) == area(bb) && na <= nb)));
        if (left) {
            a[na++] = entry;
            ba = mbr(ba, entry.box);
        } else {
            b[nb++] = entry;
            bb = mbr(bb, entry.box);
        }
    }
    node->n = na;
    memcpy(node->entries, a, (size_t)na * sizeof *a);
    RNode *sibling = calloc(1, sizeof *sibling);
    sibling->level = node->level;
    sibling->parent = node->parent;
    sibling->n = nb;
    memcpy(sibling->entries, b, (size_t)nb * sizeof *b);
    for (int i = 0; i < na; ++i)
        if (node->entries[i].child)
            node->entries[i].child->parent = node;
    for (int i = 0; i < nb; ++i)
        if (sibling->entries[i].child)
            sibling->entries[i].child->parent = sibling;
    return sibling;
}
void rtree_insert(RTree *tree, Entry entry, int level) {
    RNode *node = tree->root;
    while (node->level > level) {
        int chosen = 0;
        for (int i = 1; i < node->n; ++i) {
            const Box a = node->entries[i].box, b = node->entries[chosen].box;
            const Integer ea = enlargement(a, entry.box), eb = enlargement(b, entry.box);
            if (ea < eb || (ea == eb && area(a) < area(b)))
                chosen = i;
        }
        node = node->entries[chosen].child;
    }
    node->entries[node->n++] = entry;
    if (entry.child)
        entry.child->parent = node;
    while (true) {
        RNode *sibling = node->n > tree->maximum ? split_node(tree, node) : NULL, *parent = node->parent;
        if (!parent) {
            if (sibling) {
                tree->root = calloc(1, sizeof *tree->root);
                tree->root->level = node->level + 1;
                tree->root->n = 2;
                tree->root->entries[0] = (Entry){.box = node_box(node), .child = node};
                tree->root->entries[1] = (Entry){.box = node_box(sibling), .child = sibling};
                node->parent = sibling->parent = tree->root;
            }
            return;
        }
        for (int i = 0; i < parent->n; ++i)
            if (parent->entries[i].child == node) {
                parent->entries[i].box = node_box(node);
                break;
            }
        if (sibling) {
            parent->entries[parent->n++] = (Entry){.box = node_box(sibling), .child = sibling};
            sibling->parent = parent;
        }
        node = parent;
    }
}
RNode *rtree_leaf(const RNode *node, Point point) {
    if (node->level == 0) {
        for (int i = 0; i < node->n; ++i)
            if (node->entries[i].id == point.id)
                return (RNode *)node;
        return NULL;
    }
    for (int i = 0; i < node->n; ++i)
        if (contains(node->entries[i].box, point_box(point))) {
            RNode *found = rtree_leaf(node->entries[i].child, point);
            if (found)
                return found;
        }
    return NULL;
}
static void remove_entry(RNode *node, int index) {
    memmove(node->entries + index, node->entries + index + 1,
            (size_t)(node->n - index - 1) * sizeof *node->entries);
    --node->n;
}
void rtree_delete(RTree *tree, Point point) {
    RNode *node = rtree_leaf(tree->root, point);
    for (int i = 0; i < node->n; ++i)
        if (node->entries[i].id == point.id) {
            remove_entry(node, i);
            break;
        }
    RNode *removed[64];
    int nremoved = 0;
    while (node != tree->root) {
        RNode *parent = node->parent;
        int position = 0;
        while (parent->entries[position].child != node)
            ++position;
        if (node->n < tree->minimum) {
            remove_entry(parent, position);
            removed[nremoved++] = node;
        } else
            parent->entries[position].box = node_box(node);
        node = parent;
    }
    for (int k = 0; k < nremoved; ++k) {
        RNode *old = removed[k];
        const int n = old->n;
        Entry entries[65];
        memcpy(entries, old->entries, (size_t)n * sizeof *entries);
        for (int i = 0; i < n; ++i)
            rtree_insert(tree, entries[i], old->level);
        free(old);
    }
    while (tree->root->level > 0 && tree->root->n == 1) {
        RNode *old = tree->root;
        tree->root = old->entries[0].child;
        tree->root->parent = NULL;
        free(old);
    }
}
static int entry_axis;
static int compare_entries(const void *left, const void *right) {
    const Entry *a = left, *b = right;
    const Integer ax = entry_axis ? a->box.y1 + a->box.y2 : a->box.x1 + a->box.x2,
                  bx = entry_axis ? b->box.y1 + b->box.y2 : b->box.x1 + b->box.x2,
                  ay = entry_axis ? a->box.x1 + a->box.x2 : a->box.y1 + a->box.y2,
                  by = entry_axis ? b->box.x1 + b->box.x2 : b->box.y1 + b->box.y2;
    if (ax != bx)
        return ax < bx ? -1 : 1;
    if (ay != by)
        return ay < by ? -1 : 1;
    return (a->number > b->number) - (a->number < b->number);
}
void rtree_bulk(RTree *tree, const Entry *source, int n) {
    rtree_free(tree->root);
    Entry *entries = malloc((size_t)n * sizeof *entries);
    memcpy(entries, source, (size_t)n * sizeof *entries);
    int level = 0;
    while (true) {
        const int pages = (n + tree->maximum - 1) / tree->maximum;
        int slabs = 1;
        while (slabs * slabs < pages)
            ++slabs;
        entry_axis = 0;
        qsort(entries, (size_t)n, sizeof *entries, compare_entries);
        RNode **nodes = malloc((size_t)n * sizeof *nodes);
        int nnodes = 0;
        for (int start = 0; start < n; start += slabs * tree->maximum) {
            const int end = start + slabs * tree->maximum < n ? start + slabs * tree->maximum : n;
            entry_axis = 1;
            qsort(entries + start, (size_t)(end - start), sizeof *entries, compare_entries);
            for (int begin = start; begin < end; begin += tree->maximum) {
                RNode *node = calloc(1, sizeof *node);
                node->level = level;
                node->n = begin + tree->maximum < end ? tree->maximum : end - begin;
                memcpy(node->entries, entries + begin, (size_t)node->n * sizeof *entries);
                for (int i = 0; i < node->n; ++i)
                    if (node->entries[i].child)
                        node->entries[i].child->parent = node;
                nodes[nnodes++] = node;
            }
        }
        free(entries);
        if (nnodes == 1) {
            tree->root = nodes[0];
            tree->root->parent = NULL;
            free(nodes);
            return;
        }
        n = nnodes;
        entries = malloc((size_t)n * sizeof *entries);
        for (int i = 0; i < n; ++i)
            entries[i] = (Entry){.box = node_box(nodes[i]), .number = i, .child = nodes[i]};
        free(nodes);
        ++level;
    }
}
void rtree_free(RNode *node) {
    if (!node)
        return;
    if (node->level > 0)
        for (int i = 0; i < node->n; ++i)
            rtree_free(node->entries[i].child);
    free(node);
}
