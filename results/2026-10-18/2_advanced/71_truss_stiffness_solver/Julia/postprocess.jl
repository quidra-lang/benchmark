function axial_forces(geometry,properties,displacement,temperature,removed=0)
    forces = zeros(length(geometry))
    for (number,(g,p)) in enumerate(zip(geometry,properties))
        number==removed && continue
        ix,iy,jx,jy = g.dofs
        extension = (displacement[jx]-displacement[ix])*g.cosine+(displacement[jy]-displacement[iy])*g.sine
        forces[number] = p.stiffness*extension-temperature[number]
    end
    forces
end
function support_reactions(matrix,displacement,force,restrained)
    result = zeros(length(force))
    for r in restrained
        value = 0.0
        for d in eachindex(force)
            value += matrix[r,d]*displacement[d]
        end
        result[r] = value-force[r]
    end
    result
end
function superpose(combination,results)
    name,factor = combination.terms[1]
    first_result = results[name]
    vectors = [factor.*getproperty(first_result,key) for key in (:displacement,:forces,:reactions,:external)]
    for (name,factor) in combination.terms[2:end]
        for (target,key) in zip(vectors,(:displacement,:forces,:reactions,:external))
            source = getproperty(results[name],key)
            for i in eachindex(target)
                target[i] += factor*source[i]
            end
        end
    end
    (name=combination.name,displacement=vectors[1],forces=vectors[2],reactions=vectors[3],external=vectors[4])
end
function equilibrium_residual(result,geometry)
    residual = result.external.+result.reactions
    for (g,force) in zip(geometry,result.forces)
        for (d,t) in zip(g.dofs,(g.cosine,g.sine,-g.cosine,-g.sine))
            residual[d] += force*t
        end
    end
    maximum(abs,residual)
end
