#include "awk.h"
int valid_filename(const char *s) {
    if(!*s||*s=='.')return 0;
    for(;*s;++s)if(!isalnum((unsigned char)*s)&&*s!='.'&&*s!='_'&&*s!='-')return 0;
    return 1;
}
static int valid_name(const char *s) {
    if(!isalpha((unsigned char)*s)&&*s!='_')return 0;
    for(++s;*s;++s)if(!isalnum((unsigned char)*s)&&*s!='_')return 0;
    return 1;
}
Streams read_args(void) {
    Streams s= {
        .current=-1
    };
    FILE *f=fopen("input/args.txt","r");
    if(!f)exit(EXIT_FAILURE);
    char *line;
    while((line=read_line(f))) {
        Operand a= {
            0
        };
        char *text=line;
        if(!strncmp(text,"-F ",3)) {
            a.option=a.assignment=1;
            a.name=str_copy("FS");
            a.value=str_copy(text+3);
        }
        else {
            if(!strncmp(text,"-v ",3)) {
                a.option=1;
                text+=3;
            }
            char *equal=strchr(text,'=');
            if(equal) {
                *equal=0;
                if(a.option||valid_name(text)) {
                    a.assignment=1;
                    a.name=str_copy(text);
                    a.value=str_copy(equal+1);
                }
                else *equal='=';
            }
            if(!a.assignment)a.name=str_copy(text);
        }
        s.args=mem_resize(s.args,(size_t)(s.count+1)*sizeof *s.args);
        s.args[s.count++]=a;
        free(line);
    }
    fclose(f);
    return s;
}
char *getline_file(Streams *s,const char *name,int *status) {
    InputStream *in=NULL;
    for(int i=0;i<s->ni;++i)if(!strcmp(s->inputs[i]->name,name))in=s->inputs[i];
    if(!in) {
        in=mem_new(sizeof *in);
        in->name=str_copy(name);
        s->inputs=mem_resize(s->inputs,(size_t)(s->ni+1)*sizeof *s->inputs);
        s->inputs[s->ni++]=in;
    }
    if(!in->opened) {
        if(valid_filename(name)) {
            char *path=mem_new(strlen(name)+7);
            sprintf(path,"input/%s",name);
            in->file=fopen(path,"r");
            free(path);
        }
        if(!in->file) {
            *status=-1;
            return NULL;
        }
        in->opened=in->ever=1;
    }
    char *line=read_line(in->file);
    *status=line?1:0;
    if(line)++in->reads;
    return line;
}
int close_stream(Streams *s,const char *name) {
    int closed=0;
    for(int i=0;i<s->ni;++i)if(!strcmp(s->inputs[i]->name,name)&&s->inputs[i]->opened) {
        fclose(s->inputs[i]->file);
        s->inputs[i]->file=NULL;
        s->inputs[i]->opened=0;
        closed=1;
    }
    for(int i=0;i<s->no;++i)if(!strcmp(s->outputs[i]->name,name)&&s->outputs[i]->open) {
        s->outputs[i]->open=0;
        closed=1;
    }
    return closed?0:-1;
}
void output_string(Streams *s,const char *name,int append,const char *text) {
    if(!name) {
        buffer_text(&s->standard,text);
        ++s->writes;
        return;
    }
    OutputStream *out=NULL;
    for(int i=0;i<s->no;++i)if(!strcmp(s->outputs[i]->name,name))out=s->outputs[i];
    if(!out) {
        out=mem_new(sizeof *out);
        out->name=str_copy(name);
        s->outputs=mem_resize(s->outputs,(size_t)(s->no+1)*sizeof *s->outputs);
        s->outputs[s->no++]=out;
    }
    if(!out->open) {
        out->open=1;
        if(!append) {
            out->content.length=0;
            if(out->content.data)*out->content.data=0;
        }
    }
    buffer_text(&out->content,text);
    ++out->writes;
}
void write_streams(Streams *s) {
    FILE *f=fopen("output/stdout.txt","w");
    if(!f)exit(EXIT_FAILURE);
    if(s->standard.length)fwrite(s->standard.data,1,s->standard.length,f);
    fclose(f);
    for(int i=0;i<s->no;++i) {
        OutputStream *o=s->outputs[i];
        char *path=mem_new(strlen(o->name)+8);
        sprintf(path,"output/%s",o->name);
        f=fopen(path,"w");
        free(path);
        if(!f)exit(EXIT_FAILURE);
        if(o->content.length)fwrite(o->content.data,1,o->content.length,f);
        fclose(f);
    }
}
