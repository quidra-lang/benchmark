module Dataset
export Settings, Lot, controlconstants, readsettings, readmeasurements, readattributes
struct Settings
    characteristic::String
    lsl::Int
    usl::Int
    target::Int
    n::Int
    m::Int
    passes::Int
    rules::Vector{Vector{Int}}
    k::Float64
    h::Float64
    lambda::Float64
    e::Float64
    span::Int
    gap::Int
    z::Float64
    bin::Int
    window::Int
    step::Int
end
struct Lot
    number::Int
    inspected::Int
    defectives::Int
    defects::Int
end
const CONSTANTS = [
    (1.880,2.659,0.0,3.267,0.0,3.267,1.128,0.7979),
    (1.023,1.954,0.0,2.568,0.0,2.574,1.693,0.8862),
    (0.729,1.628,0.0,2.266,0.0,2.282,2.059,0.9213),
    (0.577,1.427,0.0,2.089,0.0,2.114,2.326,0.9400),
    (0.483,1.287,0.030,1.970,0.0,2.004,2.534,0.9515),
    (0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594),
    (0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650),
    (0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693),
    (0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727)]
controlconstants(n) = NamedTuple{(:a2,:a3,:b3,:b4,:d3,:d4,:d2,:c4)}(CONSTANTS[n-1])
function readsettings()
    fields = Dict{String,String}()
    rules = Vector{Int}[]
    for line in eachline("input/spec.txt")
        f = split(line)
        if f[1] == "rules"
            push!(rules,parse.(Int,f[3:end]))
        else
            fields[f[1]] = f[2]
        end
    end
    num(k) = parse(Int,fields[k])
    real(k) = parse(Float64,fields[k])
    Settings(fields["characteristic"],num("lsl"),num("usl"),num("target"),num("subgroup_size"),num("phase1_subgroups"),num("max_passes"),rules,real("cusum_k"),real("cusum_h"),real("ewma_lambda"),real("ewma_l"),num("ma_span"),num("event_gap"),real("ci_z"),num("histogram_bin"),num("rolling_window"),num("rolling_step"))
end
rows(name) = [parse.(Int,split(line,',')) for line in readlines("input/"*name)[2:end]]
readmeasurements() = [r[3] for r in rows("measurements.csv")]
readattributes() = [Lot(r...) for r in rows("attributes.csv")]
end
