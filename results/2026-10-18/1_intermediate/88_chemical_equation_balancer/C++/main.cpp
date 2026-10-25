#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
using Integer = int64_t;
using Composition = map<string,Integer>;
const vector<string> symbols={
    "H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca","Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn","Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr","Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn","Sb","Te","I","Xe"
};
const vector<Integer> weights={
    1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293
};
const Composition W=[] {
    Composition c;
    for(size_t i=0;i<symbols.size();++i)c[symbols[i]]=weights[i];
    return c;
}
();
const Composition valence={
    {
        "H",1
    },{
        "F",1
    },{
        "Cl",1
    },{
        "Br",1
    },{
        "I",1
    },{
        "O",2
    },{
        "S",2
    },{
        "Se",2
    },{
        "B",3
    },{
        "N",3
    },{
        "P",3
    },{
        "As",3
    },{
        "C",4
    },{
        "Si",4
    },{
        "Ge",4
    }
};
const Composition metals={
    {
        "Li",1
    },{
        "Na",1
    },{
        "K",1
    },{
        "Rb",1
    },{
        "Be",2
    },{
        "Mg",2
    },{
        "Ca",2
    },{
        "Sr",2
    },{
        "Al",3
    }
};
vector<string> split(const string& s){
    istringstream in(s);
    vector<string> v;
    string x;
    while(in>>x)v.push_back(x);
    return v;
}
string join(const vector<string>& a,const string& sep=" "){
    string s;
    for(const string& x:a){
        if(!s.empty())s+=sep;
        s+=x;
    }
    return s;
}
string dec(Integer n,int d){
    Integer p=1;
    for(int i=0;i<d;++i)p*=10;
    string f=to_string(n%p);
    return to_string(n/p)+"."+string(d-f.size(),'0')+f;
}
string ent(Integer n){
    return (n<0?"-":"")+dec(abs(n),2);
}
string signedInt(Integer n){
    return (n>0?"+":"")+to_string(n);
}
[[noreturn]] void fail(const string& s){
    throw runtime_error("error: "+s);
}
struct Fraction{
    Integer n,d;
    Fraction(Integer a=0,Integer b=1){
        Integer g=gcd(a,b);
        n=a/g*(b<0?-1:1);
        d=abs(b)/g;
    }
    Fraction operator-(Fraction b)const{
        return {
            n*b.d-b.n*d,d*b.d
        };
    }
    Fraction operator*(Fraction b)const{
        return {
            n*b.n,d*b.d
        };
    }
    Fraction operator/(Fraction b)const{
        return {
            n*b.d,d*b.n
        };
    }
    string text()const{
        return signedInt(n)+(d==1?"":"/"+to_string(d));
    }
};
vector<string> order(const Composition& c){
    vector<string> es;
    if(c.count("C")){
        es.push_back("C");
        if(c.count("H"))es.push_back("H");
    }
    for(const auto& [e,n]:c)if(!c.count("C")||(e!="C"&&e!="H"))es.push_back(e);
    return es;
}
void add(Composition& a,const Composition& b,Integer k=1){
    for(const auto& [e,n]:b)a[e]+=n*k;
}
Composition scale(Composition c,Integer k){
    for(auto& [e,n]:c)n*=k;
    return c;
}
Integer mass(const Composition& c){
    Integer m=0;
    for(const auto& [e,n]:c)m+=n*W.at(e);
    return m;
}
Integer countOf(const Composition& c,const string& e){
    auto it=c.find(e);
    return it==c.end()?0:it->second;
}
string hill(const Composition& c,Integer q=0){
    string s;
    for(const string& e:order(c))s+=e+(c.at(e)==1?"":to_string(c.at(e)));
    if(q)s+="^"+(abs(q)==1?string():to_string(abs(q)))+(q>0?"+":"-");
    return s;
}
struct Formula{
    Composition c;
    Integer q=0;
    Integer mass()const{
        return ::mass(c);
    }
};
struct Parser{
    string text;
    size_t p=0;
    vector<string> seen;
    char peek()const{
        return p<text.size()?text[p]:'\0';
    }
    Integer number(){
        size_t start=p;
        while(isdigit(peek()))++p;
        if(start==p)return 1;
        if(text[start]=='0')throw invalid_argument("");
        return stoll(text.substr(start,p-start));
    }
    Composition sequence(){
        Composition c;
        int items=0;
        while(true){
            char ch=peek();
            Composition item;
            if(isupper(ch)){
                string e(1,text[p++]);
                if(islower(peek()))e+=text[p++];
                seen.push_back(e);
                item[e]=1;
            }else if(ch=='('||ch=='['){
                ++p;
                item=sequence();
                if(peek()!=(ch=='('?')':']'))throw invalid_argument("");
                ++p;
            }else break;
            Integer k=number();
            add(c,item,k);
            ++items;
        }
        if(!items)throw invalid_argument("");
        return c;
    }
    Formula parse(){
        Formula f{
            sequence(),0
        };
        while(peek()=='.'){
            ++p;
            Integer k=number();
            Composition c=sequence();
            add(f.c,c,k);
        }
        if(peek()=='^'){
            ++p;
            Integer k=number();
            char ch=peek();
            if(ch!='+'&&ch!='-')throw invalid_argument("");
            ++p;
            f.q=ch=='+'?k:-k;
        }
        if(p!=text.size())throw invalid_argument("");
        return f;
    }
};
Formula formula(const string& text,const string& word=""){
    Parser p{
        text
    };
    Formula f;
    try{
        f=p.parse();
    }catch(const invalid_argument&){
        fail("invalid formula "+(word.empty()?text:word));
    }
    for(const string& e:p.seen)if(!W.count(e))fail("unknown element "+e);
    return f;
}
struct Species{
    string f,state;
    Integer coefficient=1;
    Formula formula;
    string name()const{
        return f+state;
    }
    Integer mass()const{
        return formula.mass();
    }
};
Species species(const string& word,bool check=false){
    Species s;
    s.f=word;
    for(const string& state:{
        "(s)","(l)","(g)","(aq)"
    })if(word.size()>=state.size()&&word.substr(word.size()-state.size())==state){
        s.state=state;
        s.f=word.substr(0,word.size()-state.size());
        break;
    }
    if(check&&!s.f.empty()&&isdigit(s.f[0])){
        size_t n=0;
        while(n<s.f.size()&&isdigit(s.f[n]))++n;
        if(s.f[0]=='0')fail("invalid formula "+word);
        s.coefficient=stoll(s.f.substr(0,n));
        s.f=s.f.substr(n);
    }
    s.formula=formula(s.f,word);
    return s;
}
struct Equation{
    vector<Species> list;
    size_t r;
    vector<Integer> signs()const{
        vector<Integer> s(list.size(),-1);
        fill(s.begin(),s.begin()+r,1);
        return s;
    }
};
Equation equation(const vector<string>& a,bool check=false){
    int arrow=-1;
    bool valid=a.size()%2==1;
    for(size_t i=0;i<a.size();++i){
        bool op=a[i]=="+"||a[i]=="->";
        if(i%2){
            if(!op)valid=false;
            if(a[i]=="->"){
                if(arrow>=0)valid=false;
                arrow=i;
            }
        }else if(op)valid=false;
    }
    if(!valid||arrow<0)fail("malformed equation");
    Equation eq;
    eq.r=(arrow+1)/2;
    for(size_t i=0;i<a.size();i+=2)eq.list.push_back(species(a[i],check));
    return eq;
}
Integer quantity(const string& s){
    if(!regex_match(s,regex("(0|[1-9][0-9]{0,3})(\\.[0-9]{1,3})?")))fail("invalid quantity "+s);
    size_t p=s.find('.');
    string a=s.substr(0,p),b=p==string::npos?"":s.substr(p+1);
    b.append(3-b.size(),'0');
    Integer q=stoll(a)*1000+stoll(b);
    if(!q)fail("invalid quantity "+s);
    return q;
}
Integer enthalpy(string s){
    string word=s;
    if(!regex_match(s,regex("-?(0|[1-9][0-9]{0,4})(\\.[0-9]{1,2})?")))fail("invalid enthalpy "+s);
    Integer sign=1;
    if(s[0]=='-'){
        sign=-1;
        s=s.substr(1);
    }
    size_t p=s.find('.');
    string b=p==string::npos?"":s.substr(p+1);
    b.append(2-b.size(),'0');
    return sign*(stoll(s.substr(0,p))*100+stoll(b));
}
struct Matrix{
    vector<string> labels;
    vector<vector<Integer>> rows;
};
Matrix matrix(const vector<Species>& list,const vector<Integer>& signs){
    Composition all;
    for(const Species& s:list)add(all,s.formula.c);
    Matrix m;
    m.labels=order(all);
    m.labels.push_back("charge");
    for(const string& e:m.labels){
        vector<Integer> row;
        for(size_t i=0;i<list.size();++i)row.push_back(signs[i]*(e=="charge"?list[i].formula.q:countOf(list[i].formula.c,e)));
        m.rows.push_back(row);
    }
    return m;
}
struct Nullspace{
    int rank;
    vector<vector<Integer>> basis;
};
Nullspace nullspace(const vector<vector<Integer>>& rows,size_t n){
    vector<vector<Fraction>> a;
    for(const auto& row:rows){
        vector<Fraction> r;
        for(Integer x:row)r.emplace_back(x);
        a.push_back(r);
    }
    vector<size_t> piv,free;
    for(size_t j=0;j<n;++j){
        size_t r=piv.size(),i=r;
        while(i<a.size()&&!a[i][j].n)++i;
        if(i==a.size()){
            free.push_back(j);
            continue;
        }
        swap(a[r],a[i]);
        Fraction t=a[r][j];
        for(Fraction& x:a[r])x=x/t;
        for(size_t k=0;k<a.size();++k)if(k!=r&&a[k][j].n){
            Fraction f=a[k][j];
            for(size_t z=0;z<n;++z)a[k][z]=a[k][z]-f*a[r][z];
        }
        piv.push_back(j);
    }
    Nullspace result{
        int(piv.size()),{
        }
    };
    for(size_t f:free){
        vector<Fraction> v(n);
        v[f]=Fraction(1);
        for(size_t i=0;i<piv.size();++i)v[piv[i]]=Fraction(-a[i][f].n,a[i][f].d);
        Integer l=1;
        for(Fraction x:v)l=lcm(l,x.d);
        vector<Integer> b;
        Integer g=0;
        for(Fraction x:v){
            Integer z=x.n*(l/x.d);
            b.push_back(z);
            g=gcd(g,z);
        }
        for(Integer& x:b)x/=g;
        result.basis.push_back(b);
    }
    return result;
}
vector<Integer> coefficients(const vector<Species>& list,const vector<Integer>& sign,size_t k){
    auto result=nullspace(matrix(list,sign).rows,list.size());
    if(result.basis.size()>1)throw runtime_error("AMBIGUOUS (nullity "+to_string(result.basis.size())+")");
    if(result.basis.empty())throw runtime_error("IMPOSSIBLE");
    vector<Integer> v=result.basis[0];
    if(v[0]<0)for(Integer& x:v)x=-x;
    for(size_t i=0;i<k;++i)if(v[i]<=0)throw runtime_error("IMPOSSIBLE");
    return v;
}
string term(const string& s,Integer k){
    return (k==1?"":to_string(k))+s;
}
string notation(const Equation& eq,const vector<Integer>& v){
    vector<string> l,r;
    for(size_t i=0;i<v.size();++i)(i<eq.r?l:r).push_back(term(eq.list[i].name(),v[i]));
    return join(l," + ")+" -> "+join(r," + ");
}
string gas(const Species& s,Integer n,Integer d){
    return s.state=="(g)"?" "+dec(n*22414/d,3)+" L":"";
}
vector<string> ratios(const Composition& a){
    vector<string> es=order(a),out;
    string f=es[0];
    for(const string& e:es)if(a.at(e)*W.at(f)<a.at(f)*W.at(e))f=e;
    for(const string& e:es)out.push_back(e+" "+dec(1000*a.at(e)*W.at(f)/(W.at(e)*a.at(f)),3));
    for(Integer k=1;k<=12;++k){
        Composition c;
        bool ok=true;
        for(const string& e:es){
            Integer n=k*a.at(e)*W.at(f),d=W.at(e)*a.at(f),i=(2*n+d)/(2*d);
            c[e]=i;
            if(20*abs(n-i*d)>d)ok=false;
        }
        if(ok){
            out.push_back(hill(c)+" (k = "+to_string(k)+")");
            return out;
        }
    }
    out.push_back("no simple ratio");
    return out;
}
string group(const string& f,Integer k){
    string c=f.substr(0,f.find('^'));
    if(k==1)return c;
    int depth=0,last=-1;
    if(c[0]=='[')for(size_t i=0;i<c.size();++i){
        if(c[i]=='[')++depth;
        if(c[i]==']'&&--depth==0){
            last=i;
            break;
        }
    }
    return (regex_match(c,regex("[A-Z][a-z]?"))||last==int(c.size())-1?c:"("+c+")")+to_string(k);
}
const map<string,int> counts={
    {
        "ELEMENT",1
    },{
        "PARSE",1
    },{
        "MASS",1
    },{
        "PERCENT",1
    },{
        "EMPIRICAL",1
    },{
        "DBE",1
    },{
        "OXSTATE",1
    },{
        "MOLES",2
    },{
        "GRAMS",2
    },{
        "MOLECULAR",2
    },{
        "SALT",2
    },{
        "HEAT",2
    },{
        "COMBUST",3
    },{
        "HEATS",0
    },{
        "DERIVE",-2
    },{
        "BALANCE",-1
    },{
        "MATRIX",-1
    },{
        "CHECK",-1
    },{
        "DELTAH",-1
    },{
        "REDOX",-3
    },{
        "HALF",-3
    },{
        "STOICH",-4
    },{
        "LIMITING",-4
    },{
        "YIELD",-4
    }
};
struct Chemistry{
    map<string,Integer> heats;
    vector<string> execute(const string& line){
        vector<string> a=split(line);
        string cmd=a[0];
        a.erase(a.begin());
        int n=a.size();
        if(!counts.count(cmd))fail("unknown command "+cmd);
        int expected=counts.at(cmd);
        if((expected>=0&&n!=expected)||(expected==-1&&n<1)||(expected==-2&&(n<2||n%2))||(expected==-3&&n<2))fail("wrong argument count for "+cmd);
        if(cmd=="ELEMENT"){
            if(!W.count(a[0]))fail("unknown element "+a[0]);
            return {
                a[0]+" (Z = "+to_string(find(symbols.begin(),symbols.end(),a[0])-symbols.begin()+1)+") "+dec(W.at(a[0]),3)+" u"
            };
        }
        if(cmd=="HEATS"){
            vector<string> out;
            for(const auto& [s,h]:heats)out.push_back(s+" "+ent(h)+" kJ/mol");
            return out.empty()?vector<string>{
                "no enthalpies"
            }:out;
        }
        if(cmd=="HEAT"){
            species(a[0]);
            Integer h=enthalpy(a[1]);
            string out="dHf("+a[0]+") = "+ent(h)+" kJ/mol";
            if(heats.count(a[0]))out+=" (was "+ent(heats[a[0]])+")";
            heats[a[0]]=h;
            return {
                out
            };
        }
        if(cmd=="DERIVE"){
            Composition b;
            Integer t=0;
            for(int i=0;i<n;i+=2){
                string e=a[i];
                if(!W.count(e))fail("unknown element "+e);
                if(b.count(e))fail("duplicate element "+e);
                Integer q=quantity(a[i+1]);
                if(q>100000)fail("invalid percentage "+a[i+1]);
                b[e]=q;
                t+=q;
            }
            if(abs(t-100000)>1000)fail("percentages sum to "+dec(t,3));
            return ratios(b);
        }
        if(cmd=="COMBUST"){
            Integer s=quantity(a[0]),p=quantity(a[1]),r=quantity(a[2]),c=p*12011/44009,h=r*2016/18015,o=s-c-h;
            if(!c||!h||100*o < -s)fail("inconsistent masses");
            Composition b={
                {
                    "C",c
                },{
                    "H",h
                }
            };
            if(100*o>s)b["O"]=o;
            vector<string> out;
            for(const string& e:order(b))out.push_back("mass "+e+" "+dec(b[e],3)+" g");
            vector<string> tail=ratios(b);
            out.insert(out.end(),tail.begin(),tail.end());
            return out;
        }
        const vector<string> formulaCommands={
            "PARSE","MASS","PERCENT","EMPIRICAL","DBE","OXSTATE","MOLES","GRAMS","MOLECULAR","SALT"
        };
        if(find(formulaCommands.begin(),formulaCommands.end(),cmd)!=formulaCommands.end()){
            Formula f=formula(a[0]);
            Composition c=f.c;
            Integer q=f.q,m=f.mass();
            vector<string> es=order(c),out;
            if(cmd=="PARSE"){
                vector<string> parts;
                for(const string& e:es)parts.push_back(e+" "+to_string(c[e]));
                return {
                    hill(c,q)+" ("+join(parts,", ")+"; charge "+signedInt(q)+")"
                };
            }
            if(cmd=="MASS")return {
                "M("+a[0]+") = "+dec(m,3)+" g/mol"
            };
            if(cmd=="PERCENT"){
                for(const string& e:es)out.push_back(e+" "+dec(10000*c[e]*W.at(e)/m,2)+"%");
                return out;
            }
            if(cmd=="EMPIRICAL"){
                Integer g=0;
                for(const auto& [e,x]:c)g=gcd(g,x);
                for(auto& [e,x]:c)x/=g;
                return {
                    hill(c)+" (n = "+to_string(g)+")"
                };
            }
            if(cmd=="DBE"){
                if(q)fail("charged formula "+a[0]);
                Integer t=2;
                for(const string& e:es){
                    if(!valence.count(e))fail("no valence for "+e);
                    t+=c[e]*(valence.at(e)-2);
                }
                return {
                    "DBE = "+string(t<0?"-":"")+to_string(abs(t)/2)+"."+(t%2?"5":"0")
                };
            }
            if(cmd=="OXSTATE"){
                map<string,Fraction> st;
                string last;
                auto assign=[&](const string& e,Integer x){
                    st[e]=Fraction(x);
                    last=e;
                };
                if(es.size()==1)st[es[0]]=Fraction(q,c[es[0]]);
                else{
                    if(c.count("F"))assign("F",-1);
                    for(const string& e:es)if(metals.count(e))assign(e,metals.at(e));
                    if(c.count("H")){
                        bool only=true;
                        for(const string& e:es)if(e!="H"&&!metals.count(e))only=false;
                        assign("H",only?-1:1);
                    }
                    if(c.count("O"))assign("O",-2);
                    else if(!c.count("F"))for(const string& e:{
                        "Cl","Br","I"
                    })if(c.count(e)){
                        assign(e,-1);
                        break;
                    }
                    vector<string> u;
                    Integer sum=0;
                    for(const string& e:es)if(!st.count(e))u.push_back(e);
                    else sum+=c[e]*st[e].n;
                    if(u.size()>1)return {
                        "indeterminate: "+join(u)
                    };
                    if(!u.empty())st[u[0]]=Fraction(q-sum,c[u[0]]);
                    else if(sum!=q)st[last]=Fraction(q-sum+c[last]*st[last].n,c[last]);
                }
                for(const string& e:es)out.push_back(e+" "+st[e].text());
                return {
                    join(out,", ")
                };
            }
            if(cmd=="SALT"){
                Formula b=formula(a[1]);
                if(q<=0)fail("not a cation "+a[0]);
                if(b.q>=0)fail("not an anion "+a[1]);
                for(const string& s:a)if(s.find('.')!=string::npos)fail("hydrate ion "+s);
                Integer g=gcd(q,b.q),x=-b.q/g,y=q/g;
                Composition z=scale(c,x);
                add(z,b.c,y);
                return {
                    group(a[0],x)+group(a[1],y)+" ("+hill(z)+", "+dec(mass(z),3)+" g/mol)"
                };
            }
            if(cmd=="MOLECULAR"&&q)fail("charged formula "+a[0]);
            Integer x=quantity(a[1]);
            if(cmd=="MOLES")return {
                dec(x,3)+" g "+a[0]+" = "+dec(x*1000000/m,6)+" mol"
            };
            if(cmd=="GRAMS")return {
                dec(x,3)+" mol "+a[0]+" = "+dec(x*m/1000,3)+" g"
            };
            Integer k=(2*x+m)/(2*m);
            if(!k||10*abs(x-k*m)>m)return {
                "no integer multiple (ratio "+dec(1000*x/m,3)+")"
            };
            return {
                hill(scale(c,k))+" (n = "+to_string(k)+", "+dec(k*m,3)+" g/mol)"
            };
        }
        if(cmd=="REDOX"||cmd=="HALF"){
            string medium=a[0];
            if(medium!="acidic"&&medium!="basic")fail("invalid medium "+medium);
            Equation eq=equation(vector<string>(a.begin()+1,a.end()));
            for(const Species& s:eq.list)if(s.f=="H^+"||s.f=="OH^-"||s.f=="H2O")fail("reserved species "+s.name());
            vector<Species> aux={
                species(medium=="acidic"?"H^+":"OH^-"),species("H2O")
            };
            if(cmd=="HALF")aux.push_back({
                "e^-","",1,{
                    {
                    },-1
                }
            });
            vector<Species> list=eq.list;
            list.insert(list.end(),aux.begin(),aux.end());
            vector<Integer> signs=eq.signs();
            signs.insert(signs.end(),aux.size(),1);
            vector<Integer> v=coefficients(list,signs,eq.list.size());
            vector<string> left,right;
            for(size_t i=0;i<eq.list.size();++i)(i<eq.r?left:right).push_back(term(list[i].name(),v[i]));
            for(size_t i=eq.list.size();i<list.size();++i)if(v[i])(v[i]>0?left:right).push_back(term(list[i].name(),abs(v[i])));
            vector<string> out={
                join(left," + ")+" -> "+join(right," + ")
            };
            if(cmd=="HALF")out.push_back(v.back()>0?"reduction":v.back()<0?"oxidation":"no electron transfer");
            return out;
        }
        vector<string> words=a,rest;
        if(cmd=="STOICH"||cmd=="LIMITING"||cmd=="YIELD"){
            if(count(a.begin(),a.end(),":")!=1)fail("invalid separator");
            auto p=find(a.begin(),a.end(),":");
            words.assign(a.begin(),p);
            rest.assign(p+1,a.end());
            if((cmd=="STOICH"&&rest.size()!=2)||(cmd=="YIELD"&&rest.size()!=4))fail("wrong argument count for "+cmd);
        }
        Equation eq=equation(words,cmd=="CHECK");
        const vector<Species>& list=eq.list;
        size_t r=eq.r;
        vector<Integer> signs=eq.signs();
        if(cmd=="MATRIX"){
            Matrix m=matrix(list,signs);
            Nullspace ns=nullspace(m.rows,list.size());
            vector<string> names,out;
            for(const Species& s:list)names.push_back(s.name());
            out.push_back("columns: "+join(names));
            for(size_t i=0;i<m.rows.size();++i){
                vector<string> row;
                for(Integer x:m.rows[i])row.push_back(to_string(x));
                out.push_back(m.labels[i]+": "+join(row));
            }
            out.push_back("rank "+to_string(ns.rank)+", nullity "+to_string(ns.basis.size()));
            for(const auto& v:ns.basis){
                vector<string> row;
                for(Integer x:v)row.push_back(to_string(x));
                out.push_back("null: "+join(row));
            }
            return out;
        }
        if(cmd=="CHECK"){
            Matrix m=matrix(list,signs);
            vector<string> diff;
            for(size_t i=0;i<m.rows.size();++i){
                Integer l=0,rr=0;
                for(size_t j=0;j<list.size();++j)(j<r?l:rr)+=m.rows[i][j]*list[j].coefficient;
                rr=-rr;
                if(l!=rr)diff.push_back(m.labels[i]+": "+(m.labels[i]=="charge"?signedInt(l):to_string(l))+" != "+(m.labels[i]=="charge"?signedInt(rr):to_string(rr)));
            }
            if(!diff.empty()){
                diff.insert(diff.begin(),"not balanced");
                return diff;
            }
            Integer g=0;
            for(const Species& s:list)g=gcd(g,s.coefficient);
            return {
                g==1?"balanced":"balanced, not in lowest terms (gcd "+to_string(g)+")"
            };
        }
        int target=-1,product=-1;
        vector<Integer> qs;
        if(cmd=="DELTAH")for(const Species& s:list)if(!heats.count(s.name()))fail("no enthalpy for "+s.name());
        if(cmd=="STOICH"){
            for(size_t i=0;i<list.size();++i)if(list[i].name()==rest[0]){
                target=i;
                break;
            }
            if(target<0)fail("species "+rest[0]+" not in equation");
            qs.push_back(quantity(rest[1]));
        }
        if(cmd=="LIMITING"){
            if(rest.size()!=r)fail("expected "+to_string(r)+" masses, got "+to_string(rest.size()));
            for(const string& x:rest)qs.push_back(quantity(x));
        }
        if(cmd=="YIELD"){
            for(size_t i=0;i<r;++i)if(list[i].name()==rest[0]){
                target=i;
                break;
            }
            if(target<0)fail(rest[0]+" is not a reactant");
            for(size_t i=r;i<list.size();++i)if(list[i].name()==rest[2]){
                product=i;
                break;
            }
            if(product<0)fail(rest[2]+" is not a product");
            qs={
                quantity(rest[1]),quantity(rest[3])
            };
        }
        vector<Integer> v=coefficients(list,signs,list.size());
        vector<string> out={
            notation(eq,v)
        };
        if(cmd=="BALANCE")return out;
        if(cmd=="DELTAH"){
            Integer h=0;
            for(size_t i=0;i<list.size();++i)h-=signs[i]*v[i]*heats.at(list[i].name());
            out.push_back("dH = "+ent(h)+" kJ ("+(h<0?"exothermic":h>0?"endothermic":"thermoneutral")+")");
            return out;
        }
        if(cmd=="STOICH"){
            Integer d=v[target]*list[target].mass();
            for(size_t i=0;i<list.size();++i){
                Integer x=qs[0]*v[i];
                out.push_back(list[i].name()+" "+dec(x*1000000/d,6)+" mol "+dec(x*list[i].mass()/d,3)+" g"+gas(list[i],x,d));
            }
            return out;
        }
        if(cmd=="YIELD"){
            Integer t=qs[0]*v[product]*list[product].mass()/(v[target]*list[target].mass());
            out.push_back("theoretical "+dec(t,3)+" g");
            out.push_back("actual "+dec(qs[1],3)+" g");
            out.push_back(t?"yield "+dec(qs[1]*10000/t,2)+"%":"yield undefined");
            return out;
        }
        size_t l=0;
        for(size_t i=1;i<r;++i)if(qs[i]*v[l]*list[l].mass()<qs[l]*v[i]*list[i].mass())l=i;
        Integer d=v[l]*list[l].mass();
        out.push_back("limiting "+list[l].name());
        out.push_back("extent "+dec(qs[l]*1000000/d,6)+" mol");
        for(size_t i=r;i<list.size();++i)out.push_back("product "+list[i].name()+" "+dec(qs[l]*v[i]*list[i].mass()/d,3)+" g"+gas(list[i],qs[l]*v[i],d));
        for(size_t i=0;i<r;++i)if(i!=l)out.push_back("remaining "+list[i].name()+" "+dec((qs[i]*d-qs[l]*v[i]*list[i].mass())/d,3)+" g");
        return out;
    }
};
int main(){
    int n;
    cin>>n;
    string line;
    getline(cin,line);
    Chemistry engine;
    while(n--&&getline(cin,line)){
        try{
            for(const string& s:engine.execute(line))cout<<s<<'\n';
        }catch(const runtime_error& e){
            cout<<e.what()<<'\n';
        }
    }
}
