#include "mrp.h"
#include <errno.h>
#include <sys/stat.h>

enum { MPS,CUSTOMER_ORDER,DEPENDENT,SAFETY };
enum { STOCK,RECEIPT,PLANNED };
typedef struct { int item,kind,week,parent,parent_number,inquiry,line; int64_t quantity; } Demand;
typedef struct { int item,number,receipt,original,release; int64_t quantity; } PlannedOrder;
typedef struct { Demand *demand; int64_t share; } Allocation;
typedef struct Supply {
    int kind,week,line; int64_t quantity,remaining; PlannedOrder *order;
    Allocation *allocations; int allocation_count,allocation_capacity;
    Demand **roots; int root_count,root_capacity;
} Supply;
typedef struct {
    Demand *demands; int demand_count,demand_capacity;
    int64_t gross[27],on_hand[27],net[27],pr[27],pl[27],past_due;
    PlannedOrder orders[26]; int order_count;
    Supply *supplies; int supply_count; Supply *order_supplies[26];
} ItemPlan;
typedef struct { ItemPlan items[100]; int64_t loads[20][27],overloads[20][27]; } Plan;
typedef struct { int inquiry,week,material; char *reason; } Promise;
static const Model *sort_model;

static int64_t sum(const int64_t *values,int count) { int64_t total=0; for (int i=0;i<count;i++) total+=values[i]; return total; }
static char *depth_label(int depth) { char *periods=allocate((size_t)depth+1); memset(periods,'.',(size_t)depth); return format("%s%d",periods,depth); }
static void extend(Strings *target,Strings source) { for (int i=0;i<source.count;i++) add_string(target,source.data[i]); }
static char *schedule_error(const Model *model,int item,const char *id,int week,int64_t quantity) { if (item<0) return format("unknown item %s",id); if (week<1 || week>model->horizon) return format("week %d outside horizon",week); if (quantity<1) return format("bad quantity %" PRId64,quantity); return NULL; }
static void read_schedule(Model *model,const char *name,bool unique) {
    Strings lines=read_lines(name); ScheduleRow *rows=unique ? model->mps : model->receipts; int *count=unique ? &model->mps_count : &model->receipt_count;
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char **f=fields.data; int item=find_item(model,f[0]),week=(int)integer(f[1]); int64_t quantity=integer(f[2]); char *message=schedule_error(model,item,f[0],week,quantity);
        if (!message && unique) for (int j=0;j<*count;j++) if (rows[j].item==item && rows[j].week==week) { message=format("duplicate %s week %d",f[0],week); break; }
        if (message) record_error(model,name,i+1,message); else rows[(*count)++]=(ScheduleRow){item,week,i+1,quantity};
    }
}
static Model *load_model(void) {
    Model *model=allocate(sizeof(*model)); Strings params=read_lines("params.txt"),peg={0};
    for (int i=0;i<params.count;i++) { Strings words=split(params.data[i],' '); if (!strcmp(words.data[0],"horizon")) model->horizon=(int)integer(words.data[1]); else if (!strcmp(words.data[0],"tree_quantity")) model->tree_quantity=integer(words.data[1]); else peg=(Strings){words.data+1,words.count-1,0}; }
    read_items(model); read_bom(model); read_centers(model); read_routings(model); read_schedule(model,"mps.csv",true); read_schedule(model,"receipts.csv",false);
    Strings lines=read_lines("orders.csv");
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char **f=fields.data,*message=NULL; int item=find_item(model,f[1]),week=(int)integer(f[3]); int64_t quantity=integer(f[2]); for (int j=0;j<model->inquiry_count;j++) if (!strcmp(model->inquiries[j].id,f[0])) { message=format("duplicate order %s",f[0]); break; } if (!message) message=schedule_error(model,item,f[1],week,quantity); if (message) record_error(model,"orders.csv",i+1,message); else { Inquiry *q=&model->inquiries[model->inquiry_count++]; strcpy(q->id,f[0]); q->item=item; q->week=week; q->quantity=quantity; q->line=i+1; } }
    compute_structure(model); model->peg_count=peg.count; for (int i=0;i<peg.count;i++) model->peg[i]=find_item(model,peg.data[i]);
    for (int i=1;i<model->receipt_count;i++) { ScheduleRow row=model->receipts[i]; int j=i; while (j>0 && (model->receipts[j-1].week>row.week || (model->receipts[j-1].week==row.week && model->receipts[j-1].line>row.line))) { model->receipts[j]=model->receipts[j-1]; j--; } model->receipts[j]=row; }
    for (int i=0;i<model->receipt_count;i++) model->scheduled[model->receipts[i].item][model->receipts[i].week]+=model->receipts[i].quantity;
    sort_model=model; return model;
}
static void add_demand(ItemPlan *plan,Demand demand) { if (plan->demand_count==plan->demand_capacity) { plan->demand_capacity=plan->demand_capacity ? plan->demand_capacity*2 : 16; plan->demands=resize(plan->demands,(size_t)plan->demand_capacity*sizeof(*plan->demands)); } plan->demands[plan->demand_count++]=demand; }
static Plan *run_mrp(const Model *model,const Demand *promised,int promised_count,const Demand *extra) {
    Plan *plan=allocate(sizeof(*plan));
    for (int i=0;i<model->mps_count;i++) { ScheduleRow row=model->mps[i]; add_demand(&plan->items[row.item],(Demand){.item=row.item,.kind=MPS,.week=row.week,.line=row.line,.inquiry=-1,.quantity=row.quantity}); }
    for (int i=0;i<promised_count;i++) add_demand(&plan->items[promised[i].item],promised[i]); if (extra) add_demand(&plan->items[extra->item],*extra);
    for (int k=0;k<model->item_count;k++) {
        int index=model->order[k]; const Item *item=&model->items[index]; ItemPlan *p=&plan->items[index];
        for (int i=0;i<p->demand_count;i++) p->gross[p->demands[i].week]+=p->demands[i].quantity;
        int64_t projected=item->on_hand;
        for (int week=1;week<=model->horizon;week++) { int64_t available=projected+model->scheduled[index][week]-p->gross[week]; projected=available; if (available<item->safety) { int64_t quantity=lot_size(item,week,available,model->scheduled[index],p->gross,model->horizon); int original=week-item->lead,release=original<1 ? 1 : original; p->orders[p->order_count]=(PlannedOrder){index,p->order_count+1,week,original,release,quantity}; p->order_count++; p->net[week]=item->safety-available; p->pr[week]=quantity; p->pl[release]+=quantity; projected=available+quantity; if (original<1) p->past_due+=quantity; } p->on_hand[week]=projected; }
        for (int i=0;i<p->order_count;i++) for (int j=0;j<item->child_count;j++) { const Link *link=&model->links[item->children[j]]; add_demand(&plan->items[link->child],(Demand){.item=link->child,.kind=DEPENDENT,.week=p->orders[i].release,.parent=index,.parent_number=p->orders[i].number,.inquiry=-1,.quantity=need(link,p->orders[i].quantity)}); }
        for (int i=0;i<p->order_count;i++) for (int j=0;j<item->operation_count;j++) { const Operation *operation=&model->operations[item->operations[j]]; int week=operation_week(p->orders[i].receipt,item->lead,j,item->operation_count); plan->loads[operation->center][week]+=operation->setup+p->orders[i].quantity*operation->run; }
    }
    for (int i=0;i<model->center_count;i++) for (int week=1;week<=model->horizon;week++) { int64_t overload=plan->loads[i][week]-model->centers[i].available; plan->overloads[i][week]=overload>0 ? overload : 0; } return plan;
}
static void free_plan(Plan *plan,int item_count) { for (int i=0;i<item_count;i++) free(plan->items[i].demands); free(plan); }
static Plan *promise_inquiries(const Model *model,Plan *base,Promise *promises) {
    Plan *current=base; Demand promised[50]; int promised_count=0;
    for (int i=0;i<model->inquiry_count;i++) {
        Inquiry inquiry=model->inquiries[i]; Promise *promise=&promises[i]; promise->inquiry=i; promise->reason="";
        for (int week=inquiry.week;week<=model->horizon;week++) {
            Demand demand={.item=inquiry.item,.kind=CUSTOMER_ORDER,.week=week,.inquiry=i,.line=inquiry.line,.quantity=inquiry.quantity}; Plan *trial=run_mrp(model,promised,promised_count,&demand); char *reason=NULL;
            for (int j=0;j<model->item_count;j++) { int item=model->order[j]; if (trial->items[item].past_due>current->items[item].past_due) { reason=(char *)model->items[item].id; break; } }
            if (!reason) { if (!promise->material) promise->material=week; for (int j=0;j<model->center_count && !reason;j++) { int center=model->center_order[j]; for (int w=1;w<=model->horizon;w++) if (trial->overloads[center][w]>current->overloads[center][w]) { reason=format("%s week %d",model->centers[center].id,w); break; } } }
            if (!reason) { promise->week=week; promised[promised_count++]=demand; if (current!=base) free_plan(current,model->item_count); current=trial; break; }
            if (week==inquiry.week) promise->reason=reason; free_plan(trial,model->item_count);
        }
    }
    return current;
}
static int compare_demands(const void *left,const void *right) { const Demand *a=left,*b=right; if (a->week!=b->week) return a->week-b->week; if (a->kind!=b->kind) return a->kind-b->kind; if (a->kind==CUSTOMER_ORDER) return a->line-b->line; if (a->kind==DEPENDENT) { int order=strcmp(sort_model->items[a->parent].id,sort_model->items[b->parent].id); return order ? order : a->parent_number-b->parent_number; } return 0; }
static int compare_supplies(const void *left,const void *right) { const Supply *a=left,*b=right; if (a->week!=b->week) return a->week-b->week; if (a->kind!=b->kind) return a->kind-b->kind; return a->line-b->line; }
static int compare_roots(const void *left,const void *right) { const Demand *a=*(Demand *const *)left,*b=*(Demand *const *)right; int order=strcmp(sort_model->items[a->item].id,sort_model->items[b->item].id); if (order) return order; if (a->kind!=b->kind) return a->kind-b->kind; if (a->week!=b->week) return a->week-b->week; return a->kind==CUSTOMER_ORDER ? strcmp(sort_model->inquiries[a->inquiry].id,sort_model->inquiries[b->inquiry].id) : 0; }
static Supply *parent_supply(Plan *plan,const Demand *demand) { return plan->items[demand->parent].order_supplies[demand->parent_number-1]; }
static void add_root(Supply *supply,Demand *root) { for (int i=0;i<supply->root_count;i++) { Demand *old=supply->roots[i]; if (old->item==root->item && old->kind==root->kind && old->week==root->week && (root->kind!=CUSTOMER_ORDER || old->inquiry==root->inquiry)) return; } if (supply->root_count==supply->root_capacity) { supply->root_capacity=supply->root_capacity ? supply->root_capacity*2 : 8; supply->roots=resize(supply->roots,(size_t)supply->root_capacity*sizeof(*supply->roots)); } supply->roots[supply->root_count++]=root; }
static void peg_plan(const Model *model,Plan *plan) {
    for (int k=0;k<model->item_count;k++) {
        int index=model->order[k]; const Item *item=&model->items[index]; ItemPlan *p=&plan->items[index]; if (item->safety) add_demand(p,(Demand){.item=index,.kind=SAFETY,.inquiry=-1,.quantity=item->safety}); if (p->demand_count>1) qsort(p->demands,(size_t)p->demand_count,sizeof(*p->demands),compare_demands);
        int count=(item->on_hand>0 ? 1 : 0)+p->order_count; for (int i=0;i<model->receipt_count;i++) if (model->receipts[i].item==index) count++; p->supplies=allocate((size_t)count*sizeof(*p->supplies));
        if (item->on_hand) p->supplies[p->supply_count++]=(Supply){.kind=STOCK,.quantity=item->on_hand,.remaining=item->on_hand};
        for (int i=0;i<model->receipt_count;i++) { ScheduleRow row=model->receipts[i]; if (row.item==index) p->supplies[p->supply_count++]=(Supply){.kind=RECEIPT,.week=row.week,.line=row.line,.quantity=row.quantity,.remaining=row.quantity}; }
        for (int i=0;i<p->order_count;i++) p->supplies[p->supply_count++]=(Supply){.kind=PLANNED,.week=p->orders[i].receipt,.quantity=p->orders[i].quantity,.remaining=p->orders[i].quantity,.order=&p->orders[i]};
        if (count>1) qsort(p->supplies,(size_t)count,sizeof(*p->supplies),compare_supplies); for (int i=0;i<count;i++) if (p->supplies[i].kind==PLANNED) p->order_supplies[p->supplies[i].order->number-1]=&p->supplies[i];
        int s=0; for (int i=0;i<p->demand_count;i++) { Demand *demand=&p->demands[i]; int64_t remaining=demand->quantity; while (remaining) { while (!p->supplies[s].remaining) s++; Supply *supply=&p->supplies[s]; int64_t share=remaining<supply->remaining ? remaining : supply->remaining; if (supply->allocation_count==supply->allocation_capacity) { supply->allocation_capacity=supply->allocation_capacity ? supply->allocation_capacity*2 : 8; supply->allocations=resize(supply->allocations,(size_t)supply->allocation_capacity*sizeof(*supply->allocations)); } supply->allocations[supply->allocation_count++]=(Allocation){demand,share}; supply->remaining-=share; remaining-=share; } }
        for (int i=0;i<p->order_count;i++) { Supply *supply=p->order_supplies[i]; for (int j=0;j<supply->allocation_count;j++) { Demand *demand=supply->allocations[j].demand; if (demand->kind==DEPENDENT) { Supply *parent=parent_supply(plan,demand); for (int r=0;r<parent->root_count;r++) add_root(supply,parent->roots[r]); } else add_root(supply,demand); } if (supply->root_count>1) qsort(supply->roots,(size_t)supply->root_count,sizeof(*supply->roots),compare_roots); }
    }
}
static char *demand_text(const Model *model,const Demand *demand) { const char *id=model->items[demand->item].id; if (demand->kind==SAFETY) return format("SAFETY %s",id); if (demand->kind==MPS) return format("MPS %s week %d",id,demand->week); if (demand->kind==CUSTOMER_ORDER) return format("ORDER %s %s week %d",model->inquiries[demand->inquiry].id,id,demand->week); return format("%s order %d week %d",model->items[demand->parent].id,demand->parent_number,demand->week); }
static Strings grid_lines(const Model *model,const Plan *plan) {
    Strings lines={0}; int64_t weeks[26]; for (int i=0;i<model->horizon;i++) weeks[i]=i+1;
    for (int k=0;k<model->item_count;k++) { int index=model->order[k]; const Item *item=&model->items[index]; const ItemPlan *p=&plan->items[index]; add_string(&lines,format("ITEM %s LLC %d LT %d LOT %s SS %" PRId64 " OH %" PRId64 " %s",item->id,item->code,item->lead,lot_label(item),item->safety,item->on_hand,item->description)); const char *labels[]={"WEEK","GROSS","RECEIPTS","ON_HAND","NET","PLAN_RCPT","PLAN_REL"}; const int64_t *values[]={weeks,p->gross+1,model->scheduled[index]+1,p->on_hand+1,p->net+1,p->pr+1,p->pl+1}; for (int i=0;i<7;i++) add_string(&lines,table_row(labels[i],values[i],model->horizon,6)); add_string(&lines,format("TOTAL gross %" PRId64 " receipts %" PRId64 " planned %" PRId64 " orders %d ending %" PRId64,sum(p->gross,27),sum(model->scheduled[index],27),sum(p->pr,27),p->order_count,p->on_hand[model->horizon])); } return lines;
}
static void where_used(const Model *model,int index,int depth,int64_t extension,Strings *lines) { const Item *item=&model->items[index]; for (int i=0;i<item->parent_count;i++) { const Link *link=&model->links[item->parents[i]]; int64_t ext=extension*link->quantity; add_string(lines,format("%s %s qty %" PRId64 " ext %" PRId64,depth_label(depth),model->items[link->parent].id,link->quantity,ext)); where_used(model,link->parent,depth+1,ext,lines); } }
static void allocation_lines(const Model *model,Plan *plan,const Supply *supply,int depth,Strings *lines) { for (int i=0;i<supply->allocation_count;i++) { Allocation allocation=supply->allocations[i]; add_string(lines,format("%*sALLOC %" PRId64 " %s",2*depth,"",allocation.share,demand_text(model,allocation.demand))); if (supply->kind==PLANNED && allocation.demand->kind==DEPENDENT) allocation_lines(model,plan,parent_supply(plan,allocation.demand),depth+1,lines); } }
static Strings pegging_lines(const Model *model,Plan *plan) {
    Strings lines={0}; for (int k=0;k<model->peg_count;k++) { int index=model->peg[k]; ItemPlan *p=&plan->items[index]; add_string(&lines,format("PEG %s orders %d",model->items[index].id,p->order_count)); where_used(model,index,1,1,&lines); for (int kind=STOCK;kind<=PLANNED;kind++) for (int i=0;i<p->supply_count;i++) { Supply *supply=&p->supplies[i]; if (supply->kind!=kind) continue; if (kind==STOCK) add_string(&lines,format("STOCK quantity %" PRId64,supply->quantity)); else if (kind==RECEIPT) add_string(&lines,format("RECEIPT line %d week %d quantity %" PRId64,supply->line,supply->week,supply->quantity)); else { PlannedOrder *order=supply->order; add_string(&lines,format("ORDER %d receipt %d release %d quantity %" PRId64,order->number,order->receipt,order->release,order->quantity)); } allocation_lines(model,plan,supply,1,&lines); if (supply->remaining) add_string(&lines,format("  EXCESS %" PRId64,supply->remaining)); for (int j=0;j<supply->root_count;j++) add_string(&lines,format("  ROOT %s",demand_text(model,supply->roots[j]))); } } return lines;
}
static void explosion(const Model *model,int index,int64_t gross,int64_t extension,int depth,int64_t *totals,Strings *lines) { const Item *item=&model->items[index]; for (int i=0;i<item->child_count;i++) { const Link *link=&model->links[item->children[i]]; const Item *child=&model->items[link->child]; int64_t ext=extension*link->quantity,quantity=need(link,gross); totals[link->child]+=quantity; add_string(lines,format("%s %s qty %" PRId64 " scrap %" PRId64 " ext %" PRId64 " gross %" PRId64 " lt %d cum %d %s",depth_label(depth),child->id,link->quantity,link->scrap,ext,quantity,child->lead,child->cumulative,child->description)); explosion(model,link->child,quantity,ext,depth+1,totals,lines); } }
static Strings tree_lines(const Model *model) { Strings lines={0}; for (int k=0;k<model->item_count;k++) { int index=model->item_order[k]; const Item *item=&model->items[index]; if (!item->child_count || item->parent_count) continue; add_string(&lines,format("TREE %s quantity %" PRId64,item->id,model->tree_quantity)); add_string(&lines,format("0 %s ext 1 gross %" PRId64 " lt %d cum %d %s",item->id,model->tree_quantity,item->lead,item->cumulative,item->description)); int64_t totals[100]={0}; explosion(model,index,model->tree_quantity,1,1,totals,&lines); for (int j=0;j<model->item_count;j++) { int child=model->item_order[j]; if (totals[child]) add_string(&lines,format("SUM %s %" PRId64,model->items[child].id,totals[child])); } Strings path={0}; add_string(&path,item->id); int current=index; while (model->items[current].child_count) { const Item *parent=&model->items[current]; int chosen=model->links[parent->children[0]].child; for (int i=1;i<parent->child_count;i++) { int child=model->links[parent->children[i]].child; if (model->items[child].cumulative>model->items[chosen].cumulative) chosen=child; } current=chosen; add_string(&path,model->items[current].id); } add_string(&lines,format("CRITICAL %s cum %d",join(path," -> "),item->cumulative)); } return lines; }

