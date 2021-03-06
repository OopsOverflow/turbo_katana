open Ast
open Astmanip

type state = {
  addrs: Addrs.t;
  env: Env.t;
}

let chan = ref stdout

let lbl_counter = ref 0

(** Generate a unique label. *)
  
let unique_lbl () =
  lbl_counter := !lbl_counter + 1;
  "lbl" ^ string_of_int !lbl_counter

(** Generate a unique method label. *)

let meth_lbl className methName =
  Printf.sprintf "%s_%i_%s" className (String.length methName) methName

(** Generate a unique constructor label. *)

let ctor_lbl className =
  Printf.sprintf "_CTOR_%s_" className

(** Generate a unique static method label. *)

let static_lbl className methName =
	Printf.sprintf "%s_%i_%s" className (String.length methName) methName

(** Get a list of all instance attributes in a class, in offset order. *)

let rec all_attrs decls decl = 
  let attrs = 
    List.map (fun ({ name; _ }: param) -> name) decl.instAttrs
  in match decl.super with
  | None -> attrs
  | Some(super) ->
    let super = get_class decls super.name
    in all_attrs decls super @ attrs
  
(** Get the offset of an instance attribute in a class. *)

let attr_offset decls decl attrName =
  let attrs = all_attrs decls decl
  in let rev_index = List.rev attrs |> Util.index_of attrName
  in (List.length attrs) - rev_index (* VTABLE is offset 0 *) 

(** Get the offset of an static attribute in a class. *)

let static_attr_offset decls decl attr =
	let rec r_offset decls =
		match decls with 
		| d::_ when decl = d -> 
			List.map (fun (a: param) -> a.name) d.staticAttrs 
			|> Util.index_of attr
		| d::r -> (List.length d.staticAttrs) + r_offset r 
		| _ -> failwith "static_attr_offset unreachable"
	in r_offset decls + List.length decls (* after the vtables *)
    
(* --------------------------------------------- *)

(** Put the code of the program on the output channel. *)

let _NOP () = Printf.fprintf !chan "NOP\n"
let _ERR = Printf.fprintf !chan "ERR %s\n"
let _START () = Printf.fprintf !chan "START\n"
let _STOP () = Printf.fprintf !chan "STOP\n"
let _PUSHI = Printf.fprintf !chan "PUSHI %i\n"
let _PUSHS s = Printf.fprintf !chan "PUSHS \"%s\"\n" (String.escaped s)
let _PUSHG = Printf.fprintf !chan "PUSHG %i\n"
let _PUSHL = Printf.fprintf !chan "PUSHL %i\n"
let _PUSHSP = Printf.fprintf !chan "PUSHSP %i\n"
let _PUSHFP = Printf.fprintf !chan "PUSHFP %i\n"
let _STOREL = Printf.fprintf !chan "STOREL %i\n"
let _STOREG = Printf.fprintf !chan "STOREG %i\n"
let _PUSHN = Printf.fprintf !chan "PUSHN %i\n"
let _POPN = Printf.fprintf !chan "POPN %i\n"
let _DUPN = Printf.fprintf !chan "DUPN %i\n"
let _SWAP () = Printf.fprintf !chan "SWAP\n"
let _EQUAL () = Printf.fprintf !chan "EQUAL\n"
let _NOT () = Printf.fprintf !chan "NOT\n"
let _JUMP = Printf.fprintf !chan "JUMP %s\n"
let _JZ = Printf.fprintf !chan "JZ %s\n"
let _PUSHA = Printf.fprintf !chan "PUSHA %s\n"
let _CALL () = Printf.fprintf !chan "CALL\n"
let _RETURN () = Printf.fprintf !chan "RETURN\n"
let _ADD () = Printf.fprintf !chan "ADD\n"
let _SUB () = Printf.fprintf !chan "SUB\n"
let _MUL () = Printf.fprintf !chan "MUL\n"
let _DIV () = Printf.fprintf !chan "DIV\n"
let _INF () = Printf.fprintf !chan "INF\n"
let _INFEQ () = Printf.fprintf !chan "INFEQ\n"
let _SUP () = Printf.fprintf !chan "SUP\n"
let _SUPEQ () = Printf.fprintf !chan "SUPEQ\n"
let _WRITEI () = Printf.fprintf !chan "WRITEI\n"
let _STR () = Printf.fprintf !chan "STR\n"
let _WRITES () = Printf.fprintf !chan "WRITES\n"
let _CONCAT () = Printf.fprintf !chan "CONCAT\n"
let _STORE = Printf.fprintf !chan "STORE %d\n"
let _LOAD = Printf.fprintf !chan "LOAD %d\n"
let _ALLOC = Printf.fprintf !chan "ALLOC %d\n"
let _LABEL = Printf.fprintf !chan "%s: NOP\n"
let _COMMENT = Printf.fprintf !chan "-- %s\n"
let _BREAK () = Printf.fprintf !chan "* NOP\n"

