const SYMBOLS=split(
    "H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe",
)
const W=Dict(
    zip(
        SYMBOLS,
        [
            1008,
            4003,
            6941,
            9012,
            10811,
            12011,
            14007,
            15999,
            18998,
            20180,
            22990,
            24305,
            26982,
            28086,
            30974,
            32065,
            35453,
            39948,
            39098,
            40078,
            44956,
            47867,
            50942,
            51996,
            54938,
            55845,
            58933,
            58693,
            63546,
            65380,
            69723,
            72630,
            74922,
            78971,
            79904,
            83798,
            85468,
            87620,
            88906,
            91224,
            92906,
            95950,
            98000,
            101070,
            102906,
            106420,
            107868,
            112414,
            114818,
            118710,
            121760,
            127600,
            126904,
            131293,
        ],
    ),
)
const VALENCE=Dict(
    e=>i for (i, es) in
    enumerate([split("H F Cl Br I"), split("O S Se"), split("B N P As"), split("C Si Ge")]) for
    e in es
)
const METALS=Dict("Li"=>1, "Na"=>1, "K"=>1, "Rb"=>1, "Be"=>2, "Mg"=>2, "Ca"=>2, "Sr"=>2, "Al"=>3)
struct ChemError <: Exception
    message::String
end
struct NoCoefficients <: Exception
    message::String
end
fail(s) = throw(ChemError(s))
dec(n, d) = string(div(n, 10^d), ".", lpad(string(mod(n, 10^d)), d, '0'))
ent(n) = (n<0 ? "-" : "")*dec(abs(n), 2)
function signed(n)
    n==0 && return "0"
    x=n//1
    (n>0 ? "+" : "-")*string(abs(numerator(x)))*(
        denominator(x)==1 ? "" : "/"*string(denominator(x))
    )
end
function hillorder(c)
    es=sort!(collect(keys(c)))
    "C" in es ? vcat(["C"], "H" in es ? ["H"] : String[], filter(e->e!="C"&&e!="H", es)) : es
end
function add!(a, b, k = 1)
    for (e, n) in b
        a[e]=get(a, e, 0)+n*k
    end
    a
end
scaled(c, k) = Dict(e=>n*k for (e, n) in c)
mass(c) = sum(n*W[e] for (e, n) in c; init = 0)
hill(c, q = 0) =
    join(e*(c[e]==1 ? "" : string(c[e])) for e in hillorder(c))*(
        q==0 ? "" : "^"*(abs(q)==1 ? "" : string(abs(q)))*(q>0 ? "+" : "-")
    )
struct Formula
    c::Dict{String,Int}
    q::Int
end
struct Species
    f::String
    state::String
    coefficient::Int
    formula::Formula
end
name(s::Species) = s.f*s.state
mass(s::Species) = mass(s.formula.c)
mutable struct Parser
    text::String
    p::Int
    seen::Vector{String}
end
peek(p) = p.p<=lastindex(p.text) ? p.text[p.p] : '\0'
function number!(p)
    start=p.p
    while isdigit(peek(p))
        p.p+=1
    end
    start==p.p && return 1
    p.text[start]=='0' && throw(ArgumentError(""))
    parse(Int, p.text[start:(p.p-1)])
end
function sequence!(p)
    c=Dict{String,Int}()
    items=0
    while true
        ch=peek(p)
        if 'A'<=ch<='Z'
            e=string(ch)
            p.p+=1
            if 'a'<=peek(p)<='z'
                e*=string(peek(p))
                p.p+=1
            end
            push!(p.seen, e)
            item=Dict(e=>1)
        elseif ch=='('||ch=='['
            p.p+=1
            item=sequence!(p)
            peek(p)!=(ch=='(' ? ')' : ']') && throw(ArgumentError(""))
            p.p+=1
        else
            break
        end
        k=number!(p)
        add!(c, item, k)
        items+=1
    end
    items==0 && throw(ArgumentError(""))
    c
