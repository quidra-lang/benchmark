const COMMAND_DISPLAY = Dict(name => value[1] for (name,value) in SYMBOL_COMMANDS)
const COMMAND_TYPES = Dict(name => value[2] for (name,value) in SYMBOL_COMMANDS)
const SYMBOL_TYPES = let table = Dict{String,String}()
    for (characters,kind) in [("+-*","binary"),("=<>:","relation"),("([","open"),(")]!","close"),(",;","punctuation")]
        for c in characters
            table[string(c)] = kind
        end
    end
    table
end
const LARGE_GLYPHS = Dict("\\sum"=>["\\--"," > ","/--"],"\\prod"=>["___","| |","| |"],"\\int"=>[" /"," |","/ "])
mutable struct FormulaBox
    width::Int
    height::Int
    baseline::Int
    description::String
    children::Vector{Tuple{FormulaBox,Int,Int,String}}
    strings::Vector{Tuple{String,Int,Int}}
end
new_box(w,h,b,description) = FormulaBox(w,h,b,description,Tuple{FormulaBox,Int,Int,String}[],Tuple{String,Int,Int}[])
descent(box) = box.height-1-box.baseline
add_child!(box,child,x,y,role="") = push!(box.children,(child,x,y,role))
draw_string!(box,text,x=0,y=0) = push!(box.strings,(text,x,y))
function delimiter_glyph(delimiter,height)
    delimiter == "." && return String[]
    character = string(delimiter[end])
    height == 1 && return [character]
    delimiter in ("[","]","|") && return fill(delimiter,height)
    left = delimiter in ("(","\\{")
    result = [left ? "/" : "\\"]
    append!(result,fill("|",height-2))
    push!(result,left ? "\\" : "/")
    if delimiter in ("\\{","\\}") && height >= 3
        result[(height-1)÷2+1] = left ? "<" : ">"
    end
    result
end
