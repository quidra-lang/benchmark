#include "tac.h"
static const char *pass_names[]= {
    "constprop","copyprop","cse","dce","licm","unreachable"
};
static char *numbers(const unsigned char *bits,int n,const char *prefix,int offset) {
    char *out=allocate((size_t)n*40+2);
    int any=0;
    for(int i=0;i<n;++i)if(bits[i]) {
        size_t k=strlen(out);
        sprintf(out+k,"%s%s%d",any?",":"",prefix,i+offset);
        any=1;
    }
    if(!any)strcpy(out,"-");
    return out;
}
static char *move_numbers(Ints move) {
    char *out=allocate((size_t)move.count*40+2);
    for(int i=0;i<move.count;++i)sprintf(out+strlen(out),"%s#%d",i?",":"",move.data[i]+1);
    if(!move.count)strcpy(out,"-");
    return out;
}
static int instruction_count(Function *f) {
    int count=0;
    for(int i=0;i<f->count;++i)count+=f->code[i].kind>=0;
    return count;
}
static int propagation(Function *f,Analysis *a,int copies,Strings *records) {
    unsigned char *deleted=allocate((size_t)f->count);
    for(int i=0;i<a->instructions.count;++i)if(a->blocks[a->iblock[i]].reachable) {
        Instruction *s=&f->code[a->instructions.data[i]];
        char *operands[2];
        int nu=used(s,operands);
        for(int j=0;j<nu;++j) {
            char replacement[NAME]="";
            const char *v=operands[j];
            if(copies) {
                for(int c=0;c<a->nc;++c)if(a->before[3][i].bits[c]&&!strcmp(a->copies[c].x,v))strcpy(replacement,a->copies[c].y);
            }
            else {
                int found=0,valid=1;
                for(int d=0;d<a->nd;++d)if(a->before[0][i].bits[d]&&!strcmp(a->definitions[d].name,v)) {
                    Definition def=a->definitions[d];
                    if(!def.number) {
                        valid=0;
                        break;
                    }
                    Instruction *source=&a->function->code[def.line];
                    if(source->kind!=COPY||!constant(source->a)) {
                        valid=0;
                        break;
                    }
                    if(found&&strcmp(replacement,source->a)) {
                        valid=0;
                        break;
                    }
                    strcpy(replacement,source->a);
                    found=1;
                }
                if(!found||!valid)*replacement=0;
            }
            if(*replacement) {
                strings_format(records,"#%d: %s -> %s",i+1,v,replacement);
                strcpy(operands[j],replacement);
            }
        }
        if(!copies) {
            char before[TEXT];
            instruction_text(s,before);
            int folded=fold_instruction(s);
            if(folded<0) {
                deleted[a->instructions.data[i]]=1;
                strings_format(records,"#%d: delete %s",i+1,before);
            }
            else if(folded) {
                if(s->kind==GOTO)strings_format(records,"#%d: fold goto %s",i+1,s->target);
                else {
                    char text[TEXT];
                    instruction_text(s,text);
                    strings_format(records,"#%d: fold %s",i+1,text);
                }
            }
        }
    }
    filter_code(f,deleted);
    free(deleted);
    return records->count;
}
static void collect_sources(Analysis *a,int candidate,const Instruction *expression,unsigned char *sources) {
    int b=a->iblock[candidate];
    for(int n=candidate-1;n>=a->blocks[b].first;--n)if(expression_equal(&a->function->code[a->instructions.data[n]],expression)) {
        sources[n]=1;
        return;
    }
    Ints todo= {
        0
    };
    for(int i=0;i<a->blocks[b].predecessors.count;++i) {
        int p=a->blocks[b].predecessors.data[i];
        if(a->blocks[p].reachable)ints_add(&todo,p);
    }
    unsigned char *seen=allocate((size_t)a->nb);
    while(todo.count) {
        int p=todo.data[--todo.count];
        if(seen[p])continue;
        seen[p]=1;
        int found=0;
        for(int n=a->blocks[p].last;n>=a->blocks[p].first;--n)if(expression_equal(&a->function->code[a->instructions.data[n]],expression)) {
            sources[n]=1;
            found=1;
            break;
        }
        if(!found)for(int i=0;i<a->blocks[p].predecessors.count;++i) {
            int pred=a->blocks[p].predecessors.data[i];
            if(a->blocks[pred].reachable)ints_add(&todo,pred);
        }
    }
    free(seen);
    free(todo.data);
}
static int cse_pass(Function *f,Analysis *a,Strings *records) {
    int count=0,ni=a->instructions.count;
    unsigned char *done=allocate((size_t)a->ne);
    for(int i=0;i<ni;++i)if(a->blocks[a->iblock[i]].reachable) {
        Instruction *s=&a->function->code[a->instructions.data[i]];
        int e=expr_index(a,s);
        if(e<0||done[e]||!a->before[2][i].bits[e])continue;
        done[e]=1;
        unsigned char *candidates=allocate((size_t)ni),*sources=allocate((size_t)ni);
        for(int n=0;n<ni;++n)if(a->blocks[a->iblock[n]].reachable&&expr_index(a,&a->function->code[a->instructions.data[n]])==e&&a->before[2][n].bits[e]) {
            candidates[n]=1;
            ++count;
            collect_sources(a,n,s,sources);
        }
        for(int n=0;n<ni;++n)if(candidates[n])sources[n]=0;
        char temp[NAME];
        sprintf(temp,"_t%d",++f->temporary);
        char *src=numbers(sources,ni,"#",1),*dst=numbers(candidates,ni,"#",1);
        strings_format(records,"%s: %s sources=%s replaced=%s",a->expressions[e].text,temp,src,dst);
        free(src);
        free(dst);
        cse_rewrite(f,a,candidates,sources,temp);
        free(candidates);
        free(sources);
    }
    free(done);
    return count;
}
static int dce_pass(Function *f,Analysis *a,Strings *records) {
    unsigned char *deleted=allocate((size_t)f->count);
    char **notes=allocate((size_t)a->instructions.count*sizeof *notes);
    for(int b=0;b<a->nb;++b)if(a->blocks[b].reachable) {
        Set live=set_copy(a->out[1][b]);
        for(int n=a->blocks[b].last;n>=a->blocks[b].first;--n) {
            int line=a->instructions.data[n];
            Instruction *s=&f->code[line];
            int x=variable_index(a,defined(s)),erase=(s->kind==COPY&&!strcmp(s->dest,s->a))||((s->kind==COPY||s->kind==BIN||s->kind==LOAD)&&x>=0&&!live.bits[x]);
            char text[TEXT];
            instruction_text(s,text);
            if(erase) {
                deleted[line]=1;
                notes[n]=allocate(strlen(text)+40);
                sprintf(notes[n],"#%d: delete %s",n+1,text);
            }
            else {
                if(s->kind==CALL&&x>=0&&!live.bits[x]) {
                    notes[n]=allocate(strlen(text)+48);
                    sprintf(notes[n],"#%d: unused result %s",n+1,text);
                    *s->dest=0;
                }
                transfer(a,1,live,s);
            }
        }
        free(live.bits);
    }
    for(int n=0;n<a->instructions.count;++n)if(notes[n]) {
        strings_add(records,notes[n]);
        free(notes[n]);
    }
    free(notes);
    filter_code(f,deleted);
    free(deleted);
    return records->count;
}
static int loop_invariant(Analysis *a,Loop *loop,int n,const unsigned char *marked) {
    Instruction *s=&a->function->code[a->instructions.data[n]];
    if(s->kind!=COPY&&s->kind!=BIN&&s->kind!=LOAD)return 0;
    if(s->kind==LOAD)for(int j=0;j<a->instructions.count;++j)if(loop->blocks.bits[a->iblock[j]]) {
        Instruction *other=&a->function->code[a->instructions.data[j]];
        if(other->kind==CALL||(other->kind==STORE&&!strcmp(other->op,s->op)))return 0;
    }
    char *uses[2];
    Instruction copy=*s;
    int nu=used(&copy,uses);
    for(int j=0;j<nu;++j) {
        int inside=0,outside=0,last=-1;
        for(int d=0;d<a->nd;++d)if(a->before[0][n].bits[d]&&!strcmp(a->definitions[d].name,uses[j])) {
            int def=a->definitions[d].number-1;
            if(def<0||!loop->blocks.bits[a->iblock[def]])outside=1;
            else {
                ++inside;
                last=def;
            }
        }
        if(inside&&(outside||inside!=1||!marked[last]))return 0;
    }
    return 1;
}
static int licm_pass(Function *f,Analysis *a,Strings *records) {
    int *order=allocate((size_t)a->nl*sizeof *order);
    for(int i=0;i<a->nl;++i)order[i]=i;
    for(int i=0;i<a->nl;++i)for(int j=i+1;j<a->nl;++j)if(set_count(a->loops[order[j]].blocks)<set_count(a->loops[order[i]].blocks)||(set_count(a->loops[order[j]].blocks)==set_count(a->loops[order[i]].blocks)&&order[j]<order[i])) {
        int t=order[i];
        order[i]=order[j];
        order[j]=t;
    }
    int changes=0;
    for(int index=0;index<a->nl&&!changes;++index) {
        int li=order[index];
        Loop *l=&a->loops[li];
        unsigned char *marked=allocate((size_t)a->instructions.count),*moved=allocate((size_t)a->instructions.count);
        Ints marks= {
            0
        },move= {
            0
        };
        int changed;
        do {
            changed=0;
            for(int n=0;n<a->instructions.count;++n)if(l->blocks.bits[a->iblock[n]]&&!marked[n]&&loop_invariant(a,l,n,marked)) {
                marked[n]=1;
                ints_add(&marks,n);
                changed=1;
            }
        }
        while(changed);
        for(int i=0;i<marks.count;++i) {
            int n=marks.data[i],b=a->iblock[n];
            Instruction *s=&a->function->code[a->instructions.data[n]];
            int x=variable_index(a,s->dest),definitions=0;
            for(int j=0;j<a->instructions.count;++j)if(l->blocks.bits[a->iblock[j]]&&!strcmp(defined(&a->function->code[a->instructions.data[j]]),s->dest))++definitions;
            if(definitions!=1||a->in[1][l->header].bits[x])continue;
            int all_exits=1,outside_live=0;
            for(int j=0;j<a->nb;++j) {
                if(l->exits.bits[j]&&!a->blocks[j].dom.bits[b])all_exits=0;
                if(l->outside.bits[j]&&a->in[1][j].bits[x])outside_live=1;
            }
            int danger=s->kind==LOAD||(s->kind==BIN&&(!strcmp(s->op,"/")||!strcmp(s->op,"%"))&&(!constant(s->b)||!strtoll(s->b,NULL,10)));
            if(!all_exits&&(danger||outside_live))continue;
            Instruction copy=*s;
            char *uses[2];
            int nu=used(&copy,uses),valid=1;
            for(int j=0;j<nu;++j)for(int d=0;d<a->nd;++d)if(a->before[0][n].bits[d]&&!strcmp(a->definitions[d].name,uses[j])) {
                int def=a->definitions[d].number-1;
                if(def>=0&&l->blocks.bits[a->iblock[def]]&&!moved[def])valid=0;
            }
            if(valid) {
                moved[n]=1;
                ints_add(&move,n);
            }
        }
        if(move.count) {
            Ints q= {
                0
            };
            Block *h=&a->blocks[l->header];
            for(int j=0;j<h->predecessors.count;++j) {
                int p=h->predecessors.data[j];
                if(!l->blocks.bits[p])ints_add(&q,p);
            }
            int pre=l->header&&q.count==1&&a->blocks[q.data[0]].ns==1?q.data[0]:-1;
            char label[NAME]="";
            if(pre<0)sprintf(label,"_p%d",++f->preheader);
            char *list=move_numbers(move);
            if(pre>=0)strings_format(records,"B%d: hoist %s to B%d",l->header+1,list,pre+1);
            else strings_format(records,"B%d: hoist %s to new %s",l->header+1,list,label);
            free(list);
            hoist_code(f,a,li,move,pre,label);
            changes=move.count;
            free(q.data);
        }
        free(marks.data);
        free(move.data);
        free(marked);
        free(moved);
    }
    free(order);
    return changes;
}
static int unreachable_pass(Function *f,Analysis *a,Strings *records) {
    unsigned char *deleted=allocate((size_t)f->count);
    for(int b=0;b<a->nb;++b)if(!a->blocks[b].reachable) {
        strings_format(records,"remove block B%d",b+1);
        for(int line=a->blocks[b].startline;line<=a->blocks[b].endline;++line)deleted[line]=1;
    }
    filter_code(f,deleted);
    free(deleted);
    deleted=allocate((size_t)f->count);
    for(int line=0;line<f->count;++line)if(f->code[line].kind==GOTO||f->code[line].kind==IF)for(int next=line+1;next<f->count&&f->code[next].kind<0;++next)if(!strcmp(f->code[line].target,f->code[next].target)) {
        deleted[line]=1;
        strings_format(records,"remove jump #%d",f->code[line].number);
        break;
    }
    filter_code(f,deleted);
    free(deleted);
    deleted=allocate((size_t)f->count);
    for(int line=0;line<f->count;++line)if(f->code[line].kind<0) {
        int targeted=0;
        for(int i=0;i<f->count;++i)if((f->code[i].kind==GOTO||f->code[i].kind==IF)&&!strcmp(f->code[i].target,f->code[line].target))targeted=1;
        if(!targeted) {
            deleted[line]=1;
            strings_format(records,"remove label %s",f->code[line].target);
        }
    }
    filter_code(f,deleted);
    free(deleted);
    return records->count;
}
static int apply_pass(Function *f,int pass,Strings *records) {
    Function snapshot=function_copy(f);
    Analysis a=analyze(&snapshot);
    for(int i=0;i<f->count;++i)f->code[i].number=snapshot.code[i].number;
    int n=pass==0?propagation(f,&a,0,records):pass==1?propagation(f,&a,1,records):pass==2?cse_pass(f,&a,records):pass==3?dce_pass(f,&a,records):pass==4?licm_pass(f,&a,records):unreachable_pass(f,&a,records);
    analysis_free(&a);
    function_free(&snapshot);
    return n;
}
static void print_block_set(FILE *f,Set s) {
    char *text=numbers(s.bits,s.size,"B",1);
    fputs(text,f);
    free(text);
}
static void print_int_blocks(FILE *f,Ints s) {
    if(!s.count)fputc('-',f);
    for(int i=0;i<s.count;++i)fprintf(f,"%sB%d",i?",":"",s.data[i]+1);
}
static void print_data_set(FILE *f,Analysis *a,int type,Set s) {
    int any=0;
    for(int i=0;i<s.size;++i)if(s.bits[i]) {
        if(any)fputc(',',f);
        if(type==0)fprintf(f,"%s:%d",a->definitions[i].name,a->definitions[i].number);
        else fputs(type==1?a->variables[i]:a->expressions[i].text,f);
        any=1;
    }
    if(!any)fputc('-',f);
}
static void tree(FILE *f,Analysis *a,int b,int depth) {
    fprintf(f,"%*sB%d\n",2*depth,"",b+1);
    for(int i=0;i<a->nb;++i)if(a->blocks[i].reachable&&a->blocks[i].idom==b)tree(f,a,i,depth+1);
}
static void function_analysis(FILE *f,Function *fn,const char *type) {
    Analysis a=analyze(fn);
    fprintf(f,"== %s (%s) ==\ncode:\n",fn->name,type);
    int n=0;
    for(int line=0;line<fn->count;++line) {
        Instruction *s=&fn->code[line];
        char text[TEXT];
        instruction_text(s,text);
        if(s->kind<0) {
            fprintf(f,"%s\n",text);
            continue;
        }
        fprintf(f,"  #%d %s",n+1,text);
        if(a.blocks[a.iblock[n]].reachable) {
            char *uses[2];
            int nu=used(s,uses),any=0;
            for(int j=0;j<nu;++j) {
                if(j&&!strcmp(uses[j],uses[0]))continue;
                fprintf(f,"%s%s:",any?" ":" | ",uses[j]);
                int found=0;
                for(int d=0;d<a.nd;++d)if(a.before[0][n].bits[d]&&!strcmp(a.definitions[d].name,uses[j])) {
                    fprintf(f,"%s%d",found?",":"",a.definitions[d].number);
                    found=1;
                }
                if(!found)fputc('-',f);
                any=1;
            }
        }
        fputc('\n',f);
        ++n;
    }
    fprintf(f,"blocks: %d\n",a.nb);
    for(int b=0;b<a.nb;++b) {
        Block *block=&a.blocks[b];
        fprintf(f,"B%d %d-%d labels=",b+1,block->first+1,block->last+1);
        int any=0;
        for(int l=block->startline;l<a.instructions.data[block->first];++l) {
            fprintf(f,"%s%s",any?",":"",fn->code[l].target);
            any=1;
        }
        if(!any)fputc('-',f);
        fputs(" preds=",f);
        print_int_blocks(f,block->predecessors);
        fputs(" succs=",f);
        Ints succ= {
            .data=block->successors,.count=block->ns
        };
        print_int_blocks(f,succ);
        fputc('\n',f);
    }
    Set missing=set_new(a.nb,0);
    for(int b=0;b<a.nb;++b)missing.bits[b]=!a.blocks[b].reachable;
    fputs("unreachable: ",f);
    print_block_set(f,missing);
    free(missing.bits);
    fputs("\norder: ",f);
    print_int_blocks(f,a.order);
    fputs("\ndominators:\n",f);
    for(int b=0;b<a.nb;++b)if(a.blocks[b].reachable) {
        fprintf(f,"B%d idom=",b+1);
        if(a.blocks[b].idom<0)fputc('-',f);
        else fprintf(f,"B%d",a.blocks[b].idom+1);
        fputs(" dom=",f);
        print_block_set(f,a.blocks[b].dom);
        fputc('\n',f);
    }
    fputs("dominator tree:\n",f);
    if(a.nb)tree(f,&a,0,0);
    fprintf(f,"loops: %d\n",a.nl);
    for(int i=0;i<a.nl;++i) {
        Loop *l=&a.loops[i];
        fprintf(f,"header=B%d latches=",l->header+1);
        print_block_set(f,l->latches);
        fprintf(f," depth=%d blocks=",l->depth);
        print_block_set(f,l->blocks);
        fputs(" exits=",f);
        print_block_set(f,l->exits);
        fputc('\n',f);
    }
    static const char *names[]= {
        "reaching definitions","liveness","available expressions"
    };
    for(int t=0;t<3;++t) {
        fprintf(f,"%s: iterations=%d\n",names[t],a.iterations[t]);
        for(int b=0;b<a.nb;++b)if(a.blocks[b].reachable) {
            fprintf(f,"B%d in=",b+1);
            print_data_set(f,&a,t,a.in[t][b]);
            fputs(" out=",f);
            print_data_set(f,&a,t,a.out[t][b]);
            fputc('\n',f);
        }
    }
    analysis_free(&a);
}
static int function_index(Program *p,const char *name) {
    for(int i=0;i<p->count;++i)if(!strcmp(p->functions[i].name,name))return i;
    return -1;
}
static unsigned char *call_graph(Program *p,FILE *f) {
    int n=p->count;
    unsigned char *edges=allocate((size_t)n*n),*closure=allocate((size_t)n*n),*reachable=allocate((size_t)n);
    for(int i=0;i<n;++i)for(int l=0;l<p->functions[i].count;++l)if(p->functions[i].code[l].kind==CALL)edges[i*n+function_index(p,p->functions[i].code[l].target)]=1;
    memcpy(closure,edges,(size_t)n*n);
    for(int k=0;k<n;++k)for(int i=0;i<n;++i)for(int j=0;j<n;++j)closure[i*n+j]|=closure[i*n+k]&&closure[k*n+j];
    int main=function_index(p,"main");
    for(int i=0;i<n;++i)reachable[i]=i==main||closure[main*n+i];
    if(f) {
        for(int i=0;i<n;++i) {
            fprintf(f,"%s -> ",p->functions[i].name);
            int any=0;
            for(int j=0;j<n;++j)if(edges[i*n+j]) {
                fprintf(f,"%s%s",any?",":"",p->functions[j].name);
                any=1;
            }
            if(!any)fputc('-',f);
            fprintf(f,"%s\n",closure[i*n+i]?" (recursive)":"");
        }
        fputs("unreachable functions: ",f);
        int any=0;
        for(int i=0;i<n;++i)if(!reachable[i]) {
            fprintf(f,"%s%s",any?",":"",p->functions[i].name);
            any=1;
        }
        if(!any)fputc('-',f);
        fputc('\n',f);
    }
    free(edges);
    free(closure);
    return reachable;
}
static void rename_variable(char *v,Analysis *a,Allocation *g) {
    int i=variable_index(a,v);
    if(i>=0&&g->colors[i]>=0)sprintf(v,"R%d",g->colors[i]);
}
static void register_report(FILE *f,Function *original,Function *allocated,int registers) {
    Analysis a=analyze(original);
    Allocation g=allocate_registers(&a,registers);
    int n=g.nodes;
    fprintf(f,"== %s ==\nnodes=%d edges=%d registers=%d\n",original->name,n,g.edge_count,registers);
    for(int x=0;x<n;++x) {
        int degree=0;
        for(int y=0;y<n;++y)degree+=g.edges[x*n+y]!=0;
        char *cost=big_string(&g.cost[x]);
        fprintf(f,"%s degree=%d cost=%s neighbors=",a.variables[x],degree,cost);
        free(cost);
        int any=0;
        for(int y=0;y<n;++y)if(g.edges[x*n+y]) {
            fprintf(f,"%s%s",any?",":"",a.variables[y]);
            any=1;
        }
        if(!any)fputc('-',f);
        fputc('\n',f);
    }
    fputs("simplify: ",f);
    for(int i=0;i<n;++i)fprintf(f,"%s%s",i?",":"",a.variables[g.order[i]]);
    if(!n)fputc('-',f);
    fputs("\npotential spills: ",f);
    int any=0;
    for(int i=0;i<n;++i) {
        int x=g.order[i];
        if(g.potential_degree[x]) {
            char *cost=big_string(&g.cost[x]);
            fprintf(f,"%s%s(%s/%d)",any?",":"",a.variables[x],cost,g.potential_degree[x]);
            free(cost);
            any=1;
        }
    }
    if(!any)fputc('-',f);
    fputc('\n',f);
    int spilled=0,used_colors[16]= {
        0
    };
    for(int x=0;x<n;++x) {
        fprintf(f,"%s -> ",a.variables[x]);
        if(g.colors[x]<0) {
            fputs("spill\n",f);
            ++spilled;
        }
        else {
            fprintf(f,"R%d\n",g.colors[x]);
            used_colors[g.colors[x]]=1;
        }
    }
    int spill_uses=0,spill_defs=0,pressure=0,moves=0;
    for(int i=0;i<a.instructions.count;++i)if(a.blocks[a.iblock[i]].reachable) {
        int before=set_count(a.before[1][i]),after=set_count(a.after_live[i]);
        if(before>pressure)pressure=before;
        if(after>pressure)pressure=after;
    }
    for(int i=0;i<allocated->np;++i) {
        int x=variable_index(&a,allocated->params[i]);
        spill_defs+=x>=0&&g.colors[x]<0;
        rename_variable(allocated->params[i],&a,&g);
    }
    unsigned char *deleted=allocate((size_t)allocated->count);
    for(int l=0;l<allocated->count;++l) {
        Instruction *s=&allocated->code[l];
        int x=variable_index(&a,defined(s));
        spill_defs+=x>=0&&g.colors[x]<0;
        char *uses[2];
        int nu=used(s,uses);
        for(int j=0;j<nu;++j) {
            int v=variable_index(&a,uses[j]);
            spill_uses+=v>=0&&g.colors[v]<0;
            rename_variable(uses[j],&a,&g);
        }
        if(*defined(s))rename_variable(s->dest,&a,&g);
        if(s->kind==COPY&&!strcmp(s->dest,s->a)) {
            deleted[l]=1;
            ++moves;
        }
    }
    filter_code(allocated,deleted);
    free(deleted);
    int used=0;
    for(int c=0;c<registers;++c)used+=used_colors[c];
    fprintf(f,"summary: pressure=%d used=%d spilled=%d moves=%d spill_uses=%d spill_defs=%d\n",pressure,used,spilled,moves,spill_uses,spill_defs);
    write_function(f,allocated);
    allocation_free(&g);
    analysis_free(&a);
}
typedef struct {
    char name[NAME];
    long long value;
}
Variable;
typedef struct {
    Program *program;
    long long **arrays;
    long long *input;
    int position;
    Ints output;
    long long *steps,*calls,kinds[KIND_COUNT];
}
Execution;
static long long value(Variable *vars,int n,const char *operand) {
    if(constant(operand))return strtoll(operand,NULL,10);
    for(int i=0;i<n;++i)if(!strcmp(vars[i].name,operand))return vars[i].value;
    return 0;
}
static void assign(Variable **vars,int *n,const char *name,long long v) {
    for(int i=0;i<*n;++i)if(!strcmp((*vars)[i].name,name)) {
        (*vars)[i].value=v;
        return;
    }
    *vars=resize(*vars,(size_t)(*n+1)*sizeof **vars);
    strcpy((*vars)[*n].name,name);
    (*vars)[(*n)++].value=v;
}
static int array_index(Program *p,const char *name) {
    for(int i=0;i<p->na;++i)if(!strcmp(p->arrays[i].name,name))return i;
    return -1;
}
static long long execute_function(Execution *e,int fi,long long *args) {
    Function *f=&e->program->functions[fi];
    Variable *vars=NULL;
    int nv=0;
    long long *pushed=NULL;
    int np=0;
    long long result=0;
    ++e->calls[fi];
    for(int i=0;i<f->np;++i)assign(&vars,&nv,f->params[i],args[i]);
    for(int line=0;line<f->count;++line) {
        Instruction s=f->code[line];
        if(s.kind<0)continue;
        ++e->steps[fi];
        ++e->kinds[s.kind];
        long long a=*s.a?value(vars,nv,s.a):0,b=*s.b?value(vars,nv,s.b):0;
        switch(s.kind) {
            case COPY:assign(&vars,&nv,s.dest,a);
            break;
            case BIN:assign(&vars,&nv,s.dest,operation(s.op,a,b));
            break;
            case LOAD:assign(&vars,&nv,s.dest,e->arrays[array_index(e->program,s.op)][a]);
            break;
            case STORE:e->arrays[array_index(e->program,s.op)][a]=b;
            break;
            case GOTO:case IF:if(s.kind==GOTO||operation(s.op,a,b)) {
                for(int j=0;j<f->count;++j)if(f->code[j].kind<0&&!strcmp(f->code[j].target,s.target)) {
                    line=j;
                    break;
                }
            }
            break;
            case PARAM:pushed=resize(pushed,(size_t)(np+1)*sizeof *pushed);
            pushed[np++]=a;
            break;
            case CALL: {
                long long returned=execute_function(e,function_index(e->program,s.target),s.count?pushed+np-s.count:NULL);
                np-=s.count;
                if(*s.dest)assign(&vars,&nv,s.dest,returned);
                break;
            }
            case RETURN:result=a;
            goto done;
            case READ:assign(&vars,&nv,s.dest,e->input[e->position++]);
            break;
            case PRINT:ints_add(&e->output,(int)a);
            break;
        }
    }
    done:free(vars);
    free(pushed);
    return result;
}
static Execution execute(Program *p,long long *input) {
    Execution e= {
        .program=p,.input=input
    };
    e.steps=allocate((size_t)p->count*sizeof *e.steps);
    e.calls=allocate((size_t)p->count*sizeof *e.calls);
    e.arrays=allocate((size_t)p->na*sizeof *e.arrays);
    for(int i=0;i<p->na;++i)e.arrays[i]=allocate((size_t)p->arrays[i].size*sizeof **e.arrays);
    execute_function(&e,function_index(p,"main"),NULL);
    for(int i=0;i<p->na;++i)free(e.arrays[i]);
    free(e.arrays);
    return e;
}
static long long sum(long long *v,int n) {
    long long s=0;
    for(int i=0;i<n;++i)s+=v[i];
    return s;
}
static void compare_runs(FILE *f,Program *original,Program *optimized,Program *allocated) {
    FILE *input=fopen("input/input.txt","r");
    if(!input)exit(EXIT_FAILURE);
    int runs;
    fscanf(input,"%d",&runs);
    Program *programs[]= {
        original,optimized,allocated
    };
    const char *names[]= {
        "original","optimized","allocated"
    };
    long long *profile[3],*calls=allocate((size_t)original->count*sizeof *calls),kinds[3][KIND_COUNT]= {
        {
            0
        }
    },total[3]= {
        0
    };
    for(int p=0;p<3;++p)profile[p]=allocate((size_t)original->count*sizeof **profile);
    int same=0;
    for(int run=1;run<=runs;++run) {
        int m;
        fscanf(input,"%d",&m);
        long long *values=allocate((size_t)m*sizeof *values);
        for(int i=0;i<m;++i)fscanf(input,"%lld",&values[i]);
        fprintf(f,"run %d: inputs=%d\n",run,m);
        Execution result[3];
        for(int p=0;p<3;++p) {
            result[p]=execute(programs[p],values);
            long long steps=sum(result[p].steps,programs[p]->count),ncalls=sum(result[p].calls,programs[p]->count);
            total[p]+=steps;
            fprintf(f,"  %s: steps=%lld calls=%lld output=",names[p],steps,ncalls);
            if(!result[p].output.count)fputc('-',f);
            for(int i=0;i<result[p].output.count;++i)fprintf(f,"%s%d",i?",":"",result[p].output.data[i]);
            fputc('\n',f);
            for(int i=0;i<original->count;++i) {
                profile[p][i]+=result[p].steps[i];
                if(!p)calls[i]+=result[p].calls[i];
            }
            for(int k=0;k<KIND_COUNT;++k)kinds[p][k]+=result[p].kinds[k];
        }
        int equal=1;
        for(int p=1;p<3;++p)if(result[p].output.count!=result[0].output.count||(result[0].output.count&&memcmp(result[p].output.data,result[0].output.data,(size_t)result[0].output.count*sizeof(int))))equal=0;
        fprintf(f,"  result: %s\n",equal?"same":"different");
        same+=equal;
        for(int p=0;p<3;++p) {
            free(result[p].steps);
            free(result[p].calls);
            free(result[p].output.data);
        }
        free(values);
    }
    fputs("== profile ==\n",f);
    for(int i=0;i<original->count;++i)fprintf(f,"%s: calls=%lld original=%lld optimized=%lld allocated=%lld\n",original->functions[i].name,calls[i],profile[0][i],profile[1][i],profile[2][i]);
    int static_counts[2][KIND_COUNT]= {
        {
            0
        }
    },counts[2]= {
        0
    };
    for(int p=0;p<2;++p)for(int i=0;i<programs[p]->count;++i)if(!programs[p]->functions[i].removed)for(int l=0;l<programs[p]->functions[i].count;++l) {
        int k=programs[p]->functions[i].code[l].kind;
        if(k>=0) {
            ++counts[p];
            ++static_counts[p][k];
        }
    }
    fprintf(f,"== summary ==\nruns=%d same=%d different=%d\ninstructions: original=%d optimized=%d\nkinds: ",runs,same,runs-same,counts[0],counts[1]);
    for(int k=0;k<KIND_COUNT;++k)fprintf(f,"%s%s=%d->%d",k?" ":"",kind_names[k],static_counts[0][k],static_counts[1][k]);
    fprintf(f,"\nsteps: original=%lld optimized=%lld allocated=%lld\n",total[0],total[1],total[2]);
    for(int p=0;p<3;++p) {
        fprintf(f,"dynamic %s: ",names[p]);
        for(int k=0;k<KIND_COUNT;++k)fprintf(f,"%s%s=%lld",k?" ":"",kind_names[k],kinds[p][k]);
        fputc('\n',f);
        free(profile[p]);
    }
    free(calls);
    fclose(input);
}
int main(void) {
    Program original=read_program("input/program.tac"),optimized=program_copy(&original);
    FILE *params=fopen("input/params.txt","r");
    if(!params)return EXIT_FAILURE;
    char line[256],word[64];
    int registers,round_limit,enabled[6]= {
        0
    };
    fgets(line,sizeof line,params);
    sscanf(line,"registers %d",&registers);
    fgets(line,sizeof line,params);
    char *token=strtok(line," \n");
    while((token=strtok(NULL," \n")))for(int p=0;p<6;++p)if(!strcmp(token,pass_names[p]))enabled[p]=1;
    fscanf(params,"%63s %d",word,&round_limit);
    fclose(params);
    FILE *analysis=fopen("output/analysis.txt","w"),*passes=fopen("output/passes.txt","w"),*out=fopen("output/optimized.tac","w"),*regs=fopen("output/regalloc.txt","w"),*comparison=fopen("output/comparison.txt","w");
    if(!analysis||!passes||!out||!regs||!comparison)return EXIT_FAILURE;
    fputs("== call graph (original) ==\n",analysis);
    free(call_graph(&original,analysis));
    for(int i=0;i<original.count;++i)function_analysis(analysis,&original.functions[i],"original");
    long long totals[6]= {
        0
    };
    for(int i=0;i<optimized.count;++i) {
        Function *fn=&optimized.functions[i];
        int before=instruction_count(fn),round=0;
        fprintf(passes,"== %s ==\n",fn->name);
        for(round=1;round<=round_limit;++round) {
            Strings records[6]= {
                {
                    0
                }
            };
            int changes[6]= {
                0
            },any=0;
            for(int p=0;p<6;++p)if(enabled[p]) {
                changes[p]=apply_pass(fn,p,&records[p]);
                totals[p]+=changes[p];
                any|=changes[p]!=0;
            }
            fprintf(passes,"round %d:",round);
            for(int p=0;p<6;++p)if(enabled[p])fprintf(passes," %s=%d",pass_names[p],changes[p]);
            fputc('\n',passes);
            for(int p=0;p<6;++p) {
                for(int r=0;r<records[p].count;++r)fprintf(passes,"  %s %s\n",pass_names[p],records[p].data[r]);
                strings_free(&records[p]);
            }
            if(!any)break;
        }
        if(round>round_limit)round=round_limit;
        fprintf(passes,"result: rounds=%d instructions=%d->%d\n",round,before,instruction_count(fn));
    }
    fputs("== call graph (optimized) ==\n",analysis);
    unsigned char *reachable=call_graph(&optimized,analysis);
    fputs("== program ==\nremoved functions: ",passes);
    int any=0;
    for(int i=0;i<optimized.count;++i)if(enabled[5]&&!reachable[i]) {
        optimized.functions[i].removed=1;
        fprintf(passes,"%s%s",any?",":"",optimized.functions[i].name);
        any=1;
    }
    if(!any)fputc('-',passes);
    fputs("\n== total ==\n",passes);
    any=0;
    for(int p=0;p<6;++p)if(enabled[p]) {
        fprintf(passes,"%s%s=%lld",any?" ":"",pass_names[p],totals[p]);
        any=1;
    }
    fputc('\n',passes);
    free(reachable);
    for(int i=0;i<optimized.count;++i)if(!optimized.functions[i].removed)function_analysis(analysis,&optimized.functions[i],"optimized");
    write_program(out,&optimized);
    Program allocated=program_copy(&optimized);
    for(int i=0;i<optimized.count;++i)if(!optimized.functions[i].removed)register_report(regs,&optimized.functions[i],&allocated.functions[i],registers);
    compare_runs(comparison,&original,&optimized,&allocated);
    fclose(analysis);
    fclose(passes);
    fclose(out);
    fclose(regs);
    fclose(comparison);
    program_free(&original);
    program_free(&optimized);
    program_free(&allocated);
    return 0;
}
