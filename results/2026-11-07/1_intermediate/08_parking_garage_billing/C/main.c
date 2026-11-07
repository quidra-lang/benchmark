#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *types[] = {"MOTORCYCLE","CAR","ECAR","VAN","BUS"};
static const char *kinds[] = {"MOTO","COMPACT","LARGE","EV"};
static const int preferences[5][3] = {{0,1,2},{1,2,-1},{3,1,2},{2,-1,-1},{2,-1,-1}};
static const int preference_counts[] = {3,2,3,1,1};
typedef struct { int level, number, kind, vehicle; bool closed; } Spot;
typedef struct {
    char plate[9];
    int type, spot, entry, energy, charge, validation;
    bool active, paid;
    int payment, parking, night;
} Vehicle;
typedef struct { char plate[9]; int type, joined; } Waiting;
typedef struct { int parking, night, lost, charge, total, due; } Bill;
typedef struct { char plate[9], location[24]; int entry, exit, type, total; bool lost; } Record;
typedef struct { char plate[9]; int last; } Pass;
typedef struct { int entries, exits, refused, revenue, stay; } Counts;
typedef struct { int exits, parking, night, lost, charge, total; } Revenue;
typedef struct Temp { struct Temp *next; char data[]; } Temp;
static Temp *temps;
static Spot spots[1080];
static int spot_count, level_count, starts[9], sizes[9];
static Vehicle vehicles[1000];
static Waiting queue[3];
static Record records[1000];
static Pass passes[1000];
static int vehicle_count, queue_count, record_count, pass_count, parked_count;
static int now, peak, peak_time;
static int rates[5] = {100,200,200,300,600}, caps[5] = {800,1600,1600,2400,4800}, fees[3] = {300,2000,30};
static Counts totals[5], daily[1000][5];
static Revenue revenue[5];

