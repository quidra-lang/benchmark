function read_materials()
    materials = NamedTuple[]
    for line in readlines(joinpath("input","materials.txt"))
        words = String.(split(line))
        push!(
            materials,
            (
                code=only(words[1]),
                name=words[2],
                k=parse(Float64,words[3]),
                rho=parse(Float64,words[4]),
                cp=parse(Float64,words[5])
            )
        )
    end
    materials
end
heat_capacity(material,dx,thickness) = material.rho*material.cp*dx*dx*thickness
interior_conductance(first,second,thickness) = 2*first*second/(first+second)*thickness
fixed_conductance(conductivity,thickness) = 2*conductivity*thickness
convective_conductance(
    conductivity,
    coefficient,
    dx,
    thickness
) = 1/(1/(coefficient*dx*thickness)+1/(2*conductivity*thickness))