(* Code for a binary integer operation. *)

let code_op op = match op with
  | Eq -> _EQUAL ()
  | Neq -> _EQUAL (); _NOT ()
  | Lt -> _INF ()
  | Le -> _INFEQ ()
  | Gt -> _SUP ()
  | Ge -> _SUPEQ ()
  | Add -> _ADD ()
  | Sub -> _SUB ()
  | Mul -> _MUL ()
  | Div -> _DIV ()

(* -------------- INSTRUCTIONS -------------- *)
(* Below are functions to generate code for instructions.
 * Code generated by instructions leaves the stack as it was 
 * before execution. 
 *)

(** Code for an if / then / else instruction. *)

let rec code_instr_ite decls state (cmp, yes, no) =
  let lbl_else = unique_lbl () in
  let lbl_end = unique_lbl () in
  code_expr decls state cmp;
  _JZ lbl_else;
  (code_instr decls state yes);
  _JUMP lbl_end;
  _LABEL lbl_else;
  (code_instr decls state no);
  _LABEL lbl_end;

(** Code for a block instruction. *)

and code_instr_block decls state (lp, li) =
  let state = {
    addrs = List.fold_left (fun addrs (p: param) -> Addrs.add_local addrs p.name) state.addrs lp;
    env = List.fold_left (fun env (p: param) -> Env.add env p) state.env lp;
  }
  in _PUSHN (List.length lp);
	List.iter (code_instr decls state) li;
  _POPN (List.length lp)

(** Code for an assign instruction. *)

and code_instr_assign decls state (to_, from_) =
	match to_ with
	| Attr(e, s) -> 
		let name = get_expr_type decls state.env e 
		in let decl = get_class decls name
		in let off = attr_offset decls decl s
		in code_expr decls state e;
		code_expr decls state from_;
		_STORE off

	| StaticAttr(name, s) ->
		let decl = get_class decls name
		in let addr = static_attr_offset decls decl s
		in code_expr decls state from_;
		_STOREG addr

	| Id(s) -> 
		let addr = Addrs.get state.addrs s
		in code_expr decls state from_;
		_STOREL addr

	| _ -> failwith "code_instr_assign unreachable"
  
(** Code for an instruction. *)

and code_instr decls state instr = 
  match instr with
  | Block(lp, li) -> code_instr_block decls state (lp, li)
  | Assign(to_, from_) -> code_instr_assign decls state (to_, from_)
  | Return -> _RETURN ()
  | Ite(cmp, yes, no) -> code_instr_ite decls state (cmp, yes, no)
  | Expr(e) -> code_expr decls state e; _POPN 1 

(* -------------- EXPRESSIONS -------------- *)
(* Below are functions to generate code for expressions.
 * Code generated by expressions leaves a pointer to the 
 * instance on the stack. 
 *
 * In case of builtin types such as Integer or String,
 * it leaves an integer or a pointer to the strings heap
 * on the stack.
 *
 * For Void expressions, it leaves something undefined on
 * the stack.
 *)

