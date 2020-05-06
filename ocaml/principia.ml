open Sexp
open Errors
open Lexing
open Prelude
open Checker
open Datatypes

let parseErr f lexbuf =
  try f Lexer.main lexbuf with
  | Parser.Error ->
    raise (Errors.Parser (lexeme_start lexbuf, lexeme_end lexbuf))
  | Failure msg ->
    raise (Errors.Lexer (msg, lexeme_start lexbuf, lexeme_end lexbuf))

let parse filename =
  let chan = open_in filename in
  Printf.printf "Parsing “%s”.\n" filename;
  let lexbuf = Lexing.from_channel chan in
  parseErr Parser.file lexbuf

let sep = "─-"

let extList : sexp -> sexp list = function
  | List xs -> xs
  | u       -> showSExp u
               |> Printf.sprintf "Expected list at “%s”"
               |> fun x -> Other x
               |> raise

(* This will probably be faster
   than converting string into char list
   and using List.for_all *)
let isSeparator : sexp -> bool = function
  | Atom s -> let res = ref true in
    String.iter (fun ch -> res := String.contains sep ch && !res) s; !res
  | _      -> false

let rec macroexpand curr tau =
  let mu =
    findMap (fun x -> let (pattern, body) = x in
                      try let substs = matches Env.empty pattern tau in
                          Some (multisubst substs body)
                      with MatchError _ -> None) curr.defs in
  let tau' = match mu with
  | Some v -> v
  | None   -> tau in
  match tau' with
  | Symtree xs -> Symtree (List.map (macroexpand curr) xs)
  | v          -> v

let parseTerm curr expr =
  macroexpand curr (term curr expr)

let separators = [":="; "≔"]
let genEnv curr xs =
  let rec genEnvAux env : sexp list -> env = function
    | x :: Atom sep :: value :: rest ->
      if List.mem sep separators then
        genEnvAux (Env.add (symbol x) (parseTerm curr value) env) rest
      else raise (Other "Invalid separator “:=”.")
    | [] -> env
    | _ -> raise (Other "Invalid substitution list.") in
  genEnvAux Env.empty xs

let rec parseDeriv curr : sexp -> derivation = function
  | List (Atom "sorry" :: xs) ->
    Sorry (String.concat " " (List.map symbol xs))
  | List (name :: Supp xs :: ys) ->
    Proof { edge          = symbol name;
            children      = List.map (parseDeriv curr) ys;
            substitutions = genEnv curr xs }
  | List (name :: xs) ->
    Proof { edge          = symbol name;
            children      = List.map (parseDeriv curr) xs;
            substitutions = Env.empty }
  | x when isPrimitive x -> Proof { edge          = symbol x;
                                    children      = [];
                                    substitutions = Env.empty }
  | expr -> showSExp expr
            |> Printf.sprintf "“%s” is not proof tree"
            |> fun x -> Other x
            |> raise

let pop (xs : ('a list) ref) : 'a =
  match !xs with
  | x :: xs' -> xs := xs'; x
  | [] -> raise (Failure "pop")

let preamble curr (expr : (sexp list) ref) =
  let finished : bool ref        = ref false in
  let expected : int ref         = ref 0 in
  let names    : (name list) ref = ref [] in
  let premises : (term list) ref = ref [] in
  let elem     : sexp ref        = ref (Atom "_") in
  while not !finished do
    elem := pop expr;
    if isSeparator !elem then begin
      names := symbol (pop expr) :: !names;
      expected := !expected + 1
    end
    else if !expected <> 0 then begin
      premises := parseTerm curr !elem :: !premises;
      expected := !expected - 1
    end
    else finished := true
  done;
  if List.length !names <> List.length !premises then
    raise (Other "Invalid theorem definition")
  else ();
  let name = pop names in let conclusion = pop premises in
  (name, conclusion,
   List.rev !names, List.rev !premises,
   parseDeriv curr !elem)

let init : state =
  { variables = [];
    infix     = Env.empty;
    context   = Env.empty;
    bound     = [];
    defs      = [] }

let st : state ref = ref init

let evalTheorem src =
  let expr : (sexp list) ref = ref src in
  while nonempty !expr do
    let (name, conclusion, names, premises, proof) = preamble !st expr in
    let ctx = ref !st.context in
    List.iter2
      (fun name tau ->
        ctx := Env.add name { premises   = [];
                              conclusion = tau } !ctx)
      names premises;
    if Env.mem name !st.context then
      raise (AlreadyDefinedError name)
    else
      check !ctx !st.bound conclusion proof;
      Printf.printf "“%s” checked\n" name;
      st := { !st with context =
        Env.add name { premises   = premises;
                       conclusion = conclusion }
                !st.context }
  done

let rec eval : sexp list -> unit = function
  | [Atom "infix"; Atom op; Int prec] ->
    st := { !st with infix = Env.add op prec !st.infix }
  | Atom "variables" :: xs ->
    st := { !st with variables = !st.variables @ List.map symbol xs }
  | Atom "bound" :: xs ->
    st := { !st with bound = !st.bound @ List.map (term !st) xs }
  | [Atom "define"; pattern; body] ->
    st := { !st with defs = (term !st pattern, parseTerm !st body) :: !st.defs }
  | Atom "include" :: xs ->
    List.iter (symbol >> dofile) xs
  | Atom "postulate" :: expr ->
    let stack : (sexp list) ref = ref expr in
    let premises : (term list) ref = ref [] in
    while nonempty !stack do
      let x = pop stack in
      if isSeparator x then
        let name       = symbol (pop stack) in
        let conclusion = pop stack in
        if Env.mem name !st.context then
          raise (AlreadyDefinedError name)
        else begin
          st := { !st with context =
                  Env.add name
                    { premises   = !premises;
                      conclusion = parseTerm !st conclusion }
                    !st.context };
          premises := []
        end
      else premises := !premises @ [parseTerm !st x]
    done;
    if nonempty !premises then
      raise (Other "Incomplete postulate.")
    else ()
  | Atom "lemma"   :: expr
  | Atom "theorem" :: expr -> evalTheorem expr
  | x :: xs ->
    Other (Printf.sprintf "Unknown/incorrect form “%s”" (showSExp x)) |> raise
  | []      -> Other "Empty S-Expression" |> raise
and dofile filename =
  parse filename |> List.iter (extList >> handleErrors eval ())

let () =
  Array.to_list Sys.argv
  |> List.tl
  |> List.iter dofile