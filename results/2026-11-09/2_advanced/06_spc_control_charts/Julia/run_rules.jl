module RunRules
export Signal, zones, checkrules, zonename
struct Signal
    chart::Int
    rule::Int
    first::Int
    last::Int
    value::Float64
    direction::Int
end
function zones(l)
    a = (l.ucl-l.cl)/3
    b = (l.cl-l.lcl)/3
    (lcl=l.lcl,cl=l.cl,ucl=l.ucl,u1=l.cl+a,u2=l.cl+2*a,l1=l.cl-b,l2=l.cl-2*b)
end
function zonename(l,v)
    z = zones(l)
    v > z.ucl ? "OUT+" : v < z.lcl ? "OUT-" : v > z.u2 ? "A+" : v > z.u1 ? "B+" : v > z.cl ? "C+" : v < z.l2 ? "A-" : v < z.l1 ? "B-" : v < z.cl ? "C-" : "C0"
end
const LENGTHS = (1,3,5,8,6,14,15,8)
function checkrules(chart,numbers,values,limits,rules)
    z = zones(limits)
    signals = Signal[]
    for k in eachindex(values), r in rules
        len = LENGTHS[r]
        k < len && continue
        window = @view values[k-len+1:k]
        last = values[k]
        direction = nothing
        if r == 1
            if last > z.ucl || last < z.lcl
                direction = last > z.cl ? 1 : -1
            end
        elseif r == 2 || r == 3
            upper,lower,needed = r == 2 ? (z.u2,z.l2,2) : (z.u1,z.l1,4)
            if last > upper && count(v -> v > upper,window) >= needed
                direction = 1
            elseif last < lower && count(v -> v < lower,window) >= needed
                direction = -1
            end
        elseif r == 4
            all(v -> v > z.cl,window) && (direction = 1)
            all(v -> v < z.cl,window) && (direction = -1)
        elseif r == 5
            all(j -> window[j] > window[j-1],2:len) && (direction = 1)
            all(j -> window[j] < window[j-1],2:len) && (direction = -1)
        elseif r == 6
            differences = diff(window)
            all(x -> !iszero(x),differences) && all(j -> (differences[j] > 0) != (differences[j-1] > 0),2:length(differences)) && (direction = 0)
        elseif r == 7
            all(v -> z.l1 < v < z.u1,window) && (direction = 0)
        elseif all(v -> v > z.u1 || v < z.l1,window) && any(v -> v > z.u1,window) && any(v -> v < z.l1,window)
            direction = 0
        end
        direction === nothing || push!(signals,Signal(chart,r,numbers[k-len+1],numbers[k],last,direction))
    end
    signals
end
end
