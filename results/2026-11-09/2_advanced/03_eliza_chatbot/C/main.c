#include "eliza.h"
#include <errno.h>
#include <sys/stat.h>

typedef struct { Strings *data; int count,capacity; } Clauses;
typedef struct { char *word; int count; } WordCount;
typedef struct { WordCount *data; int count,capacity; } Counts;
typedef struct { int *data; int count,capacity; } Integers;
typedef struct State State;
typedef struct {
    char *name,*previous;
    int turns,sources[5],stored,recalled;
    Strings history,last_trace;
    bool trace_on,has_trace;
    Counts topics,words;
    Integers unrecognized;
    State *undo;
} Session;
struct State {
    int positions[600],hits[600],item_uses[600],uses[100],replies[100],list_positions[3];
    Memory memory;
    Session session;
};
typedef struct { Script *script; State *state; Strings transcript; int sessions,total_turns,total_sources[5]; } Bot;
typedef struct { const char *label; int number; Rule *rule; } RuleEntry;
static const char *const sources[]={"keyword","memory","question","default","repeat"};

static void extend(Strings *destination,Strings source) { for (int i=0;i<source.count;i++) strings_add(destination,source.data[i]); }
static void add_integer(Integers *numbers,int number) { if (numbers->count==numbers->capacity) { numbers->capacity=numbers->capacity ? numbers->capacity*2 : 8; numbers->data=resize(numbers->data,(size_t)numbers->capacity*sizeof(*numbers->data)); } numbers->data[numbers->count++]=number; }
static void count_word(Counts *counts,const char *word) { for (int i=0;i<counts->count;i++) if (!strcmp(counts->data[i].word,word)) { counts->data[i].count++; return; } if (counts->count==counts->capacity) { counts->capacity=counts->capacity ? counts->capacity*2 : 16; counts->data=resize(counts->data,(size_t)counts->capacity*sizeof(*counts->data)); } counts->data[counts->count++]=(WordCount){copy_text(word),1}; }
static Counts copy_counts(Counts source) { Counts result={0}; if (source.count) { result.data=allocate((size_t)source.count*sizeof(*result.data)); memcpy(result.data,source.data,(size_t)source.count*sizeof(*result.data)); result.count=result.capacity=source.count; } return result; }
static State *clone_state(State *original) {
    State *copy=allocate(sizeof(*copy)); *copy=*original;
    copy->memory.texts=strings_copy(original->memory.texts); copy->memory.log=strings_copy(original->memory.log);
    copy->session.history=strings_copy(original->session.history); copy->session.last_trace=strings_copy(original->session.last_trace);
    copy->session.topics=copy_counts(original->session.topics); copy->session.words=copy_counts(original->session.words);
    if (original->session.unrecognized.count) { int count=original->session.unrecognized.count; copy->session.unrecognized.data=allocate((size_t)count*sizeof(int)); memcpy(copy->session.unrecognized.data,original->session.unrecognized.data,(size_t)count*sizeof(int)); copy->session.unrecognized.capacity=count; }
    return copy;
}
static void add_clause(Clauses *clauses,Strings words) { if (clauses->count==clauses->capacity) { clauses->capacity=clauses->capacity ? clauses->capacity*2 : 8; clauses->data=resize(clauses->data,(size_t)clauses->capacity*sizeof(*clauses->data)); } clauses->data[clauses->count++]=words; }
static void finish_word(Strings *words,Text *word) {
    if (!word->length) return;
    size_t start=0,end=word->length; while (start<end && word->data[start]=='\'') start++; while (end>start && word->data[end-1]=='\'') end--;
    if (end>start) { char *text=allocate(end-start+1); memcpy(text,word->data+start,end-start); strings_add(words,text); }
    word->length=0; word->data[0]=0;
}
static Clauses normalize(const char *text) {
    Clauses clauses={0}; Strings words={0}; Text word={0}; size_t length=strlen(text);
    for (size_t i=0;i<=length;i++) {
        char c=i<length ? text[i] : '.'; if (c>='A' && c<='Z') c=(char)(c+32);
        if ((c>='a' && c<='z') || (c>='0' && c<='9') || c=='\'') { char part[2]={c,0}; text_append(&word,part); }
        else { finish_word(&words,&word); if (strchr(",.?!;",c) && words.count) { add_clause(&clauses,words); words=(Strings){0}; } }
    }
    return clauses;
}
static Strings flatten(Clauses clauses) { Strings result={0}; for (int i=0;i<clauses.count;i++) extend(&result,clauses.data[i]); return result; }
static char *clause_key(Clauses clauses) { Strings parts={0}; for (int i=0;i<clauses.count;i++) strings_add(&parts,strings_join(clauses.data[i]," ")); return strings_join(parts,"|"); }
static Clauses prepared(Bot *bot,const char *text) {
    Clauses clauses=normalize(text);
    for (int i=0;i<clauses.count;i++) { Strings words={0}; for (int j=0;j<clauses.data[i].count;j++) { char *word=clauses.data[i].data[j]; Substitution *pre=find_substitution(bot->script->pres,bot->script->pre_count,word); if (pre) extend(&words,pre->replacement); else strings_add(&words,word); } clauses.data[i]=words; }
    return clauses;
}
static bool is_quit(Bot *bot,const char *text) { Strings words=flatten(normalize(text)); return words.count==1 && strings_contains(bot->script->quit,words.data[0]); }
static int selected(Bot *bot,Clauses clauses) { for (int i=0;i<clauses.count;i++) for (int j=0;j<clauses.data[i].count;j++) if (find_keyword(bot->script,clauses.data[i].data[j])) return i; return -1; }
static int keyword_list(Bot *bot,Strings words,Keyword **keys) {
    int count=0; bool seen[100]={false};
    for (int i=0;i<words.count;i++) { Keyword *key=find_keyword(bot->script,words.data[i]); if (!key || seen[key->index]) continue; seen[key->index]=true; int position=count++; while (position>0 && keys[position-1]->rank<key->rank) { keys[position]=keys[position-1]; position--; } keys[position]=key; }
    return count;
}
static int rule_entries(Keyword *key,RuleEntry *entries) { int count=0; for (int i=0;i<key->memory_count;i++) entries[count++]=(RuleEntry){"memory",i+1,key->memories[i]}; for (int i=0;i<key->decomp_count;i++) entries[count++]=(RuleEntry){"decomp",i+1,key->decomps[i]}; return count; }
static Rule *find_rule(Bot *bot,Rule **rules,int count,Strings words,int *number,Bindings *bindings) { for (int i=0;i<count;i++) { *bindings=match_pattern(rules[i]->pattern,words,bot->script); if (bindings->matched) { *number=i+1; return rules[i]; } } return NULL; }
static char *prefix(Bot *bot) { return format("%s %d",bot->state->session.name,bot->state->session.turns); }
static void reset_cycles(Bot *bot) { memset(bot->state->positions,0,sizeof(bot->state->positions)); memset(bot->state->list_positions,0,sizeof(bot->state->list_positions)); }
static char *take_text(Bot *bot,int kind) { int position=bot->state->list_positions[kind-2]; bot->state->list_positions[kind-2]=(position+1)%bot->script->texts[kind].count; return bot->script->texts[kind].data[position]; }
static Item *take_item(Bot *bot,Rule *rule,int *number) { int position=bot->state->positions[rule->index]; Item *item=rule->items[position]; bot->state->positions[rule->index]=(position+1)%rule->count; bot->state->item_uses[item->index]++; *number=position+1; return item; }
static char *keyword_reply(Bot *bot,Clauses clauses,Strings *trace) {
    int clause=selected(bot,clauses); if (clause<0) { strings_add(trace,"CLAUSE none"); return NULL; }
    Strings words=clauses.data[clause]; strings_add(trace,format("CLAUSE %d %s",clause+1,strings_join(words," ")));
    Keyword *keys[100]; int count=keyword_list(bot,words,keys); Strings names={0}; for (int i=0;i<count;i++) strings_add(&names,keys[i]->word); strings_add(trace,format("KEYS %s",strings_join(names," ")));
    int number=0,item_number=0; Bindings bindings; Rule *rule=find_rule(bot,keys[0]->memories,keys[0]->memory_count,words,&number,&bindings);
    if (rule) {
        strings_add(trace,format("MEMORY %s %d",keys[0]->word,number)); bot->state->hits[rule->index]++;
        if (rule->count) { Item *item=take_item(bot,rule,&item_number); char *text=build_reply(item->text,bindings,bot->script); if (memory_store(&bot->state->memory,prefix(bot),keys[0]->word,text)) bot->state->session.stored++; }
    }
    bool entered[100]={false};
    for (int i=0;i<count;i++) {
        if (entered[keys[i]->index]) continue; strings_add(trace,format("ENTER %s",keys[i]->word)); Keyword *key=keys[i]; Strings current=words;
        while (true) {
            entered[key->index]=true; bot->state->uses[key->index]++;
            rule=find_rule(bot,key->decomps,key->decomp_count,current,&number,&bindings);
            if (!rule) { strings_add(trace,format("NOMATCH %s",key->word)); break; }
            bot->state->hits[rule->index]++;
            if (!rule->count) { strings_add(trace,format("DECOMP %s %d 0",key->word,number)); break; }
            Item *item=take_item(bot,rule,&item_number); strings_add(trace,format("DECOMP %s %d %d",key->word,number,item_number));
            if (item->kind==REASM) { bot->state->replies[key->index]++; count_word(&bot->state->session.topics,key->word); return build_reply(item->text,bindings,bot->script); }
            if (item->kind==NEWKEY) break;
            char *target=item->args.data[0]; Keyword *next=find_keyword(bot->script,target);
            if (!next || entered[next->index]) { strings_add(trace,format("BLOCKED %s",target)); break; }
            if (item->kind==RESTATE) { current=restated_words(item->args,bindings); strings_add(trace,current.count ? format("RESTATE %s %s",target,strings_join(current," ")) : format("RESTATE %s",target)); }
            else strings_add(trace,format("GOTO %s",target));
            key=next;
        }
    }
    return NULL;
}
static char *decide(Bot *bot,const char *text,Strings *trace) {
    Session *session=&bot->state->session; Clauses clauses=normalize(text); char *reply=NULL; int source=0; char *key=clause_key(clauses);
    if (bot->script->texts[4].count && clauses.count && session->previous && !strcmp(session->previous,key)) { strings_add(trace,"REPEAT"); reply=take_text(bot,4); source=4; }
    else {
        reply=keyword_reply(bot,prepared(bot,text),trace);
        if (!reply) {
            if (bot->state->memory.texts.count) { reply=memory_recall(&bot->state->memory,prefix(bot)); source=1; session->recalled++; }
            else if (*text && text[strlen(text)-1]=='?' && bot->script->texts[3].count) { reply=take_text(bot,3); source=2; }
            else { reply=take_text(bot,2); source=3; }
        }
    }
    strings_add(trace,format("REPLY %s",sources[source])); session->previous=key; session->sources[source]++;
    if (source==2 || source==3) add_integer(&session->unrecognized,session->turns);
    return reply;
}
static Strings grouped(Strings words,int size) { Strings result={0}; for (int i=0;i<words.count;i+=size) { int count=words.count-i; if (count>size) count=size; strings_add(&result,strings_join((Strings){words.data+i,count,0}," ")); } return result; }
static char *source_line(int turns,const int *counts) { return format("turns=%d keyword=%d memory=%d question=%d default=%d repeat=%d",turns,counts[0],counts[1],counts[2],counts[3],counts[4]); }
static int compare_counts(const void *left,const void *right) { const WordCount *a=left,*b=right; if (a->count!=b->count) return a->count>b->count ? -1 : 1; return strcmp(a->word,b->word); }
static char *ranked_counts(Counts original) { Counts counts=copy_counts(original); if (!counts.count) return "none"; qsort(counts.data,(size_t)counts.count,sizeof(*counts.data),compare_counts); Strings values={0}; for (int i=0;i<counts.count && i<5;i++) strings_add(&values,format("%s %d",counts.data[i].word,counts.data[i].count)); return strings_join(values,", "); }
static int compare_strings(const void *left,const void *right) { return strcmp(*(char *const *)left,*(char *const *)right); }
static int compare_integers(const void *left,const void *right) { int a=*(const int *)left,b=*(const int *)right; return (a>b)-(a<b); }
static int compare_keys(const void *left,const void *right) { const Keyword *a=*(Keyword *const *)left,*b=*(Keyword *const *)right; if (a->rank!=b->rank) return a->rank>b->rank ? -1 : 1; return strcmp(a->word,b->word); }
static Strings command(Bot *bot,const char *line) {
    char *space=strchr(line,' '); const char *text=space ? space+1 : ""; Strings words=strings_split(line),args=strings_split(text),result={0}; char *name=words.data[0]; Session *session=&bot->state->session;
    const char *const commands[]={":prepare",":test",":reflect",":keys",":groups",":find",":script",":why",":trace",":history",":memory",":forget",":cycles",":coverage",":reset",":unused",":stats",":say",":explain",":undo"};
    int kind=-1; for (int i=0;i<20;i++) if (!strcmp(name,commands[i])) kind=i;
    if (kind<0) { strings_add(&result,format("unknown command %s",name)); return result; }
    bool no_args=kind==3 || kind==7 || (kind>=9 && kind<=11) || (kind>=14 && kind<=16) || kind==19;
    bool one_arg=kind==4 || kind==5 || kind==6 || kind==12 || kind==13;
    bool free_text=kind==0 || kind==2 || kind==17 || kind==18;
    if ((no_args && args.count) || (one_arg && args.count!=1) || (free_text && !*text) || (kind==1 && args.count<2) || (kind==8 && (args.count!=1 || (strcmp(args.data[0],"on") && strcmp(args.data[0],"off"))))) { strings_add(&result,"bad arguments"); return result; }
    Keyword *keyword=NULL;
    if (kind==1 || kind==6 || kind==12 || kind==13) { keyword=find_keyword(bot->script,args.data[0]); if (!keyword) { strings_add(&result,format("unknown keyword %s",args.data[0])); return result; } }
    RuleEntry entries[40]; int count=keyword ? rule_entries(keyword,entries) : 0;
    switch (kind) {
    case 0: {
        Clauses clauses=prepared(bot,text); for (int i=0;i<clauses.count;i++) strings_add(&result,format("clause %d: %s",i+1,strings_join(clauses.data[i]," "))); if (!clauses.count) strings_add(&result,"no words");
        int index=selected(bot,clauses); if (index<0) strings_add(&result,"selected none"); else { strings_add(&result,format("selected %d",index+1)); Keyword *keys[100]; int n=keyword_list(bot,clauses.data[index],keys); Strings labels={0}; for (int i=0;i<n;i++) strings_add(&labels,format("%s/%d",keys[i]->word,keys[i]->rank)); strings_add(&result,format("keys %s",strings_join(labels," "))); } break;
    }
    case 1: {
        const char *body=strchr(text,' ')+1; Strings input=flatten(prepared(bot,body));
        for (int i=0;i<count;i++) { Bindings bindings=match_pattern(entries[i].rule->pattern,input,bot->script); char *value="no match"; if (bindings.matched) { Strings parts={0}; for (int j=0;j<bindings.count;j++) strings_add(&parts,format("[%s]",strings_join(bindings.data[j]," "))); value=parts.count ? strings_join(parts," ") : "match"; } strings_add(&result,format("%s %d: %s",entries[i].label,entries[i].number,value)); } if (!count) strings_add(&result,"no rules"); break;
    }
    case 2: { Clauses clauses=prepared(bot,text); for (int i=0;i<clauses.count;i++) strings_add(&result,strings_join(reflect(clauses.data[i],bot->script)," ")); if (!clauses.count) strings_add(&result,"no words"); break; }
    case 3: { Keyword *keys[100]; for (int i=0;i<bot->script->keyword_count;i++) keys[i]=bot->script->keywords[i]; qsort(keys,(size_t)bot->script->keyword_count,sizeof(*keys),compare_keys); Strings labels={0}; for (int i=0;i<bot->script->keyword_count;i++) strings_add(&labels,format("%s/%d",keys[i]->word,keys[i]->rank)); result=grouped(labels,8); break; }
    case 4: { Strings names={0}; for (int i=0;i<bot->script->group_count;i++) if (strings_contains(bot->script->groups[i].members,args.data[0])) strings_add(&names,bot->script->groups[i].name); qsort(names.data,(size_t)names.count,sizeof(*names.data),compare_strings); strings_add(&result,names.count ? strings_join(names," ") : "none"); break; }
    case 5: {
        char *word=args.data[0]; Keyword *key=find_keyword(bot->script,word); if (key) strings_add(&result,format("keyword rank %d",key->rank));
        for (int type=0;type<2;type++) { Substitution *subs=type ? bot->script->posts : bot->script->pres; int n=type ? bot->script->post_count : bot->script->pre_count; for (int i=0;i<n;i++) if (!strcmp(subs[i].source,word) || strings_contains(subs[i].replacement,word)) strings_add(&result,format("%s %d: %s -> %s",type ? "post" : "pre",subs[i].line,subs[i].source,strings_join(subs[i].replacement," "))); }
        for (int i=0;i<bot->script->group_count;i++) if (strings_contains(bot->script->groups[i].members,word)) strings_add(&result,format("group %s line %d",bot->script->groups[i].name,bot->script->groups[i].line));
        for (int i=0;i<bot->script->keyword_count;i++) { RuleEntry locations[40]; int n=rule_entries(bot->script->keywords[i],locations); for (int j=0;j<n;j++) if (strings_contains(locations[j].rule->pattern,word)) strings_add(&result,format("pattern %s %s %d",bot->script->keywords[i]->word,locations[j].label,locations[j].number)); }
        if (strings_contains(bot->script->stop,word)) strings_add(&result,"stop word"); if (strings_contains(bot->script->quit,word)) strings_add(&result,"quit word"); if (!result.count) strings_add(&result,"not found"); break;
    }
    case 6: { Integers numbers={0}; add_integer(&numbers,keyword->line); for (int i=0;i<count;i++) { add_integer(&numbers,entries[i].rule->line); for (int j=0;j<entries[i].rule->count;j++) add_integer(&numbers,entries[i].rule->items[j]->line); } qsort(numbers.data,(size_t)numbers.count,sizeof(int),compare_integers); for (int i=0;i<numbers.count;i++) strings_add(&result,format("%d %s",numbers.data[i],bot->script->lines.data[numbers.data[i]-1])); break; }
    case 7: if (session->has_trace) extend(&result,session->last_trace); else strings_add(&result,"no reply yet"); break;
    case 8: session->trace_on=!strcmp(args.data[0],"on"); strings_add(&result,format("trace %s",args.data[0])); break;
    case 9: { int start=session->history.count>5 ? session->history.count-5 : 0; for (int i=start;i<session->history.count;i++) strings_add(&result,session->history.data[i]); if (!result.count) strings_add(&result,"no turns yet"); break; }
    case 10: strings_add(&result,format("memory %d/%d",bot->state->memory.texts.count,bot->state->memory.capacity)); for (int i=0;i<bot->state->memory.texts.count;i++) strings_add(&result,format("%d: %s",i+1,bot->state->memory.texts.data[i])); break;
    case 11: { int n=bot->state->memory.texts.count; memory_clear(&bot->state->memory,prefix(bot)); strings_add(&result,format("forgot %d",n)); break; }
    case 12: case 13:
        for (int i=0;i<count;i++) { Rule *rule=entries[i].rule; if (kind==12) strings_add(&result,rule->count ? format("%s %d: next %d/%d",entries[i].label,entries[i].number,bot->state->positions[rule->index]+1,rule->count) : format("%s %d: empty",entries[i].label,entries[i].number)); else { Strings uses={0}; for (int j=0;j<rule->count;j++) strings_add(&uses,format("%d",bot->state->item_uses[rule->items[j]->index])); strings_add(&result,format("%s %d: hits %d entries %s",entries[i].label,entries[i].number,bot->state->hits[rule->index],uses.count ? strings_join(uses," ") : "-")); } } if (!count) strings_add(&result,"no rules"); break;
    case 14: reset_cycles(bot); strings_add(&result,"cycles reset"); break;
    case 15: { Integers numbers={0}; for (int i=0;i<bot->script->item_count;i++) if (!bot->state->item_uses[i]) add_integer(&numbers,bot->script->items[i]->line); qsort(numbers.data,(size_t)numbers.count,sizeof(int),compare_integers); strings_add(&result,format("unused %d",numbers.count)); Strings values={0}; for (int i=0;i<numbers.count;i++) strings_add(&values,format("%d",numbers.data[i])); extend(&result,grouped(values,12)); break; }
    case 16: strings_add(&result,source_line(session->turns,session->sources)); break;
    case 17: case 18:
        if (is_quit(bot,text)) strings_add(&result,"would quit"); else { State *saved=clone_state(bot->state); Strings trace={0}; char *reply=decide(bot,text,&trace); bot->state=saved; if (kind==17) strings_add(&result,reply); else result=trace; } break;
    case 19: if (!session->undo) strings_add(&result,"nothing to undo"); else { bot->state=session->undo; strings_add(&result,format("undone turn %d",bot->state->session.turns+1)); } break;
    }
    return result;
}
static void indented(Bot *bot,Strings lines) { for (int i=0;i<lines.count;i++) strings_add(&bot->transcript,format("  %s",lines.data[i])); }
static void notes(Bot *bot) {
    Session *session=&bot->state->session; strings_add(&bot->transcript,format("NOTES %s",session->name)); Strings lines={0},unrecognized={0};
    strings_add(&lines,source_line(session->turns,session->sources)); strings_add(&lines,format("topics: %s",ranked_counts(session->topics))); strings_add(&lines,format("words: %s",ranked_counts(session->words)));
    strings_add(&lines,format("memory: stored=%d recalled=%d pending=%d",session->stored,session->recalled,bot->state->memory.texts.count)); for (int i=0;i<session->unrecognized.count;i++) strings_add(&unrecognized,format("%d",session->unrecognized.data[i])); strings_add(&lines,format("unrecognized: %s",unrecognized.count ? strings_join(unrecognized," ") : "none")); indented(bot,lines);
    bot->total_turns+=session->turns; for (int i=0;i<5;i++) bot->total_sources[i]+=session->sources[i];
}
static void run_dialogue(Bot *bot,Strings lines) {
    for (int i=0;i<lines.count;i++) {
        char *line=lines.data[i];
        if (!strncmp(line,"SESSION ",8)) {
            bot->sessions++; char *name=line+8;
            if (bot->sessions>1) { strings_add(&bot->transcript,""); if (!bot->script->persist_cycles) reset_cycles(bot); if (!bot->script->persist_memory) memory_clear(&bot->state->memory,format("%s 0",name)); }
            bot->state->session=(Session){0}; bot->state->session.name=name;
            strings_add(&bot->transcript,line); Strings initial=bot->script->texts[0]; extend(&bot->transcript,eliza_lines(initial.data[(bot->sessions-1)%initial.count]));
        } else if (*line==':') { strings_add(&bot->transcript,line); indented(bot,command(bot,line)); }
        else {
            strings_add(&bot->transcript,format("YOU: %s",line));
            if (is_quit(bot,line)) { Strings final=bot->script->texts[1]; extend(&bot->transcript,eliza_lines(final.data[(bot->sessions-1)%final.count])); notes(bot); continue; }
            State *snapshot=clone_state(bot->state); snapshot->session.undo=NULL; Session *session=&bot->state->session; session->undo=snapshot; session->turns++;
            Strings words=flatten(normalize(line)); for (int j=0;j<words.count;j++) if (!strings_contains(bot->script->stop,words.data[j])) count_word(&session->words,words.data[j]); strings_add(&session->history,format("%d: %s",session->turns,line));
            Strings trace={0}; char *reply=decide(bot,line,&trace); extend(&bot->transcript,eliza_lines(reply)); session->last_trace=trace; session->has_trace=true; if (session->trace_on) indented(bot,trace);
        }
    }
    strings_add(&bot->transcript,""); strings_add(&bot->transcript,format("SUMMARY sessions=%d %s",bot->sessions,source_line(bot->total_turns,bot->total_sources)));
}
static Strings statistics(Bot *bot) {
    Keyword *keys[100]; int count=bot->script->keyword_count;
    for (int i=0;i<count;i++) { Keyword *key=bot->script->keywords[i]; int j=i; while (j>0 && (bot->state->uses[keys[j-1]->index]<bot->state->uses[key->index] || (bot->state->uses[keys[j-1]->index]==bot->state->uses[key->index] && strcmp(keys[j-1]->word,key->word)>0))) { keys[j]=keys[j-1]; j--; } keys[j]=key; }
    Strings lines={0}; strings_add(&lines,"keyword,rank,uses,replies,decomposition_hits");
    for (int i=0;i<count;i++) { Keyword *key=keys[i]; Strings hits={0}; for (int j=0;j<key->decomp_count;j++) strings_add(&hits,format("%d",bot->state->hits[key->decomps[j]->index])); strings_add(&lines,format("%s,%d,%d,%d,%s",key->word,key->rank,bot->state->uses[key->index],bot->state->replies[key->index],hits.count ? strings_join(hits,"/") : "-")); }
    return lines;
}
static void write_lines(const char *path,Strings lines) { FILE *file=fopen(path,"w"); if (!file) exit(EXIT_FAILURE); for (int i=0;i<lines.count;i++) if (fprintf(file,"%s\n",lines.data[i])<0) exit(EXIT_FAILURE); if (fclose(file)) exit(EXIT_FAILURE); }
int main(void) {
    Script *script=load_script("input/script.txt"); if (mkdir("output",0777) && errno!=EEXIST) return EXIT_FAILURE;
    write_lines("output/lint.txt",lint_script(script)); Bot bot={0}; bot.script=script; bot.state=allocate(sizeof(*bot.state)); bot.state->memory.capacity=script->memsize;
    run_dialogue(&bot,read_lines("input/dialogue.txt")); write_lines("output/transcript.txt",bot.transcript); write_lines("output/keyword_stats.csv",statistics(&bot)); write_lines("output/memory_log.txt",bot.state->memory.log); return EXIT_SUCCESS;
}
