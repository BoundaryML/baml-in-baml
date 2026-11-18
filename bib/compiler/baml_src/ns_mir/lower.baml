// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// HIR/TIR to MIR lowering. This file holds unit 0 of the MIR plan: the
// lowering's small types (`SwitchKind`, `SwitchOtherwise`, `LoopContext`,
// `ArmedDefer`), the package-shared data (`PackageLoweringData`,
// `package_lowering_data`), `SyntheticOrdinals`, the `LoweringContext`
// struct and its constructors. The rest of lower.rs is stubbed by unit in
// `mir_stubs_u<N>.baml`.
//
// Restructured (BAML forces it):
// - `LoweringContext`'s methods are free functions taking `ctx:
//   LoweringContext` first; its constructors `new` / `new_for_let` are
//   static functions of the class.
// - `Lowered<T>` (`Result<T, MirInternalError>`) is `T throws
//   MirInternalError`: `?` is plain propagation, and the entry points
//   (`lower_function`, `lower_let_body`) catch it into their memo value.
//   The `*_stubs_*` files throw it (with a "not ported" message) from a
//   stub that declares it, since a stub that only panics would warn that
//   its `throws` is extraneous (E0097).
// - The `'db` borrows of package data (`resolved_aliases`,
//   `interface_method_names`) are shared references to the memoized
//   `PackageLoweringData`; never mutate them.
// - `HashMap` / `FxHashMap` keyed by an id are `map<int, ..>`, keyed by a
//   `BindingId` or `ParamTy` are maps keyed by that class; `FxHashSet<T>`
//   is `map<T, bool>`. `tested_pattern_values` (keyed by `PatMetadataKey`, a
//   `(scope, pattern)` tuple) is `map<ExprMetadataScope, map<int, int>>`.
// - Rust swaps whole fields with `mem::take` / `mem::replace` /
//   `Option::take` around lambda bodies and nested matches (`builder`,
//   `binding_locals`, `defer_stack`, `pending_lambdas`, `capture_indices`,
//   `loop_context`, `match_scrutinee`, ...). Arrays and maps are shared by
//   reference here: save the old object in a local, assign a fresh `[]` /
//   `{}` / `null`, and assign the saved one back, never clearing it in place.

// port: baml_compiler2_mir/src/lower.rs::SwitchKind @ d9be6853b
// Classifies what kind of switch a match/catch expression lowers to.
// `TypeTag` dispatches class-type and primitive-type arms via runtime type
// tags, using `RvalueTypeTag` for the switch operand.
type SwitchKind = SwitchKindInteger | SwitchKindEnumDiscriminant | SwitchKindTypeTag;

class SwitchKindInteger {
}

class SwitchKindEnumDiscriminant {
    value: root.types.DeclName,
}

class SwitchKindTypeTag {
}

// port: baml_compiler2_mir/src/lower.rs::SwitchOtherwise @ d9be6853b
// What happens in the otherwise block of a switch.
type SwitchOtherwise = SwitchOtherwiseMatch | SwitchOtherwiseCatch;

// Match expression: goto join (non-exhaustive) or unreachable (exhaustive).
class SwitchOtherwiseMatch {
    is_exhaustive: bool,
}

// Catch expression: rethrow unmatched errors with their landing's context.
// If `wildcard_skips_panics`, a panic passes over the wildcard body (see
// `emit_catch_wildcard_entry`).
class SwitchOtherwiseCatch {
    error_local: int,
    context_local: int,
    wildcard_skips_panics: bool,
}

// port: baml_compiler2_mir/src/lower.rs::LoopContext @ d9be6853b
class LoopContext {
    break_target: int,
    continue_target: int,
    // Depth of `defer_stack` at loop entry. `break`/`continue` replay the
    // defers declared inside the loop body so far (down to this depth)
    // before jumping.
    defer_depth: int,
}

// port: baml_compiler2_mir/src/lower.rs::ArmedDefer @ d9be6853b
// A `defer` body armed in the scope being lowered, with the handler in force
// where it was armed. Every copy of the body (the inline replays at the
// non-throwing exits and the landing pad) unwinds to that handler: the pad of
// the defer armed before it, or the enclosing `catch`; never to its own pad,
// and never to the pad of a defer armed after it.
class ArmedDefer {
    // The body, an inline `ExprBlock` (an expression id).
    body: int,
    // `MirBuilder.current_unwind` at arming.
    unwind: int?,
}

