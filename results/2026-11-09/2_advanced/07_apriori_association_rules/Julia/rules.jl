module AssociationRules
using ..Baskets: setless
export Rule, makerule, meets, ruleless, liftvalue
struct Rule
    x::UInt128
    y::UInt128
    count::Int
    support::Rational{Int}
    confidence::Rational{Int}
    lift::Rational{Int}
    leverage::Rational{Int}
    conviction::Union{Nothing,Rational{Int}}
    improvement::Rational{Int}
end
liftvalue(total,together,a,b) = total*together//(a*b)
function makerule(x,y,together,total,a,b,improvement)
    conviction = a == together ? nothing : (total-b)*a//(total*(a-together))
    Rule(x,y,together,together//total,together//a,liftvalue(total,together,a,b),(total*together-a*b)//(total*total),conviction,improvement)
end
meets(confidence,lift,p) = confidence >= p.confidence && lift >= p.lift
function ruleless(a,b)
    a.confidence != b.confidence && return a.confidence > b.confidence
    a.lift != b.lift && return a.lift > b.lift
    a.count != b.count && return a.count > b.count
    a.x != b.x ? setless(a.x,b.x) : setless(a.y,b.y)
end
end
