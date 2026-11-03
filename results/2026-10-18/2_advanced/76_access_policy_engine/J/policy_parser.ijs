parse_target =: 3 : 0
    alternatives =. 0$a:
    for_alternative. ' | 'split_text y do.
        clauses =. 0$a:
        for_clause. ' & 'split_text >alternative do.
            'reference operator literal' =. split_words >clause
            mandatory =. '!'={:reference
            if. mandatory do.
                reference =. }:reference
            end.
            tree =. parse_expression literal
            clauses =. clauses,<(<reference),(<mandatory),(<operator),<tree
        end.
        alternatives =. alternatives,<clauses
    end.
    alternatives
)
parse_attachment =: 3 : 0
    'effect rest' =. split_first y
    'identifier arguments_text' =. split_first rest
    arguments =. 0$a:
    if. #arguments_text do.
        for_argument. ';'split_text arguments_text do.
            text =. trim >argument
            equals =. text i.'='
            name =. equals{.text
            tree =. parse_expression (equals+1)}.text
            arguments =. arguments,<(<name),<tree
        end.
    end.
    (<effect-:'DENY'),(<identifier),<arguments
)
read_policies =: 3 : 0
    ElementKinds =: 0$a:
    ElementIds =: 0$a:
    Behaviors =: 0$a:
    Parents =: i.0
    Children =: 0$a:
    Targets =: 0$a:
    Conditions =: 0$a:
    Obligations =: 0$a:
    Advice =: 0$a:
    stack =. i.0
    for_line. read_lines 'input/policies.txt' do.
        line =. trim >line
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        'keyword rest' =. split_first line
        if. (<keyword)e.'POLICYSET';'POLICY';'RULE' do.
            'identifier behavior' =. split_words rest
            index =. #ElementIds
            parent =. _1
            if. #stack do.
                parent =. {:stack
                Children =: (<(parent{::Children),index)parent}Children
            end.
            kind =. (('POLICYSET';'POLICY';'RULE')i.<keyword){::'policyset';'policy';'rule'
            ElementKinds =: ElementKinds,<kind
            ElementIds =: ElementIds,<identifier
            Behaviors =: Behaviors,<behavior
            Parents =: Parents,parent
            Children =: Children,<i.0
            Targets =: Targets,<0$a:
            Conditions =: Conditions,<0$a:
            Obligations =: Obligations,<0$a:
            Advice =: Advice,<0$a:
            stack =. stack,index
        elseif. keyword-:'END' do.
            stack =. }:stack
        else.
            index =. {:stack
            select. keyword
            case. 'TARGET' do.
                Targets =: (<(index{::Targets),<parse_target rest)index}Targets
            case. 'CONDITION' do.
                Conditions =: (<parse_expression rest)index}Conditions
            case. 'OBLIGATION' do.
                Obligations =: (<(index{::Obligations),<parse_attachment rest)index}Obligations
            case. 'ADVICE' do.
                Advice =: (<(index{::Advice),<parse_attachment rest)index}Advice
            end.
        end.
    end.
    RuleIndices =: I.ElementKinds=<'rule'
    PolicyIndices =: I.ElementKinds=<'policy'
    i.0
)
