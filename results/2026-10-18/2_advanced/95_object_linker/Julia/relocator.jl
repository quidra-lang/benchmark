const TYPES = ["ABS32","REL32","ABS16","HI16","LO16","GPREL16","CALL24"]
const WIDTHS = Dict("ABS32"=>4,"REL32"=>4,"ABS16"=>2,"HI16"=>2,"LO16"=>2,"GPREL16"=>2,"CALL24"=>3)
const RANGES = Dict("ABS32"=>(-2^31,2^32),"REL32"=>(-2^31,2^31),"ABS16"=>(-2^15,2^16),"HI16"=>(-2^31,2^32),"GPREL16"=>(-2^15,2^15),"CALL24"=>(-2^25,2^25))
function unpaired_hi16(relocations,index)
    current = relocations[index]
    current.type == "HI16" || return false
    index == length(relocations) && return true
    following = relocations[index+1]
    !(following.type == "LO16" && following.symbol === current.symbol && following.addend == current.addend)
end
function relocation_value(type,symbol,addend,place,gp)
    value = symbol+addend
    type in ("REL32","CALL24") && (value -= place)
    type == "GPREL16" && (value -= gp)
    field = type == "HI16" ? mod(fld(mod(value,2^32)+32768,65536),65536) :
        type == "CALL24" ? mod(fld(value,4),2^24) : mod(value,2^(8*WIDTHS[type]))
    within_range = !haskey(RANGES,type) || RANGES[type][1] <= value < RANGES[type][2]
    value,field,within_range
end
