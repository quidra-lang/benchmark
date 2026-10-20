import java.io.*;
import java.util.*;
public class Main {
    static class Rejection extends RuntimeException {
        Rejection(String s) {
            super(s);
        }
    }
    static void check(boolean bad, String reason) {
        if (bad) throw new Rejection(reason);
    }
    static String decimal(long n) {
        return n / 100 + "." + String.format(Locale.ROOT, "%02d", n % 100);
    }
    static class Order {
        String id, trader, type, side, condition, status = "OPEN";
        long price, trigger, peak, quantity, left, visible, filled, value, priority;
        List<String> history = new ArrayList<>(List.of("ACCEPT"));
        Order(String id, String trader, String type, String side, long q) {
            this.id=id;
            this.trader=trader;
            this.type=type;
            this.side=side;
            quantity=left=q;
        }
        boolean active() {
            return resting() || status.equals("PENDING");
        }
        boolean resting() {
            return status.equals("OPEN") || status.equals("PARTIAL");
        }
        boolean matches(long p) {
            return price == 0 || (side.equals("BUY") ? p <= price : p >= price);
        }
        boolean triggered(long p) {
            return side.equals("BUY") ? p >= trigger : p <= trigger;
        }
        String line() {
            return "ORDER "+id+" "+status+" "+filled+"/"+quantity;
        }
        String details() {
            return id+" "+trader+" "+type+" "+side+" "+(price==0?"-":price)+" "+status+" "+filled+"/"+quantity+
            " avg "+(filled==0?"-":decimal(value*100/filled))+(trigger==0?"":" trigger "+trigger);
        }
        void fill(int number, long p, long q) {
            left-=q;
            filled+=q;
            value+=p*q;
            history.add("FILL "+number+" "+p+" "+q);
        }
    }
    static class Trader {
        String name;
        long bought, sold, cash, fees;
        Long limit;
        Trader(String name) {
            this.name=name;
        }
        long net() {
            return bought-sold;
        }
        long volume() {
            return bought+sold;
        }
        long pnl(long mark) {
            return cash+net()*mark;
        }
        String position(long mark) {
            return "POSITION "+name+" bought "+bought+" sold "+sold+" net "+net()+" cash "+cash+" fees "+fees+" pnl "+pnl(mark);
        }
    }
    record Trade(int number, long price, long quantity, Order buy, Order sell, Order taker, long buyFee, long sellFee) {
        String line() {
            return "TRADE "+number+" "+price+" "+quantity+" "+buy.id+" "+buy.trader+" "+sell.id+" "+sell.trader;
        }
    }
    static class Level {
        long price, quantity;
        int count;
        Level(long p) {
            price=p;
        }
    }
    static class Engine {
        Map<String,Order> orders = new LinkedHashMap<>();
        Map<String,Trader> traders = new TreeMap<>();
        List<Order> pending = new ArrayList<>(), buys = new ArrayList<>(), sells = new ArrayList<>();
        List<Trade> trades = new ArrayList<>();
        StringBuilder out = new StringBuilder();
        long makerFee, takerFee, band, tick=1, lot=1, priority;
        boolean halted;
        void emit(Object... parts) {
            for(int i=0;i<parts.length;i++) {
                if(i>0) out.append(' ');
                out.append(parts[i]);
            }
            out.append('\n');
        }
        List<Order> book(String side) {
            return side.equals("BUY")?buys:sells;
        }
        List<Order> opposite(String side) {
            return side.equals("BUY")?sells:buys;
        }
        Comparator<Order> comparator(String side) {
            return Comparator.<Order>comparingLong(o -> side.equals("BUY")?-o.price:o.price).thenComparingLong(o -> o.priority);
        }
        Order best(List<Order> b) {
            return b.stream().min(comparator(b==buys?"BUY":"SELL")).orElse(null);
        }
        long last() {
            return trades.isEmpty()?0:trades.getLast().price;
        }
        Trader register(String name) {
            return traders.computeIfAbsent(name, Trader::new);
        }
        Trader trader(String name) {
            check(!traders.containsKey(name),"unknown trader");
            return traders.get(name);
        }
        Order order(String id) {
            check(!orders.containsKey(id),"unknown order");
            return orders.get(id);
        }
        List<Order> active(String name) {
            return orders.values().stream().filter(o -> o.trader.equals(name)&&o.active()).toList();
        }
        long exposure(String name,String side,Order excluded) {
            Trader t=traders.get(name);
            long x=side.equals("BUY")?t.net():-t.net();
            for(Order o:active(name)) if(o!=excluded&&o.side.equals(side)) x+=o.left;
            return x;
        }
        void risk(String name,String side,long q,Order excluded) {
            Trader t=traders.get(name);
            check(t!=null&&t.limit!=null&&exposure(name,side,excluded)+q>t.limit,"risk limit");
        }
        void band(long p) {
            check(band>0&&last()!=0&&Math.abs(p-last())>band,"outside band");
        }
        void accept(Order o) {
            register(o.trader);
            orders.put(o.id,o);
        }
        void match(Order x) {
            List<Order> b=opposite(x.side);
            while(x.left>0) {
                Order y=best(b);
                if(y==null||!x.matches(y.price)) break;
                if(y.trader.equals(x.trader)) {
                    emit("STP",y.id,y.left);
                    y.history.add("STP "+y.left);
                    b.remove(y);
                    y.left=0;
                    y.status="CANCELLED";
                    continue;
                }
                long q=Math.min(x.left,y.visible),p=y.price;
                Order buy=x.side.equals("BUY")?x:y,sell=buy==x?y:x;
                long xf=q*takerFee,yf=q*makerFee;
                Trade t=new Trade(trades.size()+1,p,q,buy,sell,x,buy==x?xf:yf,sell==x?xf:yf);
                trades.add(t);
                x.fill(t.number,p,q);
                y.fill(t.number,p,q);
                y.visible-=q;
                Trader bt=traders.get(buy.trader),st=traders.get(sell.trader);
                bt.bought+=q;
                bt.cash-=p*q+t.buyFee;
                bt.fees+=t.buyFee;
                st.sold+=q;
                st.cash+=p*q-t.sellFee;
                st.fees+=t.sellFee;
                emit(t.line());
                if(y.left==0) {
                    b.remove(y);
                    y.status="FILLED";
                }
                else {
                    y.status="PARTIAL";
                    if(y.visible==0) {
                        y.priority=++priority;
                        y.visible=Math.min(y.peak,y.left);
                        y.history.add("REFRESH "+y.visible+" "+(y.left-y.visible));
                        emit("REFRESH",y.id,y.visible,y.left-y.visible);
                    }
                }
            }
        }
        void post(Order o,boolean forceRest) {
            if(o.left==0) o.status="FILLED";
            else if(forceRest||o.type.equals("ICEBERG")||o.type.equals("STOPLIMIT")||(o.type.equals("LIMIT")&&!"IOC".equals(o.condition))) {
                o.priority=++priority;
                o.visible=o.peak==0?o.left:Math.min(o.peak,o.left);
                book(o.side).add(o);
                o.status=o.filled>0?"PARTIAL":"OPEN";
                o.history.add("REST "+o.price+" "+o.visible);
            } else {
                o.history.add("EXPIRE "+o.left);
                o.left=0;
                o.status="CANCELLED";
            }
            emit(o.line());
        }
        void trigger() {
            while(!trades.isEmpty()) {
                long p=last();
                List<Order> batch=pending.stream().filter(o -> o.triggered(p)).toList();
                if(batch.isEmpty()) return;
                pending.removeAll(batch);
                for(Order o:batch) {
                    emit("TRIGGER",o.id);
                    o.history.add("TRIGGER");
                    match(o);
                    post(o,false);
                }
            }
        }
        void cancel(Order o) {
            if(o.status.equals("PENDING")) pending.remove(o);
            else book(o.side).remove(o);
            o.history.add("CANCEL "+o.left);
            o.left=0;
            o.status="CANCELLED";
            emit(o.line());
        }
        void newOrder(String[] a) {
            String kind=a[0];
            boolean market=kind.equals("MARKET"),stop=kind.equals("STOP"),sl=kind.equals("STOPLIMIT"),ice=kind.equals("ICEBERG");
            long p=market||stop?0:Long.parseLong(a[sl?5:4]);
            long tr=stop||sl?Long.parseLong(a[4]):0;
            long q=Long.parseLong(a[market?4:sl?6:5]);
            Order o=new Order(a[1],a[2],kind,a[3],q);
            o.price=p;
            o.trigger=tr;
            if(ice) o.peak=Long.parseLong(a[6]);
            if(kind.equals("LIMIT")&&a.length==7) o.condition=a[6];
            check(halted,"halted");
            check(orders.containsKey(o.id),"duplicate id");
            check((!market&&!stop&&p==0)||((stop||sl)&&tr==0),"invalid price");
            check(q==0,"invalid quantity");
            check(p%tick!=0||tr%tick!=0,"invalid tick");
            check(q%lot!=0,"invalid lot");
            if(ice) check(o.peak==0||o.peak>q||o.peak%lot!=0,"invalid peak");
            if(stop||sl) check(last()!=0&&o.triggered(last()),"invalid trigger");
            if(p!=0) band(p);
            risk(o.trader,o.side,q,null);
            Order b=best(opposite(o.side));
            if("POSTONLY".equals(o.condition)) check(b!=null&&o.matches(b.price),"would cross");
            if("FOK".equals(o.condition)) {
                long total=0;
                for(Order y:opposite(o.side)) if(!y.trader.equals(o.trader)&&o.matches(y.price)) total+=y.left;
                check(total<q,"unfillable");
            }
            accept(o);
            if(stop||sl) {
                o.status="PENDING";
                pending.add(o);
                emit(o.line());
            }
            else {
                if(!"POSTONLY".equals(o.condition)) match(o);
                post(o,false);
                trigger();
            }
        }
        List<Level> levels(String side) {
            List<Order> sorted=new ArrayList<>(book(side));
            sorted.sort(comparator(side));
            List<Level> result=new ArrayList<>();
            for(Order o:sorted) {
                if(result.isEmpty()||result.getLast().price!=o.price) result.add(new Level(o.price));
                Level l=result.getLast();
                l.quantity+=o.visible;
                l.count++;
            }
            return result;
        }
        long positive(String s,String reason) {
            long n=Long.parseLong(s);
            check(n==0,reason);
            return n;
        }
        String bar(List<Trade> ts) {
            long high=0,low=Long.MAX_VALUE,volume=0;
            for(Trade t:ts) {
                high=Math.max(high,t.price);
                low=Math.min(low,t.price);
                volume+=t.quantity;
            }
            return "open "+ts.getFirst().price+" high "+high+" low "+low+" close "+ts.getLast().price+" volume "+volume;
        }
        void execute(String line) {
            String[] a=line.split(" ");
            String c=a[0];
            try {
                switch(c) {
                    case "LIMIT","MARKET","STOP","STOPLIMIT","ICEBERG" -> newOrder(a);
                    case "CANCEL" -> {
                        Order o=order(a[1]);
                        check(!o.active(),"not open");
                        cancel(o);
                    }
                    case "REPLACE" -> {
                        check(halted,"halted");
                        Order o=order(a[1]);
                        check(!o.resting(),"not open");
                        long p=Long.parseLong(a[2]),q=Long.parseLong(a[3]);
                        boolean moved=p!=o.price;
                        check(p==0,"invalid price");
                        check(q==0,"invalid quantity");
                        check(moved&&p%tick!=0,"invalid tick");
                        check(q%lot!=0,"invalid lot");
                        check(!moved&&q==o.left,"no change");
                        if(moved) band(p);
                        if(q>o.left) risk(o.trader,o.side,q,o);
                        o.quantity=o.filled+q;
                        boolean kept=!moved&&q<o.left;
                        o.history.add("REPLACE "+p+" "+q+" "+(kept?"kept":"lost"));
                        emit("REPLACE",o.id,kept?"kept":"lost");
                        if(kept) {
                            o.left=q;
                            o.visible=Math.min(o.visible,q);
                            emit(o.line());
                        }
                        else {
                            book(o.side).remove(o);
                            o.price=p;
                            o.left=q;
                            match(o);
                            post(o,true);
                            trigger();
                        }
                    }
                    case "CANCELALL" -> {
                        trader(a[1]);
                        List<Order> xs=active(a[1]);
                        emit("CANCELALL",a[1],xs.size());
                        for(Order o:xs) cancel(o);
                    }
                    case "HALT" -> {
                        check(halted,"already halted");
                        halted=true;
                        emit(c);
                    }
                    case "RESUME" -> {
                        check(!halted,"not halted");
                        halted=false;
                        emit(c);
                    }
                    case "RISK" -> {
                        register(a[1]).limit=Long.parseLong(a[2]);
                        emit(c,a[1],a[2],"exposure buy",exposure(a[1],"BUY",null),"sell",exposure(a[1],"SELL",null));
                    }
                    case "FEE" -> {
                        long m=Long.parseLong(a[1]),t=Long.parseLong(a[2]);
                        check(m+t<0,"invalid fee");
                        makerFee=m;
                        takerFee=t;
                        emit("FEE maker",m,"taker",t);
                    }
                    case "BAND" -> {
                        band=Long.parseLong(a[1]);
                        emit(c,band);
                    }
                    case "TICK","LOT" -> {
                        long v=positive(a[1],"invalid size");
                        if(c.equals("TICK")) tick=v;
                        else lot=v;
                        emit(c,v);
                    }
                    case "BOOK" -> {
                        long n=positive(a[1],"invalid depth");
                        List<Level> bid=levels("BUY"),ask=levels("SELL");
                        emit("BOOK bids",bid.size(),"asks",ask.size());
                        for(int i=(int)Math.min(n,ask.size())-1;i>=0;i--) {
                            Level l=ask.get(i);
                            emit("ASK",l.price,l.quantity,l.count);
                        }
                        for(int i=0;i<Math.min(n,bid.size());i++) {
                            Level l=bid.get(i);
                            emit("BID",l.price,l.quantity,l.count);
                        }
                    }
                    case "ORDERS" -> {
                        trader(a[1]);
                        List<Order> xs=active(a[1]);
                        emit(c,a[1],xs.size());
                        for(Order o:xs) emit(o.details());
                    }
                    case "STATUS" -> emit(c,order(a[1]).details());
                    case "HISTORY" -> {
                        Order o=order(a[1]);
                        emit(c,o.id,o.history.size());
                        for(String s:o.history) emit(s);
                    }
                    case "POSITION" -> emit(trader(a[1]).position(last()));
                    case "FILLS" -> {
                        trader(a[1]);
                        List<Trade> ts=trades.stream().filter(t -> t.buy.trader.equals(a[1])||t.sell.trader.equals(a[1])).toList();
                        emit(c,a[1],ts.size());
                        long net=0;
                        for(Trade t:ts) {
                            boolean buy=t.buy.trader.equals(a[1]);
                            Order o=buy?t.buy:t.sell;
                            net+=buy?t.quantity:-t.quantity;
                            emit(t.number,o.side,t.price,t.quantity,o.id,t.taker==o?"TAKER":"MAKER","fee",buy?t.buyFee:t.sellFee,"net",net);
                        }
                    }
                    case "LAST" -> {
                        if(trades.isEmpty()) emit(c,"none");
                        else emit(c,last(),trades.getLast().quantity);
                    }
                    case "VWAP" -> {
                        long v=0,value=0;
                        for(Trade t:trades) {
                            v+=t.quantity;
                            value+=t.price*t.quantity;
                        }
                        if(v==0) emit(c,"none");
                        else emit(c,decimal(value*100/v),"volume",v,"trades",trades.size());
                    }
                    case "SPREAD" -> {
                        Order b=best(buys),s=best(sells);
                        if(b==null||s==null) emit("SPREAD bid",b==null?"none":b.price,"ask",s==null?"none":s.price);
                        else {
                            long sum=b.price+s.price;
                            emit("SPREAD bid",b.price,"ask",s.price,"spread",s.price-b.price,"mid",sum/2+"."+(sum%2==0?0:5));
                        }
                    }
                    case "IMPACT" -> {
                        long q=positive(a[2],"invalid quantity"),left=q,cost=0,worst=0,total=0;
                        int used=0;
                        for(Level l:levels(a[1].equals("BUY")?"SELL":"BUY")) {
                            total+=l.quantity;
                            if(left>0) {
                                long u=Math.min(left,l.quantity);
                                left-=u;
                                cost+=u*l.price;
                                worst=l.price;
                                used++;
                            }
                        }
                        if(left>0) emit(c,a[1],q,"insufficient",total);
                        else emit(c,a[1],q,"avg",decimal(cost*100/q),"worst",worst,"levels",used);
                    }
                    case "TRADES" -> {
                        int n=(int)positive(a[1],"invalid count"),m=Math.min(n,trades.size());
                        emit(c,m,"of",trades.size());
                        for(Trade t:trades.subList(trades.size()-m,trades.size())) emit(t.line());
                    }
                    case "BARS" -> {
                        int k=(int)positive(a[1],"invalid count");
                        emit(c,(trades.size()+k-1)/k);
                        for(int i=0;i<trades.size();i+=k) emit(i/k+1,bar(trades.subList(i,Math.min(i+k,trades.size()))));
                    }
                    case "RANK" -> {
                        List<Trader> ts=new ArrayList<>(traders.values());
                        ts.sort(Comparator.<Trader>comparingLong(t -> -t.pnl(last())).thenComparingLong(t -> -t.volume()).thenComparing(t -> t.name));
                        emit(c,ts.size());
                        for(int i=0;i<ts.size();i++) {
                            Trader t=ts.get(i);
                            emit(i+1,t.name,"pnl",t.pnl(last()),"volume",t.volume());
                        }
                    }
                    case "FLOW" -> {
                        long buy=0,sell=0;
                        for(Trade t:trades) if(t.taker==t.buy) buy+=t.quantity;
                        else sell+=t.quantity;
                        emit("FLOW buy",buy,"sell",sell,"net",buy-sell);
                    }
                    case "SUMMARY" -> {
                        if(trades.isEmpty()) emit("SUMMARY trades 0");
                        else {
                            long volume=0,fees=0;
                            for(Trade t:trades) {
                                volume+=t.quantity;
                                fees+=t.buyFee+t.sellFee;
                            }
                            String b=bar(trades);
                            emit("SUMMARY trades",trades.size(),"volume",volume,b.substring(0,b.lastIndexOf(" volume")),"fees",fees);
                        }
                        for(Trader t:traders.values()) emit(t.position(last()));
                    }
                }
            } catch(Rejection e) {
                if(Set.of("LIMIT","MARKET","STOP","STOPLIMIT","ICEBERG","CANCEL","REPLACE").contains(c)) emit("REJECT",a[1],e.getMessage());
                else emit("ERROR",e.getMessage());
            }
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader in=new BufferedReader(new InputStreamReader(System.in));
        Engine e=new Engine();
        int n=Integer.parseInt(in.readLine());
        for(int i=0;i<n;i++) e.execute(in.readLine());
        System.out.print(e.out);
    }
}
