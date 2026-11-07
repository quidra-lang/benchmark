include("molecule.jl")
include("smiles_parser.jl")
include("rings_aromatic.jl")
include("canonical.jl")
include("search.jl")
const QUERY_COUNTS = Dict("MATCH" => (1,1), "CONTAINS" => (2,2), "MATRIX" => (2,12),
    "NEAREST" => (2,2), "WITHIN" => (2,2), "COMPARE" => (2,2), "CLUSTER" => (1,1))
const SYSTEM_KINDS = ["isolated", "fused", "spiro", "bridged"]
line(parts...) = join(string.(parts), " ")
kv(key, value) = string(key, "=", value)
valid_name(value) = occursin(r"^[A-Za-z0-9_-]{1,32}$", value)
function valid_number(value, low, high)
    occursin(r"^(0|[1-9][0-9]*)$", value) || return false
    length(value) <= length(string(high)) || return false
    low <= parse(Int, value) <= high
end
function data_lines(name)
    [(number=i, text=text) for (i,text) in enumerate(readlines(joinpath("input", name)))
        if !isempty(text) && !startswith(text, "#")]
end
function threshold(value)
    parts = split(value, '/'; keepempty=true)
    length(parts) == 2 || return nothing
    (valid_number(parts[1],0,99) && valid_number(parts[2],1,99)) || return nothing
    p,q = parse.(Int, parts)
    p <= q ? (p,q) : nothing
end
function fraction_text(value)
    p,q = value
    divisor = gcd(p,q)
    string(p ÷ divisor, "/", q ÷ divisor)
end
fraction_compare(a,b) = cmp(a[1]*b[2], b[1]*a[2])
member_names(molecules) = join([m.name for m in molecules], ",")
cause!(causes, reason) = (causes[reason] = get(causes,reason,0) + 1)
function analyze!(m)
    find_rings!(m)
    for bond in ordered_bonds(m)
        a,b = bond.ends
        bond.kind = bond.symbol === nothing ?
            (bond.ring && m.atoms[a].aromatic && m.atoms[b].aromatic ? 4 : 1) : BOND_TYPES[bond.symbol]
    end
    kekulize!(m, [a for a in eachindex(m.atoms) if needs_pi(m,a)])
    for (a,atom) in enumerate(m.atoms)
        total = bond_total(m,a)
        if atom.bracket
            total + atom.hydrogens > atom.element.valences[end] + abs(atom.charge) &&
                analysis_error("bad valence",atom.column)
        else
            hydrogens = organic_hydrogens(atom,total)
            hydrogens === nothing && analysis_error("bad valence",atom.column)
            atom.hydrogens = hydrogens
        end
    end
end
function molecular_properties(m)
    counts = Dict{String,Int}()
    hydrogens,weight = 0,0
    for atom in m.atoms
        symbol = atom.element.symbol
        counts[symbol] = get(counts,symbol,0) + 1
        hydrogens += atom.hydrogens
        weight += atom.mass == 0 ? atom.element.weight : atom.mass*1000
    end
    counts["H"] = get(counts,"H",0) + hydrogens
    weight += hydrogens*m.elements["H"].weight
    symbols = sort([s for (s,n) in counts if n > 0])
    if get(counts,"C",0) > 0
        prefix = get(counts,"H",0) > 0 ? ["C","H"] : ["C"]
        symbols = [prefix; [s for s in symbols if !(s in ["C","H"])]]
    end
    formula = join([s * (counts[s] == 1 ? "" : string(counts[s])) for s in symbols])
    heavy = count(a -> a.element.symbol != "H",m.atoms)
    heavy_degrees = [count(b -> m.atoms[b].element.symbol != "H",neighbor_numbers(m,a)) for a in eachindex(m.atoms)]
    triple_ends = Set(a for b in ordered_bonds(m) if b.multiplicity == 3 for a in b.ends)
    rotatable = count(ordered_bonds(m)) do bond
        a,b = bond.ends
        bond.multiplicity == 1 && !bond.ring && heavy_degrees[a] >= 2 && heavy_degrees[b] >= 2 &&
            !(a in triple_ends) && !(b in triple_ends)
    end
    donors,acceptors = 0,0
    for (a,atom) in enumerate(m.atoms)
        atom.element.symbol in ("N","O") || continue
        acceptors += 1
        attached = atom.hydrogens + count(b -> m.atoms[b].element.symbol == "H",neighbor_numbers(m,a))
        donors += attached >= 1
    end
    violations = Int(weight > 500000) + Int(donors > 5) + Int(acceptors > 10)
    (formula=formula, weight=weight, heavy=heavy, rotatable=rotatable, donors=donors, acceptors=acceptors,
        lipinski=violations <= 1 ? "pass" : "fail", charge=sum(a.charge for a in m.atoms))
