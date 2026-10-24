#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
typedef long long I;
typedef struct {
    char **v;
    int n, cap;
} Lines;
typedef struct {
    char id[9], name[9];
    int trader, type, side, condition, status;
    I price, trigger, peak, quantity, remaining, visible, filled, value, priority;
    Lines history;
} Order;
typedef struct {
    char name[9];
    I bought, sold, cash, fees, limit;
    int limited;
} Trader;
typedef struct {
    I price, quantity, buy_fee, sell_fee;
    int buy, sell, taker;
} Trade;
typedef struct {
    I price, visible;
    int count;
} Level;
static Order orders[1000];
static Trader traders[2000];
static int no, nt;
static Trade *trades;
static int nx, tx;
static I priority, maker, taker, band, tick=1, lot=1;
static int halted;
static const char *types[]={"LIMIT","MARKET","STOP","STOPLIMIT","ICEBERG"}, *states[]={"PENDING","OPEN","PARTIAL","FILLED","CANCELLED"};

static I min(I a, I b) {
    return a<b?a:b;
}

static I absolute(I x) {
    return x<0?-x:x;
}

static void history(int i, const char *format,...) {
    char text[200];
    va_list ap;
    va_start(ap, format);
    vsnprintf(text, sizeof text, format, ap);
    va_end(ap);
    Lines *h=&orders[i].history;
    if (h->n==h->cap) {
        h->cap=h->cap?h->cap*2:8;
        h->v=realloc(h->v,(size_t)h->cap*sizeof *h->v);
    }
    h->v[h->n]=malloc(strlen(text)+1);
    strcpy(h->v[h->n++], text);
}

static int find_order(const char *id) {
    for (int i=0; i<no; i++) if (!strcmp(id, orders[i].id)) return i;
    return -1;
}

static int find_trader(const char *name) {
    for (int i=0; i<nt; i++) if (!strcmp(name, traders[i].name)) return i;
    return -1;
}

static int register_trader(const char *name) {
    int i=find_trader(name);
    if (i<0) {
        i=nt++;
        strcpy(traders[i].name, name);
    }
    return i;
}

static int resting(int i) {
    return orders[i].status==1||orders[i].status==2;
}

static int active(int i) {
    return orders[i].status<=2;
}

static I net(int t) {
    return traders[t].bought-traders[t].sold;
}

static I pnl(int t) {
    return traders[t].cash+net(t)*(nx?trades[nx-1].price:0);
}

static I exposure(int t, int side, int exclude) {
    I n=side?-net(t):net(t);
    for (int i=0; i<no; i++) if (i!=exclude&&active(i)&&orders[i].trader==t&&orders[i].side==side)n+=orders[i].remaining;
    return n;
}

static int risk(int t, int side, I q, int exclude) {
    return t>=0&&traders[t].limited&&exposure(t, side, exclude)+q>traders[t].limit;
}

static int outside(I p) {
    return band&&nx&&absolute(p-trades[nx-1].price)>band;
}

static int best(int side) {
    int b=-1;
    for (int i=0; i<no; i++) if (resting(i)&&orders[i].side==side&&(b<0||(side?orders[i].price<orders[b].price:orders[i].price>orders[b].price)||(orders[i].price==orders[b].price&&orders[i].priority<orders[b].priority)))b=i;
    return b;
}

static int matchable(int side, I price, I other) {
    return price<0||(side?other>=price:other<=price);
}

static void decimal(I v, char *s) {
    sprintf(s,"%lld.%02lld", v/100, v%100);
}

static void order_line(int i) {
    Order *o=&orders[i];
    printf("ORDER %s %s %lld/%lld\n", o->id, states[o->status], o->filled, o->quantity);
}

static void details(int i) {
    Order *o=&orders[i];
    char price[40]="-", avg[40]="-";
    if (o->price>=0)sprintf(price,"%lld", o->price);
    if (o->filled)decimal(o->value*100/o->filled, avg);
    printf("%s %s %s %s %s %s %lld/%lld avg %s", o->id, traders[o->trader].name, types[o->type], o->side?"SELL":"BUY", price, states[o->status], o->filled, o->quantity, avg);
    if (o->type==2||o->type==3)printf(" trigger %lld", o->trigger);
    puts("");
}

static void position(int t) {
    Trader *v=&traders[t];
    printf("POSITION %s bought %lld sold %lld net %lld cash %lld fees %lld pnl %lld\n", v->name, v->bought, v->sold, net(t), v->cash, v->fees, pnl(t));
}

