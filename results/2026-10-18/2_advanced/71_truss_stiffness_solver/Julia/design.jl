const TRUSS_PI = 3.141592653589793
buckling(p,g,inertia=p.inertia) = TRUSS_PI*TRUSS_PI*p.young*inertia/(g.length*g.length)
function utilization(force,p,g,section=nothing)
    area,inertia = isnothing(section) ? (p.area,p.inertia) : (section.area,section.inertia)
    max(abs(force/area)/p.yield_stress,max(0,-force)/buckling(p,g,inertia))
end
function slenderness(p,g,section=nothing)
    area,inertia = isnothing(section) ? (p.area,p.inertia) : (section.area,section.inertia)
    g.length/sqrt(inertia/area)
end
slenderness_limit(number,combinations,limits) = any(
    r->r.forces[number]<0,
    combinations
) ? limits[1] : limits[2]
function select_section(members,sections,properties,geometry,combinations,limits)
    for (number,section) in enumerate(sections)
        acceptable = true
        for member in members
            if slenderness(properties[member],geometry[member],section)>limits[member] ||
                any(
                    r->utilization(r.forces[member],properties[member],geometry[member],section)>1,
                    combinations
                )
                acceptable = false
                break
            end
        end
        acceptable && return number
    end
    length(sections)
end
