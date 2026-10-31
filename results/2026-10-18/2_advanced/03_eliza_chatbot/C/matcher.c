#include "eliza.h"

static bool word_fits(const char *element,const char *word,Script *s) {
    if (!strcmp(element,"#")) return true;
    if (*element=='@') { Group *group=find_group(s,element+1); return group && strings_contains(group->members,word); }
    return !strcmp(element,word);
}
static bool match_from(Strings pattern,Strings words,Script *s,int position,int start,int *ends) {
    if (position==pattern.count) return start==words.count;
    if (!strcmp(pattern.data[position],"*")) {
        for (int end=start;end<=words.count;end++) { ends[position]=end; if (match_from(pattern,words,s,position+1,end,ends)) return true; }
    } else if (start<words.count && word_fits(pattern.data[position],words.data[start],s)) { ends[position]=start+1; return match_from(pattern,words,s,position+1,start+1,ends); }
    return false;
}
Bindings match_pattern(Strings pattern,Strings words,Script *s) {
    Bindings result={0}; int ends[8]; result.matched=match_from(pattern,words,s,0,0,ends);
    if (!result.matched) return result;
    int start=0;
    for (int i=0;i<pattern.count;i++) { if (is_wildcard(pattern.data[i])) result.data[result.count++]=(Strings){words.data ? words.data+start : NULL,ends[i]-start,0}; start=ends[i]; }
    return result;
}
static bool element_covers(const char *element,const char *other,Script *s) {
    if (!strcmp(element,"#")) return strcmp(other,"*")!=0;
    if (*element=='@') { Group *group=find_group(s,element+1); if (*other=='@') { Group *covered=find_group(s,other+1); for (int i=0;i<covered->members.count;i++) if (!strings_contains(group->members,covered->members.data[i])) return false; return true; } return strings_contains(group->members,other); }
    return !strcmp(element,other);
}
static bool covers_from(Strings earlier,Strings later,Script *s,int position,int start) {
    if (position==earlier.count) return start==later.count;
    if (!strcmp(earlier.data[position],"*")) { for (int end=start;end<=later.count;end++) if (covers_from(earlier,later,s,position+1,end)) return true; return false; }
    return start<later.count && element_covers(earlier.data[position],later.data[start],s) && covers_from(earlier,later,s,position+1,start+1);
}
bool pattern_covers(Strings earlier,Strings later,Script *s) { return covers_from(earlier,later,s,0,0); }
