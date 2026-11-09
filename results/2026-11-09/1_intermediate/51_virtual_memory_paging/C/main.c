#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <limits.h>
#include <ctype.h>

static const char *policies[] = {"FIFO",  "LRU",    "LFU",     "NRU",    "AGING",
                                 "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT"};
typedef struct {
    int page, frames, tlb, sets, policy, local, asid, tick, tau;
    int64_t seed;
} Config;
typedef struct Page {
    int pid, number, frame, slot, r, m, load, last, uses, age, references;
    bool ro, locked, ever;
} Page;
typedef struct {
    int pid, count, accesses, faults, writebacks, segfaults, protfaults, peak, hand;
    bool exited;
    Page pages[256];
    int history[3000], history_count;
} Process;
typedef struct {
    int pid, address;
    char op;
} Access;
typedef struct {
    int kind, pid, a, b;
    char op;
} Event;
enum { ACCESS, EXIT_EVENT, CLEAN_EVENT, LOCK_EVENT, UNLOCK_EVENT };
typedef struct {
    Config c;
    Process *processes[100];
    int process_count;
    Page *frames[16], *tlb[8][8], *swap[2048];
    int tlb_count[8];
    Access *future;
    int future_count, cursor, time, faults, zero, swapin, tlbhits, writebacks, switches, previous,
        hand;
    int64_t random;
    bool fixed, trace, silent, fault_history[3000];
    Event log[3500];
    int log_count;
} Simulation;
typedef struct {
    char **words;
    int count;
    bool access;
    Access a;
} Command;

