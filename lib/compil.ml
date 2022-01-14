open Ast

let lbl_counter = ref 0

let genlbl () =
  lbl_counter := !lbl_counter + 1;
  "lbl" ^ string_of_int !lbl_counter

let addr_of env id = match List.assoc_opt id env with
  | Some(addr) -> addr
  | None -> failwith (Printf.sprintf "variable %s not found in env" id)

let addenv env id = match env with
  | [] -> [(id, 0)]
  | (_, addr)::_ -> (id, addr + 1)::env

let compile chan ast =
  let decls = ast.decls in

  let _NOP = Printf.fprintf chan "NOP\n" in
  let _ERR = Printf.fprintf chan "ERR %s\n" in
  let _START = Printf.fprintf chan "START\n" in
  let _STOP = Printf.fprintf chan "STOP\n" in
  let _PUSHI = Printf.fprintf chan "PUSHI %i\n" in
  let _PUSHS = Printf.fprintf chan "PUSHS %s\n" in
  let _PUSHG = Printf.fprintf chan "PUSHG %i\n" in
  let _PUSHL = Printf.fprintf chan "PUSHL %i\n" in
  let _PUSHSP = Printf.fprintf chan "PUSHSP %i\n" in
  let _PUSHFP = Printf.fprintf chan "PUSHFP %i\n" in
  let _STOREL = Printf.fprintf chan "STOREL %i\n" in
  let _STOREG = Printf.fprintf chan "STOREG %i\n" in
  let _PUSHN = Printf.fprintf chan "PUSHN %i\n" in
  let _POPN = Printf.fprintf chan "POPN %i\n" in
  let _DUPN = Printf.fprintf chan "DUPN %i\n" in
  let _SWAP = Printf.fprintf chan "SWAP\n" in
  let _EQUAL = Printf.fprintf chan "EQUAL\n" in
  let _NOT = Printf.fprintf chan "NOT\n" in
  let _JUMP = Printf.fprintf chan "JUMP %s\n" in
  let _JZ = Printf.fprintf chan "JZ %s\n" in
  let _PUSHA = Printf.fprintf chan "PUSHA %s\n" in
  let _CALL = Printf.fprintf chan "CALL\n" in
  let _RETURN = Printf.fprintf chan "RETURN\n" in
  let _ADD = Printf.fprintf chan "ADD\n" in
  let _SUB = Printf.fprintf chan "SUB\n" in
  let _MUL = Printf.fprintf chan "MUL\n" in
  let _DIV = Printf.fprintf chan "DIV\n" in
  let _INF = Printf.fprintf chan "INF\n" in
  let _INFEQ = Printf.fprintf chan "INFEQ\n" in
  let _SUP = Printf.fprintf chan "SUP\n" in
  let _SUPEQ = Printf.fprintf chan "SUPEQ\n" in
  let _WRITEI = Printf.fprintf chan "WRITEI\n" in
  let _STR = Printf.fprintf chan "STR\n" in
  let _WRITES = Printf.fprintf chan "WRITES\n" in
  let _CONCAT = Printf.fprintf chan "CONCAT\n" in
  let _STORE = Printf.fprintf chan "STORE %d\n" in
  let _LOAD = Printf.fprintf chan "LOAD %d\n" in
  let _ALLOC = Printf.fprintf chan "ALLOC %d\n" in
  let _LABEL = Printf.fprintf chan "%s: NOP\n" in
  let _COMMENT = Printf.fprintf chan "-- %s\n" in
  
  let code_op op = match op with
    | Eq -> _EQUAL
    | Neq -> _EQUAL; _NOT
    | Lt -> _INF
    | Le -> _INFEQ
    | Gt -> _SUP
    | Ge -> _SUPEQ
    | Add -> _ADD
    | Sub -> _SUB
    | Mul -> _MUL
    | Div -> _DIV in
  
  
  let rec code_ite env cmp yes no =
    let lbl_else = genlbl () in
    let lbl_end = genlbl () in
    code_cmp env cmp;
    _JZ lbl_else;
    (code_expr env yes);
    _JUMP lbl_end;
    _LABEL lbl_else;
    (code_expr env no);
    _LABEL lbl_end;
  
  and code_cmp env (op, e1, e2) =
    code_expr env e1; code_expr env e2; (code_op op)
  
  and get_attr a = 
    ()  

  and code_expr env e =
    (match e with
      | Id(id) -> _PUSHG (addr_of env id)
      | Cste(c) -> _PUSHI c
      | Attr(e, s) -> get_attr e 
      | StaticAttr(s1, s2) -> ()
      | UMinus(e) -> _PUSHI 0; code_expr env e; _SUB
      | Call(e, s, le) -> () 
      | StaticCall(s1, s2, le) -> ()
      | BinOp(e1, op, e2) -> code_expr env e1; code_expr env e2; code_op op;
      | String(s) -> _PUSHS s
      | StrCat(s1, s2) -> code_expr env s1; code_expr env s2; _CONCAT
      | New(s, le) -> ()
      | StaticCast(s, e) -> ()
      )


  and code_ast ast =
    ()  
in
  code_ast ast