end
function scaffold_molecule(m)
    isempty(m.rings) && return nothing
    remaining = Set(eachindex(m.atoms))
    while true
        candidates = sort(collect(setdiff(remaining,m.ring_atoms)))
        leaf = findfirst(a -> count(b -> b in remaining,neighbor_numbers(m,a)) == 1,candidates)
        leaf === nothing && break
        delete!(remaining,candidates[leaf])
    end
    kept = copy(remaining)
    for a in remaining, b in neighbor_numbers(m,a)
        !(b in remaining) && m.neighbors[a][b].kind == 2 && push!(kept,b)
    end
    scaffold = new_molecule(m.elements)
    renumber = Dict{Int,Int}()
    for a in sort(collect(kept))
        original = m.atoms[a]
        added = sum((m.neighbors[a][b].multiplicity for b in neighbor_numbers(m,a) if !(b in kept)); init=0)
        atom = ChemAtom(original.element,original.aromatic,original.mass,original.charge,
            original.hydrogens + added,original.bracket,original.column)
        renumber[a] = add_atom!(scaffold,atom)
    end
    for original in ordered_bonds(m)
        a,b = original.ends
        (a in kept && b in kept) || continue
        bond = add_bond!(scaffold,renumber[a],renumber[b],original.symbol)
        bond.kind,bond.multiplicity,bond.ring = original.kind,original.multiplicity,original.ring
    end
    scaffold.rings = [[renumber[a] for a in ring] for ring in m.rings]
    scaffold.ring_atoms = Set(renumber[a] for a in m.ring_atoms)
    scaffold
end
function ring_systems(m)
    sets = Set.(m.rings)
    connections = [Int[] for _ in sets]
    relations = Dict{Tuple{Int,Int},String}()
    for i in eachindex(sets), j in (i+1):length(sets)
        shared = sort(collect(intersect(sets[i],sets[j])))
        isempty(shared) && continue
        push!(connections[i],j)
        push!(connections[j],i)
        relations[(i,j)] = length(shared) == 1 ? "spiro" :
            length(shared) == 2 && haskey(m.neighbors[shared[1]],shared[2]) ? "fused" : "bridged"
    end
    systems = Any[]
    remaining = Set(eachindex(sets))
    while !isempty(remaining)
        start = minimum(remaining)
        delete!(remaining,start)
        queue,head = [start],1
        while head <= length(queue)
            i = queue[head]
            head += 1
            for j in sort(connections[i])
                j in remaining || continue
                delete!(remaining,j)
                push!(queue,j)
            end
        end
        members = Set(queue)
        kinds = Set(kind for ((i,j),kind) in relations if i in members && j in members)
        kind = length(queue) == 1 ? "isolated" : "bridged" in kinds ? "bridged" : "fused" in kinds ? "fused" : "spiro"
        atoms = Set(a for i in queue for a in sets[i])
        push!(systems,(rings=sort(queue),atoms=length(atoms),kind=kind))
    end
    systems
