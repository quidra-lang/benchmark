#include <algorithm>
#include <iostream>
#include <map>
#include <memory>
#include <queue>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <vector>
using namespace std;
const vector<string> TYPES={"AND","OR","NAND","NOR","XOR","XNOR","NOT","BUF","MUX2","DFF"};
const map<string,int> COUNTS={{"BUILD",1},{"RESET",0},{"SET",3},{"APPLY",2},{"PULSE",3},{"CLOCK",4},{"RUN",1},{"WATCH",1},{"UNWATCH",1},{"SHOW",0},{"CHECK",2},{"PROBE",1},{"WAVE",2},{"HISTORY",1},{"ACTIVITY",1},{"STATUS",0},{"MODULES",0},{"NETLIST",1},{"HIERARCHY",1},{"STATS",1},{"TRUTHTABLE",1},{"EQUIV",2},{"FAULTS",1},{"CRITICAL",1},{"PERIOD",1}};
const set<string> SIM={"RESET","SET","APPLY","PULSE","CLOCK","RUN","WATCH","UNWATCH","SHOW","CHECK","PROBE","WAVE","HISTORY","ACTIVITY","STATUS"};
void fail(const string&s){throw runtime_error(s);}
void emit(const string&s){cout<<s<<'\n';}
bool has(const vector<string>&a,const string&s){return find(a.begin(),a.end(),s)!=a.end();}
vector<string> words(const string&s){istringstream in(s);string x;vector<string>a;while(in>>x)a.push_back(x);return a;}
string join(const vector<string>&a,const string&sep=" "){string s;for(size_t i=0;i<a.size();i++){if(i)s+=sep;s+=a[i];}return s;}
bool nameOK(const string&s){static const regex r("[a-z][a-z0-9_]{0,15}");return regex_match(s,r);}
bool numberOK(const string&s){static const regex r("0|[1-9][0-9]{0,8}");return regex_match(s,r);}
int number(const string&s,bool positive=false){if(!numberOK(s)||(positive&&s=="0"))fail("bad number "+s);return stoi(s);}
char value(const string&s){if(s!="0"&&s!="1"&&s!="X")fail("bad value "+s);return s[0];}
string bits(int r,int n){string b;for(int i=0;i<n;i++)b+=char('0'+((r>>(n-1-i))&1));return b;}
char logic(const string&k,const vector<char>&a){
    auto contains=[&](char c){return find(a.begin(),a.end(),c)!=a.end();};char y=a[0];
    if(k=="AND"||k=="NAND")y=contains('0')?'0':contains('X')?'X':'1';
    else if(k=="OR"||k=="NOR")y=contains('1')?'1':contains('X')?'X':'0';
    else if(k=="XOR"||k=="XNOR")y=contains('X')?'X':char('0'+count(a.begin(),a.end(),'1')%2);
    else if(k=="MUX2")y=a[0]=='X'?(a[1]==a[2]?a[1]:'X'):a[a[0]=='0'?1:2];
    if(k=="NAND"||k=="NOR"||k=="XNOR"||k=="NOT")y=y=='0'?'1':y=='1'?'0':'X';return y;
}
struct Gate {string name,kind;vector<string>inputs;string output;int delay=0;};
struct Module;
struct Item {bool instance=false;Gate gate;string name;shared_ptr<Module> module;vector<pair<string,string>>connections;};
struct Module {string name;vector<string>inputs,outputs;vector<Item>body;};
struct Circuit {
    string name;vector<string>inputs,outputs,signals;vector<Gate>gates;map<string,int>driver;map<string,vector<int>>readers;vector<int>flops,order;bool loop;
    void expand(const Module&m,const string&p,const map<string,string>&ports){
        auto actual=[&](const string&s){auto it=ports.find(s);return it==ports.end()?p+s:it->second;};
        for(const Item&x:m.body)if(!x.instance){Gate g=x.gate;g.name=p+g.name;for(string&s:g.inputs)s=actual(s);g.output=actual(g.output);gates.push_back(g);}else{map<string,string>mapping;for(const auto&[port,s]:x.connections)mapping[port]=actual(s);expand(*x.module,p+x.name+".",mapping);}
    }
    explicit Circuit(const Module&m):name(m.name),inputs(m.inputs),outputs(m.outputs){
        expand(m,"",{});signals=inputs;for(size_t i=0;i<gates.size();i++){const Gate&g=gates[i];signals.push_back(g.output);driver[g.output]=int(i);if(g.kind=="DFF")flops.push_back(int(i));for(const string&s:set<string>(g.inputs.begin(),g.inputs.end()))readers[s].push_back(int(i));}for(const string&s:signals)readers.try_emplace(s);
        vector<int>waiting(gates.size()),ready;int needed=0;
        for(size_t i=0;i<gates.size();i++){const Gate&g=gates[i];if(g.kind=="DFF")continue;needed++;for(const string&s:set<string>(g.inputs.begin(),g.inputs.end()))if(driver.count(s)&&gates[driver.at(s)].kind!="DFF")waiting[i]++;if(!waiting[i])ready.push_back(int(i));}
        while(!ready.empty()){int i=ready.back();ready.pop_back();order.push_back(i);for(int r:readers[gates[i].output])if(gates[r].kind!="DFF"&&!--waiting[r])ready.push_back(r);}loop=int(order.size())!=needed;
    }
    void combinational()const{if(!flops.empty())fail(name+" is not combinational");if(loop)fail(name+" has a combinational loop");if(inputs.size()>8)fail("too many inputs "+to_string(inputs.size()));}
    string evaluate(const string&b,const string&stuck="",char v='X')const{
        map<string,char>values;for(size_t i=0;i<inputs.size();i++)values[inputs[i]]=inputs[i]==stuck?v:b[i];
        for(int i:order){const Gate&g=gates[i];vector<char>a;for(const string&s:g.inputs)a.push_back(values.at(s));values[g.output]=g.output==stuck?v:logic(g.kind,a);}string result;for(const string&s:outputs)result+=values.at(s);return result;
    }
    tuple<map<string,int>,map<string,int>,map<string,string>>arrivals(bool period)const{
        map<string,int>late,early;map<string,string>prev;if(period){for(int i:flops){const Gate&g=gates[i];late[g.output]=early[g.output]=g.delay;}}else for(const string&s:inputs)late[s]=early[s]=0;
        for(int i:order){const Gate&g=gates[i];string best;int minimum=0;for(const string&s:g.inputs)if(late.count(s)){if(best.empty()){best=s;minimum=early[s];}else if(late[s]>late[best])best=s;minimum=min(minimum,early[s]);}if(!best.empty()){late[g.output]=late[best]+g.delay;early[g.output]=minimum+g.delay;prev[g.output]=best;}}return {late,early,prev};
    }
};
struct Event {int time;long long sequence;string signal;char value;};
struct Later {bool operator()(const Event&a,const Event&b)const{return tie(a.time,a.sequence)>tie(b.time,b.sequence);}};
struct Simulation {
    shared_ptr<Circuit>c;map<string,char>values;vector<string>watch;map<string,vector<pair<int,char>>>history;priority_queue<Event,vector<Event>,Later>queue;int time=0;long long sequence=0,processed=0;bool halted=false;
    explicit Simulation(shared_ptr<Circuit>circuit):c(circuit){reset();}
    void reset(){values.clear();history.clear();for(const string&s:c->signals){values[s]='X';history[s]={};}queue={};time=0;sequence=processed=0;halted=false;}
    void schedule(int t,const string&s,char v){queue.push({t,sequence++,s,v});}
    vector<string>describe(const vector<string>&a)const{vector<string>b;for(const string&s:a)b.push_back(s+"="+values.at(s));return b;}
    void run(int end){
        int total=0,glitches=0;
        while(!queue.empty()&&queue.top().time<end){int t=queue.top().time,count=0;map<string,char>original;
            while(!queue.empty()&&queue.top().time==t){if(count==1000){emit("halted: oscillation at time "+to_string(t));queue={};time=t;halted=true;return;}Event e=queue.top();queue.pop();count++;processed++;char old=values[e.signal];if(old==e.value)continue;original.try_emplace(e.signal,old);values[e.signal]=e.value;
                for(int i:c->readers[e.signal]){const Gate&g=c->gates[i];if(g.kind!="DFF"){vector<char>a;for(const string&s:g.inputs)a.push_back(values[s]);schedule(t+g.delay,g.output,logic(g.kind,a));}else if(e.signal==g.inputs[0]&&old=='0'&&e.value=='1')schedule(t+g.delay,g.output,values[g.inputs[1]]);}}
            total+=count;for(const auto&[s,v]:original)if(values[s]==v)glitches++;else history[s].push_back({t,values[s]});for(const string&s:watch)if(original.count(s)&&values[s]!=original[s])emit(to_string(t)+" "+s+" "+values[s]);
        }time=end;emit("run "+to_string(end)+" events "+to_string(total)+" glitches "+to_string(glitches)+" pending "+to_string(queue.size()));
    }
};
struct Simulator {
    map<string,shared_ptr<Module>>modules;vector<shared_ptr<Module>>moduleOrder;unique_ptr<Simulation>sim;
    shared_ptr<Module>lookup(const string&s)const{auto it=modules.find(s);if(it==modules.end())fail("unknown module "+s);return it->second;}
    void signal(const string&s)const{if(!sim->values.count(s))fail("unknown signal "+s);}
    void input(const string&s)const{if(!has(sim->c->inputs,s))fail("not an input "+s);}
    int time(const string&w)const{int t=number(w);if(t<sim->time)fail("time "+to_string(t)+" is in the past");return t;}
    void define(int header,const vector<string>&lines){int line=header;try{
        vector<string>w=words(lines[0]);if(w.size()<5||w[2]!="IN"||count(w.begin()+3,w.end(),"OUT")!=1||w.back()=="OUT")fail("bad module header");string name=w[1];if(!regex_match(name,regex("[A-Z][A-Z0-9_]{0,15}")))fail("bad module name "+name);if(modules.count(name))fail("duplicate module "+name);
        auto split=find(w.begin()+3,w.end(),"OUT");auto m=make_shared<Module>();m->name=name;m->inputs.assign(w.begin()+3,split);m->outputs.assign(split+1,w.end());set<string>seen;vector<string>ports=m->inputs;ports.insert(ports.end(),m->outputs.begin(),m->outputs.end());for(const string&p:ports){if(!nameOK(p))fail("bad name "+p);if(!seen.insert(p).second)fail("duplicate port "+p);}
        set<string>driven(m->inputs.begin(),m->inputs.end()),used;vector<pair<int,string>>reads;int gates=0;
        for(size_t i=1;i<lines.size();i++){line=header+int(i);vector<string>a=words(lines[i]);string kind=a[0];Item item;
            if(has(TYPES,kind)){
                if(a.size()<5||a[a.size()-3]!="->"||count(a.begin(),a.end(),"->")!=1)fail("bad gate syntax");string n=a[1];if(!nameOK(n))fail("bad name "+n);vector<string>ins(a.begin()+2,a.end()-3);string output=a[a.size()-2],delay=a.back();int low=(kind=="NOT"||kind=="BUF")?1:kind=="MUX2"?3:2,high=find(TYPES.begin(),TYPES.end(),kind)-TYPES.begin()<6?8:low;
                if(int(ins.size())<low||int(ins.size())>high)fail("bad input count "+to_string(ins.size())+" for "+kind);vector<string>names=ins;names.push_back(output);for(const string&s:names)if(!nameOK(s))fail("bad name "+s);if(!numberOK(delay)||stoi(delay)>1000)fail("bad delay "+delay);if(used.count(n))fail("duplicate name "+n);if(driven.count(output))fail("multiple drivers for "+output);
                used.insert(n);driven.insert(output);item.gate={n,kind,ins,output,stoi(delay)};gates++;for(const string&s:ins)reads.push_back({line,s});
            }else if(kind=="INST"){
                if(a.size()<3)fail("bad instance syntax");string n=a[1];if(!nameOK(n))fail("bad name "+n);auto child=lookup(a[2]);set<string>connected;
                for(size_t j=3;j<a.size();j++){const string&word=a[j];size_t pos=word.find('=');if(pos==string::npos||pos==0||pos+1==word.size()||word.find('=',pos+1)!=string::npos)fail("bad connection "+word);string p=word.substr(0,pos),s=word.substr(pos+1);if(!has(child->inputs,p)&&!has(child->outputs,p))fail("unknown port "+p);if(connected.count(p))fail("duplicate connection "+p);if(!nameOK(s))fail("bad name "+s);connected.insert(p);item.connections.push_back({p,s});}
                for(const string&p:child->inputs)if(!connected.count(p))fail("unconnected input "+p);if(used.count(n))fail("duplicate name "+n);for(const auto&[p,s]:item.connections)if(has(child->outputs,p)){if(driven.count(s))fail("multiple drivers for "+s);driven.insert(s);}used.insert(n);item.instance=true;item.name=n;item.module=child;for(const auto&[p,s]:item.connections)if(has(child->inputs,p))reads.push_back({line,s});
            }else fail("unknown statement "+kind);m->body.push_back(item);
        }
        for(const string&s:m->outputs)reads.push_back({header,s});for(const auto&[n,s]:reads)if(!driven.count(s)){line=n;fail("undriven signal "+s);}modules[name]=m;moduleOrder.push_back(m);emit("defined "+name+" inputs "+to_string(m->inputs.size())+" outputs "+to_string(m->outputs.size())+" gates "+to_string(gates)+" instances "+to_string(m->body.size()-gates));
    }catch(const runtime_error&e){emit("error: line "+to_string(line)+": "+e.what());}}
    void hierarchy(const Module&m,int depth)const{for(const Item&x:m.body)if(x.instance){emit(string(2*depth,' ')+x.name+" "+x.module->name);hierarchy(*x.module,depth+1);}}
    void execute(int line,const vector<string>&w){try{
        string cmd=w[0];vector<string>a(w.begin()+1,w.end());if(!COUNTS.count(cmd))fail("unknown command "+cmd);int n=COUNTS.at(cmd);if(int(a.size())<n||((cmd!="WATCH"&&cmd!="UNWATCH"&&cmd!="SHOW")&&int(a.size())!=n))fail("wrong argument count");if(SIM.count(cmd)&&!sim)fail("no circuit");if((cmd=="SET"||cmd=="APPLY"||cmd=="PULSE"||cmd=="CLOCK"||cmd=="RUN")&&sim->halted)fail("simulation halted");
        if(cmd=="MODULES"){emit("modules "+to_string(modules.size()));for(const auto&m:moduleOrder)emit(m->name+" inputs "+to_string(m->inputs.size())+" outputs "+to_string(m->outputs.size())+" gates "+to_string(Circuit(*m).gates.size()));return;}
        if(has(words("BUILD NETLIST HIERARCHY STATS TRUTHTABLE EQUIV FAULTS CRITICAL PERIOD"),cmd)){
            auto m=lookup(a[0]);shared_ptr<Module>m2;if(cmd=="EQUIV")m2=lookup(a[1]);auto cp=make_shared<Circuit>(*m);const Circuit&c=*cp;
            if(cmd=="BUILD"){sim=make_unique<Simulation>(cp);emit("built "+c.name+" signals "+to_string(c.signals.size())+" gates "+to_string(c.gates.size()));}
            else if(cmd=="NETLIST"){emit("netlist "+c.name+" gates "+to_string(c.gates.size())+" signals "+to_string(c.signals.size()));for(const Gate&g:c.gates)emit(g.name+" "+g.kind+" "+join(g.inputs)+" -> "+g.output+" "+to_string(g.delay));}
            else if(cmd=="HIERARCHY"){emit(c.name);hierarchy(*m,1);}
            else if(cmd=="STATS"){
                map<string,int>levels;int depth=0;for(int i:c.order){const Gate&g=c.gates[i];int v=0;for(const string&s:g.inputs)v=max(v,levels[s]);levels[g.output]=v+1;depth=max(depth,v+1);}emit("stats "+c.name+" gates "+to_string(c.gates.size())+" signals "+to_string(c.signals.size())+" depth "+(c.loop?"-":to_string(depth)));vector<string>text={"types"};for(const string&t:TYPES){int n=0;for(const Gate&g:c.gates)n+=g.kind==t;if(n){text.push_back(t);text.push_back(to_string(n));}}emit(join(text));string best=c.signals[0];for(const string&s:c.signals)if(c.readers.at(s).size()>c.readers.at(best).size())best=s;emit("max fanout "+best+" "+to_string(c.readers.at(best).size()));
            }else if(cmd=="CRITICAL"||cmd=="PERIOD"){
                bool period=cmd=="PERIOD";if(period&&c.flops.empty())fail(c.name+" has no flip-flops");if(c.loop)fail(c.name+" has a combinational loop");auto[late,early,prev]=c.arrivals(period);vector<string>ends=c.outputs;if(period){ends.clear();for(int i:c.flops)ends.push_back(c.gates[i].inputs[1]);}string best,heading=period?"flip-flops "+to_string(c.flops.size())+" period":"critical";
                for(const string&s:ends){if(!period)emit(late.count(s)?s+" min "+to_string(early[s])+" max "+to_string(late[s]):s+" unreachable");if(late.count(s)&&(best.empty()||late[s]>late[best]))best=s;}if(best.empty())emit(heading+" none");else{vector<string>path={best};while(prev.count(path.back()))path.push_back(prev[path.back()]);reverse(path.begin(),path.end());emit(heading+" "+to_string(late[best])+": "+join(path," -> "));}
            }else{
                c.combinational();vector<string>rows,expected;for(int r=0;r<(1<<c.inputs.size());r++){string b=bits(r,int(c.inputs.size()));rows.push_back(b);expected.push_back(c.evaluate(b));}
                if(cmd=="TRUTHTABLE"){vector<string>text=c.inputs;text.push_back("|");text.insert(text.end(),c.outputs.begin(),c.outputs.end());emit(join(text));for(size_t r=0;r<rows.size();r++){text.clear();for(char x:rows[r])text.push_back(string(1,x));text.push_back("|");for(char x:expected[r])text.push_back(string(1,x));emit(join(text));}}
                else if(cmd=="EQUIV"){Circuit d(*m2);d.combinational();if(c.inputs.size()!=d.inputs.size()||c.outputs.size()!=d.outputs.size())fail("port mismatch");for(size_t r=0;r<rows.size();r++){string v=d.evaluate(rows[r]);if(v!=expected[r]){emit("not equivalent at "+rows[r]+": "+expected[r]+" vs "+v);return;}}emit("equivalent");}
                else{vector<string>undetected;set<int>tests;for(const string&s:c.signals)for(char v:string("01")){int found=-1;for(size_t r=0;r<rows.size();r++)if(c.evaluate(rows[r],s,v)!=expected[r]){found=int(r);break;}if(found<0)undetected.push_back(s+"/"+v);else tests.insert(found);}int total=int(2*c.signals.size());emit("faults "+to_string(total)+" detected "+to_string(total-undetected.size()));for(const string&f:undetected)emit("undetected "+f);vector<string>text={"tests"};for(int r:tests)text.push_back(rows[r]);emit(join(text));}
            }return;
        }
        Simulation&s=*sim;
        if(cmd=="RESET"){s.reset();emit("reset");}
        else if(cmd=="SET"){int t=time(a[0]);input(a[1]);char v=value(a[2]);s.schedule(t,a[1],v);emit("set "+a[1]+" "+a[2]+" at "+to_string(t));}
        else if(cmd=="APPLY"){int t=time(a[0]);const string&b=a[1];if(b.size()!=s.c->inputs.size()||b.find_first_not_of("01X")!=string::npos)fail("bad vector "+b);for(size_t i=0;i<b.size();i++)s.schedule(t,s.c->inputs[i],b[i]);emit("apply "+b+" at "+to_string(t));}
        else if(cmd=="PULSE"||cmd=="CLOCK"){input(a[0]);int t=time(a[1]),width=number(a[2],true);if(cmd=="PULSE"){s.schedule(t,a[0],'1');s.schedule(t+width,a[0],'0');emit("pulse "+a[0]+" "+to_string(t)+" "+to_string(t+width));}else{int count=number(a[3],true);for(int i=0;i<count;i++)s.schedule(t+i*width,a[0],char('0'+i%2));emit("clock "+a[0]+" events "+to_string(count)+" last "+to_string(t+(count-1)*width));}}
        else if(cmd=="RUN"){int t=number(a[0]);if(t<=s.time)fail("time "+to_string(t)+" is not after "+to_string(s.time));s.run(t);}
        else if(cmd=="WATCH"||cmd=="UNWATCH"){set<string>seen;for(const string&x:a){signal(x);bool watched=has(s.watch,x);if(cmd=="WATCH"?(watched||seen.count(x)):(!watched||seen.count(x)))fail((cmd=="WATCH"?"already watched ":"not watched ")+x);seen.insert(x);}if(cmd=="WATCH")s.watch.insert(s.watch.end(),a.begin(),a.end());else s.watch.erase(remove_if(s.watch.begin(),s.watch.end(),[&](const string&x){return seen.count(x);}),s.watch.end());emit("watching "+(s.watch.empty()?"nothing":join(s.watch)));}
        else if(cmd=="SHOW"){for(const string&x:a)signal(x);vector<string>text=s.describe(a);if(a.empty()){text=s.describe(s.c->inputs);text.push_back("|");vector<string>outs=s.describe(s.c->outputs);text.insert(text.end(),outs.begin(),outs.end());}emit(join(text));}
        else if(cmd=="CHECK"){signal(a[0]);char v=value(a[1]);emit("check "+a[0]+"="+a[1]+" "+(s.values[a[0]]==v?"ok":"failed ("+string(1,s.values[a[0]])+")"));}
        else if(cmd=="PROBE"){string x=a[0];signal(x);string text="input";if(s.c->driver.count(x)){const Gate&g=s.c->gates[s.c->driver[x]];text=g.name+" "+g.kind+" "+join(s.describe(g.inputs))+" delay "+to_string(g.delay);}emit(x+"="+s.values[x]+" driven by "+text);vector<string>names={"fanout",to_string(s.c->readers[x].size())};for(int i:s.c->readers[x])names.push_back(s.c->gates[i].name);emit(join(names));}
        else if(cmd=="WAVE"){int start=number(a[0]),end=number(a[1]);if(!(start<end&&end<=s.time))fail("bad range "+to_string(start)+" "+to_string(end));if(s.watch.empty())fail("nothing watched");for(const string&x:s.watch){const auto&h=s.history[x];size_t i=0;char v='X';string wave;for(int t=start;t<end;t++){while(i<h.size()&&h[i].first<=t)v=h[i++].second;wave+=v;}emit(x+" "+wave);}}
        else if(cmd=="HISTORY"){string x=a[0];signal(x);vector<string>text={"history",x,"changes",to_string(s.history[x].size())};for(auto[t,v]:s.history[x])text.push_back(to_string(t)+":"+v);emit(join(text));}
        else if(cmd=="ACTIVITY"){int k=number(a[0],true);vector<string>ranked=s.c->signals;sort(ranked.begin(),ranked.end(),[&](const string&x,const string&y){return s.history[x].size()!=s.history[y].size()?s.history[x].size()>s.history[y].size():x<y;});for(int i=0;i<k&&i<int(ranked.size());i++)emit(ranked[i]+" "+to_string(s.history[ranked[i]].size()));}
        else if(cmd=="STATUS"){emit("circuit "+s.c->name+" time "+to_string(s.time)+" pending "+to_string(s.queue.size())+" events "+to_string(s.processed)+" halted "+(s.halted?"yes":"no"));map<char,int>n;for(const auto&[x,v]:s.values)n[v]++;emit("values 0:"+to_string(n['0'])+" 1:"+to_string(n['1'])+" X:"+to_string(n['X']));}
    }catch(const runtime_error&e){emit("error: line "+to_string(line)+": "+e.what());}}
};
int main(){ios::sync_with_stdio(false);cin.tie(nullptr);vector<string>lines;string line;while(getline(cin,line))lines.push_back(line);Simulator s;for(size_t i=0;i<lines.size()&&lines[i]!="END";i++){vector<string>w=words(lines[i]);if(w[0]=="MODULE"){size_t end=i+1;while(lines[end]!="ENDMODULE")end++;s.define(int(i)+1,vector<string>(lines.begin()+i,lines.begin()+end));i=end;}else s.execute(int(i)+1,w);}}
