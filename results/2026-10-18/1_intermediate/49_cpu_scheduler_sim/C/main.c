#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
typedef long long I;
typedef struct {
    char id[9];
    int arrival, priority, deadline, bursts[15], count;
} Process;
typedef struct {
    int state, burst, left, effective, wait, level, used, enqueued, start, finish, slices;
    int ready[8], began[8], ended[8], selections[8];
} Job;
typedef struct {
    int ids[10], count;
} Queue;
typedef struct {
    Process p[10];
    Job j[10];
    Queue q[3];
    int count, algo, cpu, current, previous, switch_left, run, switches, end, busy, switching, idle, maxq, sumq, events[5];
    int labels[20000], lengths[20000];
    char timeline[10][20001], snapshot[4000];
    I param[5], random, totals[3];
    int missed, met;
} Simulation;
static Process registry[10];
static int count;
static const char *algos[]={"FCFS","SJF","SRTF","RR","PRIORITY","HRRN","EDF","LOTTERY","MLFQ"};
static const char *keys[]={"cs","q","k","s","seed"}, *metrics[]={"turnaround","waiting","response","end","switches","missed"}, *states[]={"FUTURE","READY","SWITCH","RUN","IO","DONE"};
static const I low[]={0,1,1,0,1}, high[]={5,20,50,500,2147483646LL};

static int lookup(const char *s, const char **names, int n) {
    for (int i=0; i<n; i++) if (!strcmp(s, names[i])) return i;
    return -1;
}

static int find(const char *id) {
    for (int i=0; i<count; i++) if (!strcmp(registry[i].id, id)) return i;
    return -1;
}

static int uses(int a, int k) {
    return a<0||k==0||(k==1&&(a==3||a==7))||(k==2&&a==4)||(k==3&&a==8)||(k==4&&a==7);
}

static void decimal(I u, I v, char *s) {
    I x=u*100/v;
    sprintf(s,"%lld.%02lld", x/100, x%100);
}

static void notation(I *p, int a, char *s) {
    s[0]=0;
    for (int k=0; k<5; k++) if (uses(a, k)) {
        char part[80];
        sprintf(part,"%s%s=%lld", s[0]?" ":"", keys[k], p[k]);
        strcat(s, part);
    }
}

static int params(char **w, int n, int a, int preset, I *p) {
    I defaults[]={0,4,5,0,1};
    int seen[5]={0};
    memcpy(p, defaults, sizeof defaults);
    if (preset>=0)seen[preset]=1;
    for (int i=0; i<n; i++) {
        char *eq=strchr(w[i],'=');
        *eq=0;
        int k=lookup(w[i], keys,5);
        I v=atoll(eq+1);
        if (k<0) {
            printf("ERROR unknown key %s\n", w[i]);
            return 0;
        }
        if (!uses(a, k)) {
            printf("ERROR key %s not allowed for %s\n", w[i], algos[a]);
            return 0;
        }
        if (seen[k]) {
            printf("ERROR duplicate key %s\n", w[i]);
            return 0;
        }
        if (v<low[k]||v>high[k]) {
            printf("ERROR invalid %s\n", w[i]);
            return 0;
        }
        seen[k]=1;
        p[k]=v;
    }
    if (!count) {
        puts("ERROR no processes");
        return 0;
    }
    return 1;
}

static void describe(Process *p) {
    printf("%s arrival=%d priority=%d deadline=", p->id, p->arrival, p->priority);
    if (p->deadline)printf("%d", p->deadline);
    else printf("none");
    printf(" bursts=");
    for (int j=0; j<p->count; j++)printf("%s%c%d", j?",":"", j%2?'I':'C', p->bursts[j]);
    puts("");
}

static int process_compare(const void *a, const void *b) {
    return strcmp(((const Process*)a)->id,((const Process*)b)->id);
}

static I draw(I *x, I modulus) {
    *x=48271 * *x%2147483647;
    return *x%modulus;
}

static void event(Simulation *s, int t, int kind, int id, int value, int trace) {
    static const char *names[]={"PREEMPT","EXPIRE","DEMOTE","BOOST","AGE","ARRIVE","IODONE","START","DONE","IO","SWITCH","DISPATCH"};
    if (kind<5)s->events[kind]++;
    if (trace) {
        printf("%d %s", t, names[kind]);
        if (id>=0)printf(" %s", s->p[id].id);
        if (value>=0)printf(" %d", value);
        puts("");
    }
}

