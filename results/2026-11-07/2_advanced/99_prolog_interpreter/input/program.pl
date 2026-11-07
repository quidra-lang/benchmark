% program.pl -- sample programs for the interpreter

% ---- family database ----
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).
parent(liz, joe).

male(tom).
male(bob).
male(jim).
male(joe).
female(liz).
female(ann).
female(pat).

father(F, C) :- parent(F, C), male(F).
mother(M, C) :- parent(M, C), female(M).
grandparent(G, C) :- parent(G, P), parent(P, C).
sibling(X, Y) :- parent(P, X), parent(P, Y), X \== Y.
ancestor(A, D) :- parent(A, D).
ancestor(A, D) :- parent(A, X), ancestor(X, D).
cousin(X, Y) :- parent(P, X), parent(Q, Y), siblings(P, Q).
uncle(U, N) :- parent(P, N), sibling(U, P), male(U), parent(G, U).

parent(jim, kim).

% ---- graphs ----
edge(a, b).
edge(a, c).
edge(b, d).
edge(c, d).
edge(c, e).
edge(d, e).
edge(e, a).

path(X, Y, P) :- walk(X, Y, [X], Q), reverse(Q, P).
walk(X, X, V, V).
walk(X, Y, V, P) :- edge(X, Z), \+ memberchk(Z, V), walk(Z, Y, [Z|V], P).

% ---- arithmetic ----
factorial(0, 1) :- !.
factorial(N, F) :- N > 0, M is N - 1, factorial(M, G), F is N * G.

fib(0, 0).
fib(1, 1).
fib(N, F) :- N > 1, A is N - 1, B is N - 2, fib(A, FA), fib(B, FB), F is FA + FB.

gcd(A, 0, A) :- !.
gcd(A, B, G) :- C is A mod B, gcd(B, C, G).

