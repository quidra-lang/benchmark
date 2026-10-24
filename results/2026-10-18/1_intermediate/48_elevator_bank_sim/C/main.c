#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
typedef long long I;
typedef struct {
    char *words[100];
    int count, number;
} Line;
typedef struct {
    int floors, cars, capacity, door, start[8], low[8], high[8], home[8], policy, park, patience, bypass, period, limit, compare[4], comparisons;
} Config;
typedef struct {
    int time, command, a, b, c;
} Event;
typedef struct {
    int time, a, b, count, waiting, car, boarded, delivered, lost, last_board, last_alight;
    unsigned cars;
    I wait_total, travel_total;
} Group;
typedef struct {
    int group, count, time;
} Passenger;
typedef struct {
    int floor, direction, door, in_service, idle_start, calls[1000], count;
    Passenger passengers[20];
    int riding;
    I distance, stops, boarded, busy, energy;
} Car;
typedef struct {
    Config config;
    Event *events;
    int ne, policy, time, end, aborted, last_round, fire, pending[1000], np, ng, logging;
    Group groups[1000];
    Car cars[8];
    I delivered, abandoned, evacuated, wait_total, travel_total, max_wait;
} Simulation;
typedef struct {
    char name[17];
    int valid, aborted, policy;
    I delivered, wait_total, travel_total, max_wait;
} Result;
static const char *policies[]={"COST","NEAREST","ROUND","ETA"};
static const char *keys[]={"FLOORS","CARS","CAPACITY","DOOR","START","POLICY","ZONES","PARK","PATIENCE","BYPASS","PERIOD","LIMIT","COMPARE"};
static const char *commands[]={"CALL","CANCEL","OUT","IN","HOLD","FIRE","RESET","WHERE","STATUS"};

static int lookup(const char *text, const char **names, int n) {
    for (int i=0; i<n; i++) if (!strcmp(text, names[i])) return i;
    return -1;
}

static int sign(int x) {
    return (x>0)-(x<0);
}

static int minimum(int a, int b) {
    return a<b?a:b;
}

static void average(I total, I count, char *out) {
    if (!count)strcpy(out,"-");
    else {
        I value=total*100/count;
        sprintf(out,"%lld.%02lld", value/100, value%100);
    }
}

static const char *optional(int value, char *out, const char *missing) {
    if (value<0) return missing;
    sprintf(out,"%d", value);
    return out;
}

static int in_range(int x, int low, int high) {
    return low<=x&&x<=high;
}

static int serves(Config *c, int car, int a, int b) {
    return in_range(a, c->low[car], c->high[car])&&in_range(b, c->low[car], c->high[car]);
}

