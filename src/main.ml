open Frama_c_kernel
open Cil_datatype

module P = Plugin.Register (struct
  let name = "frama-c-ocaml-ctypes"
  let shortname = name
  let help = "Generate ocaml-ctypes definition from headers"
end)

module Output_type = P.String (struct
  let option_name = "-output-type"
  let arg_name = "FILE"
  let help = "filename for the type description"
  let default = "type_description.ml"
end)

module Output_fun = P.String (struct
  let option_name = "-output-function"
  let arg_name = "FILE"
  let help = "filename for the function description"
  let default = "function_description.ml"
end)

let init () =
  Kernel.AutoLoadPlugins.off ();
  Rmtmps.keepUnused := true;
  Kernel.FramaCStdLib.off ();
  Kernel.C11.on ();
  Kernel.Machdep.set "gcc_x86_64"

let () = Cmdline.run_after_early_stage init

(** Convert function definitions into declarations *)

let remove_def ((f, l) : Cabs.file) =
  let treat_one_global (b, d) =
    let d =
      match d with
      | Cabs.FUNDEF (None, (t, ((_, _, _, _) as name)), _, _, l2) ->
          Cabs.DECDEF (None, (t, [ (name, Cabs.NO_INIT) ]), l2)
      | Cabs.DECDEF (None, (a, names), l) ->
          let names = List.map (fun (n, _) -> (n, Cabs.NO_INIT)) names in
          Cabs.DECDEF (None, (a, names), l)
      | _ -> d
    in
    (b, d)
  in
  (f, List.map treat_one_global l)

let () = Frontc.add_syntactic_transformation remove_def

(** Print OCaml code *)

let rec print_type fmt (typ : Cil_types.typ) =
  match typ with
  | TVoid _ -> Fmt.pf fmt "void"
  | TInt (kind, _) ->
      Fmt.pf fmt
        (match kind with
        | IBool -> "bool"
        | IChar -> "char"
        | ISChar -> "char"
        | IUChar -> "uchar"
        | IInt -> "int"
        | IUInt -> "uint"
        | IShort -> "short"
        | IUShort -> "ushort"
        | ILong -> "long"
        | IULong -> "ulong"
        | ILongLong -> "longlong"
        | IULongLong -> "ulonglong")
  | TFloat (kind, _) ->
      Fmt.pf fmt
        (match kind with
        | FFloat -> "float"
        | FDouble -> "double"
        | FLongDouble -> "longdouble")
  | TPtr (typ, _) -> Fmt.pf fmt "ptr (%a)" print_type typ
  (*  | TArray (typ,{exp_node=Constant (CInt64(i,_,_))}) -> () *)
  | TArray (typ, _, _) -> Fmt.pf fmt "ptr (%a)" print_type typ
  | TFun _ -> assert false
  | TNamed (typeinfo, _) -> Fmt.pf fmt "%s" typeinfo.tname
  | TComp (compinfo, _) -> Fmt.pf fmt "%s" compinfo.cname
  | TEnum (enuminfo, _) -> Fmt.pf fmt "%s" enuminfo.ename
  | TBuiltin_va_list _ -> assert false

let print_orig = Fmt.quote Fmt.string