(** Code for an attribute expression. *)

and code_expr_attr decls state (e, s) = 
  match e with
  | Id("super") ->
      let clName = Env.get state.env "this"
      in let decl = get_class decls clName
      in let superDecl = get_class decls (Option.get decl.super).name
      in _PUSHL (Addrs.get state.addrs "this"); (* push this *)
      _LOAD (attr_offset decls superDecl s)
  
  | _ ->
    code_expr decls state e; (* push this *)
    let decl = get_expr_type decls state.env e 
    in let decl = get_class decls decl
    in _LOAD (attr_offset decls decl s)

(** Code for a string method call expression. *)

and code_builtin_string decls state e m = 
  code_expr decls state e; (* push this *)

  match m with
  | "print" -> _DUPN 1; _WRITES ()
  | "println" -> _DUPN 1; _WRITES (); _PUSHS "\n"; _WRITES ()
  | _ -> failwith "code_builtin_string unreachable"
  
(** Code for a integer method call expression. *)

and code_builtin_integer decls state e m =
  code_expr decls state e; (* push this *)

  match m with
  | "toString" -> _STR ()
  | _ -> failwith "code_builtin_integer unreachable"

(** Code for a method call expression. *)

and code_expr_call decls state (e, methName, args) = 
  let clName = get_expr_type decls state.env e
    
  in match clName with
  | "Integer" -> code_builtin_integer decls state e methName
  | "String" -> code_builtin_string decls state e methName
  | _ ->
    if e = Id("super")
    then
      let clName = Env.get state.env "this"
      in let decl = get_class decls clName
      in let superDecl = get_class decls (Option.get decl.super).name
      in _PUSHI 0; (* push result *)
      List.iter (code_expr decls state) args; (* push args *)
      _PUSHL (Addrs.get state.addrs "this"); (* push this *)
      _PUSHA (meth_lbl superDecl.name methName);
      _CALL ();
      _POPN ((List.length args) + 1) (* pop args & this, leave result *)

    else
      let decl = get_class decls clName
      in let vt = Vtable.make decls decl
      in let meth = find_method decls methName decl
      in _PUSHI 0; (* push result *)
      List.iter (code_expr decls state) args; (* push args *)
      code_expr decls state e; (* push this *)
      _DUPN 1;
      _LOAD 0;
      _LOAD (Vtable.offset vt meth);
      _CALL ();
      _POPN ((List.length args) + 1) (* pop args & this, leave result *)

(** Code for a static attribute expression. *)

and code_expr_static_attr decls (clName, attrName) =
  let decl = get_class decls clName
  in let off = static_attr_offset decls decl attrName
  in _PUSHG off  

(** Code for a static method call expression. *)

and code_expr_static_call decls state (clName, methName, args) =
	let name = static_lbl clName methName
  in _PUSHI 0; (* push result *)
	List.iter (code_expr decls state) args; (* push args *)
	_PUSHA name;
	_CALL ();
  _POPN (List.length args) (* pop args, leave result *)

(** Code for a new expression. *)

and code_expr_new decls state (clName, args) =
	let name = ctor_lbl clName
  in let decl = get_class decls clName
  in let size = List.length (all_attrs decls decl) + 1
  in let vti = Util.index_of decl decls
	in
  _ALLOC size; (* push this *)
  _DUPN 1;
  _PUSHG vti;
  _STORE 0;
  List.iter (code_expr decls state) args; (* push args *)
  _PUSHA name;
	_CALL ();
  _POPN (List.length args) (* pop args, leave this *)
      
(** Code for an expression. *)

