breadth_first =: 4 : 0
    molecule =. x
    count =. #0{::molecule
    parents =. count$_2
    parents =. _1 y}parents
    queue =. ,y
    front =. 0
    while. front<#queue do.
        atom =. front{queue
        front =. front+1
        for_neighbor. molecule atom_neighbors atom do.
            if. _2=neighbor{parents do.
                parents =. atom neighbor}parents
                queue =. queue,neighbor
            end.
        end.
    end.
    paths =. 0$a:
    for_atom. i.count do.
        path =. i.0
        current =. atom
        while. current~:_1 do.
            path =. path,current
            current =. current{parents
        end.
        paths =. paths,<path
    end.
    (<parents),<paths
)
ring_bond_set =: 4 : 0
    adjacent =. 2{::x
    bits =. (#1{::x)$0
    for_i. i.#y do.
        first =. i{y
        second =. ((#y)|i+1){y
        index =. (<first,second){adjacent
        bits =. 1 index}bits
    end.
    bits
)
ring_sequence =: 3 : 0
    first =. y i.<./y
    forward =. first|.y
    backward =. (1{.forward),|.}.forward
    if. (1{backward)<1{forward do.
        backward
    else.
        forward
    end.
)
find_rings =: 3 : 0
    molecule =. y
    atoms =. 0{::molecule
    bonds =. 1{::molecule
    candidates =. 0$a:
    candidate_bits =. 0$a:
    for_root. i.#atoms do.
        'parents paths' =. molecule breadth_first root
        for_bond. bonds do.
            'first second' =. 2{.bond
            if. ((first{parents)=second)+.(second{parents)=first do.
                continue.
            end.
            a =. first{::paths
            b =. second{::paths
            if. 1~:+/a e.b do.
                continue.
            end.
            sequence =. (|.a),}:b
            bits =. molecule ring_bond_set sequence
            if. (<bits)e.candidate_bits do.
                continue.
            end.
            candidates =. candidates,<sequence
            candidate_bits =. candidate_bits,<bits
        end.
    end.
    basis =. (#bonds)$<i.0
    rings =. 0$a:
    for_index. /:#&>candidates do.
        bits =. index{::candidate_bits
        while. +./bits do.
            pivot =. _1{I.bits
            vector =. pivot{::basis
            if. 0=#vector do.
                basis =. (<bits)pivot}basis
                rings =. rings,<ring_sequence index{::candidates
                break.
            end.
            bits =. bits~:vector
        end.
    end.
    keys =. 0$a:
    for_ring. rings do.
        ring =. >ring
        keys =. keys,<(#ring),ring
    end.
    rings =. (/:keys){rings
    ring_atoms =. (#atoms)$0
    ring_bonds =. (#bonds)$0
    for_ring. rings do.
        ring =. >ring
        ring_atoms =. 1 ring}ring_atoms
        ring_bonds =. ring_bonds+.molecule ring_bond_set ring
    end.
    bonds =. (5{."1 bonds),.ring_bonds
    molecule =. (<bonds)1}molecule
    molecule =. (<rings)3}molecule
    (<ring_atoms)4}molecule
)
aromatic_systems =: 4 : 0
    remaining =. (#0{::x)$0
    remaining =. 1 y}remaining
    bonds =. 1{::x
    adjacent =. 2{::x
    systems =. 0$a:
    while. +./remaining do.
        start =. {.I.remaining
        remaining =. 0 start}remaining
        queue =. ,start
        front =. 0
        while. front<#queue do.
            atom =. front{queue
            front =. front+1
            for_neighbor. x atom_neighbors atom do.
                if. neighbor{remaining do.
                    index =. (<atom,neighbor){adjacent
                    if. 4=3{index{bonds do.
                        remaining =. 0 neighbor}remaining
                        queue =. queue,neighbor
                    end.
                end.
            end.
        end.
        systems =. systems,</:~queue
    end.
    systems
)
match_visit =: 3 : 0
    if. -.+./MatchUnpaired do.
        1 return.
    end.
    first =. {.I.MatchUnpaired
    MatchUnpaired =: 0 first}MatchUnpaired
    for_second. MatchMolecule atom_neighbors first do.
        if. -.second{MatchUnpaired do.
            continue.
        end.
        index =. (<first,second){2{::MatchMolecule
        if. 4~:3{index{1{::MatchMolecule do.
            continue.
        end.
        MatchUnpaired =: 0 second}MatchUnpaired
        MatchPairs =: MatchPairs,index
        if. match_visit '' do.
            1 return.
        end.
        MatchPairs =: }:MatchPairs
        MatchUnpaired =: 1 second}MatchUnpaired
    end.
    MatchUnpaired =: 1 first}MatchUnpaired
    0
)
kekulize =: 4 : 0
    molecule =. x
    selected =. i.0
    for_system. molecule aromatic_systems y do.
        system =. >system
        MatchMolecule =: molecule
        MatchUnpaired =: (#0{::molecule)$0
        MatchUnpaired =: 1 system}MatchUnpaired
        MatchPairs =: i.0
        if. -.match_visit '' do.
            column =. 6{({.system){0{::molecule
            (<'kekulization failed'),(<column),<0$a: return.
        end.
        selected =. selected,MatchPairs
    end.
    bonds =. 1{::molecule
    for_index. i.#bonds do.
        kind =. 3{index{bonds
        multiplicity =. kind
        if. kind=4 do.
            multiplicity =. 1+index e.selected
        end.
        bonds =. multiplicity(<index,4)}bonds
    end.
    (<''),(<0),<(<bonds)1}molecule
)
