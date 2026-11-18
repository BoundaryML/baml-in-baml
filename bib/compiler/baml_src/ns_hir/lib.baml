// port: baml_compiler2_hir/src/lib.rs @ d9be6853b
//
// The HIR's top-level queries: the files of a compile, a file's AST, its
// semantic index, and the projections read off that index. The `Db` trait is
// in `db.baml`.

// port: baml_compiler2_hir/src/lib.rs::compiler2_all_files @ d9be6853b
// Every file visible to compiler2 queries, in source-root table order:
// `Stdlib` roots first and `Dynamic` roots last, so whatever whole-program
// iteration assigns downstream gives the stdlib a stable prefix of every
// index space. Whole-program consumers only; package-scoped readers use the
// root's own `files`.
function compiler2_all_files(db: Db) -> int[] throws never {
    db.root_order.flat_map((root_id) -> {
        db.source_root(root_id).files
    })
}

// port: baml_compiler2_hir/src/lib.rs::FileAst @ d9be6853b
// The syntax-tree to AST lowering output for one file: top-level items plus
// the lowering diagnostics and `env.*` references produced along the way.
class FileAst {
    items: root.ast.Item[],
    diagnostics: root.ast.LoweringDiagnostic[],
    env_var_refs: root.ast.EnvVarRef[],
}

// port: baml_compiler2_hir/src/lib.rs::file_ast @ d9be6853b
// Syntax-tree to AST lowering for one file, computed once and shared by every
// consumer of a file's AST items.
function file_ast(db: Db, file: int) -> FileAst throws never {
    db.memo.file_ast.get(file, () -> {
        let tree = typed_tree(db, file);
        // Root-relative: the path names the file's `$init_test_...` function,
        // which is part of the package's unit and must not carry the checkout's
        // location.
        let path = root_relative_path(db, file);
        let package = file_package(db, file);
        let test_owner = if (package.namespace_path.length() == 0) {
            "root"
        } else {
            `root.${package.namespace_path.join(".")}`
        };
        let surface = if (is_session_submission(db, file)) {
            root.ast.TopLevelLetSurface.Session
        } else {
            root.ast.TopLevelLetSurface.Source
        };
        let (let items, let diagnostics, let env_var_refs) = root.ast.lower_file(tree, path, test_owner, surface = surface);
        if (db.source_root(package.root_id).exclude_tests) {
            // Both test forms lower into per-file registrars. Remove them before
            // building HIR so their entire subtree (including nested/catch
            // lambdas) is absent from code, constants, and package interfaces.
            items
                = items.filter((item) -> {
                    !is_test_initializer(item)
                });
        }
        FileAst { items: items, diagnostics: diagnostics, env_var_refs: env_var_refs }
    })
}

// port: the `matches!` in lib.rs::file_ast's `retain`. A file's test
// registrar.
function is_test_initializer(item: root.ast.Item) -> bool throws never {
    match (item) {
        let f: root.ast.ItemFunction => {
            f.value.metadata.origin == root.ast.FunctionOrigin.TestInitializer
        },
        _ => false,
    }
}

// port: baml_compiler2_hir/src/lib.rs::file_semantic_index @ d9be6853b
// The coarse per-file query: the file's scope tree, item tree, bindings and
// contributions, built from its AST.
function file_semantic_index(db: Db, file: int) -> FileSemanticIndex throws never {
    db.memo.file_semantic_index.get(file, () -> {
        let file_range = root.syntax.TextRange { start: 0, end: db.file(file).text.byte_length() };
        // Syntax-tree to AST lowering is shared via `file_ast` instead of being
        // redone here.
        let ast = file_ast(db, file);
        SemanticIndexBuilder.new(db, file)
            .with_lowering_diagnostics(ast.diagnostics)
            .with_env_var_refs(ast.env_var_refs)
            .build(ast.items, file_range)
    })
}

// port: baml_compiler2_hir/src/lib.rs::file_symbol_contributions @ d9be6853b
// The symbol contributions of a file (not memoized: read off the index).
function file_symbol_contributions(db: Db, file: int) -> FileSymbolContributions throws never {
    file_semantic_index(db, file).symbol_contributions
}

// port: baml_compiler2_hir/src/lib.rs::file_item_tree @ d9be6853b
// The item tree of a file. Crate-internal in Rust: consumers use the
// `item_data` enumeration and lookup queries, never the tree itself.
function file_item_tree(db: Db, file: int) -> ItemTree throws never {
    file_semantic_index(db, file).item_tree
}

// port: baml_compiler2_hir/src/lib.rs::file_item_tree_source_map @ d9be6853b
// The item-tree source map of a file. Crate-internal in Rust: spans are
// served by the per-item `*_source_map` queries.
function file_item_tree_source_map(db: Db, file: int) -> ItemTreeSourceMap throws never {
    file_semantic_index(db, file).item_tree_source_map
}

// port: baml_compiler2_hir/src/lib.rs::scope_bindings_query @ d9be6853b
// The bindings of the scope `scope_id` (an interned `ScopeId`).
function scope_bindings_query(db: Db, scope_id: int) -> ScopeBindings throws never {
    let scope = db.scopes.get(scope_id);
    let index = file_semantic_index(db, scope.file);
    index.scope_bindings[scope.id]
}

// port: baml_compiler2_hir/src/lib.rs::file_env_var_refs @ d9be6853b
// The env var references found in a file's expression bodies.
function file_env_var_refs(db: Db, file: int) -> root.ast.EnvVarRef[] throws never {
    file_semantic_index(db, file).env_var_refs
}

// needs foundation: baml_parser/src/queries.rs::typed_tree, a tracked query
// in Rust. Parsed on each call here (only `file_ast` asks, and it is memoized).
// port: baml_parser/src/queries.rs::parse_typed @ d9be6853b
// `file`'s parse, tree and errors, once per file.
function parse_typed(db: Db, file: int) -> root.syntax.Parse throws never {
    db.memo.parse_typed.get(file, () -> {
        root.syntax.parse(db.file(file).text)
    })
}

// port: baml_parser/src/queries.rs::typed_tree @ d9be6853b
function typed_tree(db: Db, file: int) -> root.syntax.FileTree throws never {
    parse_typed(db, file).tree
}

// needs foundation: baml_base/src/files.rs::SourceFile::is_session_submission.
// `root.base.SourceFile` has no such input yet; no compile of this port is a
// `Session.eval` submission, so it is always false.
function is_session_submission(db: Db, file: int) -> bool throws never {
    false
}
