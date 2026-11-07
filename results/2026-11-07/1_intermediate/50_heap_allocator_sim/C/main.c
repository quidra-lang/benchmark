#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define LIMIT 2100
#define BLOCKS 8200
static const char *modes[] = {"FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"};
typedef struct {
    int start, size, owner, stamp;
} Block;
typedef struct {
    int size, mode, rover, age, count;
    Block b[BLOCKS];
} Heap;
typedef struct {
    char name[9];
    int state, request, root;
    short *data;
    char **history;
    int events;
} Id;
static Heap heap;
static Id ids[LIMIT];
static unsigned char links[LIMIT][LIMIT];
static int idCount, peak, counters[6];

static int power(int n) {
    return n > 0 && (n & (n - 1)) == 0;
}
static int sizeclass(int n) {
    int k = 0;
    while ((1 << (k + 1)) <= n)
        ++k;
    return k;
}
static int idof(const char *name) {
    for (int i = 1; i <= idCount; ++i)
        if (!strcmp(ids[i].name, name))
            return i;
    strcpy(ids[++idCount].name, name);
    return idCount;
}
static void history(int id, const char *line) {
    Id *p = &ids[id];
    p->history = realloc(p->history, (size_t)(p->events + 1) * sizeof(char *));
    p->history[p->events] = malloc(strlen(line) + 1);
    strcpy(p->history[p->events++], line);
    puts(line);
}
static void initialize(Heap *h, int size, int mode) {
    memset(h, 0, sizeof(*h));
    h->size = size;
    h->mode = mode;
    h->count = 1;
    h->age = 1;
    h->b[0] = (Block){0, size, 0, 1};
}
static void insert(Heap *h, int i, Block b) {
    memmove(h->b + i + 1, h->b + i, (size_t)(h->count - i) * sizeof(Block));
    h->b[i] = b;
    ++h->count;
}
static void erase(Heap *h, int i) {
    --h->count;
    memmove(h->b + i, h->b + i + 1, (size_t)(h->count - i) * sizeof(Block));
}
static int required(const Heap *h, int n) {
    int s = (n + 7) / 8 * 8 + 8;
    if (h->mode == 5) {
        int p = 32;
        while (p < s)
            p *= 2;
        s = p;
    }
    return s;
}
static int locate(const Heap *h, int a) {
    for (int i = 0; i < h->count; ++i)
        if (a < h->b[i].start + h->b[i].size)
            return i;
    return -1;
}
static int blockof(const Heap *h, int id) {
    for (int i = 0; i < h->count; ++i)
        if (h->b[i].owner == id)
            return i;
    return -1;
}
static int allocate(Heap *h, int s, int alignment, int owner) {
    int chosen = -1, place = 0, best1 = 0, best2 = 0;
    int rover = locate(h, h->rover);
    for (int i = 0; i < h->count; ++i) {
        Block b = h->b[i];
        if (b.owner)
            continue;
        int p = (b.start + 8 + alignment - 1) / alignment * alignment - 8;
        if (p > b.start && p - b.start < 16)
            p += alignment;
        if (p + s > b.start + b.size)
            continue;
        int r1 = b.start, r2 = 0;
        if (h->mode == 1)
            r1 = (i - rover + h->count) % h->count;
        if (h->mode == 2 || h->mode == 5) {
            r1 = b.size;
            r2 = b.start;
        }
        if (h->mode == 3) {
            r1 = -b.size;
            r2 = b.start;
        }
        if (h->mode == 4) {
            r1 = sizeclass(b.size);
            r2 = -b.stamp;
        }
        if (chosen < 0 || r1 < best1 || (r1 == best1 && r2 < best2)) {
            chosen = i;
            place = p;
            best1 = r1;
            best2 = r2;
        }
    }
    if (chosen < 0)
        return -1;
    int i = chosen;
    if (h->mode == 5) {
        while (h->b[i].size > s) {
            h->b[i].size /= 2;
            insert(h, i + 1, (Block){h->b[i].start + h->b[i].size, h->b[i].size, 0, ++h->age});
        }
    } else {
        Block old = h->b[i];
        if (place > old.start) {
            h->b[i] = (Block){old.start, place - old.start, 0, ++h->age};
            insert(h, ++i, (Block){place, old.start + old.size - place, 0, 0});
        }
        if (h->b[i].size - s >= 16) {
            int tail = h->b[i].size - s;
            h->b[i].size = s;
            insert(h, i + 1, (Block){place + s, tail, 0, ++h->age});
        }
    }
    h->b[i].owner = owner;
    if (h->mode == 1)
        h->rover = (h->b[i].start + h->b[i].size) % h->size;
    return i;
}
static int coalesce(Heap *h, int i, int *merges) {
    *merges = 0;
    if (h->mode == 5) {
        while (h->b[i].size < h->size) {
            Block b = h->b[i];
            int other = b.start % (2 * b.size) == 0 ? i + 1 : i - 1;
            if (other < 0 || other >= h->count || h->b[other].owner || h->b[other].size != b.size)
                break;
            if (other < i)
                i = other;
            h->b[i].size *= 2;
            erase(h, i + 1);
            ++*merges;
        }
    } else {
        if (i + 1 < h->count && !h->b[i + 1].owner) {
            h->b[i].size += h->b[i + 1].size;
            erase(h, i + 1);
            ++*merges;
        }
        if (i > 0 && !h->b[i - 1].owner) {
            h->b[i - 1].size += h->b[i].size;
            erase(h, i);
            --i;
            ++*merges;
        }
    }
    h->b[i].stamp = ++h->age;
    return i;
}
static int used(const Heap *h) {
    int u = 0;
    for (int i = 0; i < h->count; ++i)
        if (h->b[i].owner)
            u += h->b[i].size;
    return u;
}
static int frag(const Heap *h) {
    int f = 0, l = 0;
    for (int i = 0; i < h->count; ++i)
        if (!h->b[i].owner) {
            f += h->b[i].size;
            if (l < h->b[i].size)
                l = h->b[i].size;
        }
    return f ? (f - l) * 100 / f : 0;
}
static int check(int id) {
    if (ids[id].state == 1)
        return 1;
    printf("ERROR %s %s\n", ids[id].state == 2 ? "USE AFTER FREE" : "UNKNOWN ID", ids[id].name);
    return 0;
}
static void release(int id, const char *verb) {
    int i = blockof(&heap, id), size = heap.b[i].size, merges;
    heap.b[i].owner = 0;
    i = coalesce(&heap, i, &merges);
    ids[id].state = 2;
    ids[id].root = 0;
    for (int j = 1; j <= idCount; ++j)
        links[id][j] = links[j][id] = 0;
    free(ids[id].data);
    ids[id].data = NULL;
    char line[256];
    snprintf(line, sizeof(line), "%s %s block=%d merges=%d free=%d+%d", verb, ids[id].name, size,
             merges, heap.b[i].start, heap.b[i].size);
    history(id, line);
}
static void reachable(unsigned char *seen) {
    memset(seen, 0, LIMIT);
    for (int i = 1; i <= idCount; ++i)
        seen[i] = ids[i].state == 1 && ids[i].root;
    int change = 1;
    while (change) {
        change = 0;
        for (int i = 1; i <= idCount; ++i)
            if (seen[i]) {
                for (int j = 1; j <= idCount; ++j)
                    if (links[i][j] && !seen[j]) {
                        seen[j] = 1;
                        change = 1;
                    }
            }
    }
}
static void tree(int start, int size, int depth) {
    int i = locate(&heap, start);
    printf("%*s%d+%d ", depth * 2, "", start, size);
    if (heap.b[i].start == start && heap.b[i].size == size) {
        if (heap.b[i].owner)
            printf("USED %s\n", ids[heap.b[i].owner].name);
        else
            puts("FREE");
    } else {
        puts("split");
        tree(start, size / 2, depth + 1);
        tree(start + size / 2, size / 2, depth + 1);
    }
}
static void bench(int s, int64_t seed, int ops, int maxreq) {
    if (!power(s) || s < 32 || s > 65536) {
        puts("ERROR BAD HEAP SIZE");
        return;
    }
    printf("BENCH heap=%d seed=%lld ops=%d maxreq=%d\n", s, (long long)seed, ops, maxreq);
    Heap *h = malloc(sizeof(Heap));
    for (int mode = 0; mode < 6; ++mode) {
        initialize(h, s, mode);
        int live[LIMIT], count = 0, serial = 0, ok = 0, fail = 0, top = 0;
        int64_t x = seed;
        for (int step = 0; step < ops; ++step) {
            x = x * 48271 % 2147483647;
            int alloc = !count || x % 3 != 0;
            x = x * 48271 % 2147483647;
            if (alloc) {
                int n = 1 + (int)(x % maxreq), id = ++serial;
                if (allocate(h, required(h, n), 8, id) < 0)
                    ++fail;
                else {
                    live[count++] = id;
                    ++ok;
                }
            } else {
                int at = (int)(x % count), i = blockof(h, live[at]), merges;
                memmove(live + at, live + at + 1, (size_t)(--count - at) * sizeof(int));
                h->b[i].owner = 0;
                coalesce(h, i, &merges);
            }
            int u = used(h);
            if (u > top)
                top = u;
        }
        printf("BENCH %s ok=%d fail=%d peak=%d used=%d frag=%d blocks=%d\n", modes[mode], ok, fail,
               top, used(h), frag(h), h->count);
    }
    free(h);
}
static void command(char **a, int argc) {
    (void)argc;
    const char *op = a[0];
    if (!strcmp(op, "HEAP")) {
        int s = atoi(a[1]), mode = 0;
        while (strcmp(modes[mode], a[2]))
            ++mode;
        if (s < 32 || s > 65536 || s % 8 || (mode == 5 && !power(s))) {
            puts("ERROR BAD HEAP SIZE");
            return;
        }
        for (int i = 1; i <= idCount; ++i) {
            free(ids[i].data);
            for (int j = 0; j < ids[i].events; ++j)
                free(ids[i].history[j]);
            free(ids[i].history);
        }
        memset(ids, 0, sizeof(ids));
        memset(links, 0, sizeof(links));
        memset(counters, 0, sizeof(counters));
        idCount = peak = 0;
        initialize(&heap, s, mode);
        printf("HEAP size=%d mode=%s\n", s, modes[mode]);
        return;
    }
    if (!strcmp(op, "BENCH")) {
        bench(atoi(a[1]), atoll(a[2]), atoi(a[3]), atoi(a[4]));
        return;
    }
    if (!heap.size) {
        puts("ERROR NO HEAP");
        return;
    }
    int id = 0;
    if (!strcmp(op, "MALLOC") || !strcmp(op, "CALLOC") || !strcmp(op, "MEMALIGN") ||
        !strcmp(op, "REALLOC") || !strcmp(op, "FREE")) {
        id = idof(a[1]);
        int n = !strcmp(op, "FREE") ? 0 : atoi(a[2]);
        int alignment = 8, zero = !strcmp(op, "CALLOC");
        const char *verb = op;
        if (zero)
            n *= atoi(a[3]);
        if (!strcmp(op, "MEMALIGN")) {
            alignment = n;
            n = atoi(a[3]);
            if (heap.mode == 5) {
                puts("ERROR UNSUPPORTED IN BUDDY MODE");
                return;
            }
            if (!power(alignment) || alignment < 8 || alignment > 4096) {
                puts("ERROR BAD ALIGNMENT");
                return;
            }
        }
        if (!strcmp(op, "FREE") || (!strcmp(op, "REALLOC") && n == 0)) {
            if (ids[id].state != 1)
                printf("ERROR %s %s\n", ids[id].state == 2 ? "DOUBLE FREE" : "UNKNOWN ID", a[1]);
            else {
                release(id, "FREE");
                ++counters[1];
            }
            return;
        }
        if (!n) {
            puts("ERROR BAD SIZE");
            return;
        }
        if (!strcmp(op, "REALLOC") && ids[id].state == 2) {
            check(id);
            return;
        }
        int s = required(&heap, n);
        if (strcmp(op, "REALLOC") || ids[id].state == 0) {
            if (ids[id].state == 1) {
                printf("ERROR DUPLICATE ID %s\n", a[1]);
                return;
            }
            int i = allocate(&heap, s, alignment, id);
            if (i < 0) {
                printf("ERROR OUT OF MEMORY %s\n", a[1]);
                ++counters[4];
                return;
            }
            if (!strcmp(op, "REALLOC"))
                verb = "MALLOC";
            ids[id].state = 1;
            ids[id].request = n;
            ids[id].data = malloc((size_t)n * sizeof(short));
            for (int j = 0; j < n; ++j)
                ids[id].data[j] = zero ? 0 : -1;
            char line[256];
            snprintf(line, sizeof(line), "%s %s addr=%d block=%d", verb, a[1], heap.b[i].start + 8,
                     heap.b[i].size);
            history(id, line);
            ++counters[0];
            return;
        }
        int i = blockof(&heap, id), oldStart = heap.b[i].start, b = heap.b[i].size;
        const char *kind = "kept";
        if (s <= b) {
            if (heap.mode == 5) {
                if (s < b)
                    kind = "shrunk";
                while (heap.b[i].size > s) {
                    heap.b[i].size /= 2;
                    insert(&heap, i + 1,
                           (Block){oldStart + heap.b[i].size, heap.b[i].size, 0, ++heap.age});
                }
            } else if (b - s >= 16) {
                heap.b[i].size = s;
                insert(&heap, i + 1, (Block){oldStart + s, b - s, 0, 0});
                int merges;
                coalesce(&heap, i + 1, &merges);
                kind = "shrunk";
            }
        } else {
            int grow = 0;
            if (heap.mode != 5)
                grow = i + 1 < heap.count && !heap.b[i + 1].owner && b + heap.b[i + 1].size >= s;
            else {
                int extent = b, j = i + 1;
                grow = 1;
                while (extent < s) {
                    if (oldStart % (2 * extent) || j >= heap.count || heap.b[j].owner ||
                        heap.b[j].start != oldStart + extent || heap.b[j].size != extent) {
                        grow = 0;
                        break;
                    }
                    extent *= 2;
                    ++j;
                }
            }
            if (grow) {
                if (heap.mode == 5) {
                    while (heap.b[i].size < s) {
                        heap.b[i].size *= 2;
                        erase(&heap, i + 1);
                    }
                } else {
                    int total = b + heap.b[i + 1].size;
                    erase(&heap, i + 1);
                    heap.b[i].size = total;
                    if (total - s >= 16) {
                        heap.b[i].size = s;
                        insert(&heap, i + 1, (Block){oldStart + s, total - s, 0, ++heap.age});
                    }
                }
                kind = "grown";
            } else {
                int target = allocate(&heap, s, 8, id);
                if (target < 0) {
                    printf("ERROR OUT OF MEMORY %s\n", a[1]);
                    ++counters[4];
                    return;
                }
                int old = locate(&heap, oldStart);
                heap.b[old].owner = 0;
                int merges;
                coalesce(&heap, old, &merges);
                kind = "moved";
                ++counters[3];
            }
        }
        int oldRequest = ids[id].request;
        ids[id].data = realloc(ids[id].data, (size_t)n * sizeof(short));
        for (int j = oldRequest; j < n; ++j)
            ids[id].data[j] = -1;
        ids[id].request = n;
        i = blockof(&heap, id);
        char line[256];
        snprintf(line, sizeof(line), "REALLOC %s addr=%d block=%d %s", a[1], heap.b[i].start + 8,
                 heap.b[i].size, kind);
        if (!strcmp(kind, "moved")) {
            size_t end = strlen(line);
            snprintf(line + end, sizeof(line) - end, " from=%d", oldStart + 8);
        }
        history(id, line);
        ++counters[2];
        return;
    }
    if (!strcmp(op, "FILL") || !strcmp(op, "READ") || !strcmp(op, "COPY")) {
        id = idof(a[1]);
        if (!check(id))
            return;
        int off = atoi(a[2]), len = atoi(a[!strcmp(op, "COPY") ? 5 : 3]);
        if (off + len > ids[id].request) {
            printf("ERROR OUT OF BOUNDS %s\n", a[1]);
            return;
        }
        if (!strcmp(op, "COPY")) {
            int src = idof(a[3]), soff = atoi(a[4]);
            if (!check(src))
                return;
            if (soff + len > ids[src].request) {
                printf("ERROR OUT OF BOUNDS %s\n", a[3]);
                return;
            }
            memmove(ids[id].data + off, ids[src].data + soff, (size_t)len * sizeof(short));
            printf("COPY %s %d+%d from %s %d\n", a[1], off, len, a[3], soff);
        } else if (!strcmp(op, "FILL")) {
            int v = atoi(a[4]);
            for (int j = off; j < off + len; ++j)
                ids[id].data[j] = (short)v;
            printf("FILL %s %d+%d = %d\n", a[1], off, len, v);
        } else {
            printf("READ %s %d+%d =", a[1], off, len);
            for (int j = off; j < off + len; ++j) {
                if (ids[id].data[j] < 0)
                    printf(" ?");
                else
                    printf(" %d", ids[id].data[j]);
            }
            putchar('\n');
        }
        return;
    }
    if (!strcmp(op, "ROOT") || !strcmp(op, "UNROOT") || !strcmp(op, "LINK") ||
        !strcmp(op, "UNLINK")) {
        id = idof(a[1]);
        if (!check(id))
            return;
        if (!strcmp(op, "ROOT")) {
            ids[id].root = 1;
            printf("ROOT %s\n", a[1]);
        } else if (!strcmp(op, "UNROOT")) {
            if (!ids[id].root)
                printf("ERROR NOT ROOT %s\n", a[1]);
            else {
                ids[id].root = 0;
                printf("UNROOT %s\n", a[1]);
            }
        } else {
            int dst = idof(a[2]);
            if (!check(dst))
                return;
            if (!strcmp(op, "UNLINK") && !links[id][dst])
                printf("ERROR NO LINK %s %s\n", a[1], a[2]);
            else {
                links[id][dst] = !strcmp(op, "LINK");
                printf("%s %s %s\n", op, a[1], a[2]);
            }
        }
        return;
    }
    if (!strcmp(op, "GC") || !strcmp(op, "LEAKS")) {
        unsigned char seen[LIMIT];
        reachable(seen);
        int list[LIMIT], count = 0, bytes = 0, lost = 0;
        for (int i = 0; i < heap.count; ++i)
            if (heap.b[i].owner) {
                id = heap.b[i].owner;
                if (!seen[id])
                    ++lost;
                if (strcmp(op, "GC") || !seen[id]) {
                    list[count++] = id;
                    bytes += !strcmp(op, "GC") ? heap.b[i].size : ids[id].request;
                }
            }
        if (!strcmp(op, "GC")) {
            printf("GC collected=%d bytes=%d\n", count, bytes);
            for (int j = 0; j < count; ++j)
                release(list[j], "COLLECT");
            counters[5] += count;
        } else {
            printf("LEAKS count=%d requested=%d lost=%d\n", count, bytes, lost);
            for (int j = 0; j < count; ++j)
                for (int k = j + 1; k < count; ++k)
                    if (strcmp(ids[list[j]].name, ids[list[k]].name) > 0) {
                        int t = list[j];
                        list[j] = list[k];
                        list[k] = t;
                    }
            for (int j = 0; j < count; ++j) {
                id = list[j];
                Block b = heap.b[blockof(&heap, id)];
                printf("LEAK %s addr=%d block=%d req=%d %s\n", ids[id].name, b.start + 8, b.size,
                       ids[id].request, seen[id] ? "reachable" : "lost");
            }
        }
        return;
    }
    if (!strcmp(op, "HISTORY")) {
        id = idof(a[1]);
        printf("HISTORY %s events=%d\n", a[1], ids[id].events);
        for (int j = 0; j < ids[id].events; ++j)
            puts(ids[id].history[j]);
        return;
    }
    if (!strcmp(op, "SBRK")) {
        int k = atoi(a[1]);
        if (heap.size + k > 65536 || (heap.mode == 5 ? k != heap.size : k < 16 || k % 8)) {
            puts("ERROR BAD SBRK SIZE");
            return;
        }
        insert(&heap, heap.count, (Block){heap.size, k, 0, 0});
        heap.size += k;
        int merges, i = coalesce(&heap, heap.count - 1, &merges);
        printf("SBRK heap=%d free=%d+%d\n", heap.size, heap.b[i].start, heap.b[i].size);
        return;
    }
    if (!strcmp(op, "TRIM")) {
        int old = heap.size;
        while (heap.count > 1 && !heap.b[heap.count - 1].owner) {
            Block b = heap.b[heap.count - 1];
            if (heap.mode == 5 && b.size * 2 != heap.size)
                break;
            heap.size = b.start;
            --heap.count;
            if (heap.mode != 5)
                break;
        }
        if (heap.rover >= heap.size)
            heap.rover = 0;
        printf("TRIM heap=%d released=%d\n", heap.size, old - heap.size);
        return;
    }
    if (!strcmp(op, "COMPACT")) {
        if (heap.mode == 5) {
            puts("ERROR UNSUPPORTED IN BUDDY MODE");
            return;
        }
        int pos = 0, count = 0, moved = 0, moveIds[LIMIT], from[LIMIT], to[LIMIT];
        for (int i = 0; i < heap.count; ++i)
            if (heap.b[i].owner) {
                Block b = heap.b[i];
                if (b.start != pos) {
                    moveIds[moved] = b.owner;
                    from[moved] = b.start + 8;
                    to[moved++] = pos + 8;
                }
                b.start = pos;
                pos += b.size;
                heap.b[count++] = b;
            }
        heap.count = count;
        if (pos < heap.size)
            insert(&heap, count, (Block){pos, heap.size - pos, 0, ++heap.age});
        heap.rover = 0;
        counters[3] += moved;
        printf("COMPACT moved=%d free=", moved);
        if (pos == heap.size)
            puts("none");
        else
            printf("%d+%d\n", pos, heap.size - pos);
        for (int j = 0; j < moved; ++j) {
            char line[256];
            snprintf(line, sizeof(line), "MOVE %s %d -> %d", ids[moveIds[j]].name, from[j], to[j]);
            history(moveIds[j], line);
        }
        return;
    }
    if (!strcmp(op, "WHO")) {
        int p = atoi(a[1]);
        printf("WHO %d ", p);
        if (p >= heap.size)
            puts("outside");
        else {
            Block b = heap.b[locate(&heap, p)];
            if (!b.owner)
                printf("free %d+%d\n", b.start, b.size);
            else if (p < b.start + 8)
                printf("header %s\n", ids[b.owner].name);
            else
                printf("%s %s+%d\n", p - b.start - 8 < ids[b.owner].request ? "data" : "slack",
                       ids[b.owner].name, p - b.start - 8);
        }
        return;
    }
    if (!strcmp(op, "DUMP")) {
        printf("DUMP mode=%s heap=%d blocks=%d", modes[heap.mode], heap.size, heap.count);
        if (heap.mode == 1)
            printf(" rover=%d", heap.rover);
        putchar('\n');
        for (int i = 0; i < heap.count; ++i) {
            Block b = heap.b[i];
            printf("%d %d ", b.start, b.size);
            if (!b.owner)
                puts("FREE");
            else
                printf("USED %s req=%d\n", ids[b.owner].name, ids[b.owner].request);
        }
    } else if (!strcmp(op, "MAP")) {
        char map[8193];
        int count = 0;
        printf("MAP heap=%d\n", heap.size);
        for (int i = 0; i < heap.count; ++i) {
            Block b = heap.b[i];
            map[count++] = b.owner ? 'H' : 'F';
            for (int j = 0; j < b.size / 8 - 1; ++j)
                map[count++] = !b.owner ? '.' : j * 8 < ids[b.owner].request ? '#' : '-';
        }
        for (int j = 0; j < count; j += 64)
            printf("%05d %.*s\n", j * 8, count - j < 64 ? count - j : 64, map + j);
    } else if (!strcmp(op, "FREELIST")) {
        int list[BLOCKS], count = 0;
        for (int i = 0; i < heap.count; ++i)
            if (!heap.b[i].owner)
                list[count++] = i;
        printf("FREELIST count=%d\n", count);
        for (int k = 0; k <= 16; ++k) {
            int members[BLOCKS], n = 0;
            for (int j = 0; j < count; ++j)
                if (sizeclass(heap.b[list[j]].size) == k)
                    members[n++] = list[j];
            if (!n)
                continue;
            if (heap.mode == 4)
                for (int j = 0; j < n; ++j)
                    for (int l = j + 1; l < n; ++l)
                        if (heap.b[members[j]].stamp < heap.b[members[l]].stamp) {
                            int t = members[j];
                            members[j] = members[l];
                            members[l] = t;
                        }
            printf("%d-%d:", 1 << k, (1 << (k + 1)) - 1);
            for (int j = 0; j < n; ++j)
                printf(" %d+%d", heap.b[members[j]].start, heap.b[members[j]].size);
            putchar('\n');
        }
    } else if (!strcmp(op, "TREE")) {
        if (heap.mode != 5)
            puts("ERROR REQUIRES BUDDY MODE");
        else {
            printf("TREE heap=%d\n", heap.size);
            tree(0, heap.size, 0);
        }
    } else if (!strcmp(op, "STATS")) {
        int u = used(&heap), ub = 0, fb = 0, largest = 0, req = 0;
        for (int i = 0; i < heap.count; ++i) {
            Block b = heap.b[i];
            if (b.owner) {
                ++ub;
                req += ids[b.owner].request;
            } else {
                ++fb;
                if (b.size > largest)
                    largest = b.size;
            }
        }
        printf(
            "STATS used=%d used_blocks=%d free=%d free_blocks=%d largest=%d frag=%d requested=%d peak=%d\n",
            u, ub, heap.size - u, fb, largest, frag(&heap), req, peak);
        printf("OPS allocs=%d frees=%d reallocs=%d moves=%d failures=%d collected=%d\n",
               counters[0], counters[1], counters[2], counters[3], counters[4], counters[5]);
    }
}
int main(void) {
    int n;
    char line[512];
    if (!fgets(line, sizeof(line), stdin))
        return 0;
    n = atoi(line);
    while (n-- && fgets(line, sizeof(line), stdin)) {
        char *args[10];
        int count = 0;
        for (char *p = strtok(line, " \r\n"); p; p = strtok(NULL, " \r\n"))
            args[count++] = p;
        command(args, count);
        int u = used(&heap);
        if (u > peak)
            peak = u;
    }
    return 0;
}
