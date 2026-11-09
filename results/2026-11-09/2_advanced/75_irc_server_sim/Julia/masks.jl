function mask_matches(mask,value)
    mask,value = irc_fold(mask),irc_fold(value)
    pattern,position,star,restart = 1,1,0,1
    while position<=length(value)
        if pattern<=length(mask) && mask[pattern]=='*'
            star = pattern
            pattern += 1
            restart = position
        elseif pattern<=length(mask) && (mask[pattern]=='?' || mask[pattern]==value[position])
            pattern += 1
            position += 1
        elseif star!=0
            restart += 1
            position = restart
            pattern = star+1
        else
            return false
        end
    end
    while pattern<=length(mask) && mask[pattern]=='*'
        pattern += 1
    end
    pattern==length(mask)+1
end
function normalize_mask(argument)
    occursin('!',argument) && occursin('@',argument) && return argument
    occursin('@',argument) && return "*!"*argument
    occursin('!',argument) && return argument*"@*"
    occursin('.',argument) && return "*!*@"*argument
    argument*"!*@*"
end
