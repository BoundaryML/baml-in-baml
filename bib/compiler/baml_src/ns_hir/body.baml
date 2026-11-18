// port: baml_compiler2_hir/src/body.rs @ d9be6853b
//
// Per-function and per-let body queries. They read the `ItemTree` (full AST
// data); the semantic body (no spans) and the source map (spans) are separate
// queries.

// port: baml_compiler2_hir/src/body.rs::FunctionBody @ d9be6853b
// Semantic function body: an expression body, a builtin, or missing. No
// spans; those live in the `root.ast.AstSourceMap` of
// `function_body_source_map`.
type FunctionBody = FunctionBodyExpr | FunctionBodyBuiltin | FunctionBodyMissing;

// Expression body (semantic arena, no spans).
class FunctionBodyExpr {
    value: root.ast.ExprBody,
}

// Rust-bound builtin implementation (`$rust_function` or `$rust_io_function`).
class FunctionBodyBuiltin {
    value: root.ast.BuiltinKind,
}

// Body was omitted or could not be parsed.
class FunctionBodyMissing {
}

// port: baml_compiler2_hir/src/body.rs::FunctionBody::has_final_expr @ d9be6853b
// Whether the body ends in a final expression, the value it evaluates to. A
// body that ends in a statement has none, and neither has a function with no
// expression body at all.
function function_body_has_final_expr(body: FunctionBody) -> bool throws never {
    match (body) {
        let b: FunctionBodyExpr => {
            let root_expr = b.value.root_expr
                ?? return false;
            match (b.value.exprs[root_expr]) {
                let block: root.ast.ExprBlock => block.tail_expr != null,
                _ => false,
            }
        },
        FunctionBodyBuiltin | FunctionBodyMissing => false,
    }
}

// port: baml_compiler2_hir/src/body.rs::function_body @ d9be6853b
// Salsa query: semantic function body (no source map).
function function_body(db: Db, function_: int) -> FunctionBody throws never {
    db.memo.function_body.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        let item_tree = file_item_tree(db, loc.file);
        let func_data = item_tree.functions[loc.id];

        match (func_data.body) {
            let def: root.ast.FunctionBodyDefExpr => FunctionBodyExpr { value: def.v0 },
            let def: root.ast.FunctionBodyDefBuiltin => FunctionBodyBuiltin { value: def.value },
            null => FunctionBodyMissing {},
        }
    })
}

// port: baml_compiler2_hir/src/body.rs::function_body_source_map @ d9be6853b
// Salsa query: function body source map (spans only).
function function_body_source_map(db: Db, function_: int) -> root.ast.AstSourceMap? throws never {
    db.memo.function_body_source_map.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        let item_tree = file_item_tree(db, loc.file);
        let func_data = item_tree.functions[loc.id];

        match (func_data.body) {
            let def: root.ast.FunctionBodyDefExpr => def.v1,
            _ => null,
        }
    })
}

// port: baml_compiler2_hir/src/body.rs::LetBody @ d9be6853b
// Semantic let-binding body: the initializer expression, or missing.
type LetBody = LetBodyExpr | LetBodyMissing;

// Expression initializer (semantic arena, no spans).
class LetBodyExpr {
    value: root.ast.ExprBody,
}

// Initializer was omitted or could not be parsed.
class LetBodyMissing {
}

// port: baml_compiler2_hir/src/body.rs::let_body @ d9be6853b
// Salsa query: semantic let-binding body (no source map).
function let_body(db: Db, let_binding: int) -> LetBody throws never {
    db.memo.let_body.get(let_binding, () -> {
        let loc = db.let_locs.get(let_binding);
        let item_tree = file_item_tree(db, loc.file);
        let let_data = item_tree.lets[loc.id];

        match (let_data.initializer) {
            let initializer: (root.ast.ExprBody, root.ast.AstSourceMap) => {
                LetBodyExpr { value: initializer.0 }
            },
            null => LetBodyMissing {},
        }
    })
}

// port: baml_compiler2_hir/src/body.rs::let_body_source_map @ d9be6853b
// Salsa query: let-binding body source map (spans only).
function let_body_source_map(db: Db, let_binding: int) -> root.ast.AstSourceMap? throws never {
    db.memo.let_body_source_map.get(let_binding, () -> {
        let loc = db.let_locs.get(let_binding);
        let item_tree = file_item_tree(db, loc.file);
        item_tree.lets[loc.id].initializer?.1
    })
}

