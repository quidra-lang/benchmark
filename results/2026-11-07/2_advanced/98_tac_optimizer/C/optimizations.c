#include "tac.h"
void filter_code(Function *f,const unsigned char *deleted) {
    int n=0;
    for(int i=0;i<f->count;++i)if(!deleted[i])f->code[n++]=f->code[i];
    f->count=n;
}
int fold_instruction(Instruction *s) {
    if(s->kind==IF&&constant(s->a)&&constant(s->b)) {
        if(operation(s->op,strtoll(s->a,NULL,10),strtoll(s->b,NULL,10))) {
            s->kind=GOTO;
            return 1;
        }
        return -1;
    }
    if(s->kind!=BIN)return 0;
    int ca=constant(s->a),cb=constant(s->b);
    char value[NAME];
    if(ca&&cb) {
        long long a=strtoll(s->a,NULL,10),b=strtoll(s->b,NULL,10);
        if((!strcmp(s->op,"/")||!strcmp(s->op,"%"))&&!b)return 0;
        long long v=operation(s->op,a,b);
        if(v<INT32_MIN||v>INT32_MAX)return 0;
        sprintf(value,"%lld",v);
    }
    else if(ca!=cb) {
        long long c=strtoll(ca?s->a:s->b,NULL,10);
        const char *v=ca?s->b:s->a;
        if((!strcmp(s->op,"+")&&!c)||(!strcmp(s->op,"-")&&cb&&!c)||(!strcmp(s->op,"*")&&c==1)||(!strcmp(s->op,"/")&&cb&&c==1))strcpy(value,v);
        else if(!strcmp(s->op,"*")&&!c)strcpy(value,"0");
        else return 0;
    }
    else return 0;
    s->kind=COPY;
    strcpy(s->a,value);
    *s->b=0;
    *s->op=0;
    return 1;
}
void cse_rewrite(Function *f,const Analysis *a,const unsigned char *candidates,const unsigned char *sources,const char *temp) {
    Function result= {
        0
    };
    for(int line=0;line<f->count;++line) {
        Instruction s=f->code[line];
        int n=s.number-1;
        if(s.kind>=0&&n>=0&&candidates[n]) {
            s.kind=COPY;
            strcpy(s.a,temp);
            *s.b=0;
            *s.op=0;
            code_add(&result,s);
        }
        else if(s.kind>=0&&n>=0&&sources[n]) {
            Instruction copy= {
                .kind=COPY
            };
            strcpy(copy.dest,s.dest);
            strcpy(copy.a,temp);
            strcpy(s.dest,temp);
            code_add(&result,s);
            code_add(&result,copy);
        }
        else code_add(&result,s);
    }
    free(f->code);
    f->code=result.code;
    f->count=result.count;
    f->capacity=result.capacity;
    (void)a;
}
void hoist_code(Function *f,const Analysis *a,int loop,Ints move,int preheader,const char *label) {
    Loop *l=&a->loops[loop];
    int header=l->header;
    unsigned char *moving=allocate((size_t)f->count);
    for(int i=0;i<move.count;++i)moving[a->instructions.data[move.data[i]]]=1;
    int insert;
    if(preheader>=0) {
        Block *p=&a->blocks[preheader];
        insert=p->endline+1;
        int kind=f->code[p->endline].kind;
        if(kind==GOTO||kind==IF)insert=p->endline;
    }
    else insert=a->blocks[header].startline;
    Function result= {
        0
    };
    for(int line=0;line<=f->count;++line) {
        if(line==insert) {
            if(preheader<0) {
                Instruction marker= {
                    .kind=-1
                };
                strcpy(marker.target,label);
                code_add(&result,marker);
            }
            for(int i=0;i<move.count;++i)code_add(&result,f->code[a->instructions.data[move.data[i]]]);
        }
        if(line==f->count)break;
        if(moving[line])continue;
        Instruction s=f->code[line];
        if(preheader<0&&(s.kind==GOTO||s.kind==IF)) {
            int b=a->lineblock[line];
            if(!l->blocks.bits[b])for(int x=a->blocks[header].startline;x<a->instructions.data[a->blocks[header].first];++x)if(!strcmp(s.target,f->code[x].target))strcpy(s.target,label);
        }
        code_add(&result,s);
    }
    free(moving);
    free(f->code);
    f->code=result.code;
    f->count=result.count;
    f->capacity=result.capacity;
}
