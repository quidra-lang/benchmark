#include "finance.h"
#include <stdarg.h>
#include <errno.h>
#include <sys/stat.h>

typedef struct { char *date; int64_t amount; } OptionValue;
typedef struct { OptionValue *data; int count,capacity; } OptionValues;
typedef struct { int day; int64_t amount; } DatedAmount;
typedef struct { bool eom,long_stub; int lag; int64_t cap,floor; OptionValues sinks,calls; } Options;
typedef struct { int number,start,end,payment; Fraction fraction; int64_t rate,opening,coupon,principal,cash; } Period;
typedef struct { char *code,*kind,*daycount,*bdc; int issue,maturity,frequency; int64_t coupon,face; Options options; Schedule schedule; DatedAmount *sinks,*calls; int sink_count,call_count; Period *periods; int period_count; } Bond;
typedef struct { Bond *bond; int64_t clean,outstanding,accrued_amount,clean_amount,unit_value; int first,workout,next_payment; double accrued,target,fraction,ytm,ytw,wal,curve_clean,zspread; YieldPricer pricer; Risk risk; Flows flows; } Valuation;
typedef struct { int day; int64_t rate; } Fixing;
typedef struct { char *name; double shifts[30]; } Scenario;
typedef struct { int line; char *name; Strings shifts; } RawScenario;
typedef struct { int valuation,settlement_days; RawScenario scenarios[40]; int scenario_count; Strings limits[40]; int limit_count; } Params;
typedef struct { char *portfolio; Valuation *value; int64_t units,book; } Position;
typedef struct { int count; int64_t value; double duration,dv01; } Exposure;
typedef struct { int64_t coupon,principal; bool used; } YearTotals;
typedef struct { char *name; double values[300],pnls[300],total,pnl; } ScenarioResult;
static const char *const bond_types[]={"FIXED","ZERO","AMORT","FRN"};
static const char *const day_counts[]={"30/360","30E/360","ACT/360","ACT/365F","ACT/ACT"};
static const char *const business_rules[]={"FOLLOWING","MODIFIED_FOLLOWING","PRECEDING","UNADJUSTED"};
static const char *const bucket_names[]={"0-1Y","1-3Y","3-5Y","5-10Y","10Y+"};