end
function formula(text, word = text)
    p=Parser(text, 1, String[])
    c=Dict{String,Int}()
    q=0
    try
        c=sequence!(p)
        while peek(p)=='.'
            p.p+=1
            k=number!(p)
            add!(c, sequence!(p), k)
        end
        if peek(p)=='^'
            p.p+=1
            k=number!(p)
            ch=peek(p)
            !(ch in ['+', '-']) && throw(ArgumentError(""))
            p.p+=1
            q=ch=='+' ? k : -k
        end
        p.p!=length(text)+1 && throw(ArgumentError(""))
    catch e
        e isa ArgumentError || rethrow()
        fail("invalid formula "*word)
    end
    for e in p.seen
        haskey(W, e)||fail("unknown element "*e)
    end
    Formula(c, q)
end
function species(word, check = false)
    state=""
    f=word
    k=1
    for s in ["(s)", "(l)", "(g)", "(aq)"]
        if endswith(word, s)
            state=s
            f=word[1:(end-length(s))]
            break
        end
    end
    if check && (m=match(r"^[0-9]+", f))!==nothing
        startswith(f, "0")&&fail("invalid formula "*word)
        k=parse(Int, m.match)
        f=f[(length(m.match)+1):end]
    end
    Species(f, state, k, formula(f, word))
end
function equation(a, check = false)
    ops=a[2:2:end]
    (
        iseven(length(a))||count(==("->"), ops)!=1||any(x->!(x in ["+", "->"]), ops)||any(
            x->x in ["+", "->"],
            a[1:2:end],
        )
    )&&fail("malformed equation")
    list=[species(x, check) for x in a[1:2:end]]
    r=div(findfirst(==("->"), a), 2)
    (list = list, r = r, sign = [i<=r ? 1 : -1 for i in eachindex(list)])
end
function quantity(s)
    occursin(r"^(0|[1-9][0-9]{0,3})(\.[0-9]{1,3})?$", s)||fail("invalid quantity "*s)
    parts=split(s, '.')
    q=parse(Int, parts[1])*1000+(length(parts)==1 ? 0 : parse(Int, rpad(parts[2], 3, '0')))
    q==0&&fail("invalid quantity "*s)
    q
end
function enthalpy(s)
    occursin(r"^-?(0|[1-9][0-9]{0,4})(\.[0-9]{1,2})?$", s)||fail("invalid enthalpy "*s)
    parts=split(startswith(s, "-") ? s[2:end] : s, '.')
    (startswith(s, "-") ? -1 : 1)*(
        parse(Int, parts[1])*100+(length(parts)==1 ? 0 : parse(Int, rpad(parts[2], 2, '0')))
    )
end
function matrix(list, sign)
    all=Dict{String,Int}()
    for s in list
        add!(all, s.formula.c)
    end
    labels=vcat(hillorder(all), ["charge"])
    rows=[
        [
            sign[i]*(e=="charge" ? s.formula.q : get(s.formula.c, e, 0)) for
            (i, s) in enumerate(list)
        ] for e in labels
    ]
    labels, rows
