#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using namespace std;
const array<int,64> weights={100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100};
const set<string> transforms={"rot90","rot180","rot270","mirror","flip","diag","anti"};
const set<string> zero={"NEW","DUMP","SHOW","SCORE","LEGAL","HISTORY","SHEET","STATS","EVAL","STABLE","SOLVE"};
const set<string> numeric={"UNDO","REDO","HINT","PV","AI","ANALYZE","RANDOM","PERFT","DIVIDE"};
const set<string> active={"FLIPS","MOVE","PLAY","HINT","PV","AI","SOLVE","AUTOPLAY","RANDOM","MC","DIVIDE"};
char other(char s){return s=='B'?'W':'B';}
string name(int p){return string(1,'a'+p%8)+to_string(p/8+1);}
int square(const string& s){return (s[1]-'1')*8+s[0]-'a';}
bool inside(int r,int c){return r>=0&&r<8&&c>=0&&c<8;}
string initial(){string b(64,'.');b[27]=b[36]='W';b[28]=b[35]='B';return b;}
vector<int> flips(const string& b,char s,int p){vector<int> out;if(b[p]!='.')return out;int row=p/8,col=p%8;for(int dr=-1;dr<=1;++dr)for(int dc=-1;dc<=1;++dc){if(!dr&&!dc)continue;int r=row+dr,c=col+dc;vector<int> line;while(inside(r,c)&&b[8*r+c]==other(s)){line.push_back(8*r+c);r+=dr;c+=dc;}if(!line.empty()&&inside(r,c)&&b[8*r+c]==s)out.insert(out.end(),line.begin(),line.end());}sort(out.begin(),out.end());return out;}
vector<int> legal(const string& b,char s){vector<int> ms;for(int p=0;p<64;++p)if(b[p]=='.'&&!flips(b,s,p).empty())ms.push_back(p);return ms;}
string place(string b,char s,int p){for(int q:flips(b,s,p))b[q]=s;b[p]=s;return b;}
int countDisc(const string& b,char s){return count(b.begin(),b.end(),s);}
bool terminal(const string& b){return legal(b,'B').empty()&&legal(b,'W').empty();}
string gameOver(const string& b){int x=countDisc(b,'B'),y=countDisc(b,'W');return "game over B "+to_string(x)+" W "+to_string(y)+" "+(x>y?"winner B":x<y?"winner W":"draw");}
array<int,4> evaluate(const string& b,char s){int w=0;for(int i=0;i<64;++i)w+=b[i]==s?weights[i]:b[i]==other(s)?-weights[i]:0;int own=legal(b,s).size(),enemy=legal(b,other(s)).size();return {w+10*(own-enemy),w,own,enemy};}
map<tuple<string,char,int>,int> searchCache,perftCache;
int search(const string& b,char s,int d){auto key=make_tuple(b,s,d);auto hit=searchCache.find(key);if(hit!=searchCache.end())return hit->second;vector<int> ms=legal(b,s);char o=other(s);int v;if(ms.empty()&&legal(b,o).empty())v=(d<0?1:1000)*(countDisc(b,s)-countDisc(b,o));else if(d==0)v=evaluate(b,s)[0];else if(ms.empty())v=-search(b,o,d<0?-1:d-1);else{v=-1000000;for(int p:ms)v=max(v,-search(place(b,s,p),o,d<0?-1:d-1));}if(searchCache.size()>300000)searchCache.clear();searchCache[key]=v;return v;}
using Ranking=pair<int,int>;
vector<Ranking> ranked(const string& b,char s,int d){vector<Ranking> rows;for(int p:legal(b,s))rows.emplace_back(-search(place(b,s,p),other(s),d<0?-1:d-1),p);sort(rows.begin(),rows.end(),[](Ranking a,Ranking b){return a.first!=b.first?a.first>b.first:a.second<b.second;});return rows;}
pair<vector<string>,string> variation(string b,char s,int d){vector<string> steps;while(d!=0&&!terminal(b)){vector<Ranking> ms=ranked(b,s,d);if(ms.empty())steps.push_back("pass");else{int p=ms[0].second;steps.push_back(name(p));b=place(b,s,p);}s=other(s);if(d>0)--d;}return {steps,b};}
int perft(const string& b,char s,int d){if(!d)return 1;auto key=make_tuple(b,s,d);auto hit=perftCache.find(key);if(hit!=perftCache.end())return hit->second;vector<int> ms=legal(b,s);int n=0;if(ms.empty())n=legal(b,other(s)).empty()?1:perft(b,other(s),d-1);else for(int p:ms)n+=perft(place(b,s,p),other(s),d-1);if(perftCache.size()>200000)perftCache.clear();perftCache[key]=n;return n;}
pair<int,int> stable(const string& b){array<bool,64> set{};array<pair<int,int>,4> axes={{{0,1},{1,0},{1,1},{1,-1}}};while(true){vector<int> found;for(int p=0;p<64;++p){if(b[p]=='.'||set[p])continue;bool ok=true;for(auto [dr,dc]:axes){bool full=true,anchor=false;for(int sign:{-1,1}){int r=p/8+dr*sign,c=p%8+dc*sign;if(!inside(r,c)||(set[8*r+c]&&b[8*r+c]==b[p]))anchor=true;while(inside(r,c)){if(b[8*r+c]=='.')full=false;r+=dr*sign;c+=dc*sign;}}if(!full&&!anchor){ok=false;break;}}if(ok)found.push_back(p);}if(found.empty())break;for(int p:found)set[p]=true;}int black=0,white=0;for(int i=0;i<64;++i)if(set[i]){if(b[i]=='B')++black;else ++white;}return {black,white};}
int transform(int p,const string& op){int r=p/8,c=p%8;if(op=="rot90")return 8*c+7-r;if(op=="rot180")return 63-p;if(op=="rot270")return 8*(7-c)+r;if(op=="mirror")return 8*r+7-c;if(op=="flip")return 8*(7-r)+c;if(op=="diag")return 8*c+r;return 8*(7-c)+7-r;}
string transformBoard(const string& b,const string& op){string a(64,'.');for(int p=0;p<64;++p)a[transform(p,op)]=b[p];return a;}
struct Random{int64_t value;int64_t draw(){value=value*48271%2147483647;return value;}};
string randomGame(string b,char s,Random& rng){while(true){vector<int> ms=legal(b,s);if(!ms.empty())b=place(b,s,ms[rng.draw()%ms.size()]);else if(legal(b,other(s)).empty())return b;s=other(s);}}
string average(int f,int n){int v=100*f/n;return to_string(v/100)+"."+(v%100<10?"0":"")+to_string(v%100);}
string joined(const vector<string>& xs){string s;for(const string& x:xs){if(!s.empty())s+=' ';s+=x;}return s;}
struct Position{string board;char side;bool over;};
struct Move{char side;int square,count;bool passed;Position before,after;};
class Othello{
public:
    string board;char side;bool over;vector<Move> history,redo;
    Othello(){reset();}
    void reset(){board=initial();side='B';over=false;history.clear();redo.clear();}
    void emit(const string& s){cout<<s<<'\n';}
    Position snapshot()const{return {board,side,over};}
    void restore(const Position& p){board=p.board;side=p.side;over=p.over;}
    string status()const{return over?gameOver(board):string(1,side)+" to move";}
    bool adjust(bool quiet=false){if(!legal(board,side).empty())return false;if(!legal(board,other(side)).empty()){if(!quiet)emit(string(1,side)+" passes");side=other(side);return true;}over=true;if(!quiet)emit(gameOver(board));return false;}
    bool move(int p,bool quiet=false,int value=1000001){Position before=snapshot();char s=side;int k=flips(board,s,p).size();board=place(board,s,p);if(!quiet)emit(string(1,s)+" "+name(p)+" flips "+to_string(k)+(value==1000001?"":" value "+to_string(value)));side=other(s);bool passed=adjust(quiet);history.push_back({s,p,k,passed,before,snapshot()});redo.clear();return passed;}
    string reason(int p)const{return over?"game over":board[p]!='.'?"occupied":flips(board,side,p).empty()?"no flips":"";}
    void record(const string& text){Othello e;vector<int> ps;int passes=0;for(size_t i=0;i<text.size();i+=2){int p=square(text.substr(i,2));string why=e.reason(p);if(!why.empty()){emit("ILLEGAL move "+to_string(i/2+1)+" "+name(p)+" "+why);return;}ps.push_back(p);passes+=e.move(p,true);}restore(e.snapshot());history=e.history;redo.clear();string first=name(ps[0]),op=first=="e6"?"diag":first=="d3"?"anti":first=="c4"?"rot180":"",normal;for(int p:ps)normal+=name(op.empty()?p:transform(p,op));emit("record "+to_string(ps.size())+" moves "+to_string(passes)+" passes");emit("normal "+normal);emit(status());}
    void sheet(){string b=history.empty()?board:history[0].before.board;vector<string> fields;for(char c:b)fields.emplace_back(1,c);for(size_t i=0;i<history.size();++i)fields[history[i].square]=to_string(i+1);emit("   a  b  c  d  e  f  g  h");for(int r=0;r<8;++r){string line=to_string(r+1);for(int c=0;c<8;++c){string s=fields[8*r+c];line+=string(3-s.size(),' ')+s;}emit(line);}}
    void stats(){int total=0,passes=0;for(const Move& r:history){total+=r.count;passes+=r.passed;}if(history.empty())emit("moves 0");else emit("moves "+to_string(history.size())+" flips "+to_string(total)+" avg "+average(total,history.size())+" passes "+to_string(passes));for(char s:{'B','W'}){int n=0,sum=0,max=-1,p=-1,corners=0;for(const Move& r:history)if(r.side==s){++n;sum+=r.count;if(r.count>max){max=r.count;p=r.square;}corners+=r.square==0||r.square==7||r.square==56||r.square==63;}if(!n)emit(string(1,s)+" moves 0");else emit(string(1,s)+" moves "+to_string(n)+" flips "+to_string(sum)+" avg "+average(sum,n)+" max "+to_string(max)+" "+name(p)+" corners "+to_string(corners));}}
    void autoPlay(int black,int white,int64_t seed=0){Random rng{seed};string text;int n=0,passes=0;while(!over){vector<int> ms=legal(board,side);int p=seed?ms[rng.draw()%ms.size()]:ranked(board,side,side=='B'?black:white)[0].second;text+=name(p);++n;passes+=move(p,true);}emit(string(seed?"random":"autoplay")+" "+to_string(n)+" moves "+to_string(passes)+" passes");emit("moves "+text);emit(gameOver(board));}
    void monteCarlo(int k,int64_t seed){Random rng{seed};int best=-1,bp=-1;for(int p:legal(board,side)){int w=0,d=0,l=0;string start=place(board,side,p);for(int i=0;i<k;++i){string end=randomGame(start,other(side),rng);int diff=countDisc(end,side)-countDisc(end,other(side));if(diff>0)++w;else if(diff<0)++l;else ++d;}emit(name(p)+" "+to_string(w)+" "+to_string(d)+" "+to_string(l));if(2*w+d>best){best=2*w+d;bp=p;}}emit("best "+name(bp)+" "+to_string(best));}
    void execute(const string& text){istringstream in(text);string cmd,x;in>>cmd;vector<string> a;while(in>>x)a.push_back(x);string error;bool known=zero.count(cmd)||numeric.count(cmd)||cmd=="LOAD"||cmd=="TRANSFORM"||cmd=="AUTOPLAY"||cmd=="MC"||cmd=="FLIPS"||cmd=="MOVE"||cmd=="PLAY"||cmd=="RECORD";
        if(!known)error="unknown command";
        else if(cmd=="LOAD"){if(a.size()!=2||!regex_match(a[0],regex("[.BW]{64}"))||(a[1]!="B"&&a[1]!="W"))error="bad board";}
        else if(cmd=="MOVE"||cmd=="FLIPS"){if(a.size()!=1)error="bad arguments";else if(!regex_match(a[0],regex("[a-h][1-8]")))error="bad square";}
        else if(cmd=="PLAY"||cmd=="RECORD"){if(a.size()!=1)error="bad arguments";else if(a[0].size()>120||!regex_match(a[0],regex("([a-h][1-8])+")))error="bad record";}
        else if(zero.count(cmd)){if(!a.empty())error="bad arguments";}
        else if(cmd=="TRANSFORM"){if(a.size()!=1||!transforms.count(a[0]))error="bad arguments";}
        else{size_t expected=cmd=="AUTOPLAY"||cmd=="MC"?2:1;bool valid=a.size()==expected;vector<int64_t> nums;for(const string& s:a){if(!regex_match(s,regex("[0-9]+")))valid=false;else nums.push_back(stoll(s));}if(valid){int64_t n=nums[0];if(cmd=="AUTOPLAY")valid=n>=1&&n<=4&&nums[1]>=1&&nums[1]<=4;else if(cmd=="HINT"||cmd=="PV"||cmd=="AI"||cmd=="ANALYZE")valid=n>=1&&n<=4;else if(cmd=="PERFT"||cmd=="DIVIDE")valid=n>=1&&n<=8;else if(cmd=="MC")valid=n>=1&&n<=100&&nums[1]>=1&&nums[1]<=2147483646;else if(cmd=="RANDOM")valid=n>=1&&n<=2147483646;else valid=n>=1;}if(!valid)error="bad arguments";}
        if(!error.empty()){emit("ERROR "+error);return;}if(over&&active.count(cmd)){emit("ERROR game over");return;}int n=!a.empty()&&regex_match(a[0],regex("[0-9]+"))?stoi(a[0]):0;
        if(cmd=="NEW"){reset();emit("OK");}
        else if(cmd=="LOAD"){board=a[0];side=a[1][0];over=false;history.clear();redo.clear();emit("OK");adjust();}
        else if(cmd=="DUMP")emit("board "+board+" "+side);
        else if(cmd=="SHOW"){emit("  a b c d e f g h");vector<int> ms=over?vector<int>{}:legal(board,side);for(int r=0;r<8;++r){string row=to_string(r+1);for(int c=0;c<8;++c){int p=8*r+c;row+=" ";row+=find(ms.begin(),ms.end(),p)!=ms.end()?'*':board[p];}emit(row);}emit(status());}
        else if(cmd=="SCORE")emit("score B "+to_string(countDisc(board,'B'))+" W "+to_string(countDisc(board,'W'))+" empty "+to_string(countDisc(board,'.')));
        else if(cmd=="LEGAL"){vector<int> ms=over?vector<int>{}:legal(board,side);string out="legal "+to_string(ms.size());for(int p:ms)out+=" "+name(p);emit(out);}
        else if(cmd=="MOVE"||cmd=="FLIPS"){int p=square(a[0]);string why=reason(p);if(!why.empty())emit("ILLEGAL "+why);else if(cmd=="MOVE")move(p);else{vector<int> f=flips(board,side,p);string out="flips "+a[0]+" "+to_string(f.size());for(int q:f)out+=" "+name(q);emit(out);}}
        else if(cmd=="PLAY"){for(size_t i=0;i<a[0].size();i+=2){int p=square(a[0].substr(i,2));string why=reason(p);if(!why.empty()){emit("ILLEGAL move "+to_string(i/2+1)+" "+name(p)+" "+why);break;}move(p);}}
        else if(cmd=="RECORD")record(a[0]);
        else if(cmd=="UNDO"){if(size_t(n)>history.size())emit("ERROR cannot undo");else{auto first=history.end()-n;restore(first->before);redo.insert(redo.begin(),first,history.end());history.erase(first,history.end());emit(status());}}
        else if(cmd=="REDO"){if(size_t(n)>redo.size())emit("ERROR cannot redo");else{history.insert(history.end(),redo.begin(),redo.begin()+n);restore(redo[n-1].after);redo.erase(redo.begin(),redo.begin()+n);emit(status());}}
        else if(cmd=="HISTORY"){emit("history "+to_string(history.size()));for(size_t i=0;i<history.size();++i){const Move& r=history[i];emit(to_string(i+1)+" "+r.side+" "+name(r.square)+" "+to_string(r.count)+(r.passed?" pass":""));}}
        else if(cmd=="SHEET")sheet();else if(cmd=="STATS")stats();
        else if(cmd=="TRANSFORM"){board=transformBoard(board,a[0]);for(vector<Move>* rows:{&history,&redo})for(Move& r:*rows){r.square=transform(r.square,a[0]);r.before.board=transformBoard(r.before.board,a[0]);r.after.board=transformBoard(r.after.board,a[0]);}emit("OK");}
        else if(cmd=="EVAL"){auto e=evaluate(board,side);emit("eval "+to_string(e[0])+" weights "+to_string(e[1])+" mobility "+to_string(e[2])+" "+to_string(e[3]));}
        else if(cmd=="STABLE"){auto [b,w]=stable(board);emit("stable B "+to_string(b)+" W "+to_string(w));}
        else if(cmd=="HINT")for(auto [v,p]:ranked(board,side,n))emit(name(p)+" "+to_string(v));
        else if(cmd=="PV"){auto pv=variation(board,side,n);emit("pv "+to_string(search(board,side,n))+(pv.first.empty()?"":" "+joined(pv.first)));}
        else if(cmd=="AI"){auto [v,p]=ranked(board,side,n)[0];move(p,false,v);}
        else if(cmd=="ANALYZE"){map<char,int> loss={{'B',0},{'W',0}};for(size_t i=0;i<history.size();++i){const Move& r=history[i];vector<Ranking> rows=ranked(r.before.board,r.side,n);auto [best,bp]=rows[0];int v=find_if(rows.begin(),rows.end(),[&](Ranking row){return row.second==r.square;})->first;loss[r.side]+=best-v;emit(to_string(i+1)+" "+r.side+" "+name(r.square)+" "+to_string(v)+" best "+name(bp)+" "+to_string(best));}emit("loss B "+to_string(loss['B'])+" W "+to_string(loss['W']));}
        else if(cmd=="SOLVE"){if(countDisc(board,'.')>=9)emit("ERROR too many empties");else{for(auto [v,p]:ranked(board,side,-1))emit(name(p)+" "+to_string(v));auto pv=variation(board,side,-1);emit("line "+joined(pv.first));emit("final B "+to_string(countDisc(pv.second,'B'))+" W "+to_string(countDisc(pv.second,'W')));}}
        else if(cmd=="AUTOPLAY")autoPlay(n,stoi(a[1]));else if(cmd=="RANDOM")autoPlay(0,0,n);else if(cmd=="MC")monteCarlo(n,stoll(a[1]));
        else if(cmd=="PERFT")emit("perft "+to_string(n)+" "+to_string(perft(board,side,n)));
        else if(cmd=="DIVIDE"){int total=0;for(int p:legal(board,side)){int v=perft(place(board,side,p),other(side),n-1);emit(name(p)+" "+to_string(v));total+=v;}emit("total "+to_string(total));}
    }
};
int main(){int n;cin>>n;string line;getline(cin,line);Othello engine;while(n--&&getline(cin,line))engine.execute(line);}