static int configuration(Line *lines, int n, Config *c, char *error) {
    Line *found[13]={0};
    *c=(Config){.park=-1,.patience=-1,.bypass=100,.period=-1,.limit=1000};
    for (int i=0; i<n; i++) {
        int k=lookup(lines[i].words[0], keys,13);
        if (k<0) {
            sprintf(error,"unknown key %s", lines[i].words[0]);
            return 0;
        }
        if (found[k]) {
            sprintf(error,"duplicate key %s", keys[k]);
            return 0;
        }
        found[k]=&lines[i];
    }
    for (int k=0; k<5; k++) if (!found[k]) {
        sprintf(error,"missing key %s", keys[k]);
        return 0;
    }
    for (int k=0; k<13; k++) if (found[k]) {
        Line *line=found[k];
        int nv=line->count-1;
        int good_count=k==4||k==6?nv==c->cars:k==7?nv==c->cars+1:k==12?in_range(nv,1,4):nv==1;
        if (!good_count) {
            sprintf(error,"wrong number of values for %s", keys[k]);
            return 0;
        }
        int valid=1, v=(k==5||k==6||k==12)?0:atoi(line->words[1]);
        switch (k) {
            case 0:valid=in_range(v,2,50);
            c->floors=v;
            break;
            case 1:valid=in_range(v,1,8);
            c->cars=v;
            break;
            case 2:valid=in_range(v,1,20);
            c->capacity=v;
            break;
            case 3:valid=in_range(v,1,9);
            c->door=v;
            break;
            case 4:for (int i=0; i<c->cars; i++) {
                c->start[i]=atoi(line->words[i+1]);
                if (!in_range(c->start[i],1, c->floors))valid=0;
            }
            break;
            case 5:c->policy=lookup(line->words[1], policies,4);
            valid=c->policy>=0;
            break;
            case 6:for (int i=0; i<c->cars; i++) {
                sscanf(line->words[i+1],"%d:%d", &c->low[i], &c->high[i]);
                if (c->low[i]<1||c->low[i]>=c->high[i]||c->high[i]>c->floors)valid=0;
            }
            break;
            case 7:c->park=v;
            valid=in_range(v,0,100);
            for (int i=0; i<c->cars; i++) {
                c->home[i]=atoi(line->words[i+2]);
                if (!in_range(c->home[i],1, c->floors))valid=0;
            }
            break;
            case 8:c->patience=v;
            valid=in_range(v,1,1000);
            break;
            case 9:c->bypass=v;
            valid=in_range(v,50,100);
            break;
            case 10:c->period=v;
            valid=in_range(v,1,1000);
            break;
            case 11:c->limit=v;
            valid=in_range(v,1,5000);
            break;
            case 12:c->comparisons=nv;
            for (int i=0; i<nv; i++) {
                c->compare[i]=lookup(line->words[i+1], policies,4);
                if (c->compare[i]<0)valid=0;
                for (int j=0; j<i; j++) if (c->compare[j]==c->compare[i])valid=0;
            }
            break;
        }
        if (!valid) {
            sprintf(error,"bad value for %s", keys[k]);
            return 0;
        }
    }
    if (!found[6]) for (int i=0; i<c->cars; i++) {
        c->low[i]=1;
        c->high[i]=c->floors;
    }
    for (int i=0; i<c->cars; i++) {
        if (!in_range(c->start[i], c->low[i], c->high[i])) {
            sprintf(error,"car %d starts outside its zone", i+1);
            return 0;
        }
        if (c->park>=0&&!in_range(c->home[i], c->low[i], c->high[i])) {
            sprintf(error,"car %d home outside its zone", i+1);
            return 0;
        }
    }
    return 1;
}

static int validate_events(Line *lines, int n, Config *config, Event *events) {
    int last=0, groups=0, fire=0, out[8]={0}, count=0;
    static const int argc[]={3,1,1,1,2,1,0,1,0};
    for (int i=0; i<n; i++) {
        Line *line=&lines[i];
        int time=atoi(line->words[0]), command=lookup(line->words[1], commands,9);
        char error[300]="";
        int a=0, b=0, c=0;
        if (command<0)sprintf(error,"unknown command %s", line->words[1]);
        else if (line->count-2!=argc[command])sprintf(error,"wrong number of arguments for %s", commands[command]);
        else if (time<last)strcpy(error,"time goes backwards");
        else {
            if (argc[command]>0)a=atoi(line->words[2]);
            if (argc[command]>1)b=atoi(line->words[3]);
            if (argc[command]>2)c=atoi(line->words[4]);
            switch (command) {
                case 0:if (!in_range(a,1, config->floors)||!in_range(b,1, config->floors))strcpy(error,"bad floor");
                else if (a==b)strcpy(error,"same floor");
                else if (!in_range(c,1,99))strcpy(error,"bad count");
                else {
                    int served=0;
                    for (int e=0; e<config->cars; e++)served|=serves(config, e, a, b);
                    if (!served)sprintf(error,"no car serves %d->%d", a, b);
                    else if (fire)strcpy(error,"fire service active");
                }
                break;
                case 1:case 7:if (!in_range(a,1, groups))strcpy(error,"unknown group");
                break;
                case 2:case 3:if (!in_range(a,1, config->cars))strcpy(error,"bad car");
                else if (out[a-1]==(command==2))sprintf(error,"car %d already %s", a, command==2?"out":"in");
                break;
                case 4:if (!in_range(a,1, config->cars))strcpy(error,"bad car");
                else if (!in_range(b,1,9))strcpy(error,"bad ticks");
                break;
                case 5:if (!in_range(a,1, config->floors))strcpy(error,"bad floor");
                else if (fire)strcpy(error,"fire already active");
                break;
                case 6:if (!fire)strcpy(error,"fire not active");
                break;
            }
        }
        if (error[0]) {
            printf("line %d: %s\n", line->number, error);
            continue;
        }
        last=time;
        if (command==0)groups++;
        if (command==2||command==3)out[a-1]=command==2;
        if (command==5)fire=1;
        if (command==6)fire=0;
        events[count++]=(Event){time, command, a, b, c};
    }
    return count;
}