static void enqueue(Simulation *s, int i, int t) {
    Job *j=&s->j[i];
    j->state=1;
    j->enqueued=t;
    Queue *q=&s->q[s->algo==8?j->level:0];
    q->ids[q->count++]=i;
}

static void start(Simulation *s, int i, int t) {
    Job *j=&s->j[i];
    s->cpu=3;
    s->current=i;
    s->run=0;
    j->state=3;
    if (j->start<0)j->start=t;
    if (j->began[j->burst/2]<0)j->began[j->burst/2]=t;
}

static int deadline(Simulation *s, int i) {
    return s->p[i].deadline?s->p[i].arrival+s->p[i].deadline:1000000000;
}

static int preempts(Simulation *s, int i) {
    for (int k=0; k<3; k++) for (int a=0; a<s->q[k].count; a++) {
        int b=s->q[k].ids[a];
        if ((s->algo==2&&s->j[b].left<s->j[i].left)||(s->algo==4&&s->j[b].effective<s->j[i].effective)||(s->algo==6&&deadline(s, b)<deadline(s, i))||(s->algo==8&&k<s->j[i].level)) return 1;
    }
    return 0;
}

static int choose(Simulation *s, Queue *q, int t) {
    int selected=0;
    if (s->algo==7) {
        I total=0;
        for (int k=0; k<q->count; k++)total+=10-s->p[q->ids[k]].priority;
        I r=draw(&s->random, total);
        for (int k=0; k<q->count; k++) {
            r-=10-s->p[q->ids[k]].priority;
            if (r<0) return k;
        }
    }
    for (int k=1; k<q->count; k++) {
        int x=q->ids[k], y=q->ids[selected];
        Job *a=&s->j[x], *b=&s->j[y];
        int better=0;
        if (s->algo==1||s->algo==2)better=a->left<b->left;
        else if (s->algo==4)better=a->effective<b->effective;
        else if (s->algo==5)better=(I)(t-a->enqueued+a->left)*b->left>(I)(t-b->enqueued+b->left)*a->left;
        else if (s->algo==6)better=deadline(s, x)<deadline(s, y);
        if (better)selected=k;
    }
    return selected;
}

static void capture(Simulation *s) {
    char *out=s->snapshot;
    int used=0;
    if (s->cpu==0)used+=sprintf(out+used,"CPU IDLE\n");
    else used+=sprintf(out+used,"CPU %s %s\n", states[s->cpu], s->p[s->current].id);
    for (int k=0; k<(s->algo==8?3:1); k++) {
        used+=sprintf(out+used, s->algo==8?"QUEUE%d":"QUEUE", k);
        Queue *q=&s->q[k];
        if (!q->count)used+=sprintf(out+used," none");
        for (int a=0; a<q->count; a++)used+=sprintf(out+used," %s", s->p[q->ids[a]].id);
        used+=sprintf(out+used,"\n");
    }
    for (int i=0; i<s->count; i++) {
        Job *j=&s->j[i];
        used+=sprintf(out+used,"%s %s", s->p[i].id, states[j->state]);
        if (j->state==0)used+=sprintf(out+used," at=%d", s->p[i].arrival);
        else if (j->state==5)used+=sprintf(out+used," at=%d", j->finish);
        else {
            used+=sprintf(out+used," burst=%d left=%d", j->burst+1, j->left);
            if (s->algo==4)used+=sprintf(out+used," prio=%d", j->effective);
            if (s->algo==8)used+=sprintf(out+used," level=%d used=%d", j->level, j->used);
        }
        used+=sprintf(out+used,"\n");
    }
}

