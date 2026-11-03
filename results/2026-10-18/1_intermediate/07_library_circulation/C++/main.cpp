#include <algorithm>
#include <array>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

using std::string;
using std::vector;
enum State { AVAILABLE, LOANED, HOLD, LOST, WITHDRAWN };
const string stateNames[] = {"AVAILABLE", "LOANED", "HOLD", "LOST", "WITHDRAWN"};
const string kinds[] = {"FINE", "FEE", "PRICE"};
struct Ref { int title, copy; };
struct Copy {
    State state = AVAILABLE;
    int member = -1, from = 0, due = 0, renewals = 0, expiry = 0;
};
struct Title {
    string isbn, name, folded;
    int price = 0, borrowed = 0;
    std::array<int,5> counts{};
    vector<Copy> copies;
    vector<int> queue;
};
struct Charge { int day, kind, title, amount, unpaid; };
struct Member {
    string id, type, name;
    int limit, period, rate, cap, reserveLimit, fee;
    int balance = 0, reservations = 0;
    vector<Ref> loans, holds;
    vector<Charge> charges;
    vector<string> history;
};
string join(const vector<string> &a, int start) {
    string result;
    for (int i = start; i < int(a.size()); ++i) {
        if (i != start) result += ' ';
        result += a[i];
    }
    return result;
}
string money(int value) {
    return std::to_string(value/100) + "." + (value%100 < 10 ? "0" : "") + std::to_string(value%100);
}
int cents(const string &s) {
    std::size_t dot = s.find('.');
    return std::stoi(s.substr(0,dot))*100 + std::stoi(s.substr(dot+1));
}
string lower(string s) {
    for (char &c : s) if (c >= 'A' && c <= 'Z') c += 'a'-'A';
    return s;
}
string normalize(const string &input) {
    string s = input;
    s.erase(std::remove(s.begin(),s.end(),'-'),s.end());
    if (s.size() == 10) {
        int sum = 0;
        for (int i = 0; i < 10; ++i) {
            if (!(s[i] >= '0' && s[i] <= '9') && !(i == 9 && s[i] == 'X')) return "";
            sum += (10-i)*(s[i] == 'X' ? 10 : s[i]-'0');
        }
        if (sum%11) return "";
        s = "978" + s.substr(0,9);
        sum = 0;
        for (int i = 0; i < 12; ++i) sum += (i%2 ? 3 : 1)*(s[i]-'0');
        s += char('0'+(10-sum%10)%10);
        return s;
    }
    if (s.size() != 13 || (s.substr(0,3) != "978" && s.substr(0,3) != "979")) return "";
    int sum = 0;
    for (int i = 0; i < 13; ++i) {
        if (s[i] < '0' || s[i] > '9') return "";
        sum += (i%2 ? 3 : 1)*(s[i]-'0');
    }
    return sum%10 ? "" : s;
}
struct Library {
    int day = 1, borrowed = 0, returned = 0, renewed = 0, lost = 0, paid = 0, waived = 0;
    std::array<int,3> charged{};
    std::set<int> closed;
    std::map<string,int> titleIds, memberIds;
    vector<Title> titles;
    vector<Member> members;
    vector<string> output;

