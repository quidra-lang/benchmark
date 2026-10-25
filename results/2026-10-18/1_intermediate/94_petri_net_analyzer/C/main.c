#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <inttypes.h>
#include <limits.h>
typedef struct {
    int64_t v[16];
}
Mark;
typedef struct {
    int64_t value;
    int mode;
}
Target;
typedef struct {
    Mark *states;
    int *parent,*via,(*edge)[16];
    int count,found,aborted;
}
Graph;
typedef struct {
    char name[11],p[16][11],t[16][11];
    int P,T,arcs,inhibitors;
    int64_t initial[16],cap[16],priority[16],pre[16][16],post[16][16],inh[16][16];
    Mark current,*history;
    size_t history_size,history_capacity;
}
Net;
typedef struct {
    int64_t v[32];
}
Row;
typedef struct {
    Row *a;
    int n,capacity;
}
Rows;
#define ERROR(...) do { printf("error: "); printf(__VA_ARGS__); putchar('\n'); return; } while (0)
static const char *yes(int b){
    return b?"yes":"no";
}
static void *allocate(size_t n){
    void *p=calloc(n?n:1,1);
    if(!p)exit(EXIT_FAILURE);
    return p;
}
static int64_t integer(const char*s,int64_t lo,int64_t hi){
    size_t n=strlen(s);
    if(!n||n>10||(n>1&&*s=='0'))return -1;
    int64_t v=0;
    for(size_t i=0;i<n;++i){
        if(s[i]<'0'||s[i]>'9')return -1;
        v=v*10+s[i]-'0';
    }
    return v>=lo&&v<=hi?v:-1;
}
static int split(char *line,char **w){
    int n=0;
    char *s=strtok(line," \r\n");
    while(s){
        w[n++]=s;
        s=strtok(NULL," \r\n");
    }
    return n;
}
static int place(const Net*n,const char*s){
    for(int p=0;p<n->P;++p)if(!strcmp(n->p[p],s))return p;
    return -1;
}
static int transition(const Net*n,const char*s){
    for(int t=0;t<n->T;++t)if(!strcmp(n->t[t],s))return t;
    return -1;
}
static int equal(Mark a,Mark b,int P){
    return !memcmp(a.v,b.v,(size_t)P*sizeof(int64_t));
}
static void marking(Mark m,int P){
    putchar('(');
    for(int p=0;p<P;++p){
        if(p)putchar(',');
        if(m.v[p]<0)putchar('w');
        else printf("%"PRId64,m.v[p]);
    }
    putchar(')');
}
static void define(Net*n,char **w,int count){
    const char*cmd=w[0];
    int k=count-1;
    if(strcmp(cmd,"place")&&strcmp(cmd,"transition")&&strcmp(cmd,"arc")&&strcmp(cmd,"inhibit"))ERROR("unknown definition %s",cmd);
    if(!(!strcmp(cmd,"place")?(k==2||k==3):!strcmp(cmd,"transition")?(k==1||k==2):k==3))ERROR("wrong number of arguments");
    const char*a=w[1];
    if(!strcmp(cmd,"place")||!strcmp(cmd,"transition")){
        if(place(n,a)>=0||transition(n,a)>=0)ERROR("duplicate name %s",a);
        if(!strcmp(cmd,"place")){
            int64_t tokens=atoll(w[2]),cap=k==3?atoll(w[3]):0;
            if(k==3&&tokens>cap)ERROR("tokens exceed capacity of %s",a);
            strcpy(n->p[n->P],a);
            n->initial[n->P]=tokens;
            n->cap[n->P++]=cap;
        }else{
            strcpy(n->t[n->T],a);
            n->priority[n->T++]=k==2?atoll(w[2]):0;
        }
    }
    else if(!strcmp(cmd,"arc")){
        const char*b=w[2];
        if(place(n,a)<0&&transition(n,a)<0)ERROR("unknown node %s",a);
        if(place(n,b)<0&&transition(n,b)<0)ERROR("unknown node %s",b);
        int pa=place(n,a),pb=place(n,b);
        if((pa>=0)==(pb>=0))ERROR("arc must connect a place and a transition");
        int p=pa>=0?pa:pb,t=transition(n,pa>=0?b:a);
        int64_t(*mat)[16]=pa>=0?n->pre:n->post;
        if(mat[p][t])ERROR("duplicate arc %s %s",a,b);
        mat[p][t]=atoll(w[3]);
        ++n->arcs;
    }
    else{
        int p=place(n,a),t=transition(n,w[2]);
        if(p<0)ERROR("unknown place %s",a);
        if(t<0)ERROR("unknown transition %s",w[2]);
        if(n->inh[p][t])ERROR("duplicate inhibitor %s %s",a,w[2]);
        n->inh[p][t]=atoll(w[3]);
        ++n->inhibitors;
    }
}
static int reason(const Net*n,Mark m,int t,char *text){
    for(int p=0;p<n->P;++p)if(m.v[p]>=0&&m.v[p]<n->pre[p][t]){
        sprintf(text,"insufficient tokens in %s",n->p[p]);
        return 1;
    }
    for(int p=0;p<n->P;++p)if(n->inh[p][t]&&(m.v[p]<0||m.v[p]>=n->inh[p][t])){
        sprintf(text,"inhibited by %s",n->p[p]);
        return 1;
    }
    for(int p=0;p<n->P;++p)if(n->cap[p]&&(m.v[p]<0||m.v[p]-n->pre[p][t]+n->post[p][t]>n->cap[p])){
        sprintf(text,"capacity of %s exceeded",n->p[p]);
        return 1;
    }
    return 0;
}
static int enabled(const Net*n,Mark m,int t){
    char text[80];
    return !reason(n,m,t,text);
}
static Mark fire(const Net*n,Mark m,int t){
    for(int p=0;p<n->P;++p)if(m.v[p]>=0)m.v[p]+=n->post[p][t]-n->pre[p][t];
    return m;
}
static void commit(Net*n,int t){
    if(n->history_size==n->history_capacity){
        n->history_capacity=n->history_capacity?n->history_capacity*2:32;
        n->history=realloc(n->history,n->history_capacity*sizeof(Mark));
        if(!n->history)exit(EXIT_FAILURE);
    }
    n->history[n->history_size++]=n->current;
    n->current=fire(n,n->current,t);
}
static Graph new_graph(Mark start,int limit){
    Graph g={
        0
    };
    g.states=allocate((size_t)limit*sizeof(Mark));
    g.parent=allocate((size_t)limit*sizeof(int));
    g.via=allocate((size_t)limit*sizeof(int));
    g.edge=allocate((size_t)limit*sizeof(*g.edge));
    for(int i=0;i<limit;++i)for(int t=0;t<16;++t)g.edge[i][t]=-1;
    g.states[0]=start;
    g.parent[0]=-1;
    g.count=1;
    g.found=-1;
    return g;
}
static void free_graph(Graph*g){
    free(g->states);
    free(g->parent);
    free(g->via);
    free(g->edge);
}
static int matches(Mark m,const Target*target,int P){
    if(!target)return 0;
    for(int p=0;p<P;++p)if(target[p].mode&&(m.v[p]<target[p].value||(target[p].mode==2&&m.v[p]!=target[p].value)))return 0;
    return 1;
}
static Graph graph(const Net*n,Mark start,int limit,const Target*target){
    Graph g=new_graph(start,limit);
    if(matches(start,target,n->P)){
        g.found=0;
        return g;
    }
    for(int q=0;q<g.count;++q)for(int t=0;t<n->T;++t)if(enabled(n,g.states[q],t)){
        Mark m=fire(n,g.states[q],t);
        int k=0;
        while(k<g.count&&!equal(g.states[k],m,n->P))++k;
        if(k==g.count){
            if(g.count==limit){
                g.aborted=1;
                return g;
            }
            g.states[k]=m;
            g.parent[k]=q;
            g.via[k]=t;
            ++g.count;
            if(matches(m,target,n->P)){
                g.found=k;
                return g;
            }
        }
        g.edge[q][t]=k;
    }
    return g;
}
static int path(const Graph*g,int k,int*a){
    int count=0;
    while(g->parent[k]>=0){
        a[count++]=g->via[k];
        k=g->parent[k];
    }
    for(int i=0;i<count/2;++i){
        int x=a[i];
        a[i]=a[count-1-i];
        a[count-1-i]=x;
    }
    return count;
}
static void graph_visit(const Net*n,const Graph*g,int start,unsigned char*seen,int reverse){
    int*q=allocate((size_t)g->count*sizeof(int));
    int size=1;
    seen[start]=1;
    q[0]=start;
    for(int i=0;i<size;++i){
        int u=q[i];
        if(!reverse){
            for(int t=0;t<n->T;++t){
                int v=g->edge[u][t];
                if(v>=0&&!seen[v]){
                    seen[v]=1;
                    q[size++]=v;
                }
            }
        }else for(int v=0;v<g->count;++v)for(int t=0;t<n->T;++t)if(g->edge[v][t]==u&&!seen[v]){
            seen[v]=1;
            q[size++]=v;
        }
    }
    free(q);
}
static void reach(const Net*n,int limit,int display){
    Graph g=graph(n,n->current,limit,NULL);
    if(g.aborted){
        printf("reachability graph limit %d exceeded\n",limit);
        free_graph(&g);
        return;
    }
    if(display){
        for(int i=0;i<g.count;++i){
            printf("M%d ",i);
            marking(g.states[i],n->P);
            printf(": ");
            int first=1;
            for(int t=0;t<n->T;++t)if(g.edge[i][t]>=0){
                printf("%s%s->M%d",first?"":" ",n->t[t],g.edge[i][t]);
                first=0;
            }
            if(first)printf("dead");
            putchar('\n');
        }
        free_graph(&g);
        return;
    }
    int N=g.count;
    unsigned char*closure=allocate((size_t)N*N);
    for(int i=0;i<N;++i)graph_visit(n,&g,i,closure+(size_t)i*N,0);
    int*comp=allocate((size_t)N*sizeof(int));
    for(int i=0;i<N;++i)comp[i]=-1;
    int components=0;
    for(int i=0;i<N;++i)if(comp[i]<0){
        for(int j=i;j<N;++j)if(closure[(size_t)i*N+j]&&closure[(size_t)j*N+i])comp[j]=components;
        ++components;
    }
    unsigned char*terminal=allocate((size_t)components),*home=allocate((size_t)N);
    memset(terminal,1,(size_t)components);
    memset(home,1,(size_t)N);
    int edges=0,dead=0,persistent=1;
    Mark maximum={
        {
            0
        }
    };
    for(int i=0;i<N;++i){
        int degree=0;
        for(int p=0;p<n->P;++p)if(g.states[i].v[p]>maximum.v[p])maximum.v[p]=g.states[i].v[p];
        for(int j=0;j<N;++j)home[j]&=closure[(size_t)i*N+j];
        for(int t=0;t<n->T;++t){
            int k=g.edge[i][t];
            if(k<0)continue;
            ++degree;
            ++edges;
            if(comp[i]!=comp[k])terminal[comp[i]]=0;
            for(int u=0;u<n->T;++u)if(u!=t&&g.edge[i][u]>=0&&!enabled(n,g.states[k],u))persistent=0;
        }
        if(!degree)++dead;
    }
    int terminals=0,homes=0;
    for(int c=0;c<components;++c)terminals+=terminal[c];
    for(int i=0;i<N;++i)homes+=home[i];
    printf("reachable markings: %d\nedges: %d\ncomponents: %d (terminal %d)\ndead markings: %d\n",N,edges,components,terminals,dead);
    int*a=allocate((size_t)N*sizeof(int));
    for(int i=0;i<N;++i){
        int degree=0;
        for(int t=0;t<n->T;++t)degree+=g.edge[i][t]>=0;
        if(degree)continue;
        printf("  M%d ",i);
        marking(g.states[i],n->P);
        printf(" path ");
        int count=path(&g,i,a);
        if(!count)printf("empty");
        for(int k=0;k<count;++k)printf("%s%s",k?" ":"",n->t[a[k]]);
        putchar('\n');
    }
    int64_t bound=0;
    for(int p=0;p<n->P;++p)if(maximum.v[p]>bound)bound=maximum.v[p];
    printf("max tokens: ");
    marking(maximum,n->P);
    printf("\nbound: %"PRId64"\nsafe: %s\nhome markings: %d\nreversible: %s\npersistent: %s\nliveness: ",bound,yes(bound<=1),homes,yes(home[0]),yes(persistent));
    for(int t=0;t<n->T;++t){
        unsigned char*present=allocate((size_t)components);
        int used=0,cycle=0,live=1;
        for(int i=0;i<N;++i){
            int k=g.edge[i][t];
            if(k>=0){
                used=1;
                present[comp[i]]=1;
                if(comp[i]==comp[k])cycle=1;
            }
        }
        for(int c=0;c<components;++c)if(terminal[c]&&!present[c])live=0;
        printf("%s%s=%s",t?" ":"",n->t[t],live?"L4":cycle?"L3":used?"L1":"L0");
        free(present);
    }
    putchar('\n');
    free(a);
    free(closure);
    free(comp);
    free(terminal);
    free(home);
    free_graph(&g);
}
static int64_t rank_value(int64_t v){
    return v<0?INT64_MAX:v;
}
static void cover(const Net*n,int limit){
    Graph g=new_graph(n->current,limit);
    unsigned char*old=allocate((size_t)limit),*dead=allocate((size_t)limit);
    int*anc=allocate((size_t)limit*sizeof(int));
    for(int q=0;q<g.count;++q){
        if(old[q])continue;
        int count=0;
        for(int a=q;a>=0;a=g.parent[a])anc[count++]=a;
        int degree=0;
        for(int t=0;t<n->T;++t)if(enabled(n,g.states[q],t)){
            ++degree;
            Mark m=fire(n,g.states[q],t);
            for(int j=count-1;j>=0;--j){
                int a=anc[j],ge=1,gt=0;
                for(int p=0;p<n->P;++p){
                    ge&=rank_value(m.v[p])>=rank_value(g.states[a].v[p]);
                    gt|=rank_value(m.v[p])>rank_value(g.states[a].v[p]);
                }
                if(ge&&gt)for(int p=0;p<n->P;++p)if(!n->cap[p]&&rank_value(m.v[p])>rank_value(g.states[a].v[p]))m.v[p]=-1;
            }
            if(g.count==limit){
                printf("coverability tree limit %d exceeded\n",limit);
                goto done;
            }
            int k=g.count++;
            g.states[k]=m;
            g.parent[k]=q;
            g.via[k]=t;
            for(int a=0;a<k;++a)if(equal(m,g.states[a],n->P)){
                old[k]=1;
                break;
            }
        }
        dead[q]=!degree;
    }
    printf("coverability tree nodes: %d\n",g.count);
    Mark maximum={
        {
            0
        }
    };
    for(int i=0;i<g.count;++i){
        printf("  %d ",i);
        marking(g.states[i],n->P);
        if(i)printf(" <- %d %s",g.parent[i],n->t[g.via[i]]);
        else printf(" root");
        if(old[i])printf(" old");
        if(dead[i])printf(" dead");
        putchar('\n');
        for(int p=0;p<n->P;++p)if(rank_value(g.states[i].v[p])>rank_value(maximum.v[p]))maximum.v[p]=g.states[i].v[p];
    }
    printf("bounds: ");
    marking(maximum,n->P);
    printf("\nunbounded: ");
    int first=1;
    for(int p=0;p<n->P;++p)if(maximum.v[p]<0){
        printf("%s%s",first?"":" ",n->p[p]);
        first=0;
    }
    if(first)printf("none");
    putchar('\n');
    done: free(old);
    free(dead);
    free(anc);
    free_graph(&g);
}
static int bit_count(int mask){
    int n=0;
    while(mask){
        mask&=mask-1;
        ++n;
    }
    return n;
}
static int set_order(const void*a,const void*b){
    int x=*(const int*)a,y=*(const int*)b,c=bit_count(x)-bit_count(y);
    if(c)return c;
    for(int p=0;p<16;++p)if((x&(1<<p))!=(y&(1<<p)))return x&(1<<p)?-1:1;
    return 0;
}
static int *sets(const Net*n,int trap,int*count){
    int limit=1<<n->P;
    unsigned char*valid=allocate((size_t)limit);
    for(int mask=1;mask<limit;++mask){
        valid[mask]=1;
        for(int t=0;t<n->T;++t){
            int input=0,output=0;
            for(int p=0;p<n->P;++p)if(mask&(1<<p)){
                input|=n->post[p][t]>0;
                output|=n->pre[p][t]>0;
            }
            if(trap?output&&!input:input&&!output){
                valid[mask]=0;
                break;
            }
        }
    }
    int*r=allocate((size_t)limit*sizeof(int));
    *count=0;
    for(int mask=1;mask<limit;++mask)if(valid[mask]){
        int minimal=1;
        for(int s=(mask-1)&mask;s;s=(s-1)&mask)if(valid[s]){
            minimal=0;
            break;
        }
        if(minimal)r[(*count)++]=mask;
    }
    qsort(r,(size_t)*count,sizeof(int),set_order);
    free(valid);
    return r;
}
static void set_text(const Net*n,int mask){
    putchar('{');
    int first=1;
    for(int p=0;p<n->P;++p)if(mask&(1<<p)){
        printf("%s%s",first?"":",",n->p[p]);
        first=0;
    }
    putchar('}');
}
static int64_t gcd(int64_t a,int64_t b){
    while(b){
        int64_t r=a%b;
        a=b;
        b=r;
    }
    return a<0?-a:a;
}
static void add_row(Rows*r,Row v){
    if(r->n==r->capacity){
        r->capacity=r->capacity?r->capacity*2:32;
        r->a=realloc(r->a,(size_t)r->capacity*sizeof(Row));
        if(!r->a)exit(EXIT_FAILURE);
    }
    r->a[r->n++]=v;
}
static int row_order(const void*a,const void*b){
    const Row*x=a,*y=b;
    for(int i=0;i<32;++i)if(x->v[i]!=y->v[i])return x->v[i]>y->v[i]?-1:1;
    return 0;
}
static Rows flows(const Net*n,int transpose){
    int size=transpose?n->T:n->P,width=transpose?n->P:n->T;
    Rows rows={
        0
    };
    for(int i=0;i<size;++i){
        Row r={
            {
                0
            }
        };
        for(int j=0;j<width;++j)r.v[j]=transpose?n->post[j][i]-n->pre[j][i]:n->post[i][j]-n->pre[i][j];
        r.v[width+i]=1;
        add_row(&rows,r);
    }
    for(int j=0;j<width;++j){
        Rows collected={
            0
        };
        for(int i=0;i<rows.n;++i)if(!rows.a[i].v[j])add_row(&collected,rows.a[i]);
        for(int i=0;i<rows.n;++i)if(rows.a[i].v[j]>0)for(int k=0;k<rows.n;++k)if(rows.a[k].v[j]<0){
            Row r={
                {
                    0
                }
            };
            int64_t d=0;
            for(int c=0;c<width+size;++c){
                r.v[c]=-rows.a[k].v[j]*rows.a[i].v[c]+rows.a[i].v[j]*rows.a[k].v[c];
                d=gcd(d,r.v[c]);
            }
            for(int c=0;c<width+size;++c)r.v[c]/=d;
            add_row(&collected,r);
        }
        free(rows.a);
        rows=(Rows){
            0
        };
        int*support=allocate((size_t)collected.n*sizeof(int));
        unsigned char*duplicate=allocate((size_t)collected.n);
        for(int i=0;i<collected.n;++i){
            for(int c=0;c<size;++c)if(collected.a[i].v[width+c]>0)support[i]|=1<<c;
            for(int k=0;k<i;++k)if(!memcmp(collected.a[i].v,collected.a[k].v,(size_t)(width+size)*sizeof(int64_t))){
                duplicate[i]=1;
                break;
            }
        }
        for(int i=0;i<collected.n;++i)if(!duplicate[i]){
            int minimal=1;
            for(int k=0;k<collected.n;++k)if(support[k]!=support[i]&&(support[k]&support[i])==support[k]){
                minimal=0;
                break;
            }
            if(minimal)add_row(&rows,collected.a[i]);
        }
        free(support);
        free(duplicate);
        free(collected.a);
    }
    for(int i=0;i<rows.n;++i){
        Row r={
            {
                0
            }
        };
        for(int c=0;c<size;++c)r.v[c]=rows.a[i].v[width+c];
        rows.a[i]=r;
    }
    qsort(rows.a,(size_t)rows.n,sizeof(Row),row_order);
    return rows;
}
static int *realize(const Net*n,Row counts,int*length){
    size_t total=0,space=1;
    for(int t=0;t<n->T;++t){
        total+=(size_t)counts.v[t];
        space*=(size_t)counts.v[t]+1;
    }
    Mark*stack=allocate((total+1)*sizeof(Mark));
    int*choices=allocate((total+1)*sizeof(int)),*path=allocate((total+1)*sizeof(int));
    unsigned char*seen=allocate(space);
    int64_t used[16]={
        0
    };
    stack[0]=n->current;
    size_t depth=0;
    for(;;){
        if(depth==total){
            *length=(int)total;
            free(stack);
            free(choices);
            free(seen);
            return path;
        }
        int chosen=-1;
        for(int t=choices[depth];t<n->T;++t){
            choices[depth]=t+1;
            if(used[t]>=counts.v[t]||!enabled(n,stack[depth],t))continue;
            ++used[t];
            size_t key=0,mult=1;
            for(int u=0;u<n->T;++u){
                key+=(size_t)used[u]*mult;
                mult*=(size_t)counts.v[u]+1;
            }
            --used[t];
            if(seen[key])continue;
            seen[key]=1;
            chosen=t;
            break;
        }
        if(chosen>=0){
            ++used[chosen];
            path[depth]=chosen;
            stack[depth+1]=fire(n,stack[depth],chosen);
            ++depth;
            choices[depth]=0;
        }else{
            if(!depth)break;
            --depth;
            --used[path[depth]];
        }
    }
    free(stack);
    free(choices);
    free(seen);
    free(path);
    return NULL;
}
static void invariants(const Net*n,int transpose){
    Rows f=flows(n,transpose);
    int size=transpose?n->T:n->P;
    int covered[16]={
        0
    };
    int64_t bounds[16];
    for(int p=0;p<size;++p)bounds[p]=-1;
    printf("%c-semiflows: %d\n",transpose?'T':'P',f.n);
    for(int i=0;i<f.n;++i){
        Row c=f.a[i];
        printf("  ");
        int first=1;
        int64_t value=0;
        for(int p=0;p<size;++p)if(c.v[p]){
            if(!first)printf(" + ");
            if(c.v[p]!=1)printf("%"PRId64"*",c.v[p]);
            printf("%s",transpose?n->t[p]:n->p[p]);
            covered[p]=1;
            first=0;
            if(!transpose)value+=c.v[p]*n->current.v[p];
        }
        if(transpose){
            int length=0;
            int*path=realize(n,c,&length);
            if(!path)printf(": not realizable\n");
            else{
                printf(": realizable");
                for(int k=0;k<length;++k)printf(" %s",n->t[path[k]]);
                putchar('\n');
                free(path);
            }
        }else{
            printf(" = %"PRId64"\n",value);
            for(int p=0;p<size;++p)if(c.v[p]){
                int64_t b=value/c.v[p];
                if(bounds[p]<0||b<bounds[p])bounds[p]=b;
            }
        }
    }
    if(!transpose){
        printf("bounds: (");
        for(int p=0;p<size;++p){
            if(p)putchar(',');
            if(bounds[p]<0)putchar('-');
            else printf("%"PRId64,bounds[p]);
        }
        printf(")\n");
    }
    int all=1;
    for(int p=0;p<size;++p)all&=covered[p];
    printf("%s: %s\n",transpose?"consistent":"conservative",yes(all));
    free(f.a);
}
static void classify(const Net*n){
    int ordinary=1,pure=1,sm=1,mg=1,fc=1,efc=1,inputs[16]={
        0
    },outputs[16]={
        0
    };
    for(int p=0;p<n->P;++p)for(int t=0;t<n->T;++t){
        ordinary&=n->pre[p][t]<=1&&n->post[p][t]<=1;
        pure&=!(n->pre[p][t]&&n->post[p][t]);
        if(n->pre[p][t]){
            inputs[t]|=1<<p;
            outputs[p]|=1<<t;
        }
    }
    for(int t=0;t<n->T;++t){
        int c=0;
        for(int p=0;p<n->P;++p)c+=n->post[p][t]>0;
        sm&=bit_count(inputs[t])==1&&c==1;
    }
    for(int p=0;p<n->P;++p){
        int c=0;
        for(int t=0;t<n->T;++t){
            c+=n->post[p][t]>0;
            if(n->pre[p][t]&&bit_count(outputs[p])!=1&&bit_count(inputs[t])!=1)fc=0;
        }
        mg&=bit_count(outputs[p])==1&&c==1;
        for(int q=0;q<n->P;++q)if((outputs[p]&outputs[q])&&outputs[p]!=outputs[q])efc=0;
    }
    sm&=ordinary;
    mg&=ordinary;
    fc&=ordinary;
    efc&=ordinary;
    printf("ordinary: %s\npure: %s\nstate machine: %s\nmarked graph: %s\nfree choice: %s\nextended free choice: %s\ncommoner: ",yes(ordinary),yes(pure),yes(sm),yes(mg),yes(fc),yes(efc));
    if(!fc)printf("not applicable\n");
    else if(n->P>12)printf("too many places\n");
    else{
        int ns,nt,*s=sets(n,0,&ns),*traps=sets(n,1,&nt),failed=-1;
        for(int i=0;i<ns;++i){
            int holds=0;
            for(int j=0;j<nt;++j)if((s[i]&traps[j])==traps[j])for(int p=0;p<n->P;++p)if((traps[j]&(1<<p))&&n->current.v[p]>0)holds=1;
            if(!holds){
                failed=s[i];
                break;
            }
        }
        if(failed<0)printf("holds\n");
        else{
            printf("fails at ");
            set_text(n,failed);
            putchar('\n');
        }
        free(s);
        free(traps);
    }
}
static void structural_visit(int adj[32][32],int size,int start,int reverse,int*seen){
    int q[32],count=1;
    q[0]=start;
    seen[start]=1;
    for(int i=0;i<count;++i)for(int v=0;v<size;++v)if((reverse?adj[v][q[i]]:adj[q[i]][v])&&!seen[v]){
        seen[v]=1;
        q[count++]=v;
    }
}
static void workflow(const Net*n,int limit){
    int sources[16],sinks[16],ns=0,nt=0;
    for(int p=0;p<n->P;++p){
        int input=0,output=0;
        for(int t=0;t<n->T;++t){
            input|=n->post[p][t]>0;
            output|=n->pre[p][t]>0;
        }
        if(!input)sources[ns++]=p;
        if(!output)sinks[nt++]=p;
    }
    if(ns!=1){
        printf("workflow: no (%d source places)\n",ns);
        return;
    }
    if(nt!=1){
        printf("workflow: no (%d sink places)\n",nt);
        return;
    }
    int i=sources[0],o=sinks[0],adj[32][32]={
        {
            0
        }
    },f[32]={
        0
    },b[32]={
        0
    };
    for(int p=0;p<n->P;++p)for(int t=0;t<n->T;++t){
        adj[p][n->P+t]=n->pre[p][t]>0;
        adj[n->P+t][p]=n->post[p][t]>0;
    }
    structural_visit(adj,n->P+n->T,i,0,f);
    structural_visit(adj,n->P+n->T,o,1,b);
    for(int v=0;v<n->P+n->T;++v)if(!f[v]||!b[v]){
        printf("workflow: no (%s is not on a path from %s to %s)\n",v<n->P?n->p[v]:n->t[v-n->P],n->p[i],n->p[o]);
        return;
    }
    printf("workflow: source %s sink %s\n",n->p[i],n->p[o]);
    Mark start={
        {
            0
        }
    },goal={
        {
            0
        }
    };
    start.v[i]=1;
    goal.v[o]=1;
    Graph g=graph(n,start,limit,NULL);
    if(g.aborted){
        printf("reachability graph limit %d exceeded\n",limit);
        free_graph(&g);
        return;
    }
    int finish=-1,proper=1,used[16]={
        0
    };
    for(int u=0;u<g.count;++u){
        if(equal(g.states[u],goal,n->P))finish=u;
        if(g.states[u].v[o]>=1&&!equal(g.states[u],goal,n->P))proper=0;
        for(int t=0;t<n->T;++t)if(g.edge[u][t]>=0)used[t]=1;
    }
    int option=0,live=1;
    if(finish>=0){
        unsigned char*r=allocate((size_t)g.count);
        graph_visit(n,&g,finish,r,1);
        option=1;
        for(int u=0;u<g.count;++u)option&=r[u];
        free(r);
    }
    for(int t=0;t<n->T;++t)live&=used[t];
    printf("option to complete: %s\nproper completion: %s\nno dead transitions: %s\nsound: %s\n",yes(option),yes(proper),yes(live),yes(option&&proper&&live));
    free_graph(&g);
}
static void execute(Net*n,char **w,int count){
    const char*commands[]={
        "MARKING","RESET","SET","ENABLED","FIRE","UNDO","SIMULATE","CONFLICTS","REACH","GRAPH","COVER","PATH","INCIDENCE","PINV","TINV","SIPHONS","TRAPS","CLASSIFY","WORKFLOW","SHOW"
    };
    const int arity[]={
        0,0,2,0,-1,1,3,0,1,1,1,2,0,0,0,0,0,0,1,0
    };
    int cmd=0;
    while(cmd<20&&strcmp(w[0],commands[cmd]))++cmd;
    if(cmd==20)ERROR("unknown command %s",w[0]);
    if(arity[cmd]<0?count<2:count!=arity[cmd]+1)ERROR("wrong number of arguments");
    int limit=0;
    if(cmd==8||cmd==9||cmd==10||cmd==11||cmd==18){
        limit=(int)integer(w[1],1,2000);
        if(limit<0)ERROR("invalid limit %s",w[1]);
    }
    switch(cmd){
        case 0:case 1:if(cmd==1){
            memcpy(n->current.v,n->initial,sizeof(n->initial));
            n->history_size=0;
        }
        printf("marking ");
        marking(n->current,n->P);
        putchar('\n');
        break;
        case 2:{
            int p=place(n,w[1]);
            if(p<0)ERROR("unknown place %s",w[1]);
            int64_t v=integer(w[2],0,999);
            if(v<0)ERROR("invalid tokens %s",w[2]);
            if(n->cap[p]&&v>n->cap[p])ERROR("tokens exceed capacity of %s",w[1]);
            n->current.v[p]=v;
            n->history_size=0;
            printf("marking ");
            marking(n->current,n->P);
            putchar('\n');
            break;
        }
        case 3:{
            printf("enabled: ");
            int first=1;
            for(int t=0;t<n->T;++t)if(enabled(n,n->current,t)){
                printf("%s%s",first?"":" ",n->t[t]);
                first=0;
            }
            if(first)printf("none");
            putchar('\n');
            break;
        }
        case 4:{
            int ts[201];
            for(int i=1;i<count;++i){
                ts[i-1]=transition(n,w[i]);
                if(ts[i-1]<0)ERROR("unknown transition %s",w[i]);
            }
            for(int i=0;i<count-1;++i){
                char r[80];
                if(reason(n,n->current,ts[i],r)){
                    printf("step %d: %s not enabled (%s) at ",i+1,n->t[ts[i]],r);
                    marking(n->current,n->P);
                    putchar('\n');
                    return;
                }
                commit(n,ts[i]);
            }
            printf("fired %d -> ",count-1);
            marking(n->current,n->P);
            putchar('\n');
            break;
        }
        case 5:{
            int k=(int)integer(w[1],1,1000);
            if(k<0)ERROR("invalid count %s",w[1]);
            if((size_t)k>n->history_size)ERROR("cannot undo %d: history size %zu",k,n->history_size);
            n->current=n->history[n->history_size-(size_t)k];
            n->history_size-=(size_t)k;
            printf("marking ");
            marking(n->current,n->P);
            putchar('\n');
            break;
        }
        case 6:{
            int steps=(int)integer(w[1],1,1000);
            int64_t x=integer(w[2],1,2147483646);
            if(steps<0)ERROR("invalid steps %s",w[1]);
            if(x<0)ERROR("invalid seed %s",w[2]);
            if(strcmp(w[3],"PRIORITY")&&strcmp(w[3],"RANDOM"))ERROR("invalid mode %s",w[3]);
            int counts[16]={
                0
            },done=0;
            for(;done<steps;++done){
                int es[16],size=0;
                for(int t=0;t<n->T;++t)if(enabled(n,n->current,t))es[size++]=t;
                if(!size){
                    printf("dead (steps=%d)\n",done);
                    break;
                }
                int t=es[0];
                if(!strcmp(w[3],"RANDOM")){
                    x=x*48271%2147483647;
                    t=es[x%size];
                }else for(int i=1;i<size;++i)if(n->priority[es[i]]>n->priority[t])t=es[i];
                commit(n,t);
                ++counts[t];
                printf("step %d: %s -> ",done+1,n->t[t]);
                marking(n->current,n->P);
                putchar('\n');
            }
            if(done==steps)printf("completed (steps=%d)\n",steps);
            printf("counts: ");
            for(int t=0;t<n->T;++t)printf("%s%s=%d",t?" ":"",n->t[t],counts[t]);
            putchar('\n');
            break;
        }
        case 7:{
            for(int effective=0;effective<2;++effective){
                printf("%s: ",effective?"effective":"structural");
                int first=1;
                for(int u=0;u<n->T;++u)for(int v=u+1;v<n->T;++v){
                    int conflict=0;
                    if(effective)conflict=enabled(n,n->current,u)&&enabled(n,n->current,v)&&(!enabled(n,fire(n,n->current,u),v)||!enabled(n,fire(n,n->current,v),u));
                    else for(int p=0;p<n->P;++p)conflict|=n->pre[p][u]>0&&n->pre[p][v]>0;
                    if(conflict){
                        printf("%s%s/%s",first?"":" ",n->t[u],n->t[v]);
                        first=0;
                    }
                }
                if(first)printf("none");
                putchar('\n');
            }
            break;
        }
        case 8:case 9:reach(n,limit,cmd==9);
        break;
        case 10:cover(n,limit);
        break;
        case 11:{
            Target target[16];
            char*s=w[2],*entries[201];
            int size=0;
            entries[size++]=s;
            for(char*c=s;*c;++c)if(*c==','){
                *c=0;
                entries[size++]=c+1;
            }
            if(size!=n->P)ERROR("target needs %d entries",n->P);
            for(int p=0;p<size;++p){
                s=entries[p];
                if(!strcmp(s,"*")){
                    target[p]=(Target){
                        0,0
                    };
                    continue;
                }
                size_t len=strlen(s);
                int plus=len&&s[len-1]=='+';
                char raw[201];
                strcpy(raw,s);
                if(plus)raw[len-1]=0;
                int64_t v=integer(raw,0,9999999999LL);
                if(v<0)ERROR("invalid target entry %s",s);
                target[p]=(Target){
                    v,plus?1:2
                };
            }
            Graph g=graph(n,n->current,limit,target);
            if(g.found>=0){
                int*a=allocate((size_t)g.count*sizeof(int)),length=path(&g,g.found,a);
                printf("reached ");
                marking(g.states[g.found],n->P);
                printf(" length=%d",length);
                if(length)printf(":");
                for(int i=0;i<length;++i)printf(" %s",n->t[a[i]]);
                putchar('\n');
                free(a);
            }else if(g.aborted)printf("search limit %d exceeded\n",limit);
            else printf("unreachable (markings explored: %d)\n",g.count);
            free_graph(&g);
            break;
        }
        case 12:{
            char cells[17][17][32];
            int width[17]={
                0
            };
            strcpy(cells[0][0],"");
            for(int t=0;t<n->T;++t)strcpy(cells[0][t+1],n->t[t]);
            for(int p=0;p<n->P;++p){
                strcpy(cells[p+1][0],n->p[p]);
                for(int t=0;t<n->T;++t)sprintf(cells[p+1][t+1],"%"PRId64,n->post[p][t]-n->pre[p][t]);
            }
            for(int r=0;r<=n->P;++r)for(int c=0;c<=n->T;++c)if((int)strlen(cells[r][c])>width[c])width[c]=(int)strlen(cells[r][c]);
            for(int r=0;r<=n->P;++r){
                printf("%-*s",width[0],cells[r][0]);
                for(int c=1;c<=n->T;++c)printf("  %*s",width[c],cells[r][c]);
                putchar('\n');
            }
            break;
        }
        case 13:case 14:invariants(n,cmd==14);
        break;
        case 15:case 16:{
            if(n->P>12)ERROR("more than 12 places");
            int count,*ss=sets(n,cmd==16,&count);
            printf("minimal %s: %d\n",cmd==16?"traps":"siphons",count);
            for(int i=0;i<count;++i){
                int64_t tokens=0;
                for(int p=0;p<n->P;++p)if(ss[i]&(1<<p))tokens+=n->current.v[p];
                printf("  ");
                set_text(n,ss[i]);
                printf(" tokens=%"PRId64"\n",tokens);
            }
            free(ss);
            break;
        }
        case 17:classify(n);
        break;
        case 18:workflow(n,limit);
        break;
        case 19:for(int p=0;p<n->P;++p){
            printf("place %s tokens=%"PRId64" capacity=",n->p[p],n->initial[p]);
            if(n->cap[p])printf("%"PRId64,n->cap[p]);
            else printf("none");
            putchar('\n');
        }
        for(int t=0;t<n->T;++t){
            printf("transition %s priority=%"PRId64,n->t[t],n->priority[t]);
            int64_t(*mats[3])[16]={
                n->pre,n->post,n->inh
            };
            const char*labels[]={
                "pre","post","inhibit"
            };
            for(int j=0;j<3;++j){
                printf(" %s=",labels[j]);
                int first=1;
                for(int p=0;p<n->P;++p)if(mats[j][p][t]){
                    printf("%s%s:%"PRId64,first?"":",",n->p[p],mats[j][p][t]);
                    first=0;
                }
                if(first)printf("-");
            }
            putchar('\n');
        }
        break;
    }
}
int main(void){
    char line[256],*w[201];
    if(!fgets(line,sizeof(line),stdin))return 0;
    int blocks=atoi(line);
    for(int b=0;b<blocks;++b){
        Net n={
            0
        };
        fgets(line,sizeof(line),stdin);
        split(line,w);
        strcpy(n.name,w[1]);
        while(fgets(line,sizeof(line),stdin)){
            int count=split(line,w);
            if(count==2&&!strcmp(w[0],"END")&&!strcmp(w[1],"NET"))break;
            define(&n,w,count);
        }
        memcpy(n.current.v,n.initial,sizeof(n.initial));
        printf("net %s: places=%d transitions=%d arcs=%d inhibitors=%d\n",n.name,n.P,n.T,n.arcs,n.inhibitors);
        fgets(line,sizeof(line),stdin);
        int count=atoi(line);
        for(int i=0;i<count;++i){
            fgets(line,sizeof(line),stdin);
            int words=split(line,w);
            execute(&n,w,words);
        }
        free(n.history);
    }
    return 0;
}
