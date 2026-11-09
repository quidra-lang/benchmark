(* program.ml: a tour of the mini-ML checker and evaluator *)

(* basic values *)
let answer = 6 * 7;;
let greeting = "Hello, " ^ "world";;
let flags = (true && not false, 3 <= 2 || "abc" < "abd");;
let square x = x * x;;
let squares = map square (range 1 10);;
sum squares;;
let neg = - (2 + 3) * 4;;
(-17 / 5, (-17 mod 5, 17 mod (-5)));;
"tab\there" ^ "\"q\"\\";;
let   spaced=( 1+2 )*((3))  ;;
let lo = 1 and hi = 5;;
let x = lo + hi and y = hi - lo in x * y;;
[[1; 2]; []; [3]];;
([square; abs], ("", [true]));;
let nest = ((1, "two"), [fun n -> n + 1]);;
let total' = sum [1; 2; 3];;

(* polymorphism *)
let pairs = zip (range 1 3) ["one"; "two"; "three"];;
unzip pairs;;
let poly = let pair_of x = (x, x) in (pair_of 1, pair_of "a");;
let s f g x = f x (g x);;
s const const;;
compose (fun x -> x + 1) (fun x -> x * 2);;
let curry3 f x y z = f (x, (y, z));;
let pairs_with x l = let mk y = (x, y) in map mk l;;
let tag2 x y = let mk z = (x, (y, z)) in mk;;
let first_of x = let k = fun y -> (x, y) in fst (k [1]) + 0;;
let zero f x = x;;
let succ n f x = f (n f x);;
let to_int n = n (fun k -> k + 1) 0;;
to_int (succ (succ (succ zero)));;
let apply_all fs x = map (fun f -> f x) fs;;
apply_all [square; abs; fun n -> n - 100] (-7);;
let nested = let a = 1 in let b = (a, "b") in let c = fun z -> (b, z) in c [a];;
flat_map (fun x -> [x; x * 10]) [1; 2; 3];;
(for_all (fun x -> x > 0) [1; 2], mem 3 [1; 2]);;
take 3 (drop 2 (range 1 10));;
uncurry (fun a b -> a - b) (10, 3);;
curry fst 1 "x";;
iterate 5 (fun s -> s ^ "ab") "";;
flip (fun a b -> a ^ b) "x" "y";;
(max "apple" "banana", (min [3; 1] [2; 9], concat [[1]; [2; 3]; []]));;

(* recursion *)
let rec even n = if n = 0 then true else odd (n - 1)
and odd n = if n = 0 then false else even (n - 1);;
(even 10, odd 7);;
let rec fact n = if n <= 1 then 1 else n * fact (n - 1);;
map fact (range 0 12);;
let rec fib n = match n with 0 -> 0 | 1 -> 1 | _ -> fib (n - 1) + fib (n - 2);;
map fib (range 0 15);;
let fast_fib n =
  let rec go k a b = if k = 0 then a else go (k - 1) b (a + b) in
  go n 0 1;;
fast_fib 40;;
let rec gcd a b = if b = 0 then a else gcd b (a mod b);;
gcd 1071 462;;
let rec power base e =
  if e = 0 then 1
  else let half = power base (e / 2) in
       if e mod 2 = 0 then half * half else base * half * half;;
power 3 13;;
let collatz n =
  let rec steps n acc =
    if n = 1 then acc
    else if n mod 2 = 0 then steps (n / 2) (acc + 1)
    else steps (3 * n + 1) (acc + 1) in
  steps n 0;;
map collatz [6; 7; 27];;
let sign n = match n with 0 -> "zero" | -1 -> "minus one" | _ -> "other";;
map sign [0; -1; 5];;
let to_num b = match b with true -> 1 | false -> 0;;

(* lists and sorting *)
let rec split l =
  match l with
  | x :: y :: rest -> (match split rest with (a, b) -> (x :: a, y :: b))
  | _ -> (l, []);;
let rec merge le a b =
  match (a, b) with
  | ([], _) -> b
  | (_, []) -> a
  | (x :: xs, y :: ys) -> if le x y then x :: merge le xs b else y :: merge le a ys;;
let rec merge_sort le l =
  match l with
  | [] -> []
  | [x] -> [x]
  | _ -> (match split l with (a, b) -> merge le (merge_sort le a) (merge_sort le b));;
merge_sort (fun a b -> a <= b) [38; 27; 43; 3; 9; 82; 10];;
merge_sort (fun a b -> a >= b) ["pear"; "fig"; "apple"; "kiwi"];;
let rec quicksort l =
  match l with
  | [] -> []
  | pivot :: rest ->
      match partition (fun x -> x < pivot) rest with
      | (small, large) -> append (quicksort small) (pivot :: quicksort large);;
