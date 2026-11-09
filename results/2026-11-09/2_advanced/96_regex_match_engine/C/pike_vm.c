#include "regex.h"
typedef struct {
    int pc;
    Capture capture;
}
Thread;
typedef struct {
    Thread *threads;
    unsigned char *marked;
    int count;
}
ThreadList;
static void add_thread(const Pattern *p, const char *s, int n, ThreadList *list, int pc, Capture c, int q, Meter *meter) {
    if (list->marked[pc]) return;
    list->marked[pc] = 1;
    ++meter->steps;
    Instruction i = p->code[pc];
    switch (i.op) {
        case I_JMP: add_thread(p, s, n, list, i.x, c, q, meter);
        break;
        case I_SPLIT:
        add_thread(p, s, n, list, i.x, c, q, meter);
        add_thread(p, s, n, list, i.y, c, q, meter);
        break;
        case I_SAVE: c.cap[i.x] = q;
        add_thread(p, s, n, list, pc+1, c, q, meter);
        break;
        case I_ASSERT:
        if (assertion(p, i.kind, s, n, q)) add_thread(p, s, n, list, pc+1, c, q, meter);
        break;
        default: list->threads[list->count++] = (Thread) {
            pc, c
        };
        break;
    }
}
int pike_search(const Pattern *p, const char *s, int start, int full, Meter *meter, Capture *out) {
    int n = (int)strlen(s), found = 0;
    ThreadList list = {
        checked_alloc((size_t)p->size * sizeof(Thread)), checked_alloc((size_t)p->size), 0
    };
    ThreadList next = {
        checked_alloc((size_t)p->size * sizeof(Thread)), checked_alloc((size_t)p->size), 0
    };
    memset(list.marked, 0, (size_t)p->size);
    Capture empty;
    for (int k = 0; k < CAPACITY; ++k) empty.cap[k] = -1;
    for (int q = start; q <= n; ++q) {
        if (!found && (!full || q == start)) add_thread(p, s, n, &list, 0, empty, q, meter);
        next.count = 0;
        memset(next.marked, 0, (size_t)p->size);
        for (int k = 0; k < list.count; ++k) {
            Thread t = list.threads[k];
            Instruction i = p->code[t.pc];
            ++meter->steps;
            if (i.op == I_MATCH) {
                if (!full || q == n) {
                    *out = t.capture;
                    found = 1;
                    break;
                }
            }
            else if (consumes(p, &i, s, n, q)) add_thread(p, s, n, &next, t.pc+1, t.capture, q+1, meter);
        }
        if (q == n || (!next.count && (found || full))) break;
        ThreadList swap = list;
        list = next;
        next = swap;
    }
    free(list.threads);
    free(list.marked);
    free(next.threads);
    free(next.marked);
    return found;
}
