dense_ranks =: 3 : 0
    distinct =. ~.y
    ordered =. (/:distinct){distinct
    1+ordered i.y
)
refine_ranks =: 4 : 0
    ranks =. y
    bonds =. 1{::x
    adjacent =. 2{::x
    while. 1 do.
        values =. 0$a:
        for_atom. i.#ranks do.
            pairs =. 0 2$0
            for_neighbor. x atom_neighbors atom do.
                index =. (<atom,neighbor){adjacent
                pairs =. pairs,(neighbor{ranks),3{index{bonds
            end.
            pairs =. (/:pairs){pairs
            values =. values,<(atom{ranks),,pairs
        end.
        next =. dense_ranks values
        if. (#~.next)=#~.ranks do.
            next return.
        end.
        ranks =. next
    end.
)
canonical_ranks =: 3 : 0
    atoms =. 0{::y
    invariants =. 0 6$0
    for_index. i.#atoms do.
        atom =. index{atoms
        row =. (y degree index),((0{atom){AtomicNumbers),(2{atom),(3{atom),(4{atom),1{atom
        invariants =. invariants,row
    end.
    ranks =. y refine_ranks dense_ranks <"1 invariants
    classes =. #~.ranks
    while. (#~.ranks)~:#ranks do.
        for_rank. /:~~.ranks do.
            positions =. I.ranks=rank
            if. 1<#positions do.
                first =. {.positions
                break.
            end.
        end.
        values =. 2*ranks
        values =. ((first{values)-1)first}values
        ranks =. y refine_ranks dense_ranks <"0 values
    end.
    (<ranks),<classes
)
atom_notation =: 4 : 0
    atom =. y{0{::x
    'element aromatic mass charge hydrogens bracket column' =. atom
    symbol =. element{::ElementSymbols
    ordinary =. (<symbol)e.OrganicElements
    ordinary =. ordinary*.((-.aromatic)+.(<symbol)e.AromaticElements)*.(mass=0)*.charge=0
    if. aromatic do.
        ordinary =. ordinary*.((x needs_pi y,hydrogens)=x needs_pi y,0)
        symbol =. tolower symbol
    end.
    expected =. atom organic_hydrogens x bond_total y
    if. ordinary*.(expected~:_1)*.expected=hydrogens do.
        symbol return.
    end.
    text =. '['
    if. mass do.
        text =. text,integer mass
    end.
    text =. text,symbol
    if. hydrogens do.
        text =. text,'H'
        if. hydrogens~:1 do.
            text =. text,integer hydrogens
        end.
    end.
    if. charge do.
        sign =. '+'
        if. charge<0 do.
            sign =. '-'
        end.
        text =. text,sign
        if. 1~:|charge do.
            text =. text,integer |charge
        end.
    end.
    text,']'
)
bond_symbol =: 4 : 0
    bond =. y{1{::x
    'first second symbol kind multiplicity ring' =. bond
    atoms =. 0{::x
    in_ring =. ring*.(1{first{atoms)*.1{second{atoms
    select. kind
    case. 1 do.
        if. in_ring do. '-' else. '' end.
    case. 2 do. '='
    case. 3 do. '#'
    case. 4 do.
        if. in_ring do. '' else. ':' end.
    end.
)
canonical_visit =: 3 : 0
    'atom incoming' =. y
    CCounter =: CCounter+1
    CVisits =: CCounter atom}CVisits
    neighbors =. CMolecule atom_neighbors atom
    order =. (/:neighbors{CRanks){neighbors
    adjacent =. 2{::CMolecule
    for_neighbor. order do.
        bond =. (<atom,neighbor){adjacent
        if. (bond=incoming)+.bond{CClosures do.
            continue.
        end.
        if. 0=neighbor{CVisits do.
            children =. (atom{::CChildren),neighbor,bond
            CChildren =: (<children)atom}CChildren
            canonical_visit neighbor,bond
        else.
            CClosures =: 1 bond}CClosures
        end.
    end.
)
canonical_write =: 3 : 0
    atom =. y
    text =. CMolecule atom_notation atom
    neighbors =. CMolecule atom_neighbors atom
    order =. (/:neighbors{CVisits){neighbors
    adjacent =. 2{::CMolecule
    for_neighbor. order do.
        bond =. (<atom,neighbor){adjacent
        if. -.bond{CClosures do.
            continue.
        end.
        number =. bond{CAssignments
        symbol =. ''
        if. number~:_1 do.
            CAssignments =: _1 bond}CAssignments
            COccupied =: 0 number}COccupied
        else.
            number =. 1
            while. number{COccupied do.
                number =. number+1
            end.
            CAssignments =: number bond}CAssignments
            COccupied =: 1 number}COccupied
            symbol =. CMolecule bond_symbol bond
        end.
        notation =. integer number
        if. number>:10 do.
            notation =. '%',notation
        end.
        text =. text,symbol,notation
    end.
    children =. atom{::CChildren
    for_i. i.#children do.
        'child bond' =. i{children
        continuation =. (CMolecule bond_symbol bond),canonical_write child
        if. i<(#children)-1 do.
            text =. text,'(',continuation,')'
        else.
            text =. text,continuation
        end.
    end.
    text
)
canonicalize =: 3 : 0
    'ranks classes' =. canonical_ranks y
    CMolecule =: y
    CRanks =: ranks
    CVisits =: (#ranks)$0
    CCounter =: 0
    CChildren =: (#ranks)$<0 2$0
    CClosures =: (#1{::y)$0
    root =. ranks i.1
    canonical_visit root,_1
    CAssignments =: (#1{::y)$_1
    COccupied =: (1+#1{::y)$0
    (<canonical_write root),<classes
)