let print_type_global fmt (global : Cil_types.global) =
  let print_fields fmt (compinfo : Cil_types.compinfo) =
    let print_field fmt (field : Cil_types.fieldinfo) =
      Fmt.pf fmt "@[let %s = field D.t %a %a@]" field.fname print_orig
        field.forig_name print_type field.ftype
    in
    Fmt.list print_field fmt (Option.value ~default:[] compinfo.cfields)
  in
  match global with
  | GType (typeinfo, _) -> (
      match typeinfo.ttype with
      | TComp (({ corig_name = ""; _ } as c), _) ->
          Fmt.pf fmt "@[<v 2>@[module S_%s = struct@]@ " typeinfo.tname;
          Fmt.pf fmt "@[<v 2>@[module D = struct@]@ ";
          Fmt.pf fmt "@[type t@]@ ";
          Fmt.pf fmt
            "@[<hv 1>@[let t : t structure typ =@]@ @[let s = structure \"\" \
             in@]@ @[typedef s %a@]@]@ "
            print_orig typeinfo.torig_name;
          Fmt.pf fmt "@]@,@[end@]@ ";
          Fmt.pf fmt "%a@," print_fields c;
          Fmt.pf fmt "@[let () = seal D.t@]";
          Fmt.pf fmt "@]@,@[end@]@ ";
          Fmt.pf fmt "@[type %s = S_%s.D.t@]@ " typeinfo.tname typeinfo.tname;
          Fmt.pf fmt "@[let %s = S_%s.D.t@]" typeinfo.tname typeinfo.tname
      | _ ->
          Fmt.pf fmt "@[let %s = typedef %a %a@]" typeinfo.tname print_type
            typeinfo.ttype print_orig typeinfo.torig_name)
  | GCompTag (compinfo, _) ->
      assert (compinfo.corig_name <> "");
      Fmt.pf fmt "let %s = struct %a" compinfo.cname (Fmt.quote Fmt.string)
        compinfo.corig_name;
      Fmt.pf fmt "let () = seal %s" compinfo.cname
  | GCompTagDecl (compinfo, _) ->
      Fmt.pf fmt "let %s = structure \"%s\"" compinfo.cname compinfo.corig_name
  | GEnumTag (enuminfo, _) ->
      Fmt.pf fmt "let %s = enum \"%s\"" enuminfo.ename enuminfo.eorig_name
  | GEnumTagDecl (enuminfo, _) ->
      Fmt.pf fmt "let %s = enum \"%s\"" enuminfo.ename enuminfo.eorig_name
  | GVarDecl _ -> ()
  | GFunDecl _ -> ()
  | GVar _ -> ()
  | GFun _ -> ()
  | GAsm _ -> ()
  | GPragma _ -> ()
  | GText _ -> ()
  | GAnnot _ -> ()

let print_in_file file f =
  let cout = open_out file in
  Fun.protect
    ~finally:(fun () -> close_out cout)
    (fun () ->
      let fmt = Format.formatter_of_out_channel cout in
      f fmt;
      Format.pp_print_flush fmt ())

let print_type_file type_name files globals =
  let is_type_of_files (g : Global.t) =
    (match g with
    | GCompTag ({ corig_name = ""; _ }, _) -> false
    | GType _ | GEnumTag _ | GEnumTagDecl _ | GCompTag _ | GCompTagDecl _ ->
        true
    | GVarDecl _ | GFunDecl _ | GVar _ | GFun _ | GAsm _ | GPragma _ | GText _
    | GAnnot _ ->
        false)
    &&
    let loc, _ = Cil_datatype.Global.loc g in
    Datatype.Filepath.Set.mem loc.pos_path files
  in

  let globals = List.filter is_type_of_files globals in
  Kernel.feedback "print type in %s@." type_name;
  print_in_file type_name (fun fmt ->
      Fmt.pf fmt
        {|open Ctypes

      module Types (F : Ctypes.TYPE) = struct
        open F
      |};
      Fmt.pf fmt "@[<v>%a@]@, " (Fmt.list print_type_global) globals;
      Fmt.pf fmt "end")

let print_function_global fmt (global : Cil_types.global) =
  match global with
  | GFunDecl (_, vi, _) -> (
      match vi.vtype with
      | Cil_types.TFun (result, (Some [] | None), _, _) ->
          Fmt.pf fmt "let %s = foreign %a (void @-> returning %a)@ "
            vi.vorig_name print_orig vi.vorig_name print_type result
      | Cil_types.TFun (result, Some args, _, _) ->
          Fmt.pf fmt "let %s = foreign %a (%a @-> returning %a)@ " vi.vorig_name
            print_orig vi.vorig_name
            (Fmt.list ~sep:(Fmt.any "@,@-> ")
               (Fmt.using (fun (_, x, _) -> x) print_type))
            args print_type result
      | _ ->
          P.failure "Unexcepted type %a for global:%a" Cil_datatype.Typ.pretty
            vi.vtype Cil_datatype.Global.pretty global)
  | GFun (_, _)
  | GVarDecl (_, _)
  | GVar (_, _, _)
  | GType _ | GEnumTag _ | GEnumTagDecl _ | GCompTag _ | GCompTagDecl _ | GAsm _
  | GPragma _ | GText _ | GAnnot _ ->
      assert false