static Simulation *simulate(int algo, I *param, int snapshot, int trace) {
    Simulation *s=calloc(1, sizeof *s);
    s->count=count;
    s->algo=algo;
    s->current=s->previous=-1;
    s->random=param[4];
    memcpy(s->param, param, sizeof s->param);
    memcpy(s->p, registry,(size_t)count*sizeof *registry);
    qsort(s->p,(size_t)count, sizeof *s->p, process_compare);
    for (int i=0; i<count; i++) {
        s->j[i].left=s->p[i].bursts[0];
        s->j[i].effective=s->p[i].priority;
        s->j[i].start=-1;
        for (int b=0; b<8; b++)s->j[i].began[b]=-1;
    }
    for (int t=0; ; t++) {
        if (algo==4) for (int k=0; k<s->q[0].count; k++) {
            int i=s->q[0].ids[k];
            Job *j=&s->j[i];
            if (++j->wait==param[2]) {
                j->wait=0;
                if (j->effective) {
                    j->effective--;
                    event(s, t,4, i, j->effective, trace);
                }
            }
        }
        for (int i=0; i<count; i++) if (s->j[i].state==4&&!s->j[i].left) {
            Job *j=&s->j[i];
            j->burst++;
            j->left=s->p[i].bursts[j->burst];
            j->ready[j->burst/2]=t;
            enqueue(s, i, t);
            event(s, t,6, i,-1, trace);
        }
        for (int i=0; i<count; i++) if (!s->j[i].state&&s->p[i].arrival==t) {
            s->j[i].ready[0]=t;
            enqueue(s, i, t);
            event(s, t,5, i,-1, trace);
        }
        if (s->cpu==2&&!s->switch_left) {
            start(s, s->current, t);
            event(s, t,7, s->current,-1, trace);
        } else if (s->cpu==3) {
            int i=s->current;
            Job *j=&s->j[i];
            if (!j->left&&j->burst==s->p[i].count-1) {
                j->state=5;
                j->finish=t;
                event(s, t,8, i,-1, trace);
                s->cpu=0;
            } else {
                int demoted=algo==8&&j->level<2&&j->used==(j->level?8:4);
                if (demoted) {
                    j->level++;
                    j->used=0;
                    event(s, t,2, i, j->level, trace);
                }
                if (!j->left) {
                    j->burst++;
                    j->left=s->p[i].bursts[j->burst];
                    j->state=4;
                    event(s, t,9, i, j->left, trace);
                    s->cpu=0;
                } else if (demoted) {
                    enqueue(s, i, t);
                    s->cpu=0;
                } else if ((algo==3||algo==7)&&s->run==param[1]) {
                    enqueue(s, i, t);
                    event(s, t,1, i,-1, trace);
                    s->cpu=0;
                } else if (preempts(s, i)) {
                    enqueue(s, i, t);
                    event(s, t,0, i,-1, trace);
                    s->cpu=0;
                }
            }
        }
        int done=0;
        for (int i=0; i<count; i++)done+=s->j[i].state==5;
        if (done==count) {
            s->end=t;
            if (!s->snapshot[0]&&snapshot>=0)capture(s);
            break;
        }
        if (algo==8&&param[3]&&t&&t%param[3]==0) {
            for (int k=1; k<3; k++) {
                for (int a=0; a<s->q[k].count; a++)s->q[0].ids[s->q[0].count++]=s->q[k].ids[a];
                s->q[k].count=0;
            }
            for (int i=0; i<count; i++)s->j[i].level=s->j[i].used=0;
            event(s, t,3,-1,-1, trace);
        }
        if (!s->cpu) {
            Queue *q=NULL;
            for (int k=0; k<3; k++) if (s->q[k].count) {
                q=&s->q[k];
                break;
            }
            if (q) {
                int a=choose(s, q, t), i=q->ids[a];
                for (int k=a+1; k<q->count; k++)q->ids[k-1]=q->ids[k];
                q->count--;
                Job *j=&s->j[i];
                j->effective=s->p[i].priority;
                j->wait=0;
                j->slices++;
                j->selections[j->burst/2]++;
                int changed=i!=s->previous;
                if (changed)s->switches++;
                if (changed&&param[0]) {
                    s->cpu=2;
                    s->current=i;
                    s->switch_left=(int)param[0];
                    j->state=2;
                    event(s, t,10, i,-1, trace);
                } else {
                    start(s, i, t);
                    event(s, t,11, i,-1, trace);
                }
            }
        }
        if (t==snapshot)capture(s);
        int qlen=s->q[0].count+s->q[1].count+s->q[2].count;
        s->lengths[t]=qlen;
        s->sumq+=qlen;
        if (qlen>s->maxq)s->maxq=qlen;
        for (int i=0; i<count; i++)s->timeline[i][t]="-.s#i-"[s->j[i].state];
        if (s->cpu==3) {
            Job *j=&s->j[s->current];
            j->left--;
            j->used++;
            s->run++;
            s->previous=s->current;
            s->labels[t]=s->current;
            s->busy++;
            if (!j->left)j->ended[j->burst/2]=t+1;
        } else if (s->cpu==2) {
            s->switch_left--;
            s->labels[t]=-2;
            s->switching++;
        } else {
            s->labels[t]=-1;
            s->idle++;
        }
        for (int i=0; i<count; i++) if (s->j[i].state==4)s->j[i].left--;
    }
    for (int i=0; i<count; i++) {
        Job *j=&s->j[i];
        int turnaround=j->finish-s->p[i].arrival, total=0;
        for (int b=0; b<s->p[i].count; b++)total+=s->p[i].bursts[b];
        s->totals[0]+=turnaround;
        s->totals[1]+=turnaround-total;
        s->totals[2]+=j->start-s->p[i].arrival;
        if (s->p[i].deadline) {
            if (j->finish>deadline(s, i))s->missed++;
            else s->met++;
        }
    }
    return s;
}

