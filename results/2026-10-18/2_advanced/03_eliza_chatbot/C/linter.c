#include "eliza.h"

static bool has_unknown(Rule *rule,Script *s) { for (int i=0;i<rule->pattern.count;i++) if (*rule->pattern.data[i]=='@' && !find_group(s,rule->pattern.data[i]+1)) return true; return false; }
static bool reaches(Script *s,Keyword *start,Keyword *goal,bool *seen) {
    if (start==goal) return true; if (seen[start->index]) return false; seen[start->index]=true;
    for (int i=0;i<start->decomp_count;i++) for (int j=0;j<start->decomps[i]->count;j++) {
        Item *item=start->decomps[i]->items[j]; if (item->kind!=GOTO && item->kind!=RESTATE) continue;
        Keyword *target=find_keyword(s,item->args.data[0]); if (target && reaches(s,target,goal,seen)) return true;
    }
    return false;
}
static int compare_diagnostics(const void *left,const void *right) { const Diagnostic *a=left,*b=right; if (a->line!=b->line) return (a->line>b->line)-(a->line<b->line); if (a->code!=b->code) return a->code-b->code; return a->order-b->order; }
Strings lint_script(Script *s) {
    static const char *const names[]={"SYNTAX","ORPHAN","DUPLICATE","KEY_NO_DECOMP","KEY_UNREACHABLE","SYNON_UNUSED","PRE_CHAIN","SYNON_UNKNOWN","RULE_NO_REASM","RULE_SHADOWED","REF_UNBOUND","TARGET_UNDEFINED","TARGET_CYCLE"};
    static const bool errors[]={true,true,true,false,false,false,false,true,false,false,true,true,true};
    for (int i=0;i<s->keyword_count;i++) {
        Keyword *key=s->keywords[i]; if (!key->decomp_count) add_diagnostic(s,key->line,3,format("keyword %s has no DECOMP",key->word));
        bool replacement=false,target=false;
        for (int j=0;j<s->pre_count;j++) if (strings_contains(s->pres[j].replacement,key->word)) replacement=true;
        for (int j=0;j<s->item_count;j++) if ((s->items[j]->kind==GOTO || s->items[j]->kind==RESTATE) && !strcmp(s->items[j]->args.data[0],key->word)) target=true;
        if (find_substitution(s->pres,s->pre_count,key->word) && !replacement && !target) add_diagnostic(s,key->line,4,format("keyword %s is replaced by PRE",key->word));
    }
    for (int i=0;i<s->group_count;i++) {
        Group *group=&s->groups[i]; bool used=false;
        for (int j=0;j<s->rule_count;j++) for (int k=0;k<s->rules[j]->pattern.count;k++) { char *element=s->rules[j]->pattern.data[k]; if (*element=='@' && !strcmp(element+1,group->name)) used=true; }
        if (!used) add_diagnostic(s,group->line,5,format("group %s is never used",group->name));
    }
    for (int i=0;i<s->pre_count;i++) for (int j=0;j<s->pres[i].replacement.count;j++) { char *word=s->pres[i].replacement.data[j]; if (find_substitution(s->pres,s->pre_count,word)) add_diagnostic(s,s->pres[i].line,6,format("replacement %s is itself replaced by PRE",word)); }
    for (int i=0;i<s->keyword_count;i++) {
        Keyword *key=s->keywords[i];
        for (int kind=0;kind<2;kind++) {
            Rule **rules=kind ? key->decomps : key->memories; int count=kind ? key->decomp_count : key->memory_count;
            for (int j=0;j<count;j++) {
                Rule *rule=rules[j]; int wildcards=0;
                for (int k=0;k<rule->pattern.count;k++) { char *element=rule->pattern.data[k]; if (*element=='@' && !find_group(s,element+1)) add_diagnostic(s,rule->line,7,format("unknown group %s",element+1)); if (is_wildcard(element)) wildcards++; }
                if (!rule->count) add_diagnostic(s,rule->line,8,"rule has no reassembly");
                if (!has_unknown(rule,s)) for (int k=0;k<j;k++) if (!has_unknown(rules[k],s) && pattern_covers(rules[k]->pattern,rule->pattern,s)) { add_diagnostic(s,rule->line,9,format("pattern is shadowed by line %d",rules[k]->line)); break; }
                for (int k=0;k<rule->count;k++) {
                    Item *item=rule->items[k];
                    if (item->kind==REASM) { size_t length=strlen(item->text); for (size_t p=0;p+3<=length;p++) { char chunk[4]={0}; memcpy(chunk,item->text+p,3); if (is_reference(chunk) && (chunk[1]=='0' || chunk[1]-'0'>wildcards)) add_diagnostic(s,item->line,10,format("reference (%c) is not bound",chunk[1])); } }
                    if (item->kind==RESTATE) for (int p=1;p<item->args.count;p++) { char *arg=item->args.data[p]; if (is_reference(arg) && (arg[1]=='0' || arg[1]-'0'>wildcards)) add_diagnostic(s,item->line,10,format("reference (%c) is not bound",arg[1])); }
                    if (item->kind==GOTO || item->kind==RESTATE) { char *word=item->args.data[0]; Keyword *target=find_keyword(s,word); bool seen[100]={false}; if (!target) add_diagnostic(s,item->line,11,format("target %s is not a keyword",word)); else if (reaches(s,target,key,seen)) add_diagnostic(s,item->line,12,format("edge %s -> %s is on a cycle",key->word,word)); }
                }
            }
        }
    }
    Strings lines={0}; if (!s->diagnostic_count) { strings_add(&lines,"OK"); return lines; }
    qsort(s->diagnostics,(size_t)s->diagnostic_count,sizeof(*s->diagnostics),compare_diagnostics); int error_count=0;
    for (int i=0;i<s->diagnostic_count;i++) { Diagnostic *d=&s->diagnostics[i]; strings_add(&lines,format("%d %s %s",d->line,names[d->code],d->message)); if (errors[d->code]) error_count++; }
    strings_add(&lines,format("TOTAL %d errors=%d warnings=%d",s->diagnostic_count,error_count,s->diagnostic_count-error_count)); return lines;
}