// port: baml_compiler2_mir/src/lower.rs::PackageLoweringData @ d9be6853b
// All package-invariant data needed to construct a `LoweringContext`: the
// resolved type-alias environment and the interface-method pre-filter,
// computed once per package by `package_lowering_data`. Class and enum
// layout is not here: it is a property of the declaration, read by identity
// through `root.hir_ty` layout wherever a slot is needed.
class PackageLoweringData {
    resolved_aliases: root.types.ResolvedAliases,
    // Every method name any in-scope interface (own package + dependency
    // closure) declares, required or default. Fast pre-filter for
    // `dispatch_target_for_concrete`: a member name absent here can never
    // dispatch through an interface impl.
    interface_method_names: map<string, bool>,
}

// port: baml_compiler2_mir/src/lower.rs::package_lowering_data @ d9be6853b
// Build the package-invariant `PackageLoweringData` once per package,
// memoized and shared across every function's `LoweringContext`.
//
// Names are collected package-wide (not per receiver type), so the filter
// stays a pure fast path: any name declared by any reachable interface still
// falls through to the full impl enumeration.
function package_lowering_data(db: root.hir.Db, pkg_id: int) -> PackageLoweringData throws never {
    db.mir_memo.package_lowering_data.get(db.cycles, pkg_id, () -> {
        let resolved_aliases = resolved_aliases_for_package(db, pkg_id).value;
        // Renamed local (`interface_method_names` in Rust): it would shadow
        // the function of that name.
        let method_names: map<string, bool> = {};
        let all_pkgs = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
        for (let pkg in all_pkgs) {
            for (let interface_ in package_interfaces(db, pkg)) {
                for (let name in interface_method_names(db, interface_)) {
                    method_names[name] = true;
                }
            }
        }
        PackageLoweringData {
            resolved_aliases: resolved_aliases,
            interface_method_names: method_names,
        }
    })
}

// port: baml_compiler2_mir/src/lower.rs::PatMetadataKey @ d9be6853b
// A pattern's identity in a file: its arena's metadata scope and its id.
// Not hashable as a tuple: maps keyed by it nest (`tested_pattern_values`).
type PatMetadataKey = (root.hir.ExprMetadataScope, int);

// port: baml_compiler2_mir/src/lower.rs::SyntheticOrdinals @ d9be6853b
// Ordinals of the synthetic functions lowered under one top-level body, per
// `SyntheticKind`: the `i` in `<lambda(owner, i)>`. Counted across the whole
// body (a lambda nested in a lambda takes the next ordinal, not a fresh
// count), so every synthetic function of a body has a distinct identity.
// Rust's `Default` is `SyntheticOrdinals { lambda: 0, tagged: 0 }`.
class SyntheticOrdinals {
    lambda: int,
    tagged: int,

