import java.io.*;
import java.util.*;

public class Main {
    static final String[] CATEGORIES={"received","returned","adjusted-in","adjusted-out","shipped","written-down","expired","recalled"};
    static class Fault extends RuntimeException { Fault(String reason) { super(reason); } }
    static void error(boolean condition, String reason) { if (condition) throw new Fault(reason); }
    static long parseMoney(String s) {
        return Long.parseLong(s.replace(".",""));
    }
    static String money(long n) {
        long a=Math.abs(n);
        return String.format(Locale.ROOT,"%s%d.%02d",n<0 ? "-" : "",a/100,a%100);
    }
    static String signed(long n) { return (n>0 ? "+" : "")+n; }
    static String signedMoney(long n) { return (n>0 ? "+" : "")+money(n); }
    static String margin(long profit, long revenue) {
        if (revenue==0) return "n/a";
        long q=Math.abs(profit)*1000/revenue;
        return (profit<0 && q>0 ? "-" : "")+q/10+"."+q%10+"%";
    }
    record Card(long day, String kind, String warehouse, long quantity, long value) {}
    static class Item {
        String code,name;
        long level;
        Long lastCost;
        List<Card> cards=new ArrayList<>();
        Item(String code, long level, String name) {
            this.code=code;
            this.level=level;
            this.name=name;
        }
    }
    static class Warehouse {
        String code;
        Map<String,Map<Integer,Stock>> stock=new HashMap<>();
        Warehouse(String code) { this.code=code; }
    }
    static class Lot {
        int number;
        Item item;
        long day,initialQuantity,initialCost,removed;
        String warehouse,kind;
        Lot(int number, Item item, long day, long quantity, long cost, String warehouse, String kind) {
            this.number=number;
            this.item=item;
            this.day=day;
            initialQuantity=quantity;
            initialCost=cost;
            this.warehouse=warehouse;
            this.kind=kind;
        }
    }
    static class Stock {
        Lot lot;
        long quantity,cost;
        Stock(Lot lot, long quantity, long cost) {
            this.lot=lot;
            this.quantity=quantity;
            this.cost=cost;
        }
        long value() { return quantity*cost; }
    }
    record Part(Lot lot, long quantity, long cost) {}
    record Issue(List<Part> parts, long cost) {}
    static class Order {
        int number;
        Warehouse warehouse;
        Item item;
        long day,price,ordered,shipped,backorder,cancelled,returned,revenue,cogs;
        List<Part> parts=new ArrayList<>();
        Order(int number, Warehouse warehouse, Item item, long day, long quantity, long price) {
            this.number=number;
            this.warehouse=warehouse;
            this.item=item;
            this.day=day;
            ordered=quantity;
            backorder=quantity;
            this.price=price;
        }
    }
    static class Inventory {
        long day=1;
        TreeMap<String,Warehouse> warehouses=new TreeMap<>();
        TreeMap<String,Item> items=new TreeMap<>();
        List<Lot> lots=new ArrayList<>();
        List<Order> orders=new ArrayList<>();
        long[][] totals=new long[8][2];
        List<String> output;
        Warehouse warehouse(String code) {
            Warehouse w=warehouses.get(code);
            error(w==null,"unknown warehouse "+code);
            return w;
        }
        Item item(String code) {
            Item s=items.get(code);
            error(s==null,"unknown item "+code);
            return s;
        }
        Order order(String raw) {
            long n=Long.parseLong(raw);
            error(n<1 || n>orders.size(),"unknown order "+raw);
            return orders.get((int)n-1);
        }
        Lot lot(String raw) {
            long n=Long.parseLong(raw);
            error(n<1 || n>lots.size(),"unknown lot "+raw);
            return lots.get((int)n-1);
        }
        List<Stock> stock(Warehouse w, Item s) {
            Map<Integer,Stock> map=w.stock.get(s.code);
            return map==null ? new ArrayList<>() : new ArrayList<>(map.values());
        }
        List<Stock> fifo(Warehouse w, Item s) {
            List<Stock> result=stock(w,s);
            result.sort(Comparator.comparingLong((Stock a) -> a.lot.day).thenComparingInt(a -> a.lot.number));
            return result;
        }
        long onhand(Warehouse w, Item s) { return stock(w,s).stream().mapToLong(a -> a.quantity).sum(); }
        long value(Warehouse w, Item s) { return stock(w,s).stream().mapToLong(Stock::value).sum(); }
        long onhand(Item s) { return warehouses.values().stream().mapToLong(w -> onhand(w,s)).sum(); }
        long backorder(Item s) { return orders.stream().filter(o -> o.item==s).mapToLong(o -> o.backorder).sum(); }
        List<Stock> target(Item s, Warehouse selected) {
            return warehouses.values().stream().filter(w -> selected==null || w==selected)
                .flatMap(w -> stock(w,s).stream()).toList();
        }
        void card(Item s, String kind, Warehouse w, long q, long v) { s.cards.add(new Card(day,kind,w.code,q,v)); }
        void total(int category, long q, long value) {
            totals[category][0]+=q;
            totals[category][1]+=value;
        }
        void add(Warehouse w, Item s, Lot lot, long q, long cost) {
            Map<Integer,Stock> map=w.stock.computeIfAbsent(s.code,k -> new HashMap<>());
            Stock old=map.get(lot.number);
            if (old==null) map.put(lot.number,new Stock(lot,q,cost));
            else old.quantity+=q;
        }
        Lot create(Warehouse w, Item s, long q, long cost, long date, String kind) {
            Lot lot=new Lot(lots.size()+1,s,date,q,cost,w.code,kind);
            lots.add(lot);
            add(w,s,lot,q,cost);
            return lot;
        }
        Issue issue(Warehouse w, Item s, long quantity, boolean removed) {
            List<Part> parts=new ArrayList<>();
            long cost=0;
            for (Stock a:fifo(w,s)) {
                if (quantity==0) break;
                long q=Math.min(quantity,a.quantity);
                parts.add(new Part(a.lot,q,a.cost));
                cost+=q*a.cost;
                a.quantity-=q;
                quantity-=q;
                if (removed) a.lot.removed+=q;
                if (a.quantity==0) w.stock.get(s.code).remove(a.lot.number);
            }
            return new Issue(parts,cost);
        }
        Issue fill(Order o, long q, String kind) {
            Issue issued=issue(o.warehouse,o.item,q,false);
            o.shipped+=q;
            o.backorder-=q;
            o.revenue+=q*o.price;
            o.cogs+=issued.cost();
            o.parts.addAll(issued.parts());
            if (q>0) {
                total(4,q,issued.cost());
                card(o.item,kind,o.warehouse,-q,-issued.cost());
            }
            return issued;
        }
        void allocate(Warehouse w, Item s) {
            long available=onhand(w,s);
            for (Order o:orders) {
                if (available==0) break;
                if (o.warehouse==w && o.item==s && o.backorder>0) {
                    long q=Math.min(available,o.backorder);
                    Issue issued=fill(o,q,"fill");
                    available-=q;
                    output.add("  FILL order "+o.number+" qty "+q+" revenue "+money(q*o.price)+" cogs "+money(issued.cost())+
                        " profit "+money(q*o.price-issued.cost())+" backorder "+o.backorder);
                }
            }
        }
        void insufficient(Warehouse w, Item s, long q) {
            long h=onhand(w,s);
            error(h<q,"insufficient stock "+w.code+" "+s.code+" "+h);
        }
        long[] sales(Item s) {
            List<Order> selected=orders.stream().filter(o -> s==null || o.item==s).toList();
            return new long[]{selected.stream().mapToLong(o -> o.shipped-o.returned).sum(),
                selected.stream().mapToLong(o -> o.revenue).sum(),
                selected.stream().mapToLong(o -> o.cogs).sum(),selected.size()};
        }
        String salesLine(String label, long[] a) {
            return "  "+label+" sold "+a[0]+" revenue "+money(a[1])+" cogs "+money(a[2])+" profit "+money(a[1]-a[2])+" margin "+margin(a[1]-a[2],a[1]);
        }
        String buckets(String label, long[] a, boolean monetary) {
            String result="  "+label;
            String[] labels={"0-30","31-60","61-90","91+"};
            for (int i=0;i<4;i++) result+=" "+labels[i]+" "+(monetary ? money(a[i]) : Long.toString(a[i]));
            return result;
        }
        void execute(String[] t) {
            switch (t[0]) {
                case "DAY": {
                    long d=Long.parseLong(t[1]);
                    error(d<=day,"invalid day "+t[1]);
                    day=d;
                    output.add("DAY "+day);
                    break;
                }
                case "WAREHOUSE":
                    error(warehouses.containsKey(t[1]),"duplicate warehouse "+t[1]);
                    warehouses.put(t[1],new Warehouse(t[1]));
                    output.add("WAREHOUSE "+t[1]);
                    break;
                case "ITEM": {
                    boolean exists=items.containsKey(t[1]);
                    Item s=exists ? items.get(t[1]) : new Item(t[1],Long.parseLong(t[2]),t[3]);
                    s.level=Long.parseLong(t[2]);
                    s.name=t[3];
                    items.put(s.code,s);
                    output.add("ITEM "+s.code+(exists ? " updated " : " added ")+s.name+" level "+s.level);
                    break;
                }
                case "RECEIVE", "SHIP", "ADJUST", "COUNT": {
                    Warehouse w=warehouse(t[1]);
                    Item s=item(t[2]);
                    long q=t[0].equals("ADJUST") ? Long.parseLong(t[3].substring(1)) : Long.parseLong(t[3]);
                    if (!t[0].equals("COUNT")) error(q==0,"invalid quantity");
                    long h=onhand(w,s);
                    if (t[0].equals("RECEIVE")) {
                        long date=Long.parseLong(t[5]),cost=parseMoney(t[4]);
                        error(date>day,"future day "+t[5]);
                        Lot lot=create(w,s,q,cost,date,"receive");
                        s.lastCost=cost;
                        total(0,q,q*cost);
                        card(s,"receive",w,q,q*cost);
                        output.add("RECEIVE "+w.code+" "+s.code+" lot "+lot.number+" qty "+q+" cost "+money(cost)+" day "+date+" value "+money(q*cost));
                        allocate(w,s);
                    } else if (t[0].equals("SHIP")) {
                        Order o=new Order(orders.size()+1,w,s,day,q,parseMoney(t[4]));
                        orders.add(o);
                        long f=Math.min(q,h);
                        Issue issued=fill(o,f,"ship");
                        output.add("SHIP order "+o.number+" "+w.code+" "+s.code+" shipped "+f+" revenue "+money(o.revenue)+" cogs "+money(issued.cost())+
                            " profit "+money(o.revenue-issued.cost())+" backorder "+o.backorder);
                    } else if (t[0].equals("ADJUST")) {
                        if (t[3].charAt(0)=='+') {
                            long cost=parseMoney(t[4]);
                            Lot lot=create(w,s,q,cost,day,"adjust");
                            total(2,q,q*cost);
                            card(s,"adjust",w,q,q*cost);
                            output.add("ADJUST "+w.code+" "+s.code+" +"+q+" lot "+lot.number+" value "+money(q*cost));
                            allocate(w,s);
                        } else {
                            insufficient(w,s,q);
                            Issue issued=issue(w,s,q,true);
                            total(3,q,issued.cost());
                            card(s,"adjust",w,-q,-issued.cost());
                            output.add("ADJUST "+w.code+" "+s.code+" -"+q+" value "+money(issued.cost()));
                        }
                    } else {
                        if (q==h) output.add("COUNT "+w.code+" "+s.code+" qty "+q+" ok");
                        else if (q<h) {
                            Issue issued=issue(w,s,h-q,true);
                            total(3,h-q,issued.cost());
                            card(s,"count",w,q-h,-issued.cost());
                            output.add("COUNT "+w.code+" "+s.code+" qty "+h+" -> "+q+" shortage "+(h-q)+" value "+money(issued.cost()));
                        } else {
                            long cost=s.lastCost==null ? 0 : s.lastCost;
                            Lot lot=create(w,s,q-h,cost,day,"count");
                            total(2,q-h,(q-h)*cost);
                            card(s,"count",w,q-h,(q-h)*cost);
                            output.add("COUNT "+w.code+" "+s.code+" qty "+h+" -> "+q+" surplus "+(q-h)+" lot "+lot.number+" value "+money((q-h)*cost));
                            allocate(w,s);
                        }
                    }
                    break;
                }
                case "CANCEL": {
                    Order o=order(t[1]);
                    error(o.backorder==0,"no backorder "+t[1]);
                    o.cancelled+=o.backorder;
                    o.backorder=0;
                    output.add("CANCEL order "+o.number+" qty "+o.cancelled);
                    break;
                }
                case "TRANSFER": {
                    Warehouse a=warehouse(t[1]),b=warehouse(t[2]);
                    error(a==b,"same warehouse "+t[1]);
                    Item s=item(t[3]);
                    long q=Long.parseLong(t[4]);
                    error(q==0,"invalid quantity");
                    insufficient(a,s,q);
                    Issue issued=issue(a,s,q,false);
                    for (Part p:issued.parts()) add(b,s,p.lot(),p.quantity(),p.cost());
                    card(s,"transfer-out",a,-q,-issued.cost());
                    card(s,"transfer-in",b,q,issued.cost());
                    output.add("TRANSFER "+a.code+" -> "+b.code+" "+s.code+" qty "+q+" value "+money(issued.cost())+" lots "+issued.parts().size());
                    allocate(b,s);
                    break;
                }
                case "RETURN": {
                    Order o=order(t[1]);
                    long q=Long.parseLong(t[2]),cost=parseMoney(t[3]);
                    error(q==0,"invalid quantity");
                    error(q>o.shipped-o.returned,"return exceeds shipped "+t[1]+" "+(o.shipped-o.returned));
                    Lot lot=create(o.warehouse,o.item,q,cost,day,"return");
                    o.returned+=q;
                    o.revenue-=q*o.price;
                    o.cogs-=q*cost;
                    total(1,q,q*cost);
                    card(o.item,"return",o.warehouse,q,q*cost);
                    output.add("RETURN order "+o.number+" "+o.warehouse.code+" "+o.item.code+" qty "+q+" lot "+lot.number+" refund "+money(q*o.price)+" value "+money(q*cost));
                    allocate(o.warehouse,o.item);
                    break;
                }
                case "MARKET": {
                    Item s=item(t[1]);
                    long price=parseMoney(t[2]),quantity=0,loss=0,count=0;
                    for (Warehouse w:warehouses.values()) {
                        long subtotal=0;
                        for (Stock a:stock(w,s)) {
                            if (a.cost>price) {
                                long amount=a.quantity*(a.cost-price);
                                subtotal+=amount;
                                quantity+=a.quantity;
                                count++;
                                a.cost=price;
                            }
                        }
                        if (subtotal>0) card(s,"writedown",w,0,-subtotal);
                        loss+=subtotal;
                    }
                    total(5,quantity,loss);
                    output.add("MARKET "+s.code+" price "+money(price)+" lots "+count+" qty "+quantity+" loss "+money(loss));
                    break;
                }
                case "RECALL": {
                    Lot lot=lot(t[1]);
                    long quantity=0,value=0;
                    List<String> details=new ArrayList<>();
                    for (Warehouse w:warehouses.values()) {
                        for (Stock a:stock(w,lot.item)) if (a.lot==lot) quantity+=a.quantity;
                    }
                    error(quantity==0,"nothing to recall "+t[1]);
                    for (Warehouse w:warehouses.values()) {
                        for (Stock a:stock(w,lot.item)) {
                            if (a.lot==lot) {
                                value+=a.value();
                                card(lot.item,"recall",w,-a.quantity,-a.value());
                                details.add("  "+w.code+" qty "+a.quantity+" value "+money(a.value()));
                                w.stock.get(lot.item.code).remove(lot.number);
                            }
                        }
                    }
                    lot.removed+=quantity;
                    total(7,quantity,value);
                    output.add("RECALL lot "+lot.number+" "+lot.item.code+" qty "+quantity+" value "+money(value));
                    output.addAll(details);
                    break;
                }
                case "EXPIRE": {
                    long age=Long.parseLong(t[1]),quantity=0,value=0;
                    output.add("EXPIRE "+age);
                    for (Item s:items.values()) {
                        for (Warehouse w:warehouses.values()) {
                            long q=0,v=0,count=0;
                            for (Stock a:stock(w,s)) {
                                if (day-a.lot.day>age) {
                                    q+=a.quantity;
                                    v+=a.value();
                                    count++;
                                    a.lot.removed+=a.quantity;
                                    w.stock.get(s.code).remove(a.lot.number);
                                }
                            }
                            if (count>0) {
                                total(6,q,v);
                                card(s,"expire",w,-q,-v);
                                output.add("  "+s.code+" "+w.code+" lots "+count+" qty "+q+" value "+money(v));
                                quantity+=q;
                                value+=v;
                            }
                        }
                    }
                    output.add("  total qty "+quantity+" value "+money(value));
                    break;
                }
                case "VALUE", "AGING": {
                    Warehouse selected=t.length==2 ? warehouse(t[1]) : null;
                    if (t[0].equals("VALUE")) {
                        output.add("VALUE"+(selected==null ? "" : " "+selected.code));
                        long quantity=0,value=0;
                        for (Item s:items.values()) {
                            List<Stock> target=target(s,selected);
                            long q=target.stream().mapToLong(a -> a.quantity).sum(),v=target.stream().mapToLong(Stock::value).sum();
                            if (q==0) continue;
                            output.add("  "+s.code+" qty "+q+" value "+money(v)+" avg "+money(v/q));
                            if (selected==null) {
                                for (Warehouse w:warehouses.values()) if (onhand(w,s)>0) output.add("    "+w.code+" qty "+onhand(w,s)+" value "+money(value(w,s)));
                            }
                            quantity+=q;
                            value+=v;
                        }
                        output.add("  total qty "+quantity+" value "+money(value));
                    } else {
                        output.add("AGING"+(selected==null ? "" : " "+selected.code)+" day "+day);
                        long[] quantities=new long[4],values=new long[4];
                        for (Item s:items.values()) {
                            long[] q=new long[4];
                            for (Stock a:target(s,selected)) {
                                long age=day-a.lot.day;
                                int b=age<=30 ? 0 : age<=60 ? 1 : age<=90 ? 2 : 3;
                                q[b]+=a.quantity;
                                quantities[b]+=a.quantity;
                                values[b]+=a.value();
                            }
                            if (Arrays.stream(q).sum()>0) output.add(buckets(s.code,q,false));
                        }
                        output.add(buckets("total",quantities,false));
                        output.add(buckets("value",values,true));
                    }
                    break;
                }
                case "LOTS": {
                    Warehouse w=warehouse(t[1]);
                    Item s=item(t[2]);
                    output.add("LOTS "+w.code+" "+s.code);
                    for (Stock a:fifo(w,s)) output.add("  lot "+a.lot.number+" day "+a.lot.day+" qty "+a.quantity+" cost "+money(a.cost)+" value "+money(a.value())+" age "+(day-a.lot.day));
                    for (Order o:orders) if (o.warehouse==w && o.item==s && o.backorder>0) output.add("  backorder order "+o.number+" qty "+o.backorder);
                    break;
                }
                case "REORDER", "ITEMS":
                    output.add(t[0]);
                    for (Item s:items.values()) {
                        long h=onhand(s),b=backorder(s);
                        if (t[0].equals("ITEMS")) output.add("  "+s.code+" "+s.name+" level "+s.level+" onhand "+h+" backorder "+b+" cost "+(s.lastCost==null ? "none" : money(s.lastCost)));
                        else if (h-b<=s.level) output.add("  "+s.code+" "+s.name+" onhand "+h+" backorder "+b+" level "+s.level);
                    }
                    break;
                case "MARGIN", "TOP": {
                    Map<Item,long[]> summaries=new HashMap<>();
                    for (Item s:items.values()) {
                        long[] a=sales(s);
                        if (a[3]>0) summaries.put(s,a);
                    }
                    if (t[0].equals("MARGIN")) {
                        output.add("MARGIN");
                        for (Item s:items.values()) if (summaries.containsKey(s)) output.add(salesLine(s.code,summaries.get(s)));
                        output.add(salesLine("total",sales(null)));
                    } else {
                        int k=(int)Long.parseLong(t[1]);
                        output.add("TOP "+k);
                        List<Item> ranked=new ArrayList<>(summaries.keySet());
                        ranked.sort(Comparator.comparingLong((Item s) -> -(summaries.get(s)[1]-summaries.get(s)[2])).thenComparingLong(s -> -summaries.get(s)[1]).thenComparing(s -> s.code));
                        for (int i=0;i<Math.min(k,ranked.size());i++) {
                            Item s=ranked.get(i);
                            long[] a=summaries.get(s);
                            output.add("  "+(i+1)+" "+s.code+" profit "+money(a[1]-a[2])+" revenue "+money(a[1])+" margin "+margin(a[1]-a[2],a[1]));
                        }
                    }
                    break;
                }
                case "BACKORDERS":
                    output.add("BACKORDERS");
                    for (Order o:orders) if (o.backorder>0) output.add("  order "+o.number+" "+o.warehouse.code+" "+o.item.code+" qty "+o.backorder+" day "+o.day+" price "+money(o.price));
                    break;
                case "ORDER": {
                    Order o=order(t[1]);
                    output.add("ORDER "+o.number+" "+o.warehouse.code+" "+o.item.code+" day "+o.day+" price "+money(o.price));
                    output.add("  ordered "+o.ordered+" shipped "+o.shipped+" backorder "+o.backorder+" cancelled "+o.cancelled+" returned "+o.returned);
                    for (Part p:o.parts) output.add("  lot "+p.lot().number+" qty "+p.quantity()+" cost "+money(p.cost()));
                    output.add("  revenue "+money(o.revenue)+" cogs "+money(o.cogs)+" profit "+money(o.revenue-o.cogs));
                    break;
                }
                case "TRACE": {
                    Lot lot=lot(t[1]);
                    output.add("TRACE lot "+lot.number+" "+lot.item.code+" "+lot.kind+" "+lot.warehouse+" day "+lot.day+" qty "+lot.initialQuantity+" cost "+money(lot.initialCost));
                    for (Warehouse w:warehouses.values()) {
                        for (Stock a:stock(w,lot.item)) if (a.lot==lot) output.add("  held "+w.code+" qty "+a.quantity+" cost "+money(a.cost));
                    }
                    for (Order o:orders) {
                        long q=o.parts.stream().filter(p -> p.lot()==lot).mapToLong(Part::quantity).sum();
                        if (q>0) output.add("  order "+o.number+" qty "+q);
                    }
                    if (lot.removed>0) output.add("  removed qty "+lot.removed);
                    break;
                }
                case "CARD": {
                    Item s=item(t[1]);
                    output.add("CARD "+s.code+" "+s.name);
                    long quantity=0,value=0;
                    for (Card c:s.cards) {
                        quantity+=c.quantity();
                        value+=c.value();
                        output.add("  day "+c.day()+" "+c.kind()+" "+c.warehouse()+" "+signed(c.quantity())+" "+signedMoney(c.value())+" balance "+quantity+" "+money(value));
                    }
                    break;
                }
                case "STATUS":
                    output.add("STATUS");
                    for (Warehouse w:warehouses.values()) {
                        List<Stock> held=w.stock.values().stream().flatMap(map -> map.values().stream()).toList();
                        long q=held.stream().mapToLong(a -> a.quantity).sum();
                        long v=held.stream().mapToLong(Stock::value).sum();
                        long skus=w.stock.values().stream().filter(map -> !map.isEmpty()).count();
                        long backorder=orders.stream().filter(o -> o.warehouse==w).mapToLong(o -> o.backorder).sum();
                        output.add("  "+w.code+" skus "+skus+" qty "+q+" value "+money(v)+" backorder "+backorder);
                    }
                    break;
                case "SUMMARY": {
                    output.add("SUMMARY");
                    for (int i=0;i<8;i++) output.add("  "+CATEGORIES[i]+" qty "+totals[i][0]+" value "+money(totals[i][1]));
                    long q=items.values().stream().mapToLong(this::onhand).sum();
                    long v=items.values().stream().mapToLong(s -> warehouses.values().stream().mapToLong(w -> value(w,s)).sum()).sum();
                    output.add("  on-hand qty "+q+" value "+money(v));
                    output.add("  orders "+orders.size()+" open "+orders.stream().filter(o -> o.backorder>0).count()+" backorder "+orders.stream().mapToLong(o -> o.backorder).sum());
                    break;
                }
            }
            if (output.size()==1 && Set.of("LOTS","REORDER","ITEMS","TOP","BACKORDERS","CARD","STATUS").contains(t[0])) output.add("  (none)");
        }
        List<String> process(String line) {
            output=new ArrayList<>();
            try { execute(line.split(" ")); }
            catch (Fault f) { output.add("ERROR "+f.getMessage()); }
            return output;
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Inventory inventory=new Inventory();
        int n=Integer.parseInt(input.readLine());
        for (int i=0;i<n;i++) {
            for (String line:inventory.process(input.readLine())) output.println(line);
        }
        output.flush();
    }
}
