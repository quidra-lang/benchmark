function member_geometry(nodes,members,node_dofs)
    [begin
        start,finish = nodes[m.start],nodes[m.finish]
        dx,dy = finish.x-start.x,finish.y-start.y
        span = sqrt(dx*dx+dy*dy)
        (length=span,cosine=dx/span,sine=dy/span,dofs=[node_dofs[m.start];node_dofs[m.finish]])
    end for m in members]
end
function member_properties(model,choices,geometry)
    [begin
        section,material = model.sections[choice],model.materials[member.material]
        (area=section.area,inertia=section.inertia,young=material.young,yield_stress=material.yield_stress,
            density=material.density,expansion=material.expansion,stiffness=material.young*section.area/shape.length)
    end for (member,choice,shape) in zip(model.members,choices,geometry)]
end
member_weight(p,g) = p.density*9.81*p.area*g.length/1000000000
function member_stiffness(p,g)
    k,c,s = p.stiffness,g.cosine,g.sine
    xx,xy,yy = k*(c*c),k*(c*s),k*(s*s)
    [xx xy -xx -xy;xy yy -xy -yy;-xx -xy xx xy;-xy -yy xy yy]
end
function assemble(geometry,properties,degrees,removed=0)
    matrix = zeros(degrees,degrees)
    for (number,(shape,p)) in enumerate(zip(geometry,properties))
        number==removed && continue
        local_matrix = member_stiffness(p,shape)
        for row in 1:4,column in 1:4
            matrix[shape.dofs[row],shape.dofs[column]] += local_matrix[row,column]
        end
    end
    matrix
end
function load_vectors(case,geometry,properties,node_dofs,degrees,removed=0)
    external,thermal,temperature,settlement = zeros(degrees),zeros(degrees),zeros(length(geometry)),false
    for line in case.lines
        if line[1]=="FORCE"
            x,y = node_dofs[line[2]]
            external[x] += line[3]*1000
            external[y] += line[4]*1000
        elseif line[1]=="TEMPERATURE"
            number = line[2]
            number==removed && continue
            p,g = properties[number],geometry[number]
            force = p.young*p.area*p.expansion*line[3]
            temperature[number] = force
            for (d,t) in zip(g.dofs,(-g.cosine,-g.sine,g.cosine,g.sine))
                thermal[d] += force*t
            end
        elseif line[1]=="SELFWEIGHT"
            for (number,(p,g)) in enumerate(zip(properties,geometry))
                number==removed && continue
                weight = member_weight(p,g)
                external[g.dofs[2]] -= weight/2
                external[g.dofs[4]] -= weight/2
            end
        else
            settlement = true
        end
    end
    (external=external,total=external.+thermal,temperature=temperature,settlement=settlement)
end
