include("mesh.jl")
include("materials.jl")
include("transient.jl")
include("steady.jl")
include("report.jl")
const SOLVER_ORDER = ("jacobi","gauss_seidel","sor","sor_estimated")
const MILESTONE_FACTORS = (1000,100,10,1)
mutable struct ThermalFace
    neighbor::Int
    g::Float64
    theta::Union{Nothing,Float64}
end
Base.@kwdef mutable struct RunResult
    run::Any
    status::String
    snapshots::Dict{Int,NamedTuple} = Dict{Int,NamedTuple}()
    probe_samples::Vector{Tuple{Int,Vector{Float64}}} = Tuple{Int,Vector{Float64}}[]
    segment_energy::Vector{Float64} = Float64[]
    generated::Float64 = 0.0
    peak::Union{Nothing,Tuple{Float64,Int,Int}} = nothing
    alarm::Union{Nothing,Tuple{Int,Int}} = nothing
    above::Int = 0
    steps::Int = 0
    final::Vector{Float64} = Float64[]
    stored::Float64 = 0.0
    boundary::Float64 = 0.0
    balance::Bool = false
end
function read_boundary(plate)
    segments,sources = NamedTuple[],NamedTuple[]
    for line in readlines(joinpath("input","boundary.txt"))
        words = String.(split(line))
        if words[1]=="segment"
            name,edge,kind = words[2],words[3],words[6]
            values = parse.(Float64,words[7:end])
            theta = kind=="fixed" ? values[1] : kind=="convective" ? values[2] : nothing
            coefficient = kind=="convective" ? values[1] : nothing
            push!(
                segments,
                (
                    name=name,
                    edge=edge,
                    kind=kind,
                    theta=theta,
                    coefficient=coefficient,
                    faces=segment_faces(plate,edge,parse(Int,words[4]),parse(Int,words[5]))
                )
            )
        else
            cells = source_cells(plate,parse.(Int,words[3:6])...)
            power = parse(Float64,words[7])
            times = parse.(Int,words[8:end])
            intervals = [(times[i],times[i+1]) for i in 1:2:length(times)]
            push!(
                sources,
                (name=words[2],cells=cells,power=power,intervals=intervals,weight=power/length(cells))
            )
        end
    end
    segments,sources
end
function read_parameters(plate)
    params = Dict{String,Any}("probes"=>NamedTuple[],"runs"=>NamedTuple[])
    for line in readlines(joinpath("input","params.txt"))
        words = String.(split(line))
        key,values = words[1],words[2:end]
        if key in ("end_time","probe_every","max_iterations")
            params[key] = parse(Int,values[1])
        elseif key in ("initial","tolerance","omega","alarm","limit")
            params[key] = parse(Float64,values[1])
        elseif key=="snapshots"
            params[key] = parse.(Int,values)
        elseif key=="bands"
            params[key] = parse.(Float64,values)
        elseif key=="probe"
            push!(
                params["probes"],
                (name=values[1],point=cell(plate,parse(Int,values[2]),parse(Int,values[3])))
            )
        elseif key=="run"
            step = parse(Int,values[3])
            push!(params["runs"],(name=values[1],method=values[2],step=step,dt=step/1000))
        else
            params[key] = values[1]
        end
    end
    params
end
operating(source,time) = any(interval->interval[1]<=time<interval[2],source.intervals)
duty_ratio(
    source,
    end_time
) = sum(min(stop,end_time)-min(start,end_time) for (start,stop) in source.intervals)/end_time
function source_terms(sources,n,time=nothing)
    field,total = zeros(n),0.0
    for source in sources
        !isnothing(time) && !operating(source,time) && continue
        total += source.power
        for p in source.cells
            field[p] += source.weight
        end
    end
    field,total