static void emit(Simulation *s, const char *format,...) {
    if (!s->logging) return;
    printf("%d ", s->time);
    va_list ap;
    va_start(ap, format);
    vprintf(format, ap);
    va_end(ap);
    puts("");
}

static void remove_id(int *list, int *n, int id) {
    for (int i=0; i<*n; i++) if (list[i]==id) {
        for (int j=i+1; j<*n; j++)list[j-1]=list[j];
        (*n)--;
        return;
    }
}

static int load(Car *car) {
    int result=0;
    for (int i=0; i<car->riding; i++)result+=car->passengers[i].count;
    return result;
}

static void targets(Simulation *s, int e, int *floors) {
    memset(floors,0,51*sizeof *floors);
    Car *car=&s->cars[e];
    for (int i=0; i<car->riding; i++)floors[s->groups[car->passengers[i].group].b]=1;
    for (int i=0; i<car->count; i++)floors[s->groups[car->calls[i]].a]=1;
}

static int cost(Simulation *s, int e, int g) {
    Car *car=&s->cars[e];
    Group *group=&s->groups[g];
    int f=car->floor, d=car->direction, x=group->a;
    if (s->policy==1||!d) return abs(f-x);
    int floors[51], distance, via=0;
    targets(s, e, floors);
    if (sign(group->b-group->a)==d&&(x-f)*d>=0) {
        distance=abs(x-f);
        for (int y=1; y<=s->config.floors; y++) if (floors[y]&&(y-f)*d>0&&(x-y)*d>0)via++;
    } else {
        int turn=f;
        for (int y=1; y<=s->config.floors; y++) if (floors[y]) {
            if ((y-turn)*d>0)turn=y;
            if ((y-f)*d>0)via++;
        }
        distance=abs(f-turn)+abs(turn-x);
    }
    return s->policy==3?distance+s->config.door*via+car->door:distance;
}

static int assign(Simulation *s, int g, int exclude) {
    int selected=-1, best=0;
    Group *group=&s->groups[g];
    for (int e=0; e<s->config.cars; e++) if (e!=exclude&&s->cars[e].in_service&&serves(&s->config, e, group->a, group->b)) {
        if (s->policy==2) {
            if (selected<0)selected=e;
            if (e+1>s->last_round) {
                selected=e;
                break;
            }
        } else {
            int value=cost(s, e, g);
            if (selected<0||value<best) {
                selected=e;
                best=value;
            }
        }
    }
    if (selected<0) return 0;
    if (s->policy==2) {
        s->last_round=selected+1;
        emit(s,"E%d ASSIGN G%d", selected+1, g+1);
    } else emit(s,"E%d ASSIGN G%d cost=%d", selected+1, g+1, best);
    if (group->car>=0)remove_id(s->cars[group->car].calls, &s->cars[group->car].count, g);
    Car *car=&s->cars[selected];
    car->calls[car->count++]=g;
    group->car=selected;
    return 1;
}

static void dispatch(Simulation *s, int g) {
    if (!assign(s, g,-1)) {
        s->pending[s->np++]=g;
        emit(s,"PENDING G%d", g+1);
    }
}

static void walk(Simulation *s, int g, const char *word) {
    Group *group=&s->groups[g];
    if (group->car>=0)remove_id(s->cars[group->car].calls, &s->cars[group->car].count, g);
    else remove_id(s->pending, &s->np, g);
    group->car=-1;
    emit(s,"%s G%d x%d", word, g+1, group->waiting);
    s->abandoned+=group->waiting;
    group->lost+=group->waiting;
    group->waiting=0;
}

static void append(char *out, const char *format,...) {
    va_list ap;
    va_start(ap, format);
    vsprintf(out+strlen(out), format, ap);
    va_end(ap);
}

static void list_groups(int *ids, int n, char *out) {
    out[0]=0;
    for (int i=0; i<n; i++)append(out,"%sG%d", i?",":"", ids[i]+1);
    if (!n)strcpy(out,"-");
}

