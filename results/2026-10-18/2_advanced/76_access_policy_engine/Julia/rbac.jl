Base.@kwdef mutable struct RbacDefinitions
    roles::Set{String} = Set{String}()
    inherits::Dict{String,Set{String}} = Dict{String,Set{String}}()
    permissions::Dict{String,Set{Tuple{String,String}}} = Dict{String,Set{Tuple{String,String}}}()
    ssd::Vector{NamedTuple} = NamedTuple[]
    dsd::Vector{NamedTuple} = NamedTuple[]
    assignments::Vector{NamedTuple} = NamedTuple[]
    diagnostics::Vector{Tuple{Int,String,String}} = Tuple{Int,String,String}[]
    grants::Set{Tuple{String,String,String}} = Set{Tuple{String,String,String}}()
end
function role_closure(rbac,roles)
    reached,pending = Set{String}(roles),collect(roles)
    while !isempty(pending)
        for junior in rbac.inherits[pop!(pending)]
            if !(junior in reached)
                push!(reached,junior)
                push!(pending,junior)
            end
        end
    end
    reached
end
function inheritance_path(rbac,start,finish)
    failed = Set{String}()
    function visit(role)
        role==finish && return [role]
        if !(role in failed)
            for junior in sort!(collect(rbac.inherits[role]))
                suffix = visit(junior)
                !isnothing(suffix) && return [role;suffix]
            end
            push!(failed,role)
        end
        nothing
    end
    visit(start)
end
assigned_roles(rbac,user,day) = Set(a.role for a in rbac.assignments if a.user==user && a.first<=day<=a.last)
authorized_roles(rbac,user,day) = role_closure(rbac,assigned_roles(rbac,user,day))
function accept_rbac!(r,keyword,f)
    if keyword=="ROLE"
        role = f[1]
        role in r.roles && return "duplicate role $role"
        push!(r.roles,role)
        r.inherits[role],r.permissions[role] = Set{String}(),Set{Tuple{String,String}}()
    elseif keyword=="INHERITS"
        senior,junior = f
        for role in (senior,junior)
            !(role in r.roles) && return "unknown role $role"
        end
        junior in r.inherits[senior] && return "duplicate inheritance $senior $junior"
        senior in role_closure(r,[junior]) && return "cycle "*join(
            [senior;inheritance_path(r,junior,senior)],
            " > "
        )
        push!(r.inherits[senior],junior)
    elseif keyword=="PERMIT"
        role,action,resource_type = f
        !(role in r.roles) && return "unknown role $role"
        (
            action,
            resource_type
        ) in r.permissions[role] && return "duplicate permission $role $action $resource_type"
        push!(r.permissions[role],(action,resource_type))
        push!(r.grants,(role,action,resource_type))
    elseif keyword in ("SSD","DSD")
        name,n,role_text = f
        constraints = keyword=="SSD" ? r.ssd : r.dsd
        any(c->c.name==name,constraints) && return "duplicate constraint $name"
        roles = String.(split(role_text,','))
        for role in roles
            !(role in r.roles) && return "unknown role $role"
        end
        cardinality = parse(Int,n)
        !(2<=cardinality<=length(roles)) && return "bad cardinality $name $cardinality"
        push!(constraints,(name=name,cardinality=cardinality,roles=Set(roles)))
    else
        user,role,first_text,last_text = f
        !(role in r.roles) && return "unknown role $role"
        first,last = parse(Int,first_text),parse(Int,last_text)
        !(1<=first<=last<=365) && return "bad range $first $last"
        for constraint in r.ssd,day in first:last
            roles = intersect(constraint.roles,role_closure(r,union(assigned_roles(r,user,day),Set([role]))))
            length(roles)>=constraint.cardinality && return "ssd $(constraint.name) day $day roles "*join(
                sort!(collect(roles)),
                ','
            )
        end
        push!(r.assignments,(user=user,role=role,first=first,last=last))
    end
    nothing
end
function read_rbac()
    r = RbacDefinitions()
    lines = String.(readlines("input/rbac.txt"))
    for keyword in ("ROLE","INHERITS","PERMIT","SSD","DSD","ASSIGN"),(i,line) in enumerate(lines)
        f = String.(split(line))
        f[1]==keyword || continue
        error = accept_rbac!(r,keyword,f[2:end])
        !isnothing(error) && push!(r.diagnostics,(i,keyword,error))
    end
    sort!(r.diagnostics)
    r
end
