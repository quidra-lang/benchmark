OrganicElements =: ,&.>;:'B C N O P S F Cl Br I'
AromaticElements =: ,&.>;:'B C N O P S'
read_elements =: 3 : 0
    ElementSymbols =: 0$a:
    AtomicNumbers =: i.0
    AtomicWeights =: i.0
    Valences =: 0$a:
    for_record. data_lines 'elements.txt' do.
        fields =. split_words 1{::>record
        ElementSymbols =: ElementSymbols,<0{::fields
        AtomicNumbers =: AtomicNumbers,parse_integer 1{::fields
        AtomicWeights =: AtomicWeights,parse_integer 2{::fields
        Valences =: Valences,<parse_integer&>','split_char 3{::fields
    end.
    HydrogenElement =: ElementSymbols i.<,'H'
    CarbonElement =: ElementSymbols i.<,'C'
    NitrogenElement =: ElementSymbols i.<,'N'
    OxygenElement =: ElementSymbols i.<,'O'
)
new_molecule =: 4 : 0
    atoms =. x
    bonds =. (/:2{."1 y){y
    count =. #atoms
    adjacent =. (count,count)$_1
    for_index. i.#bonds do.
        'first second' =. 2{.index{bonds
        adjacent =. index(<first,second)}adjacent
        adjacent =. index(<second,first)}adjacent
    end.
    (<atoms),(<bonds),(<adjacent),(<0$a:),(<count$0),<''
)
atom_neighbors =: 4 : 'I._1~:y{2{::x'
degree =: 4 : '#x atom_neighbors y'
base_total =: 4 : 0
    adjacent =. y{2{::x
    indices =. adjacent#~adjacent~:_1
    kinds =. 3{"1 indices{1{::x
    +/kinds{0 1 2 3 1
)
bond_total =: 4 : 0
    adjacent =. y{2{::x
    indices =. adjacent#~adjacent~:_1
    +/4{"1 indices{1{::x
)
needs_pi =: 4 : 0
    'number hydrogens' =. y
    atom =. number{0{::x
    if. -.1{atom do.
        0 return.
    end.
    valences =. (0{atom){::Valences
    (({.valences)+3{atom)>:1+hydrogens+x base_total number
)
organic_hydrogens =: 4 : 0
    valences =. (0{x){::Valences
    suitable =. valences#~valences>:y
    if. #suitable do.
        ({.suitable)-y
    else.
        _1
    end.
)
analysis_error =: 4 : '(<x),<y'