static void perform(Simulation *s, Event event) {
    int a=event.a, b=event.b;
    switch (event.command) {
        case 0: {
            int g=s->ng++;
            s->groups[g]=(Group){.time=s->time,.a=a,.b=b,.count=event.c,.waiting=event.c,.car=-1};
            emit(s,"CALL G%d %d->%d x%d", g+1, a, b, event.c);
            dispatch(s, g);
            break;
        }
        case 1:if (s->groups[a-1].waiting)walk(s, a-1,"CANCEL");
        else emit(s,"CANCEL G%d ignored", a);
        break;
        case 2: {
            Car *car=&s->cars[a-1];
            car->in_service=0;
            emit(s,"E%d OUT", a);
            int calls[1000], n=car->count;
            memcpy(calls, car->calls,(size_t)n*sizeof *calls);
            car->count=0;
            for (int i=0; i<n; i++) {
                s->groups[calls[i]].car=-1;
                dispatch(s, calls[i]);
            }
            break;
        }
        case 3: {
            Car *car=&s->cars[a-1];
            car->in_service=1;
            car->idle_start=s->time;
            emit(s,"E%d IN", a);
            int pending[1000], n=s->np;
            memcpy(pending, s->pending,(size_t)n*sizeof *pending);
            s->np=0;
            for (int i=0; i<n; i++) if (!assign(s, pending[i],-1))s->pending[s->np++]=pending[i];
            break;
        }
        case 4:if (s->cars[a-1].door) {
            s->cars[a-1].door+=b;
            emit(s,"E%d HOLD %d", a, s->cars[a-1].door);
        } else emit(s,"E%d HOLD ignored", a);
        break;
        case 5:s->fire=a;
        emit(s,"FIRE %d", a);
        for (int g=0; g<s->ng; g++) if (s->groups[g].waiting)walk(s, g,"ABANDON");
        break;
        case 6:s->fire=0;
        emit(s,"RESET");
        for (int e=0; e<s->config.cars; e++)s->cars[e].idle_start=s->time;
        break;
        case 7: {
            Group *group=&s->groups[a-1];
            char place[30], riding[300]="";
            if (!group->waiting)strcpy(place,"-");
            else if (group->car<0)strcpy(place,"pending");
            else sprintf(place,"E%d", group->car+1);
            for (int e=0; e<s->config.cars; e++) {
                int people=0;
                for (int i=0; i<s->cars[e].riding; i++) if (s->cars[e].passengers[i].group==a-1)people+=s->cars[e].passengers[i].count;
                if (people)append(riding,"%sE%dx%d", riding[0]?",":"", e+1, people);
            }
            emit(s,"WHERE G%d waiting=%d car=%s riding=%s delivered=%d lost=%d", a, group->waiting, place, riding[0]?riding:"-", group->delivered, group->lost);
            break;
        }
        case 8:for (int e=0; e<s->config.cars; e++) {
            Car *car=&s->cars[e];
            char stops[200]="", calls[6000];
            int floors[51]={0};
            for (int i=0; i<car->riding; i++)floors[s->groups[car->passengers[i].group].b]=1;
            for (int f=1; f<=s->config.floors; f++) if (floors[f])append(stops,"%s%d", stops[0]?",":"", f);
            list_groups(car->calls, car->count, calls);
            emit(s,"STATUS E%d floor=%d dir=%s door=%d load=%d stops=%s calls=%s service=%s", e+1, car->floor, car->direction>0?"up":car->direction<0?"down":"idle", car->door, load(car), stops[0]?stops:"-", calls, car->in_service?"in":"out");
        }
        {
            char pending[6000];
            list_groups(s->pending, s->np, pending);
            emit(s,"STATUS pending=%s", pending);
        }
        break;
    }
}

static int bypassing(Simulation *s, int e) {
    return load(&s->cars[e])*100>=s->config.capacity*s->config.bypass;
}

static int direction(Simulation *s, int e) {
    Car *car=&s->cars[e];
    int f=car->floor, d=car->direction, floors[51], first=-1, same=0, ahead=0, behind=0;
    targets(s, e, floors);
    for (int y=1; y<=s->config.floors; y++) if (floors[y]) {
        ahead|=(y-f)*d>0;
        behind|=(y-f)*d<0;
    }
    if (!bypassing(s, e)) for (int i=0; i<car->count; i++) {
        Group *group=&s->groups[car->calls[i]];
        if (group->a==f) {
            if (first<0)first=car->calls[i];
            if (sign(group->b-group->a)==d)same=1;
        }
    }
    if (d&&(ahead||same)) return d;
    if (first>=0) return sign(s->groups[first].b-f);
    if (d&&behind) return -d;
    if (!d&&car->count) return sign(s->groups[car->calls[0]].a-f);
    return 0;
}

