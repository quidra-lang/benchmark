#include "tac.h"
static int target_block(Analysis *a,const char *label) {
    for(int i=0;i<a->function->count;++i)if(a->function->code[i].kind<0&&!strcmp(a->function->code[i].target,label))return a->lineblock[i];
    return -1;
}
static void visit(Analysis *a,int b) {
    a->blocks[b].reachable=1;
    for(int i=0;i<a->blocks[b].ns;++i) {
        int s=a->blocks[b].successors[i];
        if(!a->blocks[s].reachable)visit(a,s);
    }
    ints_add(&a->postorder,b);
}
static void successors(Analysis *a) {
    for(int b=0;b<a->nb;++b) {
        Block *block=&a->blocks[b];
        Instruction *last=&a->function->code[a->instructions.data[block->last]];
        if(last->kind==GOTO)block->successors[block->ns++]=target_block(a,last->target);
        else if(last->kind==IF) {
            int t=target_block(a,last->target);
            block->successors[block->ns++]=b+1;
            if(t!=b+1)block->successors[block->ns++]=t;
        }
        else if(last->kind!=RETURN&&b+1<a->nb)block->successors[block->ns++]=b+1;
        for(int i=0;i<block->ns;++i)ints_add(&a->blocks[block->successors[i]].predecessors,b);
    }
}
static void dominance(Analysis *a) {
    for(int b=0;b<a->nb;++b) {
        Block *block=&a->blocks[b];
        block->idom=-1;
        block->dom=set_new(a->nb,0);
        if(!block->reachable)continue;
        if(!b)block->dom.bits[0]=1;
        else for(int k=0;k<a->nb;++k)block->dom.bits[k]=a->blocks[k].reachable;
    }
    int changed;
    do {
        changed=0;
        for(int i=1;i<a->order.count;++i) {
            int b=a->order.data[i];
            Set dom=set_new(a->nb,1);
            for(int j=0;j<a->blocks[b].predecessors.count;++j) {
                int p=a->blocks[b].predecessors.data[j];
                if(a->blocks[p].reachable)set_intersect(dom,a->blocks[p].dom);
            }
            dom.bits[b]=1;
            if(!set_equal(dom,a->blocks[b].dom)) {
                changed=1;
                set_assign(a->blocks[b].dom,dom);
            }
            free(dom.bits);
        }
    }
    while(changed);
    for(int b=1;b<a->nb;++b)if(a->blocks[b].reachable) {
        int depth=-1;
        for(int d=0;d<a->nb;++d)if(d!=b&&a->blocks[b].dom.bits[d]) {
            int n=set_count(a->blocks[d].dom);
            if(n>depth) {
                depth=n;
                a->blocks[b].idom=d;
            }
        }
    }
}
static void loops(Analysis *a) {
    for(int h=0;h<a->nb;++h)if(a->blocks[h].reachable) {
        Set latch=set_new(a->nb,0);
        for(int t=0;t<a->nb;++t)if(a->blocks[t].reachable&&a->blocks[t].dom.bits[h])for(int i=0;i<a->blocks[t].ns;++i)if(a->blocks[t].successors[i]==h)latch.bits[t]=1;
        if(!set_count(latch)) {
            free(latch.bits);
            continue;
        }
        a->loops=resize(a->loops,(size_t)(a->nl+1)*sizeof *a->loops);
        Loop *l=&a->loops[a->nl++];
        memset(l,0,sizeof *l);
        l->header=h;
        l->latches=latch;
        l->blocks=set_copy(latch);
        l->blocks.bits[h]=1;
        l->exits=set_new(a->nb,0);
        l->outside=set_new(a->nb,0);
        Ints todo= {
            0
        };
        for(int i=0;i<a->nb;++i)if(latch.bits[i]&&i!=h)ints_add(&todo,i);
        while(todo.count) {
            int b=todo.data[--todo.count];
            for(int i=0;i<a->blocks[b].predecessors.count;++i) {
                int p=a->blocks[b].predecessors.data[i];
                if(a->blocks[p].reachable&&!l->blocks.bits[p]) {
                    l->blocks.bits[p]=1;
                    if(p!=h)ints_add(&todo,p);
                }
            }
        }
        free(todo.data);
        for(int b=0;b<a->nb;++b)if(l->blocks.bits[b]) {
            Instruction *last=&a->function->code[a->instructions.data[a->blocks[b].last]];
            if(last->kind==RETURN)l->exits.bits[b]=1;
            for(int i=0;i<a->blocks[b].ns;++i) {
                int s=a->blocks[b].successors[i];
                if(!l->blocks.bits[s]) {
                    l->exits.bits[b]=1;
                    l->outside.bits[s]=1;
                }
            }
        }
    }
    for(int i=0;i<a->nl;++i)for(int j=0;j<a->nl;++j)a->loops[i].depth+=a->loops[j].blocks.bits[a->loops[i].header]!=0;
    for(int b=0;b<a->nb;++b)for(int i=0;i<a->nl;++i)a->blocks[b].depth+=a->loops[i].blocks.bits[b]!=0;
}
Analysis analyze(Function *f) {
    Analysis a= {
        .function=f
    };
    int number=0;
    for(int i=0;i<f->count;++i)if(f->code[i].kind>=0) {
        f->code[i].number=++number;
        ints_add(&a.instructions,i);
    }
    a.iblock=allocate((size_t)number*sizeof *a.iblock);
    a.lineblock=allocate((size_t)f->count*sizeof *a.lineblock);
    int start=0;
    for(int n=0;n<number;++n) {
        int line=a.instructions.data[n],leader=!n||f->code[line-1].kind<0;
        int prev=n?f->code[a.instructions.data[n-1]].kind:-1;
        if(prev==GOTO||prev==IF||prev==RETURN)leader=1;
        if(leader) {
            if(a.nb) {
                a.blocks[a.nb-1].last=n-1;
                a.blocks[a.nb-1].endline=a.instructions.data[n-1];
            }
            a.blocks=resize(a.blocks,(size_t)(a.nb+1)*sizeof *a.blocks);
            Block *b=&a.blocks[a.nb++];
            memset(b,0,sizeof *b);
            b->first=n;
            b->startline=start;
        }
        a.iblock[n]=a.nb-1;
        for(int k=start;k<=line;++k)a.lineblock[k]=a.nb-1;
        start=line+1;
    }
    if(a.nb) {
        a.blocks[a.nb-1].last=number-1;
        a.blocks[a.nb-1].endline=f->count-1;
        successors(&a);
        visit(&a,0);
        for(int i=a.postorder.count-1;i>=0;--i)ints_add(&a.order,a.postorder.data[i]);
        dominance(&a);
        loops(&a);
    }
    solve_dataflow(&a);
    return a;
}
void analysis_free(Analysis *a) {
    for(int b=0;b<a->nb;++b) {
        free(a->blocks[b].predecessors.data);
        free(a->blocks[b].dom.bits);
    }
    for(int l=0;l<a->nl;++l) {
        free(a->loops[l].blocks.bits);
        free(a->loops[l].latches.bits);
        free(a->loops[l].exits.bits);
        free(a->loops[l].outside.bits);
    }
    for(int t=0;t<4;++t) {
        for(int b=0;b<a->nb;++b) {
            free(a->in[t][b].bits);
            free(a->out[t][b].bits);
        }
        for(int i=0;i<a->instructions.count;++i)free(a->before[t][i].bits);
        free(a->in[t]);
        free(a->out[t]);
        free(a->before[t]);
    }
    for(int i=0;i<a->instructions.count;++i)free(a->after_live[i].bits);
    free(a->after_live);
    free(a->instructions.data);
    free(a->postorder.data);
    free(a->order.data);
    free(a->blocks);
    free(a->iblock);
    free(a->lineblock);
    free(a->loops);
    free(a->variables);
    free(a->definitions);
    free(a->expressions);
    free(a->copies);
}
