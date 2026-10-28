using Printf
struct HMM
    name::String
    states::Vector{Char}
    symbols::Vector{Char}
    missing::Char
    initial::Vector{Float64}
    transition::Matrix{Float64}
    emission::Matrix{Float64}
end
function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
normalize(values) = values./ordered_sum(values)
function make_model(name,states,symbols,missing,initial,transition,emission)
    a,b = copy(transition),copy(emission)
    for i in axes(a,1)
        a[i,:] = normalize(a[i,:])
        b[i,:] = normalize(b[i,:])
    end
    HMM(name,states,symbols,missing,normalize(initial),a,b)
end
function read_inputs()
    read_tokens(name) = [String.(split(line,' ')) for line in readlines(joinpath("input",name))]
    rows = read_tokens("model.txt")
    states,symbols = only.(rows[1][2:end]),only.(rows[2][2:end])
    k,m = length(states),length(symbols)
    initial = parse.(Float64,rows[4][2:end])
    transition,emission = zeros(k,k),zeros(k,m)
    for i in 1:k
        transition[i,:] = parse.(Float64,rows[4+i][3:end])
        emission[i,:] = parse.(Float64,rows[4+k+i][3:end])
    end
    model = make_model("INITIAL",states,symbols,only(rows[3][2]),initial,transition,emission)
    model,read_tokens("sequences.txt"),read_tokens("labeled.txt"),read_tokens("params.txt")
end
function real_text(value,places=4)
    isnothing(value) && return "-"
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
function model_lines(model)
    lines = [
        "MODEL $(model.name)",
        "STATES "*join(model.states," "),
        "SYMBOLS "*join(model.symbols," "),
        "MISSING $(model.missing)",
        "INITIAL "*join(real_text.(model.initial)," ")
    ]
    for i in eachindex(model.states)
        push!(lines,"TRANSITION $(model.states[i]) "*join(real_text.(model.transition[i,:])," "))
    end
    for i in eachindex(model.states)
        push!(lines,"EMISSION $(model.states[i]) "*join(real_text.(model.emission[i,:])," "))
    end
    lines
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
