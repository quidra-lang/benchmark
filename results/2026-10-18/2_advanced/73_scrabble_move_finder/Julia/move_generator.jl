function anchors(board)
    isempty(board_tiles(board)) && return Set([CENTER])
    Set((r,c) for r in 1:BOARD_SIZE for c in 1:BOARD_SIZE if board[r,c]=='.' && any(
        p->board[p...]!='.',
        neighbors(r,c)
    ))
end
function cross_checks(board,trie)
    result = Dict{Tuple{Int,Int},Set{Char}}()
    for r in 1:BOARD_SIZE,c in 1:BOARD_SIZE
        board[r,c]!='.' && continue
        first,last = r,r
        while first>1 && board[first-1,c]!='.'
            first -= 1
        end
        while last<BOARD_SIZE && board[last+1,c]!='.'
            last += 1
        end
        first==last && continue
        prefix,suffix = uppercase(join(board[first:r-1,c])),uppercase(join(board[r+1:last,c]))
        result[(r,c)] = Set(l for l in LETTERS if has_word(trie,prefix*l*suffix))
    end
    result
end
function across_moves(board,rack,trie,anchor_squares,checks)
    result,counts = NamedTuple[],rack_counts(rack)
    for (row,anchor) in sort!(collect(anchor_squares))
        function extend(node,column,word,start)
            empty = column>BOARD_SIZE || board[row,column]=='.'
            empty && column>anchor && trie.terminal[node] && push!(
                result,
                (row=row,column=start,direction=0,word=word)
            )
            column>BOARD_SIZE && return
            if !empty
                letter = board[row,column]
                child = get(trie.children[node],uppercase(letter),0)
                child!=0 && extend(child,column+1,word*letter,start)
                return
            end
            allowed = get(checks,(row,column),nothing)
            for letter in sort!(collect(keys(trie.children[node])))
                !isnothing(allowed) && !(letter in allowed) && continue
                child = trie.children[node][letter]
                for (tile,written) in ((tile_index(letter),letter),(27,lowercase(letter)))
                    if counts[tile]>0
                        counts[tile] -= 1
                        extend(child,column+1,word*written,start)
                        counts[tile] += 1
                    end
                end
            end
        end
        function left_part(node,prefix,remaining)
            extend(node,anchor,prefix,anchor-length(prefix))
            remaining==0 && return
            for letter in sort!(collect(keys(trie.children[node])))
                for (tile,written) in ((tile_index(letter),letter),(27,lowercase(letter)))
                    if counts[tile]>0
                        counts[tile] -= 1
                        left_part(trie.children[node][letter],prefix*written,remaining-1)
                        counts[tile] += 1
                    end
                end
            end
        end
        if anchor>1 && board[row,anchor-1]!='.'
            first = anchor-1
            while first>1 && board[row,first-1]!='.'
                first -= 1
            end
            prefix = join(board[row,first:anchor-1])
            node = prefix_node(trie,uppercase(prefix))
            node!=0 && extend(node,anchor,prefix,first)
        else
            first = anchor-1
            while first>=1 && board[row,first]=='.' && !((row,first) in anchor_squares)
                first -= 1
            end
            left_part(1,"",anchor-first-1)
        end
    end
    result
end
placement_key(new_tiles) = Tuple(sort(collect(new_tiles)))
function generate_moves(board,rack,trie)
    anchor_squares = anchors(board)
    across = across_moves(board,rack,trie,anchor_squares,cross_checks(board,trie))
    transposed = transpose_board(board)
    down = across_moves(
        transposed,
        rack,
        trie,
        Set((c,r) for (r,c) in anchor_squares),
        cross_checks(transposed,trie)
    )
    candidates = [across;[(row=m.column,column=m.row,direction=1,word=m.word) for m in down]]
    result = Dict{Tuple,NamedTuple}()
    for move in candidates
        new_tiles = placement(board,move)
        if length(new_tiles)==1 && move.direction==1
            r,c,_ = new_tiles[1]
            length(run_at(apply_move(board,new_tiles),r,c,0).word)>=2 && continue
        end
        result[placement_key(new_tiles)] = move
    end
    collect(values(result))
end
