#include "mrp.h"
#include <stdarg.h>

void *allocate(size_t size) { void *result=calloc(1,size ? size : 1); if (!result) exit(EXIT_FAILURE); return result; }
void *resize(void *pointer,size_t size) { void *result=realloc(pointer,size ? size : 1); if (!result) exit(EXIT_FAILURE); return result; }
char *copy_text(const char *text) { char *result=allocate(strlen(text)+1); strcpy(result,text); return result; }
char *format(const char *pattern,...) { va_list args,copy; va_start(args,pattern); va_copy(copy,args); int length=vsnprintf(NULL,0,pattern,args); va_end(args); char *result=allocate((size_t)length+1); vsnprintf(result,(size_t)length+1,pattern,copy); va_end(copy); return result; }
void append_text(Text *text,const char *part) { size_t length=strlen(part),needed=text->length+length+1; if (needed>text->capacity) { size_t capacity=text->capacity ? text->capacity : 64; while (capacity<needed) capacity*=2; text->data=resize(text->data,capacity); text->capacity=capacity; } memcpy(text->data+text->length,part,length+1); text->length+=length; }
void add_string(Strings *strings,const char *text) { if (strings->count==strings->capacity) { strings->capacity=strings->capacity ? strings->capacity*2 : 8; strings->data=resize(strings->data,(size_t)strings->capacity*sizeof(*strings->data)); } strings->data[strings->count++]=copy_text(text); }
Strings split(const char *text,char separator) { Strings result={0}; const char *start=text; for (const char *p=text;;p++) if (*p==separator || !*p) { char *part=allocate((size_t)(p-start)+1); memcpy(part,start,(size_t)(p-start)); add_string(&result,part); if (!*p) break; start=p+1; } return result; }
Strings read_lines(const char *name) { FILE *file=fopen(format("input/%s",name),"r"); if (!file) exit(EXIT_FAILURE); Strings result={0}; Text line={0}; int c; while ((c=fgetc(file))!=EOF) { if (c=='\n') { add_string(&result,line.data ? line.data : ""); line.length=0; if (line.data) *line.data=0; } else { char part[2]={(char)c,0}; append_text(&line,part); } } if (ferror(file)) exit(EXIT_FAILURE); fclose(file); return result; }
char *join(Strings strings,const char *separator) { Text result={0}; for (int i=0;i<strings.count;i++) { if (i) append_text(&result,separator); append_text(&result,strings.data[i]); } return result.data ? result.data : copy_text(""); }
int64_t integer(const char *text) { return strtoll(text,NULL,10); }
void record_error(Model *model,const char *file,int line,const char *message) { add_string(&model->errors,format("%s line %d: %s",file,line,message)); }
int find_item(const Model *model,const char *id) { for (int i=0;i<model->item_count;i++) if (!strcmp(model->items[i].id,id)) return i; return -1; }
int find_center(const Model *model,const char *id) { for (int i=0;i<model->center_count;i++) if (!strcmp(model->centers[i].id,id)) return i; return -1; }
void read_items(Model *model) {
    static const char *const rules[]={"LFL","FOQ","POQ","MIN"}; Strings lines=read_lines("items.csv");
    for (int i=1;i<lines.count;i++) { Strings fields=split(lines.data[i],','); char **f=fields.data,*message=NULL; int rule=-1; for (int j=0;j<4;j++) if (!strcmp(f[2],rules[j])) rule=j; Strings lot=split(f[3],'/'); int64_t a=integer(lot.data[0]),b=lot.count==2 ? integer(lot.data[1]) : 0; bool fits=rule==LFL ? lot.count==1 && a==0 : rule==MIN ? lot.count==2 && a>=1 && b>=1 : lot.count==1 && a>=1;
        if (find_item(model,f[0])>=0) message=format("duplicate item %s",f[0]); else if (rule<0) message=format("unknown lot rule %s",f[2]); else if (!fits) message=format("bad lot parameter %s for %s",f[3],f[2]);
        if (message) { record_error(model,"items.csv",i+1,message); continue; }
        Item *item=&model->items[model->item_count++]; strcpy(item->id,f[0]); strcpy(item->description,f[8]); item->lead=(int)integer(f[1]); item->rule=(LotRule)rule; item->a=a; item->b=b; item->safety=integer(f[4]); item->on_hand=integer(f[5]); item->material=integer(f[6]); item->labor=integer(f[7]); item->code=item->cumulative=-1;
    }
}
char *lot_label(const Item *item) { if (item->rule==LFL) return "LFL"; if (item->rule==MIN) return format("MIN %" PRId64 "/%" PRId64,item->a,item->b); return format("%s %" PRId64,item->rule==FOQ ? "FOQ" : "POQ",item->a); }
