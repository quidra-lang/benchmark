#include "tac.h"
static void big_room(Big *a,int n) {
    if(n>a->capacity) {
        a->capacity=n*2;
        a->digits=resize(a->digits,(size_t)a->capacity*sizeof *a->digits);
    }
}
static void big_add(Big *a,const Big *b) {
    int n=a->length>b->length?a->length:b->length;
    big_room(a,n+1);
    uint64_t carry=0;
    for(int i=0;i<n;++i) {
        uint64_t value=carry+(i<a->length?a->digits[i]:0)+(i<b->length?b->digits[i]:0);
        a->digits[i]=(uint32_t)(value%1000000000);
        carry=value/1000000000;
    }
    a->length=n;
    if(carry)a->digits[a->length++]=(uint32_t)carry;
}
static void big_multiply(Big *a,unsigned factor) {
    uint64_t carry=0;
    big_room(a,a->length+2);
    for(int i=0;i<a->length;++i) {
        uint64_t value=(uint64_t)a->digits[i]*factor+carry;
        a->digits[i]=(uint32_t)(value%1000000000);
        carry=value/1000000000;
    }
    while(carry) {
        a->digits[a->length++]=(uint32_t)(carry%1000000000);
        carry/=1000000000;
    }
}
static Big big_copy(const Big *a) {
    Big b= {
        0
    };
    big_room(&b,a->length);
    b.length=a->length;
    memcpy(b.digits,a->digits,(size_t)a->length*sizeof *a->digits);
    return b;
}
static int fraction_less(const Big *a,unsigned ad,const Big *b,unsigned bd) {
    Big left=big_copy(a),right=big_copy(b);
    big_multiply(&left,bd);
    big_multiply(&right,ad);
    int result=0;
    if(left.length!=right.length)result=left.length<right.length;
    else for(int i=left.length-1;i>=0;--i)if(left.digits[i]!=right.digits[i]) {
        result=left.digits[i]<right.digits[i];
        break;
    }
    free(left.digits);
    free(right.digits);
    return result;
}
char *big_string(const Big *a) {
    char *s=allocate((size_t)a->length*9+2);
    if(!a->length) {
        strcpy(s,"0");
        return s;
    }
    sprintf(s,"%u",a->digits[a->length-1]);
    for(int i=a->length-2;i>=0;--i)sprintf(s+strlen(s),"%09u",a->digits[i]);
    return s;
}
static void edge(Allocation *g,int a,int b) {
    if(a<0||b<0||a==b)return;
    if(!g->edges[a*g->nodes+b]) {
        g->edges[a*g->nodes+b]=g->edges[b*g->nodes+a]=1;
        ++g->edge_count;
    }
}
Allocation allocate_registers(Analysis *a,int registers) {
    Allocation g= {
        .nodes=a->nv
    };
    int n=g.nodes;
    g.edges=allocate((size_t)n*n);
    g.partners=allocate((size_t)n*n);
    g.colors=allocate((size_t)n*sizeof *g.colors);
    g.order=allocate((size_t)n*sizeof *g.order);
    g.potential_degree=allocate((size_t)n*sizeof *g.potential_degree);
    g.cost=allocate((size_t)n*sizeof *g.cost);
    for(int i=0;i<n;++i)g.colors[i]=-1;
    for(int b=0;b<a->nb;++b)if(a->blocks[b].reachable) {
        Set live=set_copy(a->out[1][b]);
        uint32_t one_digit=1;
        Big weight= {
            .digits=&one_digit,.length=1,.capacity=1
        };
        weight=big_copy(&weight);
        for(int d=0;d<a->blocks[b].depth;++d)big_multiply(&weight,10);
        for(int i=a->blocks[b].last;i>=a->blocks[b].first;--i) {
            Instruction *s=&a->function->code[a->instructions.data[i]];
            int x=variable_index(a,defined(s)),partner=s->kind==COPY&&!constant(s->a)?variable_index(a,s->a):-1;
            if(x>=0) {
                big_add(&g.cost[x],&weight);
                for(int v=0;v<n;++v)if(live.bits[v]&&v!=partner)edge(&g,x,v);
            }
            char *uses[2];
            int nu=used(s,uses);
            for(int j=0;j<nu;++j)big_add(&g.cost[variable_index(a,uses[j])],&weight);
            transfer(a,1,live,s);
        }
        free(live.bits);
        free(weight.digits);
    }
    Set entry=a->nb?set_copy(a->in[1][0]):set_new(n,0);
    for(int p=0;p<a->function->np;++p)entry.bits[variable_index(a,a->function->params[p])]=1;
    for(int p=0;p<a->function->np;++p) {
        int x=variable_index(a,a->function->params[p]);
        uint32_t digit=1;
        Big one= {
            .digits=&digit,.length=1
        };
        big_add(&g.cost[x],&one);
        for(int v=0;v<n;++v)if(entry.bits[v])edge(&g,x,v);
    }
    free(entry.bits);
    for(int i=0;i<a->function->count;++i) {
        Instruction *s=&a->function->code[i];
        if(s->kind==COPY&&!constant(s->a)&&strcmp(s->dest,s->a)) {
            int x=variable_index(a,s->dest),y=variable_index(a,s->a);
            if(x>=0&&y>=0)g.partners[x*n+y]=g.partners[y*n+x]=1;
        }
    }
    unsigned char *remaining=allocate((size_t)n);
    memset(remaining,1,(size_t)n);
    int *degree=allocate((size_t)n*sizeof *degree);
    for(int step=0;step<n;++step) {
        for(int x=0;x<n;++x) {
            degree[x]=0;
            for(int y=0;y<n;++y)if(remaining[y]&&g.edges[x*n+y])++degree[x];
        }
        int chosen=-1;
        for(int x=0;x<n;++x)if(remaining[x]&&degree[x]<registers&&(chosen<0||degree[x]<degree[chosen]))chosen=x;
        if(chosen<0) {
            for(int x=0;x<n;++x)if(remaining[x]&&(chosen<0||fraction_less(&g.cost[x],(unsigned)degree[x],&g.cost[chosen],(unsigned)degree[chosen])))chosen=x;
            g.potential_degree[chosen]=degree[chosen];
        }
        g.order[step]=chosen;
        remaining[chosen]=0;
    }
    for(int step=n-1;step>=0;--step) {
        int x=g.order[step];
        unsigned char free_colors[16];
        memset(free_colors,1,sizeof free_colors);
        for(int y=0;y<n;++y)if(g.edges[x*n+y]&&g.colors[y]>=0)free_colors[g.colors[y]]=0;
        int color=-1;
        for(int y=0;y<n;++y)if(g.partners[x*n+y]&&g.colors[y]>=0&&free_colors[g.colors[y]]&&(color<0||g.colors[y]<color))color=g.colors[y];
        if(color<0)for(int c=0;c<registers;++c)if(free_colors[c]) {
            color=c;
            break;
        }
        g.colors[x]=color;
    }
    free(remaining);
    free(degree);
    return g;
}
void allocation_free(Allocation *a) {
    free(a->edges);
    free(a->partners);
    free(a->colors);
    free(a->order);
    free(a->potential_degree);
    for(int i=0;i<a->nodes;++i)free(a->cost[i].digits);
    free(a->cost);
}
