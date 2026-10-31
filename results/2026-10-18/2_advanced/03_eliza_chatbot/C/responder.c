#include "eliza.h"

Strings reflect(Strings words,Script *s) {
    Strings result={0}; for (int i=0;i<words.count;i++) {
        Substitution *post=find_substitution(s->posts,s->post_count,words.data[i]);
        if (post) { for (int j=0;j<post->replacement.count;j++) strings_add(&result,post->replacement.data[j]); } else strings_add(&result,words.data[i]);
    }
    return result;
}
static Strings bound(Bindings bindings,int number) { return number>=1 && number<=bindings.count ? bindings.data[number-1] : (Strings){0}; }
char *build_reply(const char *template,Bindings bindings,Script *s) {
    Text text={0}; size_t length=strlen(template);
    for (size_t i=0;i<length;) {
        char chunk[4]={0}; if (i+3<=length) memcpy(chunk,template+i,3);
        if (is_reference(chunk)) { text_append(&text,strings_join(reflect(bound(bindings,chunk[1]-'0'),s)," ")); i+=3; }
        else { char part[2]={template[i++],0}; text_append(&text,part); }
    }
    char *reply=strings_join(strings_split(text.data ? text.data : "")," ");
    if (*reply>='a' && *reply<='z') *reply=(char)(*reply-32);
    return reply;
}
Strings restated_words(Strings args,Bindings bindings) {
    Strings result={0}; for (int i=1;i<args.count;i++) { if (is_reference(args.data[i])) { Strings words=bound(bindings,args.data[i][1]-'0'); for (int j=0;j<words.count;j++) strings_add(&result,words.data[j]); } else strings_add(&result,args.data[i]); } return result;
}
Strings eliza_lines(const char *text) {
    Strings words=strings_split(text),lines={0}; char *line=format("ELIZA: %s",words.data[0]);
    for (int i=1;i<words.count;i++) { if (strlen(line)+1+strlen(words.data[i])<=72) line=format("%s %s",line,words.data[i]); else { strings_add(&lines,line); line=format("       %s",words.data[i]); } }
    strings_add(&lines,line); return lines;
}
