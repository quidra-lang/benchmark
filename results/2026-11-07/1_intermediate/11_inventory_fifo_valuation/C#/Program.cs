using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

class Program {
    static readonly string[] CATEGORIES={"received","returned","adjusted-in","adjusted-out","shipped","written-down","expired","recalled"};
    class Fault : Exception { public Fault(string reason) : base(reason) {} }
    static void error(bool condition, string reason) { if (condition) throw new Fault(reason); }
    static long parseMoney(string s) {
        return long.Parse(s.Replace(".",""));
    }
    static string money(long n) {
        long a=Math.Abs(n);
        return (n<0 ? "-" : "")+a/100+"."+(a%100).ToString("D2",CultureInfo.InvariantCulture);
    }
    static string signed(long n) { return (n>0 ? "+" : "")+n; }
    static string signedMoney(long n) { return (n>0 ? "+" : "")+money(n); }
    static string margin(long profit, long revenue) {
        if (revenue==0) return "n/a";
        long q=Math.Abs(profit)*1000/revenue;
        return (profit<0 && q>0 ? "-" : "")+q/10+"."+q%10+"%";
    }
    record Card(long day, string kind, string warehouse, long quantity, long value);
    class Item {
        public string code,name;
        public long level;
        public long? lastCost;
        public List<Card> cards=new();
        public Item(string code, long level, string name) {
            this.code=code;
            this.level=level;
            this.name=name;
        }
    }
    class Warehouse {
        public string code;
        public Dictionary<string,Dictionary<int,Stock>> stock=new();
        public Warehouse(string code) { this.code=code; }
    }
    class Lot {
        public int number;
        public Item item;
        public long day,initialQuantity,initialCost,removed;
        public string warehouse,kind;
        public Lot(int number, Item item, long day, long quantity, long cost, string warehouse, string kind) {
            this.number=number;
            this.item=item;
            this.day=day;
            initialQuantity=quantity;
            initialCost=cost;
            this.warehouse=warehouse;
            this.kind=kind;
        }
    }
    class Stock {
        public Lot lot;
        public long quantity,cost;
        public Stock(Lot lot, long quantity, long cost) {
            this.lot=lot;
            this.quantity=quantity;
            this.cost=cost;
        }
        public long value() { return quantity*cost; }
    }
    record Part(Lot lot, long quantity, long cost);
    record Issue(List<Part> parts, long cost);
    class Order {
        public int number;
        public Warehouse warehouse;
        public Item item;
        public long day,price,ordered,shipped,backorder,cancelled,returned,revenue,cogs;
        public List<Part> parts=new();
        public Order(int number, Warehouse warehouse, Item item, long day, long quantity, long price) {
            this.number=number;
            this.warehouse=warehouse;
            this.item=item;
            this.day=day;
            ordered=quantity;
            backorder=quantity;
            this.price=price;
        }
    }
    class Inventory {
        public long day=1;
        public SortedDictionary<string,Warehouse> warehouses=new(StringComparer.Ordinal);
        public SortedDictionary<string,Item> items=new(StringComparer.Ordinal);
        public List<Lot> lots=new();
        public List<Order> orders=new();
        public long[][] totals=Enumerable.Range(0,8).Select(_ => new long[2]).ToArray();
        public List<string> output;
        public Warehouse warehouse(string code) {
            Warehouse w=warehouses.GetValueOrDefault(code);
            error(w==null,"unknown warehouse "+code);
            return w;
        }
        public Item item(string code) {
            Item s=items.GetValueOrDefault(code);
            error(s==null,"unknown item "+code);
            return s;
        }
        public Order order(string raw) {
            long n=long.Parse(raw);
            error(n<1 || n>orders.Count,"unknown order "+raw);
            return orders[(int)n-1];
        }
        public Lot lookupLot(string raw) {
            long n=long.Parse(raw);
            error(n<1 || n>lots.Count,"unknown lot "+raw);
            return lots[(int)n-1];
        }
        public List<Stock> stock(Warehouse w, Item s) {
            Dictionary<int,Stock> map=w.stock.GetValueOrDefault(s.code);
            return map==null ? new() : new(map.Values);
        }
        public List<Stock> fifo(Warehouse w, Item s) {
            return stock(w,s).OrderBy(a => a.lot.day).ThenBy(a => a.lot.number).ToList();
        }
        public long onhand(Warehouse w, Item s) { return stock(w,s).Sum(a => a.quantity); }
        public long stockValue(Warehouse w, Item s) { return stock(w,s).Sum(a => a.value()); }
        public long onhand(Item s) { return warehouses.Values.Sum(w => onhand(w,s)); }
        public long backorder(Item s) { return orders.Where(o => o.item==s).Sum(o => o.backorder); }
        public List<Stock> selectedStock(Item s, Warehouse selected) {
            return warehouses.Values.Where(w => selected==null || w==selected).SelectMany(w => stock(w,s)).ToList();
        }
        public void card(Item s, string kind, Warehouse w, long q, long v) { s.cards.Add(new Card(day,kind,w.code,q,v)); }
        public void total(int category, long q, long value) {
            totals[category][0]+=q;
            totals[category][1]+=value;
        }
        public void add(Warehouse w, Item s, Lot lot, long q, long cost) {
            Dictionary<int,Stock> map=w.stock.GetValueOrDefault(s.code);
            if (map==null) {
                map=new();
                w.stock[s.code]=map;
            }
            Stock old=map.GetValueOrDefault(lot.number);
            if (old==null) map[lot.number]=new Stock(lot,q,cost);
            else old.quantity+=q;
        }
        public Lot create(Warehouse w, Item s, long q, long cost, long date, string kind) {
            Lot lot=new Lot(lots.Count+1,s,date,q,cost,w.code,kind);
            lots.Add(lot);
            add(w,s,lot,q,cost);
            return lot;
        }
        public Issue issue(Warehouse w, Item s, long quantity, bool removed) {
            List<Part> parts=new();
            long cost=0;
            foreach (Stock a in fifo(w,s)) {
                if (quantity==0) break;
                long q=Math.Min(quantity,a.quantity);
                parts.Add(new Part(a.lot,q,a.cost));
                cost+=q*a.cost;
                a.quantity-=q;
                quantity-=q;
                if (removed) a.lot.removed+=q;
                if (a.quantity==0) w.stock.GetValueOrDefault(s.code).Remove(a.lot.number);
            }
            return new Issue(parts,cost);
        }
        public Issue fill(Order o, long q, string kind) {
            Issue issued=issue(o.warehouse,o.item,q,false);
            o.shipped+=q;
            o.backorder-=q;
            o.revenue+=q*o.price;
            o.cogs+=issued.cost;
            o.parts.AddRange(issued.parts);
            if (q>0) {
                total(4,q,issued.cost);
                card(o.item,kind,o.warehouse,-q,-issued.cost);
            }
            return issued;
        }
        public void allocate(Warehouse w, Item s) {
            long available=onhand(w,s);
            foreach (Order o in orders) {
                if (available==0) break;
                if (o.warehouse==w && o.item==s && o.backorder>0) {
                    long q=Math.Min(available,o.backorder);
                    Issue issued=fill(o,q,"fill");
                    available-=q;
                    output.Add("  FILL order "+o.number+" qty "+q+" revenue "+money(q*o.price)+" cogs "+money(issued.cost)+
                        " profit "+money(q*o.price-issued.cost)+" backorder "+o.backorder);
                }
            }
        }
        public void insufficient(Warehouse w, Item s, long q) {
            long h=onhand(w,s);
            error(h<q,"insufficient stock "+w.code+" "+s.code+" "+h);
        }
        public long[] sales(Item s) {
            List<Order> selected=orders.Where(o => s==null || o.item==s).ToList();
            return new long[]{selected.Sum(o => o.shipped-o.returned),selected.Sum(o => o.revenue),
                selected.Sum(o => o.cogs),selected.Count};
        }
        public string salesLine(string label, long[] a) {
            return "  "+label+" sold "+a[0]+" revenue "+money(a[1])+" cogs "+money(a[2])+" profit "+money(a[1]-a[2])+" margin "+margin(a[1]-a[2],a[1]);
        }
        public string buckets(string label, long[] a, bool monetary) {
            string result="  "+label;
            string[] labels={"0-30","31-60","61-90","91+"};
            for (int i=0;i<4;i++) result+=" "+labels[i]+" "+(monetary ? money(a[i]) : Convert.ToString(a[i]));
            return result;
        }
        public void execute(string[] t) {
            switch (t[0]) {
                case "DAY": {
                    long d=long.Parse(t[1]);
                    error(d<=day,"invalid day "+t[1]);
                    day=d;
                    output.Add("DAY "+day);
                    break;
                }
                case "WAREHOUSE":
                    error(warehouses.ContainsKey(t[1]),"duplicate warehouse "+t[1]);
                    warehouses[t[1]]=new Warehouse(t[1]);
                    output.Add("WAREHOUSE "+t[1]);
                    break;
                case "ITEM": {
                    bool exists=items.ContainsKey(t[1]);
                    Item s=exists ? items.GetValueOrDefault(t[1]) : new Item(t[1],long.Parse(t[2]),t[3]);
                    s.level=long.Parse(t[2]);
                    s.name=t[3];
                    items[s.code]=s;
                    output.Add("ITEM "+s.code+(exists ? " updated " : " added ")+s.name+" level "+s.level);
                    break;
                }
                case "RECEIVE":
                case "SHIP":
                case "ADJUST":
                case "COUNT": {
                    Warehouse w=warehouse(t[1]);
                    Item s=item(t[2]);
                    long q=t[0].Equals("ADJUST") ? long.Parse(t[3].Substring(1)) : long.Parse(t[3]);
                    if (!t[0].Equals("COUNT")) error(q==0,"invalid quantity");
                    long h=onhand(w,s);
                    if (t[0].Equals("RECEIVE")) {
                        long date=long.Parse(t[5]),cost=parseMoney(t[4]);
                        error(date>day,"future day "+t[5]);
                        Lot lot=create(w,s,q,cost,date,"receive");
                        s.lastCost=cost;
                        total(0,q,q*cost);
                        card(s,"receive",w,q,q*cost);
                        output.Add("RECEIVE "+w.code+" "+s.code+" lot "+lot.number+" qty "+q+" cost "+money(cost)+" day "+date+" value "+money(q*cost));
                        allocate(w,s);
                    } else if (t[0].Equals("SHIP")) {
                        Order o=new Order(orders.Count+1,w,s,day,q,parseMoney(t[4]));
                        orders.Add(o);
                        long f=Math.Min(q,h);
                        Issue issued=fill(o,f,"ship");
                        output.Add("SHIP order "+o.number+" "+w.code+" "+s.code+" shipped "+f+" revenue "+money(o.revenue)+" cogs "+money(issued.cost)+
                            " profit "+money(o.revenue-issued.cost)+" backorder "+o.backorder);
                    } else if (t[0].Equals("ADJUST")) {
                        if (t[3][0]=='+') {
                            long cost=parseMoney(t[4]);
                            Lot lot=create(w,s,q,cost,day,"adjust");
                            total(2,q,q*cost);
                            card(s,"adjust",w,q,q*cost);
                            output.Add("ADJUST "+w.code+" "+s.code+" +"+q+" lot "+lot.number+" value "+money(q*cost));
                            allocate(w,s);
                        } else {
                            insufficient(w,s,q);
                            Issue issued=issue(w,s,q,true);
                            total(3,q,issued.cost);
                            card(s,"adjust",w,-q,-issued.cost);
                            output.Add("ADJUST "+w.code+" "+s.code+" -"+q+" value "+money(issued.cost));
                        }
                    } else {
                        if (q==h) output.Add("COUNT "+w.code+" "+s.code+" qty "+q+" ok");
                        else if (q<h) {
                            Issue issued=issue(w,s,h-q,true);
                            total(3,h-q,issued.cost);
                            card(s,"count",w,q-h,-issued.cost);
                            output.Add("COUNT "+w.code+" "+s.code+" qty "+h+" -> "+q+" shortage "+(h-q)+" value "+money(issued.cost));
                        } else {
                            long cost=s.lastCost ?? 0;
                            Lot lot=create(w,s,q-h,cost,day,"count");
                            total(2,q-h,(q-h)*cost);
                            card(s,"count",w,q-h,(q-h)*cost);
                            output.Add("COUNT "+w.code+" "+s.code+" qty "+h+" -> "+q+" surplus "+(q-h)+" lot "+lot.number+" value "+money((q-h)*cost));
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
                    output.Add("CANCEL order "+o.number+" qty "+o.cancelled);
                    break;
                }
                case "TRANSFER": {
                    Warehouse a=warehouse(t[1]),b=warehouse(t[2]);
                    error(a==b,"same warehouse "+t[1]);
                    Item s=item(t[3]);
                    long q=long.Parse(t[4]);
                    error(q==0,"invalid quantity");
                    insufficient(a,s,q);
                    Issue issued=issue(a,s,q,false);
                    foreach (Part p in issued.parts) add(b,s,p.lot,p.quantity,p.cost);
                    card(s,"transfer-out",a,-q,-issued.cost);
                    card(s,"transfer-in",b,q,issued.cost);
                    output.Add("TRANSFER "+a.code+" -> "+b.code+" "+s.code+" qty "+q+" value "+money(issued.cost)+" lots "+issued.parts.Count);
                    allocate(b,s);
                    break;
                }
                case "RETURN": {
                    Order o=order(t[1]);
                    long q=long.Parse(t[2]),cost=parseMoney(t[3]);
                    error(q==0,"invalid quantity");
                    error(q>o.shipped-o.returned,"return exceeds shipped "+t[1]+" "+(o.shipped-o.returned));
                    Lot lot=create(o.warehouse,o.item,q,cost,day,"return");
                    o.returned+=q;
                    o.revenue-=q*o.price;
                    o.cogs-=q*cost;
                    total(1,q,q*cost);
                    card(o.item,"return",o.warehouse,q,q*cost);
                    output.Add("RETURN order "+o.number+" "+o.warehouse.code+" "+o.item.code+" qty "+q+" lot "+lot.number+" refund "+money(q*o.price)+" value "+money(q*cost));
                    allocate(o.warehouse,o.item);
                    break;
                }
                case "MARKET": {
                    Item s=item(t[1]);
                    long price=parseMoney(t[2]),quantity=0,loss=0,count=0;
                    foreach (Warehouse w in warehouses.Values) {
                        long subtotal=0;
                        foreach (Stock a in stock(w,s)) {
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
                    output.Add("MARKET "+s.code+" price "+money(price)+" lots "+count+" qty "+quantity+" loss "+money(loss));
                    break;
                }
                case "RECALL": {
                    Lot lot=lookupLot(t[1]);
                    long quantity=0,value=0;
                    List<string> details=new();
                    foreach (Warehouse w in warehouses.Values) {
                        foreach (Stock a in stock(w,lot.item)) if (a.lot==lot) quantity+=a.quantity;
                    }
                    error(quantity==0,"nothing to recall "+t[1]);
                    foreach (Warehouse w in warehouses.Values) {
                        foreach (Stock a in stock(w,lot.item)) {
                            if (a.lot==lot) {
                                value+=a.value();
                                card(lot.item,"recall",w,-a.quantity,-a.value());
                                details.Add("  "+w.code+" qty "+a.quantity+" value "+money(a.value()));
                                w.stock.GetValueOrDefault(lot.item.code).Remove(lot.number);
                            }
                        }
                    }
                    lot.removed+=quantity;
                    total(7,quantity,value);
                    output.Add("RECALL lot "+lot.number+" "+lot.item.code+" qty "+quantity+" value "+money(value));
                    output.AddRange(details);
                    break;
                }
                case "EXPIRE": {
                    long age=long.Parse(t[1]),quantity=0,value=0;
                    output.Add("EXPIRE "+age);
                    foreach (Item s in items.Values) {
                        foreach (Warehouse w in warehouses.Values) {
                            long q=0,v=0,count=0;
                            foreach (Stock a in stock(w,s)) {
                                if (day-a.lot.day>age) {
                                    q+=a.quantity;
                                    v+=a.value();
                                    count++;
                                    a.lot.removed+=a.quantity;
                                    w.stock.GetValueOrDefault(s.code).Remove(a.lot.number);
                                }
                            }
                            if (count>0) {
                                total(6,q,v);
                                card(s,"expire",w,-q,-v);
                                output.Add("  "+s.code+" "+w.code+" lots "+count+" qty "+q+" value "+money(v));
                                quantity+=q;
                                value+=v;
                            }
                        }
                    }
                    output.Add("  total qty "+quantity+" value "+money(value));
                    break;
                }
                case "VALUE":
                case "AGING": {
                    Warehouse selected=t.Length==2 ? warehouse(t[1]) : null;
                    if (t[0].Equals("VALUE")) {
                        output.Add("VALUE"+(selected==null ? "" : " "+selected.code));
                        long quantity=0,value=0;
                        foreach (Item s in items.Values) {
                            List<Stock> target=selectedStock(s,selected);
                            long q=target.Sum(a => a.quantity),v=target.Sum(a => a.value());
                            if (q==0) continue;
                            output.Add("  "+s.code+" qty "+q+" value "+money(v)+" avg "+money(v/q));
                            if (selected==null) {
                                foreach (Warehouse w in warehouses.Values) if (onhand(w,s)>0) output.Add("    "+w.code+" qty "+onhand(w,s)+" value "+money(stockValue(w,s)));
                            }
                            quantity+=q;
                            value+=v;
                        }
                        output.Add("  total qty "+quantity+" value "+money(value));
                    } else {
                        output.Add("AGING"+(selected==null ? "" : " "+selected.code)+" day "+day);
                        long[] quantities=new long[4],values=new long[4];
                        foreach (Item s in items.Values) {
                            long[] q=new long[4];
                            foreach (Stock a in selectedStock(s,selected)) {
                                long age=day-a.lot.day;
                                int b=age<=30 ? 0 : age<=60 ? 1 : age<=90 ? 2 : 3;
                                q[b]+=a.quantity;
                                quantities[b]+=a.quantity;
                                values[b]+=a.value();
                            }
                            if (q.Sum()>0) output.Add(buckets(s.code,q,false));
                        }
                        output.Add(buckets("total",quantities,false));
                        output.Add(buckets("value",values,true));
                    }
                    break;
                }
                case "LOTS": {
                    Warehouse w=warehouse(t[1]);
                    Item s=item(t[2]);
                    output.Add("LOTS "+w.code+" "+s.code);
                    foreach (Stock a in fifo(w,s)) output.Add("  lot "+a.lot.number+" day "+a.lot.day+" qty "+a.quantity+" cost "+money(a.cost)+" value "+money(a.value())+" age "+(day-a.lot.day));
                    foreach (Order o in orders) if (o.warehouse==w && o.item==s && o.backorder>0) output.Add("  backorder order "+o.number+" qty "+o.backorder);
                    break;
                }
                case "REORDER":
                case "ITEMS":
                    output.Add(t[0]);
                    foreach (Item s in items.Values) {
                        long h=onhand(s),b=backorder(s);
                        if (t[0].Equals("ITEMS")) output.Add("  "+s.code+" "+s.name+" level "+s.level+" onhand "+h+" backorder "+b+" cost "+(s.lastCost==null ? "none" : money(s.lastCost.Value)));
                        else if (h-b<=s.level) output.Add("  "+s.code+" "+s.name+" onhand "+h+" backorder "+b+" level "+s.level);
                    }
                    break;
                case "MARGIN":
                case "TOP": {
                    Dictionary<Item,long[]> summaries=new();
                    foreach (Item s in items.Values) {
                        long[] a=sales(s);
                        if (a[3]>0) summaries[s]=a;
                    }
                    if (t[0].Equals("MARGIN")) {
                        output.Add("MARGIN");
                        foreach (Item s in items.Values) if (summaries.ContainsKey(s)) output.Add(salesLine(s.code,summaries[s]));
                        output.Add(salesLine("total",sales(null)));
                    } else {
                        int k=(int)long.Parse(t[1]);
                        output.Add("TOP "+k);
                        List<Item> ranked=summaries.Keys.OrderByDescending(s => summaries[s][1]-summaries[s][2])
                            .ThenByDescending(s => summaries[s][1]).ThenBy(s => s.code,StringComparer.Ordinal).Take(k).ToList();
                        for (int i=0;i<ranked.Count;i++) {
                            Item s=ranked[i];
                            long[] a=summaries[s];
                            output.Add("  "+(i+1)+" "+s.code+" profit "+money(a[1]-a[2])+" revenue "+money(a[1])+" margin "+margin(a[1]-a[2],a[1]));
                        }
                    }
                    break;
                }
                case "BACKORDERS":
                    output.Add("BACKORDERS");
                    foreach (Order o in orders) if (o.backorder>0) output.Add("  order "+o.number+" "+o.warehouse.code+" "+o.item.code+" qty "+o.backorder+" day "+o.day+" price "+money(o.price));
                    break;
                case "ORDER": {
                    Order o=order(t[1]);
                    output.Add("ORDER "+o.number+" "+o.warehouse.code+" "+o.item.code+" day "+o.day+" price "+money(o.price));
                    output.Add("  ordered "+o.ordered+" shipped "+o.shipped+" backorder "+o.backorder+" cancelled "+o.cancelled+" returned "+o.returned);
                    foreach (Part p in o.parts) output.Add("  lot "+p.lot.number+" qty "+p.quantity+" cost "+money(p.cost));
                    output.Add("  revenue "+money(o.revenue)+" cogs "+money(o.cogs)+" profit "+money(o.revenue-o.cogs));
                    break;
                }
                case "TRACE": {
                    Lot lot=lookupLot(t[1]);
                    output.Add("TRACE lot "+lot.number+" "+lot.item.code+" "+lot.kind+" "+lot.warehouse+" day "+lot.day+" qty "+lot.initialQuantity+" cost "+money(lot.initialCost));
                    foreach (Warehouse w in warehouses.Values) {
                        foreach (Stock a in stock(w,lot.item)) if (a.lot==lot) output.Add("  held "+w.code+" qty "+a.quantity+" cost "+money(a.cost));
                    }
                    foreach (Order o in orders) {
                        long q=o.parts.Where(p => p.lot==lot).Sum(p => p.quantity);
                        if (q>0) output.Add("  order "+o.number+" qty "+q);
                    }
                    if (lot.removed>0) output.Add("  removed qty "+lot.removed);
                    break;
                }
                case "CARD": {
                    Item s=item(t[1]);
                    output.Add("CARD "+s.code+" "+s.name);
                    long quantity=0,value=0;
                    foreach (Card c in s.cards) {
                        quantity+=c.quantity;
                        value+=c.value;
                        output.Add("  day "+c.day+" "+c.kind+" "+c.warehouse+" "+signed(c.quantity)+" "+signedMoney(c.value)+" balance "+quantity+" "+money(value));
                    }
                    break;
                }
                case "STATUS":
                    output.Add("STATUS");
                    foreach (Warehouse w in warehouses.Values) {
                        List<Stock> held=w.stock.Values.SelectMany(map => map.Values).ToList();
                        long q=held.Sum(a => a.quantity),v=held.Sum(a => a.value());
                        int skus=w.stock.Values.Count(map => map.Count>0);
                        long backorder=orders.Where(o => o.warehouse==w).Sum(o => o.backorder);
                        output.Add("  "+w.code+" skus "+skus+" qty "+q+" value "+money(v)+" backorder "+backorder);
                    }
                    break;
                case "SUMMARY": {
                    output.Add("SUMMARY");
                    for (int i=0;i<8;i++) output.Add("  "+CATEGORIES[i]+" qty "+totals[i][0]+" value "+money(totals[i][1]));
                    long q=items.Values.Sum(s => onhand(s));
                    long v=items.Values.Sum(s => warehouses.Values.Sum(w => stockValue(w,s)));
                    output.Add("  on-hand qty "+q+" value "+money(v));
                    output.Add("  orders "+orders.Count+" open "+orders.Count(o => o.backorder>0)+" backorder "+orders.Sum(o => o.backorder));
                    break;
                }
            }
            if (output.Count==1 && new[]{"LOTS","REORDER","ITEMS","TOP","BACKORDERS","CARD","STATUS"}.Contains(t[0])) output.Add("  (none)");
        }
        public List<string> process(string line) {
            output=new();
            try { execute(line.Split(' ')); }
            catch (Fault f) { output.Add("ERROR "+f.Message); }
            return output;
        }
    }
    static void Main() {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        Inventory inventory=new();
        int n=int.Parse(Console.ReadLine()!);
        for (int i=0;i<n;i++) {
            foreach (string line in inventory.process(Console.ReadLine()!)) Console.WriteLine(line);
        }
    }
}
