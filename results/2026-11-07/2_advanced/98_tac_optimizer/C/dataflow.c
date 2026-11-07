#include "tac.h"
static int name_compare(const void *a,const void *b) {
    return strcmp(a,b);
}
static int def_compare(const void *a,const void *b) {
    const Definition *x=a,*y=b;
    return x->number!=y->number?(x->number>y->number?1:-1):strcmp(x->name,y->name);
}
static int expr_compare(const void *a,const void *b) {
    return strcmp(((const Expression*)a)->text,((const Expression*)b)->text);
}
int variable_index(const Analysis *a,const char *name) {
    for(int i=0;i<a->nv;++i)if(!strcmp(a->variables[i],name))return i;
    return -1;
}
int expr_index(const Analysis *a,const Instruction *s) {
    if(s->kind!=BIN&&s->kind!=LOAD)return -1;
    for(int i=0;i<a->ne;++i)if(expression_equal(&a->expressions[i].instruction,s))return i;
    return -1;
}
static void add_variable(Analysis *a,const char *name) {
    if(!*name||constant(name)||variable_index(a,name)>=0)return;
    a->variables=resize(a->variables,(size_t)(a->nv+1)*sizeof *a->variables);
    strcpy(a->variables[a->nv++],name);
}
static void universe(Analysis *a) {
    Function *f=a->function;
    for(int p=0;p<f->np;++p) {
        add_variable(a,f->params[p]);
        a->definitions=resize(a->definitions,(size_t)(a->nd+1)*sizeof *a->definitions);
        Definition *d=&a->definitions[a->nd++];
        strcpy(d->name,f->params[p]);
        d->number=0;
        d->line=-1;
    }
    for(int i=0;i<a->instructions.count;++i)if(a->blocks[a->iblock[i]].reachable) {
        Instruction *s=&f->code[a->instructions.data[i]];
        const char *x=defined(s);
        if(*x) {
            add_variable(a,x);
            a->definitions=resize(a->definitions,(size_t)(a->nd+1)*sizeof *a->definitions);
            Definition *d=&a->definitions[a->nd++];
            strcpy(d->name,x);
            d->number=i+1;
            d->line=a->instructions.data[i];
        }
        char *use[2];
        int n=used(s,use);
        for(int j=0;j<n;++j)add_variable(a,use[j]);
        if((s->kind==BIN||s->kind==LOAD)&&expr_index(a,s)<0) {
            a->expressions=resize(a->expressions,(size_t)(a->ne+1)*sizeof *a->expressions);
            a->expressions[a->ne].instruction=*s;
            expression_text(s,a->expressions[a->ne++].text);
        }
        if(s->kind==COPY&&!constant(s->a)&&strcmp(s->dest,s->a)) {
            int found=0;
            for(int k=0;k<a->nc;++k)if(!strcmp(a->copies[k].x,s->dest)&&!strcmp(a->copies[k].y,s->a))found=1;
            if(!found) {
                a->copies=resize(a->copies,(size_t)(a->nc+1)*sizeof *a->copies);
                strcpy(a->copies[a->nc].x,s->dest);
                strcpy(a->copies[a->nc++].y,s->a);
            }
        }
    }
    qsort(a->variables,(size_t)a->nv,sizeof *a->variables,name_compare);
    qsort(a->definitions,(size_t)a->nd,sizeof *a->definitions,def_compare);
    qsort(a->expressions,(size_t)a->ne,sizeof *a->expressions,expr_compare);
}
void transfer(Analysis *a,int t,Set state,const Instruction *s) {
    const char *x=defined(s);
    if(t==0) {
        if(*x) {
            for(int i=0;i<a->nd;++i)if(!strcmp(a->definitions[i].name,x))state.bits[i]=a->definitions[i].number==s->number;
        }
    }
    else if(t==1) {
        if(*x) {
            int v=variable_index(a,x);
            if(v>=0)state.bits[v]=0;
        }
        Instruction copy=*s;
        char *v[2];
        int n=used(&copy,v);
        for(int i=0;i<n;++i) {
            int index=variable_index(a,v[i]);
            if(index>=0)state.bits[index]=1;
        }
    }
    else if(t==2) {
        int index=expr_index(a,s);
        if(index>=0)state.bits[index]=1;
        for(int i=0;i<a->ne;++i) {
            Instruction *e=&a->expressions[i].instruction;
            if((s->kind==STORE&&e->kind==LOAD&&!strcmp(s->op,e->op))||(s->kind==CALL&&e->kind==LOAD)||(*x&&(!strcmp(e->a,x)||(e->kind==BIN&&!strcmp(e->b,x)))))state.bits[i]=0;
        }
    }
    else {
        if(*x)for(int i=0;i<a->nc;++i)if(!strcmp(a->copies[i].x,x)||!strcmp(a->copies[i].y,x))state.bits[i]=0;
        if(s->kind==COPY&&!constant(s->a)&&strcmp(s->dest,s->a))for(int i=0;i<a->nc;++i)if(!strcmp(a->copies[i].x,s->dest)&&!strcmp(a->copies[i].y,s->a))state.bits[i]=1;
    }
}
void solve_dataflow(Analysis *a) {
    universe(a);
    int sizes[4]= {
        a->nd,a->nv,a->ne,a->nc
    };
    int ni=a->instructions.count;
    for(int t=0;t<4;++t) {
        a->in[t]=allocate((size_t)a->nb*sizeof(Set));
        a->out[t]=allocate((size_t)a->nb*sizeof(Set));
        a->before[t]=allocate((size_t)ni*sizeof(Set));
        for(int b=0;b<a->nb;++b) {
            a->in[t][b]=set_new(sizes[t],0);
            a->out[t][b]=set_new(sizes[t],t>=2&&a->blocks[b].reachable);
        }
        for(int i=0;i<ni;++i)a->before[t][i]=set_new(sizes[t],0);
        int changed;
        do {
            changed=0;
            ++a->iterations[t];
            Ints order=t==1?a->postorder:a->order;
            for(int j=0;j<order.count;++j) {
                int b=order.data[j];
                Block *block=&a->blocks[b];
                Set entry=set_new(sizes[t],t>=2&&b!=0);
                if(t==1) {
                    for(int k=0;k<block->ns;++k)set_union(entry,a->in[t][block->successors[k]]);
                    set_assign(a->out[t][b],entry);
                    for(int n=block->last;n>=block->first;--n)transfer(a,t,entry,&a->function->code[a->instructions.data[n]]);
                    if(!set_equal(entry,a->in[t][b]))changed=1;
                    set_assign(a->in[t][b],entry);
                }
                else {
                    if(t==0&&!b)for(int d=0;d<a->nd;++d)if(!a->definitions[d].number)entry.bits[d]=1;
                    if(t==0||b)for(int k=0;k<block->predecessors.count;++k) {
                        int p=block->predecessors.data[k];
                        if(a->blocks[p].reachable) {
                            if(t==0)set_union(entry,a->out[t][p]);
                            else set_intersect(entry,a->out[t][p]);
                        }
                    }
                    set_assign(a->in[t][b],entry);
                    for(int n=block->first;n<=block->last;++n)transfer(a,t,entry,&a->function->code[a->instructions.data[n]]);
                    if(!set_equal(entry,a->out[t][b]))changed=1;
                    set_assign(a->out[t][b],entry);
                }
                free(entry.bits);
            }
        }
        while(changed);
        for(int b=0;b<a->nb;++b)if(a->blocks[b].reachable) {
            Block *block=&a->blocks[b];
            Set state=set_copy(t==1?a->out[t][b]:a->in[t][b]);
            for(int n=t==1?block->last:block->first;t==1?n>=block->first:n<=block->last;t==1?--n:++n) {
                if(t==1) {
                    transfer(a,t,state,&a->function->code[a->instructions.data[n]]);
                    set_assign(a->before[t][n],state);
                }
                else {
                    set_assign(a->before[t][n],state);
                    transfer(a,t,state,&a->function->code[a->instructions.data[n]]);
                }
            }
            free(state.bits);
        }
    }
    a->after_live=allocate((size_t)ni*sizeof(Set));
    for(int i=0;i<ni;++i)a->after_live[i]=set_new(a->nv,0);
    for(int b=0;b<a->nb;++b)if(a->blocks[b].reachable) {
        Set live=set_copy(a->out[1][b]);
        for(int n=a->blocks[b].last;n>=a->blocks[b].first;--n) {
            set_assign(a->after_live[n],live);
            transfer(a,1,live,&a->function->code[a->instructions.data[n]]);
        }
        free(live.bits);
    }
}