end
function build_system(plate,materials,segments,sources)
    indices = Dict(material.code=>i for (i,material) in enumerate(materials))
    cell_material = [indices[code] for code in plate.codes]
    material_cells = [[p for p in 1:plate.count if cell_material[p]==i] for i in eachindex(materials)]
    cell_materials = materials[cell_material]
    capacity = [heat_capacity(material,plate.dx,plate.thickness) for material in cell_materials]
    faces = Vector{ThermalFace}[]
    for p in 1:plate.count
        row = ThermalFace[]
        for neighbor in plate.neighbors[p,:]
            conductance = neighbor==0 ? 0.0 : interior_conductance(
                cell_materials[p].k,
                cell_materials[neighbor].k,
                plate.thickness
            )
            push!(row,ThermalFace(neighbor,conductance,nothing))
        end
        push!(faces,row)
    end
    for segment in segments,(p,direction) in segment.faces
        face = faces[p][direction]
        if segment.kind=="fixed"
            face.g = fixed_conductance(cell_materials[p].k,plate.thickness)
        elseif segment.kind=="convective"
            face.g = convective_conductance(cell_materials[p].k,segment.coefficient,plate.dx,plate.thickness)
        end
        face.theta = segment.theta
    end
    diagonal = [ordered_sum(face.g for face in row) for row in faces]
    beta = [ordered_sum(face.g*face.theta for face in row if !isnothing(face.theta)) for row in faces]
    source_all,total_power = source_terms(sources,plate.count)
    (mesh=plate,materials=materials,segments=segments,sources=sources,cell_material=cell_material,material_cells=material_cells,capacity=capacity,
        faces=faces,diagonal=diagonal,beta=beta,source_all=source_all,total_power=total_power,dt_max=minimum(capacity./diagonal))
end
function run_status(run,system,params)
    times = vcat([params["end_time"],params["probe_every"]],params["snapshots"])
    for source in system.sources,(start,stop) in source.intervals
        append!(times,[start,stop])
    end
    any(time->time%run.step!=0,times) && return "step"
    run.method=="ftcs" && run.dt>system.dt_max ? "unstable" : "accepted"
end
cell_text(plate,p) = join(coordinates(plate,p)," ")
function field_summary(prefix,plate,field)
    hottest = argmax(field)
    "$prefix max $(real_text(field[hottest],2)) at $(cell_text(plate,hottest)) min $(real_text(minimum(field),2)) mean $(real_text(ordered_sum(field)/plate.count,2))"
end
stored_heat(
    system,
    field,
    initial,
    cells=1:system.mesh.count
) = ordered_sum(system.capacity[p]*(field[p]-initial) for p in cells)
function segment_flow(system,segment,field)
    segment.kind=="insulated" && return 0.0
    ordered_sum(system.faces[p][direction].g*(system.faces[p][direction].theta-field[p]) for (
        p,
        direction
    ) in segment.faces)
end
function step_boundary_energy(system,segment,run,previous,updated,intermediate)
    segment.kind=="insulated" && return 0.0
    terms = Float64[]
    for (p,direction) in segment.faces
        face = system.faces[p][direction]
        temperature = run.method=="ftcs" ? previous[p] : segment.edge in (
            "left",
            "right"
        ) ? intermediate[p] : run.method=="backward_euler" ? updated[p] : (previous[p]+updated[p])/2
        push!(terms,face.g*(face.theta-temperature))
    end
    run.dt*ordered_sum(terms)
end
function observe!(result,system,params,time,field)
    hottest = argmax(field)
    temperature = field[hottest]
    if isnothing(result.peak) || temperature>result.peak[1]
        result.peak = (temperature,time,hottest)
    end
    if temperature>=params["alarm"]
        isnothing(result.alarm) && (result.alarm=(time,hottest))
        time>0 && (result.above+=result.run.step)
    end
    if time%params["probe_every"]==0
        push!(result.probe_samples,(time,[field[probe.point] for probe in params["probes"]]))
    end
    if time in params["snapshots"]
        result.snapshots[time] = (
            field=copy(field),
            stored=stored_heat(system,field,params["initial"]),
            boundary=ordered_sum(result.segment_energy),
            source=result.generated
        )
    end
end
function simulate_run(run,system,params)
    result = RunResult(
        run=run,
        status="accepted",
        steps=params["end_time"]÷run.step,
        segment_energy=zeros(length(system.segments))
    )
    field = fill(params["initial"],system.mesh.count)
    observe!(result,system,params,0,field)
    for step in 0:result.steps-1
        source,power = source_terms(system.sources,system.mesh.count,step*run.step)
        updated,intermediate = advance_field(run.method,system,field,source,run.dt)
        for (j,segment) in enumerate(system.segments)
            result.segment_energy[j] += step_boundary_energy(system,segment,run,field,updated,intermediate)
        end
        result.generated += run.dt*power
        field = updated
        observe!(result,system,params,(step+1)*run.step,field)
    end
    result.final = field
    result.stored = stored_heat(system,field,params["initial"])
    result.boundary = ordered_sum(result.segment_energy)
    result.balance = abs(result.stored-result.boundary-result.generated)<=0.000001*(abs(result.stored)+abs(result.boundary)+abs(result.generated))
    result
