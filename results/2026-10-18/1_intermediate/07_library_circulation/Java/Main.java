import java.io.*;
import java.util.*;

public class Main {
    static class Fault extends RuntimeException {
        Fault(String reason) { super(reason); }
    }
    static void check(boolean condition, String reason) { if (condition) throw new Fault(reason); }
    static class Item {
        int day, amount, unpaid;
        String kind, isbn;
        Item(int day, String kind, String isbn, int amount) {
            this.day=day;
            this.kind=kind;
            this.isbn=isbn;
            this.amount=amount;
            unpaid=amount;
        }
    }
    static class Member {
        String id, type, name;
        int limit, period, rate, cap, reservationLimit, fee, queued;
        TreeMap<String,Copy> loans=new TreeMap<>(), holds=new TreeMap<>();
        List<Item> items=new ArrayList<>();
        List<String> history=new ArrayList<>();
        Member(String id, String type, String name) {
            this.id=id;
            this.type=type;
            this.name=name;
            boolean student=type.equals("STUDENT");
            limit=student ? 3 : 10;
            period=student ? 14 : 28;
            rate=student ? 25 : 10;
            cap=student ? 1000 : 2000;
            reservationLimit=student ? 2 : 5;
            fee=student ? 50 : 100;
        }
        int balance() { return items.stream().mapToInt(i -> i.unpaid).sum(); }
        int reservations() { return queued+holds.size(); }
        boolean blocked() { return balance()>500; }
        String status() { return blocked() ? "BLOCKED" : "OK"; }
    }
    static class Title {
        String isbn, name;
        int price, borrowed;
        List<Copy> copies=new ArrayList<>();
        List<Member> queue=new ArrayList<>();
        Title(String isbn, String name, int price) {
            this.isbn=isbn;
            this.name=name;
            this.price=price;
        }
        int count(String state) { return (int)copies.stream().filter(c -> c.state.equals(state)).count(); }
        int holdings() { return count("AVAILABLE")+count("LOANED")+count("HOLD"); }
    }
    static class Copy {
        Title title;
        int number, loanDay, due, renewals, expiry;
        String state="AVAILABLE";
        Member owner;
        Copy(Title title, int number) {
            this.title=title;
            this.number=number;
        }
    }
    static class Library {
        int day=1, borrowed, returned, renewed, lost, fines, fees, charges, paid, waived;
        TreeMap<String,Title> titles=new TreeMap<>();
        TreeMap<String,Member> members=new TreeMap<>();
        Set<Integer> closed=new HashSet<>();
        List<Copy> copies=new ArrayList<>();
        List<String> output;
        void emit(String line) { output.add(line); }
        Member member(String id) {
            Member m=members.get(id);
            check(m==null,"unknown member");
            return m;
        }
        Title book(String raw) {
            String isbn=normalize(raw);
            Title b=titles.get(isbn);
            check(b==null,"unknown book");
            return b;
        }
        Copy loan(Member m, Title b) {
            Copy c=m.loans.get(b.isbn);
            check(c==null,"not borrowed");
            return c;
        }
        int open(int d) {
            while (closed.contains(d)) d++;
            return d;
        }
        int late(Copy c) { return Math.max(0,day-c.due); }
        int fine(Copy c) { return Math.min(late(c)*c.owner.rate,c.owner.cap); }
        void charge(Member m, String kind, Title b, int amount) {
            if (amount==0) return;
            m.items.add(new Item(day,kind,b.isbn,amount));
            switch (kind) {
                case "FINE":
                    fines+=amount;
                    break;
                case "FEE":
                    fees+=amount;
                    break;
                default: charges+=amount;
            }
        }
        void release(Copy c) {
            Title b=c.title;
            c.owner=null;
            if (b.queue.isEmpty()) c.state="AVAILABLE";
            else {
                Member m=b.queue.remove(0);
                m.queued--;
                c.state="HOLD";
                c.owner=m;
                c.expiry=open(day+3);
                m.holds.put(b.isbn,c);
                emit("HOLD "+b.isbn+" copy "+c.number+" "+m.id+" until "+c.expiry);
            }
        }
        int[] endLoan(Copy c, boolean loss) {
            Member m=c.owner;
            int l=late(c), f=fine(c);
            m.loans.remove(c.title.isbn);
            charge(m,"FINE",c.title,f);
            m.history.add((loss ? "LOST " : "RETURNED ")+c.title.isbn+" copy "+c.number+
                " from "+c.loanDay+" to "+day+" late "+l+" fine "+money(f)+
                (loss ? " price "+money(c.title.price) : ""));
            return new int[]{l,f};
        }
        void loss(Copy c, String heading) {
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
                for (Member queued:b.queue) {
                    queued.queued--;
                    emit("DROPPED "+b.isbn+" "+queued.id);
                }
                b.queue.clear();
            }
        }
        String renewalReason(Copy c) {
            if (c.due<day) return "loan overdue";
            if (c.renewals==2) return "renewal limit";
            if (!c.title.queue.isEmpty()) return "title reserved";
            return null;
        }
        void renew(Copy c) {
            c.due=open(day+c.owner.period);
            c.renewals++;
            renewed++;
            emit("RENEW "+c.owner.id+" "+c.title.isbn+" copy "+c.number+" due "+c.due+" renewals "+c.renewals);
        }
        List<Copy> orderedLoans(Member m) {
            return m.loans.values().stream().sorted(Comparator.comparingInt((Copy c) -> c.due).thenComparing(c -> c.title.isbn)).toList();
        }
        List<Copy> orderedHolds(Member m) {
            return m.holds.values().stream().sorted(Comparator.comparingInt((Copy c) -> c.expiry).thenComparing(c -> c.title.isbn)).toList();
        }
        void showMember(Member m) {
            emit("MEMBER "+m.id+" "+m.type+" "+m.name);
            emit("STATUS loans "+m.loans.size()+"/"+m.limit+" reservations "+m.reservations()+"/"+m.reservationLimit+
                " balance "+money(m.balance())+" "+m.status());
            for (Copy c:orderedLoans(m)) emit("LOAN "+c.title.isbn+" copy "+c.number+" due "+c.due+" renewals "+c.renewals+
                (c.due<day ? " late "+late(c)+" fine "+money(fine(c)) : ""));
            for (Copy c:orderedHolds(m)) emit("HOLD "+c.title.isbn+" copy "+c.number+" until "+c.expiry);
            for (Title b:titles.values()) {
                int p=b.queue.indexOf(m);
                if (p>=0) emit("QUEUE "+b.isbn+" position "+(p+1));
            }
        }
        void execute(String line) {
            String[] t=line.split(" ");
            switch (t[0]) {
                case "DAY": {
                    int d=Integer.parseInt(t[1]);
                    check(d<=day,"invalid day");
                    emit("DAY "+d);
                    while (day<d) {
                        day++;
                        List<Copy> losses=copies.stream().filter(c -> c.state.equals("LOANED") && c.due+365<=day)
                            .sorted(Comparator.comparing((Copy c) -> c.owner.id).thenComparing(c -> c.title.isbn)).toList();
                        for (Copy c:losses) loss(c,"AUTOLOST");
                        List<Copy> expired=copies.stream().filter(c -> c.state.equals("HOLD") && c.expiry<day)
                            .sorted(Comparator.comparing((Copy c) -> c.title.isbn).thenComparingInt(c -> c.number)).toList();
                        for (Copy c:expired) {
                            Member m=c.owner;
                            charge(m,"FEE",c.title,m.fee);
                            m.holds.remove(c.title.isbn);
                            emit("EXPIRED "+c.title.isbn+" copy "+c.number+" "+m.id+" fee "+money(m.fee));
                            release(c);
                        }
                    }
                    break;
                }
                case "CLOSED": {
                    int d=Integer.parseInt(t[1]);
                    check(d<=day,"invalid day");
                    check(closed.contains(d),"already closed");
                    closed.add(d);
                    emit("CLOSED "+d);
                    for (Title b:titles.values()) {
                        for (Copy c:b.copies) {
                            if (c.state.equals("LOANED") && c.due==d) {
                                c.due=open(d);
                                emit("MOVED "+b.isbn+" copy "+c.number+" "+c.owner.id+" due "+c.due);
                            } else if (c.state.equals("HOLD") && c.expiry==d) {
                                c.expiry=open(d);
                                emit("MOVED "+b.isbn+" copy "+c.number+" "+c.owner.id+" until "+c.expiry);
                            }
                        }
                    }
                    break;
                }
                case "ADDBOOK": {
                    String isbn=normalize(t[1]), name=String.join(" ",Arrays.copyOfRange(t,4,t.length));
                    Title b=titles.get(isbn);
                    check(b!=null && !b.name.equals(name),"title mismatch");
                    int price=parseMoney(t[3]), count=Integer.parseInt(t[2]);
                    if (b==null) {
                        b=new Title(isbn,name,price);
                        titles.put(isbn,b);
                    }
                    b.price=price;
                    List<Copy> added=new ArrayList<>();
                    for (int i=0;i<count;i++) {
                        Copy c=new Copy(b,b.copies.size()+1);
                        b.copies.add(c);
                        copies.add(c);
                        added.add(c);
                    }
                    emit("ADDBOOK "+isbn+" added "+count+" total "+b.holdings());
                    for (Copy c:added) release(c);
                    break;
                }
                case "ADDMEMBER": {
                    check(members.containsKey(t[1]),"duplicate member");
                    check(!t[2].equals("STUDENT") && !t[2].equals("STAFF"),"unknown type");
                    Member m=new Member(t[1],t[2],String.join(" ",Arrays.copyOfRange(t,3,t.length)));
                    members.put(m.id,m);
                    emit("ADDMEMBER "+m.id+" "+m.type+" loans "+m.limit+" days "+m.period);
                    break;
                }
                case "WITHDRAW": {
                    Title b=book(t[1]);
                    int n=Integer.parseInt(t[2]);
                    check(n<1 || n>b.copies.size(),"unknown copy");
                    Copy c=b.copies.get(n-1);
                    check(!c.state.equals("AVAILABLE"),"copy not available");
                    c.state="WITHDRAWN";
                    emit("WITHDRAW "+b.isbn+" copy "+n+" total "+b.holdings());
                    break;
                }
                case "BORROW": {
                    Member m=member(t[1]);
                    Title b=book(t[2]);
                    check(closed.contains(day),"library closed");
                    check(m.loans.containsKey(b.isbn),"already borrowed");
                    check(m.blocked(),"member blocked");
                    check(m.loans.values().stream().anyMatch(c -> c.due<day),"overdue loans");
                    check(m.loans.size()>=m.limit,"loan limit");
                    Copy c=m.holds.get(b.isbn);
                    if (c==null) c=b.copies.stream().filter(x -> x.state.equals("AVAILABLE")).findFirst().orElse(null);
                    check(c==null,b.count("HOLD")>0 ? "all copies on hold" : "no copy available");
                    m.holds.remove(b.isbn);
                    c.state="LOANED";
                    c.owner=m;
                    c.loanDay=day;
                    c.due=open(day+m.period);
                    c.renewals=0;
                    m.loans.put(b.isbn,c);
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
                    String reason=renewalReason(c);
                    check(reason!=null,reason);
                    renew(c);
                    break;
                }
                case "RENEWALL": {
                    Member m=member(t[1]);
                    check(m.loans.isEmpty(),"no loans");
                    check(m.blocked(),"member blocked");
                    int done=0, skipped=0;
                    for (Copy c:m.loans.values()) {
                        String reason=renewalReason(c);
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
                    check(m.loans.containsKey(b.isbn),"already borrowed");
                    check(b.queue.contains(m) || m.holds.containsKey(b.isbn),"already reserved");
                    check(m.blocked(),"member blocked");
                    check(m.reservations()>=m.reservationLimit,"reservation limit");
                    check(b.holdings()==0,"no copies");
                    check(b.count("AVAILABLE")>0,"copy available");
                    b.queue.add(m);
                    m.queued++;
                    int p=b.queue.size();
                    List<Integer> dues=b.copies.stream().filter(c -> c.state.equals("LOANED")).map(c -> c.due).sorted().toList();
                    emit("RESERVE "+m.id+" "+b.isbn+" position "+p+" estimate "+(p<=dues.size() ? dues.get(p-1).toString() : "none"));
                    break;
                }
                case "CANCEL": {
                    Member m=member(t[1]);
                    Title b=book(t[2]);
                    int p=b.queue.indexOf(m);
                    Copy c=m.holds.get(b.isbn);
                    check(p<0 && c==null,"not reserved");
                    if (p>=0) {
                        b.queue.remove(p);
                        m.queued--;
                        emit("CANCEL "+m.id+" "+b.isbn+" queue");
                    } else {
                        m.holds.remove(b.isbn);
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
                    List<String> details=new ArrayList<>();
                    for (int i=0;i<m.items.size() && rest>0;i++) {
                        Item item=m.items.get(i);
                        int applied=Math.min(rest,item.unpaid);
                        if (applied==0) continue;
                        rest-=applied;
                        item.unpaid-=applied;
                        details.add("ITEM "+(i+1)+" "+item.kind+" paid "+money(applied)+" remaining "+money(item.unpaid));
                    }
                    paid+=amount-rest;
                    emit("PAYFINE "+m.id+" paid "+money(amount-rest)+" change "+money(rest)+" balance "+money(m.balance()));
                    output.addAll(details);
                    break;
                }
                case "WAIVE": {
                    Member m=member(t[1]);
                    int n=Integer.parseInt(t[2]);
                    check(n<1 || n>m.items.size(),"unknown item");
                    Item item=m.items.get(n-1);
                    check(item.unpaid==0,"item settled");
                    int amount=item.unpaid;
                    item.unpaid=0;
                    waived+=amount;
                    emit("WAIVE "+m.id+" item "+n+" "+item.kind+" amount "+money(amount)+" balance "+money(m.balance()));
                    break;
                }
                case "FINES": {
                    Member m=member(t[1]);
                    emit("FINES "+m.id+" items "+m.items.stream().filter(i -> i.unpaid>0).count()+" balance "+money(m.balance()));
                    for (int i=0;i<m.items.size();i++) {
                        Item item=m.items.get(i);
                        if (item.unpaid>0) emit((i+1)+" day "+item.day+" "+item.kind+" "+item.isbn+" amount "+money(item.amount)+" remaining "+money(item.unpaid));
                    }
                    break;
                }
                case "SEARCH": {
                    String keyword=lower(String.join(" ",Arrays.copyOfRange(t,1,t.length)));
                    List<Title> found=titles.values().stream().filter(b -> lower(b.name).contains(keyword))
                        .sorted(Comparator.comparing((Title b) -> lower(b.name)).thenComparing(b -> b.isbn)).toList();
                    emit("SEARCH "+found.size());
                    for (Title b:found) emit(b.isbn+" "+b.count("AVAILABLE")+"/"+b.holdings()+" "+b.name);
                    break;
                }
                case "OVERDUE": {
                    List<Copy> found=copies.stream().filter(c -> c.state.equals("LOANED") && c.due<day)
                        .sorted(Comparator.comparingInt((Copy c) -> c.due).thenComparing(c -> c.owner.id).thenComparing(c -> c.title.isbn)).toList();
                    emit("OVERDUE "+found.size());
                    for (Copy c:found) emit(c.owner.id+" "+c.title.isbn+" copy "+c.number+" due "+c.due+" late "+late(c)+" fine "+money(fine(c)));
                    break;
                }
                case "NOTICES": {
                    List<String> notices=new ArrayList<>();
                    for (Member m:members.values()) {
                        List<Copy> loans=orderedLoans(m);
                        for (Copy c:loans) if (c.due<day) notices.add("OVERDUE "+m.id+" "+c.title.isbn+" due "+c.due);
                        for (Copy c:loans) if (c.due>=day && c.due<=day+2) notices.add("DUESOON "+m.id+" "+c.title.isbn+" due "+c.due);
                        for (Copy c:orderedHolds(m)) notices.add("PICKUP "+m.id+" "+c.title.isbn+" until "+c.expiry);
                    }
                    emit("NOTICES "+notices.size());
                    output.addAll(notices);
                    break;
                }
                case "MEMBER":
                    showMember(member(t[1]));
                    break;
                case "MEMBERS": {
                    emit("MEMBERS "+members.size());
                    for (Member m:members.values()) emit(m.id+" "+m.type+" loans "+m.loans.size()+" reservations "+m.reservations()+
                        " balance "+money(m.balance())+" "+m.status());
                    break;
                }
                case "BOOK": {
                    Title b=book(t[1]);
                    emit("BOOK "+b.isbn+" "+b.name);
                    emit("PRICE "+money(b.price)+" copies "+b.holdings()+" borrowed "+b.borrowed);
                    for (Copy c:b.copies) emit("COPY "+c.number+" "+c.state+
                        (c.state.equals("LOANED") ? " "+c.owner.id+" due "+c.due : c.state.equals("HOLD") ? " "+c.owner.id+" until "+c.expiry : ""));
                    emit("QUEUE "+b.queue.size()+(b.queue.isEmpty() ? "" : " "+String.join(" ",b.queue.stream().map(m -> m.id).toList())));
                    break;
                }
                case "INVENTORY": {
                    int a=0,l=0,h=0,x=0,w=0;
                    for (Title b:titles.values()) {
                        a+=b.count("AVAILABLE");
                        l+=b.count("LOANED");
                        h+=b.count("HOLD");
                        x+=b.count("LOST");
                        w+=b.count("WITHDRAWN");
                    }
                    emit("INVENTORY titles "+titles.size()+" copies "+(a+l+h)+" available "+a+" loaned "+l+" hold "+h+" lost "+x+" withdrawn "+w);
                    for (Title b:titles.values()) emit(b.isbn+" copies "+b.holdings()+" available "+b.count("AVAILABLE")+" loaned "+b.count("LOANED")+
                        " hold "+b.count("HOLD")+" queue "+b.queue.size());
                    break;
                }
                case "HISTORY": {
                    Member m=member(t[1]);
                    emit("HISTORY "+m.id+" "+m.history.size());
                    output.addAll(m.history);
                    break;
                }
                case "STATS": {
                    int active=members.values().stream().mapToInt(m -> m.loans.size()).sum();
                    int outstanding=members.values().stream().mapToInt(Member::balance).sum();
                    emit("STATS day "+day+" titles "+titles.size()+" members "+members.size()+" closed "+closed.size());
                    emit("LOANS borrowed "+borrowed+" returned "+returned+" renewed "+renewed+" lost "+lost+" active "+active);
                    emit("MONEY fines "+money(fines)+" fees "+money(fees)+" charges "+money(charges)+" paid "+money(paid)+" waived "+money(waived)+" outstanding "+money(outstanding));
                    List<Title> top=titles.values().stream().filter(b -> b.borrowed>0)
                        .sorted(Comparator.comparingInt((Title b) -> b.borrowed).reversed().thenComparing(b -> b.isbn)).limit(3).toList();
                    for (int i=0;i<top.size();i++) {
                        Title b=top.get(i);
                        emit("TOP "+(i+1)+" "+b.isbn+" "+b.borrowed+" "+b.name);
                    }
                    break;
                }
            }
        }
        List<String> process(String line) {
            output=new ArrayList<>();
            try { execute(line); }
            catch (Fault fault) { output.add("ERROR "+fault.getMessage()); }
            return output;
        }
    }
    static String normalize(String raw) {
        String s=raw.replace("-","");
        if (s.matches("[0-9]{9}[0-9X]")) {
            int sum=0;
            for (int i=0;i<10;i++) sum+=(10-i)*(s.charAt(i)=='X' ? 10 : s.charAt(i)-'0');
            check(sum%11!=0,"invalid isbn");
            String prefix="978"+s.substring(0,9);
            sum=0;
            for (int i=0;i<12;i++) sum+=(i%2==0 ? 1 : 3)*(prefix.charAt(i)-'0');
            return prefix+(10-sum%10)%10;
        }
        check(!s.matches("97[89][0-9]{10}"),"invalid isbn");
        int sum=0;
        for (int i=0;i<13;i++) sum+=(i%2==0 ? 1 : 3)*(s.charAt(i)-'0');
        check(sum%10!=0,"invalid isbn");
        return s;
    }
    static int parseMoney(String s) {
        String[] p=s.split("\\.");
        return Integer.parseInt(p[0])*100+Integer.parseInt(p[1]);
    }
    static String money(int n) { return n/100+"."+(n%100<10 ? "0" : "")+n%100; }
    static String lower(String s) { return s.toLowerCase(Locale.ROOT); }
    public static void main(String[] args) throws IOException {
        BufferedReader input=new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output=new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Library library=new Library();
        int n=Integer.parseInt(input.readLine());
        for (int i=0;i<n;i++) {
            for (String line:library.process(input.readLine())) output.println(line);
        }
        output.flush();
    }
}
