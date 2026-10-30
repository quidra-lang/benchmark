char_at =: 4 : 0
    if. (x>:0)*.x<#y do.
        x{y
    else.
        a.{~0
    end.
)
pair_at =: 4 : '2{.x}.y'
read_organic =: 4 : 0
    position =. x
    pair =. position pair_at y
    if. (<pair)e.'Cl';'Br' do.
        (ElementSymbols i.<pair),0,position+2 return.
    end.
    character =. position char_at y
    if. character e.'BCNOPSFI' do.
        (ElementSymbols i.<,character),0,position+1
    elseif. character e.'bcnops' do.
        (ElementSymbols i.<,toupper character),1,position+1
    else.
        i.0
    end.
)
read_bracket =: 4 : 0
    column =. x
    content =. y
    position =. 0
    while. (position char_at content)e.'0123456789' do.
        position =. position+1
    end.
    if. (position>:4)+.((position>0)*.'0'=0 char_at content) do.
        (<'bad bracket atom'),<i.0 return.
    end.
    mass =. 0
    if. position do.
        mass =. parse_integer position{.content
    end.
    character =. position char_at content
    if. position=#content do.
        (<'bad bracket atom'),<i.0 return.
    end.
    if. character e.'bcnops' do.
        element =. ElementSymbols i.<,toupper character
        aromatic =. 1
        position =. position+1
    elseif. character e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do.
        pair =. position pair_at content
        if. ((1{pair)e.'abcdefghijklmnopqrstuvwxyz')*.(<pair)e.ElementSymbols do.
            element =. ElementSymbols i.<pair
            position =. position+2
        elseif. (<,character)e.ElementSymbols do.
            element =. ElementSymbols i.<,character
            position =. position+1
        else.
            (<'unknown element'),<i.0 return.
        end.
        aromatic =. 0
    else.
        (<'bad bracket atom'),<i.0 return.
    end.
    if. '@@'-:position pair_at content do.
        position =. position+2
    elseif. '@'=position char_at content do.
        position =. position+1
    end.
    hydrogens =. 0
    if. 'H'=position char_at content do.
        hydrogens =. 1
        position =. position+1
        character =. position char_at content
        if. character e.'0123456789' do.
            hydrogens =. '0123456789'i.character
            position =. position+1
        end.
    end.
    charge =. 0
    character =. position char_at content
    if. character e.'+-' do.
        charge =. 1-2*character='-'
        position =. position+1
        character =. position char_at content
        if. character e.'123456789' do.
            charge =. charge*'0123456789'i.character
            position =. position+1
        end.
    end.
    if. position~:#content do.
        (<'bad bracket atom'),<i.0 return.
    end.
    atom =. element,aromatic,mass,charge,hydrogens,1,column
    (<''),<atom
)
read_atom =: 4 : 0
    position =. x
    text =. y
    if. '['=position{text do.
        rest =. (position+1)}.text
        offset =. rest i.']'
        if. offset=#rest do.
            (<'unclosed bracket'),(<position),<i.0 return.
        end.
        'error atom' =. (position+1)read_bracket offset{.rest
        (<error),(<position+2+offset),<atom
    else.
        organic =. position read_organic text
        if. 0=#organic do.
            (<'unexpected character'),(<position),<i.0 return.
        end.
        'element aromatic end' =. organic
        atom =. element,aromatic,0,0,0,0,position+1
        (<''),(<end),<atom
    end.
)
parse_smiles =: 4 : 0
    pattern =. x
    text =. y
    atoms =. 0 7$0
    if. pattern do.
        atoms =. 0$a:
    end.
    bonds =. 0 6$0
    current =. _1
    pending =. 0
    pending_column =. 0
    branches =. 0 2$0
    open_rings =. 100 3$_1
    position =. 0
    while. position<#text do.
        character =. position{text
        column =. position+1
        symbols =. '-=#:~'
        values =. 1 2 3 4 5
        if. -.pattern do.
            symbols =. '-/\=#:'
            values =. 1 1 1 2 3 4
        end.
        if. character e.symbols do.
            if. (current=_1)+.pending~:0 do.
                (<'misplaced bond'),(<column),<0$a: return.
            end.
            pending =. (symbols i.character){values
            pending_column =. column
            position =. position+1
        elseif. character='(' do.
            if. (current=_1)+.(pending~:0)+.'('=(position-1)char_at text do.
                (<'misplaced branch'),(<column),<0$a: return.
            end.
            branches =. branches,current,column
            position =. position+1
        elseif. character=')' do.
            if. 0=#branches do.
                (<'unmatched parenthesis'),(<column),<0$a: return.
            elseif. pending do.
                (<'dangling bond'),(<pending_column),<0$a: return.
            elseif. '('=(position-1)char_at text do.
                (<'empty branch'),(<column),<0$a: return.
            end.
            current =. 0{_1{branches
            branches =. }:branches
            position =. position+1
        elseif. character e.'0123456789%' do.
            if. current=_1 do.
                (<'misplaced ring closure'),(<column),<0$a: return.
            end.
            if. character='%' do.
                digits =. (position+1)pair_at text
                if. -.*/digits e.'0123456789' do.
                    (<'bad ring number'),(<column),<0$a: return.
                end.
                ring =. parse_integer digits
                position =. position+3
            else.
                ring =. '0123456789'i.character
                position =. position+1
            end.
            symbol =. pending
            pending =. 0
            'first initial opening' =. ring{open_rings
            if. first=_1 do.
                open_rings =. (current,symbol,column)ring}open_rings
                continue.
            end.
            if. first=current do.
                (<'self bond'),(<column),<0$a: return.
            elseif. (initial~:0)*.(symbol~:0)*.initial~:symbol do.
                (<'ring bond mismatch'),(<column),<0$a: return.
            end.
            ends =. /:~first,current
            if. +./ends-:"1 (2{."1 bonds) do.
                (<'duplicate bond'),(<column),<0$a: return.
            end.
            if. symbol=0 do.
                symbol =. initial
            end.
            bonds =. bonds,ends,symbol,0,0,0
            open_rings =. _1 ring}open_rings
        else.
            if. pattern do.
                'error end atom' =. position read_pattern_atom text
            else.
                'error end atom' =. position read_atom text
            end.
            if. #error do.
                (<error),(<column),<0$a: return.
            end.
            new =. #atoms
            if. pattern do.
                atoms =. atoms,<atom
            else.
                atoms =. atoms,atom
            end.
            if. current~:_1 do.
                bonds =. bonds,current,new,pending,0,0,0
            end.
            current =. new
            pending =. 0
            position =. end
        end.
    end.
    if. pending do.
        (<'dangling bond'),(<pending_column),<0$a: return.
    elseif. #branches do.
        (<'unmatched parenthesis'),(<1{0{branches),<0$a: return.
    end.
    remaining =. I._1~:0{"1 open_rings
    if. #remaining do.
        column =. <./2{"1 remaining{open_rings
        (<'unclosed ring'),(<column),<0$a: return.
    end.
    (<''),(<0),<atoms new_molecule bonds
)