static void move(Simulation *s, int e, int step) {
    Car *car=&s->cars[e];
    car->energy+=step>0?3+load(car):1;
    car->distance++;
    car->floor+=step;
}

static void open_doors(Simulation *s, int e) {
    Car *car=&s->cars[e];
    emit(s,"E%d OPEN %d", e+1, car->floor);
    car->door=s->config.door;
    car->stops++;
    car->energy+=2;
    int kept=0;
    for (int i=0; i<car->riding; i++) {
        Passenger entry=car->passengers[i];
        Group *group=&s->groups[entry.group];
        if (group->b==car->floor) {
            emit(s,"E%d ALIGHT G%d x%d", e+1, entry.group+1, entry.count);
            int wait=entry.time-group->time, travel=s->time-group->time;
            group->delivered+=entry.count;
            group->last_alight=s->time;
            group->wait_total+=(I)wait*entry.count;
            group->travel_total+=(I)travel*entry.count;
            s->delivered+=entry.count;
            s->wait_total+=(I)wait*entry.count;
            s->travel_total+=(I)travel*entry.count;
            if (wait>s->max_wait)s->max_wait=wait;
        } else if (s->fire) {
            emit(s,"E%d EVACUATE G%d x%d", e+1, entry.group+1, entry.count);
            group->lost+=entry.count;
            s->evacuated+=entry.count;
        } else car->passengers[kept++]=entry;
    }
    car->riding=kept;
    if (s->fire) return;
    int heading=direction(s, e);
    if (heading)car->direction=heading;
    int boarding[1000], n=0;
    for (int i=0; i<car->count; i++) {
        int g=car->calls[i];
        Group *group=&s->groups[g];
        if (group->a==car->floor&&sign(group->b-group->a)==heading)boarding[n++]=g;
    }
    for (int i=0; i<n; i++) {
        int g=boarding[i];
        Group *group=&s->groups[g];
        int people=minimum(s->config.capacity-load(car), group->waiting);
        if (people) {
            car->passengers[car->riding++]=(Passenger){g, people, s->time};
            car->boarded+=people;
            group->waiting-=people;
            group->boarded+=people;
            group->last_board=s->time;
            group->cars|=1u<<e;
            emit(s,"E%d BOARD G%d x%d", e+1, g+1, people);
        }
        if (!group->waiting) {
            remove_id(car->calls, &car->count, g);
            group->car=-1;
        } else {
            emit(s,"E%d LEFT G%d x%d", e+1, g+1, group->waiting);
            assign(s, g, e);
        }
    }
}

static void advance(Simulation *s, int e) {
    Car *car=&s->cars[e];
    int old=car->floor;
    if (car->door)car->door--;
    if (!car->door) {
        int heading=s->fire?sign(s->fire-car->floor):direction(s, e), stop=0;
        if (s->fire)stop=!heading&&car->riding;
        else {
            for (int i=0; i<car->riding; i++) if (s->groups[car->passengers[i].group].b==car->floor)stop=1;
            if (!bypassing(s, e)) for (int i=0; i<car->count; i++) {
                Group *group=&s->groups[car->calls[i]];
                if (group->a==car->floor&&sign(group->b-group->a)==heading)stop=1;
            }
        }
        if (stop)open_doors(s, e);
        else if (heading) {
            car->direction=heading;
            move(s, e, heading);
        } else {
            if (car->direction) {
                emit(s,"E%d IDLE %d", e+1, car->floor);
                car->direction=0;
                car->idle_start=s->time;
            }
            if (!s->fire&&car->in_service&&s->config.park>=0&&car->floor!=s->config.home[e]&&s->time-car->idle_start>=s->config.park) {
                move(s, e, sign(s->config.home[e]-car->floor));
                if (car->floor==s->config.home[e])emit(s,"E%d PARK %d", e+1, car->floor);
            }
        }
    }
    if (car->door||car->floor!=old)car->busy++;
}

static int settled(Simulation *s, int e) {
    Car *car=&s->cars[e];
    if (car->door||car->riding||car->count) return 0;
    if (s->fire) return car->floor==s->fire;
    return !car->in_service||s->config.park<0||car->floor==s->config.home[e];
}