static I metric(Simulation *s, int i, int m) {
    if (m==0) return s->j[i].finish-s->p[i].arrival;
    if (m==2) return s->j[i].start-s->p[i].arrival;
    I x=metric(s, i,0);
    for (int b=0; b<s->p[i].count; b++)x-=s->p[i].bursts[b];
    return x;
}

static const char *label(Simulation *s, int t) {
    return s->labels[t]==-1?"IDLE":s->labels[t]==-2?"CS":s->p[s->labels[t]].id;
}

static void averages(Simulation *s, char a[3][40], char *util) {
    for (int m=0; m<3; m++)decimal(s->totals[m], s->count, a[m]);
    decimal(s->busy*100, s->end, util);
}

static I rank_value(Simulation *s, int m) {
    return m<3?s->totals[m]:m==3?s->end:m==4?s->switches:s->missed;
}

static void simulation_output(const char *command, int algo, I *p, Simulation *s, int argument) {
    char note[200], a[3][40], util[40];
    notation(p, algo, note);
    averages(s, a, util);
    if (!strcmp(command,"TRACE")) {
        printf("END %d\n", s->end);
        return;
    }
    if (!strcmp(command,"TIMELINE")) {
        if (s->end>100) {
            printf("ERROR too long %d\n", s->end);
            return;
        }
        printf("TIMELINE %s %s end=%d\n", algos[algo], note, s->end);
        for (int i=0; i<count; i++)printf("%-8s %s\n", s->p[i].id, s->timeline[i]);
        return;
    }
    if (!strcmp(command,"SNAPSHOT")) {
        printf("SNAPSHOT %s %s t=%d\n%s", algos[algo], note, argument, s->snapshot);
        return;
    }
    if (!strcmp(command,"WINDOW")) {
        printf("WINDOW %s %s width=%d\n", algos[algo], note, argument);
        for (int start=0; start<s->end; start+=argument) {
            int end=start+argument;
            if (end>s->end)end=s->end;
            int busy=0, cs=0, idle=0, hits[10]={0};
            for (int t=start; t<end; t++) if (s->labels[t]==-1)idle++;
            else if (s->labels[t]==-2)cs++;
            else {
                busy++;
                hits[s->labels[t]]++;
            }
            int top=-1;
            for (int i=0; i<count; i++) if (hits[i]&&(top<0||hits[i]>hits[top]))top=i;
            char u[40];
            decimal(busy*100, end-start, u);
            printf("%d-%d busy=%d switch=%d idle=%d util=%s top=%s\n", start, end, busy, cs, idle, u, top<0?"none":s->p[top].id);
        }
        return;
    }
    printf("%s %s %s\n", command, algos[algo], note);
    if (!strcmp(command,"BURSTS")) {
        for (int i=0; i<count; i++) for (int b=0; b<s->p[i].count; b+=2) {
            Job *j=&s->j[i];
            int k=b/2, len=s->p[i].bursts[b];
            printf("%s #%d len=%d ready=%d start=%d end=%d wait=%d slices=%d\n", s->p[i].id, k+1, len, j->ready[k], j->began[k], j->ended[k], j->ended[k]-j->ready[k]-len, j->selections[k]);
        }
        return;
    }
    if (!strcmp(command,"STATS")) {
        for (int m=0; m<3; m++) {
            I values[10];
            int lo=0, hi=0;
            for (int i=0; i<count; i++) {
                values[i]=metric(s, i, m);
                if (values[i]<metric(s, lo, m))lo=i;
                if (values[i]>metric(s, hi, m))hi=i;
            }
            for (int i=1; i<count; i++) {
                I v=values[i];
                int j=i;
                while (j&&values[j-1]>v) {
                    values[j]=values[j-1];
                    j--;
                }
                values[j]=v;
            }
            I twice=count%2?2*values[count/2]:values[count/2-1]+values[count/2];
            printf("%s min=%lld (%s) max=%lld (%s) median=%lld.%d total=%lld\n", metrics[m], metric(s, lo, m), s->p[lo].id, metric(s, hi, m), s->p[hi].id, twice/2, twice%2?5:0, s->totals[m]);
        }
        return;
    }
    int start=0, segments=0;
    for (int t=1; t<=s->end; t++) if (t==s->end||strcmp(label(s, t), label(s, start))) {
        if (segments%8==0)printf("GANTT ");
        printf("[%d-%d %s]", start, t, label(s, start));
        segments++;
        if (segments%8==0||t==s->end)puts("");
        start=t;
    }
    for (int i=0; i<count; i++) {
        printf("%s arrival=%d done=%d turnaround=%lld waiting=%lld response=%lld slices=%d", s->p[i].id, s->p[i].arrival, s->j[i].finish, metric(s, i,0), metric(s, i,1), metric(s, i,2), s->j[i].slices);
        if (s->p[i].deadline) {
            int d=deadline(s, i), late=s->j[i].finish-d;
            printf(" deadline=%d late=%d", d, late>0?late:0);
        }
        puts("");
    }
    printf("AVERAGE turnaround=%s waiting=%s response=%s\n", a[0], a[1], a[2]);
    printf("CPU end=%d busy=%d switch=%d idle=%d switches=%d util=%s\n", s->end, s->busy, s->switching, s->idle, s->switches, util);
    char avgq[40];
    decimal(s->sumq, s->end, avgq);
    printf("QUEUE max=%d avg=%s\n", s->maxq, avgq);
    printf("EVENTS preempt=%d expire=%d demote=%d boost=%d age=%d\n", s->events[0], s->events[1], s->events[2], s->events[3], s->events[4]);
    printf("DEADLINE met=%d missed=%d\n", s->met, s->missed);
}