and code_expr decls state e =
  match e with
  | Id(id) -> _PUSHL (Addrs.get state.addrs id)
  | Cste(c) -> _PUSHI c
  | Attr(e, s) -> code_expr_attr decls state (e, s)
  | StaticAttr(clName, attrName) -> code_expr_static_attr decls (clName, attrName)
  | UMinus(e) -> _PUSHI 0; code_expr decls state e; _SUB ()
  | Call(e, s, le) -> code_expr_call decls state (e, s, le) 
  | StaticCall(clName, methName, args) -> code_expr_static_call decls state (clName, methName, args)
  | BinOp(e1, op, e2) -> code_expr decls state e1; code_expr decls state e2; code_op op
  | String(s) -> _PUSHS s
  | StrCat(s1, s2) -> code_expr decls state s1; code_expr decls state s2; _CONCAT ()
  | New(clName, args) -> code_expr_new decls state (clName, args)
  | StaticCast(_, e) -> code_expr decls state e

(* -------------- INITIALIZATION -------------- *)
(* Below functions generate code for the program initialization.
 * Initialization includes:
 *  - code to generate the virtual tables,
 *  - code to allocate pointers on the stack for global variables,
 *  - code of the main instruction block.
 *  - code of the static and instance methods,
 *)

(** Code for a virtual table for a class.
    Leave a pointer to the VT on stack after execution. *)

let code_vtable decls decl =
  let vt = Vtable.make decls decl
  in _ALLOC (List.length vt);
    vt |> List.iteri (fun i (name, decl) -> 
      _DUPN 1;
      _PUSHA (meth_lbl decl.name name);
      _STORE i
    )

(** Code of a call to super constructor.
    Expects 'this' on stack and leave 'this' after execution. *)

let code_super_call decls state decl =
  let { args; name } = Option.get decl.super
  in _PUSHL (Addrs.get state.addrs "this"); (* push this *)
  List.iter (code_expr decls state) args; (* push args *)
  _PUSHA (ctor_lbl name);
  _CALL ();
  _POPN ((List.length args) + 1) (* pop args & this *)

(** Code of a constructor.
    Leave the new'ed instance pointer on the stack after execution. *)

let code_ctor decls decl =
  let addrs = Addrs.make_ctor_addrs decl.ctor.params
  in let env = Env.make_class_env decl
  in let env = Env.add_all env decl.ctor.params
  in let state = { addrs; env }

  in _LABEL (ctor_lbl decl.name);
  if Option.is_some decl.super
  then code_super_call decls { addrs; env=[] } decl;
  code_instr decls state decl.ctor.body;
  _RETURN ()

(** Code of an instance method. *)

let code_inst_method decls decl (meth: methodDecl) =
  let addrs = Addrs.make_method_addrs meth.params
  in let env = Env.make_class_env decl
  in let env = Env.add_method_env env meth
  in let state = { addrs; env }
  in _LABEL (static_lbl decl.name meth.name);
  code_instr decls state meth.body;
  _RETURN ()

(** Code of a static method. *)

let code_static_method decls decl (meth: methodDecl) =
  let state = {
    addrs = Addrs.make_static_method_addrs meth.params;
    env = Env.add_method_env [] meth;
  }
  in _LABEL (static_lbl decl.name meth.name);
  code_instr decls state meth.body;
  _RETURN ()

(** Code of static attributes. *)

let code_static_attrs decls =
  let size = List.fold_left (fun acc decl -> acc + (List.length decl.staticAttrs)) 0 decls
	in _PUSHN size

(** Code of the main instuction block. *)

let code_main_instr decls instr =
  code_instr decls { addrs = []; env = []} instr

let compile ast = 

_COMMENT "----- VTABLES -----";
List.iter (code_vtable ast.decls) ast.decls;

_COMMENT "----- STATIC ATTRIBS -----";
code_static_attrs ast.decls;

_COMMENT "----- MAIN INSTRUCTION -----";
_START ();
code_main_instr ast.decls ast.instr;
(* _BREAK (); *)
_STOP ();

_COMMENT "----- FUNCTIONS -----";
ast.decls |> List.iter (fun decl ->
    code_ctor ast.decls decl;
    decl.instMethods |> List.iter (code_inst_method ast.decls decl);
    decl.staticMethods |> List.iter (code_static_method ast.decls decl)
  );

(*	><,`C   --------- ><> *)  