quicksort [5; 1; 4; 1; 5; 9; 2; 6];;
let sieve n =
  let rec go l = match l with [] -> [] | p :: rest -> p :: go (filter (fun x -> x mod p <> 0) rest) in
  go (range 2 n);;
sieve 50;;
let rec rle l =
  match l with
  | [] -> []
  | x :: rest ->
      (match rle rest with
       | (y, n) :: tail -> if x = y then (y, n + 1) :: tail else (x, 1) :: (y, n) :: tail
       | [] -> [(x, 1)]);;
rle ["a"; "a"; "b"; "c"; "c"; "c"];;
let rec transpose m =
  match m with
  | [] :: _ -> []
  | [] -> []
  | rows -> map hd rows :: transpose (map tl rows);;
transpose [[1; 2; 3]; [4; 5; 6]];;
let dot a b = sum (map (fun p -> fst p * snd p) (zip a b));;
let mat_mul a b = let cols = transpose b in map (fun row -> map (dot row) cols) a;;
mat_mul [[1; 2]; [3; 4]] [[5; 6]; [7; 8]];;
let rec powerset l =
  match l with
  | [] -> [[]]
  | x :: rest -> let ps = powerset rest in append ps (map (fun s -> x :: s) ps);;
powerset [1; 2; 3];;
let phone = [("alice", 1234); ("bob", 5678); ("carol", 9012)];;
assoc "bob" phone;;
let to_binary n =
  let rec bits n = if n = 0 then [] else (n mod 2) :: bits (n / 2) in
  join "" (map string_of_int (rev (bits n)));;
map to_binary [5; 10; 255];;
join " " (map (fun w -> w ^ "!") ["the"; "quick"; "brown"; "fox"]);;
((1, fun x -> x) < (2, fun x -> x), [square] = []);;

(* signatures *)
val swap_int : int * string -> string * int;;
let swap_int p = swap p;;
val identity : 'a -> 'a;;
let identity x = x;;
val first_elem : 'elem list -> 'elem;;
let first_elem l = hd l;;
val bad_sig : 'a -> 'a;;
let bad_sig x = x + 1;;
val pair_sig : 'a -> 'b -> 'a * 'b;;
let pair_sig x y = (y, x);;
val nowhere : int;;
val chosen : int;;
val chosen : bool list;;
let chosen = [true];;
val same_type : 'x -> 'x -> bool;;
let same_type a b = a = b;;

(* type errors *)
1 + true;;
let bad_if x = if x then 1 else "one";;
if 1 then 2 else 3;;
let self_apply f = f f;;
let rec rec_self x = rec_self;;
lenght [1; 2];;
undefined_thing 3;;
fsd (1, 2);;
let call_int = 3 4;;
length [1] 2;;
let twin p = match p with (x, x) -> x;;
let wrong_cons = 1 :: ["a"];;
[1; 2; "three"];;
map (fun x -> x + 1) [true];;
let compose_bad = compose (fun x -> x + 1) (fun s -> s ^ "!");;
let apply_int f = f 1 + 0;;
apply_int (fun s -> s ^ "a");;
let rec loop = 5;;
let a = 1 and a = 2;;
let mono = fun f -> (f 1, f true);;
(match [1; 2] with [] -> 0 | x :: _ -> x ^ "a");;
match 1 with [] -> 0 | _ -> 1;;

(* runtime errors *)
10 / (5 - 5);;
map (fun x -> 100 mod x) [3; 0; 7];;
hd [];;
2147483647 + 1;;
- (-2147483647 - 1);;
let unsafe = last [];;
(fun x -> x) = (fun y -> y);;
nth [1; 2; 3] 5;;
assoc "dave" phone;;
let boom = if answer > 40 then failwith "boom" else 0;;

(* warnings *)
let describe l = match l with [] -> "empty" | [x] -> "one" | x :: y :: _ -> "many";;
let classify n = match n with 0 -> "zero" | 1 -> "one";;
classify 2;;
let both b c = match (b, c) with (true, _) -> 1 | (_, false) -> 2;;
let redundant l = match l with _ :: _ -> 1 | [] -> 0 | x -> 2;;
(match 5 with 0 -> "zero" | n -> "other", match [1] with [] -> 0);;
let shadow = fun x -> fun x -> x;;
let rec not_recursive x = x + 1;;
let inner_rec n = let rec helper k = k * 2 in helper n;;
let _ignored = fun _unused -> 0;;

(* syntax errors *)
let broken = (1 + 2;;
let x = if true then 1;;
let str = "unterminated;;
let swallowed = 1;;
let t = 3 # 4;;
let big = 99999999999;;
let esc = "bad \q escape";;
let q = 'a;;
fst (1, 2, 3);;
let f x = match x with | -> 0;;
let g = fun -> 1;;
val bad : int list -> ;;
1 + if true then 1 else 2;;
let h = [1; 2;];;
let survivor = answer + 1;;
let unfinished = 1 +