    // port: baml_compiler2_mir/src/lower.rs::SyntheticOrdinals::next @ d9be6853b
    // Claim the next ordinal for a synthetic function of `kind`.
    function next(self, kind: SyntheticKind) -> int throws never {
        match (kind) {
            SyntheticKind.Lambda => {
                let ordinal = self.lambda;
                self.lambda += 1;
                ordinal
            },
            SyntheticKind.Tagged => {
                let ordinal = self.tagged;
                self.tagged += 1;
                ordinal
            },
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext @ d9be6853b
// The state of lowering one top-level body (a function or a `let`
// initializer), lambdas within it included.
class LoweringContext {
    db: root.hir.Db,
    builder: MirBuilder,
    // The local holding each HIR binding the body being lowered declares.
    // Written only by `declare_binding`, `declare_parameter`, and
    // `bind_existing_local`; `verify_bindings_recorded` checks at build time
    // that no binding was left out.
    binding_locals: map<root.hir.BindingId, int>,
    // The `self` parameter of the method being lowered, for
    // `default.<member>` roots, which HIR does not resolve.
    self_binding: root.hir.BindingId?,
    loop_context: LoopContext?,
    // The locals of the handler arms being lowered that hold a caught error,
    // each with its landing's context local: `throw` of one is a rethrow
    // that carries that context. A lambda body starts with none.
    catch_rethrow_locals: (int, int)[],
    exit_block: int,
    // The inference tables: `hir_ty`'s results for this body and, for a
    // function, its parameter defaults.
    tables: InferenceTables,
    // Function generic bounds, lowered in TIR space: one entry per parameter
    // holding its full `extends A & B` conjunction, searched in declaration
    // order by dispatch.
    generic_param_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    // TIR types of the in-scope lambda parameters, by name. TIR does not
    // record `path_segment_types` for a lambda-parameter receiver, so
    // interface dispatch on one falls back to this map. Saved and restored
    // across nested lambdas.
    lambda_param_tir_types: map<string, root.types.Ty>,
    // The value the enclosing `match` is scrutinizing, set for the duration
    // of its arm lowering (saved and restored across nested matches). Null
    // outside a match.
    match_scrutinee: MatchScrutinee?,
    // Stable values read while testing patterns, keyed by pattern identity
    // (`PatMetadataKey`, nested). Binding lowering reuses these exact values
    // instead of rereading mutable captured cells or object fields after a
    // successful test.
    tested_pattern_values: map<root.hir.ExprMetadataScope, map<int, int>>,
    atomic_pattern_test: bool,
    // The `FileScopeId` of the expression body currently being lowered,
    // updated when descending into lambda bodies.
    current_scope: int,
    // Metadata namespace for the expression arena currently being lowered.
    current_metadata_scope: root.hir.ExprMetadataScope,
    // Which of the owner's arenas that is: the one whose inference result
    // types the expressions being lowered, lambdas within it included.
    inference_root: InferenceRoot,
    // AST expression body and source map.
    body: root.ast.ExprBody,
    source_map: root.ast.AstSourceMap?,
    file: int,
    func_loc: int?,
    source_param_scope: int?,
    // Raw function name from the item tree (e.g. `"Foo@render_prompt"`),
    // used to disambiguate companion scopes that share the same span.
    scope_func_name: string?,
    // The package's alias environment, shared with every function of the
    // package (`package_lowering_data`).
    resolved_aliases: root.types.ResolvedAliases,
    // All method names declared by in-scope interfaces; see
    // `PackageLoweringData.interface_method_names`.
    interface_method_names: map<string, bool>,
    // Stack of armed `defer` bodies, parallel to lexical scopes. Pushed by
    // `lower_scoped_block` as each `defer` statement is reached; replayed
    // (LIFO, re-lowered inline) at every non-throwing scope exit by
    // `replay_defers_to_depth`. Swapped at lambda boundaries so a lambda body
    // never replays the parent's defers.
    defer_stack: ArmedDefer[],
    // Ordinals of the synthetic functions lowered so far under the top-level
    // body.
    synthetic_ordinals: SyntheticOrdinals,
    // Lambda functions lowered during body traversal, moved into
    // `MirFunction.lambdas` at the end of lowering.
    pending_lambdas: MirFunction[],
    // Generic params of the enclosing lambda(s), outermost first. Empty at
    // top level; `lower_lambda` extends it with the lambda's own generic
    // params while lowering its body and restores it afterwards.
    lambda_generic_params: root.types.ParamTy[],
    // The lexical `let type T = ...` parameters currently visible, innermost
    // last. Pushed at the binding statement and truncated at the closing
    // brace.
    scoped_type_binding_params: root.types.ParamTy[],
    // Capture map for the current lambda body (null for top-level
    // functions): captured binding identity to its index in the closure's
    // captures array.
    capture_indices: map<root.hir.BindingId, int>?,
    // Bindings added to the current lambda's capture list transitively,
    // because an inner lambda needed them but HIR did not list them for this
    // lambda. The parent `lower_lambda` extends its `MakeClosure` with them.
    transitive_captures_needed: root.hir.BindingId[],
    // The tagged-template body-lambda parameters currently in scope, mapped
    // to the synthetic `BindingId.parameter` that `build_tagged_body_closure`
    // assigns each. Saved and restored around each closure body.
    tagged_body_param_bindings: map<string, root.hir.BindingId>,
    // Stack of null-exit blocks for active `OptionalChain` scopes: an
    // optional access that meets null jumps to the top of this stack.
    chain_null_exits: int[],
    // Optimization level controlling MIR-level transforms.
    opt: OptLevel,

    // port: baml_compiler2_mir/src/lower.rs::LoweringContext::new @ d9be6853b
    // A lowering context for a function body.
    function new(
        db: root.hir.Db,
        func_loc: int,
        expr_body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap?,
        opt: OptLevel,
    ) -> LoweringContext throws never {
        let file = db.function_locs.get(func_loc).file;
        let func_data = root.hir.function_data(db, func_loc);
        // The scope this function opened, from the recorded item-to-scope
        // index: exact, so companion and synthesized functions resolve.
        let func_scope = root.hir.function_scope(db, func_loc)
            ?? baml.sys.panic("every item-tree function has a recorded scope");
        let func_scope_id = db.scopes.get(func_scope).id;

        // Inference: the body's and parameter defaults' results.
        let tables = InferenceTables.for_function(db, func_loc);
        let body = with_bare_global_paths(expr_body, tables.of(InferenceRoot.Body));

        // The package's alias environment and interface pre-filter.
        let pkg_id = root.hir.file_package(db, file).root_id;
        // The per-param bound conjunctions (the dispatch view), from hir_ty's
        // `function_generic_bounds`: `T extends A & B` keeps both conjuncts.
        let generic_param_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
        let declared_bounds = root.hir_ty.function_generic_bounds(db, func_loc);
        for (let param in declared_bounds.keys()) {
            generic_param_bounds[param]
                = declared_bounds[param].filter_map((bound: root.types.InterfaceConstraint) -> root.types.InterfaceConstraint? {
                    root.types.as_interface(plain_interface_ty(bound))
                });
        }
        let pkg_data = package_lowering_data(db, pkg_id);

        // Arity from the function signature.
        let arity = root.hir.function_signature(db, func_loc).params.length();

        LoweringContext {
            db: db,
            builder: MirBuilder.new(FunctionOwnerFunction { value: func_loc }, arity),
            binding_locals: {},
            self_binding: null,
            loop_context: null,
            catch_rethrow_locals: [],
            // A placeholder; `lower_function_body` overwrites it.
            exit_block: 0,
            tables: tables,
            generic_param_bounds: generic_param_bounds,
            lambda_param_tir_types: {},
            match_scrutinee: null,
            tested_pattern_values: {},
            atomic_pattern_test: false,
            current_scope: func_scope_id,
            current_metadata_scope: root.hir.ExprMetadataScopeBody { value: func_scope_id },
            inference_root: InferenceRoot.Body,
            body: body,
            source_map: source_map,
            file: file,
            func_loc: func_loc,
            source_param_scope: func_scope_id,
            scope_func_name: func_data.name,
            resolved_aliases: pkg_data.resolved_aliases,
            interface_method_names: pkg_data.interface_method_names,
            defer_stack: [],
            synthetic_ordinals: SyntheticOrdinals { lambda: 0, tagged: 0 },
            pending_lambdas: [],
            lambda_generic_params: [],
            scoped_type_binding_params: [],
            capture_indices: null,
            transitive_captures_needed: [],
            tagged_body_param_bindings: {},
            chain_null_exits: [],
            opt: opt,
        }
    }

    // port: baml_compiler2_mir/src/lower.rs::LoweringContext::new_for_let @ d9be6853b
    // A lowering context for a top-level let binding: no parameters (arity
    // 0) and no `func_loc`; types come from the let's scope.
    function new_for_let(
        db: root.hir.Db,
        let_loc: int,
        expr_body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap?,
        opt: OptLevel,
    ) -> LoweringContext throws never {
        let file = db.let_locs.get(let_loc).file;
        let let_name = root.hir.let_data(db, let_loc).name;
        let let_scope = root.hir.let_scope(db, let_loc)
            ?? baml.sys.panic("every item-tree let has a recorded scope");
        let let_scope_id = db.scopes.get(let_scope).id;

        // Inference: the initializer's results.
        let tables = InferenceTables.for_let(db, let_loc);
        let body = with_bare_global_paths(expr_body, tables.of(InferenceRoot.Body));

        // The package's alias environment and interface pre-filter.
        let pkg_id = root.hir.file_package(db, file).root_id;
        let pkg_data = package_lowering_data(db, pkg_id);

        LoweringContext {
            db: db,
            builder: MirBuilder.new(FunctionOwnerLet { value: let_loc }, 0),
            binding_locals: {},
            self_binding: null,
            loop_context: null,
            catch_rethrow_locals: [],
            // A placeholder; `lower_let_body_inner` overwrites it.
            exit_block: 0,
            tables: tables,
            generic_param_bounds: {},
            lambda_param_tir_types: {},
            match_scrutinee: null,
            tested_pattern_values: {},
            atomic_pattern_test: false,
            current_scope: let_scope_id,
            current_metadata_scope: root.hir.ExprMetadataScopeBody { value: let_scope_id },
            inference_root: InferenceRoot.Body,
            body: body,
            source_map: source_map,
            file: file,
            func_loc: null,
            source_param_scope: null,
            scope_func_name: let_name,
            resolved_aliases: pkg_data.resolved_aliases,
            interface_method_names: pkg_data.interface_method_names,
            defer_stack: [],
            synthetic_ordinals: SyntheticOrdinals { lambda: 0, tagged: 0 },
            pending_lambdas: [],
            lambda_generic_params: [],
            scoped_type_binding_params: [],
            capture_indices: null,
            transitive_captures_needed: [],
            tagged_body_param_bindings: {},
            chain_null_exits: [],
            opt: opt,
        }
    }
}
