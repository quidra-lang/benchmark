#include <algorithm>
#include <array>
#include <cctype>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using namespace std;
const string columns="ABCDEFGHJKLMNOPQRST";
const map<int,vector<string>>handicapPoints={
    {
        9,{
            "C3","G7","C7","G3","C5","G5","E3","E7","E5"
        }
    },{
        13,{
            "D4","K10","D10","K4","D7","K7","G4","G10","G7"
        }
    },{
        19,{
            "D4","Q16","D16","Q4","D10","Q10","K4","K16","K10"
        }
    }
};
const map<string,int>arity={
    {
        "BOARD",2
    },{
        "KOMI",1
    },{
        "SUPERKO",1
    },{
        "HANDICAP",1
    },{
        "PLAY",2
    },{
        "PASS",1
    },{
        "REPLAY",1
    },{
        "UNDO",0
    },{
        "SHOW",0
    },{
        "MAP",0
    },{
        "STATUS",0
    },{
        "CAPTURES",0
    },{
        "HISTORY",0
    },{
        "MOVES",0
    },{
        "GROUP",1
    },{
        "GROUPS",0
    },{
        "ATARI",0
    },{
        "LEGAL",1
    },{
        "EYES",1
    },{
        "SAFE",1
    },{
        "LADDER",1
    },{
        "DEAD",1
    },{
        "REGIONS",0
    },{
        "SCORE",1
    }
};
char other(char c){
    return c=='B'?'W':'B';
}
string halfText(int x){
    return (x<0?"-":"")+to_string(abs(x)/2)+(abs(x)%2?".5":".0");
}
optional<int>komi(string s){
    if(!regex_match(s,regex("-?(0|[1-9][0-9]*)(\\.[05])?")))return nullopt;
    bool negative=s[0]=='-';
    if(negative)s=s.substr(1);
    size_t p=s.find('.');
    string whole=s.substr(0,p);
    if(whole.size()>3)return nullopt;
    int k=stoi(whole);
    if(k>100)return nullopt;
    int x=2*k+(p!=string::npos&&s[p+1]=='5');
    if(negative&&!x)return nullopt;
    return negative?-x:x;
}
vector<int>adjacent(int p,int n,bool diagonal=false){
    int r=p/n,c=p%n;
    vector<int>a;
    vector<pair<int,int>>steps=diagonal?vector<pair<int,int>>{
        {
            -1,-1
        },{
            -1,1
        },{
            1,-1
        },{
            1,1
        }
    }:vector<pair<int,int>>{
        {
            -1,0
        },{
            1,0
        },{
            0,-1
        },{
            0,1
        }
    };
    for(auto [dr,dc]:steps)if(r+dr>=0&&r+dr<n&&c+dc>=0&&c+dc<n)a.push_back((r+dr)*n+c+dc);
    return a;
}
set<int>flood(const string&b,int n,int p,string allowed){
    set<int>seen={
        p
    };
    vector<int>todo={
        p
    };
    while(!todo.empty()){
        int s=todo.back();
        todo.pop_back();
        for(int q:adjacent(s,n))if(!seen.count(q)&&allowed.find(b[q])!=string::npos){
            seen.insert(q);
            todo.push_back(q);
        }
    }
    return seen;
}
struct Group{
    char color;
    int first;
    set<int>stones,liberties;
};
Group group(const string&b,int n,int p){
    set<int>s=flood(b,n,p,string(1,b[p])),l;
    for(int q:s)for(int t:adjacent(q,n))if(b[t]=='.')l.insert(t);
    return {
        b[p],*s.begin(),s,l
    };
}
vector<Group>groups(const string&b,int n,char color=0){
    vector<Group>r;
    set<int>seen;
    for(int p=0;p<int(b.size());++p)if(b[p]!='.'&&!seen.count(p)&&(!color||b[p]==color)){
        Group g=group(b,n,p);
        seen.insert(g.stones.begin(),g.stones.end());
        r.push_back(g);
    }
    return r;
}
struct Placement{
    string board;
    int captured;
    string reason;
};
Placement placement(const string&b,int n,char c,int p){
    if(b[p]!='.')return {
        b,0,"occupied"
    };
    string next=b;
    next[p]=c;
    int captured=0;
    set<int>seen;
    for(int q:adjacent(p,n))if(next[q]==other(c)&&!seen.count(q)){
        Group g=group(next,n,q);
        seen.insert(g.stones.begin(),g.stones.end());
        if(g.liberties.empty()){
            for(int t:g.stones)next[t]='.';
            captured+=int(g.stones.size());
        }
    }
    return {
        next,captured,group(next,n,p).liberties.empty()?"suicide":""
    };
}
struct Region{
    int first;
    set<int>points;
    string owner;
};
vector<Region>regions(const string&b,int n){
    set<int>seen;
    vector<Region>r;
    for(int p=0;p<int(b.size());++p)if(b[p]=='.'&&!seen.count(p)){
        set<int>points=flood(b,n,p,"."),border;
        seen.insert(points.begin(),points.end());
        for(int q:points)for(int t:adjacent(q,n))if(b[t]!='.')border.insert(b[t]);
        r.push_back({
            p,points,border.size()==1?string(1,char(*border.begin())):"neutral"
        });
    }
    return r;
}
vector<Group>safeGroups(const string&b,int n,char c){
    vector<Group>own=groups(b,n,c);
    vector<set<int>>touch,vital;
    set<int>seen;
    for(int p=0;p<int(b.size());++p)if(b[p]!=c&&!seen.count(p)){
        set<int>area=flood(b,n,p,string(".")+other(c)),empty,t,v;
        seen.insert(area.begin(),area.end());
        for(int q:area)if(b[q]=='.')empty.insert(q);
        for(int i=0;i<int(own.size());++i){
            bool touches=false;
            for(int q:area)for(int a:adjacent(q,n))if(own[i].stones.count(a))touches=true;
            if(touches)t.insert(i);
            if(includes(own[i].liberties.begin(),own[i].liberties.end(),empty.begin(),empty.end()))v.insert(i);
        }
        touch.push_back(t);
        vital.push_back(v);
    }
    set<int>s,t;
    for(int i=0;i<int(own.size());++i)s.insert(i);
    for(int j=0;j<int(touch.size());++j)t.insert(j);
    while(true){
        size_t size=s.size()+t.size();
        set<int>nextS,nextT;
        for(int i:s){
            int count=0;
            for(int j:t)count+=vital[j].count(i);
            if(count>=2)nextS.insert(i);
        }
        s=nextS;
        for(int j:t)if(includes(s.begin(),s.end(),touch[j].begin(),touch[j].end()))nextT.insert(j);
        t=nextT;
        if(size==s.size()+t.size())break;
    }
    vector<Group>r;
    for(int i:s)r.push_back(own[i]);
    return r;
}
pair<string,int>ladder(const string&b,int n,int p){
    char defender=b[p],attacker=other(defender);
    map<tuple<string,int,bool>,pair<bool,int>>memo;
    function<pair<bool,int>(const string&,int,bool)>read=[&](const string&current,int depth,bool defending)->pair<bool,int>{
        if(depth>=40)return {
            defending,-1
        };
        auto key=make_tuple(current,depth,defending);
        if(memo.count(key))return memo[key];
        Group g=group(current,n,p);
        set<int>candidates=g.liberties,seen;
        if(defending)for(int q:g.stones)for(int t:adjacent(q,n))if(current[t]==attacker&&!seen.count(t)){
            Group enemy=group(current,n,t);
            seen.insert(enemy.stones.begin(),enemy.stones.end());
            if(enemy.liberties.size()==1)candidates.insert(enemy.liberties.begin(),enemy.liberties.end());
        }
        for(int q:candidates){
            Placement next=placement(current,n,defending?defender:attacker,q);
            if(!next.reason.empty())continue;
            bool success;
            if(defending){
                size_t m=group(next.board,n,p).liberties.size();
                success=m>=3||(m==2&&!read(next.board,depth+1,false).first);
            }else success=!read(next.board,depth+1,true).first;
            if(success)return memo[key]={
                true,q
            };
        }
        return memo[key]={
            false,-1
        };
    };
    size_t count=group(b,n,p).liberties.size();
    if(count>=3)return {
        "safe",-1
    };
    auto [success,move]=read(b,0,count==1);
    return {
        (count==1?success:!success)?"escapes":"captured",move
    };
}
struct Snapshot{
    string board;
    char turn;
    array<int,2>captured;
    int passes;
    bool over;
};
struct Move{
    char color;
    int point,captured;
    Snapshot before;
};
class Game{
    int n=19,komi2=13,passes=0;
    string board=string(361,'.');
    char turn='B';
    array<int,2>captured={
        0,0
    };
    bool over=false,superko=false;
    vector<int>handicap;
    vector<Move>history;
    vector<string>positions={
        board
    };
    set<int>dead;
    int colorIndex(char c){
        return c=='B'?0:1;
    }
    string name(int p){
        return string(1,columns[p%n])+to_string(p/n+1);
    }
    string sgf(int p){
        return string(1,char(97+p%n))+char(97+n-1-p/n);
    }
    int point(string s){
        if(!regex_match(s,regex("[A-HJ-T]([1-9]|1[0-9])")))return -1;
        size_t c=columns.find(s[0]);
        int r=stoi(s.substr(1));
        return c<size_t(n)&&r<=n?(r-1)*n+int(c):-1;
    }
    void reset(int size,int k){
        n=size;
        komi2=k;
        board=string(n*n,'.');
        turn='B';
        captured={
            0,0
        };
        passes=0;
        over=false;
        handicap.clear();
        history.clear();
        positions={
            board
        };
        dead.clear();
    }
    Placement check(char c,int p){
        Placement r=placement(board,n,c,p);
        if(r.reason.empty()&&positions.size()>=2&&r.board==positions[positions.size()-2])r.reason="ko";
        if(r.reason.empty()&&superko&&find(positions.begin(),positions.end(),r.board)!=positions.end())r.reason="superko";
        return r;
    }
    int move(char c,int p,optional<Placement>checked=nullopt){
        Snapshot before={
            board,turn,captured,passes,over
        };
        int count=0;
        if(p<0){
            ++passes;
            if(passes==2)over=true;
        }else{
            Placement r=checked?*checked:check(c,p);
            board=r.board;
            count=r.captured;
            captured[colorIndex(c)]+=count;
            passes=0;
        }
        turn=other(c);
        history.push_back({
            c,p,count,before
        });
        positions.push_back(board);
        dead.clear();
        return count;
    }
    string clean(){
        string b=board;
        for(int p:dead)b[p]='.';
        return b;
    }
    void show(bool map){
        string b=map?clean():board,chars=b;
        set<int>stars;
        for(int i=0;i<9;++i)if(n==19||i<4||i==8)stars.insert(point(handicapPoints.at(n)[i]));
        if(map)for(const Region&r:regions(b,n))for(int p:r.points)chars[p]=r.owner=="B"?'x':r.owner=="W"?'o':'.';
        for(int p=0;p<n*n;++p)if(b[p]!='.'){
            char c=b[p]=='B'?'X':'O';
            chars[p]=!map&&dead.count(p)?char(tolower(c)):c;
        }else if(!map)chars[p]=stars.count(p)?'+':'.';
        string header="   ";
        for(int c=0;c<n;++c){
            if(c)header+=' ';
            header+=columns[c];
        }
        cout<<header<<'\n';
        for(int r=n;r>=1;--r){
            cout<<setw(2)<<r;
            for(int c=0;c<n;++c)cout<<' '<<chars[(r-1)*n+c];
            cout<<' '<<r<<'\n';
        }
        cout<<header<<'\n';
    }
    void score(string method){
        string b=clean();
        array<int,2>territory={
            0,0
        },total={
            0,0
        };
        for(const Region&r:regions(b,n))if(r.owner!="neutral")territory[colorIndex(r.owner[0])]+=int(r.points.size());
        for(char c:string("BW")){
            int i=colorIndex(c);
            if(method=="AREA"){
                int stones=int(count(b.begin(),b.end(),c));
                total[i]=2*(stones+territory[i])+(c=='W'?komi2:0);
                cout<<c<<" stones "<<stones<<" territory "<<territory[i];
            }else{
                int prisoners=captured[i];
                for(int p:dead)if(board[p]==other(c))++prisoners;
                total[i]=2*(territory[i]+prisoners)+(c=='W'?komi2:0);
                cout<<c<<" territory "<<territory[i]<<" prisoners "<<prisoners;
            }
            if(c=='W')cout<<" komi "<<halfText(komi2);
            cout<<" total "<<halfText(total[i])<<'\n';
        }
        int d=total[0]-total[1];
        cout<<"result "<<(d>0?"B+"+halfText(d):d<0?"W+"+halfText(-d):"Draw")<<'\n';
    }
    public:
    void execute(string line){
        istringstream input(line);
        string c,word;
        input>>c;
        vector<string>a;
        while(input>>word)a.push_back(word);
        auto error=[](string s){
            cout<<"ERROR "<<s<<'\n';
        };
        if(!arity.count(c))return error("unknown command");
        if(a.size()!=size_t(arity.at(c)))return error("bad arguments");
        bool valid=true;
        if(c=="BOARD")valid=(a[0]=="9"||a[0]=="13"||a[0]=="19")&&komi(a[1]).has_value();
        else if(c=="KOMI")valid=komi(a[0]).has_value();
        else if(c=="SUPERKO")valid=a[0]=="ON"||a[0]=="OFF";
        else if(c=="HANDICAP")valid=a[0].size()==1&&a[0][0]>='2'&&a[0][0]<='9';
        else if(c=="PLAY"||c=="PASS"||c=="LEGAL"||c=="EYES"||c=="SAFE")valid=a[0]=="B"||a[0]=="W";
        else if(c=="SCORE")valid=a[0]=="AREA"||a[0]=="TERRITORY";
        if(!valid)return error("bad arguments");
        int p=-1;
        if(c=="PLAY"||c=="GROUP"||c=="LADDER"||c=="DEAD"){
            p=point(a[c=="PLAY"?1:0]);
            if(p<0)return error("bad point");
        }
        vector<pair<char,int>>records;
        if(c=="REPLAY"){
            if(!regex_match(a[0],regex("(;[BW]\\[[a-z]{0,2}\\])+")))return error("bad sequence");
            regex pattern(";([BW])\\[([a-z]*)\\]");
            for(sregex_iterator i(a[0].begin(),a[0].end(),pattern),end;i!=end;++i){
                string s=(*i)[2];
                if(!s.empty()&&(s.size()!=2||s[0]-'a'>=n||s[1]-'a'>=n))return error("bad sequence");
                records.push_back({
                    (*i)[1].str()[0],s.empty()?-1:(n-1-(s[1]-'a'))*n+s[0]-'a'
                });
            }
        }
        if((c=="PLAY"||c=="PASS"||c=="REPLAY")&&over)return error("game over");
        if(c=="BOARD"){
            reset(stoi(a[0]),*komi(a[1]));
            cout<<"board "<<n<<" komi "<<halfText(komi2)<<'\n';
        }
        else if(c=="KOMI"){
            komi2=*komi(a[0]);
            cout<<"komi "<<halfText(komi2)<<'\n';
        }
        else if(c=="SUPERKO"){
            superko=a[0]=="ON";
            cout<<"superko "<<(superko?"on":"off")<<'\n';
        }
        else if(c=="HANDICAP"){
            if(!history.empty()||board.find_first_of("BW")!=string::npos)return error("handicap not allowed");
            int k=stoi(a[0]);
            vector<int>indices;
            if(k==5)indices={
                0,1,2,3,8
            };
            else if(k==7)indices={
                0,1,2,3,4,5,8
            };
            else for(int i=0;i<k;++i)indices.push_back(i);
            for(int i:indices){
                int q=point(handicapPoints.at(n)[i]);
                handicap.push_back(q);
                board[q]='B';
            }
            turn='W';
            positions={
                board
            };
            dead.clear();
            cout<<"handicap "<<k;
            for(int q:handicap)cout<<' '<<name(q);
            cout<<'\n';
        }
        else if(c=="PLAY"){
            char color=a[0][0];
            Placement r=check(color,p);
            string reason=color!=turn?"turn":r.reason;
            if(!reason.empty())cout<<"ILLEGAL "<<color<<' '<<a[1]<<' '<<reason<<'\n';
            else{
                int count=move(color,p,r);
                cout<<color<<' '<<a[1];
                if(count)cout<<" captures "<<count;
                cout<<'\n';
            }
        }
        else if(c=="PASS"){
            char color=a[0][0];
            if(color!=turn)cout<<"ILLEGAL "<<color<<" pass turn\n";
            else{
                move(color,-1);
                cout<<color<<" pass\n";
                if(over)cout<<"game over\n";
            }
        }
        else if(c=="REPLAY"){
            int played=0;
            string stopped;
            for(auto [color,q]:records){
                optional<Placement>r=q<0?nullopt:optional<Placement>(check(color,q));
                string reason=over?"game over":color!=turn?"turn":r?r->reason:"";
                if(!reason.empty()){
                    stopped=" stopped "+string(1,color)+" "+(q<0?"pass":name(q))+" "+reason;
                    break;
                }
                move(color,q,r);
                ++played;
            }
            cout<<"replay "<<played<<" moves"<<stopped<<'\n';
            if(over)cout<<"game over\n";
        }
        else if(c=="UNDO"){
            if(history.empty())return error("nothing to undo");
            Move m=history.back();
            history.pop_back();
            board=m.before.board;
            turn=m.before.turn;
            captured=m.before.captured;
            passes=m.before.passes;
            over=m.before.over;
            positions.pop_back();
            dead.clear();
            cout<<"undo "<<m.color<<' '<<(m.point<0?"pass":name(m.point))<<'\n';
        }
        else if(c=="SHOW"||c=="MAP")show(c=="MAP");
        else if(c=="STATUS"){
            cout<<"size "<<n<<" komi "<<halfText(komi2)<<" handicap "<<handicap.size()<<" superko "<<(superko?"on":"off")<<'\n'<<"moves "<<history.size();
            if(over)cout<<" game over\n";
            else cout<<" next "<<turn<<" passes "<<passes<<'\n';
        }
        else if(c=="CAPTURES")cout<<"captures B "<<captured[0]<<" W "<<captured[1]<<'\n';
        else if(c=="HISTORY"){
            cout<<"history "<<history.size()<<'\n';
            for(size_t i=0;i<history.size();++i){
                const Move&m=history[i];
                cout<<i+1<<' '<<m.color<<' '<<(m.point<0?"pass":name(m.point));
                if(m.captured)cout<<" captures "<<m.captured;
                cout<<'\n';
            }
        }
        else if(c=="MOVES"){
            cout<<"(;GM[1]FF[4]SZ["<<n<<"]KM["<<halfText(komi2)<<']';
            if(!handicap.empty()){
                cout<<"HA["<<handicap.size()<<"]AB";
                for(int q:handicap)cout<<'['<<sgf(q)<<']';
            }
            for(const Move&m:history)cout<<';'<<m.color<<'['<<(m.point<0?"":sgf(m.point))<<']';
            cout<<")\n";
        }
        else if(c=="GROUP"||c=="DEAD"||c=="LADDER"){
            if(board[p]=='.')return error("no stone");
            Group g=group(board,n,p);
            if(c=="GROUP"){
                cout<<"group "<<g.color<<' '<<name(g.first)<<" size "<<g.stones.size()<<" liberties "<<g.liberties.size()<<"\nstones";
                for(int q:g.stones)cout<<' '<<name(q);
                cout<<"\nliberties";
                for(int q:g.liberties)cout<<' '<<name(q);
                cout<<'\n';
            }else if(c=="DEAD"){
                bool alive=dead.count(p);
                for(int q:g.stones)if(alive)dead.erase(q);
                else dead.insert(q);
                cout<<(alive?"alive":"dead")<<' '<<g.color<<' '<<name(g.first)<<" size "<<g.stones.size()<<'\n';
            }else{
                auto [status,q]=ladder(board,n,p);
                cout<<"ladder "<<a[0]<<' '<<status;
                if(q>=0)cout<<' '<<name(q);
                cout<<'\n';
            }
        }
        else if(c=="GROUPS"){
            vector<Group>gs=groups(board,n);
            cout<<"groups "<<gs.size()<<'\n';
            for(const Group&g:gs)cout<<g.color<<' '<<name(g.first)<<" size "<<g.stones.size()<<" liberties "<<g.liberties.size()<<(dead.count(g.first)?" dead":"")<<'\n';
        }
        else if(c=="ATARI"){
            bool found=false;
            for(const Group&g:groups(board,n))if(g.liberties.size()==1){
                found=true;
                cout<<"atari "<<g.color<<' '<<name(g.first)<<" size "<<g.stones.size()<<" at "<<name(*g.liberties.begin())<<'\n';
            }
            if(!found)cout<<"atari none\n";
        }
        else if(c=="LEGAL"){
            vector<pair<string,string>>rejected;
            int count=0;
            for(int q=0;q<n*n;++q)if(board[q]=='.'){
                string reason=check(a[0][0],q).reason;
                if(reason.empty())++count;
                else rejected.push_back({
                    name(q),reason
                });
            }
            cout<<"legal "<<a[0]<<' '<<count<<'\n';
            for(auto [q,r]:rejected)cout<<q<<' '<<r<<'\n';
        }
        else if(c=="EYES"){
            vector<pair<int,bool>>found;
            for(int q=0;q<n*n;++q)if(board[q]=='.'){
                vector<int>ns=adjacent(q,n);
                if(all_of(ns.begin(),ns.end(),[&](int t){
                    return board[t]==a[0][0];
                })){
                    int enemies=0;
                    for(int t:adjacent(q,n,true))enemies+=board[t]==other(a[0][0]);
                    found.push_back({
                        q,enemies<=(ns.size()==4?1:0)
                    });
                }
            }
            cout<<"eyes "<<a[0]<<' '<<found.size()<<'\n';
            for(auto [q,real]:found)cout<<name(q)<<' '<<(real?"real":"false")<<'\n';
        }
        else if(c=="SAFE"){
            vector<Group>gs=safeGroups(board,n,a[0][0]);
            cout<<"safe "<<a[0]<<' '<<gs.size()<<'\n';
            for(const Group&g:gs)cout<<name(g.first)<<" size "<<g.stones.size()<<'\n';
        }
        else if(c=="REGIONS"){
            vector<Region>rs=regions(clean(),n);
            cout<<"regions "<<rs.size()<<'\n';
            for(const Region&r:rs)cout<<name(r.first)<<" size "<<r.points.size()<<' '<<r.owner<<'\n';
        }
        else if(c=="SCORE")score(a[0]);
    }
};
int main(){
    int n;
    cin>>n;
    string line;
    getline(cin,line);
    Game game;
    while(n--&&getline(cin,line))game.execute(line);
}
