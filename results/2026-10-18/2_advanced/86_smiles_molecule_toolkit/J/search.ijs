read_pattern_atom =: 4 : 0
    position =. x
    text =. y
    character =. position{text
    if. character e.'*Aa' do.
        mode =. '*Aa'i.character
        atom =. (<mode),<0 2$0
        (<''),(<position+1),<atom return.
    end.
    if. character='[' do.
        rest =. (position+1)}.text
        offset =. rest i.']'
        if. offset=#rest do.
            (<'unclosed bracket'),(<position),<0$a: return.
        end.
        choices =. 0 2$0
        for_item. ','split_char offset{.rest do.
            item =. >item
            organic =. 0 read_organic item
            if. 0=#organic do.
                (<'bad bracket atom'),(<position),<0$a: return.
            end.
            if. (2{organic)~:#item do.
                (<'bad bracket atom'),(<position),<0$a: return.
            end.
            choices =. choices,2{.organic
        end.
        atom =. (<3),<~.choices
        (<''),(<position+2+offset),<atom
    else.
        organic =. position read_organic text
        if. 0=#organic do.
            (<'unexpected character'),(<position),<0$a: return.
        end.
        atom =. (<3),<,:2{.organic
        (<''),(<2{organic),<atom
    end.
)
atom_matches =: 4 : 0
    'mode choices' =. x
    select. mode
    case. 0 do. 1
    case. 1 do. -.1{y
    case. 2 do. 1{y
    case. 3 do. +./(2{.y)-:"1 choices
    end.
)
bond_matches =: 4 : 0
    if. x=0 do.
        y e.1 4
    elseif. x=5 do.
        1
    else.
        x=y
    end.
)
molecule_pattern =: 3 : 0
    atoms =. 0$a:
    for_atom. 0{::y do.
        atoms =. atoms,<( <3),<,:2{.atom
    end.
    bonds =. 1{::y
    for_index. i.#bonds do.
        bonds =. (3{index{bonds)(<index,2)}bonds
    end.
    atoms new_molecule bonds
)
embedding_visit =: 3 : 0
    index =. y
    if. index=#EMapping do.
        ECount =: ECount+1
        EUnique =: EUnique,<EUsed
        if. ECount=1 do.
            EFirst =: EMapping
        end.
        i.0 return.
    end.
    adjacent =. 2{::EMolecule
    bonds =. 1{::EMolecule
    for_atom. index{::ECandidates do.
        if. atom{EUsed do.
            continue.
        end.
        allowed =. 1
        for_requirement. index{::EEarlier do.
            'neighbor symbol' =. requirement
            other =. neighbor{EMapping
            target =. (<atom,other){adjacent
            if. target=_1 do.
                allowed =. 0
                break.
            end.
            if. -.symbol bond_matches 3{target{bonds do.
                allowed =. 0
                break.
            end.
        end.
        if. allowed do.
            EMapping =: atom index}EMapping
            EUsed =: 1 atom}EUsed
            embedding_visit index+1
            EUsed =: 0 atom}EUsed
        end.
    end.
)
embeddings =: 4 : 0
    pattern =. x
    molecule =. y
    pattern_atoms =. 0{::pattern
    atoms =. 0{::molecule
    if. (#pattern_atoms)>#atoms do.
        (<0),(<0),<i.0 return.
    end.
    ECandidates =: 0$a:
    EEarlier =: 0$a:
    for_index. i.#pattern_atoms do.
        candidates =. i.0
        for_atom. i.#atoms do.
            if. (index{::pattern_atoms)atom_matches atom{atoms do.
                if. (molecule degree atom)>:pattern degree index do.
                    candidates =. candidates,atom
                end.
            end.
        end.
        ECandidates =: ECandidates,<candidates
        earlier =. 0 2$0
        for_neighbor. (pattern atom_neighbors index)#~(pattern atom_neighbors index)<index do.
            bond =. (<index,neighbor){2{::pattern
            earlier =. earlier,neighbor,2{bond{1{::pattern
        end.
        EEarlier =: EEarlier,<earlier
    end.
    EMolecule =: molecule
    EMapping =: (#pattern_atoms)$_1
    EUsed =: (#atoms)$0
    ECount =: 0
    EUnique =: 0$a:
    EFirst =: i.0
    embedding_visit 0
    (<ECount),(<#~.EUnique),<EFirst
)
fingerprint_visit =: 3 : 0
    'atom depth value' =. y
    FCount =: FCount+1
    FBits =: 1(1024|value)}FBits
    if. depth=5 do.
        i.0 return.
    end.
    for_neighbor. FMolecule atom_neighbors atom do.
        if. neighbor{FUsed do.
            continue.
        end.
        bond =. (<atom,neighbor){2{::FMolecule
        kind =. 3{bond{1{::FMolecule
        next =. 1000003|kind+31*value
        next =. 1000003|(neighbor{FCodes)+31*next
        FUsed =: 1 neighbor}FUsed
        fingerprint_visit neighbor,(depth+1),next
        FUsed =: 0 neighbor}FUsed
    end.
)
fingerprint =: 3 : 0
    FMolecule =: y
    atoms =. 0{::y
    FCodes =: i.0
    for_index. i.#atoms do.
        atom =. index{atoms
        code =. (16*(0{atom){AtomicNumbers)+(8*1{atom)+y degree index
        FCodes =: FCodes,code
    end.
    FBits =: 1024$0
    FCount =: 0
    FUsed =: (#atoms)$0
    for_atom. i.#atoms do.
        FUsed =: 1 atom}FUsed
        fingerprint_visit atom,0,atom{FCodes
        FUsed =: 0 atom}FUsed
    end.
    (<FBits),<FCount
)
tanimoto =: 4 : '(+/x*.y),+/x+.y'
