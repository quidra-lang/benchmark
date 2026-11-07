CodeOrder =: ;:'SYNTAX ORPHAN DUPLICATE KEY_NO_DECOMP KEY_UNREACHABLE SYNON_UNUSED PRE_CHAIN SYNON_UNKNOWN RULE_NO_REASM RULE_SHADOWED REF_UNBOUND TARGET_UNDEFINED TARGET_CYCLE'
ErrorCodes =: ;:'SYNTAX ORPHAN DUPLICATE SYNON_UNKNOWN REF_UNBOUND TARGET_UNDEFINED TARGET_CYCLE'
unknown_groups =: 3 : 0
    unknown =. 0$a:
    for_box. y do.
        element =. >box
        if. '@'={.element do.
            if. -.(}.element) has_key GroupWords do. unknown =. unknown,<}.element end.
        end.
    end.
    unknown
)
item_references =: 3 : 0
    'kind text args line' =. y
    references =. 0$0
    if. kind-:'REASM' do.
        for_position. i.#text do.
            chunk =. (3<.(#text)-position){.position}.text
            if. is_reference chunk do. references =. references,Digits i.1{chunk end.
        end.
    elseif. kind-:'RESTATE' do.
        for_box. }.args do.
            if. is_reference >box do. references =. references,Digits i.1{>box end.
        end.
    end.
    references
)
lint_script =: 3 : 0
    replacementwords =. targets =. usedgroups =. 0$a:
    for_box. Pres do. replacementwords =. replacementwords,1{::>box end.
    for_box. Items do.
        item =. >box
        if. (0{item)e.;:'GOTO RESTATE' do. targets =. targets,0{2{::item end.
    end.
    count =. #Keywords
    reach =. =/~i.count
    for_index. i.count do.
        keyword =. index{::Keywords
        for_ruleid. 4{::keyword do.
            for_itemid. 3{::ruleid{::Rules do.
                item =. itemid{::Items
                if. (0{item)e.;:'GOTO RESTATE' do.
                    target =. 0{2{::item
                    if. target e.KeywordWords do. reach =. 1 (<index,KeywordWords i.target)}reach end.
                end.
            end.
        end.
    end.
    for_k. i.count do. reach =. reach+.((k{"1 reach)*/k{reach) end.
    for_box. Rules do.
        for_elementbox. 1{::>box do.
            element =. >elementbox
            if. '@'={.element do. usedgroups =. usedgroups,<}.element end.
        end.
    end.
    for_box. Keywords do.
        'word rank line memories decomps' =. >box
        if. 0=#decomps do. add_diagnostic (<line),(<'KEY_NO_DECOMP'),<'keyword ',word,' has no DECOMP' end.
        if. word has_key PreTable do.
            if. (-.(<word)e.replacementwords)*.-.(<word)e.targets do.
                add_diagnostic (<line),(<'KEY_UNREACHABLE'),<'keyword ',word,' is replaced by PRE'
            end.
        end.
    end.
    for_box. Groups do.
        'name members line' =. >box
        if. -.(<name)e.usedgroups do. add_diagnostic (<line),(<'SYNON_UNUSED'),<'group ',name,' is never used' end.
    end.
    for_box. Pres do.
        'source replacement line' =. >box
        for_wordbox. replacement do.
            word =. >wordbox
            if. word has_key PreTable do. add_diagnostic (<line),(<'PRE_CHAIN'),<'replacement ',word,' is itself replaced by PRE' end.
        end.
    end.
    for_keywordid. i.count do.
        'word rank line memories decomps' =. keywordid{::Keywords
        for_idsbox. (<memories),<decomps do.
            ids =. >idsbox
            for_position. i.#ids do.
                'kind pattern ruleline itemids' =. (position{ids){::Rules
                unknown =. unknown_groups pattern
                for_groupbox. unknown do. add_diagnostic (<ruleline),(<'SYNON_UNKNOWN'),<'unknown group ',>groupbox end.
                if. 0=#itemids do. add_diagnostic (<ruleline),(<'RULE_NO_REASM'),<'rule has no reassembly' end.
                if. 0=#unknown do.
                    for_earlierid. position{.ids do.
                        earlier =. earlierid{::Rules
                        if. 0=#unknown_groups 1{::earlier do.
                            if. (1{::earlier) pattern_covers pattern do.
                                add_diagnostic (<ruleline),(<'RULE_SHADOWED'),<'pattern is shadowed by line ',number 2{::earlier
                                break.
                            end.
                        end.
                    end.
                end.
                wildcards =. +/is_wildcard&>pattern
                for_itemid. itemids do.
                    item =. itemid{::Items
                    itemline =. 3{::item
                    for_reference. item_references item do.
                        if. (reference=0)+.reference>wildcards do.
                            add_diagnostic (<itemline),(<'REF_UNBOUND'),<'reference (',(number reference),') is not bound'
                        end.
                    end.
                    if. (0{item)e.;:'GOTO RESTATE' do.
                        target =. 0{::2{::item
                        targetid =. KeywordWords i.<target
                        if. targetid=count do. add_diagnostic (<itemline),(<'TARGET_UNDEFINED'),<'target ',target,' is not a keyword'
                        elseif. (<targetid,keywordid){reach do.
                            add_diagnostic (<itemline),(<'TARGET_CYCLE'),<'edge ',word,' -> ',target,' is on a cycle'
                        end.
                    end.
                end.
            end.
        end.
    end.
    orderkeys =. 0 3$0
    for_index. i.#Diagnostics do.
        diagnostic =. index{::Diagnostics
        orderkeys =. orderkeys,(0{::diagnostic),(CodeOrder i.1{diagnostic),index
    end.
    Diagnostics =: (/:orderkeys){Diagnostics
    i.0
)