void *allocate(size_t size) { void *result=calloc(1,size ? size : 1); if (!result) exit(EXIT_FAILURE); return result; }
void *resize(void *pointer,size_t size) { void *result=realloc(pointer,size ? size : 1); if (!result) exit(EXIT_FAILURE); return result; }
char *copy_text(const char *text) { char *result=allocate(strlen(text)+1); strcpy(result,text); return result; }
char *format(const char *pattern,...) { va_list args,copy; va_start(args,pattern); va_copy(copy,args); int length=vsnprintf(NULL,0,pattern,args); va_end(args); char *result=allocate((size_t)length+1); vsnprintf(result,(size_t)length+1,pattern,copy); va_end(copy); return result; }
void append_text(Text *text,const char *part) { size_t length=strlen(part),needed=text->length+length+1; if (needed>text->capacity) { size_t capacity=text->capacity ? text->capacity : 64; while (capacity<needed) capacity*=2; text->data=resize(text->data,capacity); text->capacity=capacity; } memcpy(text->data+text->length,part,length+1); text->length+=length; }
void add_string(Strings *strings,const char *text) { if (strings->count==strings->capacity) { strings->capacity=strings->capacity ? strings->capacity*2 : 8; strings->data=resize(strings->data,(size_t)strings->capacity*sizeof(*strings->data)); } strings->data[strings->count++]=copy_text(text); }
Strings split(const char *text,char separator) { Strings result={0}; const char *start=text; for (const char *p=text;;p++) if (*p==separator || !*p) { char *part=allocate((size_t)(p-start)+1); memcpy(part,start,(size_t)(p-start)); add_string(&result,part); if (!*p) break; start=p+1; } return result; }
char *join(Strings strings,const char *separator) { Text result={0}; for (int i=0;i<strings.count;i++) { if (i) append_text(&result,separator); append_text(&result,strings.data[i]); } return result.data ? result.data : copy_text(""); }
Strings read_lines(const char *name) { FILE *file=fopen(format("input/%s",name),"r"); if (!file) exit(EXIT_FAILURE); Strings result={0}; Text line={0}; int c; while ((c=fgetc(file))!=EOF) { if (c=='\n') { add_string(&result,line.data ? line.data : ""); line.length=0; if (line.data) *line.data=0; } else { char part[2]={(char)c,0}; append_text(&line,part); } } if (ferror(file)) exit(EXIT_FAILURE); fclose(file); return result; }
void add_flow(Flows *flows,int day,double amount) { if (flows->count==flows->capacity) { flows->capacity=flows->capacity ? flows->capacity*2 : 16; flows->data=resize(flows->data,(size_t)flows->capacity*sizeof(*flows->data)); } flows->data[flows->count++]=(Flow){day,amount}; }
static bool contains(Strings words,const char *word) { for (int i=0;i<words.count;i++) if (!strcmp(words.data[i],word)) return true; return false; }
static int index_of(const char *text,const char *const *values,int count) { for (int i=0;i<count;i++) if (!strcmp(text,values[i])) return i; return -1; }
static bool valid_frequency(int frequency) { return frequency==1 || frequency==2 || frequency==4 || frequency==12; }
static int64_t integer(const char *text) { return strtoll(text,NULL,10); }
static int64_t half_up(int64_t a,int64_t b) { return (2*a+b)/(2*b); }
static char *hundredths(int64_t value) { if (value<0) return format("-%s",hundredths(-value)); return format("%" PRId64 ".%02" PRId64,value/100,value%100); }
static char *decimals(double value,int digits) { int64_t scale=1; for (int i=0;i<digits;i++) scale*=10; bool negative=value<0; if (negative) value=-value; int64_t rounded=(int64_t)(value*(double)scale+0.5); return format("%s%" PRId64 ".%0*" PRId64,negative && rounded ? "-" : "",rounded/scale,digits,rounded%scale); }
static char *percent(double value) { return decimals(value*100,4); }
static char *amount(double value) { return decimals(value/100,2); }
static int64_t thousandths(const char *text) { Strings parts=split(text,'.'); return integer(parts.data[0])*1000+integer(parts.data[1]); }
static bool fail(char **reason,const char *message) { *reason=(char *)message; return false; }
static void add_error(Strings *errors,const char *file,int line,const char *key,const char *message) { add_string(errors,format("%s:%d: %s: %s",file,line,key,message)); }
static Params parse_params(void) {
    Params params={0}; Strings lines=read_lines("params.txt");
    for (int i=0;i<lines.count;i++) { Strings words=split(lines.data[i],' '); char *kind=words.data[0];
        if (!strcmp(kind,"valuation_date")) params.valuation=parse_date(words.data[1]);
        else if (!strcmp(kind,"settlement_days")) params.settlement_days=(int)integer(words.data[1]);
        else if (!strcmp(kind,"scenario")) params.scenarios[params.scenario_count++]=(RawScenario){i+1,words.data[1],{words.data+2,words.count-2,0}};
        else params.limits[params.limit_count++]=(Strings){words.data+1,words.count-1,0};
    }
    return params;
}
static void add_option(OptionValues *items,const char *date,int64_t amount) { if (items->count==items->capacity) { items->capacity=items->capacity ? items->capacity*2 : 8; items->data=resize(items->data,(size_t)items->capacity*sizeof(*items->data)); } items->data[items->count++]=(OptionValue){copy_text(date),amount}; }
static bool parse_options(const char *kind,const char *text,Options *options,char **reason) {
    options->cap=1200; Strings seen={0};
    if (strcmp(text,"-")) { Strings items=split(text,';'); for (int i=0;i<items.count;i++) {
        Strings parts=split(items.data[i],'='); char *key=parts.data[0],*value=parts.count>1 ? parts.data[1] : "";
        bool allowed=!strcmp(key,"EOM") || !strcmp(key,"LONG") || (!strcmp(kind,"FIXED") && !strcmp(key,"CALL")) || (!strcmp(kind,"AMORT") && !strcmp(key,"SINK")) || (!strcmp(kind,"FRN") && (!strcmp(key,"LAG") || !strcmp(key,"CAP") || !strcmp(key,"FLOOR")));
        if (!allowed || (contains(seen,key) && strcmp(key,"SINK") && strcmp(key,"CALL"))) return fail(reason,"invalid option"); add_string(&seen,key);
        if (!strcmp(key,"EOM")) options->eom=true; else if (!strcmp(key,"LONG")) options->long_stub=true;
        else if (!strcmp(key,"LAG")) options->lag=(int)integer(value); else if (!strcmp(key,"CAP")) options->cap=integer(value); else if (!strcmp(key,"FLOOR")) options->floor=integer(value);
        else { Strings pair=split(value,':'); add_option(!strcmp(key,"SINK") ? &options->sinks : &options->calls,pair.data[0],!strcmp(key,"SINK") ? integer(pair.data[1]) : thousandths(pair.data[1])); }
    } }
    if (!strcmp(kind,"FRN") && (options->lag<1 || options->lag>5 || options->cap>1200 || options->floor>options->cap)) return fail(reason,"invalid option"); return true;
}
static bool schedule_items(OptionValues options,Schedule schedule,DatedAmount **output,char **reason,const char *message) {
    *output=allocate((size_t)options.count*sizeof(**output)); int previous=-1;
    for (int i=0;i<options.count;i++) { if (!valid_date(options.data[i].date)) return fail(reason,message); int day=parse_date(options.data[i].date); bool inner=false; for (int j=1;j+1<schedule.count;j++) if (schedule.data[j]==day) inner=true; if (!inner || day<=previous) return fail(reason,message); (*output)[i]=(DatedAmount){day,options.data[i].amount}; previous=day; }
    return true;
}
static Bond *parse_bond(Strings fields,bool duplicate,const Calendar *calendar,const Fixing *fixings,int fixing_count,char **reason) {
    char **f=fields.data; if (duplicate) { fail(reason,"duplicate id"); return NULL; }
    if (index_of(f[1],bond_types,4)<0) { fail(reason,"unknown type"); return NULL; }
    if (!valid_date(f[2]) || !valid_date(f[3])) { fail(reason,"invalid date"); return NULL; }
    int issue=parse_date(f[2]),maturity=parse_date(f[3]),frequency=(int)integer(f[5]); int64_t coupon=integer(f[4]),face=integer(f[8]);
    if (maturity<=issue) { fail(reason,"maturity not after issue"); return NULL; }
    if (!valid_frequency(frequency)) { fail(reason,"invalid frequency"); return NULL; }
    if (index_of(f[6],day_counts,5)<0) { fail(reason,"unknown day count"); return NULL; }
    if (index_of(f[7],business_rules,4)<0) { fail(reason,"unknown business day rule"); return NULL; }
    if (face%100000 || face>10000000) { fail(reason,"invalid face"); return NULL; }
    if (coupon>1200 || (!strcmp(f[1],"ZERO") && coupon)) { fail(reason,"invalid coupon"); return NULL; }
    Bond *bond=allocate(sizeof(*bond)); bond->code=f[0]; bond->kind=f[1]; bond->issue=issue; bond->maturity=maturity; bond->frequency=frequency; bond->coupon=coupon; bond->face=face; bond->daycount=f[6]; bond->bdc=f[7];
    if (!parse_options(bond->kind,f[9],&bond->options,reason)) return NULL;
    bond->schedule=coupon_schedule(issue,maturity,frequency,bond->options.eom,bond->options.long_stub);
    if (!schedule_items(bond->options.sinks,bond->schedule,&bond->sinks,reason,"invalid sinking fund")) return NULL; bond->sink_count=bond->options.sinks.count; int64_t total=0;
    for (int i=0;i<bond->sink_count;i++) { if (!bond->sinks[i].amount) { fail(reason,"invalid sinking fund"); return NULL; } total+=bond->sinks[i].amount; }
    if (!strcmp(bond->kind,"AMORT") && (!total || total>=face)) { fail(reason,"invalid sinking fund"); return NULL; }
    if (!schedule_items(bond->options.calls,bond->schedule,&bond->calls,reason,"invalid call schedule")) return NULL; bond->call_count=bond->options.calls.count;
    for (int i=0;i<bond->call_count;i++) if (bond->calls[i].amount<100000 || bond->calls[i].amount>110000) { fail(reason,"invalid call schedule"); return NULL; }
    bond->period_count=bond->schedule.count-1; bond->periods=allocate((size_t)bond->period_count*sizeof(*bond->periods)); int64_t opening=face;
    for (int i=0;i<bond->period_count;i++) {
        int start=bond->schedule.data[i],end=bond->schedule.data[i+1]; int64_t rate=coupon;
        if (!strcmp(bond->kind,"ZERO")) rate=0;
        else if (!strcmp(bond->kind,"FRN")) { int reset=move_business(calendar,adjust_date(calendar,start,bond->bdc),bond->options.lag,-1); bool found=false; for (int j=0;j<fixing_count;j++) { if (fixings[j].day>reset) break; rate=fixings[j].rate+coupon; found=true; } if (!found) { fail(reason,"missing fixing"); return NULL; } if (rate<bond->options.floor) rate=bond->options.floor; if (rate>bond->options.cap) rate=bond->options.cap; }
        int64_t principal=0; if (i==bond->period_count-1) principal=opening; else for (int j=0;j<bond->sink_count;j++) if (bond->sinks[j].day==end) principal=bond->sinks[j].amount;
        Fraction fraction=year_fraction(bond->daycount,start,end); int64_t coupon_amount=half_up(opening*rate*fraction.numerator,10000*fraction.denominator);
        bond->periods[i]=(Period){i+1,start,end,adjust_date(calendar,end,bond->bdc),fraction,rate,opening,coupon_amount,principal,coupon_amount+principal}; opening-=principal;
    }
    return bond;
}
static Bond *find_bond(Bond **bonds,int count,const char *code) { for (int i=0;i<count;i++) if (!strcmp(bonds[i]->code,code)) return bonds[i]; return NULL; }
static Valuation *find_valuation(Valuation **values,int count,const char *code) { for (int i=0;i<count;i++) if (!strcmp(values[i]->bond->code,code)) return values[i]; return NULL; }
static Valuation *new_valuation(Bond *bond,int64_t clean,int settlement) {
    Valuation *v=allocate(sizeof(*v)); v->bond=bond; v->clean=clean; while (bond->periods[v->first].end<=settlement) v->first++; Period *current=&bond->periods[v->first]; v->outstanding=current->opening;
    Fraction elapsed=year_fraction(bond->daycount,current->start,settlement); v->accrued=(double)current->rate*(double)elapsed.numerator/(100*(double)elapsed.denominator); v->accrued_amount=half_up(v->outstanding*current->rate*elapsed.numerator,10000*elapsed.denominator); v->clean_amount=half_up(v->outstanding*clean,100000); v->unit_value=v->clean_amount+v->accrued_amount; v->target=(double)clean/1000+v->accrued;
    Fraction remaining=year_fraction(bond->daycount,settlement,current->end); v->fraction=(double)bond->frequency*(double)remaining.numerator/(double)remaining.denominator;
    int count=bond->period_count-v->first; int64_t *flows=allocate((size_t)count*sizeof(*flows));
    for (int i=0;i<count;i++) { Period *period=&bond->periods[v->first+i]; flows[i]=period->cash; if (period->cash>0) { if (!v->flows.count) v->next_payment=period->payment; add_flow(&v->flows,period->payment-settlement,(double)period->cash); } }
    v->pricer=(YieldPricer){flows,count,v->fraction,bond->frequency,v->outstanding}; v->workout=bond->maturity; return v;
}
static void analyze_valuation(Valuation *v,const Curve *curve,int settlement) {
    Bond *bond=v->bond; v->ytm=solve_yield(&v->pricer,v->target); v->risk=yield_risk(&v->pricer,v->ytm); v->ytw=v->ytm;
    for (int i=0;i<bond->call_count;i++) if (bond->calls[i].day>settlement) {
        int64_t *flows=allocate((size_t)v->pricer.count*sizeof(*flows)); int count=0;
        for (int j=v->first;j<bond->period_count;j++) { Period *period=&bond->periods[j]; flows[count++]=period->coupon; if (period->end==bond->calls[i].day) { flows[count-1]+=half_up(period->opening*bond->calls[i].amount,100000); break; } }
        YieldPricer pricer={flows,count,v->fraction,bond->frequency,v->outstanding}; double rate=solve_yield(&pricer,v->target); if (rate<v->ytw) { v->ytw=rate; v->workout=bond->calls[i].day; }
    }
    int64_t principal_days=0; for (int i=v->first;i<bond->period_count;i++) if (bond->periods[i].cash>0) principal_days+=bond->periods[i].principal*(bond->periods[i].payment-settlement);
    v->wal=(double)principal_days/(365*(double)v->outstanding); v->curve_clean=present_value(curve,v->flows,0)*100/(double)v->outstanding-v->accrued; v->zspread=z_spread(curve,v->flows,(double)v->unit_value);
}
static int64_t market_value(const Position *position) { return position->units*position->value->unit_value; }
static int64_t position_face(const Position *position) { return position->units*position->value->bond->face; }
static int64_t outstanding(const Position *position) { return position->units*position->value->outstanding; }
static int64_t gain(const Position *position) { return position->units*position->value->clean_amount-position->book; }
static double position_dv01(const Position *position) { return position->value->risk.dv01*(double)position->units*(double)position->value->outstanding/10000; }
static double position_pv(const Position *position,const Curve *curve) { return (double)position->units*present_value(curve,position->value->flows,position->value->zspread); }
static void add_exposure(Exposure *exposure,const Position *position) { int64_t value=market_value(position); exposure->count++; exposure->value+=value; exposure->duration+=(double)value*position->value->risk.modified; exposure->dv01+=position_dv01(position); }