end
function read_molecules(elements,causes)
    molecules,errors,reserved = ChemMolecule[],String[],Set{String}()
    lines = data_lines("molecules.smi")
    for record in lines
        tokens = split(record.text,' ';keepempty=true)
        if length(tokens) != 2 || isempty(tokens[1]) || !valid_name(tokens[2])
            push!(errors,line("line",string(record.number,":"),"bad line"))
            cause!(causes,"bad line")
            continue
        end
        smiles,name = String.(tokens)
        if name in reserved
            push!(errors,line("line",record.number,name * ": duplicate name"))
            cause!(causes,"duplicate name")
            continue
        end
        push!(reserved,name)
        molecule = try
            parsed = parse_smiles(smiles,elements)
            analyze!(parsed)
            parsed
        catch error
            error isa AnalysisError || rethrow()
            push!(errors,line("line",record.number,name * ":",error.reason,"at column",error.column))
            cause!(causes,error.reason)
            continue
        end
        molecule.name,molecule.order = name,length(molecules) + 1
        molecule.properties = molecular_properties(molecule)
        molecule.canonical,molecule.classes = canonicalize(molecule)
        scaffold = scaffold_molecule(molecule)
        molecule.scaffold = scaffold === nothing ? nothing : canonicalize(scaffold)[1]
        molecule.systems = ring_systems(molecule)
        molecule.aromatic_rings = [all(molecule.atoms[a].aromatic for a in r) for r in molecule.rings]
        molecule.bits,molecule.paths = fingerprint(molecule)
        push!(molecules,molecule)
    end
    paragraph = [line("MOLECULES",kv("lines",length(lines)),kv("valid",length(molecules)),kv("errors",length(errors))); errors]
    molecules,paragraph
end
function check_query(kind,args,elements,by_name)
    low,high = QUERY_COUNTS[kind]
    low <= length(args) <= high || return "bad arguments",nothing
    extra = nothing
    if kind == "MATCH"
        try
            extra = parse_smiles(args[1],elements;pattern=true)
        catch error
            error isa AnalysisError || rethrow()
            return line("bad pattern",error.reason,"at column",error.column),nothing
        end
    elseif kind == "CLUSTER"
        extra = threshold(args[1])
        extra === nothing && return "bad threshold",nothing
    elseif kind in ["CONTAINS","MATRIX","COMPARE"]
        for name in args
            haskey(by_name,name) || return "unknown molecule " * name,nothing
        end
        length(unique(args)) == length(args) || return "repeated molecule",nothing
    else
        haskey(by_name,args[1]) || return "unknown molecule " * args[1],nothing
        if kind == "NEAREST"
            valid_number(args[2],1,99) || return "bad count",nothing
            extra = parse(Int,args[2])
        else
            extra = threshold(args[2])
            extra === nothing && return "bad threshold",nothing
        end
    end
    "",extra
end
function read_queries(elements,by_name,causes)
    queries,errors,reserved = Any[],String[],Set{String}()
    lines = data_lines("queries.txt")
    for record in lines
        tokens = String.(split(record.text,' ';keepempty=true))
        kind = tokens[1]
        id = length(tokens) >= 2 ? tokens[2] : ""
        reason,extra = "",nothing
        if !haskey(QUERY_COUNTS,kind)
            reason = "unknown query"
        elseif !valid_name(id)
            reason = "bad id"
        elseif id in reserved
            reason = "duplicate id"
        else
            push!(reserved,id)
            reason,extra = check_query(kind,tokens[3:end],elements,by_name)
        end
        if isempty(reason)
            push!(queries,(kind=kind,id=id,args=tokens[3:end],extra=extra))
        else
            prefix = reason == "unknown query" ? line("line",string(record.number,":")) :
                reason == "bad id" ? line("line",record.number,kind * ":") : line("line",record.number,kind,id * ":")
            push!(errors,line(prefix,reason))
            cause!(causes,startswith(reason,"bad pattern ") ? "bad pattern" :
                startswith(reason,"unknown molecule ") ? "unknown molecule" : reason)
        end
    end
    paragraph = [line("QUERIES",kv("lines",length(lines)),kv("valid",length(queries)),kv("errors",length(errors))); errors]
    queries,paragraph