static Strings cost_lines(Model *model,const Plan *plan) { for (int i=0;i<model->item_count;i++) { model->items[i].usage=sum(plan->items[i].gross,27); model->items[i].value=model->items[i].usage*model->items[i].standard_total; } abc_classes(model); Strings lines={0}; add_string(&lines,"item,material,labor,total,usage,value,class"); for (int k=0;k<model->item_count;k++) { const Item *item=&model->items[model->item_order[k]]; add_string(&lines,format("%s,%s,%s,%s,%" PRId64 ",%s,%c",item->id,money(item->standard_material),money(item->standard_labor),money(item->standard_total),item->usage,money(item->value),item->abc)); } return lines; }
static void message(Strings *lines,int *counts,int kind,const char *text) { add_string(lines,text); counts[kind]++; }
static Strings exception_lines(const Model *model,const Plan *plan) {
    static const char *const kinds[]={"below_safety","past_due","release","expedite","defer","cancel","no_routing","no_demand","overload"}; Strings lines={0}; int counts[9]={0}; for (int i=0;i<model->errors.count;i++) add_string(&lines,format("ERROR %s",model->errors.data[i]));
    for (int k=0;k<model->item_count;k++) {
        int index=model->order[k]; const Item *item=&model->items[index]; const ItemPlan *p=&plan->items[index];
        if (item->on_hand<item->safety) message(&lines,counts,0,format("BELOW_SAFETY %s on hand %" PRId64 " safety %" PRId64,item->id,item->on_hand,item->safety));
        for (int i=0;i<p->order_count;i++) { const PlannedOrder *order=&p->orders[i]; if (order->original<1) message(&lines,counts,1,format("PAST_DUE %s order %d receipt %d release %d late %d quantity %" PRId64,item->id,order->number,order->receipt,order->original,1-order->original,order->quantity)); else if (order->original==1) message(&lines,counts,2,format("RELEASE %s order %d receipt %d quantity %" PRId64,item->id,order->number,order->receipt,order->quantity)); }
        int64_t balances[27]={0},balance=item->on_hand,covered=0; for (int week=1;week<=model->horizon;week++) { balance-=p->gross[week]; balances[week]=balance; }
        for (int i=0;i<model->receipt_count;i++) { ScheduleRow receipt=model->receipts[i]; if (receipt.item!=index) continue; int need_week=0; for (int week=1;week<=model->horizon;week++) if (balances[week]+covered<item->safety) { need_week=week; break; } char *text=format("%s receipt line %d week %d quantity %" PRId64,item->id,receipt.line,receipt.week,receipt.quantity); if (!need_week) message(&lines,counts,5,format("CANCEL %s",text)); else if (need_week<receipt.week) message(&lines,counts,3,format("EXPEDITE %s to %d",text,need_week)); else if (need_week>receipt.week) message(&lines,counts,4,format("DEFER %s to %d",text,need_week)); covered+=receipt.quantity; }
        if (item->child_count && !item->operation_count) message(&lines,counts,6,format("NO_ROUTING %s",item->id)); if (!sum(p->gross,27) && item->on_hand) message(&lines,counts,7,format("NO_DEMAND %s on hand %" PRId64,item->id,item->on_hand));
    }
    for (int k=0;k<model->center_count;k++) { int index=model->center_order[k]; for (int week=1;week<=model->horizon;week++) if (plan->overloads[index][week]) message(&lines,counts,8,format("OVERLOAD %s week %d load %" PRId64 " available %" PRId64,model->centers[index].id,week,plan->loads[index][week],model->centers[index].available)); }
    Text summary={0}; append_text(&summary,format("SUMMARY errors %d",model->errors.count)); for (int i=0;i<9;i++) append_text(&summary,format(" %s %d",kinds[i],counts[i])); add_string(&lines,summary.data); return lines;
}
static Strings capacity_lines(const Model *model,const Plan *plan) {
    Strings lines={0}; int64_t totals[20]={0},weeks[26]; for (int i=0;i<model->horizon;i++) weeks[i]=i+1;
    for (int k=0;k<model->center_count;k++) {
        int index=model->center_order[k]; const WorkCenter *center=&model->centers[index]; const int64_t *loads=plan->loads[index],*overloads=plan->overloads[index]; int64_t leveled[27]={0},utilization[27]={0}; level_loads(loads,center->available,model->horizon,leveled); int64_t total=sum(loads,27); totals[index]=total; int overloaded=0,peak=0;
        for (int week=1;week<=model->horizon;week++) { utilization[week]=percentage(loads[week],center->available); if (overloads[week]) overloaded++; if (total && (!peak || loads[week]>loads[peak])) peak=week; }
        add_string(&lines,format("CENTER %s minutes %" PRId64 " efficiency %" PRId64 " available %" PRId64 " %s",center->id,center->minutes,center->efficiency,center->available,center->description)); const char *labels[]={"WEEK","LOAD","UTIL","OVER","LEVELED"}; const int64_t *values[]={weeks,loads+1,utilization+1,overloads+1,leveled+1}; for (int i=0;i<5;i++) add_string(&lines,table_row(labels[i],values[i],model->horizon,7)); int64_t backlog=leveled[1]-center->available; if (backlog<0) backlog=0;
        add_string(&lines,format("TOTAL load %" PRId64 " available %" PRId64 " utilization %" PRId64 " overloaded %d peak %d backlog %" PRId64,total,center->available*model->horizon,percentage(total,center->available*model->horizon),overloaded,peak,backlog));
    }
    int order[20]; for (int i=0;i<model->center_count;i++) { int index=model->center_order[i],j=i; while (j>0) { int before=order[j-1]; int64_t left=totals[before]*model->centers[index].available,right=totals[index]*model->centers[before].available; if (left>right || (left==right && strcmp(model->centers[before].id,model->centers[index].id)<=0)) break; order[j]=before; j--; } order[j]=index; }
    for (int i=0;i<model->center_count;i++) { int index=order[i]; add_string(&lines,format("RANK %d %s load %" PRId64 " utilization %" PRId64,i+1,model->centers[index].id,totals[index],percentage(totals[index],model->centers[index].available*model->horizon))); } return lines;
}
static Strings promise_lines(const Model *model,const Promise *promises,const Plan *base,const Plan *final) {
    Strings lines={0}; int on_time=0,late=0,rejected=0;
    for (int i=0;i<model->inquiry_count;i++) {
        const Promise *promise=&promises[i]; Inquiry inquiry=model->inquiries[i]; const char *item=model->items[inquiry.item].id; char *head=format("ORDER %s %s quantity %" PRId64 " requested %d",inquiry.id,item,inquiry.quantity,inquiry.week); char *material=promise->material ? format("%d",promise->material) : "none";
        if (!promise->week) { rejected++; add_string(&lines,format("%s rejected material %s reason %s",head,material,promise->reason)); continue; } if (promise->week==inquiry.week) { on_time++; add_string(&lines,format("%s promised %d",head,promise->week)); } else { late++; add_string(&lines,format("%s promised %d late %d material %s reason %s",head,promise->week,promise->week-inquiry.week,material,promise->reason)); }
        for (int k=0;k<model->item_count;k++) { int index=model->order[k]; const ItemPlan *p=&final->items[index]; for (int j=0;j<p->order_count;j++) { const Supply *supply=p->order_supplies[j]; bool serves=false; for (int r=0;r<supply->root_count;r++) if (supply->roots[r]->kind==CUSTOMER_ORDER && supply->roots[r]->inquiry==i) serves=true; if (serves) { PlannedOrder *order=supply->order; add_string(&lines,format("  SUPPLY %s order %d receipt %d release %d quantity %" PRId64,model->items[index].id,order->number,order->receipt,order->release,order->quantity)); } } }
    }
    for (int k=0;k<model->item_count;k++) { int index=model->order[k]; const ItemPlan *before=&base->items[index],*after=&final->items[index]; for (int week=1;week<=model->horizon;week++) if (before->pr[week]!=after->pr[week]) { add_string(&lines,format("CHANGE %s from %d planned %" PRId64 " -> %" PRId64 " orders %d -> %d",model->items[index].id,week,sum(before->pr,27),sum(after->pr,27),before->order_count,after->order_count)); break; } }
    add_string(&lines,format("SUMMARY orders %d on_time %d late %d rejected %d",model->inquiry_count,on_time,late,rejected)); return lines;
}
static int compare_release_orders(const void *left,const void *right) { const PlannedOrder *a=*(PlannedOrder *const *)left,*b=*(PlannedOrder *const *)right; if (a->original!=b->original) return a->original-b->original; int order=strcmp(sort_model->items[a->item].id,sort_model->items[b->item].id); return order ? order : a->number-b->number; }
static Strings release_lines(const Model *model,Plan *plan) {
    PlannedOrder *orders[2600]; int count=0; int64_t available[100]; for (int i=0;i<model->item_count;i++) { available[i]=model->items[i].on_hand+model->scheduled[i][1]; for (int j=0;j<plan->items[i].order_count;j++) if (plan->items[i].orders[j].release==1) orders[count++]=&plan->items[i].orders[j]; } if (count>1) qsort(orders,(size_t)count,sizeof(*orders),compare_release_orders);
    Strings lines={0}; int made=0,ready_count=0,bought=0; int64_t purchase_total=0;
    for (int i=0;i<count;i++) { PlannedOrder *order=orders[i]; const Item *item=&model->items[order->item]; char *lateness=order->original<1 ? format(" late %d",1-order->original) : ""; char *head=format("%s order %d receipt %d quantity %" PRId64 "%s",item->id,order->number,order->receipt,order->quantity,lateness);
        if (!item->child_count) { int64_t value=order->quantity*item->material; bought++; purchase_total+=value; add_string(&lines,format("BUY %s value %s",head,money(value))); continue; }
        Strings detail={0}; bool ready=true; int64_t needs[100];
        for (int j=0;j<item->child_count;j++) { const Link *link=&model->links[item->children[j]]; int64_t quantity=need(link,order->quantity),have=available[link->child],shortage=quantity>have ? quantity-have : 0; needs[j]=quantity; if (quantity>have) ready=false; add_string(&detail,format("  PICK %s need %" PRId64 " available %" PRId64 " short %" PRId64,model->items[link->child].id,quantity,have,shortage)); }
        if (ready) { ready_count++; for (int j=0;j<item->child_count;j++) available[model->links[item->children[j]].child]-=needs[j]; }
        for (int j=0;j<item->operation_count;j++) { const Operation *operation=&model->operations[item->operations[j]]; add_string(&detail,format("  OPERATION %d %s week %d minutes %" PRId64,operation->number,model->centers[operation->center].id,operation_week(order->receipt,item->lead,j,item->operation_count),operation->setup+order->quantity*operation->run)); }
        made++; add_string(&lines,format("MAKE %s %s",head,ready ? "READY" : "SHORT")); extend(&lines,detail);
    }
    add_string(&lines,format("SUMMARY make %d ready %d short %d buy %d value %s",made,ready_count,made-ready_count,bought,money(purchase_total))); return lines;
}
static Strings value_lines(const Model *model,const Plan *plan) { Strings lines={0}; add_string(&lines,"week,inventory,purchases,labor"); for (int week=1;week<=model->horizon;week++) { int64_t inventory=0,purchases=0,labor=0; for (int k=0;k<model->item_count;k++) { int index=model->order[k]; const Item *item=&model->items[index]; const ItemPlan *p=&plan->items[index]; inventory+=p->on_hand[week]*item->standard_total; if (item->child_count) labor+=p->pl[week]*item->labor; else purchases+=p->pl[week]*item->material; } add_string(&lines,format("%d,%s,%s,%s",week,money(inventory),money(purchases),money(labor))); } return lines; }
int main(void) {
    Model *model=load_model(); Plan *base=run_mrp(model,NULL,0,NULL); Promise promises[50]={0}; Plan *final=promise_inquiries(model,base,promises); peg_plan(model,final); standard_costs(model);
    if (mkdir("output",0777) && errno!=EEXIST) return EXIT_FAILURE;
    write_report("mrp_grid.txt",grid_lines(model,final)); write_report("pegging.txt",pegging_lines(model,final)); write_report("bom_tree.txt",tree_lines(model)); write_report("cost_rollup.csv",cost_lines(model,final)); write_report("exceptions.txt",exception_lines(model,final)); write_report("capacity.txt",capacity_lines(model,final)); write_report("promises.txt",promise_lines(model,promises,base,final)); write_report("releases.txt",release_lines(model,final)); write_report("value_plan.csv",value_lines(model,final)); return EXIT_SUCCESS;
}
