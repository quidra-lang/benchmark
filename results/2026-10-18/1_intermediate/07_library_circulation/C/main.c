#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum State { AVAILABLE, LOANED, HOLD, LOST, WITHDRAWN };
static const char *states[] = {"AVAILABLE","LOANED","HOLD","LOST","WITHDRAWN"};
static const char *kinds[] = {"FINE","FEE","PRICE"};
typedef struct { int title, copy; } Ref;
typedef struct { int state, member, from, due, renewals, expiry; } Copy;
typedef struct {
    char isbn[14], name[61], folded[61];
    int price, borrowed, counts[5], copy_count, queue_count;
    Copy copies[99];
    int queue[1000];
} Title;
typedef struct { int day, kind, title, amount, unpaid; } Charge;
typedef struct {
    char id[9], type[11], name[31];
    int limit, period, rate, cap, reserve_limit, fee, balance, reservations;
    Ref loans[10], holds[5];
    int loan_count, hold_count;
    Charge *charges;
    int charge_count, charge_capacity;
    char **history;
    int history_count, history_capacity;
} Member;
typedef struct Temp {
    struct Temp *next;
    char data[];
} Temp;
static Temp *temps;
static Title *titles[1000];
static Member *members[1000];
static int title_order[1000], member_order[1000], title_count, member_count;
static bool closed[3652];
static int day = 1, closed_count, borrowed, returned, renewed, lost, paid, waived, charged[3];