collatz(1, 0) :- !.
collatz(N, S) :-
    ( N mod 2 =:= 0 -> M is N // 2 ; M is 3 * N + 1 ),
    collatz(M, S0),
    S is S0 + 1.

double(X, Y) :- Y is 2 * X.
add(X, A0, A) :- A is A0 + X.
odd(X) :- X mod 2 =:= 1.
price(apple, 1.5).
small(X) :- X < 10.

% ---- sorting ----
quicksort([], []).
quicksort([P|Xs], S) :-
    partition(Xs, P, L, G),
    quicksort(L, SL),
    quicksort(G, SG),
    append(SL, [P|SG], S).

partition([], _, [], []).
partition([X|Xs], P, [X|L], G) :- X =< P, !, partition(Xs, P, L, G).
partition([X|Xs], P, L, [X|G]) :- partition(Xs, P, L, G).

merge_sort([], []) :- !.
merge_sort([X], [X]) :- !.
merge_sort(L, S) :- split(L, A, B), merge_sort(A, SA), merge_sort(B, SB), merge(SA, SB, S).

split([], [], []).
split([X|Xs], [X|A], B) :- split(Xs, B, A).

merge([], L, L) :- !.
merge(L, [], L) :- !.
merge([X|Xs], [Y|Ys], [X|Zs]) :- X =< Y, !, merge(Xs, [Y|Ys], Zs).
merge(Xs, [Y|Ys], [Y|Zs]) :- merge(Xs, Ys, Zs).

% ---- n queens ----
queens(N, Qs) :- numlist(1, N, Ns), place(Ns, [], Qs).

place([], Qs, Qs).
place(Unplaced, Safe, Qs) :-
    select(Q, Unplaced, Rest),
    \+ attacks(Q, Safe, 1),
    place(Rest, [Q|Safe], Qs).

attacks(Q, [Q1|_], D) :- Q =:= Q1 + D.
attacks(Q, [Q1|_], D) :- Q =:= Q1 - D.
attacks(Q, [_|Qs], D) :- D1 is D + 1, attacks(Q, Qs, D1).

% ---- symbolic differentiation ----
d(X, X, 1) :- !.
d(C, _, 0) :- atomic(C), !.
d(U + V, X, DU + DV) :- !, d(U, X, DU), d(V, X, DV).
d(U - V, X, DU - DV) :- !, d(U, X, DU), d(V, X, DV).
d(U * V, X, DU * V + U * DV) :- !, d(U, X, DU), d(V, X, DV).
d(- U, X, - DU) :- d(U, X, DU).

simp(E, S) :-
    E =.. [Op, A, B],
    memberchk(Op, [+, -, *]),
    !,
    simp(A, SA),
    simp(B, SB),
    simp_op(Op, SA, SB, S).
simp(- A, S) :- !, simp(A, SA), ( integer(SA) -> S is - SA ; S = - SA ).
simp(E, E).

simp_op(+, 0, B, B) :- !.
simp_op(+, A, 0, A) :- !.
simp_op(*, 0, _, 0) :- !.
simp_op(*, _, 0, 0) :- !.
simp_op(*, 1, B, B) :- !.
simp_op(*, A, 1, A) :- !.
simp_op(-, A, 0, A) :- !.
simp_op(Op, A, B, S) :- integer(A), integer(B), !, E =.. [Op, A, B], S is E.
simp_op(Op, A, B, E) :- E =.. [Op, A, B].

% ---- term inspection ----
term_size(T, 1) :- var(T), !.
term_size(T, 1) :- atomic(T), !.
term_size(T, S) :- T =.. [_|Args], foldl(add_size, Args, 1, S).
add_size(A, S0, S) :- term_size(A, SA), S is S0 + SA.

subst(Old, New, T, New) :- T == Old, !.
subst(_, _, T, T) :- var(T), !.
subst(Old, New, T, R) :-
    compound(T),
    !,
    T =.. [F|As],
    maplist(subst(Old, New), As, Bs),
    R =.. [F|Bs].
subst(_, _, T, T).

count_leaves(leaf(X), 1).
count_leaves(node(L, R), N) :- count_leaves(L, NL), count_leaves(R, NR), N is NL + NR.
same(_A, _A).

% ---- list utilities ----
rle([], []).
rle([X|Xs], [N-X|R]) :- take_same(X, Xs, 1, N, Rest), rle(Rest, R).

take_same(X, [Y|Ys], N0, N, Rest) :- X == Y, !, N1 is N0 + 1, take_same(X, Ys, N1, N, Rest).
take_same(_, Rest, N, N, Rest).

flatten(X, [X]) :- var(X), !.
flatten([], []) :- !.
flatten([H|T], F) :- !, flatten(H, FH), flatten(T, FT), append(FH, FT, F).
flatten(X, [X]).

last([X], X) :- !.
last([_|T], X) :- last(T, X).

length([], 0).

palindrome(W) :- atom_chars(W, Cs), reverse(Cs, Cs).

% ---- peano numbers ----
nat(0).
nat(s(N)) :- nat(N).

plus(0, Y, Y).
plus(s(X), Y, s(Z)) :- plus(X, Y, Z).

% ---- output ----
hanoi(N) :- move(N, left, right, centre).
move(0, _, _, _) :- !.
move(N, A, B, C) :-
    M is N - 1,
    move(M, A, C, B),
    write(A), write(' -> '), write(B), nl,
    move(M, C, B, A).

fizzbuzz(N) :- between(1, N, I), fb(I), fail.
fizzbuzz(_).

fb(I) :- I mod 15 =:= 0, !, write(fizzbuzz), nl.
fb(I) :- I mod 3 =:= 0, !, write(fizz), nl.
fb(I) :- I mod 5 =:= 0, !, write(buzz), nl.
fb(I) :- write(I), nl.

table(N) :-
    forall(between(1, N, I),
           ( forall(between(1, N, J), ( P is I * J, write(P), ( J < N -> write(' ') ; nl ) )) )).

% ---- control and exceptions ----
classify(X, C) :-
    ( X < 0 -> C = negative
    ; X =:= 0 -> C = zero
    ; X < 10 -> C = small
    ; C = large
    ).

not_member(X, L) :- \+ member(X, L).

safe_div(X, Y, Z) :-
    catch(Z is X // Y, error(E, _), ( write(caught(E)), nl, Z = undefined )).

check_age(A) :-
    ( integer(A) -> true ; throw(bad_age(A)) ),
    A >= 0.

age_ok(A, R) :- catch(( check_age(A), R = ok ), bad_age(X), R = rejected(X)).

first_even(L, X) :- member(X, L), X mod 2 =:= 0, !.

broken(X) :- X > , true.

risky(X) :- X = a = b.

loop_forever :- loop_forever.

% ---- more deliberate errors ----
greeting('hello).
swallowed(1).
bad_goal(X) :- write(X), 1.
3.
unfinished(X) :- write(X)
