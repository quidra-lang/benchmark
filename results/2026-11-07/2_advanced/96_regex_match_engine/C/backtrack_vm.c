#include "regex.h"
typedef struct {
    int p, q;
    Capture capture;
    uint64_t visited[VISWORDS];
}
State;
static int execute(const Pattern *p, const char *s, int n, int pc, int pos, Capture initial, int partial, int full, Meter *m, Capture *out, int *end) {
    size_t size = 0, capacity = 16;
    State *stack = checked_alloc(capacity * sizeof *stack);
    State current = {
        .p = pc, .q = pos, .capture = initial, .visited = {
            0
        }
    };
    stack[size++] = current;
    int success = 0;
    while (size && !m->aborted) {
        current = stack[--size];
        int live = 1;
        while (live && !m->aborted) {
            if (++m->steps > 200000) {
                m->aborted = 1;
                break;
            }
            Instruction i = p->code[current.p];
            switch (i.op) {
                case I_CHAR: case I_ANY: case I_CLASS:
                if (!consumes(p, &i, s, n, current.q)) {
                    live = 0;
                    break;
                }
                ++current.q;
                ++current.p;
                memset(current.visited, 0, sizeof current.visited);
                break;
                case I_SPLIT: {
                    uint64_t bit = UINT64_C(1) << (current.p % 64);
                    if (current.visited[current.p / 64] & bit) {
                        live = 0;
                        break;
                    }
                    current.visited[current.p / 64] |= bit;
                    if (size == capacity) {
                        capacity *= 2;
                        stack = checked_realloc(stack, capacity * sizeof *stack);
                    }
                    State other = current;
                    other.p = i.y;
                    stack[size++] = other;
                    current.p = i.x;
                    break;
                }
                case I_JMP: current.p = i.x;
                break;
                case I_SAVE: current.capture.cap[i.x] = current.q;
                ++current.p;
                break;
                case I_ASSERT:
                if (assertion(p, i.kind, s, n, current.q)) ++current.p;
                else live = 0;
                break;
                case I_BACKREF: {
                    int a = current.capture.cap[2*i.x], b = current.capture.cap[2*i.x+1];
                    if (a < 0 || b < a || current.q + b - a > n) {
                        live = 0;
                        break;
                    }
                    for (int k = 0; k < b-a; ++k) if (!equal_character(p, (unsigned char)s[a+k], (unsigned char)s[current.q+k])) {
                        live = 0;
                        break;
                    }
                    if (live) {
                        current.q += b-a;
                        ++current.p;
                        if (b > a) memset(current.visited, 0, sizeof current.visited);
                    }
                    break;
                }
                case I_LOOK: {
                    Capture result;
                    int q = current.q;
                    int found = execute(p, s, n, current.p+1, current.q, current.capture, 1, full, m, &result, &q);
                    if (m->aborted) break;
                    if (i.kind == L_NOT) {
                        if (found) live = 0;
                        else current.p = i.x;
                    }
                    else if (!found) live = 0;
                    else {
                        current.capture = result;
                        current.p = i.x;
                        if (i.kind == L_ATOMIC) {
                            if (q > current.q) memset(current.visited, 0, sizeof current.visited);
                            current.q = q;
                        }
                    }
                    break;
                }
                case I_MATCH:
                if (partial || !full || current.q == n) {
                    *out = current.capture;
                    *end = current.q;
                    success = 1;
                    goto done;
                }
                live = 0;
                break;
            }
        }
    }
    done:
    free(stack);
    return success;
}
int backtrack_search(const Pattern *p, const char *s, int start, int full, Meter *m, Capture *out) {
    int n = (int)strlen(s);
    Capture c;
    for (int k = 0; k < CAPACITY; ++k) c.cap[k] = -1;
    for (int b = full ? 0 : start; b <= n && !m->aborted; ++b) {
        int end;
        if (execute(p, s, n, 0, b, c, 0, full, m, out, &end)) return 1;
        if (full) break;
    }
    return 0;
}