// port: baml_compiler2_hir/src/body.rs::BodyOwnerId @ d9be6853b
// A definition that owns an expression body: the key of the body queries and
// of inference (rust-analyzer's `DefWithBodyId`). Lambdas are not members: a
// lambda's body lives in its owner's arena.
// deviation: the `From<FunctionLoc>` / `From<LetLoc>` impls are not ported:
// write `BodyOwnerIdFunction { value: f }` / `BodyOwnerIdLet { value: l }`.
type BodyOwnerId = BodyOwnerIdFunction | BodyOwnerIdLet | BodyOwnerIdParameterDefaults;

// A function loc.
class BodyOwnerIdFunction {
    value: int,
}

// A let loc.
class BodyOwnerIdLet {
    value: int,
}

// A function's parameter-default expressions: one owner per function, since
// all its defaults share one arena (`FunctionDefaults.exprs`).
class BodyOwnerIdParameterDefaults {
    value: int,
}

// port: baml_compiler2_hir/src/body.rs::BodyOwnerId::file @ d9be6853b
function body_owner_id_file(db: Db, owner: BodyOwnerId) -> int throws never {
    match (owner) {
        let o: BodyOwnerIdFunction => db.function_locs.get(o.value).file,
        let o: BodyOwnerIdLet => db.let_locs.get(o.value).file,
        let o: BodyOwnerIdParameterDefaults => db.function_locs.get(o.value).file,
    }
}

// port: baml_compiler2_hir/src/body.rs::OwnerBody @ d9be6853b
// A body owner's body: the per-kind query result.
type OwnerBody = OwnerBodyFunction | OwnerBodyLet | OwnerBodyParameterDefaults;

class OwnerBodyFunction {
    value: FunctionBody,
}

class OwnerBodyLet {
    value: LetBody,
}

class OwnerBodyParameterDefaults {
    value: FunctionParameterDefaults,
}

// port: baml_compiler2_hir/src/body.rs::OwnerBody::expr_body @ d9be6853b
// The expression body, if the owner has one (null for builtin and missing
// bodies).
function owner_body_expr_body(owner_body: OwnerBody) -> root.ast.ExprBody? throws never {
    match (owner_body) {
        let o: OwnerBodyFunction => match (o.value) {
            let b: FunctionBodyExpr => b.value,
            FunctionBodyBuiltin | FunctionBodyMissing => null,
        },
        let o: OwnerBodyLet => match (o.value) {
            let b: LetBodyExpr => b.value,
            LetBodyMissing => null,
        },
        let o: OwnerBodyParameterDefaults => o.value.defaults.exprs,
    }
}

// port: baml_compiler2_hir/src/body.rs::body @ d9be6853b
// The body of any body owner (rust-analyzer's `DefWithBodyId` pattern).
function body(db: Db, owner: BodyOwnerId) -> OwnerBody throws never {
    match (owner) {
        let o: BodyOwnerIdFunction => OwnerBodyFunction { value: function_body(db, o.value) },
        let o: BodyOwnerIdLet => OwnerBodyLet { value: let_body(db, o.value) },
        let o: BodyOwnerIdParameterDefaults => {
            OwnerBodyParameterDefaults { value: function_parameter_defaults(db, o.value) }
        },
    }
}

// port: baml_compiler2_hir/src/body.rs::body_source_map @ d9be6853b
// The body source map of any body owner (spans only).
function body_source_map(db: Db, owner: BodyOwnerId) -> root.ast.AstSourceMap? throws never {
    match (owner) {
        let o: BodyOwnerIdFunction => function_body_source_map(db, o.value),
        let o: BodyOwnerIdLet => let_body_source_map(db, o.value),
        let o: BodyOwnerIdParameterDefaults => {
            function_parameter_defaults(db, o.value).defaults.source_map
        },
    }
}

// port: baml_compiler2_hir/src/body.rs::body_scope @ d9be6853b
// The scope opened for a body owner's body.
function body_scope(db: Db, owner: BodyOwnerId) -> int? throws never {
    match (owner) {
        let o: BodyOwnerIdFunction => function_scope(db, o.value),
        let o: BodyOwnerIdLet => let_scope(db, o.value),
        // Defaults are keyed under the FUNCTION's scope (the semantic index
        // walks them there, `ExprMetadataScope::ParameterDefault`).
        let o: BodyOwnerIdParameterDefaults => function_scope(db, o.value),
    }
}

// port: baml_compiler2_hir/src/body.rs::file_body_owners @ d9be6853b
// Every body owner in `file`: functions (methods included), then top-level
// lets, each group in source order.
function file_body_owners(db: Db, file: int) -> BodyOwnerId[] throws never {
    let functions: BodyOwnerId[] = file_functions(db, file).map((f) -> {
        BodyOwnerIdFunction { value: f }
    });
    let lets: BodyOwnerId[] = file_lets(db, file).map((l) -> {
        BodyOwnerIdLet { value: l }
    });
    functions.concat(lets)
}
