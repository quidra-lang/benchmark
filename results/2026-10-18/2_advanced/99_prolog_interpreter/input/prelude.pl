% prelude.pl -- list and control library loaded before the user program

append([], L, L).
append([H|T], L, [H|R]) :-
    append(T, L, R).

member(X, [X|_]).
member(X, [_|T]) :-
    member(X, T).

memberchk(X, L) :-
    member(X, L),
    !.

reverse(L, R) :-
    reverse_(L, [], R).

reverse_([], Acc, Acc).
reverse_([H|T], Acc, R) :-
    reverse_(T, [H|Acc], R).

nth1(1, [X|_], X) :-
    !.
nth1(N, [_|T], X) :-
    N > 1,
    M is N - 1,
    nth1(M, T, X).

last([X], X).
last([_|T], X) :-
    last(T, X).

select(X, [X|T], T).
select(X, [H|T], [H|R]) :-
    select(X, T, R).

permutation([], []).
permutation(L, [H|T]) :-
    select(H, L, R),
    permutation(R, T).

sum_list(L, S) :-
    sum_list_(L, 0, S).

sum_list_([], S, S).
sum_list_([X|Xs], A, S) :-
    B is A + X,
    sum_list_(Xs, B, S).

max_list([X|Xs], M) :-
    max_list_(Xs, X, M).

max_list_([], M, M).
max_list_([X|Xs], A, M) :-
    ( X > A -> B = X ; B = A ),
    max_list_(Xs, B, M).

numlist(L, H, []) :-
    L > H,
    !.
numlist(L, H, [L|T]) :-
    M is L + 1,
    numlist(M, H, T).

maplist(_, []).
maplist(G, [X|Xs]) :-
    call(G, X),
    maplist(G, Xs).

maplist(_, [], []).
maplist(G, [X|Xs], [Y|Ys]) :-
    call(G, X, Y),
    maplist(G, Xs, Ys).

foldl(_, [], A, A).
foldl(G, [X|Xs], A0, A) :-
    call(G, X, A0, A1),
    foldl(G, Xs, A1, A).

include(_, [], []).
include(P, [X|Xs], R) :-
    ( call(P, X) -> R = [X|R1] ; R = R1 ),
    include(P, Xs, R1).

exclude(_, [], []).
exclude(P, [X|Xs], R) :-
    ( call(P, X) -> R = R1 ; R = [X|R1] ),
    exclude(P, Xs, R1).

delete([], _, []).
delete([X|Xs], Y, R) :-
    ( X == Y -> R = R1 ; R = [X|R1] ),
    delete(Xs, Y, R1).

once(G) :-
    call(G),
    !.

ignore(G) :-
    ( call(G) -> true ; true ).

forall(C, A) :-
    \+ ( call(C), \+ call(A) ).