static void command(char **w, int n) {
    char *c=w[0];
    if (!strcmp(c,"PROC")) {
        int at=find(w[1]);
        if (at>=0) {
            printf("ERROR duplicate process %s\n", w[1]);
            return;
        }
        if (count==10) {
            puts("ERROR too many processes");
            return;
        }
        if (atoll(w[2])>200) {
            printf("ERROR invalid arrival %s\n", w[1]);
            return;
        }
        if (atoll(w[3])>9) {
            printf("ERROR invalid priority %s\n", w[1]);
            return;
        }
        int bursts=n-4, valid=bursts%2;
        for (int i=0; i<bursts; i++) if (w[i+4][0]!=(i%2?'I':'C')||atoll(w[i+4]+1)<1||atoll(w[i+4]+1)>30)valid=0;
        if (!valid) {
            printf("ERROR invalid bursts %s\n", w[1]);
            return;
        }
        Process p={0};
        strcpy(p.id, w[1]);
        p.arrival=atoi(w[2]);
        p.priority=atoi(w[3]);
        p.count=bursts;
        int cpu=0, io=0;
        for (int i=0; i<bursts; i++) {
            p.bursts[i]=atoi(w[i+4]+1);
            if (i%2)io+=p.bursts[i];
            else cpu+=p.bursts[i];
        }
        registry[count++]=p;
        printf("PROC %s cpu=%d io=%d\n", p.id, cpu, io);
        return;
    }
    if (!strcmp(c,"GEN")) {
        int amount=atoi(w[2]);
        for (int i=1; i<=amount; i++) {
            char id[9];
            sprintf(id,"%s%d", w[1], i);
            if (find(id)>=0) {
                printf("ERROR duplicate process %s\n", id);
                return;
            }
        }
        if (count+amount>10) {
            puts("ERROR too many processes");
            return;
        }
        I random=atoll(w[3]);
        printf("GEN count=%d\n", amount);
        for (int i=1; i<=amount; i++) {
            Process p={0};
            sprintf(p.id,"%s%d", w[1], i);
            p.arrival=(int)draw(&random,21);
            p.priority=(int)draw(&random,10);
            int m=1+(int)draw(&random,3);
            for (int b=0; b<m; b++) {
                if (b)p.bursts[p.count++]=1+(int)draw(&random,8);
                p.bursts[p.count++]=1+(int)draw(&random,9);
            }
            registry[count++]=p;
            describe(&p);
        }
        return;
    }
    if (!strcmp(c,"SETPRIO")||!strcmp(c,"DEADLINE")||!strcmp(c,"DROP")) {
        int i=find(w[1]);
        if (i<0) {
            printf("ERROR unknown process %s\n", w[1]);
            return;
        }
        if (!strcmp(c,"DROP")) {
            for (int j=i+1; j<count; j++)registry[j-1]=registry[j];
            count--;
            printf("DROP %s\n", w[1]);
            return;
        }
        int v=atoi(w[2]), isprio=!strcmp(c,"SETPRIO");
        if (v>(isprio?9:1000)) {
            printf("ERROR invalid %s %s\n", isprio?"priority":"deadline", w[1]);
            return;
        }
        if (isprio) {
            registry[i].priority=v;
            printf("SETPRIO %s priority=%d\n", w[1], v);
        } else {
            registry[i].deadline=v;
            if (v)printf("DEADLINE %s %d\n", w[1], v);
            else printf("DEADLINE %s none\n", w[1]);
        }
        return;
    }
    if (!strcmp(c,"CLEAR")) {
        printf("CLEAR count=%d\n", count);
        count=0;
        return;
    }
    if (!strcmp(c,"LIST")) {
        printf("LIST count=%d\n", count);
        Process sorted[10];
        memcpy(sorted, registry,(size_t)count*sizeof *registry);
        qsort(sorted,(size_t)count, sizeof *sorted, process_compare);
        for (int i=0; i<count; i++)describe(&sorted[i]);
        return;
    }
    int all=!strcmp(c,"COMPARE")||!strcmp(c,"RANK"), diff=!strcmp(c,"DIFF"), a=-1, b=-1, m=-1, offset=2, key=-1, arg=-1;
    I lo=0, hi=0, p[5];
    if (!all) {
        a=lookup(w[1], algos,9);
        if (a<0) {
            printf("ERROR unknown algorithm %s\n", w[1]);
            return;
        }
        if (diff) {
            b=lookup(w[2], algos,9);
            offset=3;
            if (b<0) {
                printf("ERROR unknown algorithm %s\n", w[2]);
                return;
            }
        }
    } else if (!strcmp(c,"RANK")) {
        m=lookup(w[1], metrics,6);
        if (m<0) {
            printf("ERROR unknown metric %s\n", w[1]);
            return;
        }
    } else offset=1;
    if (!strcmp(c,"WINDOW")) {
        I width=atoll(w[2]);
        if (width<1||width>1000) {
            puts("ERROR invalid window");
            return;
        }
        arg=(int)width;
        offset=3;
    }
    if (!strcmp(c,"SNAPSHOT")) {
        arg=atoi(w[2]);
        offset=3;
    }
    if (!strcmp(c,"SWEEP")) {
        key=lookup(w[2], keys,5);
        if (key<0) {
            printf("ERROR unknown key %s\n", w[2]);
            return;
        }
        if (!uses(a, key)) {
            printf("ERROR key %s not allowed for %s\n", w[2], algos[a]);
            return;
        }
        lo=atoll(w[3]);
        hi=atoll(w[4]);
        if (lo>hi||lo<low[key]||hi>high[key]||hi-lo>20) {
            puts("ERROR invalid range");
            return;
        }
        offset=5;
    }
    if (!params(w+offset, n-offset, all||diff?-1:a, key, p)) return;
    char note[200];
    notation(p, all||diff?-1:a, note);
    if (key>=0) {
        printf("SWEEP %s %s %lld %lld\n", algos[a], keys[key], lo, hi);
        I best=-1, bestv=lo;
        for (I v=lo; v<=hi; v++) {
            p[key]=v;
            Simulation *s=simulate(a, p,-1,0);
            char av[3][40], u[40], pn[200];
            averages(s, av, u);
            notation(p, a, pn);
            printf("%s turnaround=%s waiting=%s response=%s util=%s end=%d switches=%d\n", pn, av[0], av[1], av[2], u, s->end, s->switches);
            if (best<0||s->totals[1]<best) {
                best=s->totals[1];
                bestv=v;
            }
            free(s);
        }
        printf("BEST %s=%lld\n", keys[key], bestv);
        return;
    }
    if (diff) {
        Simulation *one=simulate(a, p,-1,0), *two=simulate(b, p,-1,0);
        printf("DIFF %s %s %s\n", algos[a], algos[b], note);
        int wins=0, losses=0, ties=0;
        for (int i=0; i<count; i++) {
            printf("%s turnaround=%lld/%lld waiting=%lld/%lld response=%lld/%lld\n", one->p[i].id, metric(one, i,0), metric(two, i,0), metric(one, i,1), metric(two, i,1), metric(one, i,2), metric(two, i,2));
            I x=metric(one, i,0), y=metric(two, i,0);
            wins+=x<y;
            losses+=x>y;
            ties+=x==y;
        }
        printf("WINS %s=%d %s=%d ties=%d\n", algos[a], wins, algos[b], losses, ties);
        free(one);
        free(two);
        return;
    }
    if (all) {
        I totals[9][3], values[9];
        char texts[9][40];
        if (m<0) {
            printf("COMPARE %s\n", note);
            printf("%-8s %8s %8s %8s %8s %8s %8s %8s\n","ALGO","TURN","WAIT","RESP","UTIL","END","SWITCH","MISS");
        } else printf("RANK %s %s\n", metrics[m], note);
        for (int algo=0; algo<9; algo++) {
            Simulation *s=simulate(algo, p,-1,0);
            memcpy(totals[algo], s->totals, sizeof s->totals);
            if (m<0) {
                char av[3][40], u[40];
                averages(s, av, u);
                printf("%-8s %8s %8s %8s %8s %8d %8d %8d\n", algos[algo], av[0], av[1], av[2], u, s->end, s->switches, s->missed);
            } else {
                values[algo]=rank_value(s, m);
                if (m<3)decimal(values[algo], count, texts[algo]);
                else sprintf(texts[algo],"%lld", values[algo]);
            }
            free(s);
        }
        if (m<0) {
            int best[3]={0};
            for (int k=0; k<3; k++) for (int algo=1; algo<9; algo++) if (totals[algo][k]<totals[best[k]][k])best[k]=algo;
            printf("BEST turnaround=%s waiting=%s response=%s\n", algos[best[0]], algos[best[1]], algos[best[2]]);
        } else {
            int ids[9];
            for (int i=0; i<9; i++) {
                int j=i;
                while (j&&values[ids[j-1]]>values[i]) {
                    ids[j]=ids[j-1];
                    j--;
                }
                ids[j]=i;
            }
            for (int k=0; k<9; k++) {
                int i=ids[k], rank=1;
                for (int j=0; j<9; j++)rank+=values[j]<values[i];
                printf("%d %s %s\n", rank, algos[i], texts[i]);
            }
        }
        return;
    }
    int trace=!strcmp(c,"TRACE");
    if (trace)printf("TRACE %s %s\n", algos[a], note);
    Simulation *s=simulate(a, p,!strcmp(c,"SNAPSHOT")?arg:-1, trace);
    simulation_output(c, a, p, s, arg);
    free(s);
}
static char *read_line(FILE *input) {
    size_t length=0, capacity=128;
    char *line=malloc(capacity);
    int character;
    while ((character=fgetc(input))!=EOF&&character!='\n') {
        if (length+1==capacity) {
            capacity*=2;
            line=realloc(line, capacity);
        }
        line[length++]=(char)character;
    }
    if (!length&&character==EOF) {
        free(line);
        return NULL;
    }
    line[length]=0;
    return line;
}

int main(void) {
    char *line=read_line(stdin);
    if (!line) return 0;
    int n=atoi(line);
    free(line);
    size_t capacity=32;
    char **words=malloc(capacity*sizeof *words);
    for (int i=0; i<n; i++) {
        line=read_line(stdin);
        if (!line)break;
        int nw=0;
        for (char *s=strtok(line," \r\n"); s; s=strtok(NULL," \r\n")) {
            if ((size_t)nw==capacity) {
                capacity*=2;
                words=realloc(words, capacity*sizeof *words);
            }
            words[nw++]=s;
        }
        command(words, nw);
        free(line);
    }
    free(words);
    return 0;
}
