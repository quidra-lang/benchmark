local symbols={};
for s in ('H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe'):gmatch('%S+') do
    symbols[#symbols+1]=s
end
local weights={1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293}
local W,Z={},{};
for i,s in ipairs(symbols) do
    W[s]=weights[i];
    Z[s]=i
end
local valence={H=1,F=1,Cl=1,Br=1,I=1,O=2,S=2,Se=2,B=3,N=3,P=3,As=3,C=4,Si=4,Ge=4}
local metals={Li=1,Na=1,K=1,Rb=1,Be=2,Mg=2,Ca=2,Sr=2,Al=3}
local heats={}
local function fail(s)
    error('error: '..s,0)
end
local function gcd(a,b)
    a=math.abs(a);
    b=math.abs(b);
    while b~=0 do
        a,b=b,a%b
    end;
    return a
end
local function dec(n,d)
    local p=1;
    for _=1,d do
        p=p*10
    end;
    return string.format('%d.%0'..d..'d',n//p,n%p)
end
local function ent(n)
    return (n<0 and '-' or '')..dec(math.abs(n),2)
end
local function signed(n)
    return (n>0 and '+' or '')..n
end
local function fraction(n,d)
    d=d or 1;
    local g=gcd(n,d);
    return {n=n//g*(d<0 and -1 or 1),d=math.abs(d)//g}
end
local function sub(a,b)
    return fraction(a.n*b.d-b.n*a.d,a.d*b.d)
end
local function mul(a,b)
    return fraction(a.n*b.n,a.d*b.d)
end
local function divide(a,b)
    return fraction(a.n*b.d,a.d*b.n)
end
local function fractionText(x)
    return signed(x.n)..(x.d==1 and '' or '/'..x.d)
end
local function order(c)
    local es={};
    for e in pairs(c) do
        es[#es+1]=e
    end;
    table.sort(es);
    if not c.C then
        return es
    end;
    local out={'C'};
    if c.H then
        out[#out+1]='H'
    end;
    for _,e in ipairs(es) do
        if e~='C' and e~='H' then
            out[#out+1]=e
        end
    end;
    return out
end
local function add(a,b,k)
    k=k or 1;
    for e,n in pairs(b) do
        a[e]=(a[e] or 0)+n*k
    end;
    return a
end
local function scale(c,k)
    local a={};
    for e,n in pairs(c) do
        a[e]=n*k
    end;
    return a
end
local function mass(c)
    local m=0;
    for e,n in pairs(c) do
        m=m+n*W[e]
    end;
    return m
end
local function hill(c,q)
    local t={};
    for _,e in ipairs(order(c)) do
        t[#t+1]=e..(c[e]==1 and '' or c[e])
    end;
    q=q or 0;
    return table.concat(t)..(q==0 and '' or '^'..(math.abs(q)==1 and '' or math.abs(q))..(q>0 and '+' or '-'))
end
local function formula(text,word)
    local p,seen=1,{}
    local function peek()
        return text:sub(p,p)
    end
    local function number()
        local start=p;
        while peek():match('^%d$') do
            p=p+1
        end;
        if start==p then
            return 1
        end;
        if text:sub(start,start)=='0' then
            error('syntax')
        end;
        return tonumber(text:sub(start,p-1))
    end
    local sequence
    sequence=function()
        local c,items={},0;
        while true do
            local ch=peek();
            local item;
            if ch:match('^[A-Z]$') then
                local e=ch;
                p=p+1;
                if peek():match('^[a-z]$') then
                    e=e..peek();
                    p=p+1
                end;
                seen[#seen+1]=e;
                item={[e]=1}
            elseif ch=='(' or ch=='[' then
                p=p+1;
                item=sequence();
                if peek()~=(ch=='(' and ')' or ']') then
                    error('syntax')
                end;
                p=p+1
            else
                break
            end;
            add(c,item,number());
            items=items+1
        end;
        if items==0 then
            error('syntax')
        end;
        return c
    end
    local ok,f=pcall(function()
        local c=sequence();
        while peek()=='.' do
            p=p+1;
            local k=number();
            add(c,sequence(),k)
        end;
        local q=0;
        if peek()=='^' then
            p=p+1;
            local k=number();
            local ch=peek();
            if ch~='+' and ch~='-' then
                error('syntax')
            end;
            p=p+1;
            q=ch=='+' and k or -k
        end;
        if p~=#text+1 then
            error('syntax')
        end;
        return {c=c,q=q}
    end)
    if not ok then
        fail('invalid formula '..(word or text))
    end
    for _,e in ipairs(seen) do
        if not W[e] then
            fail('unknown element '..e)
        end
    end;
    f.m=mass(f.c);
    return f
end
local function species(word,check)
    local state,f,k='',word,1
    for _,s in ipairs({'(s)','(l)','(g)','(aq)'}) do
        if word:sub(-#s)==s then
            state=s;
            f=word:sub(1,#word-#s);
            break
        end
    end
    if check then
        local digits=f:match('^%d+');
        if digits then
            if digits:sub(1,1)=='0' then
                fail('invalid formula '..word)
            end;
            k=tonumber(digits);
            f=f:sub(#digits+1)
        end
    end
    local s=formula(f,word);
    s.f=f;
    s.state=state;
    s.name=f..state;
    s.k=k;
    return s
end
local function slice(a,first,last)
    local b={};
    for i=first,last or #a do
        b[#b+1]=a[i]
    end;
    return b
end
local function equation(a,check)
    local valid,arrow=#a%2==1,nil
    for i,s in ipairs(a) do
        local op=s=='+' or s=='->';
        if i%2==0 then
            if not op then
                valid=false
            end;
            if s=='->' then
                if arrow then
                    valid=false
                end;
                arrow=i
            end
        elseif op then
            valid=false
        end
    end
    if not valid or not arrow then
        fail('malformed equation')
    end
    local list,sign,r={},{},arrow//2;
    for i=1,#a,2 do
        list[#list+1]=species(a[i],check);
        sign[#sign+1]=#list<=r and 1 or -1
    end;
    return {list=list,r=r,sign=sign}
end
local function decimalWord(s,maxWhole,digits,negative)
    local sign=1;
    if negative and s:sub(1,1)=='-' then
        sign=-1;
        s=s:sub(2)
    end
    local a,b=s:match('^(%d+)%.(%d+)$');
    if not a then
        a=s:match('^(%d+)$');
        b=''
    end
    if not a or #a>maxWhole or (#a>1 and a:sub(1,1)=='0') or #b>digits then
        return nil
    end
    return sign*(tonumber(a)*10^digits+tonumber(b..string.rep('0',digits-#b)))
end
local function quantity(s)
    local q=decimalWord(s,4,3,false);
    if not q or q<=0 then
        fail('invalid quantity '..s)
    end;
    return math.tointeger(q)
end
local function enthalpy(s)
    local q=decimalWord(s,5,2,true);
    if not q then
        fail('invalid enthalpy '..s)
    end;
    return math.tointeger(q)
end
local function matrix(list,sign)
    local all={};
    for _,s in ipairs(list) do
        add(all,s.c)
    end;
    local labels=order(all);
    labels[#labels+1]='charge';
    local rows={}
    for _,e in ipairs(labels) do
        local row={};
        for i,s in ipairs(list) do
            row[i]=sign[i]*(e=='charge' and s.q or (s.c[e] or 0))
        end;
        rows[#rows+1]=row
    end;
    return labels,rows
end
local function nullspace(rows,n)
    local a={};
    for i,row in ipairs(rows) do
        a[i]={};
        for j,x in ipairs(row) do
            a[i][j]=fraction(x)
        end
    end
    local piv,free={},{}
    for j=1,n do
        local r=#piv+1;
        local i=r;
        while i<=#a and a[i][j].n==0 do
            i=i+1
        end;
        if i>#a then
            free[#free+1]=j
        else
            a[r],a[i]=a[i],a[r];
            local t=a[r][j];
            for z=1,n do
                a[r][z]=divide(a[r][z],t)
            end;
            for k=1,#a do
                if k~=r and a[k][j].n~=0 then
                    local f=a[k][j];
                    for z=1,n do
                        a[k][z]=sub(a[k][z],mul(f,a[r][z]))
                    end
                end
            end;
            piv[#piv+1]=j
        end
    end
    local basis={};
    for _,f in ipairs(free) do
        local v={};
        for j=1,n do
            v[j]=fraction(0)
        end;
        v[f]=fraction(1);
        for i,j in ipairs(piv) do
            v[j]=fraction(-a[i][f].n,a[i][f].d)
        end;
        local l=1;
        for _,x in ipairs(v) do
            l=l//gcd(l,x.d)*x.d
        end;
        local b,g={},0;
        for j,x in ipairs(v) do
            b[j]=x.n*(l//x.d);
            g=gcd(g,b[j])
        end;
        for j=1,n do
            b[j]=b[j]//g
        end;
        basis[#basis+1]=b
    end;
    return #piv,basis
end
local function coefficients(list,sign,k)
    local _,rows=matrix(list,sign);
    local _,basis=nullspace(rows,#list)
    if #basis>=2 then
        error('AMBIGUOUS (nullity '..#basis..')',0)
    end;
    if #basis==0 then
        error('IMPOSSIBLE',0)
    end
    local v=basis[1];
    if v[1]<0 then
        for i=1,#v do
            v[i]=-v[i]
        end
    end;
    for i=1,k or #list do
        if v[i]<=0 then
            error('IMPOSSIBLE',0)
        end
    end;
    return v
end
local function term(s,k)
    return (k==1 and '' or k)..s
end
local function notation(eq,v)
    local left,right={},{};
    for i,s in ipairs(eq.list) do
        local t=i<=eq.r and left or right;
        t[#t+1]=term(s.name,v[i])
    end;
    return table.concat(left,' + ')..' -> '..table.concat(right,' + ')
end
local function gas(s,n,d)
    return s.state=='(g)' and ' '..dec(n*22414//d,3)..' L' or ''
end
local function ratios(a)
    local es=order(a);
    local f=es[1];
    for _,e in ipairs(es) do
        if a[e]*W[f]<a[f]*W[e] then
            f=e
        end
    end;
    local out={};
    for _,e in ipairs(es) do
        out[#out+1]=e..' '..dec(1000*a[e]*W[f]//(W[e]*a[f]),3)
    end
    for k=1,12 do
        local c,ok={},true;
        for _,e in ipairs(es) do
            local n,d=k*a[e]*W[f],W[e]*a[f];
            local i=(2*n+d)//(2*d);
            c[e]=i;
            if 20*math.abs(n-i*d)>d then
                ok=false
            end
        end;
        if ok then
            out[#out+1]=hill(c)..' (k = '..k..')';
            return out
        end
    end;
    out[#out+1]='no simple ratio';
    return out
end
local function group(f,k)
    local core=f:match('^[^^]+');
    if k==1 then
        return core
    end;
    local depth,last=0,nil;
    if core:sub(1,1)=='[' then
        for i=1,#core do
            local ch=core:sub(i,i);
            if ch=='[' then
                depth=depth+1
            elseif ch==']' then
                depth=depth-1;
                if depth==0 then
                    last=i;
                    break
                end
            end
        end
    end;
    return ((core:match('^[A-Z][a-z]?$') or last==#core) and core or '('..core..')')..k
end
local counts={ELEMENT=1,PARSE=1,MASS=1,PERCENT=1,EMPIRICAL=1,DBE=1,OXSTATE=1,MOLES=2,GRAMS=2,MOLECULAR=2,SALT=2,HEAT=2,COMBUST=3,HEATS=0,DERIVE=-2,BALANCE=-1,MATRIX=-1,CHECK=-1,DELTAH=-1,REDOX=-3,HALF=-3,STOICH=-4,LIMITING=-4,YIELD=-4}
local formulaCommands={PARSE=true,MASS=true,PERCENT=true,EMPIRICAL=true,DBE=true,OXSTATE=true,MOLES=true,GRAMS=true,MOLECULAR=true,SALT=true}
local function execute(line)
    local a={};
    for s in line:gmatch('%S+') do
        a[#a+1]=s
    end;
    local cmd=table.remove(a,1);
    local n=#a;
    local expected=counts[cmd]
    if not expected then
        fail('unknown command '..cmd)
    end
    if (expected>=0 and n~=expected) or (expected==-1 and n<1) or (expected==-2 and (n<2 or n%2~=0)) or (expected==-3 and n<2) then
        fail('wrong argument count for '..cmd)
    end
    if cmd=='ELEMENT' then
        if not W[a[1]] then
            fail('unknown element '..a[1])
        end;
        return {a[1]..' (Z = '..Z[a[1]]..') '..dec(W[a[1]],3)..' u'}
    end
    if cmd=='HEATS' then
        local names={};
        for s in pairs(heats) do
            names[#names+1]=s
        end;
        table.sort(names);
        local out={};
        for _,s in ipairs(names) do
            out[#out+1]=s..' '..ent(heats[s])..' kJ/mol'
        end;
        return #out==0 and {'no enthalpies'} or out
    end
    if cmd=='HEAT' then
        species(a[1]);
        local h=enthalpy(a[2]);
        local out='dHf('..a[1]..') = '..ent(h)..' kJ/mol'..(heats[a[1]]~=nil and ' (was '..ent(heats[a[1]])..')' or '');
        heats[a[1]]=h;
        return {out}
    end
    if cmd=='DERIVE' then
        local b,t={},0;
        for i=1,n,2 do
            local e=a[i];
            if not W[e] then
                fail('unknown element '..e)
            end;
            if b[e] then
                fail('duplicate element '..e)
            end;
            local q=quantity(a[i+1]);
            if q>100000 then
                fail('invalid percentage '..a[i+1])
            end;
            b[e]=q;
            t=t+q
        end;
        if math.abs(t-100000)>1000 then
            fail('percentages sum to '..dec(t,3))
        end;
        return ratios(b)
    end
    if cmd=='COMBUST' then
        local s,p,r=quantity(a[1]),quantity(a[2]),quantity(a[3]);
        local c,h=p*12011//44009,r*2016//18015;
        local o=s-c-h;
        if c==0 or h==0 or 100*o < -s then
            fail('inconsistent masses')
        end;
        local b={C=c,H=h};
        if 100*o>s then
            b.O=o
        end;
        local out={};
        for _,e in ipairs(order(b)) do
            out[#out+1]='mass '..e..' '..dec(b[e],3)..' g'
        end;
        for _,x in ipairs(ratios(b)) do
            out[#out+1]=x
        end;
        return out
    end
    if formulaCommands[cmd] then
        local f=formula(a[1]);
        local c,q,m=f.c,f.q,f.m;
        local es=order(c)
        if cmd=='PARSE' then
            local parts={};
            for _,e in ipairs(es) do
                parts[#parts+1]=e..' '..c[e]
            end;
            return {hill(c,q)..' ('..table.concat(parts,', ')..'; charge '..signed(q)..')'}
        end
        if cmd=='MASS' then
            return {'M('..a[1]..') = '..dec(m,3)..' g/mol'}
        end
        if cmd=='PERCENT' then
            local out={};
            for _,e in ipairs(es) do
                out[#out+1]=e..' '..dec(10000*c[e]*W[e]//m,2)..'%'
            end;
            return out
        end
        if cmd=='EMPIRICAL' then
            local g=0;
            for _,x in pairs(c) do
                g=gcd(g,x)
            end;
            local b={};
            for e,x in pairs(c) do
                b[e]=x//g
            end;
            return {hill(b)..' (n = '..g..')'}
        end
        if cmd=='DBE' then
            if q~=0 then
                fail('charged formula '..a[1])
            end;
            local t=2;
            for _,e in ipairs(es) do
                if not valence[e] then
                    fail('no valence for '..e)
                end;
                t=t+c[e]*(valence[e]-2)
            end;
            return {'DBE = '..(t<0 and '-' or '')..(math.abs(t)//2)..'.'..(t%2~=0 and 5 or 0)}
        end
        if cmd=='OXSTATE' then
            local st,last={},nil;
            local function assign(e,x)
                st[e]=fraction(x);
                last=e
            end
            if #es==1 then
                st[es[1]]=fraction(q,c[es[1]])
            else
                if c.F then
                    assign('F',-1)
                end;
                for _,e in ipairs(es) do
                    if metals[e] then
                        assign(e,metals[e])
                    end
                end
                if c.H then
                    local only=true;
                    for _,e in ipairs(es) do
                        if e~='H' and not metals[e] then
                            only=false
                        end
                    end;
                    assign('H',only and -1 or 1)
                end
                if c.O then
                    assign('O',-2)
                elseif not c.F then
                    for _,e in ipairs({'Cl','Br','I'}) do
                        if c[e] then
                            assign(e,-1);
                            break
                        end
                    end
                end
                local u,sum={},0;
                for _,e in ipairs(es) do
                    if st[e] then
                        sum=sum+c[e]*st[e].n
                    else
                        u[#u+1]=e
                    end
                end
                if #u>1 then
                    return {'indeterminate: '..table.concat(u,' ')}
                end
                if #u==1 then
                    st[u[1]]=fraction(q-sum,c[u[1]])
                elseif sum~=q then
                    st[last]=fraction(q-sum+c[last]*st[last].n,c[last])
                end
            end;
            local out={};
            for _,e in ipairs(es) do
                out[#out+1]=e..' '..fractionText(st[e])
            end;
            return {table.concat(out,', ')}
        end
        if cmd=='SALT' then
            local b=formula(a[2]);
            if q<=0 then
                fail('not a cation '..a[1])
            end;
            if b.q>=0 then
                fail('not an anion '..a[2])
            end;
            for _,s in ipairs(a) do
                if s:find('.',1,true) then
                    fail('hydrate ion '..s)
                end
            end;
            local g=gcd(q,b.q);
            local x,y=-b.q//g,q//g;
            local z=add(scale(c,x),b.c,y);
            return {group(a[1],x)..group(a[2],y)..' ('..hill(z)..', '..dec(mass(z),3)..' g/mol)'}
        end
        if cmd=='MOLECULAR' and q~=0 then
            fail('charged formula '..a[1])
        end;
        local x=quantity(a[2]);
        if cmd=='MOLES' then
            return {dec(x,3)..' g '..a[1]..' = '..dec(x*1000000//m,6)..' mol'}
        end;
        if cmd=='GRAMS' then
            return {dec(x,3)..' mol '..a[1]..' = '..dec(x*m//1000,3)..' g'}
        end;
        local k=(2*x+m)//(2*m);
        if k==0 or 10*math.abs(x-k*m)>m then
            return {'no integer multiple (ratio '..dec(1000*x//m,3)..')'}
        end;
        return {hill(scale(c,k))..' (n = '..k..', '..dec(k*m,3)..' g/mol)'}
    end
    if cmd=='REDOX' or cmd=='HALF' then
        if a[1]~='acidic' and a[1]~='basic' then
            fail('invalid medium '..a[1])
        end;
        local eq=equation(slice(a,2));
        for _,s in ipairs(eq.list) do
            if s.f=='H^+' or s.f=='OH^-' or s.f=='H2O' then
                fail('reserved species '..s.name)
            end
        end
        local list,sign=slice(eq.list,1),slice(eq.sign,1);
        local aux={species(a[1]=='acidic' and 'H^+' or 'OH^-'),species('H2O')};
        if cmd=='HALF' then
            aux[#aux+1]={f='e^-',name='e^-',state='',k=1,c={},q=-1,m=0}
        end;
        for _,s in ipairs(aux) do
            list[#list+1]=s;
            sign[#sign+1]=1
        end
        local v=coefficients(list,sign,#eq.list);
        local left,right={},{};
        for i,s in ipairs(eq.list) do
            local t=i<=eq.r and left or right;
            t[#t+1]=term(s.name,v[i])
        end;
        for i=#eq.list+1,#list do
            if v[i]~=0 then
                local t=v[i]>0 and left or right;
                t[#t+1]=term(list[i].name,math.abs(v[i]))
            end
        end;
        local out={table.concat(left,' + ')..' -> '..table.concat(right,' + ')};
        if cmd=='HALF' then
            out[#out+1]=v[#v]>0 and 'reduction' or v[#v]<0 and 'oxidation' or 'no electron transfer'
        end;
        return out
    end
    local words,rest=a,{}
    if cmd=='STOICH' or cmd=='LIMITING' or cmd=='YIELD' then
        local count,index=0,nil;
        for i,s in ipairs(a) do
            if s==':' then
                count=count+1;
                index=i
            end
        end;
        if count~=1 then
            fail('invalid separator')
        end;
        words=slice(a,1,index-1);
        rest=slice(a,index+1);
        if (cmd=='STOICH' and #rest~=2) or (cmd=='YIELD' and #rest~=4) then
            fail('wrong argument count for '..cmd)
        end
    end
    local eq=equation(words,cmd=='CHECK');
    local list,r,sign=eq.list,eq.r,eq.sign
    if cmd=='MATRIX' then
        local labels,rows=matrix(list,sign);
        local rank,basis=nullspace(rows,#list);
        local names={};
        for _,s in ipairs(list) do
            names[#names+1]=s.name
        end;
        local out={'columns: '..table.concat(names,' ')};
        for i,row in ipairs(rows) do
            out[#out+1]=labels[i]..': '..table.concat(row,' ')
        end;
        out[#out+1]='rank '..rank..', nullity '..#basis;
        for _,v in ipairs(basis) do
            out[#out+1]='null: '..table.concat(v,' ')
        end;
        return out
    end
    if cmd=='CHECK' then
        local labels,rows=matrix(list,sign);
        local diff={};
        for i,row in ipairs(rows) do
            local l,rr=0,0;
            for j,x in ipairs(row) do
                if j<=r then
                    l=l+x*list[j].k
                else
                    rr=rr-x*list[j].k
                end
            end;
            if l~=rr then
                diff[#diff+1]=labels[i]..': '..(labels[i]=='charge' and signed(l) or l)..' != '..(labels[i]=='charge' and signed(rr) or rr)
            end
        end;
        if #diff>0 then
            table.insert(diff,1,'not balanced');
            return diff
        end;
        local g=0;
        for _,s in ipairs(list) do
            g=gcd(g,s.k)
        end;
        return {g==1 and 'balanced' or 'balanced, not in lowest terms (gcd '..g..')'}
    end
    local target,product,qs=nil,nil,{}
    if cmd=='DELTAH' then
        for _,s in ipairs(list) do
            if heats[s.name]==nil then
                fail('no enthalpy for '..s.name)
            end
        end
    end
    if cmd=='STOICH' then
        for i,s in ipairs(list) do
            if s.name==rest[1] then
                target=i;
                break
            end
        end;
        if not target then
            fail('species '..rest[1]..' not in equation')
        end;
        qs={quantity(rest[2])}
    end
    if cmd=='LIMITING' then
        if #rest~=r then
            fail('expected '..r..' masses, got '..#rest)
        end;
        for _,s in ipairs(rest) do
            qs[#qs+1]=quantity(s)
        end
    end
    if cmd=='YIELD' then
        for i=1,r do
            if list[i].name==rest[1] then
                target=i;
                break
            end
        end;
        if not target then
            fail(rest[1]..' is not a reactant')
        end;
        for i=r+1,#list do
            if list[i].name==rest[3] then
                product=i;
                break
            end
        end;
        if not product then
            fail(rest[3]..' is not a product')
        end;
        qs={quantity(rest[2]),quantity(rest[4])}
    end
    local v=coefficients(list,sign);
    local out={notation(eq,v)};
    if cmd=='BALANCE' then
        return out
    end
    if cmd=='DELTAH' then
        local h=0;
        for i,s in ipairs(list) do
            h=h-sign[i]*v[i]*heats[s.name]
        end;
        out[#out+1]='dH = '..ent(h)..' kJ ('..(h<0 and 'exothermic' or h>0 and 'endothermic' or 'thermoneutral')..')';
        return out
    end
    if cmd=='STOICH' then
        local d=v[target]*list[target].m;
        for i,s in ipairs(list) do
            local x=qs[1]*v[i];
            out[#out+1]=s.name..' '..dec(x*1000000//d,6)..' mol '..dec(x*s.m//d,3)..' g'..gas(s,x,d)
        end;
        return out
    end
    if cmd=='YIELD' then
        local t=qs[1]*v[product]*list[product].m//(v[target]*list[target].m);
        out[#out+1]='theoretical '..dec(t,3)..' g';
        out[#out+1]='actual '..dec(qs[2],3)..' g';
        out[#out+1]=t==0 and 'yield undefined' or 'yield '..dec(qs[2]*10000//t,2)..'%';
        return out
    end
    local l=1;
    for i=2,r do
        if qs[i]*v[l]*list[l].m<qs[l]*v[i]*list[i].m then
            l=i
        end
    end;
    local d=v[l]*list[l].m;
    out[#out+1]='limiting '..list[l].name;
    out[#out+1]='extent '..dec(qs[l]*1000000//d,6)..' mol';
    for i=r+1,#list do
        out[#out+1]='product '..list[i].name..' '..dec(qs[l]*v[i]*list[i].m//d,3)..' g'..gas(list[i],qs[l]*v[i],d)
    end;
    for i=1,r do
        if i~=l then
            out[#out+1]='remaining '..list[i].name..' '..dec((qs[i]*d-qs[l]*v[i]*list[i].m)//d,3)..' g'
        end
    end;
    return out
end
local n=tonumber(io.read('*l'));
for _=1,n do
    local ok,out=pcall(execute,io.read('*l'));
    if ok then
        for _,s in ipairs(out) do
            io.write(s,'\n')
        end
    else
        io.write(out,'\n')
    end
end
