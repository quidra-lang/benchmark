load 'molecule.ijs'
load 'smiles_parser.ijs'
load 'rings_aromatic.ijs'
load 'canonical.ijs'
load 'search.ijs'

QueryKinds =: ;:'MATCH CONTAINS MATRIX NEAREST WITHIN COMPARE CLUSTER'
ArgumentRanges =: 7 2$1 1 2 2 2 12 2 2 2 2 2 2 1 1
SystemKinds =: ;:'isolated fused spiro bridged'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : '".y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do.
            text =. text,x
        end.
        text =. text,i{::y
    end.
    text
)
split_char =: 4 : 0
    fields =. 0$a:
    text =. ''
    for_character. y do.
        if. character=x do.
            fields =. fields,<text
            text =. ''
        else.
            text =. text,character
        end.
    end.
    fields,<text
)
split_words =: 3 : 0
    ' 'split_char y
)
data_lines =: 3 : 0
    result =. 0$a:
    lines =. <;._2 (1!:1 <'input/',y)
    for_i. i.#lines do.
        line =. i{::lines
        if. 0=#line do.
            continue.
        end.
        if. '#'~:{.line do.
            result =. result,<( <i+1),<line
        end.
    end.
    result
)
valid_name =: 3 : 0
    allowed =. 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
    (0<#y)*.(32>:#y)*.*/y e.allowed
)
valid_number =: 4 : 0
    if. (0=#y)+.2<#y do.
        0 return.
    end.
    if. -.*/y e.'0123456789' do.
        0 return.
    end.
    if. (1<#y)*.'0'={.y do.
        0 return.
    end.
    number =. parse_integer y
    ((0{x)<:number)*.number<:1{x
)
read_threshold =: 3 : 0
    parts =. '/'split_char y
    if. 2~:#parts do.
        i.0 return.
    end.
    if. -.(0 99 valid_number 0{::parts)*.1 99 valid_number 1{::parts do.
        i.0 return.
    end.
    values =. parse_integer&>parts
    if. (0{values)>1{values do.
        i.0
    else.
        values
    end.
)
fraction_text =: 3 : 0
    'numerator denominator' =. y
    divisor =. numerator+.denominator
    (integer numerator intdiv divisor),'/',integer denominator intdiv divisor
)
fraction_compare =: 4 : '*((0{x)*1{y)-(0{y)*1{x'
atom_numbers =: 4 : 'x join integer&.>1+y'
member_names =: 3 : ''',''join y{MoleculeNames'
record_cause =: 3 : 0
    index =. CauseNames i.<y
    if. index=#CauseNames do.
        CauseNames =: CauseNames,<y
        CauseCounts =: CauseCounts,0
    end.
    CauseCounts =: (1+index{CauseCounts)index}CauseCounts
)
analyze =: 3 : 0
    molecule =. find_rings y
    atoms =. 0{::molecule
    bonds =. 1{::molecule
    for_index. i.#bonds do.
        'first second symbol kind multiplicity ring' =. index{bonds
        kind =. symbol
        if. symbol=0 do.
            kind =. 1
            if. ring*.(1{first{atoms)*.1{second{atoms do.
                kind =. 4
            end.
        end.
        bonds =. kind(<index,3)}bonds
    end.
    molecule =. (<bonds)1}molecule
    needing =. i.0
    for_atom. i.#atoms do.
        if. molecule needs_pi atom,4{atom{atoms do.
            needing =. needing,atom
        end.
    end.
    'error column molecule' =. molecule kekulize needing
    if. #error do.
        (<error),(<column),<0$a: return.
    end.
    for_index. i.#atoms do.
        atom =. index{atoms
        total =. molecule bond_total index
        if. 5{atom do.
            maximum =. {: (0{atom){::Valences
            if. (total+4{atom)>maximum+|3{atom do.
                (<'bad valence'),(<6{atom),<0$a: return.
            end.
        else.
            hydrogens =. atom organic_hydrogens total
            if. hydrogens=_1 do.
                (<'bad valence'),(<6{atom),<0$a: return.
            end.
            atoms =. hydrogens(<index,4)}atoms
        end.
    end.
    molecule =. (<atoms)0}molecule
    (<''),(<0),<molecule
)
molecular_properties =: 3 : 0
    atoms =. 0{::y
    bonds =. 1{::y
    counts =. (#ElementSymbols)$0
    weight =. 0
    hydrogens =. +/4{"1 atoms
    heavy =. 0
    heavy_degrees =. (#atoms)$0
    triple_ends =. (#atoms)$0
    for_bond. bonds do.
        if. 3=4{bond do.
            triple_ends =. 1(2{.bond)}triple_ends
        end.
    end.
    donors =. 0
    acceptors =. 0
    for_index. i.#atoms do.
        atom =. index{atoms
        element =. 0{atom
        counts =. (1+element{counts)element}counts
        mass =. 2{atom
        if. mass do.
            weight =. weight+1000*mass
        else.
            weight =. weight+element{AtomicWeights
        end.
        heavy =. heavy+element~:HydrogenElement
        neighbors =. y atom_neighbors index
        elements =. 0{"1 neighbors{atoms
        heavy_degrees =. (+/elements~:HydrogenElement)index}heavy_degrees
        if. element e.NitrogenElement,OxygenElement do.
            acceptors =. acceptors+1
            attached =. (4{atom)++/elements=HydrogenElement
            donors =. donors+attached>:1
        end.
    end.
    counts =. (hydrogens+HydrogenElement{counts)HydrogenElement}counts
    weight =. weight+hydrogens*HydrogenElement{AtomicWeights
    elements =. I.counts>0
    elements =. (/:elements{ElementSymbols){elements
    if. CarbonElement{counts do.
        prefix =. ,CarbonElement
        if. HydrogenElement{counts do.
            prefix =. prefix,HydrogenElement
        end.
        elements =. prefix,elements-.prefix
    end.
    formula =. ''
    for_element. elements do.
        formula =. formula,element{::ElementSymbols
        if. 1~:element{counts do.
            formula =. formula,integer element{counts
        end.
    end.
    rotatable =. 0
    for_bond. bonds do.
        'first second symbol kind multiplicity ring' =. bond
        if. (multiplicity~:1)+.ring do.
            continue.
        end.
        if. ((first{heavy_degrees)<2)+.(second{heavy_degrees)<2 do.
            continue.
        end.
        rotatable =. rotatable+-. (first{triple_ends)+.second{triple_ends
    end.
    violations =. (weight>500000)+(donors>5)+acceptors>10
    lipinski =. 'pass'
    if. violations>1 do.
        lipinski =. 'fail'
    end.
    charge =. +/3{"1 atoms
    (<formula),(<weight),(<heavy),(<rotatable),(<donors),(<acceptors),(<lipinski),<charge
)
scaffold_molecule =: 3 : 0
    if. 0=#3{::y do.
        0$a: return.
    end.
    atoms =. 0{::y
    bonds =. 1{::y
    ring_atoms =. 4{::y
    remaining =. (#atoms)$1
    while. 1 do.
        leaf =. _1
        for_atom. I.remaining*.-.ring_atoms do.
            neighbors =. y atom_neighbors atom
            if. 1=+/neighbors{remaining do.
                leaf =. atom
                break.
            end.
        end.
        if. leaf=_1 do.
            break.
        end.
        remaining =. 0 leaf}remaining
    end.
    kept =. remaining
    for_bond. bonds do.
        'first second symbol kind multiplicity ring' =. bond
        if. kind=2 do.
            if. first{remaining do.
                kept =. 1 second}kept
            end.
            if. second{remaining do.
                kept =. 1 first}kept
            end.
        end.
    end.
    numbers =. I.kept
    renumber =. (#atoms)$_1
    renumber =. (i.#numbers)numbers}renumber
    new_atoms =. numbers{atoms
    adjacent =. 2{::y
    for_i. i.#numbers do.
        number =. i{numbers
        added =. 0
        for_neighbor. (y atom_neighbors number)#~-. (y atom_neighbors number){kept do.
            bond =. (<number,neighbor){adjacent
            added =. added+4{bond{bonds
        end.
        new_atoms =. (added+4{i{new_atoms)(<i,4)}new_atoms
    end.
    new_bonds =. 0 6$0
    for_bond. bonds do.
        if. */(2{.bond){kept do.
            changed =. ((2{.bond){renumber),2}.bond
            new_bonds =. new_bonds,changed
        end.
    end.
    scaffold =. new_atoms new_molecule new_bonds
    rings =. 0$a:
    for_ring. 3{::y do.
        rings =. rings,<(>ring){renumber
    end.
    scaffold =. (<rings)3}scaffold
    (<numbers{ring_atoms)4}scaffold
)
ring_systems =: 3 : 0
    rings =. 3{::y
    count =. #rings
    adjacent =. 2{::y
    relations =. (count,count)$0
    for_first. i.count do.
        a =. first{::rings
        for_second. (first+1)+i.count-(first+1) do.
            b =. second{::rings
            shared =. a#~a e.b
            if. 0=#shared do.
                continue.
            elseif. 1=#shared do.
                relation =. 2
            elseif. 2=#shared do.
                if. _1~:(<shared){adjacent do.
                    relation =. 1
                else.
                    relation =. 3
                end.
            else.
                relation =. 3
            end.
            relations =. relation(<first,second)}relations
            relations =. relation(<second,first)}relations
        end.
    end.
    remaining =. count$1
    systems =. 0$a:
    while. +./remaining do.
        start =. {.I.remaining
        remaining =. 0 start}remaining
        queue =. ,start
        front =. 0
        while. front<#queue do.
            ring =. front{queue
            front =. front+1
            for_neighbor. I.0~:ring{relations do.
                if. neighbor{remaining do.
                    remaining =. 0 neighbor}remaining
                    queue =. queue,neighbor
                end.
            end.
        end.
        members =. /:~queue
        kind =. 0
        if. 1<#members do.
            kinds =. ,members{"1 members{relations
            if. 3 e.kinds do.
                kind =. 3
            elseif. 1 e.kinds do.
                kind =. 1
            else.
                kind =. 2
            end.
        end.
        atoms =. ~.;members{rings
        systems =. systems,<( <members),(<#atoms),<kind
    end.
    systems
)
read_molecules =: 3 : 0
    Molecules =: 0$a:
    MoleculeNames =: 0$a:
    lines =. data_lines 'molecules.smi'
    errors =. 0$a:
    reserved =. 0$a:
    for_record. lines do.
        'number line' =. >record
        tokens =. split_words line
        bad =. 2~:#tokens
        if. -.bad do.
            bad =. (0=#0{::tokens)+.-.valid_name 1{::tokens
        end.
        if. bad do.
            errors =. errors,<'line ',(integer number),': bad line'
            record_cause 'bad line'
            continue.
        end.
        'smiles name' =. tokens
        prefix =. 'line ',(integer number),' ',name,': '
        if. (<name)e.reserved do.
            errors =. errors,<prefix,'duplicate name'
            record_cause 'duplicate name'
            continue.
        end.
        reserved =. reserved,<name
        'error column molecule' =. 0 parse_smiles smiles
        if. 0=#error do.
            'error column molecule' =. analyze molecule
        end.
        if. #error do.
            errors =. errors,<prefix,error,' at column ',integer column
            record_cause error
            continue.
        end.
        molecule =. (<name)5}molecule
        Molecules =: Molecules,<molecule
        MoleculeNames =: MoleculeNames,<name
    end.
    line =. 'MOLECULES lines=',(integer #lines),' valid=',integer #Molecules
    MoleculeErrors =: (<line,' errors=',integer #errors),errors
)
prepare_molecules =: 3 : 0
    for_index. i.#Molecules do.
        molecule =. index{::Molecules
        properties =. molecular_properties molecule
        'canonical classes' =. canonicalize molecule
        scaffold =. scaffold_molecule molecule
        scaffold_text =. ''
        if. #scaffold do.
            scaffold_text =. 0{::canonicalize scaffold
        end.
        systems =. ring_systems molecule
        aromatic =. i.0
        atoms =. 0{::molecule
        for_ring. 3{::molecule do.
            aromatic =. aromatic,*/1{"1 (>ring){atoms
        end.
        'bits paths' =. fingerprint molecule
        details =. (<properties),(<canonical),(<classes),(<scaffold_text),(<systems),(<aromatic),(<bits),<paths
        Molecules =: (<molecule,details)index}Molecules
    end.
)
check_arguments =: 3 : 0
    'kind arguments' =. y
    QPattern =: 0$a:
    QThreshold =: i.0
    QCount =: 0
    range =. (QueryKinds i.<kind){ArgumentRanges
    if. ((#arguments)<0{range)+.(#arguments)>1{range do.
        'bad arguments' return.
    end.
    select. kind
    case. 'MATCH' do.
        'error column pattern' =. 1 parse_smiles 0{::arguments
        if. #error do.
            'bad pattern ',error,' at column ',integer column return.
        end.
        QPattern =: pattern
    case. 'CLUSTER' do.
        QThreshold =: read_threshold 0{::arguments
        if. 0=#QThreshold do.
            'bad threshold' return.
        end.
    case. 'CONTAINS';'MATRIX';'COMPARE' do.
        for_name. arguments do.
            if. -.name e.MoleculeNames do.
                'unknown molecule ',>name return.
            end.
        end.
        if. (#~.arguments)~:#arguments do.
            'repeated molecule' return.
        end.
    case. 'NEAREST';'WITHIN' do.
        name =. 0{::arguments
        if. -.(<name)e.MoleculeNames do.
            'unknown molecule ',name return.
        end.
        if. kind-:'NEAREST' do.
            text =. 1{::arguments
            if. -.1 99 valid_number text do.
                'bad count' return.
            end.
            QCount =: parse_integer text
        else.
            QThreshold =: read_threshold 1{::arguments
            if. 0=#QThreshold do.
                'bad threshold' return.
            end.
        end.
    end.
    ''
)
read_queries =: 3 : 0
    Queries =: 0$a:
    errors =. 0$a:
    reserved =. 0$a:
    lines =. data_lines 'queries.txt'
    for_record. lines do.
        'number line' =. >record
        fields =. split_words line
        kind =. 0{::fields
        identifier =. ''
        if. 1<#fields do.
            identifier =. 1{::fields
        end.
        prefix =. 'line ',integer number
        if. -.(<kind)e.QueryKinds do.
            reason =. 'unknown query'
            text =. prefix,': ',reason
        elseif. -.valid_name identifier do.
            reason =. 'bad id'
            text =. prefix,' ',kind,': ',reason
        else.
            if. (<identifier)e.reserved do.
                reason =. 'duplicate id'
            else.
                reserved =. reserved,<identifier
                arguments =. 2}.fields
                reason =. check_arguments(<kind),<arguments
                if. 0=#reason do.
                    query =. (<kind),(<identifier),(<arguments),(<QPattern),(<QThreshold),<QCount
                    Queries =: Queries,<query
                    continue.
                end.
            end.
            text =. prefix,' ',kind,' ',identifier,': ',reason
        end.
        errors =. errors,<text
        cause =. reason
        if. 'bad pattern '-:12{.reason do.
            cause =. 'bad pattern'
        elseif. 'unknown molecule '-:17{.reason do.
            cause =. 'unknown molecule'
        end.
        record_cause cause
    end.
    line =. 'QUERIES lines=',(integer #lines),' valid=',integer #Queries
    QueryErrors =: (<line,' errors=',integer #errors),errors
)
properties_lines =: 3 : 0
    lines =. <'name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski'
    for_molecule. Molecules do.
        molecule =. >molecule
        values =. 6{::molecule
        weight =. 1{::values
        weight_text =. (integer weight intdiv 1000),'.',_3{.'000',integer 1000|weight
        fields =. (5{molecule),(0{values),<weight_text
        numbers =. (2{::values),(#3{::molecule),(3{::values),(4{::values),5{::values
        fields =. fields,(integer&.>numbers),6{values
        lines =. lines,<','join fields
    end.
    lines
)
group_indices =: 3 : 0
    groups =. 0$a:
    for_key. ~.y do.
        members =. I.y=key
        groups =. groups,<key,<members
    end.
    groups
)
canonical_paragraphs =: 3 : 0
    canonicals =. 0$a:
    formulas =. 0$a:
    scaffold_keys =. 0$a:
    scaffold_indices =. i.0
    for_i. i.#Molecules do.
        molecule =. i{::Molecules
        canonicals =. canonicals,<7{::molecule
        formulas =. formulas,<0{::6{::molecule
        scaffold =. 9{::molecule
        if. #scaffold do.
            scaffold_keys =. scaffold_keys,<scaffold
            scaffold_indices =. scaffold_indices,i
        end.
    end.
    by_canonical =. group_indices canonicals
    by_formula =. group_indices formulas
    by_scaffold =. group_indices scaffold_keys
    canonical =. <'CANONICAL molecules=',(integer #Molecules),' unique=',integer #by_canonical
    for_i. i.#Molecules do.
        molecule =. i{::Molecules
        charge =. 7{::6{::molecule
        charge_text =. integer charge
        if. charge>0 do.
            charge_text =. '+',charge_text
        end.
        line =. (i{::MoleculeNames),' ',(7{::molecule),' classes=',integer 8{::molecule
        canonical =. canonical,<line,' charge=',charge_text
    end.
    duplicate_groups =. 0$a:
    duplicate_count =. 0
    for_group. by_canonical do.
        group =. >group
        members =. 1{::group
        if. 1<#members do.
            duplicate_groups =. duplicate_groups,<group
            duplicate_count =. duplicate_count+#members
        end.
    end.
    duplicates =. <'DUPLICATES groups=',(integer #duplicate_groups),' molecules=',integer duplicate_count
    for_i. i.#duplicate_groups do.
        'key members' =. i{::duplicate_groups
        duplicates =. duplicates,<'group ',(integer i+1),' ',key,' members=',member_names members
    end.
    isomer_groups =. 0$a:
    for_group. by_formula do.
        'key members' =. >group
        forms =. #~.members{canonicals
        if. forms>:2 do.
            isomer_groups =. isomer_groups,<( <key),(<members),<forms
        end.
    end.
    isomers =. <'ISOMERS groups=',integer #isomer_groups
    for_i. i.#isomer_groups do.
        'key members forms' =. i{::isomer_groups
        line =. 'isomer ',(integer i+1),' ',key,' forms=',integer forms
        isomers =. isomers,<line,' members=',member_names members
    end.
    acyclic =. (#Molecules)-#scaffold_indices
    scaffolds =. <'SCAFFOLDS distinct=',(integer #by_scaffold),' acyclic=',integer acyclic
    texts =. 0$a:
    counts =. i.0
    for_group. by_scaffold do.
        'key members' =. >group
        texts =. texts,<key
        counts =. counts,#members
    end.
    order =. /:texts
    order =. (\:order{counts){order
    for_i. i.#order do.
        'key positions' =. (i{order){::by_scaffold
        members =. positions{scaffold_indices
        line =. 'scaffold ',(integer i+1),' ',key,' count=',integer #members
        scaffolds =. scaffolds,<line,' members=',member_names members
    end.
    (<canonical),(<duplicates),(<isomers),<scaffolds
)
ring_paragraphs =: 3 : 0
    paragraphs =. 0$a:
    sizes =. 81$0
    kinds =. 4$0
    total_rings =. 0
    total_aromatic =. 0
    for_molecule. Molecules do.
        molecule =. >molecule
        rings =. 3{::molecule
        if. 0=#rings do.
            continue.
        end.
        atoms =. 0{::molecule
        bonds =. 1{::molecule
        aromatic =. 11{::molecule
        systems =. 10{::molecule
        total_rings =. total_rings+#rings
        total_aromatic =. total_aromatic++/aromatic
        line =. 'MOLECULE ',(5{::molecule),' atoms=',(integer #atoms),' bonds=',integer #bonds
        line =. line,' rings=',(integer #rings),' aromatic=',(integer +/aromatic),' systems=',integer #systems
        line =. line,' ring_atoms=',integer +/4{::molecule
        paragraph =. <line,' ring_bonds=',integer +/5{"1 bonds
        for_i. i.#rings do.
            ring =. i{::rings
            size =. #ring
            sizes =. (1+size{sizes)size}sizes
            flag =. 'no'
            if. i{aromatic do.
                flag =. 'yes'
            end.
            hetero =. +/CarbonElement~:0{"1 ring{atoms
            line =. 'ring ',(integer i+1),' size=',(integer size),' aromatic=',flag,' hetero=',integer hetero
            paragraph =. paragraph,<line,' atoms=','-'atom_numbers ring
        end.
        for_i. i.#systems do.
            'members atom_count kind' =. i{::systems
            kinds =. (1+kind{kinds)kind}kinds
            line =. 'system ',(integer i+1),' kind=',(kind{::SystemKinds),' rings=',','atom_numbers members
            paragraph =. paragraph,<line,' atoms=',integer atom_count
        end.
        pairs =. 0$a:
        for_bond. bonds do.
            if. (4=3{bond)*.2=4{bond do.
                pairs =. pairs,<'='atom_numbers 2{.bond
            end.
        end.
        double_text =. '-'
        if. #pairs do.
            double_text =. ' 'join pairs
        end.
        paragraph =. paragraph,<'kekule ',double_text
        paragraphs =. paragraphs,<paragraph
    end.
    line =. 'SUMMARY molecules=',(integer #Molecules),' cyclic=',integer #paragraphs
    summary =. <line,' rings=',(integer total_rings),' aromatic=',integer total_aromatic
    line =. 'sizes'
    occurring =. I.sizes>0
    if. #occurring do.
        for_size. occurring do.
            line =. line,' ',(integer size),'=',integer size{sizes
        end.
    else.
        line =. line,' -'
    end.
    summary =. summary,<line
    line =. 'systems'
    for_kind. i.4 do.
        line =. line,' ',(kind{::SystemKinds),'=',integer kind{kinds
    end.
    summary =. summary,<line
    paragraphs,<summary
)
substructure_paragraphs =: 3 : 0
    paragraphs =. 0$a:
    patterns =. 0
    hits =. 0
    contains =. 0
    found =. 0
    for_query. Queries do.
        'kind identifier arguments pattern threshold count' =. >query
        select. kind
        case. 'MATCH' do.
            patterns =. patterns+1
            matches =. 0$a:
            total =. 0
            top =. _1
            top_count =. _1
            for_i. i.#Molecules do.
                'match_count unique mapping' =. pattern embeddings i{::Molecules
                if. match_count do.
                    matches =. matches,<( <i),(<match_count),(<unique),<mapping
                    total =. total+match_count
                    if. match_count>top_count do.
                        top =. i
                        top_count =. match_count
                    end.
                end.
            end.
            hits =. hits+#matches
            line =. 'MATCH ',identifier,' ',(0{::arguments),' atoms=',integer #0{::pattern
            line =. line,' bonds=',(integer #1{::pattern),' hits=',integer #matches
            paragraph =. <line,' embeddings=',integer total
            for_match. matches do.
                'index count unique mapping' =. >match
                line =. (index{::MoleculeNames),' count=',(integer count),' unique=',integer unique
                paragraph =. paragraph,<line,' map=',','atom_numbers mapping
            end.
            if. top~:_1 do.
                paragraph =. paragraph,<'top ',(top{::MoleculeNames),' count=',integer top_count
            end.
            paragraphs =. paragraphs,<paragraph
        case. 'CONTAINS' do.
            contains =. contains+1
            indices =. MoleculeNames i.arguments
            first =. (0{indices){::Molecules
            second =. (1{indices){::Molecules
            'count unique mapping' =. (molecule_pattern first)embeddings second
            line =. 'CONTAINS ',identifier,' ',(0{::arguments),' ',(1{::arguments),' result='
            if. count do.
                found =. found+1
                line =. line,'yes count=',(integer count),' unique=',(integer unique),' map=',','atom_numbers mapping
            else.
                line =. line,'no'
            end.
            paragraph =. ,<line
            paragraphs =. paragraphs,<paragraph
        end.
    end.
    line =. 'SUMMARY patterns=',(integer patterns),' hits=',(integer hits),' contains=',integer contains
    paragraph =. ,<line,' found=',integer found
    paragraphs,<paragraph
)
prepare_similarities =: 3 : 0
    count =. #Molecules
    SimilarCommon =: (count,count)$0
    SimilarUnion =: (count,count)$0
    for_first. i.count do.
        for_second. first+i.count-first do.
            a =. 12{::first{::Molecules
            b =. 12{::second{::Molecules
            'common union' =. a tanimoto b
            SimilarCommon =: common(<first,second)}SimilarCommon
            SimilarCommon =: common(<second,first)}SimilarCommon
            SimilarUnion =: union(<first,second)}SimilarUnion
            SimilarUnion =: union(<second,first)}SimilarUnion
        end.
    end.
)
similarity =: 4 : '((<x,y){SimilarCommon),(<x,y){SimilarUnion'
ranked_neighbors =: 3 : 0
    order =. i.0
    for_index. (i.#Molecules)-.y do.
        value =. y similarity index
        position =. #order
        for_i. i.#order do.
            if. 0<value fraction_compare y similarity i{order do.
                position =. i
                break.
            end.
        end.
        order =. (position{.order),index,position}.order
    end.
    order
)
matrix_paragraph =: 3 : 0
    'kind identifier arguments pattern threshold count' =. y
    selected =. MoleculeNames i.arguments
    paragraph =. <'MATRIX ',identifier,' size=',integer #selected
    for_first. selected do.
        values =. 0$a:
        for_second. selected do.
            values =. values,<fraction_text first similarity second
        end.
        paragraph =. paragraph,<'row ',(first{::MoleculeNames),' ',' 'join values
    end.
    best_first =. 0{selected
    best_second =. 1{selected
    best =. best_first similarity best_second
    for_i. i.#selected do.
        first =. i{selected
        for_second. (i+1)}.selected do.
            value =. first similarity second
            if. 0<value fraction_compare best do.
                best =. value
                best_first =. first
                best_second =. second
            end.
        end.
    end.
    line =. 'best ',(best_first{::MoleculeNames),' ',best_second{::MoleculeNames
    paragraph,<line,' ',fraction_text best
)
neighbors_paragraph =: 3 : 0
    'kind identifier arguments pattern threshold count' =. y
    source =. MoleculeNames i.0{arguments
    order =. ranked_neighbors source
    if. kind-:'NEAREST' do.
        order =. (count<.#order){.order
        heading =. 'NEAREST ',identifier,' ',(source{::MoleculeNames),' count=',integer #order
    else.
        selected =. i.0
        for_index. order do.
            if. 0<:(source similarity index)fraction_compare threshold do.
                selected =. selected,index
            end.
        end.
        order =. selected
        heading =. 'WITHIN ',identifier,' ',(source{::MoleculeNames),' threshold=',fraction_text threshold
        heading =. heading,' count=',integer #order
    end.
    paragraph =. <heading
    for_i. i.#order do.
        index =. i{order
        value =. source similarity index
        line =. (integer i+1),' ',(index{::MoleculeNames),' ',fraction_text value
        paragraph =. paragraph,<line,' common=',integer 0{value
    end.
    paragraph
)
compare_paragraph =: 3 : 0
    'kind identifier arguments pattern threshold count' =. y
    'first second' =. MoleculeNames i.arguments
    a =. first{::Molecules
    b =. second{::Molecules
    value =. first similarity second
    identical =. 'no'
    if. (7{::a)-:7{::b do.
        identical =. 'yes'
    end.
    line =. 'COMPARE ',identifier,' ',(first{::MoleculeNames),' ',(second{::MoleculeNames),' bits='
    line =. line,(integer +/12{::a),',',integer +/12{::b
    line =. line,' common=',(integer 0{value),' union=',integer 1{value
    ,<line,' tanimoto=',(fraction_text value),' identical=',identical
)
cluster_paragraph =: 3 : 0
    'kind identifier arguments pattern threshold count' =. y
    neighbors =. 0$a:
    for_first. i.#Molecules do.
        members =. i.0
        for_second. (i.#Molecules)-.first do.
            if. 0<:(first similarity second)fraction_compare threshold do.
                members =. members,second
            end.
        end.
        neighbors =. neighbors,<members
    end.
    order =. \:#&>neighbors
    assigned =. (#Molecules)$0
    clusters =. 0$a:
    for_center. order do.
        if. center{assigned do.
            continue.
        end.
        others =. center{::neighbors
        members =. center,others#~-.others{assigned
        clusters =. clusters,<members
        assigned =. 1 members}assigned
    end.
    singletons =. +/1=#&>clusters
    line =. 'CLUSTER ',identifier,' threshold=',(fraction_text threshold),' clusters=',integer #clusters
    paragraph =. <line,' singletons=',integer singletons
    number =. 0
    for_members. clusters do.
        members =. >members
        if. 1=#members do.
            continue.
        end.
        number =. number+1
        line =. 'cluster ',(integer number),' centroid=',(({.members){::MoleculeNames),' size=',integer #members
        paragraph =. paragraph,<line,' members=',member_names members
    end.
    paragraph
)
similarity_paragraphs =: 3 : 0
    fingerprints =. <'FINGERPRINTS molecules=',(integer #Molecules),' size=1024 depth=5'
    for_i. i.#Molecules do.
        molecule =. i{::Molecules
        line =. (i{::MoleculeNames),' bits=',integer +/12{::molecule
        fingerprints =. fingerprints,<line,' paths=',integer 13{::molecule
    end.
    paragraphs =. ,<fingerprints
    for_query. Queries do.
        query =. >query
        kind =. 0{::query
        select. kind
        case. 'MATRIX' do. paragraph =. matrix_paragraph query
        case. 'NEAREST';'WITHIN' do. paragraph =. neighbors_paragraph query
        case. 'COMPARE' do. paragraph =. compare_paragraph query
        case. 'CLUSTER' do. paragraph =. cluster_paragraph query
        case. do. continue.
        end.
        paragraphs =. paragraphs,<paragraph
    end.
    paragraphs
)
causes_paragraph =: 3 : 0
    paragraph =. <'CAUSES kinds=',integer #CauseNames
    order =. /:CauseNames
    order =. (\:order{CauseCounts){order
    for_index. order do.
        paragraph =. paragraph,<(index{::CauseNames),'=',integer index{CauseCounts
    end.
    paragraph
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
)
write_paragraphs =: 4 : 0
    lines =. 0$a:
    for_i. i.#y do.
        if. i do.
            lines =. lines,<''
        end.
        lines =. lines,i{::y
    end.
    x write_lines lines
)
run =: 3 : 0
    read_elements ''
    CauseNames =: 0$a:
    CauseCounts =: i.0
    read_molecules ''
    prepare_molecules ''
    read_queries ''
    prepare_similarities ''
    try.
        1!:5 <'output'
    catch.
    end.
    'properties.csv'write_lines properties_lines ''
    'canonical.txt'write_paragraphs canonical_paragraphs ''
    'rings.txt'write_paragraphs ring_paragraphs ''
    'substructure.txt'write_paragraphs substructure_paragraphs ''
    'similarity.txt'write_paragraphs similarity_paragraphs ''
    errors =. (<MoleculeErrors),(<QueryErrors),<causes_paragraph ''
    'errors.txt'write_paragraphs errors
)
run ''