end
function properties_lines(molecules)
    lines = ["name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"]
    for m in molecules
        p = m.properties
        weight = string(p.weight ÷ 1000,".",lpad(string(p.weight % 1000),3,'0'))
        push!(lines,join([m.name,p.formula,weight,p.heavy,length(m.rings),p.rotatable,p.donors,p.acceptors,p.lipinski],","))
    end
    lines
end
function canonical_paragraphs(molecules)
    by_canonical,by_formula,by_scaffold = [Dict{String,Vector{ChemMolecule}}() for _ in 1:3]
    canonical_keys,formula_keys = String[],String[]
    acyclic = 0
    for m in molecules
        if !haskey(by_canonical,m.canonical)
            by_canonical[m.canonical] = ChemMolecule[]
            push!(canonical_keys,m.canonical)
        end
        push!(by_canonical[m.canonical],m)
        formula = m.properties.formula
        if !haskey(by_formula,formula)
            by_formula[formula] = ChemMolecule[]
            push!(formula_keys,formula)
        end
        push!(by_formula[formula],m)
        if m.scaffold === nothing
            acyclic += 1
        else
            push!(get!(by_scaffold,m.scaffold,ChemMolecule[]),m)
        end
    end
    canonical = [line("CANONICAL",kv("molecules",length(molecules)),kv("unique",length(by_canonical)))]
    for m in molecules
        charge = m.properties.charge
        push!(canonical,line(m.name,m.canonical,kv("classes",m.classes),kv("charge",charge > 0 ? "+" * string(charge) : string(charge))))
    end
    duplicate_keys = [key for key in canonical_keys if length(by_canonical[key]) >= 2]
    duplicates = [line("DUPLICATES",kv("groups",length(duplicate_keys)),
        kv("molecules",sum((length(by_canonical[key]) for key in duplicate_keys);init=0)))]
    for (i,key) in enumerate(duplicate_keys)
        push!(duplicates,line("group",i,key,kv("members",member_names(by_canonical[key]))))
    end
    isomer_keys = [key for key in formula_keys if length(unique([m.canonical for m in by_formula[key]])) >= 2]
    isomers = [line("ISOMERS",kv("groups",length(isomer_keys)))]
    for (i,key) in enumerate(isomer_keys)
        forms = length(unique([m.canonical for m in by_formula[key]]))
        push!(isomers,line("isomer",i,key,kv("forms",forms),kv("members",member_names(by_formula[key]))))
    end
    scaffolds = [line("SCAFFOLDS",kv("distinct",length(by_scaffold)),kv("acyclic",acyclic))]
    scaffold_keys = sort(collect(keys(by_scaffold));by=key -> (-length(by_scaffold[key]),key))
    for (i,key) in enumerate(scaffold_keys)
        push!(scaffolds,line("scaffold",i,key,kv("count",length(by_scaffold[key])),kv("members",member_names(by_scaffold[key]))))
    end
    [canonical,duplicates,isomers,scaffolds]
