const ORGANIC = Set(["B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"])
const AROMATIC = Set(["B", "C", "N", "O", "P", "S"])
const BOND_TYPES = Dict("-" => 1, "/" => 1, "\\" => 1, "=" => 2, "#" => 3, ":" => 4)
const BASE_VALUES = [1, 2, 3, 1]
struct AnalysisError <: Exception
    reason::String
    column::Int
end
analysis_error(reason, column) = throw(AnalysisError(reason, column))
struct Element
    symbol::String
    number::Int
    weight::Int
    valences::Vector{Int}
end
mutable struct ChemAtom
    element::Element
    aromatic::Bool
    mass::Int
    charge::Int
    hydrogens::Int
    bracket::Bool
    column::Int
end
mutable struct ChemBond
    ends::Tuple{Int,Int}
    symbol::Any
    kind::Int
    multiplicity::Int
    ring::Bool
end
mutable struct ChemMolecule
    elements::Dict{String,Element}
    atoms::Vector{Any}
    neighbors::Vector{Dict{Int,ChemBond}}
    bonds::Dict{Tuple{Int,Int},ChemBond}
    rings::Vector{Vector{Int}}
    ring_atoms::Set{Int}
    name::String
    order::Int
    properties::Any
    canonical::String
    classes::Int
    scaffold::Union{Nothing,String}
    systems::Vector{Any}
    aromatic_rings::Vector{Bool}
    bits::Set{Int}
    paths::Int
end
function new_molecule(elements)
    ChemMolecule(elements, Any[], Dict{Int,ChemBond}[], Dict{Tuple{Int,Int},ChemBond}(),
        Vector{Int}[], Set{Int}(), "", 0, nothing, "", 0, nothing, Any[], Bool[], Set{Int}(), 0)
end
function add_atom!(m, atom)
    push!(m.atoms, atom)
    push!(m.neighbors, Dict{Int,ChemBond}())
    length(m.atoms)
end
bond_key(a, b) = a < b ? (a, b) : (b, a)
function add_bond!(m, a, b, symbol)
    bond = ChemBond(bond_key(a, b), symbol, 0, 0, false)
    m.bonds[bond.ends] = bond
    m.neighbors[a][b] = bond
    m.neighbors[b][a] = bond
    bond
end
ordered_bonds(m) = [m.bonds[key] for key in sort(collect(keys(m.bonds)))]
neighbor_numbers(m, a) = sort(collect(keys(m.neighbors[a])))
degree(m, a) = length(m.neighbors[a])
base_total(m, a) = sum((BASE_VALUES[b.kind] for b in values(m.neighbors[a])); init=0)
bond_total(m, a) = sum((b.multiplicity for b in values(m.neighbors[a])); init=0)
function read_elements()
    elements = Dict{String,Element}()
    for text in readlines("input/elements.txt")
        (isempty(text) || startswith(text, "#")) && continue
        f = split(text)
        elements[String(f[1])] = Element(String(f[1]), parse(Int, f[2]),
            parse(Int, f[3]), parse.(Int, split(f[4], ',')))
    end
    elements
end
function needs_pi(m, a, hydrogens=m.atoms[a].hydrogens)
    atom = m.atoms[a]
    atom.aromatic && atom.element.valences[1] + atom.charge >= base_total(m, a) + hydrogens + 1
end
function organic_hydrogens(atom, total)
    index = findfirst(v -> v >= total, atom.element.valences)
    index === nothing ? nothing : atom.element.valences[index] - total
end
