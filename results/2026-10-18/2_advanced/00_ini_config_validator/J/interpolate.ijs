NB. Cache (success; string), including failures, independently of literal dollars.
reference_report =: 4 : 0
    'document line' =. x
    'code message' =. y
    ReferenceDiagnostics =: ReferenceDiagnostics,<(<document),(<line),(<code),<message
)
expand_key =: 3 : 0
    if. y has_key ReferenceResults do. y get_key ReferenceResults return. end.
    ReferenceProgress =: ReferenceProgress,<y
    result =. evaluate_reference y
    ReferenceProgress =: }:ReferenceProgress
    ReferenceResults =: ((<y),<result) put_key ReferenceResults
    result
)
evaluate_reference =: 3 : 0
    key =. y
    definition =. key get_key ReferenceConfiguration
    text =. 0{::definition
    origin =. 1{::definition
    result =. ''
    position =. 0
    while. position<#text do.
        if. -. '${'-:2{.position}.text do.
            char =. position{text
            if. char=LITERAL_DOLLAR do. char =. '$' end.
            result =. result,char
            position =. position+1
            continue.
        end.
        tail =. (position+2)}.text
        close =. tail i.'}'
        reference =. close{.tail
        if. (close=#tail) +. -.is_section_name reference do.
            origin reference_report (<'E_BAD_REF'),<key,': invalid reference'
            (<0),<'' return.
        end.
        target =. reference
        if. -.'.'e.reference do. target =. (section_of key),'.',reference end.
        if. -.target has_key ReferenceConfiguration do.
            origin reference_report (<'E_UNDEFINED'),<key,': undefined reference ',target
            (<0),<'' return.
        end.
        if. (<target)e.ReferenceProgress do.
            path =. ((ReferenceProgress i.<target)}.ReferenceProgress),<target
            target_origin =. 1{::target get_key ReferenceConfiguration
            target_origin reference_report (<'E_CYCLE'),<'interpolation cycle ',' -> ' join path
            ReferenceCycles =: ~.ReferenceCycles,path
            expanded =. (<0),<''
        else.
            expanded =. expand_key target
        end.
        if. -.0{::expanded do.
            if. -.(<key)e.ReferenceCycles do.
                origin reference_report (<'E_DEPENDENCY'),<key,': depends on failed key ',target
            end.
            (<0),<'' return.
        end.
        result =. result,1{::expanded
        position =. position+close+3
    end.
    (<1),<result
)
expand_values =: 3 : 0
    ReferenceConfiguration =: y
    ReferenceResults =: empty_table ''
    ReferenceProgress =: ReferenceCycles =: ReferenceDiagnostics =: 0$a:
    for_key. sort_keys table_keys y do. expand_key >key end.
    (<ReferenceResults),<ReferenceDiagnostics
)