let print_function_file ~output_type fun_name files globals =
  let is_fun_of_files (g : Global.t) =
    (match g with
    | GFunDecl _ -> true
    | GFun _ ->
        P.failure "Unexpected global: %a" Cil_datatype.Global.pretty g;
        false
    | GVarDecl _ | GVar _ | GType _ | GEnumTag _ | GEnumTagDecl _ | GCompTag _
    | GCompTagDecl _ | GAsm _ | GPragma _ | GText _ | GAnnot _ ->
        false)
    &&
    let loc, _ = Cil_datatype.Global.loc g in
    Datatype.Filepath.Set.mem loc.pos_path files
  in

  let globals = List.filter is_fun_of_files globals in
  Kernel.feedback "print function in %s@." fun_name;
  print_in_file fun_name (fun fmt ->
      Fmt.pf fmt
        {|open Ctypes

(* This Types_generated module is an instantiation of the Types
   functor defined in the type_description.ml file. It's generated by
   a C program that dune creates and runs behind the scenes. *)
module Types = %s

module Functions (F : Ctypes.FOREIGN) = struct
  open F
  open Types
  @[<v 2>%a@]
end|}
        (String.capitalize_ascii
           (Filename.chop_extension (Filename.basename output_type)))
        (Fmt.list print_function_global)
        globals)

let main () =
  let files = Kernel.Files.get () in
  let ast = Ast.get () in
  let files = Datatype.Filepath.Set.of_list files in
  let output_type = Output_type.get () in
  print_type_file output_type files ast.globals;
  print_function_file ~output_type (Output_fun.get ()) files ast.globals

let () = Db.Main.extend main

let boot () =
  let play_analysis () =
    if Kernel.TypeCheck.get () then
      if Kernel.Files.get () <> [] || Kernel.TypeCheck.is_set () then (
        Ast.compute ();
        (* Printing files before anything else (in debug mode only) *)
        if Kernel.debug_atleast 1 && Kernel.is_debug_key_enabled Kernel.dkey_ast
        then Frama_c_kernel.File.pretty_ast ());
    try
      Db.Main.apply ();
      Log.treat_deferred_error ();
      (* Printing code, if required, have to be done at end. *)
      if Kernel.PrintCode.get () then Frama_c_kernel.File.pretty_ast ();
      (* Easier to handle option -set-project-as-default at the last moment:
         no need to worry about nested [Project.on] *)
      Project.set_keep_current (Kernel.Set_project_as_default.get ());
      (* unset Kernel.Set_project_as_default, but only if it set.
         This avoids disturbing the "set by user" flag. *)
      if Kernel.Set_project_as_default.get () then
        Kernel.Set_project_as_default.off ()
    with Globals.No_such_entry_point msg -> Kernel.abort "%s" msg
  in

  let on_from_name name f =
    try Project.on (Project.from_unique_name name) f ()
    with Project.Unknown_project -> Kernel.abort "no project `%s'." name
  in
  let () = Db.Main.play := play_analysis in
  let () =
    Sys.catch_break true;
    let f () =
      ignore (Project.create "default");
      let on_from_name = { Cmdline.on_from_name } in
      Cmdline.parse_and_boot ~on_from_name
        ~get_toplevel:(fun () -> !Db.Toplevel.run)
        ~play_analysis
    in
    Cmdline.catch_toplevel_run ~f ~at_normal_exit:Cmdline.run_normal_exit_hook
      ~on_error:Cmdline.run_error_exit_hook
  in
  ()

let () = boot ()