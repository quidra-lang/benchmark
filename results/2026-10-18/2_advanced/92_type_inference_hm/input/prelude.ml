(* prelude.ml: combinators and list functions loaded before the program *)
let id x = x;;
let const x _ = x;;
let compose f g x = f (g x);;
let flip f x y = f y x;;
let twice f x = f (f x);;
let curry f x y = f (x, y);;
let uncurry f p = f (fst p) (snd p);;
let swap p = (snd p, fst p);;

val abs : int -> int;;
let abs n = if n < 0 then - n else n;;
let max a b = if a < b then b else a;;
let min a b = if a < b then a else b;;

let is_empty l = match l with [] -> true | _ -> false;;
let hd l = match l with x :: _ -> x | [] -> failwith "hd";;
let tl l = match l with _ :: rest -> rest | [] -> failwith "tl";;

let rec length l = match l with [] -> 0 | _ :: rest -> 1 + length rest;;
let rec map f l = match l with [] -> [] | x :: rest -> f x :: map f rest;;
let rec filter p l =
  match l with
  | [] -> []
  | x :: rest -> if p x then x :: filter p rest else filter p rest;;
let rec fold_left f acc l =
  match l with [] -> acc | x :: rest -> fold_left f (f acc x) rest;;
let rec fold_right f l acc =
  match l with [] -> acc | x :: rest -> f x (fold_right f rest acc);;
let append a b = fold_right (fun x acc -> x :: acc) a b;;
let rev l = fold_left (fun acc x -> x :: acc) [] l;;
let concat ls = fold_right append ls [];;
let rec range a b = if a > b then [] else a :: range (a + 1) b;;
val sum : int list -> int;;
let sum l = fold_left (fun a b -> a + b) 0 l;;
let rec exists p l = match l with [] -> false | x :: rest -> p x || exists p rest;;
let for_all p l = not (exists (fun x -> not (p x)) l);;
let mem x l = exists (fun y -> y = x) l;;
let rec nth l n =
  match l with
  | [] -> failwith "nth"
  | x :: rest -> if n = 0 then x else nth rest (n - 1);;
let rec assoc k l =
  match l with
  | [] -> failwith ("assoc " ^ k)
  | (key, v) :: rest -> if key = k then v else assoc k rest;;
let rec zip a b =
  match (a, b) with
  | ([], []) -> []
  | (x :: xs, y :: ys) -> (x, y) :: zip xs ys
  | _ -> failwith "zip";;
let unzip l = (map fst l, map snd l);;
let rec take n l =
  if n = 0 then [] else match l with [] -> [] | x :: rest -> x :: take (n - 1) rest;;
let rec drop n l =
  if n = 0 then l else match l with [] -> [] | _ :: rest -> drop (n - 1) rest;;
let rec insert le x l =
  match l with
  | [] -> [x]
  | y :: rest -> if le x y then x :: l else y :: insert le x rest;;
let sort le l = fold_right (insert le) l [];;
let rec join sep l =
  match l with
  | [] -> ""
  | [x] -> x
  | x :: rest -> x ^ sep ^ join sep rest;;
let partition p l = (filter p l, filter (fun x -> not (p x)) l);;
let flat_map f l = concat (map f l);;
let rec last l = match l with [x] -> x | _ :: rest -> last rest;;
let rec iterate n f x = if n = 0 then x else iterate (n - 1) f (f x);;