end
function solve_steady(system)
    rhs = system.beta.+system.source_all
    vectors = [rhs,system.beta]
    for source in system.sources
        vector = zeros(system.mesh.count)
        vector[source.cells] .= 1/length(source.cells)
        push!(vectors,vector)
    end
    fields = band_solve(system,vectors)
    rhs,fields[1],fields[2],fields[3:end]
end
function run_iterative_methods(system,params,solution,rhs)
    jacobi = iterate_steady(system,params["initial"],params["tolerance"],params["max_iterations"],"jacobi")
    rho = sqrt(jacobi.changes[end]/jacobi.changes[end-2])
    omega_opt = 2/(1+sqrt(1-rho*rho))
    results = [jacobi]
    for method in SOLVER_ORDER[2:end]
        omega = method=="sor_estimated" ? omega_opt : params["omega"]
        push!(
            results,
            iterate_steady(system,params["initial"],params["tolerance"],params["max_iterations"],method,omega)
        )
    end
    enriched = NamedTuple[]
    for result in results
        milestones = String[]
        for factor in MILESTONE_FACTORS
            i = findfirst(change->change<params["tolerance"]*factor,result.changes)
            push!(milestones,isnothing(i) ? "never" : string(i))
        end
        push!(
            enriched,
            (
                ;result...,
                rate=sqrt(result.changes[end]/result.changes[end-2]),
                milestones=milestones,
                error=maximum(abs.(result.field.-solution)),
                residual=maximum_residual(system,result.field,rhs)
            )
        )
    end
    enriched,rho,omega_opt