static Simulation *simulate(Config c, Event *events, int n, int policy, int logging) {
    Simulation *s=calloc(1, sizeof *s);
    s->config=c;
    s->events=events;
    s->ne=n;
    s->policy=policy;
    s->logging=logging;
    for (int e=0; e<c.cars; e++) {
        s->cars[e].floor=c.start[e];
        s->cars[e].in_service=1;
    }
    int next=0;
    for (s->time=0; ; s->time++) {
        if (c.patience>=0) for (int g=0; g<s->ng; g++) if (s->groups[g].waiting&&s->time==s->groups[g].time+c.patience)walk(s, g,"ABANDON");
        while (next<n&&events[next].time==s->time)perform(s, events[next++]);
        for (int e=0; e<c.cars; e++) advance(s, e);
        int all=1;
        for (int e=0; e<c.cars; e++) all&=settled(s, e);
        if (next==n&&all) {
            emit(s,"END");
            break;
        }
        if (s->time==c.limit) {
            s->aborted=1;
            emit(s,"ABORT");
            break;
        }
    }
    s->end=s->time;
    return s;
}

static void averages(Simulation *s, char *out) {
    char wait[40], travel[40], maxwait[40];
    average(s->wait_total, s->delivered, wait);
    average(s->travel_total, s->delivered, travel);
    if (s->delivered)sprintf(maxwait,"%lld", s->max_wait);
    else strcpy(maxwait,"-");
    sprintf(out,"avg_wait=%s avg_travel=%s max_wait=%s", wait, travel, maxwait);
}

static void breakdown(Simulation *s, int key, int period) {
    I passengers=0, delivered=0, wait=0;
    int groups=0;
    for (int g=0; g<s->ng; g++) {
        Group *group=&s->groups[g];
        if ((period?group->time/s->config.period:group->a)==key) {
            groups++;
            passengers+=group->count;
            delivered+=group->delivered;
            wait+=group->wait_total;
        }
    }
    if (!groups) return;
    char avg[40];
    average(wait, delivered, avg);
    if (period)printf("P%d %d-%d:", key, key*s->config.period, key*s->config.period+s->config.period-1);
    else printf("F%d:", key);
    printf(" groups=%d passengers=%lld delivered=%lld avg_wait=%s\n", groups, passengers, delivered, avg);
}

static void report(Simulation *s) {
    I passengers=0;
    for (int g=0; g<s->ng; g++) {
        Group *group=&s->groups[g];
        char cars[100]="", wait[40]="-", travel[40]="-";
        for (int e=0; e<s->config.cars; e++) if (group->cars&(1u<<e))append(cars,"%s%d", cars[0]?",":"", e+1);
        if (group->boarded==group->count)sprintf(wait,"%d", group->last_board-group->time);
        if (group->delivered==group->count)sprintf(travel,"%d", group->last_alight-group->time);
        printf("G%d t=%d %d->%d n=%d delivered=%d lost=%d wait=%s travel=%s cars=%s\n", g+1, group->time, group->a, group->b, group->count, group->delivered, group->lost, wait, travel, cars[0]?cars:"-");
        passengers+=group->count;
    }
    for (int e=0; e<s->config.cars; e++) {
        Car *car=&s->cars[e];
        I util=car->busy*1000/(s->end+1);
        printf("E%d distance=%lld stops=%lld boarded=%lld busy=%lld util=%lld.%lld%% energy=%lld\n", e+1, car->distance, car->stops, car->boarded, car->busy, util/10, util%10, car->energy);
    }
    for (int f=1; f<=s->config.floors; f++)breakdown(s, f,0);
    if (s->config.period>=0) for (int p=0; p<=10000/s->config.period; p++)breakdown(s, p,1);
    char av[200];
    averages(s, av);
    printf("summary: groups=%d passengers=%lld delivered=%lld abandoned=%lld evacuated=%lld %s end=%d\n", s->ng, passengers, s->delivered, s->abandoned, s->evacuated, av, s->end);
}

