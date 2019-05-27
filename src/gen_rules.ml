open! Stdune
open Import
module Menhir_rules = Menhir
module Toplevel_rules = Toplevel.Stanza
open Dune_file
open! No_io

module For_stanza = struct
  type ('merlin, 'cctx, 'js) t =
    { merlin : 'merlin
    ; cctx   : 'cctx
    ; js     : 'js
    }

  let empty_none =
    { merlin = None
    ; cctx = None
    ; js = None
    }

  let empty_list =
    { merlin = []
    ; cctx = []
    ; js = []
    }

  let cons_maybe hd_o tl =
    match hd_o with
    | Some hd -> hd :: tl
    | None -> tl

  let cons acc x =
    { merlin = cons_maybe x.merlin acc.merlin
    ; cctx = cons_maybe x.cctx acc.cctx
    ; js =
        match x.js with
        | None -> acc.js
        | Some js -> List.rev_append acc.js js
    }

  let rev t =
    { t with
      merlin = List.rev t.merlin
    ; cctx = List.rev t.cctx
    }
end

module Gen(P : sig val sctx : Super_context.t end) = struct
  module CC = Compilation_context
  module SC = Super_context
  (* We need to instantiate Install_rules earlier to avoid issues whenever
   * Super_context is used too soon.
   * See: https://github.com/ocaml/dune/pull/1354#issuecomment-427922592 *)
  module Lib_rules = Lib_rules.Gen(P)

  let sctx = P.sctx

  let with_format sctx ~dir ~f =
    let scope = SC.find_scope_by_dir sctx (Path.as_in_build_dir_exn dir) in
    let project = Scope.project scope in
    Dune_project.find_extension_args project Auto_format.key
    |> Option.iter ~f

  let gen_format_rules sctx ~output_dir =
    with_format sctx ~dir:output_dir
      ~f:(Format_rules.gen_rules_output sctx ~output_dir)

  (* Stanza *)

  let gen_rules dir_contents cctxs
        { Dir_with_dune. src_dir; ctx_dir; data = stanzas
        ; scope; kind = dir_kind ; dune_version = _ } =
    let expander =
      Super_context.expander sctx ~dir:ctx_dir in
    let for_stanza stanza =
      let dir = ctx_dir in
      match stanza with
      | Toplevel toplevel ->
        Toplevel_rules.setup ~sctx ~dir ~toplevel;
        For_stanza.empty_none
      | Library lib ->
        let cctx, merlin =
          Lib_rules.rules lib ~dir ~scope ~dir_contents ~expander ~dir_kind in
        { For_stanza.
          merlin = Some merlin
        ; cctx = Some (lib.buildable.loc, cctx)
        ; js = None
        }
      | Executables exes ->
        let cctx, merlin =
          Exe_rules.rules exes
            ~sctx ~dir ~scope ~expander
            ~dir_contents ~dir_kind
        in
        { For_stanza.
          merlin = Some merlin
        ; cctx = Some (exes.buildable.loc, cctx)
        ; js =
            Some (List.concat_map exes.names ~f:(fun (_, exe) ->
              List.map
                [exe ^ ".bc.js" ; exe ^ ".bc.runtime.js"]
                ~f:(Path.Build.relative ctx_dir)))
        }
      | Alias alias ->
        Simple_rules.alias sctx alias ~dir ~expander;
        For_stanza.empty_none
      | Tests tests ->
        let cctx, merlin =
          Test_rules.rules tests ~sctx ~dir ~scope ~expander ~dir_contents
            ~dir_kind
        in
        { For_stanza.
          merlin = Some merlin
        ; cctx = Some (tests.exes.buildable.loc, cctx)
        ; js = None
        }
      | Copy_files { glob; _ } ->
        let source_dirs =
          let loc = String_with_vars.loc glob in
          let src_glob = Expander.expand_str expander glob in
          Path.Source.relative src_dir src_glob ~error_loc:loc
          |> Path.Source.parent_exn
          |> Path.Source.Set.singleton
        in
        { For_stanza.
          merlin = Some (Merlin.make ~source_dirs ())
        ; cctx = None
        ; js = None
        }
      | Install { Install_conf. section = _; files; package = _ } ->
        List.map files ~f:(fun fb ->
          File_binding.Unexpanded.expand_src ~dir:(Path.build ctx_dir)
            fb ~f:(Expander.expand_str expander))
        |> Path.Set.of_list
        |> Rules.Produce.Alias.add_deps (Alias.all ~dir:(Path.build ctx_dir));
        For_stanza.empty_none
      | _ ->
        For_stanza.empty_none
    in
    let { For_stanza.
          merlin = merlins
        ; cctx = cctxs
        ; js = js_targets
        } = List.fold_left stanzas
              ~init:{ For_stanza.empty_list with cctx = cctxs }
              ~f:(fun acc a -> For_stanza.cons acc (for_stanza a))
            |> For_stanza.rev
    in
    let allow_approx_merlin =
      let dune_project = Scope.project scope in
      Dune_project.allow_approx_merlin dune_project in
    Option.iter (Merlin.merge_all ~allow_approx_merlin merlins)
      ~f:(fun m ->
        let more_src_dirs =
          List.map (Dir_contents.dirs dir_contents) ~f:(fun dc ->
            Path.Build.drop_build_context_exn (Dir_contents.dir dc))
        in
        Merlin.add_rules sctx ~dir:ctx_dir ~more_src_dirs ~expander ~dir_kind
          (Merlin.add_source_dir m src_dir));
    let build_dir = Super_context.build_dir sctx in
    List.iter stanzas ~f:(fun stanza ->
      match (stanza : Stanza.t) with
      | Menhir.T m when Expander.eval_blang expander m.enabled_if ->
        begin match
          List.find_map (Menhir_rules.module_names m)
            ~f:(fun name ->
              Option.bind (Dir_contents.lookup_module dir_contents name)
                ~f:(fun buildable ->
                  List.find_map cctxs ~f:(fun (loc, cctx) ->
                    Option.some_if (Loc.equal loc buildable.loc) cctx)))
        with
        | None ->
          (* This happens often when passing a [-p ...] option that
             hides a library *)
          let targets =
            List.map (Menhir_rules.targets m)
              ~f:(Path.relative (Path.build ctx_dir))
          in
          SC.add_rule sctx ~dir:(Path.build ctx_dir)
            (Build.fail ~targets
               { fail = fun () ->
                   Errors.fail m.loc
                     "I can't determine what library/executable the files \
                      produced by this stanza are part of."
               })
        | Some cctx ->
          Menhir_rules.gen_rules cctx m ~build_dir ~dir:ctx_dir
        end
      | Coq.T m when Expander.eval_blang expander m.enabled_if ->
        Coq_rules.setup_rules ~sctx ~dir:ctx_dir ~dir_contents m
        |> SC.add_rules ~dir:(Path.build ctx_dir) sctx
      | Coqpp.T m ->
        Coq_rules.coqpp_rules ~sctx ~build_dir ~dir:ctx_dir m
        |> SC.add_rules ~dir:(Path.build ctx_dir) sctx
      | _ -> ());
    let dyn_deps =
      let pred =
        let id = lazy (
          let open Sexp.Encoder in
          constr "exclude" (List.map ~f:Path.Build.to_sexp js_targets)
        ) in
        List.iter js_targets ~f:(fun js_target ->
          assert (Path.Build.equal (Path.Build.parent_exn js_target)
                    ctx_dir));
        Predicate.create ~id ~f:(fun basename ->
          not (List.exists js_targets ~f:(fun js_target ->
            String.equal (Path.Build.basename js_target) basename)))
      in
      File_selector.create ~dir:(Path.build ctx_dir) pred
      |> Build.paths_matching ~loc:Loc.none
    in
    Rules.Produce.Alias.add_deps
      ~dyn_deps
      (Alias.all ~dir:(Path.build ctx_dir)) Path.Set.empty;
    cctxs

  let gen_rules dir_contents cctxs ~dir : (Loc.t * Compilation_context.t) list =
    with_format sctx ~dir ~f:(fun _ -> Format_rules.gen_rules ~dir);
    match SC.stanzas_in sctx ~dir:(Path.as_in_build_dir_exn dir) with
    | None -> []
    | Some d -> gen_rules dir_contents cctxs d

  let gen_rules ~dir components : Build_system.extra_sub_directories_to_keep =
    (let dir = Path.as_in_build_dir_exn dir in
     Install_rules.init_meta sctx ~dir;
     Install_rules.gen_rules sctx ~dir;
     Opam_create.add_rules sctx ~dir);
    (match components with
     | ".js"  :: rest -> Js_of_ocaml_rules.setup_separate_compilation_rules
                           sctx rest
     | "_doc" :: rest -> Odoc.gen_rules sctx rest ~dir
     | ".ppx"  :: rest -> Preprocessing.gen_rules sctx rest
     | comps ->
       begin match List.last comps with
       | Some ".formatted" -> gen_format_rules sctx ~output_dir:dir
       | Some ".bin" ->
         let src_dir = Path.parent_exn dir in
         Super_context.local_binaries sctx
           ~dir:(Path.as_in_build_dir_exn src_dir)
         |> List.iter ~f:(fun t ->
           let loc = File_binding.Expanded.src_loc t in
           let src = File_binding.Expanded.src_path t in
           let dst =
             let dir = Path.as_in_build_dir dir |> Option.value_exn in
             File_binding.Expanded.dst_path t ~dir
             |> Path.build
           in
           Super_context.add_rule sctx ~loc ~dir (Build.symlink ~src ~dst))
       | _ ->
         match
           File_tree.find_dir (SC.file_tree sctx)
             (Path.drop_build_context_exn dir)
         with
         | None ->
           (* We get here when [dir] is a generated directory, such as
              [.utop] or [.foo.objs]. *)
           if Utop.is_utop_dir dir then
             Utop.setup sctx ~dir:(Path.parent_exn dir)
           else if components <> [] then
             Build_system.load_dir ~dir:(Path.parent_exn dir)
         | Some _ ->
           (* This interprets "rule" and "copy_files" stanzas. *)
           let dir_contents =
             Dir_contents.get sctx ~dir:(Path.as_in_build_dir_exn dir)
           in
           match dir_contents with
           | Group_part root ->
             Build_system.load_dir ~dir:(Path.build root)
           | Standalone_or_root dir_contents ->
             match Dir_contents.kind dir_contents with
             | Group_part _ -> assert false
             | Standalone ->
               ignore (gen_rules dir_contents [] ~dir : _ list)
             | Group_root subs ->
               let cctxs = gen_rules dir_contents [] ~dir in
               let subs = Memo.Lazy.force subs in
               List.iter subs ~f:(fun dc ->
                 ignore (
                   gen_rules dir_contents cctxs
                     ~dir:(Path.build (Dir_contents.dir dc))
                   : _ list))
       end);
    match components with
    | [] -> These (String.Set.of_list [".js"; "_doc"; ".ppx"])
    | [(".js"|"_doc"|".ppx")] -> All
    | _  -> These String.Set.empty

end

module type Gen = sig
  val gen_rules
    :  dir:Path.t
    -> string list
    -> Build_system.extra_sub_directories_to_keep
  val sctx : Super_context.t
end

let turn_library_into_external_variant visible_libraries lib =
  match lib with
  | { Library.variant=(Some variant)
    ; implements=(Some (loc, vlib))
    ; project
    ; _} as conf ->
    Option.some_if
      (Lib_name.Set.mem visible_libraries vlib)
      (External_variant
         { implementation = (Library.best_name conf)
         ; virtual_lib = vlib
         ; variant
         ; project
         ; loc
         })
  | _ -> None

let map_stanza visible_libraries = function
  | Library lib -> turn_library_into_external_variant visible_libraries lib
  | _ -> None

let filter_out_stanzas_from_hidden_packages visible_libraries pkgs stanzas =
  List.filter_map stanzas ~f:(fun stanza ->
    match Dune_file.stanza_package stanza with
    | Some package when Package.Name.Set.mem pkgs package.name -> Some stanza
    | None -> Some stanza
    | Some _ -> map_stanza visible_libraries stanza
  )

let visible_libraries pkgs stanzas =
  stanzas
  |> List.filter_map
       ~f:(function
         | Library
             ({ public = Some { package; _ }
              ; _
              } as conf)
           when (Package.Name.Set.mem pkgs package.name) ->
           Some (Library.best_name conf)
         | _ -> None)
  |> Lib_name.Set.of_list

let gen ~contexts
      ?(external_lib_deps_mode=false)
      ?only_packages conf =
  let open Fiber.O in
  let { Dune_load. file_tree; dune_files; packages; projects } = conf in
  let packages =
    match only_packages with
    | None -> packages
    | Some pkgs ->
      Package.Name.Map.filter packages ~f:(fun { Package.name; _ } ->
        Package.Name.Set.mem pkgs name)
  in
  let sctxs = Hashtbl.create 4 in
  List.iter contexts ~f:(fun c ->
    Hashtbl.add sctxs c.Context.name (Fiber.Ivar.create ()));
  let make_sctx (context : Context.t) : _ Fiber.t =
    let host () =
      match context.for_host with
      | None -> Fiber.return None
      | Some h ->
        Fiber.Ivar.read (Hashtbl.find_exn sctxs h.name)
        >>| Option.some
    in

    let stanzas () =
      let+ stanzas = Dune_load.Dune_files.eval ~context dune_files in
      match only_packages with
      | None -> stanzas
      | Some pkgs ->
        let visible_libraries =
          stanzas
          |> Dune_load.Dune_file.fold_stanzas ~init:[] ~f:(fun _ s acc -> s::acc)
          |> visible_libraries pkgs
        in
        List.map stanzas ~f:(fun (dir_conf : Dune_load.Dune_file.t) ->
          { dir_conf with
            stanzas = filter_out_stanzas_from_hidden_packages visible_libraries pkgs dir_conf.stanzas
          })
    in
    let* (host, stanzas) = Fiber.fork_and_join host stanzas in
    let sctx =
      Super_context.create
        ?host
        ~context
        ~projects
        ~file_tree
        ~packages
        ~external_lib_deps_mode
        ~stanzas
    in
    let module P = struct let sctx = sctx end in
    let module M = Gen(P) in
    let+ () =
      Fiber.Ivar.fill (Hashtbl.find_exn sctxs context.name) sctx in
    (context.name, (module M : Gen))
  in
  let+ contexts = Fiber.parallel_map contexts ~f:make_sctx in
  let map = String.Map.of_list_exn contexts in
  let sctxs = String.Map.map map ~f:(fun (module M : Gen) -> M.sctx) in
  let generators = (String.Map.map map ~f:(fun (module M : Gen) -> M.gen_rules)) in
  let () =
    Build_system.set_packages (fun path ->
      let open Option.O in
      Option.value ~default:Package.Name.Set.empty (
        let* ctx_name, _ = Path.extract_build_context path in
        let* sctx = String.Map.find sctxs ctx_name in
        Path.Map.find (Install_rules.packages sctx) path))
  in
  Build_system.set_rule_generators
    ~init:(fun () ->
      String.Map.iter map ~f:(fun (module M : Gen) ->
        Odoc.init M.sctx))
    ~gen_rules:
      (function
        | Install ctx ->
          Option.map (String.Map.find sctxs ctx) ~f:(fun sctx ->
            (fun ~dir _ ->
               Install_rules.gen_rules sctx ~dir:(Path.as_in_build_dir_exn dir);
               Build_system.These String.Set.empty))
        | Context ctx ->
          String.Map.find generators ctx);
  sctxs