end
function steady_state_lines(system,params,solution,base,responses,iterative)
    plate = system.mesh
    lines = [field_summary("steady",plate,solution)]
    append!(lines,temperature_lines(plate,solution))
    for (material,cells) in zip(system.materials,system.material_cells)
        temperatures = solution[cells]
        push!(
            lines,
            "material $(material.code) $(material.name) cells $(length(cells)) min $(real_text(minimum(temperatures),2)) max $(real_text(maximum(temperatures),2)) mean $(real_text(ordered_sum(temperatures)/length(cells),2))"
        )
    end
    duties = [duty_ratio(source,params["end_time"]) for source in system.sources]
    for (source,duty) in zip(system.sources,duties)
        temperatures = solution[source.cells]
        push!(
            lines,
            "source $(source.name) power $(real_text(source.power,4)) duty $(real_text(duty,4)) mean $(real_text(ordered_sum(temperatures)/length(source.cells),2)) max $(real_text(maximum(temperatures),2))"
        )
    end
    for source in system.sources,(contributor,response) in zip(system.sources,responses)
        coefficient = ordered_sum(response[p] for p in source.cells)/length(source.cells)
        push!(lines,"influence $(source.name) $(contributor.name) $(real_text(coefficient,4))")
    end
    superposition,duty = copy(base),copy(base)
    for p in 1:plate.count,(source,response,ratio) in zip(system.sources,responses,duties)
        superposition[p] += source.power*response[p]
        duty[p] += (ratio*source.power)*response[p]
    end
    verdict(value) = value ? "ok" : "failed"
    push!(lines,"superposition $(verdict(maximum(abs.(superposition.-solution))<=0.000001))")
    for (source,response) in zip(system.sources,responses),segment in system.segments
        value = segment.kind=="insulated" ? 0.0 : ordered_sum(system.faces[p][direction].g*response[p] for (
            p,
            direction
        ) in segment.faces)
        push!(lines,"path $(source.name) $(segment.name) $(real_text(value,4))")
    end
    push!(lines,field_summary("duty_steady",plate,duty))
    for (source,response) in zip(system.sources,responses)
        powers = [(params["limit"]-(solution[p]-source.power*response[p]))/response[p] for p in 1:plate.count]
        p = argmin(powers)
        push!(lines,"headroom $(source.name) max_power $(real_text(powers[p],4)) at $(cell_text(plate,p))")
    end
    interfaces = Dict{Tuple{Int,Int},NamedTuple}()
    largest,chosen = -1.0,(0,0)
    for p in 1:plate.count,direction in (RIGHT,BOTTOM)
        face = system.faces[p][direction]
        q = face.neighbor
        q==0 && continue
        gradient = abs(solution[p]-solution[q])/plate.dx
        if gradient>largest
            largest,chosen = gradient,(p,q)
        end
        first,second = system.cell_material[p],system.cell_material[q]
        first==second && continue
        flow = face.g*(solution[p]-solution[q])
        if first>second
            first,second = second,first
            flow = -flow
        end
        key = (first,second)
        previous = get(interfaces,key,(count=0,forward=0.0,backward=0.0))
        interfaces[key] = (
            count=previous.count+1,
            forward=previous.forward+(flow>0 ? flow : 0.0),
            backward=previous.backward+(flow<0 ? abs(flow) : 0.0)
        )
    end
    for (first,second) in sort(collect(keys(interfaces)))
        result = interfaces[(first,second)]
        push!(
            lines,
            "interface $(system.materials[first].code) $(system.materials[second].code) faces $(result.count) forward $(real_text(result.forward,4)) backward $(real_text(result.backward,4))"
        )
    end
    flows = Float64[]
    for segment in system.segments
        flow = segment_flow(system,segment,solution)
        push!(flows,flow)
        push!(lines,"segment $(segment.name) $(segment.edge) $(segment.kind) flow $(real_text(flow,4))")
    end
    balanced = abs(ordered_sum(flows)+system.total_power)<=0.000001*(ordered_sum(abs(flow) for flow in flows)+system.total_power)
    push!(
        lines,
        "sources $(real_text(system.total_power,4))",
        "balance $(verdict(balanced))",
        "max_gradient $(real_text(largest,2)) between $(cell_text(plate,chosen[1])) and $(cell_text(plate,chosen[2]))"
    )
    for result in iterative
        prefix = "solver $(result.method)"
        result.method in ("sor","sor_estimated") && (prefix*=" omega $(real_text(result.omega,4))")
        push!(
            lines,
            "$prefix iterations $(result.iterations) converged $(result.converged ? "yes" : "no") rate $(real_text(result.rate,6)) milestones $(join(result.milestones," "))"
        )
    end
    lines
end
function rejected_run_line(result,maximum_step=nothing)
    run = result.run
    line = "run $(run.name) $(run.method) dt $(time_text(run.step)) rejected $(result.status)"
    result.status=="unstable" && !isnothing(maximum_step) && (line*=" max_dt $(real_text(maximum_step,4))")
    line
end
function snapshot_lines(system,params,results)
    lines = String[]
    for result in results
        if result.status!="accepted"
            push!(lines,rejected_run_line(result,system.dt_max))
            continue
        end
        run = result.run
        for time in params["snapshots"]
            field = result.snapshots[time].field
            prefix = "run $(run.name) $(run.method) dt $(time_text(run.step)) time $(time_text(time))"
            push!(lines,field_summary(prefix,system.mesh,field))
            append!(lines,temperature_lines(system.mesh,field))
        end
    end
    lines
end
function probe_lines(params,results)
    lines = ["run,time,probe,temperature"]
    for result in results
        result.status=="accepted" || continue
        for (time,temperatures) in result.probe_samples,(probe,temperature) in zip(
            params["probes"],
            temperatures
        )
            push!(lines,"$(result.run.name),$(time_text(time)),$(probe.name),$(real_text(temperature,3))")
        end
    end
    lines