static void trade_line(int i) {
    Trade *x=&trades[i];
    Order *b=&orders[x->buy], *s=&orders[x->sell];
    printf("TRADE %d %lld %lld %s %s %s %s\n", i+1, x->price, x->quantity, b->id, traders[b->trader].name, s->id, traders[s->trader].name);
}

static void execute(int a) {
    Order *x=&orders[a];
    while (x->remaining) {
        int b=best(1-x->side);
        if (b<0||!matchable(x->side, x->price, orders[b].price))break;
        Order *y=&orders[b];
        if (x->trader==y->trader) {
            printf("STP %s %lld\n", y->id, y->remaining);
            history(b,"STP %lld", y->remaining);
            y->remaining=y->visible=0;
            y->status=4;
            continue;
        }
        I q=min(x->remaining, y->visible), p=y->price;
        int bi=x->side?b:a, si=x->side?a:b;
        I bf=q*(bi==a?taker:maker), sf=q*(si==a?taker:maker);
        if (nx==tx) {
            tx=tx?tx*2:32;
            trades=realloc(trades,(size_t)tx*sizeof *trades);
        }
        trades[nx++]=(Trade){p, q, bf, sf, bi, si, a};
        x->remaining-=q;
        y->remaining-=q;
        y->visible-=q;
        x->filled+=q;
        y->filled+=q;
        x->value+=q*p;
        y->value+=q*p;
        Trader *bt=&traders[orders[bi].trader], *st=&traders[orders[si].trader];
        bt->bought+=q;
        st->sold+=q;
        bt->cash-=q*p+bf;
        st->cash+=q*p-sf;
        bt->fees+=bf;
        st->fees+=sf;
        trade_line(nx-1);
        history(a,"FILL %d %lld %lld", nx, p, q);
        history(b,"FILL %d %lld %lld", nx, p, q);
        if (!y->remaining)y->status=3;
        else {
            y->status=2;
            if (!y->visible) {
                y->priority=++priority;
                y->visible=min(y->peak, y->remaining);
                history(b,"REFRESH %lld %lld", y->visible, y->remaining-y->visible);
                printf("REFRESH %s %lld %lld\n", y->id, y->visible, y->remaining-y->visible);
            }
        }
    }
}

static void finish(int a, int stay) {
    Order *x=&orders[a];
    if (!x->remaining)x->status=3;
    else if (stay) {
        x->priority=++priority;
        x->visible=x->type==4?min(x->peak, x->remaining):x->remaining;
        x->status=x->filled?2:1;
        history(a,"REST %lld %lld", x->price, x->visible);
    } else {
        history(a,"EXPIRE %lld", x->remaining);
        x->remaining=x->visible=0;
        x->status=4;
    }
    order_line(a);
}

static void triggers(void) {
    while (nx) {
        int selected[1000], n=0;
        I last=trades[nx-1].price;
        for (int i=0; i<no; i++) if (orders[i].status==0&&(orders[i].side?last<=orders[i].trigger:last>=orders[i].trigger))selected[n++]=i;
        if (!n)break;
        for (int j=0; j<n; j++)orders[selected[j]].status=4;
        for (int j=0; j<n; j++) {
            int i=selected[j];
            printf("TRIGGER %s\n", orders[i].id);
            history(i,"TRIGGER");
            execute(i);
            finish(i, orders[i].type==3);
        }
    }
}

static void cancel(int i) {
    history(i,"CANCEL %lld", orders[i].remaining);
    orders[i].remaining=orders[i].visible=0;
    orders[i].status=4;
    order_line(i);
}

static int levels(int side, Level *v) {
    int n=0;
    for (int i=0; i<no; i++) if (resting(i)&&orders[i].side==side) {
        int j=0;
        for (; j<n&&v[j].price!=orders[i].price; j++);
        if (j==n)v[n++]=(Level) {
            orders[i].price,0,0
        };
        v[j].visible+=orders[i].visible;
        v[j].count++;
    }
    for (int i=1; i<n; i++) {
        Level x=v[i];
        int j=i;
        while (j&&v[j-1].price>x.price) {
            v[j]=v[j-1];
            j--;
        }
        v[j]=x;
    }
    return n;
}

static int trader_before(int a, int b, int ranked) {
    if (ranked) {
        if (pnl(a)!=pnl(b)) return pnl(a)>pnl(b);
        I av=traders[a].bought+traders[a].sold, bv=traders[b].bought+traders[b].sold;
        if (av!=bv) return av>bv;
    }
    return strcmp(traders[a].name, traders[b].name)<0;
}