static char *format(const char *pattern, ...) {
    va_list args, measure;
    va_start(args,pattern);
    va_copy(measure,args);
    int length = vsnprintf(NULL,0,pattern,measure);
    va_end(measure);
    if (length < 0) exit(EXIT_FAILURE);
    Temp *t = malloc(sizeof(*t)+(size_t)length+1);
    if (!t) exit(EXIT_FAILURE);
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
static char *time_text(int t) { return format("%d-%02d:%02d",t/1440+1,t%1440/60,t%60); }
static char *duration(int t) { return format("%d:%02d",t/60,t%60); }
static char *tenth(int q) { return format("%d.%d",q/10,q%10); }
static int lookup(const char *const *names, int count, const char *s) {
    for (int i = 0; i < count; ++i) if (!strcmp(names[i],s)) return i;
    return -1;
}
static char *label(int s) { return format("L%d-%d",spots[s].level,spots[s].number); }
static char *location(const Vehicle *v) {
    return v->type == 4 ? format("%s..%d",label(v->spot),spots[v->spot].number+2) : label(v->spot);
}
static bool free_spot(int s) { return !spots[s].closed && spots[s].vehicle < 0; }
static int pass_id(const char *p) {
    for (int i = 0; i < pass_count; ++i) if (!strcmp(passes[i].plate,p)) return i;
    return -1;
}
static bool valid_pass(const char *p) {
    int i = pass_id(p);
    return i >= 0 && now/1440+1 <= passes[i].last;
}
static int spot_id(const char *s) {
    int level, number;
    sscanf(s,"L%d-%d",&level,&number);
    if (level > level_count || number > sizes[level-1]) return -1;
    return starts[level-1]+number-1;
}
static int parked(const char *plate) {
    for (int i = 0; i < vehicle_count; ++i) if (vehicles[i].active && !strcmp(vehicles[i].plate,plate)) return i;
    return -1;
}
static int vehicle(const char *plate) {
    int i = parked(plate);
    error(i < 0,format("%s is not parked",plate));
    return i;
}
static int waiting(const char *plate) {
    for (int i = 0; i < queue_count; ++i) if (!strcmp(queue[i].plate,plate)) return i;
    return -1;
}
static int preference(int type, int kind) {
    for (int i = 0; i < preference_counts[type]; ++i) if (preferences[type][i] == kind) return i;
    return -1;
}
static int assign(int type) {
    if (type == 4) {
        for (int l = 0; l < level_count; ++l) {
            for (int j = 0; j+2 < sizes[l]; ++j) {
                int s = starts[l]+j;
                if (spots[s].kind == 2 && spots[s+1].kind == 2 && spots[s+2].kind == 2 && free_spot(s) && free_spot(s+1) && free_spot(s+2)) return s;
            }
        }
    } else {
        for (int k = 0; k < preference_counts[type]; ++k) {
            for (int i = 0; i < spot_count; ++i) if (spots[i].kind == preferences[type][k] && free_spot(i)) return i;
        }
    }
    return -1;
}
static void occupy(int id, int s) {
    Vehicle *v = &vehicles[id];
    v->spot = s;
    for (int i = 0; i < (v->type == 4 ? 3 : 1); ++i) spots[s+i].vehicle = id;
}
static void vacate(int id) {
    Vehicle *v = &vehicles[id];
    for (int i = 0; i < (v->type == 4 ? 3 : 1); ++i) spots[v->spot+i].vehicle = -1;
}
static int park(const char *plate, int type, int s) {
    int id = vehicle_count++;
    Vehicle *v = &vehicles[id];
    strcpy(v->plate,plate);
    v->type = type;
    v->entry = now;
    v->active = true;
    occupy(id,s);
    ++parked_count;
    ++totals[type].entries;
    ++daily[now/1440+1][type].entries;
    if (parked_count > peak) {
        peak = parked_count;
        peak_time = now;
    }
    return id;
}
static void refuse(int type, int time) {
    ++totals[type].refused;
    ++daily[time/1440+1][type].refused;
}
static void giveups(void) {
    int length = 0;
    for (int i = 0; i < queue_count; ++i) {
        Waiting w = queue[i];
        if (now-w.joined >= 30) {
            line("GIVEUP %s %s %s",w.plate,types[w.type],time_text(w.joined+30));
            refuse(w.type,w.joined+30);
        } else queue[length++] = w;
    }
    queue_count = length;
}
static void process_queue(void) {
    int length = 0;
    for (int i = 0; i < queue_count; ++i) {
        Waiting w = queue[i];
        int s = assign(w.type);
        if (s < 0) queue[length++] = w;
        else {
            int id = park(w.plate,w.type,s);
            line("ADMIT %s %s %s waited %s",w.plate,types[w.type],location(&vehicles[id]),duration(now-w.joined));
        }
    }
    queue_count = length;
}
static void interval(const Vehicle *v, int from, int free_time, int *parking, int *night) {
    int length = now-from;
    *parking = 0;
    *night = 0;
    if (valid_pass(v->plate) || length <= free_time) return;
    for (int i = 0; i*1440 < length; ++i) {
        int minutes = length-i*1440;
        if (minutes > 1440) minutes = 1440;
        if (!i) minutes -= free_time;
        int amount = (minutes+29)/30*rates[v->type];
        *parking += amount < caps[v->type] ? amount : caps[v->type];
    }
    *night = (now/1440-from/1440)*fees[0];
}
static Bill bill(const Vehicle *v, bool loss) {
    int p, n;
    interval(v,v->paid ? v->payment : v->entry,v->paid ? 15 : 15+v->validation,&p,&n);
    int due = p+n;
    p += v->paid ? v->parking : 0;
    n += v->paid ? v->night : 0;
    int lost = loss ? fees[1] : 0;
    int total = p+n+lost+v->charge;
    return (Bill){p,n,lost,v->charge,total,v->paid ? due : total};
}
static void fee_line(const char *heading, const Vehicle *v, Bill b) {
    line("%s %s %s stay %s parking %d night %d lost %d charge %d total %d due %d",heading,v->plate,location(v),duration(now-v->entry),b.parking,b.night,b.lost,b.charge,b.total,b.due);
}
static char *annotation(const Vehicle *v) {
    char *s = valid_pass(v->plate) ? " PASS" : "";
    if (v->validation) s = format("%s VAL %d",s,v->validation);
    if (v->energy) s = format("%s KWH %d",s,v->energy);
    return v->paid ? format("%s PAID",s) : s;
}
static int location_order(const void *left, const void *right) {
    int a = vehicles[*(const int *)left].spot, b = vehicles[*(const int *)right].spot;
    return a < b ? -1 : a > b ? 1 : 0;
}
static int entry_order(const void *left, const void *right) {
    int a = vehicles[*(const int *)left].entry, b = vehicles[*(const int *)right].entry;
    return a != b ? (a < b ? -1 : 1) : location_order(left,right);
}
static int ordered_vehicles(int *ids) {
    int length = 0;
    for (int i = 0; i < vehicle_count; ++i) if (vehicles[i].active) ids[length++] = i;
    qsort(ids,(size_t)length,sizeof(*ids),location_order);
    return length;
}
static void move_vehicle(int id, int s) {
    char *before = location(&vehicles[id]);
    vacate(id);
    occupy(id,s);
    line("MOVE %s %s -> %s",vehicles[id].plate,before,label(s));
}
static int pass_order(const void *left, const void *right) {
    return strcmp(passes[*(const int *)left].plate,passes[*(const int *)right].plate);
}
static Counts add_counts(Counts a, Counts b) {
    return (Counts){a.entries+b.entries,a.exits+b.exits,a.refused+b.refused,a.revenue+b.revenue,a.stay+b.stay};
}
static void execute(char **a, int count) {
    const char *cmd = a[0];
    if (!strcmp(cmd,"LEVEL")) {
        int level = level_count++, start = spot_count;
        starts[level] = start;
        for (int k = 0; k < 4; ++k) {
            int added = atoi(a[k+1]);
            for (int i = 0; i < added; ++i) {
                spots[spot_count] = (Spot){level+1,spot_count-start+1,k,-1,false};
                ++spot_count;
            }
        }
        sizes[level] = spot_count-start;
        line("LEVEL %d spots %d MOTO %s COMPACT %s LARGE %s EV %s",level+1,sizes[level],a[1],a[2],a[3],a[4]);
        process_queue();
    } else if (!strcmp(cmd,"CLOSE") || !strcmp(cmd,"OPEN")) {
        int s = spot_id(a[1]);
        if (error(s < 0,format("unknown spot %s",a[1]))) return;
        Spot *p = &spots[s];
        if (!strcmp(cmd,"CLOSE")) {
            if (error(p->closed,format("spot %s is already closed",a[1]))) return;
            if (error(p->vehicle >= 0,format("spot %s is occupied by %s",a[1],p->vehicle >= 0 ? vehicles[p->vehicle].plate : ""))) return;
            p->closed = true;
        } else {
            if (error(!p->closed,format("spot %s is not closed",a[1]))) return;
            p->closed = false;
        }
        line("%s %s %s",cmd,a[1],kinds[p->kind]);
        if (!strcmp(cmd,"OPEN")) process_queue();
    } else if (!strcmp(cmd,"RATE")) {
        int type = lookup(types,5,a[1]);
        if (error(type < 0,format("unknown type %s",a[1]))) return;
        int rate = atoi(a[2]), cap = atoi(a[3]);
        if (error(cap < rate,format("cap below rate for %s",a[1]))) return;
        rates[type] = rate;
        caps[type] = cap;
        line("RATE %s %d %d",a[1],rate,cap);
    } else if (!strcmp(cmd,"FEE")) {
        const char *items[] = {"NIGHT","LOST","KWH"};
        int item = lookup(items,3,a[1]);
        if (error(item < 0,format("unknown fee %s",a[1]))) return;
        fees[item] = atoi(a[2]);
        line("FEE %s %s",a[1],a[2]);
    } else if (!strcmp(cmd,"ENTER")) {
        int type = lookup(types,5,a[2]);
        if (error(type < 0,format("unknown type %s",a[2]))) return;
        int previous = parked(a[1]);
        if (error(previous >= 0,format("%s is already parked at %s",a[1],previous >= 0 ? location(&vehicles[previous]) : ""))) return;
        if (error(waiting(a[1]) >= 0,format("%s is already waiting",a[1]))) return;
        int s = assign(type);
        if (s >= 0) {
            int id = park(a[1],type,s);
            line("ENTER %s %s %s",a[1],a[2],location(&vehicles[id]));
        } else if (queue_count < 3) {
            Waiting *w = &queue[queue_count++];
            strcpy(w->plate,a[1]);
            w->type = type;
            w->joined = now;
            line("WAIT %s %s %d",a[1],a[2],queue_count);
        } else {
            refuse(type,now);
            line("FULL %s %s",a[1],a[2]);
        }
    } else if (!strcmp(cmd,"LEAVE")) {
        int i = waiting(a[1]);
        if (error(i < 0,format("%s is not waiting",a[1]))) return;
        line("LEAVE %s %s",a[1],types[queue[i].type]);
        memmove(queue+i,queue+i+1,(size_t)(queue_count-i-1)*sizeof(*queue));
        --queue_count;
    } else if (!strcmp(cmd,"EXIT") || !strcmp(cmd,"PAY") || !strcmp(cmd,"QUOTE") || !strcmp(cmd,"CHARGE") || !strcmp(cmd,"VALIDATE") || !strcmp(cmd,"MOVE")) {
        int id = vehicle(a[1]);
        if (id < 0) return;
        Vehicle *v = &vehicles[id];
        if (!strcmp(cmd,"EXIT")) {
            bool loss = count == 3;
            if (error(loss && v->paid,format("%s has already paid",a[1]))) return;
            Bill b = bill(v,loss);
            fee_line("EXIT",v,b);
            Record *r = &records[record_count++];
            strcpy(r->plate,v->plate);
            strcpy(r->location,location(v));
            r->entry = v->entry;
            r->exit = now;
            r->type = v->type;
            r->total = b.total;
            r->lost = loss;
            ++totals[v->type].exits;
            totals[v->type].stay += now-v->entry;
            totals[v->type].revenue += b.total;
            ++daily[now/1440+1][v->type].exits;
            daily[now/1440+1][v->type].revenue += b.total;
            Revenue *sum = &revenue[v->type];
            ++sum->exits;
            sum->parking += b.parking;
            sum->night += b.night;
            sum->lost += b.lost;
            sum->charge += b.charge;
            sum->total += b.total;
            vacate(id);
            v->active = false;
            --parked_count;
            process_queue();
        } else if (!strcmp(cmd,"QUOTE")) fee_line("QUOTE",v,bill(v,false));
        else if (!strcmp(cmd,"PAY")) {
            if (error(v->paid,format("%s has already paid",a[1]))) return;
            Bill b = bill(v,false);
            v->paid = true;
            v->payment = now;
            v->parking = b.parking;
            v->night = b.night;
            line("PAY %s parking %d night %d charge %d total %d",v->plate,b.parking,b.night,b.charge,b.total);
        } else if (!strcmp(cmd,"CHARGE")) {
            if (error(v->type != 2,format("%s is not an electric car",a[1])) || error(spots[v->spot].kind != 3,format("%s is not at a charger",a[1])) || error(v->paid,format("%s has already paid",a[1]))) return;
            int energy = atoi(a[2]);
            if (error(v->energy+energy > 100,format("charge limit exceeded for %s",a[1]))) return;
            int cost = energy*fees[2];
            v->energy += energy;
            v->charge += cost;
            line("CHARGE %s kwh %d cost %d stay_kwh %d stay_cost %d",v->plate,energy,cost,v->energy,v->charge);
        } else if (!strcmp(cmd,"VALIDATE")) {
            if (error(v->paid,format("%s has already paid",a[1]))) return;
            int minutes = atoi(a[2]);
            if (error(v->validation+minutes > 180,format("validation limit exceeded for %s",a[1]))) return;
            v->validation += minutes;
            line("VALIDATE %s %d total %d",v->plate,minutes,v->validation);
        } else {
            if (error(v->type == 4,format("bus %s cannot be moved",a[1]))) return;
            int s = spot_id(a[2]);
            if (error(s < 0,format("unknown spot %s",a[2])) || error(s == v->spot,format("%s is already at %s",a[1],a[2]))) return;
            if (error(spots[s].closed,format("spot %s is closed",a[2]))) return;
            if (error(spots[s].vehicle >= 0,format("spot %s is occupied by %s",a[2],spots[s].vehicle >= 0 ? vehicles[spots[s].vehicle].plate : ""))) return;
            if (error(preference(v->type,spots[s].kind) < 0,format("%s cannot use %s spot %s",types[v->type],kinds[spots[s].kind],a[2]))) return;
            move_vehicle(id,s);
            process_queue();
        }
    } else if (!strcmp(cmd,"PASS")) {
        int i = pass_id(a[1]), days = atoi(a[2]);
        bool valid = i >= 0 && now/1440+1 <= passes[i].last;
        if (i < 0) {
            i = pass_count++;
            strcpy(passes[i].plate,a[1]);
        }
        passes[i].last = valid ? passes[i].last+days : now/1440+days;
        line("PASS %s until %d",a[1],passes[i].last);
    } else if (!strcmp(cmd,"UNPASS")) {
        if (error(!valid_pass(a[1]),format("%s has no pass",a[1]))) return;
        passes[pass_id(a[1])].last = 0;
        line("UNPASS %s",a[1]);
    } else if (!strcmp(cmd,"REBALANCE")) {
        int ids[1000], count_ids = ordered_vehicles(ids), moved = 0;
        for (int j = 0; j < count_ids; ++j) {
            int id = ids[j];
            Vehicle *v = &vehicles[id];
            if (v->type == 4) continue;
            int current = preference(v->type,spots[v->spot].kind);
            if (!current) continue;
            int s = assign(v->type);
            if (s >= 0 && preference(v->type,spots[s].kind) < current) {
                move_vehicle(id,s);
                ++moved;
            }
        }
        line("REBALANCE %d",moved);
        process_queue();
    } else if (!strcmp(cmd,"WHERE")) {
        int id = parked(a[1]), q = waiting(a[1]), last = -1;
        if (id >= 0) {
            Vehicle *v = &vehicles[id];
            line("WHERE %s %s %s %s stay %s%s",a[1],location(v),types[v->type],time_text(v->entry),duration(now-v->entry),annotation(v));
        } else if (q >= 0) line("WHERE %s waiting %d",a[1],q+1);
        else {
            for (int i = 0; i < record_count; ++i) if (!strcmp(records[i].plate,a[1])) last = i;
            if (last >= 0) line("WHERE %s gone %s",a[1],time_text(records[last].exit));
            else error(true,format("unknown plate %s",a[1]));
        }
    } else if (!strcmp(cmd,"LIST") || !strcmp(cmd,"OVERSTAY")) {
        int level = !strcmp(cmd,"LIST") && count == 2 ? atoi(a[1]) : 0;
        if (error(level > level_count,format("unknown level %d",level))) return;
        int ids[1000], all_count = ordered_vehicles(ids), length = 0;
        for (int i = 0; i < all_count; ++i) {
            Vehicle *v = &vehicles[ids[i]];
            if (level && spots[v->spot].level != level) continue;
            if (!strcmp(cmd,"OVERSTAY") && now-v->entry < atoi(a[1])*60) continue;
            ids[length++] = ids[i];
        }
        if (!strcmp(cmd,"OVERSTAY")) {
            qsort(ids,(size_t)length,sizeof(*ids),entry_order);
            line("OVERSTAY %s %d",a[1],length);
        } else line("LIST %d",length);
        for (int i = 0; i < length; ++i) {
            Vehicle *v = &vehicles[ids[i]];
            line("%s %s %s %s%s",location(v),v->plate,types[v->type],time_text(v->entry),!strcmp(cmd,"LIST") ? annotation(v) : format(" stay %s",duration(now-v->entry)));
        }
    } else if (!strcmp(cmd,"MAP")) {
        line("MAP %d",level_count);
        for (int l = 0; l < level_count; ++l) {
            char symbols[140];
            int length = 0;
            for (int j = 0; j < sizes[l]; ++j) {
                if (j && j%10 == 0) symbols[length++] = ' ';
                Spot s = spots[starts[l]+j];
                symbols[length++] = s.closed ? '#' : (s.vehicle >= 0 ? "MCLE" : "mcle")[s.kind];
            }
            symbols[length] = '\0';
            line("L%d %s",l+1,symbols);
        }
    } else if (!strcmp(cmd,"OCCUPANCY")) {
        line("OCCUPANCY vehicles %d waiting %d",parked_count,queue_count);
        int all_used[4] = {0}, all_available[4] = {0}, all_closed = 0;
        for (int l = 0; l < level_count; ++l) {
            int used[4] = {0}, available[4] = {0}, closed = 0;
            for (int j = 0; j < sizes[l]; ++j) {
                Spot s = spots[starts[l]+j];
                if (s.closed) ++closed;
                else ++available[s.kind];
                if (s.vehicle >= 0) ++used[s.kind];
            }
            printf("L%d",l+1);
            for (int k = 0; k < 4; ++k) {
                printf(" %s %d/%d",kinds[k],used[k],available[k]);
                all_used[k] += used[k];
                all_available[k] += available[k];
            }
            all_closed += closed;
            line(" closed %d",closed);
        }
        printf("TOTAL");
        int used = 0, available = 0;
        for (int k = 0; k < 4; ++k) {
            printf(" %s %d/%d",kinds[k],all_used[k],all_available[k]);
            used += all_used[k];
            available += all_available[k];
        }
        line(" closed %d rate %s%%",all_closed,tenth(available ? used*1000/available : 0));
    } else if (!strcmp(cmd,"SIGN")) {
        int free_counts[4] = {0}, buses = 0;
        for (int l = 0; l < level_count; ++l) {
            int run = 0;
            for (int j = 0; j < sizes[l]; ++j) {
                int s = starts[l]+j;
                if (free_spot(s)) ++free_counts[spots[s].kind];
                if (free_spot(s) && spots[s].kind == 2) ++run;
                else {
                    buses += run/3;
                    run = 0;
                }
            }
            buses += run/3;
        }
        printf("SIGN");
        for (int k = 0; k < 5; ++k) {
            int count = buses;
            if (k != 4) {
                count = 0;
                for (int i = 0; i < preference_counts[k]; ++i) count += free_counts[preferences[k][i]];
            }
            printf(" %s %s",types[k],count ? format("%d",count) : "FULL");
        }
        putchar('\n');
    } else if (!strcmp(cmd,"RATES")) {
        line("RATES");
        for (int k = 0; k < 5; ++k) line("%s %d %d",types[k],rates[k],caps[k]);
        line("NIGHT %d LOST %d KWH %d",fees[0],fees[1],fees[2]);
    } else if (!strcmp(cmd,"PASSES")) {
        int ids[1000], length = 0;
        for (int i = 0; i < pass_count; ++i) if (now/1440+1 <= passes[i].last) ids[length++] = i;
        qsort(ids,(size_t)length,sizeof(*ids),pass_order);
        line("PASSES %d",length);
        for (int j = 0; j < length; ++j) {
            Pass p = passes[ids[j]];
            line("%s until %d%s",p.plate,p.last,parked(p.plate) >= 0 ? " IN" : "");
        }
    } else if (!strcmp(cmd,"HISTORY")) {
        int length = 0, total = 0;
        for (int i = 0; i < record_count; ++i) {
            if (!strcmp(records[i].plate,a[1])) {
                ++length;
                total += records[i].total;
            }
        }
        if (error(!length,format("no history for %s",a[1]))) return;
        line("HISTORY %s visits %d paid %d",a[1],length,total);
        for (int i = 0; i < record_count; ++i) {
            Record r = records[i];
            if (!strcmp(r.plate,a[1])) line("%s %s %s %s %d%s",time_text(r.entry),time_text(r.exit),r.location,types[r.type],r.total,r.lost ? " LOST" : "");
        }
    } else if (!strcmp(cmd,"REVENUE")) {
        line("REVENUE");
        Revenue all = {0};
        for (int k = 0; k <= 5; ++k) {
            Revenue r = k == 5 ? all : revenue[k];
            line("%s exits %d parking %d night %d lost %d charge %d total %d",k == 5 ? "TOTAL" : types[k],r.exits,r.parking,r.night,r.lost,r.charge,r.total);
            if (k < 5) {
                all.exits += r.exits;
                all.parking += r.parking;
                all.night += r.night;
                all.lost += r.lost;
                all.charge += r.charge;
                all.total += r.total;
            }
        }
    } else if (!strcmp(cmd,"DAILY") || !strcmp(cmd,"STATS")) {
        bool by_day = !strcmp(cmd,"DAILY");
        Counts *rows = by_day ? daily[atoi(a[1])] : totals;
        Counts all = {0};
        for (int k = 0; k < 5; ++k) all = add_counts(all,rows[k]);
        if (by_day) line("DAILY %s entries %d exits %d refused %d revenue %d",a[1],all.entries,all.exits,all.refused,all.revenue);
        else line("STATS parked %d peak %d at %s",parked_count,peak,peak ? time_text(peak_time) : "-");
        for (int k = 0; k < (by_day ? 5 : 6); ++k) {
            Counts c = k == 5 ? all : rows[k];
            const char *name = k == 5 ? "ALL" : types[k];
            if (by_day) line("%s entries %d exits %d refused %d revenue %d",name,c.entries,c.exits,c.refused,c.revenue);
            else line("%s entries %d exits %d refused %d avg_stay %s",name,c.entries,c.exits,c.refused,tenth(c.exits ? c.stay*10/c.exits : 0));
        }
    }
}
int main(void) {
    char input[256];
    if (!fgets(input,sizeof(input),stdin)) return 0;
    int count = atoi(input);
    for (int i = 0; i < count; ++i) {
        if (!fgets(input,sizeof(input),stdin)) break;
        input[strcspn(input,"\n")] = '\0';
        char *a[12];
        int length = 0;
        for (char *word = strtok(input," "); word; word = strtok(NULL," ")) a[length++] = word;
        int hour, minute;
        sscanf(a[1],"%d:%d",&hour,&minute);
        now = (atoi(a[0])-1)*1440+hour*60+minute;
        giveups();
        execute(a+2,length-2);
        clear_temps();
    }
    return 0;
}