typedef struct { Flows flows; } FlatContext;
static double flat_value(double rate,void *context) { FlatContext *data=context; Curve curve={0}; curve.count=1; curve.rates[0]=rate; return present_value(&curve,data->flows,0); }
static double portfolio_pv(const Position *positions,int count,const Curve *curve) { double total=0; for (int i=0;i<count;i++) total+=position_pv(&positions[i],curve); return total; }
static double rate_duration(const Position *positions,int count,const Curve *curve,int pillar,double base) { double down[30]={0},up[30]={0}; for (int i=0;i<curve->count;i++) if (pillar<0 || pillar==i) { down[i]=-0.0001; up[i]=0.0001; } Curve lower=shifted_curve(curve,down),higher=shifted_curve(curve,up); return (portfolio_pv(positions,count,&lower)-portfolio_pv(positions,count,&higher))/(2*0.0001*base); }
static char *exposure_line(const char *label,const char *name,Exposure exposure,int64_t total) { return format("%s %s positions %d value %s weight %s duration %s dv01 %s",label,name,exposure.count,hundredths(exposure.value),decimals((double)exposure.value*100/(double)total,4),decimals(exposure.duration/(double)total,4),decimals(exposure.dv01,2)); }
static void portfolio_reports(const char *name,const Position *positions,int count,const Curve *curve,const Scenario *scenarios,int scenario_count,const Params *params,int settlement,Strings *report,Strings *scenario_lines,Strings *compliance) {
    int64_t value=0,face=0,total_outstanding=0,book=0,total_gain=0,income=0; double ytm=0,modified=0,convexity=0,zspread=0,dv01=0,base=0,base_values[300]; Exposure types[4]={0},buckets[5]={0}; YearTotals ladder[100]={0}; Flows cash_flows={0};
    for (int i=0;i<count;i++) {
        const Position *position=&positions[i]; Valuation *v=position->value; Bond *bond=v->bond; int64_t mv=market_value(position);
        value+=mv; face+=position_face(position); total_outstanding+=outstanding(position); book+=position->book; total_gain+=gain(position); ytm+=(double)mv*v->ytm; modified+=(double)mv*v->risk.modified; convexity+=(double)mv*v->risk.convexity; zspread+=(double)mv*v->zspread; dv01+=position_dv01(position); base_values[i]=position_pv(position,curve); base+=base_values[i];
        add_exposure(&types[index_of(bond->kind,bond_types,4)],position); int days=bond->maturity-settlement,bucket=days<365 ? 0 : days<1095 ? 1 : days<1825 ? 2 : days<3650 ? 3 : 4; add_exposure(&buckets[bucket],position);
        for (int j=v->first;j<bond->period_count;j++) { Period *period=&bond->periods[j]; if (!period->cash) continue; int day=period->payment-settlement; if (day<=365) income+=position->units*period->coupon; add_flow(&cash_flows,day,(double)(position->units*period->cash)); int year=civil_date(period->payment).year-2000; ladder[year].used=true; ladder[year].coupon+=position->units*period->coupon; ladder[year].principal+=position->units*period->principal; }
    }
    ytm/=(double)value; modified/=(double)value; convexity/=(double)value; zspread/=(double)value; FlatContext flat={cash_flows}; double cash_yield=bisection(flat_value,&flat,0,1,(double)value);
    add_string(report,format("portfolio %s",name));
    for (int i=0;i<count;i++) { const Position *position=&positions[i]; Valuation *v=position->value; add_string(report,format("position %s face %s outstanding %s clean %s value %s weight %s book %s gain %s ytm %s modified %s dv01 %s",v->bond->code,hundredths(position_face(position)),hundredths(outstanding(position)),decimals((double)v->clean/1000,6),hundredths(market_value(position)),decimals((double)market_value(position)*100/(double)value,4),hundredths(position->book),hundredths(gain(position)),percent(v->ytm),decimals(v->risk.modified,4),decimals(position_dv01(position),2))); }
    add_string(report,format("total positions %d face %s outstanding %s value %s book %s gain %s income %s",count,hundredths(face),hundredths(total_outstanding),hundredths(value),hundredths(book),hundredths(total_gain),hundredths(income)));
    add_string(report,format("risk ytm %s yield %s modified %s convexity %s zspread %s dv01 %s",percent(ytm),percent(cash_yield),decimals(modified,4),decimals(convexity,4),percent(zspread),decimals(dv01,2)));
    Strings rates={0}; for (int i=0;i<curve->count;i++) add_string(&rates,decimals(rate_duration(positions,count,curve,i,base),4)); add_string(report,format("curve effective %s krd %s",decimals(rate_duration(positions,count,curve,-1,base),4),join(rates," ")));
    for (int i=0;i<4;i++) add_string(report,exposure_line("type",bond_types[i],types[i],value)); for (int i=0;i<5;i++) add_string(report,exposure_line("bucket",bucket_names[i],buckets[i],value));
    int64_t coupon_total=0,principal_total=0; for (int i=0;i<100;i++) if (ladder[i].used) { coupon_total+=ladder[i].coupon; principal_total+=ladder[i].principal; add_string(report,format("ladder %d coupon %s principal %s total %s",i+2000,hundredths(ladder[i].coupon),hundredths(ladder[i].principal),hundredths(ladder[i].coupon+ladder[i].principal))); }
    add_string(report,format("ladder total coupon %s principal %s total %s",hundredths(coupon_total),hundredths(principal_total),hundredths(coupon_total+principal_total)));
    ScenarioResult *worst=NULL;
    for (int s=0;s<=scenario_count;s++) {
        double deltas[30]={0}; const char *scenario_name="BASE"; if (s) { scenario_name=scenarios[s-1].name; memcpy(deltas,scenarios[s-1].shifts,sizeof(deltas)); } Curve shifted=shifted_curve(curve,deltas); ScenarioResult *result=allocate(sizeof(*result)); result->name=(char *)scenario_name;
        for (int i=0;i<count;i++) { result->values[i]=position_pv(&positions[i],&shifted); result->pnls[i]=result->values[i]-base_values[i]; result->total+=result->values[i]; add_string(scenario_lines,format("%s,%s,%s,%s,%s",name,scenario_name,positions[i].value->bond->code,amount(result->values[i]),amount(result->pnls[i]))); }
        result->pnl=result->total-base; add_string(scenario_lines,format("%s,%s,*,%s,%s",name,scenario_name,amount(result->total),amount(result->pnl))); if (s && (!worst || result->pnl<worst->pnl)) worst=result;
    }
    if (worst) {
        int order[300]; for (int i=0;i<count;i++) { int j=i; while (j>0 && (worst->pnls[order[j-1]]>worst->pnls[i] || (worst->pnls[order[j-1]]==worst->pnls[i] && strcmp(positions[order[j-1]].value->bond->code,positions[i].value->bond->code)>0))) { order[j]=order[j-1]; j--; } order[j]=i; }
        Text line={0}; append_text(&line,format("stress worst %s pnl %s losers",worst->name,amount(worst->pnl))); for (int i=0;i<count && i<3;i++) append_text(&line,format(" %s %s",positions[order[i]].value->bond->code,amount(worst->pnls[order[i]]))); add_string(report,line.data);
    }
    int breaches=0;
    for (int i=0;i<params->limit_count;i++) {
        Strings words=params->limits[i]; char *kind=words.data[0],*details=NULL; bool breach=false;
        if (!strcmp(kind,"position_weight")) { int largest=0; for (int j=1;j<count;j++) if (market_value(&positions[j])>market_value(&positions[largest])) largest=j; int64_t mv=market_value(&positions[largest]),limit=integer(words.data[1]); details=format("%s %s limit %s",positions[largest].value->bond->code,decimals((double)mv*100/(double)value,4),hundredths(limit)); breach=mv*10000>limit*value; }
        else if (!strcmp(kind,"type_weight")) { int64_t mv=types[index_of(words.data[1],bond_types,4)].value,limit=integer(words.data[2]); details=format("%s %s limit %s",words.data[1],decimals((double)mv*100/(double)value,4),hundredths(limit)); breach=mv*10000>limit*value; }
        else if (!strcmp(kind,"max_maturity")) { int years=(int)integer(words.data[1]),n=0; for (int j=0;j<count;j++) if (positions[j].value->bond->maturity-settlement>365*years) n++; details=format("%dY positions %d",years,n); breach=n>0; }
        else if (!strcmp(kind,"min_yield")) { int64_t limit=integer(words.data[1]); details=format("%s limit %s",percent(ytm),hundredths(limit)); breach=ytm*10000<(double)limit; }
        else if (!strcmp(kind,"duration")) { int64_t low=integer(words.data[1]),high=integer(words.data[2]); details=format("%s range %s %s",decimals(modified,4),hundredths(low),hundredths(high)); breach=modified<(double)low/100 || modified>(double)high/100; }
        else { int64_t limit=integer(words.data[1]); details=format("%s limit %s",decimals(dv01,2),hundredths(limit)); breach=dv01*100>(double)limit; }
        if (breach) breaches++; add_string(compliance,format("%s %s %s %s",name,kind,details,breach ? "BREACH" : "PASS"));
    }
    add_string(compliance,format("%s breaches %d",name,breaches));
}
static int compare_pillars(const void *left,const void *right) { const Pillar *a=left,*b=right; return (a->maturity>b->maturity)-(a->maturity<b->maturity); }
static int compare_bonds(const void *left,const void *right) { return strcmp((*(Bond *const *)left)->code,(*(Bond *const *)right)->code); }
static int compare_values(const void *left,const void *right) { return strcmp((*(Valuation *const *)left)->bond->code,(*(Valuation *const *)right)->bond->code); }
static int compare_positions(const void *left,const void *right) { const Position *a=left,*b=right; int order=strcmp(a->portfolio,b->portfolio); return order ? order : strcmp(a->value->bond->code,b->value->bond->code); }
static void write_lines(const char *name,Strings lines) { FILE *file=fopen(format("output/%s",name),"w"); if (!file) exit(EXIT_FAILURE); for (int i=0;i<lines.count;i++) if (fprintf(file,"%s\n",lines.data[i])<0) exit(EXIT_FAILURE); if (fclose(file)) exit(EXIT_FAILURE); }
int main(void) {
    Params params=parse_params(); Calendar calendar={0}; Strings lines=read_lines("calendar.txt"); for (int i=0;i<lines.count;i++) calendar.days[calendar.count++]=parse_date(lines.data[i]); Fixing fixings[2000]; int fixing_count=0; lines=read_lines("fixings.csv"); for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); fixings[fixing_count++]=(Fixing){parse_date(fields.data[0]),integer(fields.data[1])}; }
    int settlement=move_business(&calendar,params.valuation,params.settlement_days,1); Strings errors={0},seen={0}; Pillar pillars[30]; int pillar_count=0; lines=read_lines("curve_quotes.csv");
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char **f=fields.data,*reason=NULL; if (contains(seen,f[0])) reason="duplicate pillar"; else if (!valid_date(f[0])) reason="invalid date"; else if (parse_date(f[0])<=settlement) reason="pillar not after settlement"; else if (!valid_frequency((int)integer(f[2]))) reason="invalid frequency"; if (reason) add_error(&errors,"curve_quotes.csv",i+1,f[0],reason); else pillars[pillar_count++]=(Pillar){parse_date(f[0]),(int)integer(f[2]),integer(f[1])}; add_string(&seen,f[0]); }
    qsort(pillars,(size_t)pillar_count,sizeof(*pillars),compare_pillars); Scenario scenarios[40]={0}; int scenario_count=0; seen=(Strings){0};
    for (int i=0;i<params.scenario_count;i++) { RawScenario raw=params.scenarios[i]; if (contains(seen,raw.name)) add_error(&errors,"params.txt",raw.line,raw.name,"duplicate scenario"); else if (raw.shifts.count!=pillar_count) add_error(&errors,"params.txt",raw.line,raw.name,"wrong number of shifts"); else { Scenario *scenario=&scenarios[scenario_count++]; scenario->name=raw.name; for (int j=0;j<pillar_count;j++) scenario->shifts[j]=(double)integer(raw.shifts.data[j])*0.0001; } add_string(&seen,raw.name); }
    Bond *bonds[100]; int bond_count=0; seen=(Strings){0}; lines=read_lines("bonds.csv");
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char *reason=NULL; Bond *bond=parse_bond(fields,contains(seen,fields.data[0]),&calendar,fixings,fixing_count,&reason); if (!bond) add_error(&errors,"bonds.csv",i+1,fields.data[0],reason); else bonds[bond_count++]=bond; add_string(&seen,fields.data[0]); }
    Valuation *values[100]; int value_count=0; seen=(Strings){0}; lines=read_lines("prices.csv");
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char *code=fields.data[0],*reason=NULL; Bond *bond=find_bond(bonds,bond_count,code); Valuation *value=NULL;
        if (!bond) reason="unknown bond"; else if (contains(seen,code)) reason="duplicate price"; else if (!(bond->issue<=settlement && settlement<bond->maturity)) reason="not outstanding"; else { value=new_valuation(bond,thousandths(fields.data[1]),settlement); if (!(dirty_price(&value->pricer,0)>value->target && value->target>dirty_price(&value->pricer,1))) reason="yield out of range"; }
        if (reason) add_error(&errors,"prices.csv",i+1,code,reason); else values[value_count++]=value; add_string(&seen,code);
    }
    Position positions[300]={0}; int position_count=0; lines=read_lines("holdings.csv");
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char **f=fields.data,*reason=NULL; Bond *bond=find_bond(bonds,bond_count,f[1]); Valuation *value=find_valuation(values,value_count,f[1]); int64_t face=integer(f[2]);
        if (!bond) reason="unknown bond"; else if (!value) reason="no price"; else if (face%bond->face) reason="invalid face"; if (reason) { add_error(&errors,"holdings.csv",i+1,f[1],reason); continue; }
        int index=0; while (index<position_count && (strcmp(positions[index].portfolio,f[0]) || strcmp(positions[index].value->bond->code,f[1]))) index++; if (index==position_count) positions[position_count++]=(Position){f[0],value,0,0}; int64_t units=face/bond->face; positions[index].units+=units; positions[index].book+=half_up(units*value->outstanding*thousandths(f[3]),100000);
    }
    Curve curve=bootstrap(settlement,pillars,pillar_count); for (int i=0;i<value_count;i++) analyze_valuation(values[i],&curve,settlement); qsort(bonds,(size_t)bond_count,sizeof(*bonds),compare_bonds); qsort(values,(size_t)value_count,sizeof(*values),compare_values); qsort(positions,(size_t)position_count,sizeof(*positions),compare_positions);
    Strings cashflows={0}; add_string(&cashflows,"bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal");
    for (int i=0;i<bond_count;i++) for (int j=0;j<bonds[i]->period_count;j++) { Period *period=&bonds[i]->periods[j]; if (period->cash>0) add_string(&cashflows,format("%s,%d,%s,%s,%s,%s,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64,bonds[i]->code,period->number,date_text(period->start),date_text(period->end),date_text(period->payment),decimals((double)period->fraction.numerator/(double)period->fraction.denominator,6),period->rate,period->opening,period->coupon,period->principal)); }
    Strings analytics={0}; add_string(&analytics,"bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread");
    for (int i=0;i<value_count;i++) { Valuation *v=values[i]; add_string(&analytics,format("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",v->bond->code,decimals((double)v->clean/1000,6),decimals(v->accrued,6),decimals(v->target,6),percent(v->ytm),percent(v->ytw),date_text(v->workout),date_text(v->next_payment),decimals(v->wal,4),decimals(v->risk.macaulay,4),decimals(v->risk.modified,4),decimals(v->risk.convexity,4),decimals(v->risk.dv01,6),decimals(v->curve_clean,6),percent(v->zspread))); }
    Strings curve_lines={0}; add_string(&curve_lines,format("valuation %s settlement %s",date_text(params.valuation),date_text(settlement))); int previous=0;
    for (int i=0;i<pillar_count;i++) { int days=curve.days[i]; add_string(&curve_lines,format("pillar %s days %d frequency %d par %s zero %s df %s forward %s",date_text(pillars[i].maturity),days,pillars[i].frequency,hundredths(pillars[i].coupon),percent(curve.rates[i]),decimals(discount_factor(&curve,days,0),6),percent(forward_rate(&curve,previous,days)))); previous=days; }
    for (int year=1;year<=curve.days[pillar_count-1]/365;year++) { int days=365*year; add_string(&curve_lines,format("grid %dY days %d zero %s df %s forward %s",year,days,percent(zero_rate(&curve,days)),decimals(discount_factor(&curve,days,0),6),percent(forward_rate(&curve,days-365,days)))); }
    Strings report={0},scenario_lines={0},compliance={0}; add_string(&scenario_lines,"portfolio,scenario,bond,value,pnl");
    for (int start=0;start<position_count;) { int end=start+1; while (end<position_count && !strcmp(positions[end].portfolio,positions[start].portfolio)) end++; portfolio_reports(positions[start].portfolio,positions+start,end-start,&curve,scenarios,scenario_count,&params,settlement,&report,&scenario_lines,&compliance); start=end; }
    if (mkdir("output",0777) && errno!=EEXIST) return EXIT_FAILURE; write_lines("errors.txt",errors); write_lines("cashflows.csv",cashflows); write_lines("analytics.csv",analytics); write_lines("curve.txt",curve_lines); write_lines("portfolio.txt",report); write_lines("scenarios.csv",scenario_lines); write_lines("compliance.txt",compliance); return EXIT_SUCCESS;
}