    void line(const string &s) { output.push_back(s); }
    bool error(bool condition, const string &reason) {
        if (condition) line("ERROR " + reason);
        return condition;
    }
    int open(int d) const {
        while (closed.count(d)) ++d;
        return d;
    }
    int holdings(int t) const { return titles[t].counts[AVAILABLE]+titles[t].counts[LOANED]+titles[t].counts[HOLD]; }
    Copy &copy(Ref r) { return titles[r.title].copies[r.copy]; }
    const Copy &copy(Ref r) const { return titles[r.title].copies[r.copy]; }
    void state(Ref r, State next) {
        Title &t = titles[r.title];
        --t.counts[t.copies[r.copy].state];
        t.copies[r.copy].state = next;
        ++t.counts[next];
    }
    static void remove(vector<Ref> &refs, Ref r) {
        refs.erase(std::find_if(refs.begin(),refs.end(),[r](Ref q) { return q.title == r.title && q.copy == r.copy; }));
    }
    int find(const vector<Ref> &refs, int title) const {
        for (Ref r : refs) if (r.title == title) return r.copy;
        return -1;
    }
    int member(const string &id) {
        std::map<string,int>::const_iterator found = memberIds.find(id);
        if (error(found == memberIds.end(),"unknown member")) return -1;
        return found->second;
    }
    int title(const string &input) {
        string isbn = normalize(input);
        if (error(isbn.empty(),"invalid isbn")) return -1;
        std::map<string,int>::const_iterator found = titleIds.find(isbn);
        if (error(found == titleIds.end(),"unknown book")) return -1;
        return found->second;
    }
    bool pair(const vector<string> &a, int &m, int &t) {
        m = member(a[1]);
        if (m < 0) return false;
        t = title(a[2]);
        return t >= 0;
    }
    int late(Ref r) const { return std::max(0,day-copy(r).due); }
    int fine(Ref r) const {
        const Member &m = members[copy(r).member];
        return std::min(late(r)*m.rate,m.cap);
    }
    void charge(int m, int kind, int t, int amount) {
        if (!amount) return;
        members[m].charges.push_back({day,kind,t,amount,amount});
        members[m].balance += amount;
        charged[kind] += amount;
    }
    void release(Ref r) {
        Title &t = titles[r.title];
        if (t.queue.empty()) {
            state(r,AVAILABLE);
            return;
        }
        int m = t.queue.front();
        t.queue.erase(t.queue.begin());
        state(r,HOLD);
        Copy &c = copy(r);
        c.member = m;
        c.expiry = open(day+3);
        members[m].holds.push_back(r);
        line("HOLD " + t.isbn + " copy " + std::to_string(r.copy+1) + " " + members[m].id + " until " + std::to_string(c.expiry));
    }
    void dropQueue(int t) {
        if (holdings(t)) return;
        for (int m : titles[t].queue) {
            --members[m].reservations;
            line("DROPPED " + titles[t].isbn + " " + members[m].id);
        }
        titles[t].queue.clear();
    }
    void endLoan(Ref r, bool loss, const string &heading) {
        Copy c = copy(r);
        int m = c.member, l = late(r), f = fine(r);
        Member &person = members[m];
        Title &book = titles[r.title];
        remove(person.loans,r);
        charge(m,0,r.title,f);
        string history = string(loss ? "LOST" : "RETURNED") + " " + book.isbn + " copy " + std::to_string(r.copy+1) + " from " + std::to_string(c.from) + " to " + std::to_string(day) + " late " + std::to_string(l) + " fine " + money(f);
        if (loss) {
            history += " price " + money(book.price);
            charge(m,2,r.title,book.price);
            state(r,LOST);
            ++lost;
        } else ++returned;
        person.history.push_back(history);
        string result = heading + " " + person.id + " " + book.isbn + " copy " + std::to_string(r.copy+1) + " late " + std::to_string(l) + " fine " + money(f);
        if (loss) result += " price " + money(book.price);
        line(result + " balance " + money(person.balance));
        if (loss) dropQueue(r.title);
        else release(r);
    }
    string renewalReason(Ref r) const {
        if (late(r)) return "loan overdue";
        if (copy(r).renewals == 2) return "renewal limit";
        if (!titles[r.title].queue.empty()) return "title reserved";
        return "";
    }
    void renew(Ref r) {
        Copy &c = copy(r);
        Member &m = members[c.member];
        c.due = open(day+m.period);
        ++c.renewals;
        ++renewed;
        line("RENEW " + m.id + " " + titles[r.title].isbn + " copy " + std::to_string(r.copy+1) + " due " + std::to_string(c.due) + " renewals " + std::to_string(c.renewals));
    }
    vector<Ref> ordered(const vector<Ref> &refs, bool holds = false) const {
        vector<Ref> result = refs;
        std::sort(result.begin(),result.end(),[this,holds](Ref a, Ref b) {
            int x = holds ? copy(a).expiry : copy(a).due, y = holds ? copy(b).expiry : copy(b).due;
            return std::tie(x,titles[a.title].isbn) < std::tie(y,titles[b.title].isbn);
        });
        return result;
    }
    void execute(const vector<string> &a) {
        const string &cmd = a[0];
        if (cmd == "DAY") {
            int target = std::stoi(a[1]);
            if (error(target <= day,"invalid day")) return;
            line("DAY " + a[1]);
            while (day < target) {
                ++day;
                vector<Ref> losses;
                for (const auto &[memberId, id] : memberIds) {
                    for (Ref r : members[id].loans) if (copy(r).due+365 <= day) losses.push_back(r);
                }
                for (Ref r : losses) endLoan(r,true,"AUTOLOST");
                vector<Ref> expiries;
                for (const auto &[isbn, id] : titleIds) {
                    int t = id;
                    for (int i = 0; i < int(titles[t].copies.size()); ++i) {
                        const Copy &c = titles[t].copies[i];
                        if (c.state == HOLD && c.expiry < day) expiries.push_back({t,i});
                    }
                }
                for (Ref r : expiries) {
                    int m = copy(r).member;
                    charge(m,1,r.title,members[m].fee);
                    remove(members[m].holds,r);
                    --members[m].reservations;
                    line("EXPIRED " + titles[r.title].isbn + " copy " + std::to_string(r.copy+1) + " " + members[m].id + " fee " + money(members[m].fee));
                    release(r);
                }
            }
        } else if (cmd == "CLOSED") {
            int d = std::stoi(a[1]);
            if (error(d <= day,"invalid day") || error(closed.count(d),"already closed")) return;
            closed.insert(d);
            line("CLOSED " + a[1]);
            for (const auto &[isbn, id] : titleIds) {
                Title &t = titles[id];
                for (int i = 0; i < int(t.copies.size()); ++i) {
                    Copy &c = t.copies[i];
                    if (c.state == LOANED && c.due == d) {
                        c.due = open(d);
                        line("MOVED " + t.isbn + " copy " + std::to_string(i+1) + " " + members[c.member].id + " due " + std::to_string(c.due));
                    } else if (c.state == HOLD && c.expiry == d) {
                        c.expiry = open(d);
                        line("MOVED " + t.isbn + " copy " + std::to_string(i+1) + " " + members[c.member].id + " until " + std::to_string(c.expiry));
                    }
                }
            }
        } else if (cmd == "ADDBOOK") {
            string isbn = normalize(a[1]), name = join(a,4);
            if (error(isbn.empty(),"invalid isbn")) return;
            std::map<string,int>::const_iterator found = titleIds.find(isbn);
            int t = found == titleIds.end() ? -1 : found->second;
            if (error(t >= 0 && titles[t].name != name,"title mismatch")) return;
            if (t < 0) {
                t = int(titles.size());
                Title book;
                book.isbn = isbn;
                book.name = name;
                book.folded = lower(name);
                titles.push_back(book);
                titleIds[isbn] = t;
            }
            Title &book = titles[t];
            book.price = cents(a[3]);
            int start = int(book.copies.size()), count = std::stoi(a[2]);
            book.copies.resize(start+count);
            book.counts[AVAILABLE] += count;
            line("ADDBOOK " + isbn + " added " + a[2] + " total " + std::to_string(holdings(t)));
            for (int i = start; i < start+count; ++i) release({t,i});
        } else if (cmd == "ADDMEMBER") {
            if (error(memberIds.count(a[1]),"duplicate member") || error(a[2] != "STUDENT" && a[2] != "STAFF","unknown type")) return;
            Member m;
            m.id = a[1];
            m.type = a[2];
            m.name = join(a,3);
            bool staff = m.type == "STAFF";
            m.limit = staff ? 10 : 3;
            m.period = staff ? 28 : 14;
            m.rate = staff ? 10 : 25;
            m.cap = staff ? 2000 : 1000;
            m.reserveLimit = staff ? 5 : 2;
            m.fee = staff ? 100 : 50;
            memberIds[m.id] = int(members.size());
            members.push_back(m);
            line("ADDMEMBER " + m.id + " " + m.type + " loans " + std::to_string(m.limit) + " days " + std::to_string(m.period));
        } else if (cmd == "WITHDRAW") {
            int t = title(a[1]);
            if (t < 0) return;
            int i = std::stoi(a[2])-1;
            if (error(i < 0 || i >= int(titles[t].copies.size()),"unknown copy")) return;
            if (error(titles[t].copies[i].state != AVAILABLE,"copy not available")) return;
            state({t,i},WITHDRAWN);
            line("WITHDRAW " + titles[t].isbn + " copy " + a[2] + " total " + std::to_string(holdings(t)));
        } else if (cmd == "BORROW" || cmd == "RETURN" || cmd == "RENEW" || cmd == "RESERVE" || cmd == "CANCEL" || cmd == "LOST") {
            int m, t;
            if (!pair(a,m,t)) return;
            Member &person = members[m];
            Title &book = titles[t];
            int loan = find(person.loans,t), hold = find(person.holds,t);
            vector<int>::iterator queued = std::find(book.queue.begin(),book.queue.end(),m);
            if (cmd == "BORROW") {
                if (error(closed.count(day),"library closed") || error(loan >= 0,"already borrowed") || error(person.balance > 500,"member blocked")) return;
                bool overdue = std::any_of(person.loans.begin(),person.loans.end(),[this](Ref r) { return late(r) > 0; });
                if (error(overdue,"overdue loans") || error(int(person.loans.size()) >= person.limit,"loan limit")) return;
                const auto available = std::find_if(book.copies.begin(),book.copies.end(),[](const Copy &c) { return c.state == AVAILABLE; });
                int i = hold >= 0 ? hold : available == book.copies.end() ? -1 : int(available-book.copies.begin());
                if (error(i < 0,book.counts[HOLD] ? "all copies on hold" : "no copy available")) return;
                Ref r{t,i};
                if (hold >= 0) {
                    remove(person.holds,r);
                    --person.reservations;
                }
                state(r,LOANED);
                Copy &c = copy(r);
                c.member = m;
                c.from = day;
                c.due = open(day+person.period);
                c.renewals = 0;
                person.loans.push_back(r);
                std::sort(person.loans.begin(),person.loans.end(),[this](Ref x,Ref y) { return titles[x.title].isbn < titles[y.title].isbn; });
                ++borrowed;
                ++book.borrowed;
                line("BORROW " + person.id + " " + book.isbn + " copy " + std::to_string(i+1) + " due " + std::to_string(c.due));
            } else if (cmd == "RETURN" || cmd == "LOST" || cmd == "RENEW") {
                if (error(loan < 0,"not borrowed")) return;
                Ref r{t,loan};
                if (cmd == "RENEW") {
                    if (error(person.balance > 500,"member blocked")) return;
                    string reason = renewalReason(r);
                    if (error(!reason.empty(),reason)) return;
                    renew(r);
                } else endLoan(r,cmd == "LOST",cmd);
            } else if (cmd == "RESERVE") {
                if (error(loan >= 0,"already borrowed") || error(queued != book.queue.end() || hold >= 0,"already reserved") || error(person.balance > 500,"member blocked") || error(person.reservations >= person.reserveLimit,"reservation limit") || error(!holdings(t),"no copies") || error(book.counts[AVAILABLE] > 0,"copy available")) return;
                book.queue.push_back(m);
                ++person.reservations;
                vector<int> dues;
                for (const Copy &c : book.copies) if (c.state == LOANED) dues.push_back(c.due);
                std::sort(dues.begin(),dues.end());
                int p = int(book.queue.size());
                line("RESERVE " + person.id + " " + book.isbn + " position " + std::to_string(p) + " estimate " + (p <= int(dues.size()) ? std::to_string(dues[p-1]) : "none"));
            } else {
                if (error(queued == book.queue.end() && hold < 0,"not reserved")) return;
                --person.reservations;
                if (queued != book.queue.end()) {
                    book.queue.erase(queued);
                    line("CANCEL " + person.id + " " + book.isbn + " queue");
                } else {
                    Ref r{t,hold};
                    remove(person.holds,r);
                    line("CANCEL " + person.id + " " + book.isbn + " hold copy " + std::to_string(hold+1));
                    release(r);
                }
            }
        } else if (cmd == "RENEWALL") {
            int m = member(a[1]);
            if (m < 0) return;
            if (error(members[m].loans.empty(),"no loans") || error(members[m].balance > 500,"member blocked")) return;
            int good = 0, skipped = 0;
            for (Ref r : members[m].loans) {
                string reason = renewalReason(r);
                if (reason.empty()) {
                    renew(r);
                    ++good;
                } else {
                    line("SKIP " + titles[r.title].isbn + " " + reason);
                    ++skipped;
                }
            }
            line("RENEWALL " + a[1] + " renewed " + std::to_string(good) + " skipped " + std::to_string(skipped));
        } else if (cmd == "PAYFINE" || cmd == "WAIVE" || cmd == "FINES") {
            int m = member(a[1]);
            if (m < 0) return;
            Member &person = members[m];
            if (cmd == "PAYFINE") {
                if (error(!person.balance,"no fines")) return;
                int amount = cents(a[2]), remaining = amount;
                vector<string> details;
                for (int i = 0; i < int(person.charges.size()) && remaining; ++i) {
                    Charge &c = person.charges[i];
                    int applied = std::min(remaining,c.unpaid);
                    if (!applied) continue;
                    c.unpaid -= applied;
                    remaining -= applied;
                    details.push_back("ITEM " + std::to_string(i+1) + " " + kinds[c.kind] + " paid " + money(applied) + " remaining " + money(c.unpaid));
                }
                person.balance -= amount-remaining;
                paid += amount-remaining;
                line("PAYFINE " + person.id + " paid " + money(amount-remaining) + " change " + money(remaining) + " balance " + money(person.balance));
                for (const string &s : details) line(s);
            } else if (cmd == "WAIVE") {
                int i = std::stoi(a[2])-1;
                if (error(i < 0 || i >= int(person.charges.size()),"unknown item")) return;
                Charge &c = person.charges[i];
                if (error(!c.unpaid,"item settled")) return;
                int amount = c.unpaid;
                c.unpaid = 0;
                person.balance -= amount;
                waived += amount;
                line("WAIVE " + person.id + " item " + a[2] + " " + kinds[c.kind] + " amount " + money(amount) + " balance " + money(person.balance));
            } else {
                int count = std::count_if(person.charges.begin(),person.charges.end(),[](const Charge &c) { return c.unpaid > 0; });
                line("FINES " + person.id + " items " + std::to_string(count) + " balance " + money(person.balance));
                for (int i = 0; i < int(person.charges.size()); ++i) {
                    const Charge &c = person.charges[i];
                    if (c.unpaid) line(std::to_string(i+1) + " day " + std::to_string(c.day) + " " + kinds[c.kind] + " " + titles[c.title].isbn + " amount " + money(c.amount) + " remaining " + money(c.unpaid));
                }
            }
        } else if (cmd == "SEARCH") {
            string keyword = lower(join(a,1));
            vector<int> found;
            for (int t = 0; t < int(titles.size()); ++t) if (titles[t].folded.find(keyword) != string::npos) found.push_back(t);
            std::sort(found.begin(),found.end(),[this](int a,int b) { return std::tie(titles[a].folded,titles[a].isbn) < std::tie(titles[b].folded,titles[b].isbn); });
            line("SEARCH " + std::to_string(found.size()));
            for (int t : found) line(titles[t].isbn + " " + std::to_string(titles[t].counts[AVAILABLE]) + "/" + std::to_string(holdings(t)) + " " + titles[t].name);
        } else if (cmd == "OVERDUE") {
            vector<Ref> refs;
            for (const Member &m : members) for (Ref r : m.loans) if (late(r)) refs.push_back(r);
            std::sort(refs.begin(),refs.end(),[this](Ref a,Ref b) { return std::tie(copy(a).due,members[copy(a).member].id,titles[a.title].isbn) < std::tie(copy(b).due,members[copy(b).member].id,titles[b.title].isbn); });
            line("OVERDUE " + std::to_string(refs.size()));
            for (Ref r : refs) line(members[copy(r).member].id + " " + titles[r.title].isbn + " copy " + std::to_string(r.copy+1) + " due " + std::to_string(copy(r).due) + " late " + std::to_string(late(r)) + " fine " + money(fine(r)));
        } else if (cmd == "NOTICES") {
            vector<string> notices;
            for (const auto &[memberId, id] : memberIds) {
                const Member &m = members[id];
                for (Ref r : ordered(m.loans)) if (copy(r).due <= day+2) notices.push_back(string(late(r) ? "OVERDUE " : "DUESOON ") + m.id + " " + titles[r.title].isbn + " due " + std::to_string(copy(r).due));
                for (Ref r : ordered(m.holds,true)) notices.push_back("PICKUP " + m.id + " " + titles[r.title].isbn + " until " + std::to_string(copy(r).expiry));
            }
            line("NOTICES " + std::to_string(notices.size()));
            for (const string &s : notices) line(s);
        } else if (cmd == "MEMBER" || cmd == "MEMBERS" || cmd == "HISTORY") {
            int target = -1;
            if (cmd != "MEMBERS") {
                target = member(a[1]);
                if (target < 0) return;
            }
            if (cmd == "HISTORY") {
                line("HISTORY " + a[1] + " " + std::to_string(members[target].history.size()));
                for (const string &s : members[target].history) line(s);
                return;
            }
            if (cmd == "MEMBERS") line("MEMBERS " + std::to_string(members.size()));
            for (const auto &[memberId, id] : memberIds) {
                if (target >= 0 && id != target) continue;
                const Member &m = members[id];
                string status = m.balance > 500 ? "BLOCKED" : "OK";
                if (cmd == "MEMBERS") {
                    line(m.id + " " + m.type + " loans " + std::to_string(m.loans.size()) + " reservations " + std::to_string(m.reservations) + " balance " + money(m.balance) + " " + status);
                    continue;
                }
                line("MEMBER " + m.id + " " + m.type + " " + m.name);
                line("STATUS loans " + std::to_string(m.loans.size()) + "/" + std::to_string(m.limit) + " reservations " + std::to_string(m.reservations) + "/" + std::to_string(m.reserveLimit) + " balance " + money(m.balance) + " " + status);
                for (Ref r : ordered(m.loans)) {
                    string s = "LOAN " + titles[r.title].isbn + " copy " + std::to_string(r.copy+1) + " due " + std::to_string(copy(r).due) + " renewals " + std::to_string(copy(r).renewals);
                    if (late(r)) s += " late " + std::to_string(late(r)) + " fine " + money(fine(r));
                    line(s);
                }
                for (Ref r : ordered(m.holds,true)) line("HOLD " + titles[r.title].isbn + " copy " + std::to_string(r.copy+1) + " until " + std::to_string(copy(r).expiry));
                for (const auto &[isbn, t] : titleIds) {
                    const vector<int> &q = titles[t].queue;
                    vector<int>::const_iterator it = std::find(q.begin(),q.end(),id);
                    if (it != q.end()) line("QUEUE " + isbn + " position " + std::to_string(it-q.begin()+1));
                }
            }
        } else if (cmd == "BOOK") {
            int t = title(a[1]);
            if (t < 0) return;
            const Title &book = titles[t];
            line("BOOK " + book.isbn + " " + book.name);
            line("PRICE " + money(book.price) + " copies " + std::to_string(holdings(t)) + " borrowed " + std::to_string(book.borrowed));
            for (int i = 0; i < int(book.copies.size()); ++i) {
                const Copy &c = book.copies[i];
                string s = "COPY " + std::to_string(i+1) + " " + stateNames[c.state];
                if (c.state == LOANED || c.state == HOLD) s += " " + members[c.member].id + (c.state == LOANED ? " due " : " until ") + std::to_string(c.state == LOANED ? c.due : c.expiry);
                line(s);
            }
            string q = "QUEUE " + std::to_string(book.queue.size());
            for (int m : book.queue) q += " " + members[m].id;
            line(q);
        } else if (cmd == "INVENTORY") {
            std::array<int,5> counts{};
            for (const Title &t : titles) for (int i = 0; i < 5; ++i) counts[i] += t.counts[i];
            line("INVENTORY titles " + std::to_string(titles.size()) + " copies " + std::to_string(counts[0]+counts[1]+counts[2]) + " available " + std::to_string(counts[0]) + " loaned " + std::to_string(counts[1]) + " hold " + std::to_string(counts[2]) + " lost " + std::to_string(counts[3]) + " withdrawn " + std::to_string(counts[4]));
            for (const auto &[isbn, id] : titleIds) {
                const Title &t = titles[id];
                line(t.isbn + " copies " + std::to_string(holdings(id)) + " available " + std::to_string(t.counts[0]) + " loaned " + std::to_string(t.counts[1]) + " hold " + std::to_string(t.counts[2]) + " queue " + std::to_string(t.queue.size()));
            }
        } else if (cmd == "STATS") {
            int active = 0, outstanding = 0;
            for (const Member &m : members) {
                active += int(m.loans.size());
                outstanding += m.balance;
            }
            line("STATS day " + std::to_string(day) + " titles " + std::to_string(titles.size()) + " members " + std::to_string(members.size()) + " closed " + std::to_string(closed.size()));
            line("LOANS borrowed " + std::to_string(borrowed) + " returned " + std::to_string(returned) + " renewed " + std::to_string(renewed) + " lost " + std::to_string(lost) + " active " + std::to_string(active));
            line("MONEY fines " + money(charged[0]) + " fees " + money(charged[1]) + " charges " + money(charged[2]) + " paid " + money(paid) + " waived " + money(waived) + " outstanding " + money(outstanding));
            vector<int> top;
            for (int t = 0; t < int(titles.size()); ++t) if (titles[t].borrowed) top.push_back(t);
            std::sort(top.begin(),top.end(),[this](int a,int b) {
                if (titles[a].borrowed != titles[b].borrowed) return titles[a].borrowed > titles[b].borrowed;
                return titles[a].isbn < titles[b].isbn;
            });
            for (int i = 0; i < std::min(3,int(top.size())); ++i) line("TOP " + std::to_string(i+1) + " " + titles[top[i]].isbn + " " + std::to_string(titles[top[i]].borrowed) + " " + titles[top[i]].name);
        }
    }
};
int main() {
    string line;
    std::getline(std::cin,line);
    int count = std::stoi(line);
    Library library;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin,line);
        std::istringstream input(line);
        vector<string> arguments;
        string word;
        while (input >> word) arguments.push_back(word);
        library.output.clear();
        library.execute(arguments);
        for (const string &s : library.output) std::cout << s << '\n';
    }
}