end
function nullspace(rows, n)
    a=[Rational{Int}.(r) for r in rows]
    piv=Int[]
    free=Int[]
    for j in 1:n
        r=length(piv)+1
        i=findfirst(k->a[k][j]!=0, r:length(a))
        if i===nothing
            push!(free, j)
            continue
        end
        i+=r-1
        a[r], a[i]=a[i], a[r]
        t=a[r][j]
        a[r]=a[r] ./ t
        for k in eachindex(a)
            if k!=r&&a[k][j]!=0
                t=a[k][j]
                a[k]=a[k] .- t .* a[r]
            end
        end
        push!(piv, j)
    end
    basis=Vector{Int}[]
    for f in free
        v=fill(0//1, n)
        v[f]=1//1
        for (i, j) in enumerate(piv)
            v[j]=-a[i][f]
        end
        l=foldl(lcm, denominator.(v); init = 1)
        b=[numerator(x)*div(l, denominator(x)) for x in v]
        g=foldl(gcd, b; init = 0)
        push!(basis, div.(b, g))
    end
    length(piv), basis
end
function coefficients(list, sign, k = length(list))
    _, rows=matrix(list, sign)
    _, basis=nullspace(rows, length(list))
    d=length(basis)
    d>=2&&throw(NoCoefficients("AMBIGUOUS (nullity $d)"))
    d==0&&throw(NoCoefficients("IMPOSSIBLE"))
    v=basis[1]
    v[1]<0&&(v=-v)
    any(<=(0), v[1:k])&&throw(NoCoefficients("IMPOSSIBLE"))
    v
end
term(s, k) = (k==1 ? "" : string(k))*s
function notation(eq, v)
    t=[term(name(s), v[i]) for (i, s) in enumerate(eq.list)]
    join(t[1:eq.r], " + ")*" -> "*join(t[(eq.r+1):end], " + ")
end
gas(s, n, d) = s.state=="(g)" ? " "*dec(div(n*22414, d), 3)*" L" : ""
function ratios(a)
    es=hillorder(a)
    f=es[argmin([a[e]//W[e] for e in es])]
    out=[e*" "*dec(div(1000*a[e]*W[f], W[e]*a[f]), 3) for e in es]
    for k in 1:12
        c=Dict{String,Int}()
        ok=true
        for e in es
            n=k*a[e]*W[f]
            d=W[e]*a[f]
            i=div(2*n+d, 2*d)
            c[e]=i
            20*abs(n-i*d)>d&&(ok=false)
        end
        ok&&return vcat(out, [hill(c)*" (k = $k)"])
    end
    vcat(out, ["no simple ratio"])
end
function group(f, k)
    c=split(f, '^')[1]
    k==1&&return c
    depth=0
    last=0
    if startswith(c, "[")
        for (i, ch) in enumerate(c)
            ch=='['&&(depth+=1)
            if ch==']'
                depth-=1
                if depth==0
                    last=i
                    break
                end
            end
        end
    end
    (occursin(r"^[A-Z][a-z]?$", c)||last==length(c) ? c : "("*c*")")*string(k)
end
const COUNTS=Dict(
    "ELEMENT"=>1,
    "PARSE"=>1,
    "MASS"=>1,
    "PERCENT"=>1,
    "EMPIRICAL"=>1,
    "DBE"=>1,
    "OXSTATE"=>1,
    "MOLES"=>2,
    "GRAMS"=>2,
    "MOLECULAR"=>2,
    "SALT"=>2,
    "HEAT"=>2,
    "COMBUST"=>3,
    "HEATS"=>0,
    "DERIVE"=>-2,
    "BALANCE"=>-1,
    "MATRIX"=>-1,
    "CHECK"=>-1,
    "DELTAH"=>-1,
    "REDOX"=>-3,
    "HALF"=>-3,
    "STOICH"=>-4,
    "LIMITING"=>-4,
    "YIELD"=>-4,
)
function execute(line, heats)
    words=String.(split(line))
    cmd=popfirst!(words)
    a=words
    n=length(a)
    haskey(COUNTS, cmd)||fail("unknown command "*cmd)
    e=COUNTS[cmd]
    ((e>=0&&n!=e)||(e==-1&&n<1)||(e==-2&&(n<2||isodd(n)))||(e==-3&&n<2))&&fail(
        "wrong argument count for "*cmd,
    )
    if cmd=="ELEMENT"
        haskey(W, a[1])||fail("unknown element "*a[1])
        return ["$(a[1]) (Z = $(findfirst(==(a[1]),SYMBOLS))) $(dec(W[a[1]],3)) u"]
    elseif cmd=="HEATS"
        return isempty(heats) ? ["no enthalpies"] :
               [s*" "*ent(heats[s])*" kJ/mol" for s in sort(collect(keys(heats)))]
    elseif cmd=="HEAT"
        species(a[1])
        h=enthalpy(a[2])
        s="dHf($(a[1])) = $(ent(h)) kJ/mol"*(
            haskey(heats, a[1]) ? " (was $(ent(heats[a[1]])))" : ""
        )
        heats[a[1]]=h
        return [s]
    elseif cmd=="DERIVE"
        b=Dict{String,Int}()
        for i in 1:2:n
            s=a[i]
            haskey(W, s)||fail("unknown element "*s)
            haskey(b, s)&&fail("duplicate element "*s)
            q=quantity(a[i+1])
            q>100000&&fail("invalid percentage "*a[i+1])
            b[s]=q
        end
        t=sum(values(b))
        abs(t-100000)>1000&&fail("percentages sum to "*dec(t, 3))
        return ratios(b)
    elseif cmd=="COMBUST"
        s, p, r=quantity.(a)
        c=div(p*12011, 44009)
        h=div(r*2016, 18015)
        o=s-c-h
        (c==0||h==0||100*o < -s)&&fail("inconsistent masses")
        b=Dict("C"=>c, "H"=>h)
        100*o>s&&(b["O"]=o)
        return vcat(["mass $e $(dec(b[e],3)) g" for e in hillorder(b)], ratios(b))
    end
    if cmd in [
        "PARSE",
        "MASS",
        "PERCENT",
        "EMPIRICAL",
        "DBE",
        "OXSTATE",
        "MOLES",
        "GRAMS",
        "MOLECULAR",
        "SALT",
    ]
        f=formula(a[1])
        c=f.c
        q=f.q
        m=mass(c)
        es=hillorder(c)
        cmd=="PARSE"&&return [
            hill(c, q)*" ("*join(["$e $(c[e])" for e in es], ", ")*"; charge "*signed(q)*")",
        ]
        cmd=="MASS"&&return ["M($(a[1])) = $(dec(m,3)) g/mol"]
        cmd=="PERCENT"&&return ["$e $(dec(div(10000*c[e]*W[e],m),2))%" for e in es]
        if cmd=="EMPIRICAL"
            g=foldl(gcd, values(c))
            return [hill(Dict(e=>div(x, g) for (e, x) in c))*" (n = $g)"]
        end
        if cmd=="DBE"
            q!=0&&fail("charged formula "*a[1])
            t=2
            for e in es
                haskey(VALENCE, e)||fail("no valence for "*e)
                t+=c[e]*(VALENCE[e]-2)
            end
            return ["DBE = "*(t<0 ? "-" : "")*string(div(abs(t), 2))*"."*(isodd(t) ? "5" : "0")]
        elseif cmd=="OXSTATE"
            st=Dict{String,Rational{Int}}()
            last=""
            if length(es)==1
                st[es[1]]=q//c[es[1]]
            else
                if haskey(c, "F")
                    st["F"]=-1
                    last="F"
                end
                for e in es
                    if haskey(METALS, e)
                        st[e]=METALS[e]
                        last=e
                    end
                end
                if haskey(c, "H")
                    st["H"]=all(e->e=="H"||haskey(METALS, e), es) ? -1 : 1
                    last="H"
                end
                if haskey(c, "O")
                    st["O"]=-2
                    last="O"
                elseif !haskey(c, "F")
                    for e in ["Cl", "Br", "I"]
                        if haskey(c, e)
                            st[e]=-1
                            last=e
                            break
                        end
                    end
                end
                u=filter(e->!haskey(st, e), es)
                length(u)>1&&return ["indeterminate: "*join(u, " ")]
                total=sum(c[e]*x for (e, x) in st; init = 0//1)
                if !isempty(u)
                    st[u[1]]=(q-total)/c[u[1]]
                elseif total!=q
                    st[last]=(q-total+c[last]*st[last])/c[last]
                end
            end
            return [join([e*" "*signed(st[e]) for e in es], ", ")]
        elseif cmd=="SALT"
            b=formula(a[2])
            q<=0&&fail("not a cation "*a[1])
            b.q>=0&&fail("not an anion "*a[2])
            for s in a
                occursin('.', s)&&fail("hydrate ion "*s)
            end
            g=gcd(q, b.q)
            x=div(-b.q, g)
            y=div(q, g)
            z=add!(scaled(c, x), b.c, y)
            return [group(a[1], x)*group(a[2], y)*" ("*hill(z)*", "*dec(mass(z), 3)*" g/mol)"]
        end
        cmd=="MOLECULAR"&&q!=0&&fail("charged formula "*a[1])
        x=quantity(a[2])
        cmd=="MOLES"&&return ["$(dec(x,3)) g $(a[1]) = $(dec(div(x*1000000,m),6)) mol"]
        cmd=="GRAMS"&&return ["$(dec(x,3)) mol $(a[1]) = $(dec(div(x*m,1000),3)) g"]
        k=div(2*x+m, 2*m)
        (k==0||10*abs(x-k*m)>m)&&return ["no integer multiple (ratio $(dec(div(1000*x,m),3)))"]
        return [hill(scaled(c, k))*" (n = $k, $(dec(k*m,3)) g/mol)"]
    end
    if cmd in ["REDOX", "HALF"]
        a[1] in ["acidic", "basic"]||fail("invalid medium "*a[1])
        eq=equation(a[2:end])
        for s in eq.list
            s.f in ["H^+", "OH^-", "H2O"]&&fail("reserved species "*name(s))
        end
        aux=[species(a[1]=="acidic" ? "H^+" : "OH^-"), species("H2O")]
        cmd=="HALF"&&push!(aux, Species("e^-", "", 1, Formula(Dict{String,Int}(), -1)))
        list=vcat(eq.list, aux)
        v=coefficients(list, vcat(eq.sign, ones(Int, length(aux))), length(eq.list))
        left=String[]
        right=String[]
        for i in eachindex(eq.list)
            push!(i<=eq.r ? left : right, term(name(list[i]), v[i]))
        end
        for i in (length(eq.list)+1):length(list)
            v[i]!=0&&push!(v[i]>0 ? left : right, term(name(list[i]), abs(v[i])))
        end
        out=[join(left, " + ")*" -> "*join(right, " + ")]
        cmd=="HALF"&&push!(
            out,
            v[end]>0 ? "reduction" : v[end]<0 ? "oxidation" : "no electron transfer",
        )
        return out
    end
    words=a
    rest=String[]
    if cmd in ["STOICH", "LIMITING", "YIELD"]
        count(==(":"), a)==1||fail("invalid separator")
        i=findfirst(==(":"), a)
        words=a[1:(i-1)]
        rest=a[(i+1):end]
        ((cmd=="STOICH"&&length(rest)!=2)||(cmd=="YIELD"&&length(rest)!=4))&&fail(
            "wrong argument count for "*cmd,
        )
    end
    eq=equation(words, cmd=="CHECK")
    list=eq.list
    r=eq.r
    if cmd=="MATRIX"
        labels, rows=matrix(list, eq.sign)
        rank, basis=nullspace(rows, length(list))
        return vcat(
            ["columns: "*join(name.(list), " ")],
            [labels[i]*": "*join(row, " ") for (i, row) in enumerate(rows)],
            ["rank $rank, nullity $(length(basis))"],
            ["null: "*join(v, " ") for v in basis],
        )
    elseif cmd=="CHECK"
        labels, rows=matrix(list, eq.sign)
        diff=String[]
        for (i, row) in enumerate(rows)
            l=sum(row[j]*list[j].coefficient for j in 1:r)
            rr=-sum(row[j]*list[j].coefficient for j in (r+1):length(list))
            l!=rr&&push!(
                diff,
                labels[i]*": "*(labels[i]=="charge" ? signed(l) : string(l))*" != "*(
                    labels[i]=="charge" ? signed(rr) : string(rr)
                ),
            )
        end
        !isempty(diff)&&return vcat(["not balanced"], diff)
        g=foldl(gcd, [s.coefficient for s in list])
        return [g==1 ? "balanced" : "balanced, not in lowest terms (gcd $g)"]
    end
    qs=Int[]
    target=nothing
    product=nothing
    if cmd=="DELTAH"
        for s in list
            haskey(heats, name(s))||fail("no enthalpy for "*name(s))
        end
    elseif cmd=="STOICH"
        target=findfirst(s->name(s)==rest[1], list)
        target===nothing&&fail("species $(rest[1]) not in equation")
        qs=[quantity(rest[2])]
    elseif cmd=="LIMITING"
        length(rest)==r||fail("expected $r masses, got $(length(rest))")
        qs=quantity.(rest)
    elseif cmd=="YIELD"
        target=findfirst(i->name(list[i])==rest[1], 1:r)
        target===nothing&&fail(rest[1]*" is not a reactant")
        product=findfirst(i->name(list[i])==rest[3], (r+1):length(list))
        product===nothing&&fail(rest[3]*" is not a product")
        product+=r
        qs=[quantity(rest[2]), quantity(rest[4])]
    end
    v=coefficients(list, eq.sign)
    out=[notation(eq, v)]
    cmd=="BALANCE"&&return out
    if cmd=="DELTAH"
        h=sum(-eq.sign[i]*v[i]*heats[name(list[i])] for i in eachindex(list))
        push!(
            out,
            "dH = $(ent(h)) kJ ("*(h<0 ? "exothermic" : h>0 ? "endothermic" : "thermoneutral")*")",
        )
    elseif cmd=="STOICH"
        d=v[target]*mass(list[target])
        append!(
            out,
            [
                "$(name(s)) $(dec(div(qs[1]*v[i]*1000000,d),6)) mol $(dec(div(qs[1]*v[i]*mass(s),d),3)) g"*gas(
                    s,
                    qs[1]*v[i],
                    d,
                ) for (i, s) in enumerate(list)
            ],
        )
    elseif cmd=="YIELD"
        t=div(qs[1]*v[product]*mass(list[product]), v[target]*mass(list[target]))
        append!(
            out,
            [
                "theoretical $(dec(t,3)) g",
                "actual $(dec(qs[2],3)) g",
                t==0 ? "yield undefined" : "yield $(dec(div(qs[2]*10000,t),2))%",
            ],
        )
    else
        l=argmin([qs[i]//(v[i]*mass(list[i])) for i in 1:r])
        d=v[l]*mass(list[l])
        append!(out, ["limiting "*name(list[l]), "extent $(dec(div(qs[l]*1000000,d),6)) mol"])
        for i in (r+1):length(list)
            push!(
                out,
                "product $(name(list[i])) $(dec(div(qs[l]*v[i]*mass(list[i]),d),3)) g"*gas(
                    list[i],
                    qs[l]*v[i],
                    d,
                ),
            )
        end
        for i in 1:r
            i!=l&&push!(
                out,
                "remaining $(name(list[i])) $(dec(div(qs[i]*d-qs[l]*v[i]*mass(list[i]),d),3)) g",
            )
        end
    end
    out
end
function main()
    heats=Dict{String,Int}()
    for _ in 1:parse(Int, readline())
        line=readline()
        try
            foreach(println, execute(line, heats))
        catch e
            if e isa ChemError
                println("error: ", e.message)
            elseif e isa NoCoefficients
                println(e.message)
            else
                rethrow()
            end
        end
    end
end
main()