static void *resize(void *p, size_t size) {
    void *result = realloc(p,size);
    if (!result) exit(EXIT_FAILURE);
    return result;
}
static char *save(const char *s) {
    size_t size = strlen(s)+1;
    char *result = resize(NULL,size);
    memcpy(result,s,size);
    return result;
}
static char *format(const char *pattern, ...) {
    va_list args, measure;
    va_start(args,pattern);
    va_copy(measure,args);
    int length = vsnprintf(NULL,0,pattern,measure);
    va_end(measure);
    if (length < 0) exit(EXIT_FAILURE);
    Temp *t = resize(NULL,sizeof(*t)+(size_t)length+1);
    t->next = temps;
    temps = t;
    vsnprintf(t->data,(size_t)length+1,pattern,args);
    va_end(args);
    return t->data;
}
static void clear_temps(void) {
    while (temps) {
        Temp *next = temps->next;
        free(temps);
        temps = next;
    }
}
static void line(const char *pattern, ...) {
    va_list args;
    va_start(args,pattern);
    vprintf(pattern,args);
    va_end(args);
    putchar('\n');
}
static bool error(bool condition, const char *reason) {
    if (condition) line("ERROR %s",reason);
    return condition;
}
static char *money(int n) { return format("%d.%02d",n/100,n%100); }
static int cents(const char *s) {
    int whole, fraction;
    sscanf(s,"%d.%d",&whole,&fraction);
    return whole*100+fraction;
}
static char *join(char **a, int count, int start) {
    char result[256] = "";
    for (int i = start; i < count; ++i) {
        if (i != start) strcat(result," ");
        strcat(result,a[i]);
    }
    return format("%s",result);
}
static void lower(char *destination, const char *s) {
    while (*s) {
        *destination++ = (char)tolower((unsigned char)*s);
        ++s;
    }
    *destination = '\0';
}
static char *normalize(const char *input) {
    char s[18];
    int length = 0;
    for (; *input; ++input) if (*input != '-') s[length++] = *input;
    s[length] = '\0';
    if (length == 10) {
        int sum = 0;
        for (int i = 0; i < 10; ++i) {
            if (!(s[i] >= '0' && s[i] <= '9') && !(i == 9 && s[i] == 'X')) return NULL;
            sum += (10-i)*(s[i] == 'X' ? 10 : s[i]-'0');
        }
        if (sum%11) return NULL;
        char *result = format("978%.9s0",s);
        sum = 0;
        for (int i = 0; i < 12; ++i) sum += (i%2 ? 3 : 1)*(result[i]-'0');
        result[12] = (char)('0'+(10-sum%10)%10);
        return result;
    }
    if (length != 13 || (strncmp(s,"978",3) && strncmp(s,"979",3))) return NULL;
    int sum = 0;
    for (int i = 0; i < 13; ++i) {
        if (s[i] < '0' || s[i] > '9') return NULL;
        sum += (i%2 ? 3 : 1)*(s[i]-'0');
    }
    return sum%10 ? NULL : format("%s",s);
}
static int find_title(const char *isbn) {
    for (int i = 0; i < title_count; ++i) if (!strcmp(titles[i]->isbn,isbn)) return i;
    return -1;
}
static int find_member(const char *id) {
    for (int i = 0; i < member_count; ++i) if (!strcmp(members[i]->id,id)) return i;
    return -1;
}
static int member(const char *id) {
    int m = find_member(id);
    error(m < 0,"unknown member");
    return m;
}
static int title(const char *input) {
    char *isbn = normalize(input);
    if (error(!isbn,"invalid isbn")) return -1;
    int t = find_title(isbn);
    error(t < 0,"unknown book");
    return t;
}
static int open_day(int d) {
    while (d <= 3650 && closed[d]) ++d;
    return d;
}
static Copy *copy(Ref r) { return &titles[r.title]->copies[r.copy]; }
static int holdings(int t) { return titles[t]->counts[0]+titles[t]->counts[1]+titles[t]->counts[2]; }
static void state(Ref r, int next) {
    --titles[r.title]->counts[copy(r)->state];
    copy(r)->state = next;
    ++titles[r.title]->counts[next];
}
static int find_ref(const Ref *refs, int count, int t) {
    for (int i = 0; i < count; ++i) if (refs[i].title == t) return refs[i].copy;
    return -1;
}
static void remove_ref(Ref *refs, int *count, Ref r) {
    for (int i = 0; i < *count; ++i) {
        if (refs[i].title == r.title && refs[i].copy == r.copy) {
            memmove(refs+i,refs+i+1,(size_t)(*count-i-1)*sizeof(*refs));
            --*count;
            return;
        }
    }
}
static void remove_queue(Title *t, int i) {
    memmove(t->queue+i,t->queue+i+1,(size_t)(t->queue_count-i-1)*sizeof(*t->queue));
    --t->queue_count;
}
static int queue_position(const Title *t, int m) {
    for (int i = 0; i < t->queue_count; ++i) if (t->queue[i] == m) return i;
    return -1;
}
static int late(Ref r) { return day > copy(r)->due ? day-copy(r)->due : 0; }
static int fine(Ref r) {
    Member *m = members[copy(r)->member];
    int amount = late(r)*m->rate;
    return amount < m->cap ? amount : m->cap;
}
static void charge(int m, int kind, int t, int amount) {
    if (!amount) return;
    Member *p = members[m];
    if (p->charge_count == p->charge_capacity) {
        p->charge_capacity = p->charge_capacity ? 2*p->charge_capacity : 8;
        p->charges = resize(p->charges,(size_t)p->charge_capacity*sizeof(*p->charges));
    }
    p->charges[p->charge_count++] = (Charge){day,kind,t,amount,amount};
    p->balance += amount;
    charged[kind] += amount;
}
static void history(Member *m, const char *s) {
    if (m->history_count == m->history_capacity) {
        m->history_capacity = m->history_capacity ? 2*m->history_capacity : 8;
        m->history = resize(m->history,(size_t)m->history_capacity*sizeof(*m->history));
    }
    m->history[m->history_count++] = save(s);
}
static void release(Ref r) {
    Title *t = titles[r.title];
    if (!t->queue_count) {
        state(r,AVAILABLE);
        return;
    }
    int m = t->queue[0];
    remove_queue(t,0);
    state(r,HOLD);
    copy(r)->member = m;
    copy(r)->expiry = open_day(day+3);
    members[m]->holds[members[m]->hold_count++] = r;
    line("HOLD %s copy %d %s until %d",t->isbn,r.copy+1,members[m]->id,copy(r)->expiry);
}
static void drop_queue(int t) {
    if (holdings(t)) return;
    Title *book = titles[t];
    for (int i = 0; i < book->queue_count; ++i) {
        int m = book->queue[i];
        --members[m]->reservations;
        line("DROPPED %s %s",book->isbn,members[m]->id);
    }
    book->queue_count = 0;
}
static void end_loan(Ref r, bool loss, const char *heading) {
    Copy c = *copy(r);
    int m = c.member, l = late(r), f = fine(r);
    Member *p = members[m];
    Title *t = titles[r.title];
    remove_ref(p->loans,&p->loan_count,r);
    charge(m,0,r.title,f);
    char *entry = format("%s %s copy %d from %d to %d late %d fine %s",loss ? "LOST" : "RETURNED",t->isbn,r.copy+1,c.from,day,l,money(f));
    if (loss) {
        entry = format("%s price %s",entry,money(t->price));
        charge(m,2,r.title,t->price);
        state(r,LOST);
        ++lost;
    } else ++returned;
    history(p,entry);
    if (loss) line("%s %s %s copy %d late %d fine %s price %s balance %s",heading,p->id,t->isbn,r.copy+1,l,money(f),money(t->price),money(p->balance));
    else line("RETURN %s %s copy %d late %d fine %s balance %s",p->id,t->isbn,r.copy+1,l,money(f),money(p->balance));
    if (loss) drop_queue(r.title);
    else release(r);
}
static const char *renewal_reason(Ref r) {
    if (late(r)) return "loan overdue";
    if (copy(r)->renewals == 2) return "renewal limit";
    if (titles[r.title]->queue_count) return "title reserved";
    return NULL;
}
static void renew(Ref r) {
    Copy *c = copy(r);
    Member *m = members[c->member];
    c->due = open_day(day+m->period);
    ++c->renewals;
    ++renewed;
    line("RENEW %s %s copy %d due %d renewals %d",m->id,titles[r.title]->isbn,r.copy+1,c->due,c->renewals);
}
static int isbn_order(const void *left, const void *right) {
    const Ref *a = left, *b = right;
    return strcmp(titles[a->title]->isbn,titles[b->title]->isbn);
}
static int due_order(const void *left, const void *right) {
    const Ref *a = left, *b = right;
    if (copy(*a)->due != copy(*b)->due) return copy(*a)->due < copy(*b)->due ? -1 : 1;
    int order = strcmp(members[copy(*a)->member]->id,members[copy(*b)->member]->id);
    return order ? order : isbn_order(left,right);
}
static int expiry_order(const void *left, const void *right) {
    const Ref *a = left, *b = right;
    if (copy(*a)->expiry != copy(*b)->expiry) return copy(*a)->expiry < copy(*b)->expiry ? -1 : 1;
    return isbn_order(left,right);
}
static int integer_order(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return a < b ? -1 : a > b ? 1 : 0;
}
static int search_order(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    int order = strcmp(titles[a]->folded,titles[b]->folded);
    return order ? order : strcmp(titles[a]->isbn,titles[b]->isbn);
}
static int top_order(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    if (titles[a]->borrowed != titles[b]->borrowed) return titles[a]->borrowed > titles[b]->borrowed ? -1 : 1;
    return strcmp(titles[a]->isbn,titles[b]->isbn);
}
static void execute(char **a, int count) {
    const char *cmd = a[0];
    if (!strcmp(cmd,"DAY")) {
        int target = atoi(a[1]);
        if (error(target <= day,"invalid day")) return;
        line("DAY %d",target);
        while (day < target) {
            ++day;
            Ref losses[10000];
            int loss_count = 0;
            for (int j = 0; j < member_count; ++j) {
                Member *m = members[member_order[j]];
                for (int i = 0; i < m->loan_count; ++i) if (copy(m->loans[i])->due+365 <= day) losses[loss_count++] = m->loans[i];
            }
            for (int i = 0; i < loss_count; ++i) end_loan(losses[i],true,"AUTOLOST");
            Ref expiries[20000];
            int expiry_count = 0;
            for (int j = 0; j < title_count; ++j) {
                int t = title_order[j];
                for (int i = 0; i < titles[t]->copy_count; ++i) {
                    Ref r = {t,i};
                    if (copy(r)->state == HOLD && copy(r)->expiry < day) expiries[expiry_count++] = r;
                }
            }
            for (int i = 0; i < expiry_count; ++i) {
                Ref r = expiries[i];
                int m = copy(r)->member;
                charge(m,1,r.title,members[m]->fee);
                remove_ref(members[m]->holds,&members[m]->hold_count,r);
                --members[m]->reservations;
                line("EXPIRED %s copy %d %s fee %s",titles[r.title]->isbn,r.copy+1,members[m]->id,money(members[m]->fee));
                release(r);
            }
        }
    } else if (!strcmp(cmd,"CLOSED")) {
        int d = atoi(a[1]);
        if (error(d <= day,"invalid day") || error(closed[d],"already closed")) return;
        closed[d] = true;
        ++closed_count;
        line("CLOSED %d",d);
        for (int j = 0; j < title_count; ++j) {
            Title *t = titles[title_order[j]];
            for (int i = 0; i < t->copy_count; ++i) {
                Copy *c = &t->copies[i];
                if (c->state == LOANED && c->due == d) {
                    c->due = open_day(d);
                    line("MOVED %s copy %d %s due %d",t->isbn,i+1,members[c->member]->id,c->due);
                } else if (c->state == HOLD && c->expiry == d) {
                    c->expiry = open_day(d);
                    line("MOVED %s copy %d %s until %d",t->isbn,i+1,members[c->member]->id,c->expiry);
                }
            }
        }
    } else if (!strcmp(cmd,"ADDBOOK")) {
        char *isbn = normalize(a[1]), *name = join(a,count,4);
        if (error(!isbn,"invalid isbn")) return;
        int t = find_title(isbn);
        if (error(t >= 0 && strcmp(titles[t]->name,name),"title mismatch")) return;
        if (t < 0) {
            t = title_count;
            titles[t] = calloc(1,sizeof(*titles[t]));
            if (!titles[t]) exit(EXIT_FAILURE);
            strcpy(titles[t]->isbn,isbn);
            strcpy(titles[t]->name,name);
            lower(titles[t]->folded,name);
            int position = title_count;
            while (position && strcmp(titles[title_order[position-1]]->isbn,isbn) > 0) {
                title_order[position] = title_order[position-1];
                --position;
            }
            title_order[position] = t;
            ++title_count;
        }
        Title *book = titles[t];
        book->price = cents(a[3]);
        int start = book->copy_count, added = atoi(a[2]);
        book->copy_count += added;
        book->counts[AVAILABLE] += added;
        line("ADDBOOK %s added %d total %d",isbn,added,holdings(t));
        for (int i = start; i < book->copy_count; ++i) release((Ref){t,i});
    } else if (!strcmp(cmd,"ADDMEMBER")) {
        if (error(find_member(a[1]) >= 0,"duplicate member") || error(strcmp(a[2],"STUDENT") && strcmp(a[2],"STAFF"),"unknown type")) return;
        int id = member_count;
        Member *m = calloc(1,sizeof(*m));
        if (!m) exit(EXIT_FAILURE);
        members[id] = m;
        strcpy(m->id,a[1]);
        strcpy(m->type,a[2]);
        strcpy(m->name,join(a,count,3));
        bool staff = !strcmp(m->type,"STAFF");
        m->limit = staff ? 10 : 3;
        m->period = staff ? 28 : 14;
        m->rate = staff ? 10 : 25;
        m->cap = staff ? 2000 : 1000;
        m->reserve_limit = staff ? 5 : 2;
        m->fee = staff ? 100 : 50;
        int position = member_count;
        while (position && strcmp(members[member_order[position-1]]->id,m->id) > 0) {
            member_order[position] = member_order[position-1];
            --position;
        }
        member_order[position] = id;
        ++member_count;
        line("ADDMEMBER %s %s loans %d days %d",m->id,m->type,m->limit,m->period);
    } else if (!strcmp(cmd,"WITHDRAW")) {
        int t = title(a[1]);
        if (t < 0) return;
        int i = atoi(a[2])-1;
        if (error(i < 0 || i >= titles[t]->copy_count,"unknown copy") || error(titles[t]->copies[i].state != AVAILABLE,"copy not available")) return;
        state((Ref){t,i},WITHDRAWN);
        line("WITHDRAW %s copy %d total %d",titles[t]->isbn,i+1,holdings(t));
    } else if (!strcmp(cmd,"BORROW") || !strcmp(cmd,"RETURN") || !strcmp(cmd,"RENEW") || !strcmp(cmd,"RESERVE") || !strcmp(cmd,"CANCEL") || !strcmp(cmd,"LOST")) {
        int m = member(a[1]);
        if (m < 0) return;
        int t = title(a[2]);
        if (t < 0) return;
        Member *p = members[m];
        Title *book = titles[t];
        int loan = find_ref(p->loans,p->loan_count,t), hold = find_ref(p->holds,p->hold_count,t), q = queue_position(book,m);
        if (!strcmp(cmd,"BORROW")) {
            if (error(closed[day],"library closed") || error(loan >= 0,"already borrowed") || error(p->balance > 500,"member blocked")) return;
            bool overdue = false;
            for (int i = 0; i < p->loan_count; ++i) overdue |= late(p->loans[i]) > 0;
            if (error(overdue,"overdue loans") || error(p->loan_count >= p->limit,"loan limit")) return;
            int available = -1;
            for (int i = 0; i < book->copy_count; ++i) {
                if (book->copies[i].state == AVAILABLE) {
                    available = i;
                    break;
                }
            }
            int i = hold >= 0 ? hold : available;
            if (error(i < 0,book->counts[HOLD] ? "all copies on hold" : "no copy available")) return;
            Ref r = {t,i};
            if (hold >= 0) {
                remove_ref(p->holds,&p->hold_count,r);
                --p->reservations;
            }
            state(r,LOANED);
            *copy(r) = (Copy){LOANED,m,day,open_day(day+p->period),0,0};
            p->loans[p->loan_count++] = r;
            qsort(p->loans,(size_t)p->loan_count,sizeof(*p->loans),isbn_order);
            ++borrowed;
            ++book->borrowed;
            line("BORROW %s %s copy %d due %d",p->id,book->isbn,i+1,copy(r)->due);
        } else if (!strcmp(cmd,"RETURN") || !strcmp(cmd,"LOST") || !strcmp(cmd,"RENEW")) {
            if (error(loan < 0,"not borrowed")) return;
            Ref r = {t,loan};
            if (!strcmp(cmd,"RENEW")) {
                if (error(p->balance > 500,"member blocked")) return;
                const char *reason = renewal_reason(r);
                if (error(reason != NULL,reason)) return;
                renew(r);
            } else end_loan(r,!strcmp(cmd,"LOST"),cmd);
        } else if (!strcmp(cmd,"RESERVE")) {
            if (error(loan >= 0,"already borrowed") || error(q >= 0 || hold >= 0,"already reserved") || error(p->balance > 500,"member blocked") || error(p->reservations >= p->reserve_limit,"reservation limit") || error(!holdings(t),"no copies") || error(book->counts[AVAILABLE] > 0,"copy available")) return;
            book->queue[book->queue_count++] = m;
            ++p->reservations;
            int dues[99], length = 0;
            for (int i = 0; i < book->copy_count; ++i) if (book->copies[i].state == LOANED) dues[length++] = book->copies[i].due;
            qsort(dues,(size_t)length,sizeof(*dues),integer_order);
            line("RESERVE %s %s position %d estimate %s",p->id,book->isbn,book->queue_count,book->queue_count <= length ? format("%d",dues[book->queue_count-1]) : "none");
        } else {
            if (error(q < 0 && hold < 0,"not reserved")) return;
            --p->reservations;
            if (q >= 0) {
                remove_queue(book,q);
                line("CANCEL %s %s queue",p->id,book->isbn);
            } else {
                Ref r = {t,hold};
                remove_ref(p->holds,&p->hold_count,r);
                line("CANCEL %s %s hold copy %d",p->id,book->isbn,hold+1);
                release(r);
            }
        }
    } else if (!strcmp(cmd,"RENEWALL")) {
        int m = member(a[1]);
        if (m < 0) return;
        Member *p = members[m];
        if (error(!p->loan_count,"no loans") || error(p->balance > 500,"member blocked")) return;
        int good = 0, skipped = 0;
        for (int i = 0; i < p->loan_count; ++i) {
            Ref r = p->loans[i];
            const char *reason = renewal_reason(r);
            if (reason) {
                line("SKIP %s %s",titles[r.title]->isbn,reason);
                ++skipped;
            } else {
                renew(r);
                ++good;
            }
        }
        line("RENEWALL %s renewed %d skipped %d",p->id,good,skipped);
    } else if (!strcmp(cmd,"PAYFINE") || !strcmp(cmd,"WAIVE") || !strcmp(cmd,"FINES")) {
        int m = member(a[1]);
        if (m < 0) return;
        Member *p = members[m];
        if (!strcmp(cmd,"PAYFINE")) {
            if (error(!p->balance,"no fines")) return;
            int amount = cents(a[2]), remaining = amount;
            int *applied = calloc((size_t)p->charge_count,sizeof(*applied));
            if (!applied) exit(EXIT_FAILURE);
            for (int i = 0; i < p->charge_count && remaining; ++i) {
                Charge *c = &p->charges[i];
                applied[i] = remaining < c->unpaid ? remaining : c->unpaid;
                c->unpaid -= applied[i];
                remaining -= applied[i];
            }
            p->balance -= amount-remaining;
            paid += amount-remaining;
            line("PAYFINE %s paid %s change %s balance %s",p->id,money(amount-remaining),money(remaining),money(p->balance));
            for (int i = 0; i < p->charge_count; ++i) if (applied[i]) line("ITEM %d %s paid %s remaining %s",i+1,kinds[p->charges[i].kind],money(applied[i]),money(p->charges[i].unpaid));
            free(applied);
        } else if (!strcmp(cmd,"WAIVE")) {
            int i = atoi(a[2])-1;
            if (error(i < 0 || i >= p->charge_count,"unknown item")) return;
            Charge *c = &p->charges[i];
            if (error(!c->unpaid,"item settled")) return;
            int amount = c->unpaid;
            c->unpaid = 0;
            p->balance -= amount;
            waived += amount;
            line("WAIVE %s item %d %s amount %s balance %s",p->id,i+1,kinds[c->kind],money(amount),money(p->balance));
        } else {
            int count_unpaid = 0;
            for (int i = 0; i < p->charge_count; ++i) count_unpaid += p->charges[i].unpaid > 0;
            line("FINES %s items %d balance %s",p->id,count_unpaid,money(p->balance));
            for (int i = 0; i < p->charge_count; ++i) {
                Charge c = p->charges[i];
                if (c.unpaid) line("%d day %d %s %s amount %s remaining %s",i+1,c.day,kinds[c.kind],titles[c.title]->isbn,money(c.amount),money(c.unpaid));
            }
        }
    } else if (!strcmp(cmd,"SEARCH")) {
        char keyword[31];
        lower(keyword,join(a,count,1));
        int found[1000], length = 0;
        for (int i = 0; i < title_count; ++i) if (strstr(titles[i]->folded,keyword)) found[length++] = i;
        qsort(found,(size_t)length,sizeof(*found),search_order);
        line("SEARCH %d",length);
        for (int j = 0; j < length; ++j) {
            int t = found[j];
            line("%s %d/%d %s",titles[t]->isbn,titles[t]->counts[AVAILABLE],holdings(t),titles[t]->name);
        }
    } else if (!strcmp(cmd,"OVERDUE")) {
        Ref refs[10000];
        int length = 0;
        for (int m = 0; m < member_count; ++m) {
            for (int i = 0; i < members[m]->loan_count; ++i) if (late(members[m]->loans[i])) refs[length++] = members[m]->loans[i];
        }
        qsort(refs,(size_t)length,sizeof(*refs),due_order);
        line("OVERDUE %d",length);
        for (int i = 0; i < length; ++i) {
            Ref r = refs[i];
            line("%s %s copy %d due %d late %d fine %s",members[copy(r)->member]->id,titles[r.title]->isbn,r.copy+1,copy(r)->due,late(r),money(fine(r)));
        }
    } else if (!strcmp(cmd,"NOTICES")) {
        char **notices = resize(NULL,15000*sizeof(*notices));
        int length = 0;
        for (int j = 0; j < member_count; ++j) {
            Member *m = members[member_order[j]];
            Ref refs[10];
            memcpy(refs,m->loans,(size_t)m->loan_count*sizeof(*refs));
            qsort(refs,(size_t)m->loan_count,sizeof(*refs),due_order);
            for (int i = 0; i < m->loan_count; ++i) {
                Ref r = refs[i];
                if (copy(r)->due <= day+2) notices[length++] = format("%s %s %s due %d",late(r) ? "OVERDUE" : "DUESOON",m->id,titles[r.title]->isbn,copy(r)->due);
            }
            memcpy(refs,m->holds,(size_t)m->hold_count*sizeof(*refs));
            qsort(refs,(size_t)m->hold_count,sizeof(*refs),expiry_order);
            for (int i = 0; i < m->hold_count; ++i) notices[length++] = format("PICKUP %s %s until %d",m->id,titles[refs[i].title]->isbn,copy(refs[i])->expiry);
        }
        line("NOTICES %d",length);
        for (int i = 0; i < length; ++i) line("%s",notices[i]);
        free(notices);
    } else if (!strcmp(cmd,"MEMBER") || !strcmp(cmd,"MEMBERS") || !strcmp(cmd,"HISTORY")) {
        int target = -1;
        if (strcmp(cmd,"MEMBERS")) {
            target = member(a[1]);
            if (target < 0) return;
        }
        if (!strcmp(cmd,"HISTORY")) {
            Member *m = members[target];
            line("HISTORY %s %d",m->id,m->history_count);
            for (int i = 0; i < m->history_count; ++i) line("%s",m->history[i]);
            return;
        }
        if (!strcmp(cmd,"MEMBERS")) line("MEMBERS %d",member_count);
        for (int j = 0; j < member_count; ++j) {
            int id = member_order[j];
            if (target >= 0 && id != target) continue;
            Member *m = members[id];
            const char *status = m->balance > 500 ? "BLOCKED" : "OK";
            if (!strcmp(cmd,"MEMBERS")) {
                line("%s %s loans %d reservations %d balance %s %s",m->id,m->type,m->loan_count,m->reservations,money(m->balance),status);
                continue;
            }
            line("MEMBER %s %s %s",m->id,m->type,m->name);
            line("STATUS loans %d/%d reservations %d/%d balance %s %s",m->loan_count,m->limit,m->reservations,m->reserve_limit,money(m->balance),status);
            Ref refs[10];
            memcpy(refs,m->loans,(size_t)m->loan_count*sizeof(*refs));
            qsort(refs,(size_t)m->loan_count,sizeof(*refs),due_order);
            for (int i = 0; i < m->loan_count; ++i) {
                Ref r = refs[i];
                line("LOAN %s copy %d due %d renewals %d%s",titles[r.title]->isbn,r.copy+1,copy(r)->due,copy(r)->renewals,late(r) ? format(" late %d fine %s",late(r),money(fine(r))) : "");
            }
            memcpy(refs,m->holds,(size_t)m->hold_count*sizeof(*refs));
            qsort(refs,(size_t)m->hold_count,sizeof(*refs),expiry_order);
            for (int i = 0; i < m->hold_count; ++i) line("HOLD %s copy %d until %d",titles[refs[i].title]->isbn,refs[i].copy+1,copy(refs[i])->expiry);
            for (int k = 0; k < title_count; ++k) {
                int t = title_order[k], q = queue_position(titles[t],id);
                if (q >= 0) line("QUEUE %s position %d",titles[t]->isbn,q+1);
            }
        }
    } else if (!strcmp(cmd,"BOOK")) {
        int t = title(a[1]);
        if (t < 0) return;
        Title *book = titles[t];
        line("BOOK %s %s",book->isbn,book->name);
        line("PRICE %s copies %d borrowed %d",money(book->price),holdings(t),book->borrowed);
        for (int i = 0; i < book->copy_count; ++i) {
            Copy c = book->copies[i];
            if (c.state == LOANED || c.state == HOLD) line("COPY %d %s %s %s %d",i+1,states[c.state],members[c.member]->id,c.state == LOANED ? "due" : "until",c.state == LOANED ? c.due : c.expiry);
            else line("COPY %d %s",i+1,states[c.state]);
        }
        printf("QUEUE %d",book->queue_count);
        for (int i = 0; i < book->queue_count; ++i) printf(" %s",members[book->queue[i]]->id);
        putchar('\n');
    } else if (!strcmp(cmd,"INVENTORY")) {
        int totals[5] = {0};
        for (int t = 0; t < title_count; ++t) for (int i = 0; i < 5; ++i) totals[i] += titles[t]->counts[i];
        line("INVENTORY titles %d copies %d available %d loaned %d hold %d lost %d withdrawn %d",title_count,totals[0]+totals[1]+totals[2],totals[0],totals[1],totals[2],totals[3],totals[4]);
        for (int j = 0; j < title_count; ++j) {
            int t = title_order[j];
            Title *b = titles[t];
            line("%s copies %d available %d loaned %d hold %d queue %d",b->isbn,holdings(t),b->counts[0],b->counts[1],b->counts[2],b->queue_count);
        }
    } else if (!strcmp(cmd,"STATS")) {
        int active = 0, outstanding = 0;
        for (int i = 0; i < member_count; ++i) {
            active += members[i]->loan_count;
            outstanding += members[i]->balance;
        }
        line("STATS day %d titles %d members %d closed %d",day,title_count,member_count,closed_count);
        line("LOANS borrowed %d returned %d renewed %d lost %d active %d",borrowed,returned,renewed,lost,active);
        line("MONEY fines %s fees %s charges %s paid %s waived %s outstanding %s",money(charged[0]),money(charged[1]),money(charged[2]),money(paid),money(waived),money(outstanding));
        int top[1000], length = 0;
        for (int i = 0; i < title_count; ++i) if (titles[i]->borrowed) top[length++] = i;
        qsort(top,(size_t)length,sizeof(*top),top_order);
        for (int i = 0; i < length && i < 3; ++i) line("TOP %d %s %d %s",i+1,titles[top[i]]->isbn,titles[top[i]]->borrowed,titles[top[i]]->name);
    }
}
int main(void) {
    char input[512];
    if (!fgets(input,sizeof(input),stdin)) return 0;
    int count = atoi(input);
    for (int i = 0; i < count; ++i) {
        if (!fgets(input,sizeof(input),stdin)) break;
        input[strcspn(input,"\n")] = '\0';
        char *arguments[128];
        int length = 0;
        for (char *word = strtok(input," "); word; word = strtok(NULL," ")) arguments[length++] = word;
        execute(arguments,length);
        clear_temps();
    }
    for (int i = 0; i < title_count; ++i) free(titles[i]);
    for (int i = 0; i < member_count; ++i) {
        for (int j = 0; j < members[i]->history_count; ++j) free(members[i]->history[j]);
        free(members[i]->history);
        free(members[i]->charges);
        free(members[i]);
    }
    return 0;
}
