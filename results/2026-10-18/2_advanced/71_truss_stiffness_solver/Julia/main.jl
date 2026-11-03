include("model_io.jl")
include("assembly.jl")
include("solver.jl")
include("postprocess.jl")
include("design.jl")
using Printf

words(parts...) = join(string.(parts)," ")
function ordered_total(items)
    value = 0.0
    for item in items
        value += item
    end
    value
end
function format_real(value,digits=4)
    text = Printf.format(Printf.Format("%.$(digits)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
rounded(value) = parse(Float64,format_real(value))
function extreme_index(entries,minimum_value=false)
    index = 1
    for i in 2:length(entries)
        if minimum_value ? rounded(entries[i])<rounded(entries[index]) : rounded(entries[i])>rounded(entries[index])
            index = i
        end
    end
    index
end
function renumber(nodes,members)
    neighbors = [Set{Int}() for _ in nodes]
    for m in members
        push!(neighbors[m.start],m.finish)
        push!(neighbors[m.finish],m.start)
    end
    key(v) = (length(neighbors[v]),nodes[v].id)
    queue = [argmin(key,eachindex(nodes))]
    visited,head = Set(queue),1
    while head<=length(queue)
        v = queue[head]
        head += 1
        following = sort!(collect(setdiff(neighbors[v],visited));by=key)
        append!(queue,following)
        union!(visited,following)
    end
    reverse(queue),neighbors
end
function numbering_metrics(numbers,neighbors,members)
    bandwidth = maximum(abs(numbers[m.start]-numbers[m.finish]) for m in members)
    profile = sum(numbers[v]-minimum(numbers[u] for u in union(
        neighbors[v],
        Set([v])
    )) for v in eachindex(neighbors))
    bandwidth,profile
end
function truss_context(model)
    nodes,members,settings = model.nodes,model.members,model.settings
    order,neighbors = renumber(nodes,members)
    numbers = zeros(Int,length(nodes))
    for (i,v) in enumerate(order)
        numbers[v] = i-1
    end
    node_dofs = [[2n+1,2n+2] for n in numbers]
    degrees = 2length(nodes)
    owners = fill((0,0),degrees)
    for (v,directions) in enumerate(node_dofs),axis in 1:2
        owners[directions[axis]] = (v,axis)
    end
    prescribed,support_directions = zeros(degrees),NTuple{3,Int}[]
    for support in model.supports,axis in 1:2
        if support.fixed[axis]==1
            d = node_dofs[support.node][axis]
            prescribed[d] = support.prescribed[axis]
            push!(support_directions,(support.node,axis,d))
        end
    end
    restrained = sort!([d for (_,_,d) in support_directions])
    free = setdiff(collect(1:degrees),restrained)
    geometry = member_geometry(nodes,members,node_dofs)
    group_order = unique([m.group for m in members])
    groups = [[i for (i,m) in enumerate(members) if m.group==name] for name in group_order]
    definitions = Dict(c.name=>c for c in model.combinations)
    result_order = [("case",c.name) for c in model.cases]
    append!(result_order,[("combination",c.name) for c in model.combinations])
    deck = settings["deck"]
    deck_x = [nodes[v].x for v in deck]
    (;model,nodes,members,settings,order,neighbors,numbers,node_dofs,degrees,owners,prescribed,support_directions,
        restrained,free,geometry,group_order,groups,definitions,result_order,deck,deck_x,units=Dict{Int,NamedTuple}())
end
function build_system(a,choices,removed=0)
    properties = member_properties(a.model,choices,a.geometry)
    matrix = assemble(a.geometry,properties,a.degrees,removed)
    free_matrix = matrix[a.free,a.free]
    lower,unstable = factor_cholesky(free_matrix,a.free)
    (;properties,matrix,free_matrix,lower,unstable,removed)
end
function displacement(a,system,force,settlement=false)
    result = zeros(a.degrees)
    for d in a.restrained
        result[d] = settlement ? a.prescribed[d] : 0.0
    end
    right = Float64[]
    for d in a.free
        value = force[d]
        for r in a.restrained
            value -= system.matrix[d,r]*result[r]
        end
        push!(right,value)
    end
    result[a.free] = solve_cholesky(system.lower,right)
    result
end
function case_result(a,system,case)
    loading = load_vectors(case,a.geometry,system.properties,a.node_dofs,a.degrees,system.removed)
    d = displacement(a,system,loading.total,loading.settlement)
    forces = axial_forces(a.geometry,system.properties,d,loading.temperature,system.removed)
    reactions = support_reactions(system.matrix,d,loading.total,a.restrained)
    (name=case.name,displacement=d,forces=forces,reactions=reactions,external=loading.external)
end
function analyze(a,system,combination=nothing)
    combinations = isnothing(combination) ? a.model.combinations : [combination]
    needed = Set(name for item in combinations for (name,_) in item.terms)
    results = Dict{String,NamedTuple}()
    for case in a.model.cases
        (isnothing(combination) || case.name in needed) && (results[case.name]=case_result(a,system,case))
    end
    for item in combinations
        results[item.name] = superpose(item,results)
    end
    results
end
function unit_result(a,node)
    get!(a.units,node) do
        force = zeros(a.degrees)
        force[a.node_dofs[node][2]] = -1000.0
        d = displacement(a,a.final_system,force)
        forces = axial_forces(a.geometry,a.properties,d,zeros(length(a.members)))
        reactions = support_reactions(a.final_system.matrix,d,force,a.restrained)
        (name="unit",displacement=d,forces=forces,reactions=reactions,external=force)
    end
end
function design_sections(a)
    choices = [m.section for m in a.members]
    history = String[]
    for round_number in 1:10
        system = build_system(a,choices)
        results = analyze(a,system)
        combinations = [results[c.name] for c in a.model.combinations]
        limits = [slenderness_limit(i,combinations,a.settings["slenderness"]) for i in eachindex(a.members)]
        utilizations = [[utilization(r.forces[i],p,g) for r in combinations] for (i,(p,g)) in enumerate(zip(
            system.properties,
            a.geometry
        ))]
        pairs = [(u,i,j) for (i,row) in enumerate(utilizations) for (j,u) in enumerate(row)]
        maximum_item = pairs[extreme_index(first.(pairs))]
        weight = ordered_total(member_weight(p,g) for (p,g) in zip(system.properties,a.geometry))
        changes = NamedTuple[]
        for (group,indices) in enumerate(a.groups)
            chosen = select_section(indices,a.model.sections,system.properties,a.geometry,combinations,limits)
            current = choices[indices[1]]
            if chosen!=current
                entries = [u for i in indices for u in utilizations[i]]
                push!(
                    changes,
                    (group=group,current=current,chosen=chosen,largest=entries[extreme_index(entries)])
                )
            end
        end
        u,i,j = maximum_item
        push!(
            history,
            words(
                "round",
                round_number,
                "weight",
                format_real(weight/1000),
                "max_utilization",
                format_real(u),
                "at",
                a.members[i].id,
                combinations[j].name,
                "changes",
                length(changes)
            )
        )
        for change in changes
            push!(
                history,
                words(
                    "change",
                    a.group_order[change.group],
                    a.model.sections[change.current].name,
                    a.model.sections[change.chosen].name,
                    "utilization",
                    format_real(change.largest)
                )
            )
        end
        converged = isempty(changes)
        if converged || round_number==10
            governing_cases = [extreme_index(row) for row in utilizations]
            governing = [row[j] for (row,j) in zip(utilizations,governing_cases)]
            push!(history,words("result",converged ? "converged" : "not_converged","rounds",round_number))
            return (
                ;a...,
                choices,
                final_system=system,
                properties=system.properties,
                results,
                combinations,
                limits,
                utilizations,
                weight,
                governing_cases,
                governing
            ),history
        end
        for change in changes,i in a.groups[change.group]
            choices[i] = change.chosen
        end
    end
end
function design_report(a,history)
    lines = copy(history)
    for (name,indices) in zip(a.group_order,a.groups)
        i = indices[extreme_index(a.governing[indices])]
        section = a.model.sections[a.choices[indices[1]]].name
        push!(
            lines,
            words(
                "group",
                name,
                "section",
                section,
                "members",
                length(indices),
                "utilization",
                format_real(a.governing[i]),
                "at",
                a.members[i].id
            )
        )
    end
    for (i,(m,p,g)) in enumerate(zip(a.members,a.properties,a.geometry))
        slender,limit = slenderness(p,g),a.limits[i]
        verdict = a.governing[i]<=1 && slender<=limit ? "ok" : "over"
        push!(lines,words("member",m.id,"group",m.group,"section",a.model.sections[a.choices[i]].name,"utilization",format_real(a.governing[i]),
            "governing",a.combinations[a.governing_cases[i]].name,"slenderness",format_real(slender),"limit",format_real(limit),verdict))
    end
    ranking = sort!(collect(eachindex(a.members));by=i->(-rounded(a.governing[i]),i))
    for (rank,i) in enumerate(ranking[1:min(5,end)])
        push!(lines,words("rank",rank,"member",a.members[i].id,"utilization",format_real(a.governing[i])))
    end
    for (i,m) in enumerate(a.members)
        entries = [r.forces[i]/1000 for r in a.combinations]
        hi,lo = extreme_index(entries),extreme_index(entries,true)
        push!(
            lines,
            words(
                "envelope",
                m.id,
                "max",
                format_real(entries[hi]),
                a.combinations[hi].name,
                "min",
                format_real(entries[lo]),
                a.combinations[lo].name
            )
        )
    end
    for (i,s) in enumerate(a.model.sections)
        indices = findall(==(i),a.choices)
        isempty(indices) && continue
        span = ordered_total(a.geometry[j].length for j in indices)
        push!(lines,words("section",s.name,"members",length(indices),"length",format_real(span)))
    end
    push!(lines,"weight "*format_real(a.weight/1000))
    lines
end
magnitudes(
    a,
    result
) = [sqrt(result.displacement[x]*result.displacement[x]+result.displacement[y]*result.displacement[y]) for (
    x,
    y
) in a.node_dofs]
function result_summary(a,kind,result)
    entries = magnitudes(a,result)
    node = extreme_index(entries)
    energy = ordered_total(n*n*g.length/(2*p.young*p.area) for (n,g,p) in zip(
        result.forces,
        a.geometry,
        a.properties
    ))/1000
    reactions = [ordered_total(result.reactions[d[axis]] for d in a.node_dofs)/1000 for axis in 1:2]
    forces = [ordered_total(result.external[d[axis]] for d in a.node_dofs)/1000 for axis in 1:2]
    scale = max(1,maximum(abs,result.external),maximum(abs,result.reactions))
    equilibrium = equilibrium_residual(result,a.geometry)<=1e-6*scale ? "ok" : "failed"
    words(kind,result.name,"equilibrium",equilibrium,"max_displacement",format_real(entries[node]),"at",a.nodes[node].id,
        "energy",format_real(energy),"reactions",format_real.(reactions)...,"loads",format_real.(forces)...)
end
function deflection_report(a)
    name,ratio = a.settings["deflection"]
    result = a.results[name]
    fixed = Set(v for (v,axis,_) in a.support_directions if axis==2)
    anchors = findall(v->v in fixed,a.deck)
    lines = String[]
    for (first_position,last_position) in zip(anchors,anchors[2:end])
        left,right = a.deck[first_position],a.deck[last_position]
        xa,xb = a.deck_x[first_position],a.deck_x[last_position]
        va,vb = result.displacement[a.node_dofs[left][2]],result.displacement[a.node_dofs[right][2]]
        interior = collect(first_position+1:last_position-1)
        entries = [abs(result.displacement[a.node_dofs[a.deck[i]][2]]-(va+(vb-va)*(a.deck_x[i]-xa)/(xb-xa))) for i in interior]
        chosen = extreme_index(entries)
        largest,node,limit = entries[chosen],a.deck[interior[chosen]],(xb-xa)/ratio
        push!(lines,words("deflection",name,"span",a.nodes[left].id,a.nodes[right].id,"max",format_real(largest),"at",a.nodes[node].id,
            "limit",format_real(limit),largest<=limit ? "ok" : "exceeded"))
        unit = unit_result(a,node)
        virtual = ordered_total(n*(u/1000)*g.length/(p.young*p.area) for (n,u,g,p) in zip(
            result.forces,
            unit.forces,
            a.geometry,
            a.properties
        ))
        stiffness = -result.displacement[a.node_dofs[node][2]]
        verdict = abs(virtual-stiffness)<=1e-6*max(1,abs(stiffness)) ? "ok" : "failed"
        push!(
            lines,
            words(
                "virtual_work",
                name,
                "node",
                a.nodes[node].id,
                "stiffness",
                format_real(stiffness),
                "virtual",
                format_real(virtual),
                verdict
            )
        )
    end
    lines
end
function removal_report(a)
    combination = a.definitions[a.settings["removal"]]
    lines = String[]
    for (removed,m) in enumerate(a.members)
        system = build_system(a,a.choices,removed)
        if system.unstable!=0
            node,axis = a.owners[system.unstable]
            push!(lines,words("removal",m.id,"unstable at",a.nodes[node].id,"xy"[axis]))
            continue
        end
        result = analyze(a,system,combination)[combination.name]
        indices = filter(!=(removed),collect(eachindex(a.members)))
        entries = [utilization(result.forces[i],system.properties[i],a.geometry[i]) for i in indices]
        largest = extreme_index(entries)
        displacements = magnitudes(a,result)
        node = extreme_index(displacements)
        push!(lines,words("removal",m.id,"stable max_utilization",format_real(entries[largest]),"at",a.members[indices[largest]].id,
            "max_displacement",format_real(displacements[node]),"at",a.nodes[node].id))
    end
    lines
end
function analysis_report(a)
    before = numbering_metrics(collect(0:length(a.nodes)-1),a.neighbors,a.members)
    after = numbering_metrics(a.numbers,a.neighbors,a.members)
    lines = [words("model nodes",length(a.nodes),"members",length(a.members),"supports",length(a.model.supports),
        "free_dofs",length(a.free),"restrained_dofs",length(a.restrained),"indeterminacy",length(a.members)+length(a.restrained)-2length(a.nodes)),
        "renumbering "*join([a.nodes[v].id for v in a.order]," "),words(
            "bandwidth before",
            before[1],
            "after",
            after[1]
        ),words("profile before",before[2],"after",after[2])]
    for (m,g) in zip(a.members,a.geometry)
        push!(
            lines,
            words(
                "member",
                m.id,
                "nodes",
                a.nodes[m.start].id,
                a.nodes[m.finish].id,
                "length",
                format_real(g.length),
                "cos",
                format_real(g.cosine,6),
                "sin",
                format_real(g.sine,6)
            )
        )
    end
    for (kind,name) in a.result_order
        push!(lines,result_summary(a,kind,a.results[name]))
    end
    for (node,axis,degree) in a.support_directions
        entries = [r.reactions[degree]/1000 for r in a.combinations]
        hi,lo = extreme_index(entries),extreme_index(entries,true)
        line = words(
            "reaction_envelope",
            a.nodes[node].id,
            "xy"[axis],
            "max",
            format_real(entries[hi]),
            a.combinations[hi].name,
            "min",
            format_real(entries[lo]),
            a.combinations[lo].name
        )
        axis==2 && (line*= " uplift "*(any(<(0),entries) ? "yes" : "no"))
        push!(lines,line)
    end
    displacements = [magnitudes(a,r) for r in a.combinations]
    for (node,n) in enumerate(a.nodes)
        entries = [d[node] for d in displacements]
        hi = extreme_index(entries)
        push!(
            lines,
            words("displacement_envelope",n.id,"max",format_real(entries[hi]),a.combinations[hi].name)
        )
    end
    append!(lines,deflection_report(a))
    append!(lines,removal_report(a))
    lines
end
function ordinate(a,entries,x)
    (x<a.deck_x[1] || x>a.deck_x[end]) && return 0.0
    x==a.deck_x[end] && return entries[end]
    i = searchsortedlast(a.deck_x,x)
    entries[i]+(entries[i+1]-entries[i])*(x-a.deck_x[i])/(a.deck_x[i+1]-a.deck_x[i])
end
function vehicle_range(a,entries,positions,axles)
    effects = [ordered_total(load*ordinate(a,entries,p-offset) for (offset,load) in axles) for p in positions]
    hi,lo = extreme_index(effects),extreme_index(effects,true)
    (largest=effects[hi],high_position=positions[hi],smallest=effects[lo],low_position=positions[lo])
end
function influence_report(a)
    member_ordinates = [Float64[] for _ in a.members]
    reaction_ordinates = Dict(d=>Float64[] for (_,_,d) in a.support_directions)
    for node in a.deck
        result = unit_result(a,node)
        for (i,n) in enumerate(result.forces)
            push!(member_ordinates[i],n/1000)
        end
        for (_,_,d) in a.support_directions
            push!(reaction_ordinates[d],result.reactions[d]/1000)
        end
    end
    lines = String[]
    for i in a.settings["influence"]
        entries = member_ordinates[i]
        push!(lines,words("influence",a.members[i].id))
        for (node,eta) in zip(a.deck,entries)
            push!(lines,words("node",a.nodes[node].id,format_real(eta)))
        end
        hi,lo = extreme_index(entries),extreme_index(entries,true)
        push!(lines,words("max",format_real(entries[hi]),"at",a.nodes[a.deck[hi]].id,"min",format_real(entries[lo]),"at",a.nodes[a.deck[lo]].id,
            "positive",format_real(ordered_total(v for v in entries if v>0)),"negative",format_real(ordered_total(v for v in entries if v<0))))
        crossings = Float64[]
        for k in 1:length(entries)-1
            left,right = entries[k],entries[k+1]
            if (left>0 && right<0) || (left<0 && right>0)
                push!(crossings,a.deck_x[k]+(a.deck_x[k+1]-a.deck_x[k])*left/(left-right))
            end
        end
        push!(
            lines,
            words("crossings",length(crossings))*(isempty(crossings) ? "" : " "*join(
                [format_real(v,1) for v in crossings],
                " "
            ))
        )
    end
    step,axles = a.settings["vehicle"]
    positions = collect(a.deck_x[1]:step:a.deck_x[end]+axles[end][1])
    push!(lines,words("vehicle axles",length(axles),"positions",length(positions)))
    ranges = NamedTuple[]
    for (m,entries) in zip(a.members,member_ordinates)
        r = vehicle_range(a,entries,positions,axles)
        push!(ranges,r)
        push!(
            lines,
            words(
                "vehicle_member",
                m.id,
                "max",
                format_real(r.largest),
                "at",
                r.high_position,
                "min",
                format_real(r.smallest),
                "at",
                r.low_position
            )
        )
    end
    for (node,axis,d) in a.support_directions
        r = vehicle_range(a,reaction_ordinates[d],positions,axles)
        push!(
            lines,
            words(
                "vehicle_reaction",
                a.nodes[node].id,
                "xy"[axis],
                "max",
                format_real(r.largest),
                "at",
                r.high_position,
                "min",
                format_real(r.smallest),
                "at",
                r.low_position
            )
        )
    end
    name,gamma_d,gamma_l = a.settings["rating"]
    dead,ratings = a.results[name],Tuple{Int,String,Float64}[]
    for (i,(m,p,g,r)) in enumerate(zip(a.members,a.properties,a.geometry,ranges))
        nd = dead.forces[i]/1000
        pt,pc = p.area*p.yield_stress/1000,min(p.area*p.yield_stress,buckling(p,g))/1000
        tension,compression = "none","none"
        if rounded(r.largest)>0
            rating = (pt-gamma_d*nd)/(gamma_l*r.largest)
            tension = format_real(rating)
            push!(ratings,(i,"tension",rating))
        end
        if rounded(r.smallest)<0
            rating = (pc+gamma_d*nd)/(gamma_l*(-r.smallest))
            compression = format_real(rating)
            push!(ratings,(i,"compression",rating))
        end
        push!(lines,words("rating",m.id,"tension",tension,"compression",compression))
    end
    i,kind,rating = ratings[extreme_index([r[3] for r in ratings],true)]
    push!(lines,words("rating_min",format_real(rating),"at",a.members[i].id,kind))
    lines
end
function vibration_report(a)
    name,mode_count,iterations = a.settings["vibration"]
    external = a.results[name].external
    masses = [-external[d[2]]/9.81 for d in a.node_dofs]
    free_masses = [masses[a.owners[d][1]] for d in a.free]
    n,modes = length(a.free),Vector{Float64}[]
    lines = [words("vibration",name,"mass",format_real(ordered_total(masses)),"iterations",iterations)]
    for mode in 1:mode_count
        vector = ones(n)
        for _ in 1:iterations
            for previous in modes
                beta = ordered_total(previous[i]*free_masses[i]*vector[i] for i in 1:n)
                vector = [vector[i]-beta*previous[i] for i in 1:n]
            end
            solution = solve_cholesky(a.final_system.lower,free_masses.*vector)
            magnitude = sqrt(ordered_total(free_masses[i]*solution[i]*solution[i] for i in 1:n))
            vector = solution./magnitude
        end
        push!(modes,vector)
        product = [ordered_total(a.final_system.free_matrix[i,j]*vector[j] for j in 1:n) for i in 1:n]
        eigenvalue = ordered_total(vector[i]*product[i] for i in 1:n)/ordered_total(free_masses[i]*vector[i]*vector[i] for i in 1:n)
        frequency = sqrt(1000*eigenvalue)/(2*TRUSS_PI)
        push!(lines,words("mode",mode,"frequency",format_real(frequency),"period",format_real(1/frequency)))
        peak = argmax(abs.(vector))
        normalized = zeros(a.degrees)
        normalized[a.free] = vector./vector[peak]
        for (node,(x,y)) in zip(a.nodes,a.node_dofs)
            push!(lines,words("node",node.id,format_real(normalized[x]),format_real(normalized[y])))
        end
    end
    lines
end
function new_canvas(nodes,horizontal,vertical)
    x0,x1,y0,y1 = minimum(n.x for n in nodes),maximum(n.x for n in nodes),minimum(n.y for n in nodes),maximum(n.y for n in nodes)
    width,height = floor(Int,(x1-x0)/horizontal+0.5)+5,floor(Int,(y1-y0)/vertical+0.5)+5
    (;x0,y1,horizontal,vertical,width,height,grid=fill(' ',height,width))
end
canvas_position(canvas,x,y) = (
    floor(Int,(x-canvas.x0)/canvas.horizontal+0.5)+2,
    floor(Int,(canvas.y1-y)/canvas.vertical+0.5)+2
)
function canvas_put!(canvas,column,row,character)
    0<=column<canvas.width && 0<=row<canvas.height && (canvas.grid[row+1,column+1]=character)
end
function draw_line!(canvas,first_point,last_point,character)
    c,r = first_point
    c1,r1 = last_point
    dc,dr,sc,sr = abs(c1-c),-abs(r1-r),c<c1 ? 1 : -1,r<r1 ? 1 : -1
    error = dc+dr
    while true
        canvas_put!(canvas,c,r,character)
        (c,r)==(c1,r1) && break
        twice = 2error
        if twice>=dr
            error += dr
            c += sc
        end
        if twice<=dc
            error += dc
            r += sr
        end
    end
end
function framed(canvas)
    border = "+"*repeat("-",canvas.width)*"+"
    [border;["|"*join(canvas.grid[r,:])*"|" for r in 1:canvas.height];border]
end
function drawing_report(a)
    lines = String[]
    for (name,magnification,horizontal,vertical) in a.settings["drawing"]
        result = a.results[name]
        canvas = new_canvas(a.nodes,horizontal,vertical)
        original = [canvas_position(canvas,n.x,n.y) for n in a.nodes]
        deformed = [canvas_position(
            canvas,
            n.x+magnification*result.displacement[x],
            n.y+magnification*result.displacement[y]
        ) for (n,(x,y)) in zip(a.nodes,a.node_dofs)]
        for m in a.members
            draw_line!(canvas,original[m.start],original[m.finish],'.')
        end
        for (c,r) in original
            canvas_put!(canvas,c,r,'+')
        end
        for m in a.members
            draw_line!(canvas,deformed[m.start],deformed[m.finish],'*')
        end
        for (c,r) in deformed
            canvas_put!(canvas,c,r,'o')
        end
        push!(
            lines,
            words("drawing",name,"magnification",magnification,"columns",canvas.width,"rows",canvas.height)
        )
        append!(lines,framed(canvas))
    end
    horizontal,vertical = a.settings["utilization_map"]
    canvas = new_canvas(a.nodes,horizontal,vertical)
    points = [canvas_position(canvas,n.x,n.y) for n in a.nodes]
    for (m,u) in zip(a.members,a.governing)
        character = u>=1 ? '#' : Char(Int('0')+floor(Int,10u))
        draw_line!(canvas,points[m.start],points[m.finish],character)
    end
    for (c,r) in points
        canvas_put!(canvas,c,r,'o')
    end
    push!(lines,words("utilization_map columns",canvas.width,"rows",canvas.height))
    append!(lines,framed(canvas))
    lines
end
function csv_reports(a)
    displacements,forces,reactions = ["case,node,dx,dy"],["case,member,force,stress,utilization"],["case,node,rx,ry"]
    for (_,name) in a.result_order
        result = a.results[name]
        for (node,(x,y)) in zip(a.nodes,a.node_dofs)
            push!(
                displacements,
                join(
                    [
                        name,
                        string(node.id),
                        format_real(result.displacement[x]),
                        format_real(result.displacement[y])
                    ],
                    ','
                )
            )
        end
        for (m,p,g,n) in zip(a.members,a.properties,a.geometry,result.forces)
            push!(
                forces,
                join(
                    [
                        name,
                        string(m.id),
                        format_real(n/1000),
                        format_real(n/p.area),
                        format_real(utilization(n,p,g))
                    ],
                    ','
                )
            )
        end
        for support in a.model.supports
            x,y = a.node_dofs[support.node]
            push!(
                reactions,
                join(
                    [
                        name,
                        string(a.nodes[support.node].id),
                        format_real(result.reactions[x]/1000),
                        format_real(result.reactions[y]/1000)
                    ],
                    ','
                )
            )
        end
    end
    displacements,forces,reactions
end
function main()
    a,history = design_sections(truss_context(read_model()))
    displacements,forces,reactions = csv_reports(a)
    outputs = [("analysis.txt",analysis_report(a)),("displacements.csv",displacements),("member_forces.csv",forces),("reactions.csv",reactions),
        (
            "design.txt",
            design_report(a,history)
        ),("influence.txt",influence_report(a)),("drawing.txt",drawing_report(a)),(
            "vibration.txt",
            vibration_report(a)
        )]
    mkpath("output")
    for (name,lines) in outputs
        write(joinpath("output",name),join(lines,"\n")*"\n")
    end
end
main()