end
function ring_paragraphs(molecules)
    paragraphs = Vector{String}[]
    sizes,kinds = Dict{Int,Int}(),Dict(kind => 0 for kind in SYSTEM_KINDS)
    aromatic_total,ring_total = 0,0
    for m in molecules
        isempty(m.rings) && continue
        aromatic_total += count(m.aromatic_rings)
        ring_total += length(m.rings)
        paragraph = [line("MOLECULE",m.name,kv("atoms",length(m.atoms)),kv("bonds",length(m.bonds)),
            kv("rings",length(m.rings)),kv("aromatic",count(m.aromatic_rings)),kv("systems",length(m.systems)),
            kv("ring_atoms",length(m.ring_atoms)),kv("ring_bonds",count(b -> b.ring,ordered_bonds(m))))]
        for (i,ring) in enumerate(m.rings)
            push!(paragraph,line("ring",i,kv("size",length(ring)),kv("aromatic",m.aromatic_rings[i] ? "yes" : "no"),
                kv("hetero",count(a -> m.atoms[a].element.symbol != "C",ring)),kv("atoms",join(ring,"-"))))
            sizes[length(ring)] = get(sizes,length(ring),0) + 1
        end
        for (i,system) in enumerate(m.systems)
            kinds[system.kind] += 1
            push!(paragraph,line("system",i,kv("kind",system.kind),kv("rings",join(system.rings,",")),kv("atoms",system.atoms)))
        end
        doubles = [join(b.ends,"=") for b in ordered_bonds(m) if b.kind == 4 && b.multiplicity == 2]
        push!(paragraph,line("kekule",isempty(doubles) ? "-" : join(doubles," ")))
        push!(paragraphs,paragraph)
    end
    summary = [line("SUMMARY",kv("molecules",length(molecules)),kv("cyclic",length(paragraphs)),kv("rings",ring_total),kv("aromatic",aromatic_total))]
    push!(summary,line("sizes",isempty(sizes) ? "-" : join([kv(k,sizes[k]) for k in sort(collect(keys(sizes)))]," ")))
    push!(summary,line("systems",join([kv(k,kinds[k]) for k in SYSTEM_KINDS]," ")))
    push!(paragraphs,summary)
    paragraphs
end
function substructure_paragraphs(queries,molecules,by_name)
    paragraphs = Vector{String}[]
    patterns,hits,contains,found = 0,0,0,0
    for query in queries
        kind,id,args = query.kind,query.id,query.args
        if kind == "MATCH"
            patterns += 1
            matches = [(m,embeddings(query.extra,m)) for m in molecules]
            filter!(r -> r[2].count > 0,matches)
            hits += length(matches)
            total = sum((r[2].count for r in matches);init=0)
            paragraph = [line("MATCH",id,args[1],kv("atoms",length(query.extra.atoms)),
                kv("bonds",length(query.extra.bonds)),kv("hits",length(matches)),kv("embeddings",total))]
            for (m,result) in matches
                push!(paragraph,line(m.name,kv("count",result.count),kv("unique",result.unique),kv("map",join(result.mapping,","))))
            end
            if !isempty(matches)
                top = matches[argmax([r[2].count for r in matches])]
                push!(paragraph,line("top",top[1].name,kv("count",top[2].count)))
            end
            push!(paragraphs,paragraph)
        elseif kind == "CONTAINS"
            contains += 1
            result = embeddings(molecule_pattern(by_name[args[1]]),by_name[args[2]])
            text = line("CONTAINS",id,args[1],args[2],kv("result",result.count > 0 ? "yes" : "no"))
            if result.count > 0
                found += 1
                text = line(text,kv("count",result.count),kv("unique",result.unique),kv("map",join(result.mapping,",")))
            end
            push!(paragraphs,[text])
        end
    end
    push!(paragraphs,[line("SUMMARY",kv("patterns",patterns),kv("hits",hits),kv("contains",contains),kv("found",found))])
    paragraphs