end
function comparison_lines(system,params,results,reference,solution,rhs,iterative,rho,omega_opt)
    lines = ["ftcs_max_dt $(real_text(system.dt_max,4))"]
    for result in results
        if result.status!="accepted"
            push!(lines,rejected_run_line(result))
            continue
        end
        run = result.run
        temperature,peak_time,peak_cell = result.peak
        alarm = isnothing(result.alarm) ? "never" : "$(time_text(result.alarm[1])) at $(cell_text(system.mesh,result.alarm[2]))"
        push!(lines,"run $(run.name) $(run.method) dt $(time_text(run.step)) steps $(result.steps) peak $(real_text(temperature,2)) time $(time_text(peak_time)) at $(cell_text(system.mesh,peak_cell)) alarm $alarm above $(time_text(result.above))",
            "energy $(run.name) stored $(real_text(result.stored,2)) boundary $(real_text(result.boundary,2)) source $(real_text(result.generated,2)) balance $(result.balance ? "ok" : "failed")")
        for time in params["snapshots"]
            snapshot = result.snapshots[time]
            push!(
                lines,
                "energy_at $(run.name) time $(time_text(time)) stored $(real_text(snapshot.stored,2)) boundary $(real_text(snapshot.boundary,2)) source $(real_text(snapshot.source,2))"
            )
        end
        for (material,cells) in zip(system.materials,system.material_cells)
            value = stored_heat(system,result.final,params["initial"],cells)
            push!(lines,"energy_material $(run.name) $(material.code) $(real_text(value,2))")
        end
        for (segment,value) in zip(system.segments,result.segment_energy)
            push!(lines,"energy_segment $(run.name) $(segment.name) $(real_text(value,2))")
        end
        for (i,probe) in enumerate(params["probes"])
            readings = [values[i] for (_,values) in result.probe_samples]
            high,low = argmax(readings),argmin(readings)
            push!(
                lines,
                "probe_summary $(run.name) $(probe.name) max $(real_text(readings[high],3)) time $(time_text(result.probe_samples[high][1])) min $(real_text(readings[low],3)) time $(time_text(result.probe_samples[low][1]))"
            )
        end
        if run.name!=reference.run.name
            for time in params["snapshots"]
                errors = abs.(result.snapshots[time].field.-reference.snapshots[time].field)
                rms = sqrt(ordered_sum(error*error for error in errors)/system.mesh.count)
                push!(
                    lines,
                    "compare $(run.name) $(reference.run.name) time $(time_text(time)) max_diff $(real_text(maximum(errors),6)) rms_diff $(real_text(rms,6))"
                )
            end
        end
        push!(lines,"final $(run.name) steady_max_diff $(real_text(maximum(abs.(result.final.-solution)),6))")
    end
    push!(lines,"steady direct max_residual $(real_text(maximum_residual(system,solution,rhs),6))")
    for result in iterative
        push!(
            lines,
            "steady $(result.method) iterations $(result.iterations) max_diff $(real_text(result.error,6)) max_residual $(real_text(result.residual,6))"
        )
    end
    push!(
        lines,
        "jacobi_spectral_radius $(real_text(rho,6)) squared $(real_text(rho*rho,6))",
        "omega_estimated $(real_text(omega_opt,4))"
    )
    lines
end
function isotherm_output(system,params,solution,reference)
    counts,grid = isotherm_lines(system.mesh,solution,params["bands"])
    lines = vcat(["isotherms steady counts "*join(counts," ")],grid)
    for time in params["snapshots"]
        counts,grid = isotherm_lines(system.mesh,reference.snapshots[time].field,params["bands"])
        push!(lines,"isotherms $(reference.run.name) time $(time_text(time)) counts "*join(counts," "))
        append!(lines,grid)
    end
    lines
end
function main()
    plate,materials = read_plate(),read_materials()
    segments,sources = read_boundary(plate)
    params = read_parameters(plate)
    system = build_system(plate,materials,segments,sources)
    rhs,solution,base,responses = solve_steady(system)
    iterative,rho,omega_opt = run_iterative_methods(system,params,solution,rhs)
    results = RunResult[]
    for run in params["runs"]
        status = run_status(run,system,params)
        push!(results,status=="accepted" ? simulate_run(run,system,params) : RunResult(run=run,status=status))
    end
    reference = results[findfirst(result->result.run.name==params["reference"],results)]
    outputs = [("snapshots.txt",snapshot_lines(system,params,results)),("probes.csv",probe_lines(params,results)),
        ("steady_state.txt",steady_state_lines(system,params,solution,base,responses,iterative)),(
            "solver_comparison.txt",
            comparison_lines(system,params,results,reference,solution,rhs,iterative,rho,omega_opt)
        ),
        ("isotherms.txt",isotherm_output(system,params,solution,reference))]
    for (name,lines) in outputs
        write_lines(name,lines)
    end
end
main()