static void command(char **w, int n) {
    char *c=w[0];
    int type=-1;
    for (int i=0; i<5; i++) if (!strcmp(c, types[i]))type=i;
    if (type>=0) {
        int side=!strcmp(w[3],"SELL"), t=find_trader(w[2]), cond=0;
        I p=-1, r=0, q=0, k=0;
        if (type==0||type==4) {
            p=atoll(w[4]);
            q=atoll(w[5]);
            if (type==4)k=atoll(w[6]);
            else if (n==7)cond=!strcmp(w[6],"IOC")?1:!strcmp(w[6],"FOK")?2:3;
        } else if (type==1)q=atoll(w[4]);
        else {
            r=atoll(w[4]);
            if (type==2)q=atoll(w[5]);
            else {
                p=atoll(w[5]);
                q=atoll(w[6]);
            }
        }
        const char *err=NULL;
        if (halted)err="halted";
        else if (find_order(w[1])>=0)err="duplicate id";
        else if ((p==0)||((type==2||type==3)&&!r))err="invalid price";
        else if (!q)err="invalid quantity";
        else if ((p>=0&&p%tick)||((type==2||type==3)&&r%tick))err="invalid tick";
        else if (q%lot)err="invalid lot";
        else if (type==4&&(!k||k>q||k%lot))err="invalid peak";
        else if ((type==2||type==3)&&nx&&(side?r>=trades[nx-1].price:r<=trades[nx-1].price))err="invalid trigger";
        else if (p>=0&&outside(p))err="outside band";
        else if (risk(t, side, q,-1))err="risk limit";
        else if (cond==3&&best(1-side)>=0&&matchable(side, p, orders[best(1-side)].price))err="would cross";
        else if (cond==2) {
            I available=0;
            for (int i=0; i<no; i++) if (resting(i)&&orders[i].side!=side&&orders[i].trader!=t&&matchable(side, p, orders[i].price))available+=orders[i].remaining;
            if (available<q)err="unfillable";
        }
        if (err) {
            printf("REJECT %s %s\n", w[1], err);
            return;
        }
        int i=no++;
        Order *o=&orders[i];
        strcpy(o->id, w[1]);
        o->trader=register_trader(w[2]);
        o->type=type;
        o->side=side;
        o->condition=cond;
        o->price=p;
        o->trigger=r;
        o->peak=k;
        o->quantity=o->remaining=q;
        history(i,"ACCEPT");
        if (type==2||type==3) {
            o->status=0;
            order_line(i);
        } else {
            if (cond!=3)execute(i);
            finish(i, type==4||(type==0&&cond!=1));
            triggers();
        }
        return;
    }
    if (!strcmp(c,"CANCEL")||!strcmp(c,"REPLACE")) {
        int i=find_order(w[1]);
        int replace=!strcmp(c,"REPLACE");
        I p=replace?atoll(w[2]):0, q=replace?atoll(w[3]):0;
        const char *err=NULL;
        if (replace&&halted)err="halted";
        else if (i<0)err="unknown order";
        else if (replace?!resting(i):!active(i))err="not open";
        else if (replace) {
            Order *o=&orders[i];
            if (!p)err="invalid price";
            else if (!q)err="invalid quantity";
            else if (p!=o->price&&p%tick)err="invalid tick";
            else if (q%lot)err="invalid lot";
            else if (p==o->price&&q==o->remaining)err="no change";
            else if (p!=o->price&&outside(p))err="outside band";
            else if (q>o->remaining&&risk(o->trader, o->side, q, i))err="risk limit";
        }
        if (err) {
            printf("REJECT %s %s\n", w[1], err);
            return;
        }
        if (!replace)cancel(i);
        else {
            Order *o=&orders[i];
            int kept=p==o->price&&q<o->remaining;
            o->quantity=o->filled+q;
            history(i,"REPLACE %lld %lld %s", p, q, kept?"kept":"lost");
            printf("REPLACE %s %s\n", o->id, kept?"kept":"lost");
            o->remaining=q;
            if (kept) {
                o->visible=min(o->visible, q);
                order_line(i);
            } else {
                o->status=4;
                o->price=p;
                execute(i);
                finish(i,1);
                triggers();
            }
        }
        return;
    }
    if (!strcmp(c,"HALT")||!strcmp(c,"RESUME")) {
        int h=!strcmp(c,"HALT");
        if (halted==h)printf("ERROR %s\n", h?"already halted":"not halted");
        else {
            halted=h;
            puts(c);
        }
        return;
    }
    if (!strcmp(c,"RISK")) {
        int t=register_trader(w[1]);
        traders[t].limited=1;
        traders[t].limit=atoll(w[2]);
        printf("RISK %s %lld exposure buy %lld sell %lld\n", w[1], traders[t].limit, exposure(t,0,-1), exposure(t,1,-1));
        return;
    }
    if (!strcmp(c,"FEE")) {
        I a=atoll(w[1]), b=atoll(w[2]);
        if (a+b<0)puts("ERROR invalid fee");
        else {
            maker=a;
            taker=b;
            printf("FEE maker %lld taker %lld\n", a, b);
        }
        return;
    }
    if (!strcmp(c,"BAND")||!strcmp(c,"TICK")||!strcmp(c,"LOT")) {
        I v=atoll(w[1]);
        if (strcmp(c,"BAND")&&!v) {
            puts("ERROR invalid size");
            return;
        }
        if (!strcmp(c,"BAND"))band=v;
        else if (!strcmp(c,"TICK"))tick=v;
        else lot=v;
        printf("%s %lld\n", c, v);
        return;
    }
    if (!strcmp(c,"CANCELALL")||!strcmp(c,"ORDERS")||!strcmp(c,"POSITION")||!strcmp(c,"FILLS")) {
        int t=find_trader(w[1]);
        if (t<0) {
            puts("ERROR unknown trader");
            return;
        }
        if (!strcmp(c,"POSITION")) {
            position(t);
            return;
        }
        if (!strcmp(c,"FILLS")) {
            int count=0;
            I running=0;
            for (int j=0; j<nx; j++) if (orders[trades[j].buy].trader==t||orders[trades[j].sell].trader==t)count++;
            printf("FILLS %s %d\n", w[1], count);
            for (int j=0; j<nx; j++) {
                Trade *x=&trades[j];
                int buy=orders[x->buy].trader==t, i=buy?x->buy:x->sell;
                if (orders[i].trader!=t)continue;
                running+=buy?x->quantity:-x->quantity;
                printf("%d %s %lld %lld %s %s fee %lld net %lld\n", j+1, buy?"BUY":"SELL", x->price, x->quantity, orders[i].id, i==x->taker?"TAKER":"MAKER", buy?x->buy_fee:x->sell_fee, running);
            }
            return;
        }
        int count=0;
        for (int i=0; i<no; i++) if (active(i)&&orders[i].trader==t)count++;
        printf("%s %s %d\n", c, w[1], count);
        for (int i=0; i<no; i++) if (active(i)&&orders[i].trader==t) {
            if (!strcmp(c,"CANCELALL"))cancel(i);
            else details(i);
        }
        return;
    }
    if (!strcmp(c,"STATUS")||!strcmp(c,"HISTORY")) {
        int i=find_order(w[1]);
        if (i<0) {
            puts("ERROR unknown order");
            return;
        }
        if (!strcmp(c,"STATUS")) {
            printf("STATUS ");
            details(i);
        } else {
            printf("HISTORY %s %d\n", w[1], orders[i].history.n);
            for (int j=0; j<orders[i].history.n; j++)puts(orders[i].history.v[j]);
        }
        return;
    }
    if (!strcmp(c,"BOOK")||!strcmp(c,"IMPACT")) {
        Level bids[1000], asks[1000];
        int nb=levels(0, bids), na=levels(1, asks);
        if (!strcmp(c,"BOOK")) {
            I d=atoll(w[1]);
            if (!d) {
                puts("ERROR invalid depth");
                return;
            }
            printf("BOOK bids %d asks %d\n", nb, na);
            for (int i=(int)min(d, na)-1; i>=0; i--)printf("ASK %lld %lld %d\n", asks[i].price, asks[i].visible, asks[i].count);
            for (int i=nb-1; i>=0&&nb-i<=d; i--)printf("BID %lld %lld %d\n", bids[i].price, bids[i].visible, bids[i].count);
        } else {
            I q=atoll(w[2]), left=q, cost=0, total=0, worst=0;
            int side=!strcmp(w[1],"SELL"), nlev=side?nb:na, used=0;
            Level *v=side?bids:asks;
            if (!q) {
                puts("ERROR invalid quantity");
                return;
            }
            for (int j=0; j<nlev; j++) {
                Level x=v[side?nlev-1-j:j];
                total+=x.visible;
                if (left) {
                    I u=min(left, x.visible);
                    cost+=u*x.price;
                    left-=u;
                    worst=x.price;
                    used++;
                }
            }
            if (left)printf("IMPACT %s %lld insufficient %lld\n", w[1], q, total);
            else {
                char avg[40];
                decimal(cost*100/q, avg);
                printf("IMPACT %s %lld avg %s worst %lld levels %d\n", w[1], q, avg, worst, used);
            }
        }
        return;
    }
    if (!strcmp(c,"LAST")) {
        if (nx)printf("LAST %lld %lld\n", trades[nx-1].price, trades[nx-1].quantity);
        else puts("LAST none");
        return;
    }
    if (!strcmp(c,"SPREAD")) {
        int b=best(0), a=best(1);
        printf("SPREAD bid ");
        if (b<0)printf("none");
        else printf("%lld", orders[b].price);
        printf(" ask ");
        if (a<0)printf("none");
        else printf("%lld", orders[a].price);
        if (a>=0&&b>=0) {
            I x=orders[a].price, y=orders[b].price;
            printf(" spread %lld mid %lld.%d", x-y,(x+y)/2,(x+y)%2?5:0);
        }
        puts("");
        return;
    }
    if (!strcmp(c,"TRADES")||!strcmp(c,"BARS")) {
        I k=atoll(w[1]);
        if (!k) {
            puts("ERROR invalid count");
            return;
        }
        if (!strcmp(c,"TRADES")) {
            int m=(int)min(k, nx);
            printf("TRADES %d of %d\n", m, nx);
            for (int i=nx-m; i<nx; i++)trade_line(i);
        } else {
            printf("BARS %lld\n",(nx+k-1)/k);
            for (I a=0, g=1; a<nx; a+=k, g++) {
                I end=min(a+k, nx), hi=0, lo=trades[a].price, v=0;
                for (I j=a; j<end; j++) {
                    I p=trades[j].price;
                    if (p>hi)hi=p;
                    if (p<lo)lo=p;
                    v+=trades[j].quantity;
                }
                printf("%lld open %lld high %lld low %lld close %lld volume %lld\n", g, trades[a].price, hi, lo, trades[end-1].price, v);
            }
        }
        return;
    }
    if (!strcmp(c,"FLOW")) {
        I b=0, s=0;
        for (int i=0; i<nx; i++) if (orders[trades[i].taker].side)s+=trades[i].quantity;
        else b+=trades[i].quantity;
        printf("FLOW buy %lld sell %lld net %lld\n", b, s, b-s);
        return;
    }
    if (!strcmp(c,"VWAP")||!strcmp(c,"SUMMARY")) {
        I v=0, cost=0, fees=0, hi=0, lo=nx?trades[0].price:0;
        for (int i=0; i<nx; i++) {
            Trade x=trades[i];
            v+=x.quantity;
            cost+=x.price*x.quantity;
            fees+=x.buy_fee+x.sell_fee;
            if (x.price>hi)hi=x.price;
            if (x.price<lo)lo=x.price;
        }
        if (!strcmp(c,"VWAP")) {
            if (!nx)puts("VWAP none");
            else {
                char avg[40];
                decimal(cost*100/v, avg);
                printf("VWAP %s volume %lld trades %d\n", avg, v, nx);
            }
            return;
        }
        if (!nx)puts("SUMMARY trades 0");
        else printf("SUMMARY trades %d volume %lld open %lld high %lld low %lld close %lld fees %lld\n", nx, v, trades[0].price, hi, lo, trades[nx-1].price, fees);
    }
    int ranked=!strcmp(c,"RANK"), ids[2000];
    for (int i=0; i<nt; i++) {
        int j=i;
        while (j&&trader_before(i, ids[j-1], ranked)) {
            ids[j]=ids[j-1];
            j--;
        }
        ids[j]=i;
    }
    if (ranked)printf("RANK %d\n", nt);
    for (int j=0; j<nt; j++) {
        int i=ids[j];
        if (ranked)printf("%d %s pnl %lld volume %lld\n", j+1, traders[i].name, pnl(i), traders[i].bought+traders[i].sold);
        else position(i);
    }
}
int main(void) {
    char line[512], *w[10];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count=atoi(line);
    for (int k=0; k<count; k++) {
        if (!fgets(line, sizeof line, stdin))break;
        int n=0;
        for (char *s=strtok(line," \r\n"); s; s=strtok(NULL," \r\n"))w[n++]=s;
        command(w, n);
    }
    for (int i=0; i<no; i++) {
        for (int j=0; j<orders[i].history.n; j++)free(orders[i].history.v[j]);
        free(orders[i].history.v);
    }
    free(trades);
    return 0;
}
