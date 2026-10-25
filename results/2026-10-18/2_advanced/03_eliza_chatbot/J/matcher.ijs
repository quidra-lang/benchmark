is_wildcard =: 3 : '((<y)e.;:''* #'')+.''@''={.y'
word_fits =: 4 : 0
    if. x-:'#' do. 1 return. end.
    if. '@'={.x do.
        group =. }.x
        if. -.group has_key GroupWords do. 0 return. end.
        (<y)e.group get_key GroupWords
    else. x-:y end.
)
match_search =: 3 : 0
    'pattern words position start bindings' =. y
    if. position=#pattern do. (<start=#words),<bindings return. end.
    element =. position{::pattern
    if. element-:'*' do.
        for_finish. start+i.1+(#words)-start do.
            bound =. (finish-start){.start}.words
            found =. match_search (<pattern),(<words),(<position+1),(<finish),<(bindings,<bound)
            if. 0{::found do. found return. end.
        end.
    elseif. start<#words do.
        if. element word_fits start{::words do.
            if. is_wildcard element do. bindings =. bindings,<,start{words end.
            match_search (<pattern),(<words),(<position+1),(<start+1),<bindings return.
        end.
    end.
    (<0),<0$a:
)
match_pattern =: 4 : 'match_search (<x),(<y),(<0),(<0),<0$a:'
element_covers =: 4 : 0
    if. x-:'#' do. -.y-:'*' return. end.
    if. '@'={.x do.
        members =. (}.x) get_key GroupWords
        if. '@'={.y do. *./((}.y) get_key GroupWords)e.members
        else. (<y)e.members end.
    else. x-:y end.
)
cover_search =: 3 : 0
    'earlier later position start' =. y
    if. position=#earlier do. start=#later return. end.
    element =. position{::earlier
    if. element-:'*' do.
        for_finish. start+i.1+(#later)-start do.
            if. cover_search (<earlier),(<later),(<position+1),<finish do. 1 return. end.
        end.
    elseif. start<#later do.
        if. element element_covers start{::later do.
            cover_search (<earlier),(<later),(<position+1),<start+1 return.
        end.
    end.
    0
)
pattern_covers =: 4 : 'cover_search (<x),(<y),(<0),<0'
