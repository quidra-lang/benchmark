#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <ctype.h>

#define MAX_HISTORY 550
#define MAX_QUEUE 600
#define MAX_PENDING 600
#define MAX_SAVES 550
#define MAX_BFS 4096
#define MAX_CANDIDATES 256
#define MAX_OPERATIONS 256

typedef struct { int s,x,y; } Position;
typedef struct { int x,y; } Cell;
typedef struct {
    int drops,holds,operations,faults,perfect,sent,cancelled,received,combo,chain;
    int kinds[7],clears[11];
} Statistics;
typedef struct {
    int board[22];
    int64_t random;
    int queue[MAX_QUEUE],queue_len,hold;
    bool used_hold;
    int kind;
    Position position;
    int last,test,keys,drop,fall,ground,resets,lowest;
    int initial_level,level,score,lines,pieces,streak,chain;
    int pending[MAX_PENDING],pending_len;
    bool ended;
    Statistics stats;
} State;
typedef struct {
    char name[9];
    State state,start;
    State *history;
    int history_len;
} Save;
typedef struct {
    int number;
    State state,start;
    State history[MAX_HISTORY];
    int history_len;
    Save saves[MAX_SAVES];
    int save_len;
} Game;
typedef struct { Position p; int parent,operation; } BFSNode;
typedef struct { int kind,value,ops[MAX_OPERATIONS],count,index,occupied[4]; } Candidate;
typedef struct { Position p; int spin; } SpinCandidate;

static const char kind_names[]="IOTSZJL";
static const char *operation_names[]={"L","R","LL","RR","SD","DD","CW","CCW","HD","LOCK","HOLD"};
static const char *command_names[]={"NEW","PRINT","NEXT","PREVIEW","STATUS","ANALYZE","ROW","GARBAGE","ATTACK","TICK","UNDO","SAVE","LOAD","SPINS","HINT","AUTO"};
static const char *clear_names[]={"SINGLE","DOUBLE","TRIPLE","TETRIS","TSPIN_MINI","TSPIN_MINI_SINGLE","TSPIN_MINI_DOUBLE","TSPIN","TSPIN_SINGLE","TSPIN_DOUBLE","TSPIN_TRIPLE"};
static const char *frames[7][4]={
    {"....","####","....","...."},{"##","##",NULL,NULL},{".#.","###","...",NULL},
    {".##","##.","...",NULL},{"##.",".##","...",NULL},{"#..","###","...",NULL},{"..#","###","...",NULL}
};
static const int kick_other[8][5][2]={
    {{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}},
    {{0,0},{1,0},{1,-1},{0,2},{1,2}},
    {{0,0},{1,0},{1,-1},{0,2},{1,2}},
    {{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}},
    {{0,0},{1,0},{1,1},{0,-2},{1,-2}},
    {{0,0},{-1,0},{-1,-1},{0,2},{-1,2}},
    {{0,0},{-1,0},{-1,-1},{0,2},{-1,2}},
    {{0,0},{1,0},{1,1},{0,-2},{1,-2}}
};
static const int kick_i[8][5][2]={
    {{0,0},{-2,0},{1,0},{-2,-1},{1,2}},
    {{0,0},{2,0},{-1,0},{2,1},{-1,-2}},
    {{0,0},{-1,0},{2,0},{-1,2},{2,-1}},
    {{0,0},{1,0},{-2,0},{1,-2},{-2,1}},
    {{0,0},{2,0},{-1,0},{2,1},{-1,-2}},
    {{0,0},{-2,0},{1,0},{-2,-1},{1,2}},
    {{0,0},{1,0},{-2,0},{1,-2},{-2,1}},
    {{0,0},{-1,0},{2,0},{-1,2},{2,-1}}
};
static const int kick_states[8][2]={{0,1},{1,0},{1,2},{2,1},{2,3},{3,2},{3,0},{0,3}};
static Cell shape[7][4][4];
static BFSNode bfs[MAX_BFS];
static Candidate candidates[MAX_CANDIDATES];
static SpinCandidate spins[MAX_BFS];
static Game *game;
static int serial_number;