end
function similarity_paragraphs(queries,molecules,by_name)
    fingerprints = [line("FINGERPRINTS",kv("molecules",length(molecules)),"size=1024 depth=5")]
    append!(fingerprints,[line(m.name,kv("bits",length(m.bits)),kv("paths",m.paths)) for m in molecules])
    paragraphs = [fingerprints]
    cache = Dict{Tuple{Int,Int},Tuple{Int,Int}}()
    function similarity(a,b)
        get!(cache,bond_key(a.order,b.order)) do
            tanimoto(a.bits,b.bits)
        end
    end
    for query in queries
        kind,id,args = query.kind,query.id,query.args
        paragraph = String[]
        if kind == "MATRIX"
            selected = [by_name[name] for name in args]
            push!(paragraph,line("MATRIX",id,kv("size",length(selected))))
            for a in selected
                push!(paragraph,line("row",a.name,join([fraction_text(similarity(a,b)) for b in selected]," ")))
            end
            best_i,best_j,best = 1,2,similarity(selected[1],selected[2])
            for i in eachindex(selected), j in (i+1):length(selected)
                value = similarity(selected[i],selected[j])
                if fraction_compare(value,best) > 0
                    best_i,best_j,best = i,j,value
                end
            end
            push!(paragraph,line("best",selected[best_i].name,selected[best_j].name,fraction_text(best)))
        elseif kind in ["NEAREST","WITHIN"]
            source = by_name[args[1]]
            neighbors = [(m,similarity(source,m)) for m in molecules if m !== source]
            sort!(neighbors;lt=(a,b) -> fraction_compare(a[2],b[2]) == 0 ?
                a[1].order < b[1].order : fraction_compare(a[2],b[2]) > 0)
            result = kind == "NEAREST" ? neighbors[1:min(query.extra,length(neighbors))] :
                [r for r in neighbors if fraction_compare(r[2],query.extra) >= 0]
            heading = kind == "NEAREST" ? line(kind,id,source.name,kv("count",length(result))) :
                line(kind,id,source.name,kv("threshold",fraction_text(query.extra)),kv("count",length(result)))
            push!(paragraph,heading)
            for (i,(m,value)) in enumerate(result)
                push!(paragraph,line(i,m.name,fraction_text(value),kv("common",value[1])))
            end
        elseif kind == "COMPARE"
            a,b = by_name[args[1]],by_name[args[2]]
            value = similarity(a,b)
            push!(paragraph,line(kind,id,a.name,b.name,kv("bits",string(length(a.bits),",",length(b.bits))),
                kv("common",value[1]),kv("union",value[2]),kv("tanimoto",fraction_text(value)),
                kv("identical",a.canonical == b.canonical ? "yes" : "no")))
        elseif kind == "CLUSTER"
            neighbors = [[b.order for b in molecules if b !== a && fraction_compare(similarity(a,b),query.extra) >= 0] for a in molecules]
            order = sort(collect(eachindex(molecules));by=i -> (-length(neighbors[i]),i))
            assigned,clusters = Set{Int}(),Vector{Int}[]
            for center in order
                center in assigned && continue
                members = [center;[i for i in neighbors[center] if !(i in assigned)]]
                push!(clusters,members)
                union!(assigned,members)
            end
            push!(paragraph,line(kind,id,kv("threshold",fraction_text(query.extra)),
                kv("clusters",length(clusters)),kv("singletons",count(c -> length(c) == 1,clusters))))
            number = 0
            for members in clusters
                length(members) == 1 && continue
                number += 1
                push!(paragraph,line("cluster",number,kv("centroid",molecules[members[1]].name),
                    kv("size",length(members)),kv("members",member_names(molecules[members]))))
            end
        else
            continue
        end
        push!(paragraphs,paragraph)
    end
    paragraphs
end
paragraphs_text(paragraphs) = join([join(p,"\n") for p in paragraphs],"\n\n") * "\n"
function main()
    elements = read_elements()
    causes = Dict{String,Int}()
    molecules,molecule_errors = read_molecules(elements,causes)
    by_name = Dict(m.name => m for m in molecules)
    queries,query_errors = read_queries(elements,by_name,causes)
    causes_lines = [line("CAUSES",kv("kinds",length(causes)))]
    append!(causes_lines,[kv(reason,causes[reason]) for reason in sort(collect(keys(causes));by=r -> (-causes[r],r))])
    reports = [("properties.csv",join(properties_lines(molecules),"\n") * "\n"),
        ("canonical.txt",paragraphs_text(canonical_paragraphs(molecules))),
        ("rings.txt",paragraphs_text(ring_paragraphs(molecules))),
        ("substructure.txt",paragraphs_text(substructure_paragraphs(queries,molecules,by_name))),
        ("similarity.txt",paragraphs_text(similarity_paragraphs(queries,molecules,by_name))),
        ("errors.txt",paragraphs_text([molecule_errors,query_errors,causes_lines]))]
    mkpath("output")
    for (name,text) in reports
        write(joinpath("output",name),text)
    end
end
main()