static int before(Result *a, Result *b) {
    I x=a->wait_total*b->delivered, y=b->wait_total*a->delivered;
    if (x!=y) return x<y;
    return a->travel_total*b->delivered<b->travel_total*a->delivered;
}
int main(void) {
    char buffer[512];
    if (!fgets(buffer, sizeof buffer, stdin)) return 0;
    int q=atoi(buffer), line_number=1;
    Result results[50]={0};
    for (int scenario=0; scenario<q; scenario++) {
        fgets(buffer, sizeof buffer, stdin);
        line_number++;
        sscanf(buffer,"SCENARIO %16s", results[scenario].name);
        Line settings[1000], event_lines[1000];
        int ns=0, nl=0;
        char *allocations[1000];
        int na=0;
        while (fgets(buffer, sizeof buffer, stdin)) {
            line_number++;
            buffer[strcspn(buffer,"\r\n")]=0;
            if (!strcmp(buffer,"END"))break;
            char *copy=malloc(strlen(buffer)+1);
            strcpy(copy, buffer);
            allocations[na++]=copy;
            Line line={.number=line_number};
            for (char *word=strtok(copy," "); word; word=strtok(NULL," "))line.words[line.count++]=word;
            if (line.words[0][0]>='0'&&line.words[0][0]<='9')event_lines[nl++]=line;
            else settings[ns++]=line;
        }
        printf("== %s ==\n", results[scenario].name);
        Config config;
        char error[300];
        if (!configuration(settings, ns, &config, error)) {
            printf("error: %s\n", error);
        } else {
            results[scenario].valid=1;
            results[scenario].policy=config.policy;
            char park[40], patience[40], period[40], compare[100]="";
            for (int i=0; i<config.comparisons; i++)append(compare,"%s%s", i?",":"", policies[config.compare[i]]);
            printf("config: floors=%d cars=%d capacity=%d door=%d policy=%s park=%s patience=%s bypass=%d period=%s limit=%d compare=%s\n", config.floors, config.cars, config.capacity, config.door, policies[config.policy], optional(config.park, park,"off"), optional(config.patience, patience,"off"), config.bypass, optional(config.period, period,"off"), config.limit, compare[0]?compare:"-");
            for (int e=0; e<config.cars; e++) {
                char home[40];
                printf("E%d: start=%d zone=%d-%d home=%s\n", e+1, config.start[e], config.low[e], config.high[e], config.park<0?"-":optional(config.home[e], home,"-"));
            }
            Event events[1000];
            int ne=validate_events(event_lines, nl, &config, events);
            Simulation *s=simulate(config, events, ne, config.policy,1);
            report(s);
            Result *r=&results[scenario];
            r->aborted=s->aborted;
            r->delivered=s->delivered;
            r->wait_total=s->wait_total;
            r->travel_total=s->travel_total;
            r->max_wait=s->max_wait;
            free(s);
            for (int i=0; i<config.comparisons; i++) {
                int policy=config.compare[i];
                Simulation *other=simulate(config, events, ne, policy,0);
                char av[200];
                averages(other, av);
                printf("compare %s: delivered=%lld %s end=%d status=%s\n", policies[policy], other->delivered, av, other->end, other->aborted?"abort":"end");
                free(other);
            }
        }
        for (int i=0; i<na; i++)free(allocations[i]);
    }
    puts("== ranking ==");
    int ranked[50], nr=0;
    for (int i=0; i<q; i++) if (results[i].valid&&!results[i].aborted&&results[i].delivered) {
        int j=nr;
        while (j&&before(&results[i], &results[ranked[j-1]])) {
            ranked[j]=ranked[j-1];
            j--;
        }
        ranked[j]=i;
        nr++;
    }
    for (int j=0; j<nr; j++) {
        Result *r=&results[ranked[j]];
        char wait[40], travel[40];
        average(r->wait_total, r->delivered, wait);
        average(r->travel_total, r->delivered, travel);
        printf("%d. %s policy=%s avg_wait=%s avg_travel=%s max_wait=%lld\n", j+1, r->name, policies[r->policy], wait, travel, r->max_wait);
    }
    for (int i=0; i<q; i++) if (!results[i].valid||results[i].aborted||!results[i].delivered)printf("- %s %s\n", results[i].name,!results[i].valid?"invalid":results[i].aborted?"aborted":"empty");
    puts("== policies ==");
    for (int p=0; p<4; p++) {
        int runs=0;
        I delivered=0, wait=0, travel=0;
        for (int j=0; j<nr; j++) {
            Result *r=&results[ranked[j]];
            if (r->policy==p) {
                runs++;
                delivered+=r->delivered;
                wait+=r->wait_total;
                travel+=r->travel_total;
            }
        }
        if (runs) {
            char w[40], t[40];
            average(wait, delivered, w);
            average(travel, delivered, t);
            printf("%s: runs=%d avg_wait=%s avg_travel=%s\n", policies[p], runs, w, t);
        }
    }
    return 0;
}