static void emit(Simulation *s, const char *format, ...) {
    if (s->silent)
        return;
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
}
static void error(Simulation *s, const char *message) {
    emit(s, "ERROR %s\n", message);
}
static int policy_index(const char *name) {
    for (int i = 0; i < 10; i++)
        if (strcmp(name, policies[i]) == 0)
            return i;
    return -1;
}
static int number(const char *s) {
    return (int)strtol(s, NULL, 10);
}
static int address(const char *s) {
    return (int)strtol(s + 2, NULL, 16);
}
static bool settings(Command cmd, Config *c) {
    *c = (Config){256, 4, 4, 1, 0, 0, 0, 0, 8, 1};
    const char *keys[] = {"page",  "frames", "tlb",  "sets", "policy",
                          "scope", "asid",   "tick", "tau",  "seed"};
    bool seen[10] = {false};
    for (int i = 1; i < cmd.count; i++) {
        char *pair = cmd.words[i], *equal = strchr(pair, '=');
        size_t len = (size_t)(equal - pair);
        char key[11];
        memcpy(key, pair, len);
        key[len] = '\0';
        const char *value = equal + 1;
        int k = -1;
        for (int j = 0; j < 10; j++)
            if (strcmp(key, keys[j]) == 0)
                k = j;
        if (k < 0) {
            printf("ERROR unknown key %s\n", key);
            return false;
        }
        if (seen[k]) {
            printf("ERROR duplicate key %s\n", key);
            return false;
        }
        seen[k] = true;
        bool valid = true;
        int64_t n = strtoll(value, NULL, 10);
        switch (k) {
        case 0:
            valid = n >= 16 && n <= 4096 && (n & (n - 1)) == 0;
            if (valid)
                c->page = (int)n;
            break;
        case 1:
        case 2:
        case 3:
            valid = n >= 1 && n <= (k == 1 ? 16 : 8);
            if (valid) {
                if (k == 1)
                    c->frames = (int)n;
                if (k == 2)
                    c->tlb = (int)n;
                if (k == 3)
                    c->sets = (int)n;
            }
            break;
        case 4:
            c->policy = policy_index(value);
            valid = c->policy >= 0;
            break;
        case 5:
            valid = strcmp(value, "GLOBAL") == 0 || strcmp(value, "LOCAL") == 0;
            c->local = strcmp(value, "LOCAL") == 0;
            break;
        case 6:
            valid = strcmp(value, "ON") == 0 || strcmp(value, "OFF") == 0;
            c->asid = strcmp(value, "ON") == 0;
            break;
        case 7:
            valid = n >= 0 && n <= 1000;
            if (valid)
                c->tick = (int)n;
            break;
        case 8:
            valid = n >= 1 && n <= 1000;
            if (valid)
                c->tau = (int)n;
            break;
        case 9:
            valid = n >= 1 && n <= 2147483646LL;
            if (valid)
                c->seed = n;
            break;
        }
        if (!valid) {
            printf("ERROR invalid %s\n", key);
            return false;
        }
    }
    if (c->tlb % c->sets != 0) {
        puts("ERROR invalid sets");
        return false;
    }
    return true;
}
static Simulation *create(Config c, Access *future, int count, bool silent) {
    Simulation *s = calloc(1, sizeof(*s));
    s->c = c;
    s->future = future;
    s->future_count = count;
    s->silent = silent;
    s->cursor = -1;
    s->previous = -1;
    s->random = c.seed;
    return s;
}
static void destroy(Simulation *s) {
    if (!s)
        return;
    for (int pid = 1; pid <= 99; pid++)
        free(s->processes[pid]);
    free(s->future);
    free(s);
}
static Process *get_process(Simulation *s, int pid) {
    Process *p = s->processes[pid];
    if (!p) {
        emit(s, "ERROR unknown process %d\n", pid);
        return NULL;
    }
    if (p->exited) {
        emit(s, "ERROR process %d exited\n", pid);
        return NULL;
    }
    return p;
}
static void declare(Simulation *s, int pid, int count) {
    if (s->fixed) {
        error(s, "processes are fixed");
        return;
    }
    if (s->processes[pid]) {
        emit(s, "ERROR duplicate process %d\n", pid);
        return;
    }
    if (count < 1 || count > 256) {
        error(s, "invalid page count");
        return;
    }
    if (s->process_count >= 8 || (s->c.local && s->process_count == s->c.frames)) {
        error(s, "too many processes");
        return;
    }
    Process *p = calloc(1, sizeof(*p));
    p->pid = pid;
    p->count = count;
    for (int i = 0; i < count; i++) {
        p->pages[i].pid = pid;
        p->pages[i].number = i;
        p->pages[i].frame = -1;
        p->pages[i].slot = -1;
    }
    s->processes[pid] = p;
    s->process_count++;
}
static int resident(Process *p) {
    int count = 0;
    for (int i = 0; i < p->count; i++)
        if (p->pages[i].frame >= 0)
            count++;
    return count;
}
static int quota(Simulation *s, int pid) {
    int rank = 0;
    for (int i = 1; i < pid; i++)
        if (s->processes[i])
            rank++;
    return s->c.frames / s->process_count + (rank < s->c.frames % s->process_count);
}
static void invalidate(Simulation *s, Page *p) {
    for (int set = 0; set < s->c.sets; set++) {
        int count = 0;
        for (int i = 0; i < s->tlb_count[set]; i++)
            if (s->tlb[set][i] != p)
                s->tlb[set][count++] = s->tlb[set][i];
        s->tlb_count[set] = count;
    }
}
static void write_page(Simulation *s, Page *p) {
    s->writebacks++;
    s->processes[p->pid]->writebacks++;
    p->m = 0;
    if (p->slot < 0) {
        int slot = 0;
        while (s->swap[slot])
            slot++;
        s->swap[slot] = p;
        p->slot = slot;
    }
}
static int next_use(Simulation *s, Page *p) {
    for (int i = s->cursor + 1; i < s->future_count; i++)
        if (s->future[i].pid == p->pid && s->future[i].address / s->c.page == p->number)
            return i;
    return INT_MAX;
}
static bool better(Simulation *s, int a, int b) {
    Page *x = s->frames[a], *y = s->frames[b];
    switch (s->c.policy) {
    case 0:
        return x->load < y->load;
    case 1:
        return x->last < y->last;
    case 2:
        return x->uses != y->uses ? x->uses < y->uses : x->load < y->load;
    case 3:
        return 2 * x->r + x->m != 2 * y->r + y->m ? 2 * x->r + x->m < 2 * y->r + y->m : a < b;
    case 4:
        return x->age != y->age ? x->age < y->age : x->load < y->load;
    default: {
        int nx = next_use(s, x), ny = next_use(s, y);
        return nx != ny ? nx > ny : a < b;
    }
    }
}
static int choose(Simulation *s, int *candidates, int count, Process *owner) {
    int unlocked[16], n = 0;
    for (int i = 0; i < count; i++)
        if (!s->frames[candidates[i]]->locked)
            unlocked[n++] = candidates[i];
    if (n > 0) {
        memcpy(candidates, unlocked, n * sizeof(int));
        count = n;
    }
    if (s->c.policy <= 4 || s->c.policy == 9) {
        int best = candidates[0];
        for (int i = 1; i < count; i++)
            if (better(s, candidates[i], best))
                best = candidates[i];
        return best;
    }
    if (s->c.policy == 8) {
        s->random = s->random * 48271 % 2147483647;
        return candidates[s->random % count];
    }
    int h = s->c.local ? owner->hand : s->hand;
    for (int i = 1; i < count; i++) {
        int f = candidates[i], j = i;
        while (j > 0 && (candidates[j - 1] - h + s->c.frames) % s->c.frames >
                            (f - h + s->c.frames) % s->c.frames) {
            candidates[j] = candidates[j - 1];
            j--;
        }
        candidates[j] = f;
    }
    int chosen = -1;
    if (s->c.policy == 5) {
        while (chosen < 0)
            for (int i = 0; i < count; i++) {
                int f = candidates[i];
                if (!s->frames[f]->r) {
                    chosen = f;
                    break;
                }
                s->frames[f]->r = 0;
            }
    } else if (s->c.policy == 6) {
        while (chosen < 0) {
            for (int i = 0; i < count; i++) {
                int f = candidates[i];
                if (!s->frames[f]->r && !s->frames[f]->m) {
                    chosen = f;
                    break;
                }
            }
            if (chosen >= 0)
                break;
            for (int i = 0; i < count; i++) {
                int f = candidates[i];
                if (!s->frames[f]->r && s->frames[f]->m) {
                    chosen = f;
                    break;
                }
                s->frames[f]->r = 0;
            }
        }
    } else {
        for (int i = 0; i < count; i++) {
            int f = candidates[i];
            Page *p = s->frames[f];
            if (p->r) {
                p->r = 0;
                p->last = s->time;
            } else if (s->time - p->last > s->c.tau) {
                if (!p->m) {
                    chosen = f;
                    break;
                }
                write_page(s, p);
            }
        }
        if (chosen < 0) {
            for (int i = 0; i < count; i++)
                if (!s->frames[candidates[i]]->m) {
                    chosen = candidates[i];
                    break;
                }
            if (chosen < 0)
                chosen = candidates[0];
        }
    }
    if (s->c.local)
        owner->hand = (chosen + 1) % s->c.frames;
    else
        s->hand = (chosen + 1) % s->c.frames;
    return chosen;
}
static void access_page(Simulation *s, Access a) {
    s->fixed = true;
    s->cursor++;
    Process *owner = get_process(s, a.pid);
    if (!owner)
        return;
    if (a.address >= owner->count * s->c.page) {
        owner->segfaults++;
        emit(s, "SEGFAULT P%d 0x%X\n", a.pid, a.address);
        return;
    }
    Page *p = &owner->pages[a.address / s->c.page];
    if (a.op == 'W' && p->ro) {
        owner->protfaults++;
        emit(s, "PROTFAULT P%d 0x%X\n", a.pid, a.address);
        return;
    }
    s->time++;
    owner->accesses++;
    bool switched = s->previous >= 0 && s->previous != a.pid;
    if (switched) {
        s->switches++;
        if (!s->c.asid)
            memset(s->tlb_count, 0, sizeof(s->tlb_count));
    }
    s->previous = a.pid;
    int set = p->number % s->c.sets;
    bool hit = false, fault = false;
    for (int i = 0; i < s->tlb_count[set]; i++)
        if (s->tlb[set][i] == p)
            hit = true;
    if (hit)
        invalidate(s, p);
    char result[128];
    if (hit) {
        s->tlbhits++;
        strcpy(result, "TLBHIT");
    } else if (p->frame >= 0)
        strcpy(result, "HIT");
    else {
        fault = true;
        s->faults++;
        owner->faults++;
        if (p->slot >= 0) {
            s->swapin++;
            strcpy(result, "FAULT SWAPIN");
        } else {
            s->zero++;
            strcpy(result, "FAULT ZERO");
        }
        int frame = -1;
        if (!s->c.local || resident(owner) < quota(s, a.pid))
            for (int i = 0; i < s->c.frames; i++)
                if (!s->frames[i]) {
                    frame = i;
                    break;
                }
        if (frame < 0) {
            int candidates[16], count = 0;
            for (int i = 0; i < s->c.frames; i++)
                if (s->frames[i] && (!s->c.local || s->frames[i]->pid == a.pid))
                    candidates[count++] = i;
            frame = choose(s, candidates, count, owner);
            Page *victim = s->frames[frame];
            snprintf(result + strlen(result), sizeof(result) - strlen(result), " evict=P%d:%d",
                     victim->pid, victim->number);
            invalidate(s, victim);
            if (victim->m) {
                write_page(s, victim);
                strcat(result, " writeback");
            }
            victim->frame = -1;
        }
        s->frames[frame] = p;
        p->frame = frame;
        p->load = s->time;
        p->uses = 0;
        p->m = 0;
        p->age = 0;
        int current = resident(owner);
        if (current > owner->peak)
            owner->peak = current;
    }
    if (s->tlb_count[set] == s->c.tlb / s->c.sets) {
        for (int i = 1; i < s->tlb_count[set]; i++)
            s->tlb[set][i - 1] = s->tlb[set][i];
        s->tlb_count[set]--;
    }
    s->tlb[set][s->tlb_count[set]++] = p;
    p->r = 1;
    if (a.op == 'W')
        p->m = 1;
    p->last = s->time;
    p->uses++;
    p->ever = true;
    p->references++;
    owner->history[owner->history_count++] = p->number;
    s->fault_history[s->time - 1] = fault;
    s->log[s->log_count++] = (Event){ACCESS, a.pid, a.address, 0, a.op};
    bool interrupt = s->c.tick > 0 && s->time % s->c.tick == 0;
    if (interrupt)
        for (int i = 0; i < s->c.frames; i++)
            if (s->frames[i]) {
                Page *page = s->frames[i];
                page->age = page->age / 2 + 128 * page->r;
                page->r = 0;
            }
    if (s->trace) {
        emit(s, "t=%d P%d %c 0x%X page=%d frame=%d phys=0x%X %s%s\n", s->time, a.pid, a.op,
             a.address, p->number, p->frame, p->frame * s->c.page + a.address % s->c.page, result,
             switched ? " switch" : "");
        if (interrupt)
            emit(s, "t=%d tick\n", s->time);
    }
}
static void exit_process(Simulation *s, int pid) {
    Process *p = get_process(s, pid);
    if (!p)
        return;
    int count = 0, slots = 0;
    for (int i = 0; i < p->count; i++) {
        Page *page = &p->pages[i];
        if (page->frame >= 0) {
            s->frames[page->frame] = NULL;
            page->frame = -1;
            count++;
        }
        invalidate(s, page);
        if (page->slot >= 0) {
            s->swap[page->slot] = NULL;
            page->slot = -1;
            slots++;
        }
    }
    p->exited = true;
    s->log[s->log_count++] = (Event){EXIT_EVENT, pid, 0, 0, 0};
    emit(s, "EXIT P%d freed=%d slots=%d\n", pid, count, slots);
}
static void attributes(Simulation *s, const char *cmd, int pid, int first, int last, bool ro) {
    Process *p = get_process(s, pid);
    if (!p)
        return;
    if (first > last || last >= p->count) {
        error(s, "invalid page range");
        return;
    }
    bool protect = strcmp(cmd, "PROTECT") == 0, lock = strcmp(cmd, "LOCK") == 0;
    for (int i = first; i <= last; i++) {
        if (protect)
            p->pages[i].ro = ro;
        else
            p->pages[i].locked = lock;
    }
    if (!protect)
        s->log[s->log_count++] = (Event){lock ? LOCK_EVENT : UNLOCK_EVENT, pid, first, last, 0};
}
static void clean(Simulation *s) {
    int count = 0;
    for (int i = 0; i < s->c.frames; i++)
        if (s->frames[i] && s->frames[i]->m) {
            write_page(s, s->frames[i]);
            count++;
        }
    s->log[s->log_count++] = (Event){CLEAN_EVENT, 0, 0, 0, 0};
    emit(s, "CLEAN written=%d\n", count);
}
static Simulation *rerun(Simulation *s, int policy, int count) {
    Config c = s->c;
    c.policy = policy;
    c.frames = count;
    Access *future = malloc(3000 * sizeof(*future));
    int n = 0;
    for (int i = 0; i < s->log_count; i++) {
        Event e = s->log[i];
        if (e.kind == ACCESS)
            future[n++] = (Access){e.pid, e.a, e.op};
    }
    Simulation *r = create(c, future, n, true);
    for (int pid = 1; pid <= 99; pid++)
        if (s->processes[pid])
            declare(r, pid, s->processes[pid]->count);
    for (int i = 0; i < s->log_count; i++) {
        Event e = s->log[i];
        switch (e.kind) {
        case ACCESS:
            access_page(r, (Access){e.pid, e.a, e.op});
            break;
        case EXIT_EVENT:
            exit_process(r, e.pid);
            break;
        case CLEAN_EVENT:
            clean(r);
            break;
        default:
            attributes(r, e.kind == LOCK_EVENT ? "LOCK" : "UNLOCK", e.pid, e.a, e.b, false);
            break;
        }
    }
    return r;
}
static void percentage(Simulation *s, int x, int y) {
    int v = y ? 10000 * x / y : 0;
    emit(s, "%d.%02d%%", v / 100, v % 100);
}
static void summary(Simulation *s) {
    int seg = 0, prot = 0;
    for (int pid = 1; pid <= 99; pid++)
        if (s->processes[pid]) {
            seg += s->processes[pid]->segfaults;
            prot += s->processes[pid]->protfaults;
        }
    emit(s, "SUMMARY policy=%s scope=%s time=%d\n", policies[s->c.policy],
         s->c.local ? "LOCAL" : "GLOBAL", s->time);
    emit(s, "total faults=%d zero=%d swapin=%d faultrate=", s->faults, s->zero, s->swapin);
    percentage(s, s->faults, s->time);
    emit(s, " tlbhits=%d tlbrate=", s->tlbhits);
    percentage(s, s->tlbhits, s->time);
    emit(s, " writebacks=%d switches=%d segfaults=%d protfaults=%d\n", s->writebacks, s->switches,
         seg, prot);
    for (int pid = 1; pid <= 99; pid++)
        if (s->processes[pid]) {
            Process *p = s->processes[pid];
            emit(
                s,
                "P%d accesses=%d faults=%d writebacks=%d segfaults=%d protfaults=%d resident=%d peak=%d",
                pid, p->accesses, p->faults, p->writebacks, p->segfaults, p->protfaults,
                resident(p), p->peak);
            if (s->c.local)
                emit(s, " quota=%d", quota(s, pid));
            emit(s, "%s\n", p->exited ? " exited" : "");
        }
}
static void frame_dump(Simulation *s) {
    int used = 0;
    for (int i = 0; i < s->c.frames; i++)
        if (s->frames[i])
            used++;
    emit(s, "FRAMES used=%d/%d\n", used, s->c.frames);
    for (int i = 0; i < s->c.frames; i++) {
        Page *p = s->frames[i];
        if (!p)
            emit(s, "%d free\n", i);
        else
            emit(s, "%d P%d:%d R=%d M=%d load=%d last=%d uses=%d age=%d%s\n", i, p->pid, p->number,
                 p->r, p->m, p->load, p->last, p->uses, p->age, p->locked ? " locked" : "");
    }
    if (s->c.policy >= 5 && s->c.policy <= 7) {
        if (!s->c.local)
            emit(s, "hand=%d\n", s->hand);
        else {
            emit(s, "hand");
            for (int pid = 1; pid <= 99; pid++)
                if (s->processes[pid])
                    emit(s, " P%d=%d", pid, s->processes[pid]->hand);
            emit(s, "\n");
        }
    }
}
static void page_table(Simulation *s, int pid) {
    Process *p = get_process(s, pid);
    if (!p)
        return;
    emit(s, "PAGETABLE P%d pages=%d resident=%d\n", pid, p->count, resident(p));
    for (int i = 0; i < p->count; i++)
        if (p->pages[i].ever) {
            Page *page = &p->pages[i];
            emit(s, "%d ", i);
            if (page->frame >= 0)
                emit(s, "frame=%d R=%d M=%d", page->frame, page->r, page->m);
            else if (page->slot >= 0)
                emit(s, "swap=%d", page->slot);
            else
                emit(s, "zero");
            emit(s, "%s%s\n", page->ro ? " RO" : "", page->locked ? " locked" : "");
        }
}
static void compare(Simulation *s) {
    int faults[10], writes[10], ranking[10];
    emit(s, "COMPARE accesses=%d frames=%d\n", s->time, s->c.frames);
    for (int i = 0; i < 10; i++) {
        Simulation *r = rerun(s, i, s->c.frames);
        faults[i] = r->faults;
        writes[i] = r->writebacks;
        ranking[i] = i;
        emit(s, "%s faults=%d writebacks=%d tlbhits=%d\n", policies[i], r->faults, r->writebacks,
             r->tlbhits);
        destroy(r);
    }
    for (int i = 1; i < 10; i++) {
        int p = ranking[i], j = i;
        while (j > 0 &&
               (faults[p] < faults[ranking[j - 1]] ||
                (faults[p] == faults[ranking[j - 1]] && writes[p] < writes[ranking[j - 1]]))) {
            ranking[j] = ranking[j - 1];
            j--;
        }
        ranking[j] = p;
    }
    emit(s, "ranking");
    for (int i = 0; i < 10; i++)
        emit(s, " %s", policies[ranking[i]]);
    emit(s, "\n");
}
static void execute(Simulation *s, Command cmd) {
    if (cmd.access) {
        access_page(s, cmd.a);
        return;
    }
    char **t = cmd.words;
    const char *name = t[0];
    if (strcmp(name, "PROCESS") == 0)
        declare(s, number(t[1]), number(t[2]));
    else if (strcmp(name, "EXIT") == 0)
        exit_process(s, number(t[1]));
    else if (strcmp(name, "PROTECT") == 0 || strcmp(name, "LOCK") == 0 ||
             strcmp(name, "UNLOCK") == 0)
        attributes(s, name, number(t[1]), number(t[2]), number(t[3]),
                   cmd.count > 4 && strcmp(t[4], "RO") == 0);
    else if (strcmp(name, "TRACE") == 0)
        s->trace = strcmp(t[1], "ON") == 0;
    else if (strcmp(name, "SUMMARY") == 0)
        summary(s);
    else if (strcmp(name, "FRAMES") == 0)
        frame_dump(s);
    else if (strcmp(name, "PAGETABLE") == 0)
        page_table(s, number(t[1]));
    else if (strcmp(name, "TLB") == 0) {
        int used = 0;
        for (int i = 0; i < s->c.sets; i++)
            used += s->tlb_count[i];
        emit(s, "TLB used=%d/%d sets=%d\n", used, s->c.tlb, s->c.sets);
        for (int i = 0; i < s->c.sets; i++) {
            emit(s, "set %d:", i);
            for (int j = s->tlb_count[i] - 1; j >= 0; j--) {
                Page *p = s->tlb[i][j];
                emit(s, " P%d:%d->%d", p->pid, p->number, p->frame);
            }
            emit(s, "\n");
        }
    } else if (strcmp(name, "SWAP") == 0) {
        int used = 0;
        for (int i = 0; i < 2048; i++)
            if (s->swap[i])
                used++;
        emit(s, "SWAP used=%d\n", used);
        for (int i = 0; i < 2048; i++)
            if (s->swap[i])
                emit(s, "%d P%d:%d\n", i, s->swap[i]->pid, s->swap[i]->number);
    } else if (strcmp(name, "CLEAN") == 0)
        clean(s);
    else if (strcmp(name, "COMPARE") == 0)
        compare(s);
    else if (strcmp(name, "CURVE") == 0) {
        int policy = policy_index(t[1]), lo = number(t[2]), hi = number(t[3]);
        if (policy < 0) {
            error(s, "unknown policy");
            return;
        }
        if (lo < 1 || lo > hi || hi > 16 || (s->c.local && lo < s->process_count)) {
            error(s, "invalid frame range");
            return;
        }
        emit(s, "CURVE %s frames=%d..%d\n", t[1], lo, hi);
        int previous = INT_MAX;
        for (int f = lo; f <= hi; f++) {
            Simulation *r = rerun(s, policy, f);
            emit(s, "F=%d faults=%d%s\n", f, r->faults, r->faults > previous ? " ANOMALY" : "");
            previous = r->faults;
            destroy(r);
        }
    } else if (strcmp(name, "EAT") == 0) {
        int64_t total = (int64_t)number(t[1]) * s->time +
                        (int64_t)number(t[2]) * (2 * s->time - s->tlbhits) +
                        (int64_t)number(t[3]) * (s->swapin + s->writebacks);
        if (!s->time)
            emit(s, "EAT accesses=0\n");
        else {
            int64_t v = 100 * total / s->time;
            emit(s, "EAT accesses=%d total=%lld average=%lld.%02lld\n", s->time, (long long)total,
                 (long long)(v / 100), (long long)(v % 100));
        }
    } else if (strcmp(name, "TIMELINE") == 0) {
        int w = number(t[1]);
        if (w < 1) {
            error(s, "invalid window");
            return;
        }
        emit(s, "TIMELINE window=%d", w);
        for (int i = 0; i < s->time; i += w) {
            int count = 0;
            for (int j = i; j < i + w && j < s->time; j++)
                count += s->fault_history[j];
            emit(s, " %d", count);
        }
        emit(s, "\n");
    } else if (strcmp(name, "WSET") == 0 || strcmp(name, "HOT") == 0) {
        int pid = number(t[1]);
        Process *p = get_process(s, pid);
        if (!p)
            return;
        int k = number(t[2]);
        bool working_set = strcmp(name, "WSET") == 0;
        if (k < 1) {
            error(s, working_set ? "invalid window" : "invalid count");
            return;
        }
        if (working_set) {
            bool pages[256] = {false};
            int count = 0;
            int start = p->history_count > k ? p->history_count - k : 0;
            for (int i = start; i < p->history_count; i++)
                pages[p->history[i]] = true;
            for (int i = 0; i < p->count; i++)
                count += pages[i];
            emit(s, "WSET P%d window=%d size=%d", pid, k, count);
            for (int i = 0; i < p->count; i++)
                if (pages[i])
                    emit(s, " %d", i);
        } else {
            int order[256], count = 0;
            for (int i = 0; i < p->count; i++)
                if (p->pages[i].references)
                    order[count++] = i;
            for (int i = 1; i < count; i++) {
                int page = order[i], j = i;
                while (j > 0 && p->pages[page].references > p->pages[order[j - 1]].references) {
                    order[j] = order[j - 1];
                    j--;
                }
                order[j] = page;
            }
            emit(s, "HOT P%d", pid);
            for (int i = 0; i < count && i < k; i++)
                emit(s, " %d:%d", order[i], p->pages[order[i]].references);
        }
        emit(s, "\n");
    }
}
static char *read_line(void) {
    size_t capacity = 128, length = 0;
    char *line = malloc(capacity);
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 >= capacity) {
            capacity *= 2;
            line = realloc(line, capacity);
        }
        if (ch != '\r')
            line[length++] = (char)ch;
    }
    line[length] = '\0';
    return line;
}
static Command parse(char *line) {
    Command cmd = {0};
    int capacity = 16;
    cmd.words = malloc(capacity * sizeof(char *));
    char *token = strtok(line, " ");
    while (token) {
        if (cmd.count == capacity) {
            capacity *= 2;
            cmd.words = realloc(cmd.words, capacity * sizeof(char *));
        }
        cmd.words[cmd.count++] = token;
        token = strtok(NULL, " ");
    }
    cmd.access = isdigit((unsigned char)cmd.words[0][0]) != 0;
    if (cmd.access)
        cmd.a = (Access){number(cmd.words[0]), address(cmd.words[2]), cmd.words[1][0]};
    return cmd;
}
int main(void) {
    char *line = read_line();
    int n = number(line);
    free(line);
    Command *commands = malloc(3500 * sizeof(*commands));
    char **lines = malloc(n * sizeof(*lines));
    int count = 0;
    for (int i = 0; i < n; i++) {
        lines[i] = read_line();
        Command cmd = parse(lines[i]);
        char **t = cmd.words;
        if (strcmp(t[0], "LOOP") == 0) {
            int start = address(t[3]), interval = number(t[4]), length = number(t[5]),
                repeats = number(t[6]);
            for (int r = 0; r < repeats; r++)
                for (int j = 0; j < length; j++)
                    commands[count++] =
                        (Command){NULL, 0, true, {number(t[1]), start + j * interval, t[2][0]}};
            free(cmd.words);
        } else if (strcmp(t[0], "RAND") == 0) {
            int lo = address(t[2]), hi = address(t[3]), times = number(t[4]), rate = number(t[6]);
            int64_t x = strtoll(t[5], NULL, 10);
            for (int j = 0; j < times; j++) {
                x = x * 48271 % 2147483647;
                int addr = lo + (int)(x % (hi - lo));
                x = x * 48271 % 2147483647;
                commands[count++] =
                    (Command){NULL, 0, true, {number(t[1]), addr, x % 100 < rate ? 'W' : 'R'}};
            }
            free(cmd.words);
        } else
            commands[count++] = cmd;
    }
    Simulation *s = NULL;
    for (int i = 0; i < count; i++) {
        Command cmd = commands[i];
        if (!cmd.access && strcmp(cmd.words[0], "SYSTEM") == 0) {
            destroy(s);
            s = NULL;
            Config c;
            if (!settings(cmd, &c))
                continue;
            Access *future = malloc(3000 * sizeof(*future));
            int refs = 0;
            for (int j = i + 1; j < count; j++) {
                if (!commands[j].access && strcmp(commands[j].words[0], "SYSTEM") == 0)
                    break;
                if (commands[j].access)
                    future[refs++] = commands[j].a;
            }
            s = create(c, future, refs, false);
            printf(
                "SYSTEM page=%d frames=%d tlb=%d sets=%d policy=%s scope=%s asid=%s tick=%d tau=%d seed=%lld\n",
                c.page, c.frames, c.tlb, c.sets, policies[c.policy], c.local ? "LOCAL" : "GLOBAL",
                c.asid ? "ON" : "OFF", c.tick, c.tau, (long long)c.seed);
        } else if (!s)
            puts("ERROR no system");
        else
            execute(s, cmd);
    }
    destroy(s);
    for (int i = 0; i < count; i++)
        free(commands[i].words);
    for (int i = 0; i < n; i++)
        free(lines[i]);
    free(lines);
    free(commands);
    return 0;
}