static Position position(int s,int x,int y){Position p={s,x,y};return p;}
static bool same_position(Position a,Position b){return a.s==b.s&&a.x==b.x&&a.y==b.y;}
static int64_t seed_step(int64_t value){return value*48271LL%2147483647LL;}
static Position spawn_position(int kind){return position(0,kind==1?5:4,22);}
static int sum_pending(const State *s){int n=0;for(int i=0;i<s->pending_len;++i)n+=s->pending[i];return n;}
static int compare_int(const void *a,const void *b){return (*(const int*)a>*(const int*)b)-(*(const int*)a<*(const int*)b);}
static void init_shapes(void){
    for(int k=0;k<7;++k){
        int n=k==0?4:k==1?2:3,count=0;
        for(int j=0;j<n;++j)for(int i=0;i<n;++i)if(frames[k][j][i]=='#')shape[k][0][count++]=(Cell){i,j};
        for(int r=1;r<4;++r)for(int m=0;m<4;++m){Cell p=shape[k][r-1][m];shape[k][r][m]=(Cell){n-1-p.y,p.x};}
    }
}
static void piece_cells(int kind,Position p,Cell out[4]){
    for(int i=0;i<4;++i){Cell b=shape[kind][p.s][i];out[i]=(Cell){p.x+b.x,p.y-b.y};}
}
static int lowest_row(int kind,Position p){Cell c[4];piece_cells(kind,p,c);int lowest=23;for(int i=0;i<4;++i)if(c[i].y<lowest)lowest=c[i].y;return lowest;}
static bool fits(const int board[22],int kind,Position p){
    Cell c[4];piece_cells(kind,p,c);
    for(int i=0;i<4;++i){int x=c[i].x,y=c[i].y;if(x<1||x>10||y<1||y>22||(board[y-1]&(1<<(x-1)))!=0)return false;}
    return true;
}
static bool try_move(const int board[22],int kind,Position p,int op,Position *result,int *test){
    if(op>=6&&op<=7){
        int b=(p.s+(op==6?1:3))%4,row=0;
        for(int i=0;i<8;++i)if(kick_states[i][0]==p.s&&kick_states[i][1]==b){row=i;break;}
        for(int i=0;i<(kind==1?1:5);++i){
            int dx=kind==1?0:(kind==0?kick_i:kick_other)[row][i][0];
            int dy=kind==1?0:(kind==0?kick_i:kick_other)[row][i][1];
            Position q=position(b,p.x+dx,p.y+dy);
            if(fits(board,kind,q)){*result=q;*test=i+1;return true;}
        }
        return false;
    }
    int dx=(op==0||op==2)?-1:(op==1||op==3)?1:0;
    int dy=dx==0?-1:0;
    bool repeat=op==2||op==3||op==5,changed=false;
    Position q=p;
    do{
        Position n=position(q.s,q.x+dx,q.y+dy);
        if(!fits(board,kind,n))break;
        q=n;changed=true;
    }while(repeat);
    if(changed){*result=q;*test=0;return true;}
    return false;
}
static Position landing(const int board[22],int kind,Position p){Position result;int test;return try_move(board,kind,p,5,&result,&test)?result:p;}
static int place_piece(const int board[22],int kind,Position p,int result[22]){
    memcpy(result,board,sizeof(int)*22);
    Cell c[4];piece_cells(kind,p,c);
    for(int i=0;i<4;++i)result[c[i].y-1]|=1<<(c[i].x-1);
    int count=0;
    for(int i=0;i<22;++i)if(result[i]!=1023)result[count++]=result[i];
    int lines=22-count;
    for(int i=count;i<22;++i)result[i]=0;
    return lines;
}
static int evaluate_well(const int board[22],int cleared,int heights[10],int *holes,int *bumpiness){
    *holes=0;*bumpiness=0;int total=0;
    for(int c=0;c<10;++c){
        int h=0;
        for(int r=21;r>=0;--r)if((board[r]&(1<<c))!=0){h=r+1;break;}
        heights[c]=h;total+=h;
        for(int r=0;r<h;++r)if((board[r]&(1<<c))==0)++*holes;
    }
    for(int c=0;c<9;++c)*bumpiness+=abs(heights[c]-heights[c+1]);
    return 76*cleared-51*total-36*(*holes)-18*(*bumpiness);
}
static int search_routes(const int board[22],int kind,Position start,const Position *target,int *last_index){
    if(!fits(board,kind,start))return 0;
    static bool seen[4][32][32];
    memset(seen,0,sizeof(seen));
    bfs[0]=(BFSNode){start,-1,-1};int count=1;
    if(start.s>=0&&start.s<4&&start.x>=-8&&start.x<24&&start.y>=0&&start.y<32)seen[start.s][start.x+8][start.y]=true;
    for(int i=0;i<count;++i){
        if(target&&same_position(landing(board,kind,bfs[i].p),*target)){*last_index=i;return count;}
        for(int op=0;op<8;++op){
            Position q;int test;
            if(!try_move(board,kind,bfs[i].p,op,&q,&test))continue;
            if(q.s<0||q.s>=4||q.x<-8||q.x>=24||q.y<0||q.y>=32)continue;
            if(seen[q.s][q.x+8][q.y])continue;
            seen[q.s][q.x+8][q.y]=true;
            if(count>=MAX_BFS)break;
            bfs[count++]=(BFSNode){q,i,op};
        }
    }
    return target?0:count;
}
static int reconstruct_ops(int last,int result[MAX_OPERATIONS]){
    int reversed[MAX_OPERATIONS],count=0;
    while(last>=0&&bfs[last].parent>=0&&count<MAX_OPERATIONS){reversed[count++]=bfs[last].operation;last=bfs[last].parent;}
    for(int i=0;i<count;++i)result[i]=reversed[count-1-i];
    return count;
}
static int t_spin(const int board[22],Position p,int test){
    Cell corners[4]={{p.x,p.y},{p.x+2,p.y},{p.x+2,p.y-2},{p.x,p.y-2}};
    bool blocked[4];int count=0;
    for(int i=0;i<4;++i){int x=corners[i].x,y=corners[i].y;blocked[i]=x<1||x>10||y<1||y>22||(board[y-1]&(1<<(x-1)))!=0;if(blocked[i])++count;}
    if(count<3)return 0;
    return (blocked[p.s]&&blocked[(p.s+1)%4])||test==5?2:1;
}
static void clear_info(int spin,int lines,int *name,int *points,int *sent){
    static const int ordinary_points[]={0,100,300,500,800},ordinary_sent[]={0,0,1,2,4};
    static const int mini_points[]={100,200,400},mini_sent[]={0,0,1};
    static const int full_points[]={400,800,1200,1600},full_sent[]={0,2,4,6};
    if(spin==2){*name=7+lines;*points=full_points[lines];*sent=full_sent[lines];}
    else if(spin==1){*name=4+lines;*points=mini_points[lines];*sent=mini_sent[lines];}
    else {*name=lines==0?-1:lines-1;*points=ordinary_points[lines];*sent=ordinary_sent[lines];}
}
static void summary(const Game *g){
    const State *s=&g->state;const Statistics *a=&s->stats;
    printf("summary game %d score %d level %d lines %d pieces %d\n",g->number,s->score,s->level,s->lines,s->pieces);
    printf("clears single %d double %d triple %d tetris %d perfect %d\n",a->clears[0],a->clears[1],a->clears[2],a->clears[3],a->perfect);
    printf("tspins mini %d mini_single %d mini_double %d zero %d single %d double %d triple %d\n",a->clears[4],a->clears[5],a->clears[6],a->clears[7],a->clears[8],a->clears[9],a->clears[10]);
    printf("pieces");for(int i=0;i<7;++i)printf(" %c %d",kind_names[i],a->kinds[i]);puts("");
    printf("best combo %d chain %d holds %d drops %d faults %d\n",a->combo,a->chain,a->holds,a->drops,a->faults);
    printf("garbage sent %d cancelled %d received %d\n",a->sent,a->cancelled,a->received);
    int numerator[]={a->sent,a->sent,a->operations},denominator[]={s->pieces,s->lines,s->pieces};
    const char *labels[]={"app","apl","kpp"};
    printf("rates");for(int i=0;i<3;++i){int q=denominator[i]?100*numerator[i]/denominator[i]:0;printf(" %s %d.%02d",labels[i],q/100,q%100);}puts("");
}
static void game_over(Game *g,const char *reason){printf("game over %s\n",reason);summary(g);g->state.ended=true;}
static void add_bag(State *s){
    int pieces[7]={0,1,2,3,4,5,6};
    for(int i=6;i>=1;--i){s->random=seed_step(s->random);int j=(int)(s->random%(i+1));int a=pieces[i];pieces[i]=pieces[j];pieces[j]=a;}
    for(int i=0;i<7;++i)if(s->queue_len<MAX_QUEUE)s->queue[s->queue_len++]=pieces[i];
}
static int next_piece(State *s){
    int kind=s->queue[0];memmove(s->queue,s->queue+1,sizeof(int)*(size_t)(--s->queue_len));
    if(s->queue_len<5)add_bag(s);
    return kind;
}
static void spawn_piece(Game *g,int kind){
    State *s=&g->state;
    s->kind=kind;s->position=spawn_position(kind);s->last=0;s->test=0;s->keys=0;s->drop=0;s->fall=0;s->ground=0;s->resets=0;
    s->lowest=lowest_row(kind,s->position);
    if(!fits(s->board,kind,s->position))game_over(g,"block out");
}
static void new_game(Game *g,int seed,int level){
    for(int i=0;i<g->save_len;++i)free(g->saves[i].history);
    memset(g,0,sizeof(*g));g->number=++serial_number;
    g->state.random=seed;g->state.initial_level=level;g->state.level=level;g->state.hold=-1;
    add_bag(&g->state);
    int kind=next_piece(&g->state);spawn_piece(g,kind);g->start=g->state;
}
static void update_position(State *s,Position p,int last,int test){
    s->position=p;s->last=last;s->test=test;
    int lowest=lowest_row(s->kind,p);
    if(lowest<s->lowest){s->lowest=lowest;s->resets=0;}
}
static bool grounded(const State *s){Position p;int test;return !try_move(s->board,s->kind,s->position,4,&p,&test);}
static void give_drops(State *s,int points){s->score+=points;s->drop+=points;s->stats.drops+=points;}
static bool insert_garbage(Game *g,int rows,int hole){
    State *s=&g->state;
    for(int r=22-rows;r<22;++r)if(s->board[r]!=0){game_over(g,"top out");return false;}
    memmove(s->board+rows,s->board,sizeof(int)*(size_t)(22-rows));
    for(int r=0;r<rows;++r)s->board[r]=1023^(1<<(hole-1));
    return true;
}
static void print_ops(const int ops[],int count){for(int i=0;i<count;++i)printf("%s%s",i?" ":"",operation_names[ops[i]]);}
static void cancel_garbage(State *s,int n){
    while(n>0&&s->pending_len>0){int q=s->pending[0]<n?s->pending[0]:n;s->pending[0]-=q;n-=q;
        if(s->pending[0]==0){--s->pending_len;memmove(s->pending,s->pending+1,(size_t)s->pending_len*sizeof(int));}
    }
}
static void lock_piece(Game *g){
    State *s=&g->state;int kind=s->kind;Position p=s->position;
    Cell old_cells[4];piece_cells(kind,p,old_cells);
    int last=0,route_count=search_routes(s->board,kind,spawn_position(kind),&p,&last);
    int shortest[MAX_OPERATIONS],shortest_len=route_count?reconstruct_ops(last,shortest):-1;
    int spin=kind==2&&s->last==2?t_spin(s->board,p,s->test):0;
    int board[22];int lines=place_piece(s->board,kind,p,board);memcpy(s->board,board,sizeof(board));
    if(g->history_len<MAX_HISTORY)g->history[g->history_len++]=g->start;
    ++s->pieces;++s->stats.kinds[kind];s->stats.operations+=s->keys;
    int name,points,sent;clear_info(spin,lines,&name,&points,&sent);
    int level=s->level;points*=level;bool back=false;
    if(lines>0){++s->streak;if(lines==4||spin){++s->chain;back=s->chain>=2;}else s->chain=0;}else s->streak=0;
    if(back){points=points*3/2;++sent;}
    int combo=s->streak-1,combo_points=combo>=1?50*combo*level:0;
    static const int combo_sent[]={0,1,1,2,2,3,3,4,4,4,5};
    if(combo>=0)sent+=combo_sent[combo>10?10:combo];
    bool perfect=lines>0;
    if(perfect)for(int i=0;i<22;++i)if(s->board[i]){perfect=false;break;}
    int perfect_points=0;
    if(perfect){static const int p_points[]={800,1200,1800,2000};perfect_points=(lines==4&&back?3200:p_points[lines-1])*level;sent+=10;++s->stats.perfect;}
    int gained=points+combo_points+perfect_points;
    s->score+=gained;s->lines+=lines;s->stats.sent+=sent;
    if(combo>s->stats.combo)s->stats.combo=combo;
    if(s->chain>s->stats.chain)s->stats.chain=s->chain;
    printf("lock %d %c %c %d %d keys %d ",s->pieces,kind_names[kind],"0R2L"[p.s],p.x,p.y,s->keys);
    if(shortest_len<0)printf("-");else printf("%d",shortest_len);
    printf(" drop %d lines %d sent %d +%d total %d\n",s->drop,lines,sent,gained,s->score);
    if(shortest_len>=0&&s->keys>shortest_len){++s->stats.faults;printf("finesse ");if(shortest_len)print_ops(shortest,shortest_len);else printf("none");puts("");}
    if(name>=0){++s->stats.clears[name];printf("clear %s %d",clear_names[name],points);
        if(back)printf(" b2b");
        if(combo>=1)printf(" combo %d %d",combo,combo_points);
        if(perfect)printf(" perfect %d",perfect_points);
        puts("");
    }
    int next_level=s->initial_level+s->lines/10;
    if(next_level>level){s->level=next_level;printf("level %d\n",s->level);}
    bool lockout=true;for(int i=0;i<4;++i)if(old_cells[i].y<21)lockout=false;
    if(lockout){game_over(g,"lock out");return;}
    int pending=sum_pending(s),cancelled=sent<pending?sent:pending;
    cancel_garbage(s,cancelled);
    if(cancelled){s->stats.cancelled+=cancelled;printf("cancel %d pending %d\n",cancelled,sum_pending(s));}
    if(lines==0){int risen=0;
        while(s->pending_len>0&&risen<8){int count=s->pending[0]<8-risen?s->pending[0]:8-risen;
            s->random=seed_step(s->random);int hole=(int)(s->random%10)+1;
            if(!insert_garbage(g,count,hole))return;
            s->stats.received+=count;risen+=count;cancel_garbage(s,count);
            printf("rise %d hole %d pending %d\n",count,hole,sum_pending(s));
        }
    }
    s->used_hold=false;int next=next_piece(s);spawn_piece(g,next);if(!s->ended)g->start=*s;
}
static void operation(Game *g,int op){
    State *s=&g->state;
    if(op>=0&&op<8){
        ++s->keys;Position p;int test;
        if(!try_move(s->board,s->kind,s->position,op,&p,&test)){printf("fail %s\n",operation_names[op]);return;}
        if(op==4||op==5){give_drops(s,s->position.y-p.y);update_position(s,p,1,0);s->fall=0;s->ground=0;}
        else{update_position(s,p,op>=6?2:1,test);if(s->ground>0&&s->resets<15){s->ground=0;++s->resets;}}
    }else if(op==8){
        Position p=landing(s->board,s->kind,s->position);int rows=s->position.y-p.y;
        give_drops(s,2*rows);if(rows>0)update_position(s,p,1,0);lock_piece(g);
    }else if(op==9){
        if(grounded(s))lock_piece(g);else puts("fail LOCK");
    }else{
        if(s->used_hold){puts("fail HOLD");return;}
        s->used_hold=true;++s->stats.holds;int previous=s->hold;s->hold=s->kind;
        spawn_piece(g,previous>=0?previous:next_piece(s));
    }
}
static void tick(Game *g){
    State *s=&g->state;
    if(!grounded(s)){
        s->ground=0;++s->fall;
        static const int intervals[]={60,48,37,28,21,16,11,8,6,4,3,2};
        int interval=s->level>=13?1:intervals[s->level-1];
        if(s->fall>=interval){Position p=s->position;--p.y;update_position(s,p,1,0);s->fall=0;}
    }else{++s->ground;if(s->ground>=30)lock_piece(g);}
}
static void add_candidate(const int board[22],int kind,Position p,const int *prefix,int prefix_len,const int *rot,int rot_len,const int *shift,int shift_len,int start_index,int *count){
    Position end=landing(board,kind,p);
    Cell cells[4];piece_cells(kind,end,cells);
    int indexes[4];for(int i=0;i<4;++i)indexes[i]=(cells[i].y-1)*10+cells[i].x-1;
    qsort(indexes,4,sizeof(int),compare_int);
    for(int i=start_index;i<*count;++i){
        bool same=true;
        for(int j=0;j<4;++j)if(candidates[i].occupied[j]!=indexes[j]){same=false;break;}
        if(same)return;
    }
    if(*count>=MAX_CANDIDATES)return;
    Candidate *c=&candidates[*count];c->kind=kind;c->count=0;c->index=*count;
    memcpy(c->occupied,indexes,sizeof(indexes));
    for(int i=0;i<prefix_len&&c->count<MAX_OPERATIONS;++i)c->ops[c->count++]=prefix[i];
    for(int i=0;i<rot_len&&c->count<MAX_OPERATIONS;++i)c->ops[c->count++]=rot[i];
    for(int i=0;i<shift_len&&c->count<MAX_OPERATIONS;++i)c->ops[c->count++]=shift[i];
    if(c->count<MAX_OPERATIONS)c->ops[c->count++]=8;
    int after[22];int lines=place_piece(board,kind,end,after);int heights[10],holes,bump;
    c->value=evaluate_well(after,lines,heights,&holes,&bump);
    ++*count;
}
static int append_candidates(const State *s,int kind,Position start,const int *prefix,int prefix_len,int count){
    static const int rotations[4][2]={{-1,-1},{6,-1},{6,6},{7,-1}};
    int start_index=count;
    for(int r=0;r<4;++r){
        Position p=start;bool valid=true;int rot[2],rot_len=0;
        for(int j=0;j<2;++j)if(rotations[r][j]>=0){
            Position q;int test;
            if(!try_move(s->board,kind,p,rotations[r][j],&q,&test)){valid=false;break;}
            p=q;rot[rot_len++]=rotations[r][j];
        }
        if(!valid)continue;
        add_candidate(s->board,kind,p,prefix,prefix_len,rot,rot_len,NULL,0,start_index,&count);
        for(int direction=0;direction<=1;++direction){
            Position q=p;int shifts[MAX_OPERATIONS],shift_len=0;
            while(shift_len<MAX_OPERATIONS-5){
                Position next;int test;
                if(!try_move(s->board,kind,q,direction,&next,&test))break;
                q=next;shifts[shift_len++]=direction;
                add_candidate(s->board,kind,q,prefix,prefix_len,rot,rot_len,shifts,shift_len,start_index,&count);
            }
        }
    }
    return count;
}
static int compare_candidates(const void *left,const void *right){
    const Candidate *a=left,*b=right;
    if(a->value!=b->value)return a->value>b->value?-1:1;
    return a->index<b->index?-1:a->index>b->index?1:0;
}
static int ranked(const State *s){
    int count=append_candidates(s,s->kind,s->position,NULL,0,0);
    int held=s->hold>=0?s->hold:s->queue[0];int prefix[]={10};
    if(!s->used_hold&&fits(s->board,held,spawn_position(held)))count=append_candidates(s,held,spawn_position(held),prefix,1,count);
    qsort(candidates,(size_t)count,sizeof(Candidate),compare_candidates);
    return count;
}
static int compare_spin(const void *left,const void *right){
    const SpinCandidate *a=left,*b=right;
    if(a->p.y!=b->p.y)return a->p.y-b->p.y;
    if(a->p.x!=b->p.x)return a->p.x-b->p.x;
    return a->p.s-b->p.s;
}
static void command_spins(const State *s){
    if(s->kind!=2){puts("spins 0");return;}
    int count=search_routes(s->board,2,s->position,NULL,NULL),found=0;
    for(int i=0;i<count;++i){
        Position start=bfs[i].p;
        for(int op=6;op<=7;++op){
            Position p,down;int test,unused;
            if(!try_move(s->board,2,start,op,&p,&test))continue;
            if(try_move(s->board,2,p,4,&down,&unused))continue;
            int spin=t_spin(s->board,p,test);
            if(!spin)continue;
            int old=-1;for(int j=0;j<found;++j)if(same_position(spins[j].p,p)){old=j;break;}
            if(old>=0){if(spin>spins[old].spin)spins[old].spin=spin;}
            else if(found<MAX_BFS)spins[found++]=(SpinCandidate){p,spin};
        }
    }
    qsort(spins,(size_t)found,sizeof(SpinCandidate),compare_spin);
    for(int i=0;i<found;++i){int after[22],name,points,sent;
        int lines=place_piece(s->board,2,spins[i].p,after);clear_info(spins[i].spin,lines,&name,&points,&sent);
        printf("spin %c %d %d %s\n","0R2L"[spins[i].p.s],spins[i].p.x,spins[i].p.y,clear_names[name]);
    }
    printf("spins %d\n",found);
}
static void print_board(const State *s){
    bool current[22][10]={0},ghost[22][10]={0};
    if(!s->ended){
        Cell c[4],g[4];piece_cells(s->kind,s->position,c);piece_cells(s->kind,landing(s->board,s->kind,s->position),g);
        for(int i=0;i<4;++i){current[c[i].y-1][c[i].x-1]=true;ghost[g[i].y-1][g[i].x-1]=true;}
    }
    for(int r=22;r>=1;--r){printf("%2d ",r);
        for(int c=1;c<=10;++c){char ch=s->board[r-1]&(1<<(c-1))?'#':current[r-1][c-1]?'@':ghost[r-1][c-1]?'+':'.';putchar(ch);}
        puts("");
    }
}
static void save_game(Game *g,const char *name){
    Save *v=NULL;
    for(int i=0;i<g->save_len;++i)if(strcmp(g->saves[i].name,name)==0){v=&g->saves[i];break;}
    if(!v){if(g->save_len>=MAX_SAVES)return;v=&g->saves[g->save_len++];memset(v,0,sizeof(*v));strcpy(v->name,name);}
    free(v->history);v->history=NULL;v->history_len=g->history_len;
    v->state=g->state;v->start=g->start;
    if(v->history_len){v->history=malloc((size_t)v->history_len*sizeof(State));if(!v->history)exit(2);memcpy(v->history,g->history,(size_t)v->history_len*sizeof(State));}
}
static Save *find_save(Game *g,const char *name){for(int i=0;i<g->save_len;++i)if(strcmp(g->saves[i].name,name)==0)return &g->saves[i];return NULL;}
static void load_game(Game *g,Save *v){g->state=v->state;g->start=v->start;g->history_len=v->history_len;if(v->history_len)memcpy(g->history,v->history,(size_t)v->history_len*sizeof(State));}
static void command(Game *g,int id,int argc,char *argv[]){
    State *s=&g->state;
    if(id==1){print_board(s);return;}
    if(id==2){printf("hold %c next ",s->hold<0?'-':kind_names[s->hold]);for(int i=0;i<5;++i)putchar(kind_names[s->queue[i]]);puts("");return;}
    if(id==3){
        int n=atoi(argv[0]),queue[MAX_QUEUE],len=s->queue_len;memcpy(queue,s->queue,(size_t)len*sizeof(int));int64_t random=s->random;
        while(len<n){int pieces[7]={0,1,2,3,4,5,6};for(int i=6;i>=1;--i){random=seed_step(random);int j=(int)(random%(i+1)),temp=pieces[i];pieces[i]=pieces[j];pieces[j]=temp;}for(int i=0;i<7;++i)queue[len++]=pieces[i];}
        printf("preview ");for(int i=0;i<n;++i)putchar(kind_names[queue[i]]);puts("");return;
    }
    if(id==4){
        printf("score %d level %d lines %d pieces %d\n",s->score,s->level,s->lines,s->pieces);
        if(s->ended)printf("piece -");else printf("piece %c %c %d %d",kind_names[s->kind],"0R2L"[s->position.s],s->position.x,s->position.y);
        printf(" streak %d chain %d pending %d\n",s->streak,s->chain,sum_pending(s));return;
    }
    if(id==5){int heights[10],holes,bump;int value=evaluate_well(s->board,0,heights,&holes,&bump);
        printf("heights");for(int i=0;i<10;++i)printf(" %d",heights[i]);puts("");
        printf("holes %d bumpiness %d value %d\n",holes,bump,value);return;
    }
    if(id==6){int row=atoi(argv[0]);const char *pattern=argv[1];Cell c[4];piece_cells(s->kind,s->position,c);
        for(int i=0;i<4;++i)if(c[i].y==row&&pattern[c[i].x-1]=='#'){puts("ERROR overlap");return;}
        int mask=0;for(int i=0;i<10;++i)if(pattern[i]=='#')mask|=1<<i;
        s->board[row-1]=mask;puts("OK");return;
    }
    if(id==7){int n=atoi(argv[0]),hole=atoi(argv[1]);if(!insert_garbage(g,n,hole))return;
        for(int j=0;j<=n;++j){Position p=s->position;p.y+=j;if(fits(s->board,s->kind,p)){s->position=p;puts("OK");return;}}
        game_over(g,"top out");return;
    }
    if(id==8){s->pending[s->pending_len++]=atoi(argv[0]);printf("pending %d\n",sum_pending(s));return;}
    if(id==9){int n=atoi(argv[0]);for(int i=0;i<n&&!s->ended;++i)tick(g);return;}
    if(id==10){if(!g->history_len){puts("ERROR nothing to undo");return;}
        g->state=g->history[--g->history_len];g->start=g->state;
        printf("undo %d %c\n",g->state.pieces,kind_names[g->state.kind]);return;
    }
    if(id==11){save_game(g,argv[0]);puts("OK");return;}
    if(id==12){Save *v=find_save(g,argv[0]);if(!v){puts("ERROR unknown save");return;}load_game(g,v);printf("load %d %c\n",g->state.pieces,kind_names[g->state.kind]);return;}
    if(id==13){command_spins(s);return;}
    if(id==14){int n=ranked(s),limit=atoi(argv[0]);if(limit>n)limit=n;
        for(int i=0;i<limit;++i){printf("hint %d %c ",i+1,kind_names[candidates[i].kind]);print_ops(candidates[i].ops,candidates[i].count);printf(" value %d\n",candidates[i].value);}
        return;
    }
    if(id==15){int iterations=atoi(argv[0]);
        for(int i=0;i<iterations&&!s->ended;++i){int n=ranked(s);if(n<=0)break;
            Candidate c=candidates[0];printf("auto %c ",kind_names[c.kind]);print_ops(c.ops,c.count);puts("");
            for(int j=0;j<c.count&&!s->ended;++j)operation(g,c.ops[j]);
        }
    }
    (void)argc;
}
static int find_name(const char *name,const char **names,int size){for(int i=0;i<size;++i)if(strcmp(name,names[i])==0)return i;return -1;}
static bool valid_number(const char *s,int min,int max){
    int64_t n=0;if(!s||!*s||(s[0]=='0'&&s[1]))return false;
    for(const char *p=s;*p;++p){if(!isdigit((unsigned char)*p))return false;n=n*10+(*p-'0');if(n>max)return false;}
    return n>=min;
}
static bool valid_arguments(int command_id,int argc,char *argv[]){
    if(command_id==0)return argc==2&&valid_number(argv[0],1,2147483646)&&valid_number(argv[1],1,15);
    if(command_id==6){if(argc!=2||!valid_number(argv[0],1,22)||strlen(argv[1])!=10)return false;
        bool empty=false;for(int i=0;i<10;++i){if(argv[1][i]=='.')empty=true;else if(argv[1][i]!='#')return false;}return empty;
    }
    if(command_id==7)return argc==2&&valid_number(argv[0],1,10)&&valid_number(argv[1],1,10);
    if(command_id==11||command_id==12){if(argc!=1){return false;}size_t len=strlen(argv[0]);if(len<1||len>8)return false;for(size_t i=0;i<len;++i)if(argv[0][i]<'a'||argv[0][i]>'z')return false;return true;}
    int limit=command_id==3?14:command_id==8?20:command_id==9?1000:command_id==14?10:command_id==15?50:0;
    if(limit)return argc==1&&valid_number(argv[0],1,limit);
    return argc==0;
}
int main(void){
    init_shapes();
    game=calloc(1,sizeof(Game));if(!game)return 1;
    int count=0;if(scanf("%d\n",&count)!=1)return 1;
    for(int i=0;i<count;++i){char line[256];if(!fgets(line,sizeof(line),stdin))break;
        line[strcspn(line,"\r\n")]=0;
        char *argv[120];int argc=0;
        char *save=NULL;for(char *token=strtok_r(line," ",&save);token;token=strtok_r(NULL," ",&save))if(argc<120)argv[argc++]=token;
        if(!argc)continue;
        int id=find_name(argv[0],command_names,16);
        if(id>=0){
            if(!valid_arguments(id,argc-1,argv+1)){puts("ERROR bad arguments");continue;}
            if(id==0){
                if(serial_number>0&&!game->state.ended){puts("game stopped");summary(game);}
                printf("game %d seed %d level %d\n",serial_number+1,atoi(argv[1]),atoi(argv[2]));
                new_game(game,atoi(argv[1]),atoi(argv[2]));
            }else if(serial_number==0)puts("ERROR no game");
            else if(game->state.ended&&id!=1&&id!=2&&id!=3&&id!=4&&id!=5&&id!=12)puts("ERROR game over");
            else command(game,id,argc-1,argv+1);
        }else{
            int ops[120],invalid=-1;
            for(int j=0;j<argc;++j){ops[j]=find_name(argv[j],operation_names,11);if(ops[j]<0){invalid=j;break;}}
            if(invalid>=0)printf("ERROR unknown %s\n",argv[invalid]);
            else if(serial_number==0)puts("ERROR no game");
            else if(game->state.ended)puts("ERROR game over");
            else for(int j=0;j<argc&&!game->state.ended;++j)operation(game,ops[j]);
        }
    }
    if(serial_number>0&&!game->state.ended){puts("game stopped");summary(game);}
    for(int i=0;i<game->save_len;++i)free(game->saves[i].history);
    free(game);
    return 0;
}
