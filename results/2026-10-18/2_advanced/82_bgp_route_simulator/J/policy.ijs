NoExport =: 65535 65281
parse_community =: 3 : 0
    if. y-:'NO_EXPORT' do.
        NoExport
    else.
        >parse_integer&.><;._1 ':',y
    end.
)
parse_communities =: 3 : 0
    result =. 0 2$0
    for_community. y do.
        result =. result,parse_community >community
    end.
    /:~~.result
)
community_member =: 4 : '+./x-:"1 y'
community_text =: 3 : 0
    if. y-:NoExport do.
        'NO_EXPORT'
    else.
        (integer 0{y),':',integer 1{y
    end.
)
communities_text =: 3 : 0
    if. 0=#y do.
        '-' return.
    end.
    ','join community_text&.><"1 /:~y
)
edit_communities =: 4 : 0
    edited =. y
    for_action. x{::RuleActions do.
        'kind value' =. >action
        if. kind-:'ADD' do.
            if. -.value community_member edited do.
                edited =. edited,value
            end.
        elseif. kind-:'REMOVE' do.
            edited =. edited#~-.value-:"1 edited
        end.
    end.
    /:~edited
)
read_policies =: 3 : 0
    ListNames =: 0$a:
    ListEntries =: 0$a:
    RuleNames =: 0$a:
    RuleActive =: i.0
    RuleOwners =: i.0
    RuleDirections =: i.0
    RuleTargets =: 0$a:
    RuleConditions =: 0$a:
    RuleActions =: 0$a:
    RuleDeny =: i.0
    RuleAllow =: i.0
    RuleLocalPref =: i.0
    RuleMed =: i.0
    RulePrepend =: i.0
    for_line. read_lines 'input/policies.txt' do.
        fields =. split_words >line
        if. 'PLIST'-:0{::fields do.
            name =. 1{::fields
            index =. ListNames i.<name
            if. index=#ListNames do.
                ListNames =: ListNames,<name
                ListEntries =: ListEntries,<0$a:
            end.
            prefix =. parse_prefix 3{::fields
            low =. 1{prefix
            high =. low
            position =. 4
            if. position<#fields do.
                if. 'GE'-:position{::fields do.
                    low =. parse_integer(position+1){::fields
                    high =. 32
                    position =. position+2
                end.
            end.
            if. position<#fields do.
                high =. parse_integer(position+1){::fields
            end.
            permit =. 'PERMIT'-:2{::fields
            entry =. (<permit),(<prefix),(<low),<high
            ListEntries =: (<(index{::ListEntries),<entry)index}ListEntries
            continue.
        end.
        RuleNames =: RuleNames,1{fields
        RuleActive =: RuleActive,'ON'-:2{::fields
        RuleOwners =: RuleOwners,ASNumbers i.parse_integer 3{::fields
        RuleDirections =: RuleDirections,'EXPORT'-:4{::fields
        RuleTargets =: RuleTargets,5{fields
        separator =. fields i.<'THEN'
        conditions =. 0$a:
        position =. 6
        while. position<separator do.
            kind =. position{::fields
            value =. (position+1){::fields
            select. kind
            case. 'PREFIX' do. value =. ListNames i.<value
            case. 'CONTAINS';'ORIGINAS' do. value =. parse_integer value
            case. 'LENGTH' do. value =. >parse_integer&.><;._1 '-',value
            case. 'COMMUNITY' do. value =. parse_community value
            end.
            conditions =. conditions,<kind;value
            position =. position+2
        end.
        RuleConditions =: RuleConditions,<conditions
        deny =. 0
        allow =. 0
        local_pref =. _1
        med =. _1
        prepend =. _1
        actions =. 0$a:
        position =. separator+1
        while. position<#fields do.
            kind =. position{::fields
            position =. position+1
            value =. i.0
            if. -.(<kind)e.;:'DENY ALLOW' do.
                token =. position{::fields
                position =. position+1
                if. (<kind)e.;:'ADD REMOVE' do.
                    value =. parse_community token
                else.
                    value =. parse_integer token
                end.
            end.
            select. kind
            case. 'DENY' do. deny =. 1
            case. 'ALLOW' do. allow =. 1
            case. 'LOCALPREF' do. local_pref =. value
            case. 'MED' do. med =. value
            case. 'PREPEND' do. prepend =. value
            end.
            actions =. actions,<kind;value
        end.
        RuleActions =: RuleActions,<actions
        RuleDeny =: RuleDeny,deny
        RuleAllow =: RuleAllow,allow
        RuleLocalPref =: RuleLocalPref,local_pref
        RuleMed =: RuleMed,med
        RulePrepend =: RulePrepend,prepend
    end.
    RuleHits =: (#RuleNames)$0
)
prefix_permitted =: 4 : 0
    for_entry. x{::ListEntries do.
        'permit prefix low high' =. >entry
        if. ((1{y)>:low)*.((1{y)<:high)*.prefix contains_address 0{y do.
            permit return.
        end.
    end.
    0
)
applied_rule =: 3 : 0
    'direction owner link prefix path communities' =. y
    neighbor =. (owner other_end link){ASNumbers
    for_rule. I.RuleActive*.(RuleOwners=owner)*.RuleDirections=direction do.
        target =. rule{::RuleTargets
        if. (-.(,target)-:,'*')*.(-.target-:integer neighbor)*.-.target-:link{::LinkNames do.
            continue.
        end.
        matches =. 1
        for_condition. rule{::RuleConditions do.
            'kind value' =. >condition
            select. kind
            case. 'PREFIX' do. matches =. value prefix_permitted prefix{AllPrefixes
            case. 'CONTAINS' do. matches =. value e.path
            case. 'ORIGINAS' do.
                origin_as =. owner{ASNumbers
                if. #path do.
                    origin_as =. {:path
                end.
                matches =. value=origin_as
            case. 'LENGTH' do. matches =. ((#path)>:0{value)*.(#path)<:1{value
            case. 'COMMUNITY' do. matches =. value community_member communities
            end.
            if. -.matches do.
                break.
            end.
        end.
        if. matches do.
            rule return.
        end.
    end.
    _1
)
