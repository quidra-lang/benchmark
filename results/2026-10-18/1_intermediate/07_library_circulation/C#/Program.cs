using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text.RegularExpressions;

class Program {
    class Fault  : Exception {
        public Fault(string reason) : base(reason) {}
    }
    static void check(bool condition, string reason) { if (condition) throw new Fault(reason); }
    class Item {
        public int day, amount, unpaid;
        public string kind, isbn;
        public Item(int day, string kind, string isbn, int amount) {
            this.day=day;
            this.kind=kind;
            this.isbn=isbn;
            this.amount=amount;
            unpaid=amount;
        }
    }
    class Member {
        public string id, type, name;
        public int limit, period, rate, cap, reservationLimit, fee, queued;
        public SortedDictionary<string,Copy> loans=new(StringComparer.Ordinal), holds=new(StringComparer.Ordinal);
        public List<Item> items=new();
        public List<string> history=new();
        public Member(string id, string type, string name) {
            this.id=id;
            this.type=type;
            this.name=name;
            bool student=type.Equals("STUDENT");
            limit=student ? 3 : 10;
            period=student ? 14 : 28;
            rate=student ? 25 : 10;
            cap=student ? 1000 : 2000;
            reservationLimit=student ? 2 : 5;
            fee=student ? 50 : 100;
        }
        public int balance() { return items.Sum(i => i.unpaid); }
        public int reservations() { return queued+holds.Count; }
        public bool blocked() { return balance()>500; }
        public string status() { return blocked() ? "BLOCKED" : "OK"; }
    }
    class Title {
        public string isbn, name;
        public int price, borrowed;
        public List<Copy> copies=new();
        public List<Member> queue=new();
        public Title(string isbn, string name, int price) {
            this.isbn=isbn;
            this.name=name;
            this.price=price;
        }
        public int count(string state) { return (int)copies.Count(c => c.state.Equals(state)); }
        public int holdings() { return count("AVAILABLE")+count("LOANED")+count("HOLD"); }
    }
    class Copy {
        public Title title;
        public int number, loanDay, due, renewals, expiry;
        public string state="AVAILABLE";
        public Member owner;
        public Copy(Title title, int number) {
            this.title=title;
            this.number=number;
        }
    }
    class Library {
        public int day=1, borrowed, returned, renewed, lost, fines, fees, charges, paid, waived;
        public SortedDictionary<string,Title> titles=new(StringComparer.Ordinal);
        public SortedDictionary<string,Member> members=new(StringComparer.Ordinal);
        public HashSet<int> closed=new();
        public List<Copy> copies=new();
        public List<string> output;
        public void emit(string line) { output.Add(line); }
        public Member member(string id) {
            Member m=members.GetValueOrDefault(id);
            check(m==null,"unknown member");
            return m;
        }
        public Title book(string raw) {
            string isbn=normalize(raw);
            Title b=titles.GetValueOrDefault(isbn);
            check(b==null,"unknown book");
            return b;
        }
        public Copy loan(Member m, Title b) {
            Copy c=m.loans.GetValueOrDefault(b.isbn);
            check(c==null,"not borrowed");
            return c;
        }
        public int open(int d) {
            while (closed.Contains(d)) d++;
            return d;
        }
        public int late(Copy c) { return Math.Max(0,day-c.due); }
        public int fine(Copy c) { return Math.Min(late(c)*c.owner.rate,c.owner.cap); }
        public void charge(Member m, string kind, Title b, int amount) {
            if (amount==0) return;
            m.items.Add(new Item(day,kind,b.isbn,amount));
            switch (kind) {
                case "FINE":
                    fines+=amount;
                    break;
                case "FEE":
                    fees+=amount;
                    break;
                default:
                    charges+=amount;
                    break;
            }
        }
        public void release(Copy c) {
            Title b=c.title;
            c.owner=null;
            if (b.queue.Count==0) c.state="AVAILABLE";
            else {
                Member m=b.queue[0];
                b.queue.RemoveAt(0);
                m.queued--;
                c.state="HOLD";
                c.owner=m;
                c.expiry=open(day+3);
                m.holds[b.isbn]=c;
                emit("HOLD "+b.isbn+" copy "+c.number+" "+m.id+" until "+c.expiry);
            }
        }
        public int[] endLoan(Copy c, bool loss) {
            Member m=c.owner;
            int l=late(c), f=fine(c);
            m.loans.Remove(c.title.isbn);
            charge(m,"FINE",c.title,f);
            m.history.Add((loss ? "LOST " : "RETURNED ")+c.title.isbn+" copy "+c.number+
                " from "+c.loanDay+" to "+day+" late "+l+" fine "+money(f)+
                (loss ? " price "+money(c.title.price) : ""));
            return new int[]{l,f};
        }
        public void loss(Copy c, string heading) {
            Member m=c.owner;
            Title b=c.title;
            int[] values=endLoan(c,true);
            charge(m,"PRICE",b,b.price);
            c.state="LOST";
            c.owner=null;
            lost++;
            emit(heading+" "+m.id+" "+b.isbn+" copy "+c.number+" late "+values[0]+" fine "+money(values[1])+
                " price "+money(b.price)+" balance "+money(m.balance()));
            if (b.holdings()==0) {
                foreach (Member queued in b.queue) {
                    queued.queued--;
                    emit("DROPPED "+b.isbn+" "+queued.id);
                }
                b.queue.Clear();
            }
        }
        public string renewalReason(Copy c) {
            if (c.due<day) return "loan overdue";
            if (c.renewals==2) return "renewal limit";
            if (c.title.queue.Count!=0) return "title reserved";
            return null;
        }
        public void renew(Copy c) {
            c.due=open(day+c.owner.period);
            c.renewals++;
            renewed++;
            emit("RENEW "+c.owner.id+" "+c.title.isbn+" copy "+c.number+" due "+c.due+" renewals "+c.renewals);
        }
        public List<Copy> orderedLoans(Member m) {
            return m.loans.Values.OrderBy(c => c.due).ThenBy(c => c.title.isbn,StringComparer.Ordinal).ToList();
        }
        public List<Copy> orderedHolds(Member m) {
            return m.holds.Values.OrderBy(c => c.expiry).ThenBy(c => c.title.isbn,StringComparer.Ordinal).ToList();
        }
        public void showMember(Member m) {
            emit("MEMBER "+m.id+" "+m.type+" "+m.name);
            emit("STATUS loans "+m.loans.Count+"/"+m.limit+" reservations "+m.reservations()+"/"+m.reservationLimit+
                " balance "+money(m.balance())+" "+m.status());
            foreach (Copy c in orderedLoans(m)) emit("LOAN "+c.title.isbn+" copy "+c.number+" due "+c.due+" renewals "+c.renewals+
                (c.due<day ? " late "+late(c)+" fine "+money(fine(c)) : ""));
            foreach (Copy c in orderedHolds(m)) emit("HOLD "+c.title.isbn+" copy "+c.number+" until "+c.expiry);
            foreach (Title b in titles.Values) {
                int p=b.queue.IndexOf(m);
                if (p>=0) emit("QUEUE "+b.isbn+" position "+(p+1));
            }
        }
        public void execute(string line) {
            string[] t=line.Split(' ');
            switch (t[0]) {
                case "DAY": {
                    int d=int.Parse(t[1]);
                    check(d<=day,"invalid day");
                    emit("DAY "+d);
                    while (day<d) {
                        day++;
                        List<Copy> losses=copies.Where(c => c.state.Equals("LOANED") && c.due+365<=day)
                            .OrderBy(c => c.owner.id,StringComparer.Ordinal).ThenBy(c => c.title.isbn,StringComparer.Ordinal).ToList();
                        foreach (Copy c in losses) loss(c,"AUTOLOST");
                        List<Copy> expired=copies.Where(c => c.state.Equals("HOLD") && c.expiry<day)
                            .OrderBy(c => c.title.isbn,StringComparer.Ordinal).ThenBy(c => c.number).ToList();
                        foreach (Copy c in expired) {
                            Member m=c.owner;
                            charge(m,"FEE",c.title,m.fee);
                            m.holds.Remove(c.title.isbn);
                            emit("EXPIRED "+c.title.isbn+" copy "+c.number+" "+m.id+" fee "+money(m.fee));
                            release(c);
                        }
                    }
                    break;
                }
                case "CLOSED": {
                    int d=int.Parse(t[1]);
                    check(d<=day,"invalid day");
                    check(closed.Contains(d),"already closed");
                    closed.Add(d);
                    emit("CLOSED "+d);
                    foreach (Title b in titles.Values) {
                        foreach (Copy c in b.copies) {
                            if (c.state.Equals("LOANED") && c.due==d) {
                                c.due=open(d);
                                emit("MOVED "+b.isbn+" copy "+c.number+" "+c.owner.id+" due "+c.due);
                            } else if (c.state.Equals("HOLD") && c.expiry==d) {
                                c.expiry=open(d);
                                emit("MOVED "+b.isbn+" copy "+c.number+" "+c.owner.id+" until "+c.expiry);
                            }
                        }
                    }
                    break;
                }
                case "ADDBOOK": {
                    string isbn=normalize(t[1]), name=string.Join(" ",t.Skip(4));
                    Title b=titles.GetValueOrDefault(isbn);
                    check(b!=null && !b.name.Equals(name),"title mismatch");
                    int price=parseMoney(t[3]), count=int.Parse(t[2]);
                    if (b==null) {
                        b=new Title(isbn,name,price);
                        titles[isbn]=b;
                    }
                    b.price=price;
                    List<Copy> added=new();
                    for (int i=0;i<count;i++) {
                        Copy c=new Copy(b,b.copies.Count+1);
                        b.copies.Add(c);
                        copies.Add(c);
                        added.Add(c);
                    }
                    emit("ADDBOOK "+isbn+" added "+count+" total "+b.holdings());
                    foreach (Copy c in added) release(c);
                    break;
                }
                case "ADDMEMBER": {
                    check(members.ContainsKey(t[1]),"duplicate member");
                    check(!t[2].Equals("STUDENT") && !t[2].Equals("STAFF"),"unknown type");
                    Member m=new Member(t[1],t[2],string.Join(" ",t.Skip(3)));
                    members[m.id]=m;
                    emit("ADDMEMBER "+m.id+" "+m.type+" loans "+m.limit+" days "+m.period);
                    break;
                }
                case "WITHDRAW": {
                    Title b=book(t[1]);
                    int n=int.Parse(t[2]);
                    check(n<1 || n>b.copies.Count,"unknown copy");
                    Copy c=b.copies[n-1];
                    check(!c.state.Equals("AVAILABLE"),"copy not available");
                    c.state="WITHDRAWN";
                    emit("WITHDRAW "+b.isbn+" copy "+n+" total "+b.holdings());
                    break;
                }
                case "BORROW": {
                    Member m=member(t[1]);
                    Title b=book(t[2]);
                    check(closed.Contains(day),"library closed");
                    check(m.loans.ContainsKey(b.isbn),"already borrowed");
                    check(m.blocked(),"member blocked");
                    check(m.loans.Values.Any(c => c.due<day),"overdue loans");
                    check(m.loans.Count>=m.limit,"loan limit");
                    Copy c=m.holds.GetValueOrDefault(b.isbn);
                    if (c==null) c=b.copies.FirstOrDefault(x => x.state.Equals("AVAILABLE"));
                    check(c==null,b.count("HOLD")>0 ? "all copies on hold" : "no copy available");
                    m.holds.Remove(b.isbn);
                    c.state="LOANED";
                    c.owner=m;
                    c.loanDay=day;
                    c.due=open(day+m.period);
                    c.renewals=0;
                    m.loans[b.isbn]=c;
                    b.borrowed++;
                    borrowed++;
                    emit("BORROW "+m.id+" "+b.isbn+" copy "+c.number+" due "+c.due);
                    break;
                }
                case "RETURN": {
                    Member m=member(t[1]);
                    Title b=book(t[2]);
                    Copy c=loan(m,b);
                    int[] values=endLoan(c,false);
                    returned++;
                    emit("RETURN "+m.id+" "+b.isbn+" copy "+c.number+" late "+values[0]+" fine "+money(values[1])+" balance "+money(m.balance()));
                    release(c);
                    break;
                }
                case "RENEW": {
                    Member m=member(t[1]);
                    Copy c=loan(m,book(t[2]));
                    check(m.blocked(),"member blocked");
                    string reason=renewalReason(c);
                    check(reason!=null,reason);
                    renew(c);
                    break;
                }
                case "RENEWALL": {
                    Member m=member(t[1]);
                    check(m.loans.Count==0,"no loans");
                    check(m.blocked(),"member blocked");
                    int done=0, skipped=0;
                    foreach (Copy c in m.loans.Values) {
                        string reason=renewalReason(c);
                        if (reason!=null) {
                            emit("SKIP "+c.title.isbn+" "+reason);
                            skipped++;
                        } else {
                            renew(c);
                            done++;
                        }
                    }
                    emit("RENEWALL "+m.id+" renewed "+done+" skipped "+skipped);
                    break;
                }
                case "RESERVE": {
                    Member m=member(t[1]);
                    Title b=book(t[2]);
                    check(m.loans.ContainsKey(b.isbn),"already borrowed");
                    check(b.queue.Contains(m) || m.holds.ContainsKey(b.isbn),"already reserved");
                    check(m.blocked(),"member blocked");
                    check(m.reservations()>=m.reservationLimit,"reservation limit");
                    check(b.holdings()==0,"no copies");
                    check(b.count("AVAILABLE")>0,"copy available");
                    b.queue.Add(m);
                    m.queued++;
                    int p=b.queue.Count;
                    List<int> dues=b.copies.Where(c => c.state.Equals("LOANED")).Select(c => c.due).OrderBy(d => d).ToList();
                    emit("RESERVE "+m.id+" "+b.isbn+" position "+p+" estimate "+(p<=dues.Count ? dues[p-1].ToString() : "none"));
                    break;
                }
                case "CANCEL": {
                    Member m=member(t[1]);
                    Title b=book(t[2]);
                    int p=b.queue.IndexOf(m);
                    Copy c=m.holds.GetValueOrDefault(b.isbn);
                    check(p<0 && c==null,"not reserved");
                    if (p>=0) {
                        b.queue.RemoveAt(p);
                        m.queued--;
                        emit("CANCEL "+m.id+" "+b.isbn+" queue");
                    } else {
                        m.holds.Remove(b.isbn);
                        emit("CANCEL "+m.id+" "+b.isbn+" hold copy "+c.number);
                        release(c);
                    }
                    break;
                }
                case "LOST": {
                    Member m=member(t[1]);
                    loss(loan(m,book(t[2])),"LOST");
                    break;
                }
                case "PAYFINE": {
                    Member m=member(t[1]);
                    check(m.balance()==0,"no fines");
                    int amount=parseMoney(t[2]), rest=amount;
                    List<string> details=new();
                    for (int i=0;i<m.items.Count && rest>0;i++) {
                        Item item=m.items[i];
                        int applied=Math.Min(rest,item.unpaid);
                        if (applied==0) continue;
                        rest-=applied;
                        item.unpaid-=applied;
                        details.Add("ITEM "+(i+1)+" "+item.kind+" paid "+money(applied)+" remaining "+money(item.unpaid));
                    }
                    paid+=amount-rest;
                    emit("PAYFINE "+m.id+" paid "+money(amount-rest)+" change "+money(rest)+" balance "+money(m.balance()));
                    output.AddRange(details);
                    break;
                }
                case "WAIVE": {
                    Member m=member(t[1]);
                    int n=int.Parse(t[2]);
                    check(n<1 || n>m.items.Count,"unknown item");
                    Item item=m.items[n-1];
                    check(item.unpaid==0,"item settled");
                    int amount=item.unpaid;
                    item.unpaid=0;
                    waived+=amount;
                    emit("WAIVE "+m.id+" item "+n+" "+item.kind+" amount "+money(amount)+" balance "+money(m.balance()));
                    break;
                }
                case "FINES": {
                    Member m=member(t[1]);
                    emit("FINES "+m.id+" items "+m.items.Count(i => i.unpaid>0)+" balance "+money(m.balance()));
                    for (int i=0;i<m.items.Count;i++) {
                        Item item=m.items[i];
                        if (item.unpaid>0) emit((i+1)+" day "+item.day+" "+item.kind+" "+item.isbn+" amount "+money(item.amount)+" remaining "+money(item.unpaid));
                    }
                    break;
                }
                case "SEARCH": {
                    string keyword=lower(string.Join(" ",t.Skip(1)));
                    List<Title> found=titles.Values.Where(b => lower(b.name).Contains(keyword))
                        .OrderBy(b => lower(b.name),StringComparer.Ordinal).ThenBy(b => b.isbn,StringComparer.Ordinal).ToList();
                    emit("SEARCH "+found.Count);
                    foreach (Title b in found) emit(b.isbn+" "+b.count("AVAILABLE")+"/"+b.holdings()+" "+b.name);
                    break;
                }
                case "OVERDUE": {
                    List<Copy> found=copies.Where(c => c.state.Equals("LOANED") && c.due<day)
                        .OrderBy(c => c.due).ThenBy(c => c.owner.id,StringComparer.Ordinal).ThenBy(c => c.title.isbn,StringComparer.Ordinal).ToList();
                    emit("OVERDUE "+found.Count);
                    foreach (Copy c in found) emit(c.owner.id+" "+c.title.isbn+" copy "+c.number+" due "+c.due+" late "+late(c)+" fine "+money(fine(c)));
                    break;
                }
                case "NOTICES": {
                    List<string> notices=new();
                    foreach (Member m in members.Values) {
                        List<Copy> loans=orderedLoans(m);
                        foreach (Copy c in loans) if (c.due<day) notices.Add("OVERDUE "+m.id+" "+c.title.isbn+" due "+c.due);
                        foreach (Copy c in loans) if (c.due>=day && c.due<=day+2) notices.Add("DUESOON "+m.id+" "+c.title.isbn+" due "+c.due);
                        foreach (Copy c in orderedHolds(m)) notices.Add("PICKUP "+m.id+" "+c.title.isbn+" until "+c.expiry);
                    }
                    emit("NOTICES "+notices.Count);
                    output.AddRange(notices);
                    break;
                }
                case "MEMBER":
                    showMember(member(t[1]));
                    break;
                case "MEMBERS": {
                    emit("MEMBERS "+members.Count);
                    foreach (Member m in members.Values) emit(m.id+" "+m.type+" loans "+m.loans.Count+" reservations "+m.reservations()+
                        " balance "+money(m.balance())+" "+m.status());
                    break;
                }
                case "BOOK": {
                    Title b=book(t[1]);
                    emit("BOOK "+b.isbn+" "+b.name);
                    emit("PRICE "+money(b.price)+" copies "+b.holdings()+" borrowed "+b.borrowed);
                    foreach (Copy c in b.copies) emit("COPY "+c.number+" "+c.state+
                        (c.state.Equals("LOANED") ? " "+c.owner.id+" due "+c.due : c.state.Equals("HOLD") ? " "+c.owner.id+" until "+c.expiry : ""));
                    emit("QUEUE "+b.queue.Count+(b.queue.Count==0 ? "" : " "+string.Join(" ",b.queue.Select(m => m.id))));
                    break;
                }
                case "INVENTORY": {
                    int a=0,l=0,h=0,x=0,w=0;
                    foreach (Title b in titles.Values) {
                        a+=b.count("AVAILABLE");
                        l+=b.count("LOANED");
                        h+=b.count("HOLD");
                        x+=b.count("LOST");
                        w+=b.count("WITHDRAWN");
                    }
                    emit("INVENTORY titles "+titles.Count+" copies "+(a+l+h)+" available "+a+" loaned "+l+" hold "+h+" lost "+x+" withdrawn "+w);
                    foreach (Title b in titles.Values) emit(b.isbn+" copies "+b.holdings()+" available "+b.count("AVAILABLE")+" loaned "+b.count("LOANED")+
                        " hold "+b.count("HOLD")+" queue "+b.queue.Count);
                    break;
                }
                case "HISTORY": {
                    Member m=member(t[1]);
                    emit("HISTORY "+m.id+" "+m.history.Count);
                    output.AddRange(m.history);
                    break;
                }
                case "STATS": {
                    int active=members.Values.Sum(m => m.loans.Count);
                    int outstanding=members.Values.Sum(m => m.balance());
                    emit("STATS day "+day+" titles "+titles.Count+" members "+members.Count+" closed "+closed.Count);
                    emit("LOANS borrowed "+borrowed+" returned "+returned+" renewed "+renewed+" lost "+lost+" active "+active);
                    emit("MONEY fines "+money(fines)+" fees "+money(fees)+" charges "+money(charges)+" paid "+money(paid)+" waived "+money(waived)+" outstanding "+money(outstanding));
                    List<Title> top=titles.Values.Where(b => b.borrowed>0)
                        .OrderByDescending(b => b.borrowed).ThenBy(b => b.isbn,StringComparer.Ordinal).Take(3).ToList();
                    for (int i=0;i<top.Count;i++) {
                        Title b=top[i];
                        emit("TOP "+(i+1)+" "+b.isbn+" "+b.borrowed+" "+b.name);
                    }
                    break;
                }
            }
        }
        public List<string> process(string line) {
            output=new();
            try { execute(line); }
            catch (Fault fault) { output.Add("ERROR "+fault.Message); }
            return output;
        }
    }
    static string normalize(string raw) {
        string s=raw.Replace("-","");
        if (matches(s,"[0-9]{9}[0-9X]")) {
            int sum=0;
            for (int i=0;i<10;i++) sum+=(10-i)*(s[i]=='X' ? 10 : s[i]-'0');
            check(sum%11!=0,"invalid isbn");
            string prefix="978"+s.Substring(0,9);
            sum=0;
            for (int i=0;i<12;i++) sum+=(i%2==0 ? 1 : 3)*(prefix[i]-'0');
            return prefix+(10-sum%10)%10;
        }
        check(!matches(s,"97[89][0-9]{10}"),"invalid isbn");
        int sum13=0;
        for (int i=0;i<13;i++) sum13+=(i%2==0 ? 1 : 3)*(s[i]-'0');
        check(sum13%10!=0,"invalid isbn");
        return s;
    }
    static int parseMoney(string s) {
        string[] p=s.Split('.');
        return int.Parse(p[0])*100+int.Parse(p[1]);
    }
    static string money(int n) { return n/100+"."+(n%100<10 ? "0" : "")+n%100; }
    static string lower(string s) { return s.ToLowerInvariant(); }
    static bool matches(string s, string pattern) => Regex.IsMatch(s,"\\A(?:"+pattern+")\\z",RegexOptions.CultureInvariant);
    static void Main() {
        CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
        Library library=new();
        int n=int.Parse(Console.ReadLine()!);
        for (int i=0;i<n;i++) {
            foreach (string line in library.process(Console.ReadLine()!)) Console.WriteLine(line);
        }
    }
}
