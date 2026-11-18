// port: baml_compiler2_hir/src/builder.rs @ d9be6853b
//
// `SemanticIndexBuilder`: walks a file's AST items and builds its
// `FileSemanticIndex`. Allocates scopes in DFS pre-order with their ranges,
// builds the `ItemTree`, collects `FileSymbolContributions`, and records
// expression -> scope mappings with per-scope `ScopeBindings`.
//
// Scope chain: Project -> Package -> Namespace* -> File -> Items.
//
// deviation: Rust's `FxHashMap`s iterate in hash order; BAML maps iterate in
// insertion order. That orders the bindings a pattern registers (their local
// indices) and the duplicate diagnostics differently from Rust; the
// diagnostics are sorted by span downstream.

// port: builder.rs::PathRootReference. A path's first segment as written,
// with the scope and innermost lambda it was written in.
class PathRootReference {
    name: string,
    use_scope: int,
    use_offset: int,
    owner_lambda: int?,
}

// port: builder.rs::PatternNames
class PatternNames {
    // Per introduced name: its source range and the `Pattern::Bind` node that
    // introduces it.
    names: map<string, (root.syntax.TextRange, int)>,
    duplicates: map<string, bool>,

    // port: the derived `Default` of PatternNames.
    function new() -> PatternNames throws never {
        PatternNames { names: {}, duplicates: {} }
    }
}

// port: baml_compiler2_hir/src/builder.rs::impl_head_name @ d9be6853b
// The head name used to seed an impl's stable `ImplId` from a target type:
// the last path segment (interface/class name), or a coarse shape tag for
// non-path targets. It only needs to be position-independent and reasonably
// collision-distributed; the `LocalItemId` collision index disambiguates
// anything that shares a head.
function impl_head_name(te: root.ast.TypeExpr) -> string throws never {
    match (te.kind) {
        let k: root.ast.TypeExprKindPath => {
            k.path.segments.at(k.path.segments.length() - 1) ?? "#path"
        },
        _ => "#nonpath",
    }
}

// port: builder.rs::SemanticIndexBuilder
class SemanticIndexBuilder {
    db: Db,
    file: int,
    // The namespace the file's items belong to, whose own items claim a
    // written path's first segment before any package does.
    namespace_path: string[],
    scopes: Scope[],
    scope_bindings: ScopeBindings[],
    // Owning item -> its scope. Inverse of `Scope.owner`.
    item_scopes: map<ItemScopeOwner, int>,
    // Stack of currently-open scope ids.
    scope_stack: int[],
    // Depth of class scopes we're inside (> 0 means methods don't contribute
    // top-level symbols: they belong to the class scope).
    class_depth: int,
    // The class most recently allocated: the owner of the in-body
    // `implements` blocks that follow it in the item list.
    last_class: int?,
    // Expression to lexical scope mappings, sorted by key at the end.
    expr_scopes: (ExprMetadataKey, int)[],
    // Lambda expression -> the `Lambda` scope it opened (span-free join).
    lambda_scopes: (ExprMetadataKey, int)[],
    // Path root resolutions, sorted by key at the end.
    path_resolutions: (ExprMetadataKey, PathResolution)[],
    // Arena namespace active while walking an expression body or defaults.
    expr_metadata_scope_stack: ExprMetadataScope[],
    // Path-root references collected in source order. Unlike `expr_scopes`,
    // each carries the scope and innermost lambda at collection time, so
    // capture analysis does not rely on arena-local expression ids.
    path_root_references: PathRootReference[],
    lambda_stack: int[],
    item_tree: ItemTreeBuilder,
    type_contributions: (string, Contribution)[],
    value_contributions: (string, Contribution)[],
    diagnostics: Hir2Diagnostic[],
    lowering_diagnostics: root.ast.LoweringDiagnostic[],
    // (scope, pattern) -> names; Rust keys by the tuple.
    invalid_pattern_bindings: map<int, map<int, map<string, bool>>>,
    // (pattern span, pattern) -> scope; Rust keys by the tuple.
    invalid_pattern_binding_scopes: map<root.syntax.TextRange, map<int, int>>,
    env_var_refs: root.ast.EnvVarRef[],

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::new @ d9be6853b
    function new(db: Db, file: int) -> SemanticIndexBuilder throws never {
        SemanticIndexBuilder {
            db: db,
            file: file,
            namespace_path: [],
            scopes: [],
            scope_bindings: [],
            item_scopes: {},
            scope_stack: [],
            class_depth: 0,
            last_class: null,
            expr_scopes: [],
            lambda_scopes: [],
            path_resolutions: [],
            expr_metadata_scope_stack: [],
            path_root_references: [],
            lambda_stack: [],
            item_tree: ItemTreeBuilder.new(),
            type_contributions: [],
            value_contributions: [],
            diagnostics: [],
            lowering_diagnostics: [],
            invalid_pattern_bindings: {},
            invalid_pattern_binding_scopes: {},
            env_var_refs: [],
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::with_lowering_diagnostics @ d9be6853b
    // Set lowering diagnostics produced during CST -> AST lowering.
    function with_lowering_diagnostics(
        self,
        diags: root.ast.LoweringDiagnostic[],
    ) -> SemanticIndexBuilder throws never {
        self.lowering_diagnostics = diags;
        self
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::with_env_var_refs @ d9be6853b
    // Set env var references collected during CST -> AST lowering.
    function with_env_var_refs(
        self,
        refs: root.ast.EnvVarRef[],
    ) -> SemanticIndexBuilder throws never {
        self.env_var_refs = refs;
        self
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::build @ d9be6853b
    // Build the `FileSemanticIndex` from a list of AST items. `file_range` is
    // the full text range of the file (used for Project/Package/Namespace/File
    // scopes).
    function build(
        self,
        items: root.ast.Item[],
        file_range: root.syntax.TextRange,
    ) -> FileSemanticIndex throws never {
        let pkg_info = file_package(self.db, self.file);
        self.namespace_path = pkg_info.namespace_path;
        self.open_structural_scopes(pkg_info, file_range);

        for (let item in items) {
            self.lower_item(item);
        }
        self.validate_phase1_builtin_contracts(items);

        // Pop: File, Namespace*, Package, Project
        self.pop_scope();
        for (let _ns in pkg_info.namespace_path) {
            self.pop_scope();
        }
        self.pop_scope();
        self.pop_scope();

        // Sort for binary search.
        self.expr_scopes.sort_by_key((pair) -> {
            pair.0
        });
        self.lambda_scopes.sort_by_key((pair) -> {
            pair.0
        });
        self.path_resolutions.sort_by_key((pair) -> {
            pair.0
        });

        // Pre-intern a ScopeId for each scope.
        let scope_ids: int[] = [];
        while (scope_ids.length() < self.scopes.length()) {
            scope_ids.push(self.db.scopes.intern(self.file, scope_ids.length()));
        }

        let extra = if (!self.diagnostics && !self.lowering_diagnostics && !self.invalid_pattern_bindings) {
            null
        } else {
            SemanticIndexExtra {
                diagnostics: self.diagnostics,
                lowering_diagnostics: self.lowering_diagnostics,
                invalid_pattern_bindings: self.invalid_pattern_bindings,
                invalid_pattern_binding_scopes: self.invalid_pattern_binding_scopes,
            }
        };

        // Drops the collision counter: it has no meaning once the tree is built.
        let (let item_tree, let item_tree_source_map) = self.item_tree.finish();

        FileSemanticIndex {
            scopes: self.scopes,
            expr_scopes: self.expr_scopes,
            lambda_scopes: self.lambda_scopes,
            scope_bindings: self.scope_bindings,
            scope_ids: scope_ids,
            item_scopes: self.item_scopes,
            item_tree: item_tree,
            item_tree_source_map: item_tree_source_map,
            symbol_contributions: FileSymbolContributions {
                types: self.type_contributions,
                values: self.value_contributions,
            },
            extra: extra,
            path_resolutions: self.path_resolutions,
            env_var_refs: self.env_var_refs,
        }
    }

    // port: the scope-chain half of builder.rs::SemanticIndexBuilder::build.
    // Push Project -> Package -> Namespace* -> File, each over the whole file.
    function open_structural_scopes(
        self,
        pkg_info: PackageInfo,
        file_range: root.syntax.TextRange,
    ) -> void throws never {
        self.push_scope(ScopeKind.Project, null, file_range);
        // A structural scope: its name is never consulted for resolution; it
        // carries the package's own name, when it declares one, for dumps.
        self.push_scope(
            ScopeKind.Package,
            self.db.source_root(pkg_info.root_id).self_name,
            file_range,
        );
        for (let ns in pkg_info.namespace_path) {
            // `ns_root/` would make `root.root.X` a path: refused like every
            // other `root`, once per file in the directory.
            if (ns == ROOT_SEGMENT) {
                self.diagnostics.push(
                    Hir2DiagnosticRootNamespace {
                        span: root.syntax.TextRange.empty(file_range.start),
                    },
                );
            }
            self.push_scope(ScopeKind.Namespace, ns, file_range);
        }
        self.push_scope(ScopeKind.File, file_name(self.db.file(self.file).path), file_range);
    }

    // ── Scope management ──

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::push_scope @ d9be6853b
    function push_scope(
        self,
        kind: ScopeKind,
        name: string?,
        range: root.syntax.TextRange,
    ) -> void throws never {
        let id = self.scopes.length();
        self.scopes.push(
            Scope {
                parent: self.scope_stack.at(self.scope_stack.length() - 1),
                kind: kind,
                name: name,
                owner: null,
                range: range,
                // Empty initially; filled on pop.
                descendants: FileScopeIdRange { start: id + 1, end: id + 1 },
                is_template_body: false,
            },
        );
        self.scope_bindings.push(ScopeBindings.new());
        self.scope_stack.push(id);
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::record_scope_owner @ d9be6853b
    // Link a scope to the item it was opened for, at the one place that knows
    // both.
    function record_scope_owner(self, scope: int, owner: ItemScopeOwner) -> void throws never {
        self.scopes[scope].owner = owner;
        self.item_scopes[owner] = scope;
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::pop_scope @ d9be6853b
    function pop_scope(self) -> void throws never {
        let popped = self.scope_stack.pop() ?? baml.sys.panic("scope stack underflow");
        self.scopes[popped].descendants.end = self.scopes.length();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::current_scope_id @ d9be6853b
    function current_scope_id(self) -> int throws never {
        self.scope_stack.at(self.scope_stack.length() - 1) ?? baml.sys.panic("no current scope")
    }

    // ── Expression recording ──

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::current_expr_metadata_key @ d9be6853b
    function current_expr_metadata_key(self, expr_id: int) -> ExprMetadataKey throws never {
        let stack = self.expr_metadata_scope_stack;
        let scope = stack.at(stack.length() - 1)
            ?? baml.sys.panic("expression walked without an arena namespace");
        ExprMetadataKey.new(scope, expr_id)
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::record_expr_scope @ d9be6853b
    // Record that an expression belongs to the current scope.
    function record_expr_scope(self, expr_id: int) -> void throws never {
        let key = self.current_expr_metadata_key(expr_id);
        self.expr_scopes.push((key, self.current_scope_id()));
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::current_scope_path @ d9be6853b
    // A dotted scope path from the current scope stack, e.g. `Foo.Bar`. Skips
    // structural scopes (Project, Package, Namespace, File).
    function current_scope_path(self) -> string? throws never {
        let parts = self.scope_stack.filter_map((id) -> {
            let scope = self.scopes[id];
            match (scope.kind) {
                ScopeKind.Project | ScopeKind.Package | ScopeKind.Namespace | ScopeKind.File => null,
                _ => scope.name,
            }
        });
        if (!parts) {
            return null;
        }
        parts.join(".")
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::emit_duplicate_param_diagnostics @ d9be6853b
    // A `DuplicateDefinition` for any parameter name that appears more than
    // once in a function or lambda signature, positional or defaulted alike:
    // any collision would make later references to the name ambiguous.
    function emit_duplicate_param_diagnostics(self, params: root.ast.Param[]) -> void throws never {
        let seen: map<string, MemberSite[]> = {};
        for (let param in params) {
            seen.get_or_insert(param.name, []).push(
                MemberSite { range: param.name_span, kind: DefinitionKind.Parameter },
            );
        }
        self.emit_duplicate_diagnostics(seen);
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::reject_root_name @ d9be6853b
    // `root` is the path to the package itself (`ROOT_SEGMENT`) and names
    // nothing else: not a binding, an item, or a type parameter, so `root.X`
    // always means this package's `X`.
    function reject_root_name(
        self,
        name: string,
        span: root.syntax.TextRange,
    ) -> void throws never {
        if (name == ROOT_SEGMENT) {
            self.diagnostics.push(Hir2DiagnosticRootIsReserved { span: span });
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::reject_root_generics @ d9be6853b
    // `reject_root_name` over an item's type parameters.
    function reject_root_generics(self, generics: root.ast.GenericParam[]) -> void throws never {
        for (let generic in generics) {
            self.reject_root_name(generic.name, generic.name_span);
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::emit_duplicate_diagnostics @ d9be6853b
    // A `DuplicateDefinition` for any name with more than one site.
    function emit_duplicate_diagnostics(
        self,
        seen: map<string, MemberSite[]>,
    ) -> void throws never {
        let scope = self.current_scope_path();
        for (let name in seen.keys()) {
            let sites = seen[name];
            if (sites.length() > 1) {
                self.diagnostics.push(
                    Hir2DiagnosticDuplicateDefinition { name: name, scope: scope, sites: sites },
                );
            }
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_expr_body @ d9be6853b
    // Walk an `ExprBody` arena in source order, recording expression ownership
    // and local bindings in the lexical scope that owns each expression.
    function walk_expr_body(
        self,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        self.expr_metadata_scope_stack.push(
            ExprMetadataScopeBody { value: self.current_scope_id() },
        );
        if let root_expr: int = body.root_expr {
            self.walk_expr(root_expr, body, source_map, false);
        }
        self.expr_metadata_scope_stack.pop();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_parameter_defaults @ d9be6853b
    // Takes the parameter list and default arena separately so it serves both
    // declared functions and lambdas.
    function walk_parameter_defaults(
        self,
        params: root.ast.Param[],
        defaults: root.ast.FunctionDefaults,
    ) -> void throws never {
        self.expr_metadata_scope_stack.push(
            ExprMetadataScopeParameterDefault { value: self.current_scope_id() },
        );
        for (let param in params) {
            if let default_: int = param.default {
                self.walk_expr(default_, defaults.exprs, defaults.source_map, true);
            }
        }
        self.expr_metadata_scope_stack.pop();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_expr @ d9be6853b
    // Walk an expression, recording its scope and (for blocks) optionally
    // pushing a `Block` scope around the contents. `push_block_scope` is false
    // when walking the root body of a function or lambda, whose scope is
    // already on the stack.
    function walk_expr(
        self,
        expr_id: int,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
        push_block_scope: bool,
    ) -> void throws never {
        match (body.exprs[expr_id]) {
            let e: root.ast.ExprBlock => {
                if (push_block_scope) {
                    self.push_scope(ScopeKind.Block, null, source_map.expr_span(expr_id));
                }
                self.record_expr_scope(expr_id);
                self.walk_block_contents(e.stmts, e.tail_expr, body, source_map);
                if (push_block_scope) {
                    self.pop_scope();
                }
            },
            let e: root.ast.ExprLambda => {
                self.record_expr_scope(expr_id);
                self.walk_lambda_expr(expr_id, e.value, body, source_map);
            },
            _ => {
                self.record_expr_scope(expr_id);
                self.walk_expr_children(expr_id, body, source_map);
            },
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_block_contents @ d9be6853b
    function walk_block_contents(
        self,
        stmts: int[],
        tail_expr: int?,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        for (let stmt_id in stmts) {
            self.walk_stmt(stmt_id, body, source_map);
        }
        if (tail_expr != null) {
            self.walk_expr(tail_expr, body, source_map, true);
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_stmt @ d9be6853b
    function walk_stmt(
        self,
        stmt_id: int,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let walk = (expr: int) -> void {
            self.walk_expr(expr, body, source_map, true);
        };
        match (body.stmts[stmt_id]) {
            let s: root.ast.StmtExpr => walk(s.value),
            let s: root.ast.StmtTypeBinding => {
                if let span: root.syntax.TextRange = source_map.type_binding_name_span(stmt_id) {
                    self.reject_root_name(s.name, span);
                }
                // The operand and the `else` block are ordinary expressions in the
                // enclosing scope (`T` is not yet in scope in either).
                walk(s.operand);
                if let else_branch: int = s.else_branch {
                    walk(else_branch);
                }
            },
            let s: root.ast.StmtLet => {
                if let initializer: int = s.initializer {
                    walk(initializer);
                }
                if let else_expr: int = s.else_branch {
                    // `let ... else { ... }`: the else block runs in the enclosing
                    // scope BEFORE the pattern's names are registered, so walk it
                    // first. The block's own scope keeps inner bindings from leaking.
                    walk(else_expr);
                }
                let site = DefinitionSiteStatement { value: stmt_id };
                self.register_local_pattern(
                    s.pattern,
                    site,
                    body,
                    source_map,
                    source_map.stmt_span(stmt_id).end,
                );
            },
            let s: root.ast.StmtFor => {
                walk(s.collection);
                self.push_scope(ScopeKind.Block, null, source_map.stmt_span(stmt_id));
                let site = DefinitionSiteStatement { value: stmt_id };
                self.register_local_pattern(
                    s.binding,
                    site,
                    body,
                    source_map,
                    source_map.pattern_span(s.binding).start,
                );
                walk(s.body);
                self.pop_scope();
            },
            let s: root.ast.StmtWhile => {
                walk(s.condition);
                // A Block scope around the body and the C-style for `after` step,
                // mirroring `Stmt::For`: it gives the while statement its own
                // identity in the scope tree. The `after` step runs at the body's
                // level, not inside it: it must see the locals the for-init
                // declared, so it stays in this scope but outside the body's own.
                self.push_scope(ScopeKind.Block, null, source_map.stmt_span(stmt_id));
                walk(s.body);
                if let after: int = s.after {
                    self.walk_stmt(after, body, source_map);
                }
                self.pop_scope();
            },
            let s: root.ast.StmtWhileLet => {
                // The scrutinee is evaluated in the enclosing scope, like `While`'s
                // condition: walk it before pushing the body scope so its paths
                // don't resolve to the loop's own bindings.
                walk(s.scrutinee);
                // One Block scope spanning the whole statement holds the pattern
                // bindings, visible to the body; they vanish after the loop.
                self.push_scope(ScopeKind.Block, null, source_map.stmt_span(stmt_id));
                let site = DefinitionSiteStatement { value: stmt_id };
                self.register_local_pattern(
                    s.pattern,
                    site,
                    body,
                    source_map,
                    source_map.pattern_span(s.pattern).start,
                );
                walk(s.body);
                self.pop_scope();
            },
            let s: root.ast.StmtReturn => {
                if let value: int = s.value {
                    walk(value);
                }
            },
            let s: root.ast.StmtThrow => walk(s.value),
            let s: root.ast.StmtAssign => {
                walk(s.target);
                walk(s.value);
            },
            let s: root.ast.StmtAssignOp => {
                walk(s.target);
                walk(s.value);
            },
            // The defer body is an inline block in this same `ExprBody`; its own
            // scope contains inner bindings.
            let s: root.ast.StmtDefer => walk(s.body),
            root.ast.StmtBreak
                | root.ast.StmtContinue
                | root.ast.StmtMissing
                | root.ast.StmtHeaderComment =>
            {},
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_expr_children @ d9be6853b
    function walk_expr_children(
        self,
        expr_id: int,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let walk = (expr: int) -> void {
            self.walk_expr(expr, body, source_map, true);
        };
        let walk_all = (exprs: int[]) -> void {
            for (let expr in exprs) {
                walk(expr);
            }
        };
        match (body.exprs[expr_id]) {
            let e: root.ast.ExprIf => {
                walk(e.condition);
                walk(e.then_branch);
                if let else_branch: int = e.else_branch {
                    walk(else_branch);
                }
            },
            let e: root.ast.ExprIfLet => self.walk_if_let(e, body, source_map),
            let e: root.ast.ExprMatch => {
                walk(e.scrutinee);
                for (let arm_id in e.arms) {
                    self.walk_match_arm(arm_id, body, source_map);
                }
            },
            // `<expr> is <pattern>` is a one-shot test yielding `bool`: its pattern
            // bindings do NOT escape into the surrounding scope.
            let e: root.ast.ExprIs => walk(e.scrutinee),
            let e: root.ast.ExprCatch => {
                walk(e.base);
                let catch_span = SemanticIndexBuilder.catch_clause_scope_span(e.clause, source_map);
                self.walk_catch_clause(e.clause, body, source_map, catch_span);
            },
            let e: root.ast.ExprThrow => walk(e.value),
            let e: root.ast.ExprReturn => {
                if let value: int = e.value {
                    walk(value);
                }
            },
            let e: root.ast.ExprAwait => walk(e.future),
            let e: root.ast.ExprBinary => walk_all([e.lhs, e.rhs]),
            let e: root.ast.ExprTemplate => self.walk_template(expr_id, e.tag, body, source_map),
            let e: root.ast.ExprUnary => walk(e.expr),
            let e: root.ast.ExprOptionalChain => walk(e.expr),
            let e: root.ast.ExprCall => {
                walk(e.callee);
                walk_all(
                    e.args.map((arg) -> {
                        arg.expr
                    }),
                );
            },
            let e: root.ast.ExprOptionalCall => {
                walk(e.callee);
                walk_all(
                    e.args.map((arg) -> {
                        arg.expr
                    }),
                );
            },
            // port: builder.rs::walk_expr_children, the `Expr::Object` arm, as of
            // upstream #5719 (ported ahead of its merge). A field named twice
            // explicitly is an error. A field that also comes from a `...spread`
            // is not: explicit fields override whatever the spread supplies.
            let e: root.ast.ExprObject => {
                let sites_by_field: map<string, root.syntax.TextRange[]> = {};
                for (let field in e.fields) {
                    sites_by_field.get_or_insert(field.name, []).push(
                        source_map.object_field_name_span(expr_id, field.value),
                    );
                    walk(field.value);
                }
                for (let name in sites_by_field.keys()) {
                    let sites = sites_by_field[name];
                    if (sites.length() > 1) {
                        self.diagnostics.push(Hir2DiagnosticDuplicateObjectField { name: name, sites: sites });
                    }
                }
                walk_all(
                    e.spreads.map((spread) -> {
                        spread.expr
                    }),
                );
            },
            let e: root.ast.ExprArray => walk_all(e.elements),
            let e: root.ast.ExprTuple => walk_all(e.elements),
            let e: root.ast.ExprMap => {
                for (let entry in e.entries) {
                    walk(entry.key);
                    walk(entry.value);
                }
            },
            let e: root.ast.ExprMemberAccess => walk(e.base),
            let e: root.ast.ExprOptionalMemberAccess => walk(e.base),
            let e: root.ast.ExprUpcast => walk(e.base),
            let e: root.ast.ExprIndex => walk_all([e.base, e.index]),
            let e: root.ast.ExprOptionalIndex => walk_all([e.base, e.index]),
            let e: root.ast.ExprPath => self.walk_path(expr_id, e.value, source_map),
            // `foo<int>` references the base callable; walk it so the path root is
            // recorded for name resolution. Type args are types, not values.
            let e: root.ast.ExprGenericApply => walk(e.base),
            root.ast.ExprLiteral
                | root.ast.ExprByteStringLiteral
                | root.ast.ExprNull
                | root.ast.ExprBlock
                | root.ast.ExprLambda
                | root.ast.ExprQualifiedPath
                | root.ast.ExprMissing =>
            {},
        }
    }

    // port: the `Expr::IfLet` arm of builder.rs::SemanticIndexBuilder::walk_expr_children.
    function walk_if_let(
        self,
        e: root.ast.ExprIfLet,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        // The scrutinee is evaluated in the enclosing scope.
        self.walk_expr(e.scrutinee, body, source_map, true);

        // The then-branch sees the pattern's bindings: a fresh scope, with them
        // registered before the walk. Mirrors `walk_match_arm`.
        self.push_scope(ScopeKind.MatchArm, null, source_map.expr_span(e.then_branch));
        let visible_from = source_map.pattern_span(e.pattern).start;
        let site = DefinitionSitePatternBinding { value: e.pattern };
        self.register_local_pattern(e.pattern, site, body, source_map, visible_from);
        self.walk_expr(e.then_branch, body, source_map, true);
        self.pop_scope();

        // The else-branch never sees the pattern's bindings.
        if let else_branch: int = e.else_branch {
            self.walk_expr(else_branch, body, source_map, true);
        }
    }

    // port: the `Expr::Template` arm of builder.rs::SemanticIndexBuilder::walk_expr_children.
    function walk_template(
        self,
        expr_id: int,
        tag: root.ast.TemplateTag,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        match (tag) {
            // Tagged (`Custom`): the tag is an ordinary value reference in the
            // ENCLOSING scope, and the template body is its own lambda scope, so
            // references to enclosing locals inside `${...}` are computed as
            // captures (BEP-049 §10: MIR hand-rolls the body closure off them).
            let t: root.ast.TemplateTagCustom => {
                self.walk_expr(t.tag, body, source_map, true);
                self.walk_template_lambda_body(expr_id, t.body, body, source_map);
            },
            // Untagged (`Default`): no closure. The desugared `elaborated` concat
            // realizes the template in the ENCLOSING scope, so walk that directly:
            // it holds the same `${...}` exprs and any `${for}` bindings, with no
            // capture boundary. The structured segments are diagnostics-only.
            let t: root.ast.TemplateTagDefault => {
                self.walk_expr(t.elaborated, body, source_map, true)
            },
        }
    }

    // port: the `Expr::Path` arm of builder.rs::SemanticIndexBuilder::walk_expr_children.
    function walk_path(
        self,
        expr_id: int,
        path: root.base.Path,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let root_name = path.segments.at(0)
            ?? return;
        let use_scope = self.current_scope_id();
        let use_offset = source_map.expr_span(expr_id).start;
        // A compiler-written path names its package by identity or an item of
        // this namespace: its first segment refers to nothing in scope, so a
        // lambda it sits in captures no binding spelled like it.
        if (path.origin == root.base.PathOrigin.Written) {
            self.record_path_root_reference(root_name, use_scope, use_offset);
        }
        self.resolve_path_expr(expr_id, path, use_scope, use_offset);
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_template_lambda_body @ d9be6853b
    // Walk a TAGGED template's body inside a fresh `Lambda` scope spanning the
    // whole template expression (BEP-049 §10), making the body a capture
    // boundary: interpolations referring to enclosing locals are recorded as
    // captures, which MIR consumes when it hand-rolls the body closure.
    //
    // The lambda's parameters (the tag's `body` params) are NOT registered:
    // the tag is a cross-file item whose signature cannot be resolved during
    // the semantic-index walk (it would cycle `file_semantic_index` ->
    // `package_items`), so MIR and TIR inject them. `${for}` bindings still
    // nest in their own block scopes.
    function walk_template_lambda_body(
        self,
        expr_id: int,
        flatten_body: int,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        // The enclosing real lambda, if any, taken BEFORE pushing the template's
        // synthetic one (see the transitive-capture step below).
        let enclosing_lambda = self.lambda_stack.at(self.lambda_stack.length() - 1);

        // Span-free scope join keyed by the template expression, as
        // `walk_lambda_expr` does for real lambdas.
        let key = self.current_expr_metadata_key(expr_id);
        self.push_scope(ScopeKind.Lambda, null, source_map.expr_span(expr_id));
        let scope_id = self.current_scope_id();
        self.lambda_scopes.push((key, scope_id));
        // A synthetic template body: a Lambda scope for capture analysis, but
        // TIR types its body inline in the enclosing scope.
        self.scopes[scope_id].is_template_body = true;
        self.lambda_stack.push(scope_id);
        // Walk the desugared flatten block's CONTENTS inline in this scope:
        // `${...}` exprs referring to enclosing locals become captures, its
        // synthetic accumulator `let`s register as lambda-locals, and a `${for}`
        // binding nests in a child block scope. `push_block_scope = false` keeps
        // a block body's contents here while still recording the block's id.
        self.walk_expr(flatten_body, body, source_map, false);
        self.analyze_lambda_captures(scope_id, body, source_map);

        // BEP-049 §10: transitive capture through a synthetic lambda. When a
        // tagged template sits inside a user lambda `f`, every var the template
        // body captures from beyond `f` must also be captured BY `f` (TIR types
        // the body inline in `f`, MIR forwards the template closure's captures
        // up through `f`). The template's references attribute only to this
        // synthetic lambda, so re-record each capture as a reference owned by
        // `f`; otherwise TIR reports it unresolved (E0003).
        if let enclosing: int = enclosing_lambda {
            let at = source_map.expr_span(expr_id).start;
            for (let capture in self.scope_bindings[scope_id].captures) {
                self.path_root_references.push(
                    PathRootReference {
                        name: capture.0,
                        use_scope: enclosing,
                        use_offset: at,
                        owner_lambda: enclosing,
                    },
                );
            }
        }

        self.lambda_stack.pop();
        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::register_local_pattern @ d9be6853b
    function register_local_pattern(
        self,
        pat_id: int,
        site: DefinitionSite,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
        visible_from: int,
    ) -> void throws never {
        // Walk the pattern structurally: the names it introduces, with
        // diagnostics for duplicate names and or-alternative mismatches.
        let names = SemanticIndexBuilder.collect_pattern_names(
            body.patterns,
            pat_id,
            source_map,
            self.diagnostics,
        );

        let scope_id = self.current_scope_id();
        if (names.duplicates) {
            self.invalid_pattern_bindings.get_or_insert(scope_id, {})[pat_id] = names.duplicates;
            self.invalid_pattern_binding_scopes.get_or_insert(source_map.pattern_span(pat_id), {})[
                pat_id
            ]
                = scope_id;
        }

        for (let name in names.names.keys()) {
            let (let name_range, let bind_pattern) = names.names[name];
            self.reject_root_name(name, name_range);
            self.scope_bindings[scope_id].bindings.push(
                LocalBinding {
                    name: name,
                    site: site,
                    pattern: pat_id,
                    bind_pattern: bind_pattern,
                    name_range: name_range,
                    visible_from: visible_from,
                },
            );
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::collect_pattern_names @ d9be6853b
    // The names a pattern introduces into scope, each with the range of its
    // first occurrence. Diagnoses (1) a name bound twice within one pattern
    // (`Class { a, a }`), and (2) `Or` alternatives that bind different names
    // (the arm body would only sometimes see a name). Duplicates ACROSS
    // alternatives are fine: each alternative is its own scope.
    function collect_pattern_names(
        patterns: root.ast.Pattern[],
        pat_id: int,
        source_map: root.ast.AstSourceMap,
        diagnostics: Hir2Diagnostic[],
    ) -> PatternNames throws never {
        let result = PatternNames.new();
        let merge = (id: int) -> void {
            let inner = SemanticIndexBuilder.collect_pattern_names(patterns, id, source_map, diagnostics);
            SemanticIndexBuilder.merge_with_dup_check(result, inner, diagnostics);
        };
        match (patterns[pat_id]) {
            root.ast.PatternWildcard | root.ast.PatternType => result,
            let p: root.ast.PatternBind => {
                result.names[p.name] = (source_map.pattern_span(pat_id), pat_id);
                if let sp: int = p.subpat {
                    merge(sp);
                }
                result
            },
            let p: root.ast.PatternClass => {
                let seen_fields: map<string, root.syntax.TextRange[]> = {};
                for (let f in p.fields) {
                    seen_fields.get_or_insert(f.field, []).push(f.field_span);
                    merge(f.pat);
                }
                for (let name in seen_fields.keys()) {
                    let sites = seen_fields[name];
                    if (sites.length() > 1) {
                        diagnostics.push(
                            Hir2DiagnosticDuplicatePatternField { name: name, sites: sites },
                        );
                    }
                }
                result
            },
            let p: root.ast.PatternArray => {
                p.prefix.for_each(merge);
                if let rest_pat: int = p.rest?.pat {
                    merge(rest_pat);
                }
                p.suffix.for_each(merge);
                result
            },
            let p: root.ast.PatternTuple => {
                p.value.for_each(merge);
                result
            },
            let p: root.ast.PatternOr => {
                SemanticIndexBuilder.collect_or_pattern_names(
                    patterns,
                    pat_id,
                    p.value,
                    source_map,
                    diagnostics,
                )
            },
        }
    }

    // port: the `Pattern::Or` arm of builder.rs::SemanticIndexBuilder::collect_pattern_names.
    function collect_or_pattern_names(
        patterns: root.ast.Pattern[],
        pat_id: int,
        parts: int[],
        source_map: root.ast.AstSourceMap,
        diagnostics: Hir2Diagnostic[],
    ) -> PatternNames throws never {
        // Each alternative is collected independently; duplicates are checked
        // per branch (by the recursive call), parity across branches here.
        let branch_sets = parts.map((id) -> {
            SemanticIndexBuilder.collect_pattern_names(patterns, id, source_map, diagnostics)
        });

        let duplicates: map<string, bool> = {};
        for (
            let name in branch_sets.flat_map((branch) -> {
                branch.duplicates.keys()
            })
        ) {
            duplicates[name] = true;
        }
        let mismatched = SemanticIndexBuilder.or_mismatched_names(branch_sets);
        if (mismatched) {
            // Tighten the span to cover just the Or's branches rather than the
            // whole containing pattern (which can pull in surrounding trivia and
            // span multiple lines).
            let first_part = parts.at(0);
            let last_part = parts.at(parts.length() - 1);
            let or_span = if (first_part != null && last_part != null) {
                root.syntax.TextRange {
                    start: source_map.pattern_span(first_part).start,
                    end: source_map.pattern_span(last_part).end,
                }
            } else {
                source_map.pattern_span(pat_id)
            };
            diagnostics.push(
                Hir2DiagnosticOrPatternBindingMismatch {
                    or_span: or_span,
                    mismatched_names: mismatched,
                },
            );
            // On mismatch, suppress the Or's bindings entirely so downstream
            // scopes don't depend on branch order (`let x | _` vs `_ | let x`
            // would otherwise differ). The diagnostic above carries the error.
            return PatternNames { names: {}, duplicates: duplicates };
        }
        // Every branch introduces the same set, so the first branch's is
        // representative.
        PatternNames { names: branch_sets.at(0)?.names ?? {}, duplicates: duplicates }
    }

    // port: the parity check in the `Pattern::Or` arm of
    // builder.rs::SemanticIndexBuilder::collect_pattern_names. The names some
    // alternatives bind but the first does not, or the other way round: each
    // branch's symmetric difference with the first, sorted and distinct (Rust
    // collects them in a `BTreeSet`).
    function or_mismatched_names(branch_sets: PatternNames[]) -> string[] throws never {
        let first = branch_sets.at(0)
            ?? return [];
        let mismatched: map<string, bool> = {};
        for (let branch in branch_sets.slice(1, branch_sets.length())) {
            let only_first = first.names.keys().filter((n) -> {
                !branch.names.has(n)
            });
            let only_branch = branch.names.keys().filter((n) -> {
                !first.names.has(n)
            });
            for (let n in only_first.concat(only_branch)) {
                mismatched[n] = true;
            }
        }
        mismatched.keys().sort_by((a, b) -> {
            a.cmp(b)
        })
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::merge_with_dup_check @ d9be6853b
    // Merge `source` into `target`. A name already in `target` produces a
    // `DuplicatePatternBinding` diagnostic.
    function merge_with_dup_check(
        target: PatternNames,
        source: PatternNames,
        diagnostics: Hir2Diagnostic[],
    ) -> void throws never {
        for (let name in source.duplicates.keys()) {
            target.duplicates[name] = true;
        }
        for (let name in source.names.keys()) {
            let entry = source.names[name];
            if let prev: (root.syntax.TextRange, int) = target.names.get(name) {
                diagnostics.push(
                    Hir2DiagnosticDuplicatePatternBinding { name: name, sites: [prev.0, entry.0] },
                );
                target.duplicates[name] = true;
            } else {
                target.names[name] = entry;
            }
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_match_arm @ d9be6853b
    function walk_match_arm(
        self,
        arm_id: int,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let arm = body.match_arms[arm_id];
        self.push_scope(ScopeKind.MatchArm, null, source_map.match_arm_span(arm_id));
        let visible_from = source_map.pattern_span(arm.pattern).start;
        let site = DefinitionSitePatternBinding { value: arm.pattern };
        self.register_local_pattern(arm.pattern, site, body, source_map, visible_from);
        if let guard: int = arm.guard {
            self.walk_expr(guard, body, source_map, true);
        }
        self.walk_expr(arm.body, body, source_map, true);
        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_catch_clause @ d9be6853b
    function walk_catch_clause(
        self,
        clause: root.ast.CatchClause,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
        catch_span: root.syntax.TextRange,
    ) -> void throws never {
        self.push_scope(ScopeKind.CatchClause, null, catch_span);
        let binding_visible_from = source_map.pattern_span(clause.binding).start;
        let site = DefinitionSiteCatchBinding { value: clause.binding };
        self.register_local_pattern(clause.binding, site, body, source_map, binding_visible_from);
        if let st_pat: int = clause.stack_trace_binding {
            let st_visible_from = source_map.pattern_span(st_pat).start;
            self.register_local_pattern(
                st_pat,
                DefinitionSiteCatchBinding { value: st_pat },
                body,
                source_map,
                st_visible_from,
            );
        }
        for (let arm_id in clause.arms) {
            self.walk_catch_arm(arm_id, body, source_map);
        }
        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_catch_arm @ d9be6853b
    function walk_catch_arm(
        self,
        arm_id: int,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let arm = body.catch_arms[arm_id];
        self.push_scope(ScopeKind.CatchArm, null, source_map.catch_arm_span(arm_id));
        let visible_from = source_map.pattern_span(arm.pattern).start;
        let site = DefinitionSitePatternBinding { value: arm.pattern };
        self.register_local_pattern(arm.pattern, site, body, source_map, visible_from);
        self.walk_expr(arm.body, body, source_map, true);
        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::catch_clause_scope_span @ d9be6853b
    function catch_clause_scope_span(
        clause: root.ast.CatchClause,
        source_map: root.ast.AstSourceMap,
    ) -> root.syntax.TextRange throws never {
        let spans = [source_map.pattern_span(clause.binding)];
        if let stack_trace_binding: int = clause.stack_trace_binding {
            spans.push(source_map.pattern_span(stack_trace_binding));
        }
        for (let arm_id in clause.arms) {
            spans.push(source_map.catch_arm_span(arm_id));
        }
        spans.reduce(
            (acc, span) -> {
                acc.cover(span)
            },
            spans[0],
        )
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::walk_lambda_expr @ d9be6853b
    function walk_lambda_expr(
        self,
        expr_id: int,
        lambda: root.ast.LambdaDef,
        body: root.ast.ExprBody,
        source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let key = self.current_expr_metadata_key(expr_id);
        self.push_scope(ScopeKind.Lambda, null, source_map.expr_span(expr_id));
        let scope_id = self.current_scope_id();
        self.lambda_scopes.push((key, scope_id));
        self.register_params(scope_id, lambda.params);
        self.emit_duplicate_param_diagnostics(lambda.params);
        self.lambda_stack.push(scope_id);
        self.walk_parameter_defaults(lambda.params, lambda.defaults);

        self.expr_metadata_scope_stack.push(ExprMetadataScopeBody { value: scope_id });
        if let lambda_body: int = lambda.body {
            // The body shares this arena but gets its own metadata namespace keyed
            // by the lambda's scope, agreeing with TIR's `infer_lambda_body` and
            // MIR's `lower_lambda`. A mismatch would not fail loudly:
            // `path_resolution` would miss, flow narrowing would stop inside every
            // lambda, and closure signatures would degrade to `unknown`.
            self.walk_expr(lambda_body, body, source_map, false);
            self.analyze_lambda_captures(scope_id, body, source_map);
        }
        self.expr_metadata_scope_stack.pop();
        self.lambda_stack.pop();
        self.pop_scope();
    }

    // port: the parameter loop shared by builder.rs::SemanticIndexBuilder::walk_lambda_expr
    // and lower_function: each parameter is refused if named `root`, then
    // registered on the scope with its index.
    function register_params(self, scope_id: int, params: root.ast.Param[]) -> void throws never {
        let idx = 0;
        for (let param in params) {
            self.reject_root_name(param.name, param.name_span);
            self.scope_bindings[scope_id].params.push((param.name, idx));
            idx += 1;
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::analyze_lambda_captures @ d9be6853b
    function analyze_lambda_captures(
        self,
        lambda_scope: int,
        _lambda_body: root.ast.ExprBody,
        _lambda_source_map: root.ast.AstSourceMap,
    ) -> void throws never {
        let captures: (string, BindingId)[] = [];
        let seen: map<BindingId, bool> = {};

        for (
            let reference in self.path_root_references.filter((r) -> {
                r.owner_lambda == lambda_scope
            })
        ) {
            let binding_id = self.visible_binding_at(reference.use_scope, reference.use_offset, reference.name)
                ?? continue;
            if (
                !self.scope_is_descendant_or_self(binding_id.scope, lambda_scope)
                    && !seen.has(binding_id)
            ) {
                seen[binding_id] = true;
                captures.push((reference.name, binding_id));
                self.scope_bindings[binding_id.scope].captured_bindings[binding_id] = true;
            }
        }

        self.scope_bindings[lambda_scope].captures = captures;
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::visible_binding_at @ d9be6853b
    function visible_binding_at(
        self,
        scope_id: int,
        at_offset: int,
        name: string,
    ) -> BindingId? throws never {
        visible_binding_at_in_scopes(self.scopes, self.scope_bindings, scope_id, at_offset, name)
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::scope_is_descendant_or_self @ d9be6853b
    function scope_is_descendant_or_self(
        self,
        scope_id: int,
        ancestor_id: int,
    ) -> bool throws never {
        let current: int? = scope_id;
        while let id: int = current {
            if (id == ancestor_id) {
                return true;
            }
            current = self.scopes[id].parent;
        }
        false
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::resolve_path_expr @ d9be6853b
    // Record how the path's first segment reads here. A path source wrote
    // starts at a binding in scope, else at the package it names or a plain
    // name (`path_head`). A path the compiler wrote names a language package by
    // identity or an item of this namespace, whatever the scope binds
    // (`compiler_path_head`).
    function resolve_path_expr(
        self,
        expr_id: int,
        path: root.base.Path,
        use_scope: int,
        use_offset: int,
    ) -> void throws never {
        let root_name = path.segments.at(0) ?? baml.sys.panic("paths are never empty");
        let resolution: PathResolution = match (path.origin) {
            root.base.PathOrigin.Compiler => {
                PathResolutionItem { value: compiler_path_head(self.db, path.segments) }
            },
            root.base.PathOrigin.Written => {
                match (self.visible_binding_at(use_scope, use_offset, root_name)) {
                    let binding: BindingId => PathResolutionLocal { value: binding },
                    null => {
                        let own = self.db.file(self.file).root;
                        PathResolutionItem {
                            value: path_head(self.db, own, self.namespace_path, path.segments),
                        }
                    },
                }
            },
        };
        let key = self.current_expr_metadata_key(expr_id);
        self.path_resolutions.push((key, resolution));
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::record_path_root_reference @ d9be6853b
    function record_path_root_reference(
        self,
        root_name: string,
        use_scope: int,
        use_offset: int,
    ) -> void throws never {
        self.path_root_references.push(
            PathRootReference {
                name: root_name,
                use_scope: use_scope,
                use_offset: use_offset,
                owner_lambda: self.lambda_stack.at(self.lambda_stack.length() - 1),
            },
        );
    }

    // ── Item lowering ──

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_item @ d9be6853b
    function lower_item(self, item: root.ast.Item) -> void throws never {
        match (item) {
            let i: root.ast.ItemFunction => {
                self.lower_function(i.value);
            },
            let i: root.ast.ItemClass => self.lower_class(i.value),
            let i: root.ast.ItemEnum => self.lower_enum(i.value),
            let i: root.ast.ItemTypeAlias => self.lower_type_alias(i.value),
            let i: root.ast.ItemLet => self.lower_let(i.value),
            let i: root.ast.ItemInterface => self.lower_interface(i.value),
            let i: root.ast.ItemImplementsFor => self.lower_implements_for(i.value),
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_function @ d9be6853b
    function lower_function(self, f: root.ast.FunctionDef) -> int throws never {
        reject_attributes(f.attributes, root.base.AttributePosition.Function, self.diagnostics);
        let local_id = self.item_tree.alloc_function(f);
        let loc = self.db.function_locs.intern(self.file, local_id);
        self.reject_root_generics(f.generic_params);

        // Only a function outside a class contributes a top-level symbol:
        // methods belong to the class scope, not the package namespace.
        if (self.class_depth == 0) {
            self.reject_root_name(f.name, f.name_span);
            self.value_contributions.push(
                (
                    f.name,
                    Contribution {
                        name_span: f.name_span,
                        definition: DefinitionFunction { value: loc },
                    },
                ),
            );
        }

        self.push_scope(ScopeKind.Function, f.name, f.span);
        let scope_id = self.current_scope_id();
        self.record_scope_owner(scope_id, ItemScopeOwnerFunction { value: local_id });

        self.register_params(scope_id, f.params);
        self.emit_duplicate_param_diagnostics(f.params);
        self.walk_parameter_defaults(f.params, f.defaults);

        if let body: root.ast.FunctionBodyDefExpr = f.body {
            self.walk_expr_body(body.v0, body.v1);
        }

        self.pop_scope();
        local_id
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_class @ d9be6853b
    function lower_class(self, c: root.ast.ClassDef) -> void throws never {
        let attrs = lower_attributes(c.attributes, ClassAttrs.default_(), self.diagnostics);
        let field_attrs = c.fields.map((f) -> {
            lower_attributes(f.attributes, ClassFieldAttrs.default_(), self.diagnostics)
        });
        let fields = zip(c.fields, field_attrs);
        check_serialized_keys(
            fields.map((pair) -> {
                let (let f, let field_attr) = pair;
                SerializedMember {
                    name: f.name,
                    name_span: f.name_span,
                    alias: field_attr.schema.alias,
                    skip: field_attr.skip,
                }
            }),
            SerializedKeyContainer.Class,
            self.diagnostics,
        );
        // JSON's keys, under declared names and under aliased ones. A field
        // holding the object's keys has no key of its own.
        if (
            field_attrs.some((a) -> {
                a.json_rename != null
            })
        ) {
            for (let aliased in [false, true]) {
                let keyed = fields.filter((pair) -> {
                    !pair.1.json_flatten && !pair.1.json_fallback
                });
                check_serialized_keys(
                    keyed.map((pair) -> {
                        let (let f, let field_attr) = pair;
                        SerializedMember {
                            name: f.name,
                            name_span: f.name_span,
                            alias: json_key(field_attr.json_rename, field_attr.schema.alias, aliased),
                            skip: aliased && field_attr.skip,
                        }
                    }),
                    SerializedKeyContainer.Class,
                    self.diagnostics,
                );
            }
        }
        let local_id = self.item_tree.alloc_class(c, attrs, field_attrs);
        self.last_class = local_id;
        let loc = self.db.class_locs.intern(self.file, local_id);
        self.reject_root_name(c.name, c.name_span);
        self.reject_root_generics(c.generic_params);
        self.type_contributions.push(
            (
                c.name,
                Contribution { name_span: c.name_span, definition: DefinitionClass { value: loc } },
            ),
        );

        self.push_scope(ScopeKind.Class, c.name, c.span);
        let class_scope = self.current_scope_id();
        self.record_scope_owner(class_scope, ItemScopeOwnerClass { value: local_id });
        self.check_class_members(c);

        // Walk class methods inside the class scope, so they aren't contributed
        // as top-level symbols. `methods` holds ONLY the class-level methods: an
        // in-body `implements I { ... }` block is its own item, so its methods
        // live on the `ImplBlock` and resolve through the impl tier.
        self.class_depth += 1;
        let method_ids = c.methods.map((m) -> {
            self.lower_function(m)
        });
        self.class_depth -= 1;

        self.item_tree.set_class_methods(local_id, method_ids);
        self.pop_scope();
    }

    // port: the member checks of builder.rs::SemanticIndexBuilder::lower_class.
    // Unified per-scope duplicate detection: fields and methods share one
    // name map, so cross-kind collisions are caught too.
    function check_class_members(self, c: root.ast.ClassDef) -> void throws never {
        let seen: map<string, MemberSite[]> = {};
        for (let field in c.fields) {
            seen.get_or_insert(field.name, []).push(
                MemberSite { range: field.name_span, kind: DefinitionKind.Field },
            );
        }
        for (let method in c.methods) {
            // `to_string` / `to_json` / `from_json` are not magic methods: each
            // must come from implementing `baml.ToString` / `baml.ToJson` /
            // `baml.FromJson`, never be declared directly on the class. (Methods
            // of an `implements I { ... }` block are the impl's, not `methods`.)
            let span = method.name_span;
            let magic_method: Hir2Diagnostic? = match (method.name) {
                "to_string" => {
                    Hir2DiagnosticToStringMustImplementInterface { class_name: c.name, span: span }
                },
                "to_json" => {
                    Hir2DiagnosticToJsonMustImplementInterface { class_name: c.name, span: span }
                },
                "from_json" => {
                    Hir2DiagnosticFromJsonMustImplementInterface { class_name: c.name, span: span }
                },
                _ => null,
            };
            root.base.push_some(self.diagnostics, magic_method);
            seen.get_or_insert(method.name, []).push(
                MemberSite { range: span, kind: DefinitionKind.Method },
            );
        }
        self.emit_duplicate_diagnostics(seen);
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_implements_for @ d9be6853b
    // Lower an `implements` block, in either spelling: the AST has already
    // given an in-body block the class's generics and the class as its
    // for-target, so one path serves both.
    function lower_implements_for(self, imp: root.ast.ImplementsForDef) -> void throws never {
        self.class_depth += 1;
        self.reject_root_generics(imp.generic_params);
        // A class-like scope named after the for-target's root, so TIR can
        // resolve `self` and the block's type variables in method bodies.
        let scope_name = match (imp.for_target.kind) {
            let k: root.ast.TypeExprKindPath => k.path.segments.at(0),
            _ => null,
        };
        self.push_scope(ScopeKind.Class, scope_name, imp.span);
        let impl_scope = self.current_scope_id();
        let method_ids = imp.methods.map((method) -> {
            let fid = self.lower_function(method);
            // BEP-044: remember which interface this method came from so
            // `default.<name>()` calls in the body resolve back to the
            // interface's default function.
            self.item_tree.record_method_interface_target(
                fid,
                imp.interface_target,
                imp.associated_type_bindings,
            );
            fid
        });
        self.pop_scope();
        self.class_depth -= 1;
        let iface_head = impl_head_name(imp.interface_target);
        let for_head = impl_head_name(imp.for_target);
        let owner = match (imp.origin) {
            root.ast.ImplOrigin.InBody => self.last_class,
            root.ast.ImplOrigin.OutOfBody => null,
        };
        let block = ImplBlock {
            for_target: imp.for_target,
            generics: imp.generic_params,
            origin: imp.origin,
            owner: owner,
            interface_target: imp.interface_target,
            field_links: imp.field_links.map((link) -> {
                InterfaceFieldLink.from_ast(link)
            }),
            associated_type_bindings: imp.associated_type_bindings,
            methods: method_ids,
            span: imp.span,
            docstring: imp.docstring,
        };
        let impl_id = self.item_tree.alloc_impl(iface_head, for_head, block);
        self.record_scope_owner(impl_scope, ItemScopeOwnerImpl { value: impl_id });
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_interface @ d9be6853b
    // Lower an `interface I { ... }` declaration (BEP-044). Mirrors
    // `lower_class`: contributes the name to the type namespace, pushes a
    // member scope, walks default-method bodies so their expressions get scope
    // coverage, and stores everything in the item tree.
    function lower_interface(self, i: root.ast.InterfaceDef) -> void throws never {
        // The interface's local id is allocated only after its default methods,
        // so their function ids can be recorded on it.
        self.push_scope(ScopeKind.Class, i.name, i.span);
        let interface_scope = self.current_scope_id();

        // BEP-044: default methods are lowered inside the interface's
        // `Class`-kind scope so the semantic index reports the interface as
        // their enclosing type; otherwise MIR can't resolve `self` back to it.
        self.class_depth += 1;
        let method_ids = i.default_methods.map((m) -> {
            self.lower_function(m)
        });
        self.class_depth -= 1;
        // Required signatures are the SAME item kind, just bodyless: no body
        // walk, but the names a signature declares are checked like a body's.
        for (let m in i.required_methods) {
            reject_attributes(m.attributes, root.base.AttributePosition.Function, self.diagnostics);
            self.reject_root_generics(m.generic_params);
            for (let param in m.params) {
                self.reject_root_name(param.name, param.name_span);
            }
            method_ids.push(self.item_tree.alloc_function_signature(m));
        }

        // An interface is a contract, not a data type: neither it nor its
        // fields take attributes.
        reject_attributes(i.attributes, root.base.AttributePosition.Interface, self.diagnostics);
        for (let field in i.fields) {
            reject_attributes(field.attributes, root.base.AttributePosition.InterfaceField, self.diagnostics);
        }

        let local_id = self.item_tree.alloc_interface(i, method_ids);
        self.record_scope_owner(interface_scope, ItemScopeOwnerInterface { value: local_id });
        let loc = self.db.interface_locs.intern(self.file, local_id);
        self.reject_root_name(i.name, i.name_span);
        self.reject_root_generics(i.generic_params);
        self.type_contributions.push(
            (
                i.name,
                Contribution {
                    name_span: i.name_span,
                    definition: DefinitionInterface { value: loc },
                },
            ),
        );

        // Member duplicate detection: fields, associated types and methods share
        // one namespace (just like classes).
        let seen: map<string, MemberSite[]> = {};
        for (let field in i.fields) {
            seen.get_or_insert(field.name, []).push(
                MemberSite { range: field.name_span, kind: DefinitionKind.Field },
            );
        }
        for (let assoc in i.associated_types) {
            seen.get_or_insert(assoc.name, []).push(
                MemberSite { range: assoc.name_span, kind: DefinitionKind.AssociatedType },
            );
        }
        for (let sig in i.required_methods) {
            seen.get_or_insert(sig.name, []).push(
                MemberSite { range: sig.name_span, kind: DefinitionKind.Method },
            );
        }
        for (let m in i.default_methods) {
            seen.get_or_insert(m.name, []).push(
                MemberSite { range: m.name_span, kind: DefinitionKind.Method },
            );
        }
        self.emit_duplicate_diagnostics(seen);

        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_enum @ d9be6853b
    function lower_enum(self, e: root.ast.EnumDef) -> void throws never {
        let attrs = lower_attributes(e.attributes, EnumAttrs.default_(), self.diagnostics);
        let variant_attrs = e.variants.map((v) -> {
            lower_attributes(v.attributes, EnumVariantAttrs.default_(), self.diagnostics)
        });
        let variants = zip(e.variants, variant_attrs);
        check_serialized_keys(
            variants.map((pair) -> {
                let (let v, let variant_attr) = pair;
                SerializedMember {
                    name: v.name,
                    name_span: v.name_span,
                    alias: variant_attr.schema.alias,
                    skip: variant_attr.skip,
                }
            }),
            SerializedKeyContainer.Enum,
            self.diagnostics,
        );
        if (
            variant_attrs.some((a) -> {
                a.json_rename != null
            })
        ) {
            for (let aliased in [false, true]) {
                check_serialized_keys(
                    variants.map((pair) -> {
                        let (let v, let variant_attr) = pair;
                        SerializedMember {
                            name: v.name,
                            name_span: v.name_span,
                            alias: json_key(variant_attr.json_rename, variant_attr.schema.alias, aliased),
                            skip: aliased && variant_attr.skip,
                        }
                    }),
                    SerializedKeyContainer.Enum,
                    self.diagnostics,
                );
            }
        }
        let local_id = self.item_tree.alloc_enum(e, attrs, variant_attrs);
        let loc = self.db.enum_locs.intern(self.file, local_id);
        self.reject_root_name(e.name, e.name_span);
        self.type_contributions.push(
            (
                e.name,
                Contribution { name_span: e.name_span, definition: DefinitionEnum { value: loc } },
            ),
        );

        self.push_scope(ScopeKind.Enum, e.name, e.span);
        let scope = self.current_scope_id();
        self.record_scope_owner(scope, ItemScopeOwnerEnum { value: local_id });

        let seen: map<string, MemberSite[]> = {};
        for (let variant in e.variants) {
            seen.get_or_insert(variant.name, []).push(
                MemberSite { range: variant.name_span, kind: DefinitionKind.Variant },
            );
        }
        self.emit_duplicate_diagnostics(seen);

        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_type_alias @ d9be6853b
    function lower_type_alias(self, ta: root.ast.TypeAliasDef) -> void throws never {
        let local_id = self.item_tree.alloc_type_alias(ta);
        let loc = self.db.type_alias_locs.intern(self.file, local_id);
        self.reject_root_name(ta.name, ta.name_span);
        self.type_contributions.push(
            (
                ta.name,
                Contribution {
                    name_span: ta.name_span,
                    definition: DefinitionTypeAlias { value: loc },
                },
            ),
        );

        self.push_scope(ScopeKind.TypeAlias, ta.name, ta.span);
        let scope = self.current_scope_id();
        self.record_scope_owner(scope, ItemScopeOwnerTypeAlias { value: local_id });
        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::lower_let @ d9be6853b
    function lower_let(self, l: root.ast.LetDef) -> void throws never {
        let local_id = self.item_tree.alloc_let(l);
        let loc = self.db.let_locs.intern(self.file, local_id);
        self.reject_root_name(l.name, l.name_span);
        self.value_contributions.push(
            (
                l.name,
                Contribution { name_span: l.name_span, definition: DefinitionLet { value: loc } },
            ),
        );

        self.push_scope(ScopeKind.Let, l.name, l.span);
        let scope = self.current_scope_id();
        self.record_scope_owner(scope, ItemScopeOwnerLet { value: local_id });
        if let initializer: (root.ast.ExprBody, root.ast.AstSourceMap) = l.initializer {
            self.walk_expr_body(initializer.0, initializer.1);
        }
        self.pop_scope();
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::validate_phase1_builtin_contracts @ d9be6853b
    function validate_phase1_builtin_contracts(self, items: root.ast.Item[]) -> void throws never {
        let is_builtin_file = self.db.file(self.file).path.starts_with("<builtin>/");
        for (let item in items) {
            self.validate_item_phase1(item, is_builtin_file);
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::validate_item_phase1 @ d9be6853b
    function validate_item_phase1(
        self,
        item: root.ast.Item,
        is_builtin_file: bool,
    ) -> void throws never {
        match (item) {
            let i: root.ast.ItemFunction => self.validate_function_phase1(i.value, is_builtin_file),
            let i: root.ast.ItemClass => {
                for (let field in i.value.fields) {
                    let type_expr = field.type_expr;
                    self.validate_type_expr_phase1(type_expr, type_expr.span, is_builtin_file);
                }
                for (let method in i.value.methods) {
                    self.validate_function_phase1(method, is_builtin_file);
                }
            },
            let i: root.ast.ItemImplementsFor => {
                for (let method in i.value.methods) {
                    self.validate_function_phase1(method, is_builtin_file);
                }
            },
            let i: root.ast.ItemTypeAlias => {
                if let type_expr: root.ast.TypeExpr = i.value.type_expr {
                    self.validate_type_expr_phase1(type_expr, type_expr.span, is_builtin_file);
                }
            },
            _ => {},
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::validate_function_phase1 @ d9be6853b
    function validate_function_phase1(
        self,
        function_: root.ast.FunctionDef,
        is_builtin_file: bool,
    ) -> void throws never {
        let own_kind = self.db.source_root(self.db.file(self.file).root).kind;
        if (
            function_.metadata.explicit_trace_passthrough
                && own_kind != root.base.SourceRootKind.Stdlib
        ) {
            self.diagnostics.push(
                Hir2DiagnosticBuiltinOnlySyntax {
                    feature: "//baml:trace_passthrough",
                    span: function_.span,
                },
            );
        }
        let signature_types = function_.params.filter_map((param) -> {
            param.type_expr
        });
        root.base.push_some(signature_types, function_.return_type);
        root.base.push_some(signature_types, function_.throws_);
        for (let type_expr in signature_types) {
            self.validate_type_expr_phase1(type_expr, type_expr.span, is_builtin_file);
        }

        if let builtin: root.ast.FunctionBodyDefBuiltin = function_.body {
            if (!is_builtin_file) {
                let feature = match (builtin.value) {
                    root.ast.BuiltinKind.Vm => "$rust_function",
                    root.ast.BuiltinKind.Io => "$rust_io_function",
                    root.ast.BuiltinKind.Intrinsic => "$compiler_intrinsic",
                    root.ast.BuiltinKind.AwaitAny => "$await_any",
                    root.ast.BuiltinKind.Spawn => "$spawn",
                };
                self.diagnostics.push(
                    Hir2DiagnosticBuiltinOnlySyntax { feature: feature, span: function_.span },
                );
                return;
            }

            if let throws_: root.ast.TypeExpr = function_.throws_ {
                let invalid: string[] = [];
                let generic_param_names = function_.generic_params.map((param) -> {
                    param.name
                });
                SemanticIndexBuilder.collect_invalid_builtin_throw_types(
                    throws_,
                    generic_param_names,
                    invalid,
                );
                if (invalid) {
                    self.diagnostics.push(
                        Hir2DiagnosticDiagnosticMessage {
                            diagnostic_id: root.diagnostics.THROWS_CONTRACT_VIOLATION,
                            message: `Host-bound builtin \`${function_.name}\` may only declare \`throws\` using builtin error types and function generic vars; invalid entries: ${invalid.join(", ")}`,
                            span: throws_.span,
                        },
                    );
                }
            }
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::validate_type_expr_phase1 @ d9be6853b
    // `$rust_type` outside a builtin stdlib file.
    // divergence?: the Rust doc comment on this function describes the
    // serialized-key check (`check_serialized_keys`), not what it does.
    function validate_type_expr_phase1(
        self,
        type_expr: root.ast.TypeExpr,
        span: root.syntax.TextRange,
        is_builtin_file: bool,
    ) -> void throws never {
        if (is_builtin_file) {
            return;
        }
        if (SemanticIndexBuilder.type_expr_contains_rust(type_expr)) {
            self.diagnostics.push(
                Hir2DiagnosticBuiltinOnlySyntax { feature: "$rust_type", span: span },
            );
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::type_expr_contains_rust @ d9be6853b
    function type_expr_contains_rust(type_expr: root.ast.TypeExpr) -> bool throws never {
        let any = (types: root.ast.TypeExpr[]) -> bool {
            types.some((t) -> {
                SemanticIndexBuilder.type_expr_contains_rust(t)
            })
        };
        match (type_expr.kind) {
            root.ast.TypeExprKindRust => true,
            let k: root.ast.TypeExprKindOptional => any([k.inner]),
            let k: root.ast.TypeExprKindList => any([k.inner]),
            let k: root.ast.TypeExprKindMap => any([k.key, k.value]),
            let k: root.ast.TypeExprKindUnion => any(k.variants),
            let k: root.ast.TypeExprKindTuple => any(k.elements),
            let k: root.ast.TypeExprKindFunction => {
                let types = k.params.map((param) -> {
                    param.ty
                });
                types.push(k.ret);
                root.base.push_some(types, k.throws_);
                any(types)
            },
            let k: root.ast.TypeExprKindAssociatedTypeProjection => {
                let types = [k.base];
                root.base.push_some(types, k.interface_);
                any(types)
            },
            let k: root.ast.TypeExprKindPath => {
                any(
                    k.generic_args.concat(
                        k.associated_type_bindings.map((binding) -> {
                            binding.ty
                        }),
                    ),
                )
            },
            root.ast.TypeExprKindInt
                | root.ast.TypeExprKindBigint
                | root.ast.TypeExprKindFloat
                | root.ast.TypeExprKindString
                | root.ast.TypeExprKindBool
                | root.ast.TypeExprKindNull
                | root.ast.TypeExprKindNever
                | root.ast.TypeExprKindUint8Array
                | root.ast.TypeExprKindMedia
                | root.ast.TypeExprKindLiteral
                | root.ast.TypeExprKindUnknown
                | root.ast.TypeExprKindType
                | root.ast.TypeExprKindError
                | root.ast.TypeExprKindMissing
                | root.ast.TypeExprKindInfer =>
            {
                false
            },
        }
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::collect_invalid_builtin_throw_types @ d9be6853b
    function collect_invalid_builtin_throw_types(
        type_expr: root.ast.TypeExpr,
        allowed_generic_params: string[],
        invalid: string[],
    ) -> void throws never {
        match (type_expr.kind) {
            let k: root.ast.TypeExprKindPath => {
                if (!SemanticIndexBuilder.is_allowed_builtin_throw_path(k, allowed_generic_params)) {
                    invalid.push(SemanticIndexBuilder.render_type_expr(type_expr));
                }
            },
            let k: root.ast.TypeExprKindUnion => {
                for (let ty in k.variants) {
                    SemanticIndexBuilder.collect_invalid_builtin_throw_types(
                        ty,
                        allowed_generic_params,
                        invalid,
                    );
                }
            },
            // A projection off one of the function's own generic params, e.g.
            // `T.Error` for `<T extends Iface>`. The concrete error is the
            // implementor's associated type, resolved at the call site; the host fn
            // just propagates whatever the dispatched method throws (the declared
            // `throws` is erased for builtins), so this is sound. Any other
            // projection falls through to the catch-all.
            let k: root.ast.TypeExprKindAssociatedTypeProjection => {
                let base_kind = k.base.kind;
                let off_generic_param = base_kind is root.ast.TypeExprKindPath
                    && base_kind.generic_args.length() == 0
                    && base_kind.path.segments.length() == 1
                    && allowed_generic_params.includes(base_kind.path.segments[0]);
                if (!off_generic_param) {
                    invalid.push(SemanticIndexBuilder.render_type_expr(type_expr));
                }
            },
            // `throws never` and `throws unknown` are the two explicit effect
            // bounds, both valid for host-bound functions; the latter is needed by
            // continuations that execute user bytecode.
            root.ast.TypeExprKindNever | root.ast.TypeExprKindUnknown => {},
            _ => {
                invalid.push(SemanticIndexBuilder.render_type_expr(type_expr));
            },
        }
    }

    // port: the `TypeExprKind::Path` arm of builder.rs::SemanticIndexBuilder::collect_invalid_builtin_throw_types.
    // Whether a `throws` path of a host-bound builtin is allowed.
    function is_allowed_builtin_throw_path(
        k: root.ast.TypeExprKindPath,
        allowed_generic_params: string[],
    ) -> bool throws never {
        let path = k.path.segments;
        let no_args = k.generic_args.length() == 0;
        let first = path.at(0) ?? "";
        let second = path.at(1) ?? "";
        // `baml.errors.*`, `root.errors.*`, `baml.json.*`, and BEP-066's
        // `reflect.errors.*` (fully qualified). The `baml.json` error types are
        // stdlib error types just like `baml.errors` ones.
        let is_core_builtin_error = path.length() >= 3
            && (first == "baml" || first == "root")
            && (second == "errors" || second == "json");
        let is_reflection_error = path.length() >= 3 && first == "reflect" && second == "errors";
        let is_builtin_error = is_core_builtin_error || is_reflection_error;
        // A single-segment class name (`ParseError`) in a builtin file: the class
        // resolves in the current namespace and TIR type-checks it, so builtins
        // can throw classes of their own stdlib namespace without the full path.
        let is_builtin_class_ref = path.length() == 1 && no_args && (first.at(0)?.is_uppercase() ?? false);
        let is_allowed_generic = path.length() == 1
            && no_args
            && !is_builtin_class_ref
            && allowed_generic_params.includes(first);
        // A projection off one of the function's own generic params (`T.Error`
        // for `<T extends Iface>`), which parses as a dotted path at this phase.
        // The concrete error is the implementor's associated type, resolved at
        // the call site.
        let is_generic_param_projection = path.length() >= 2 && no_args && allowed_generic_params.includes(first);
        is_builtin_error
            || is_builtin_class_ref
            || is_allowed_generic
            || is_generic_param_projection
    }

    // port: baml_compiler2_hir/src/builder.rs::SemanticIndexBuilder::render_type_expr @ d9be6853b
    function render_type_expr(type_expr: root.ast.TypeExpr) -> string throws never {
        let render = (t: root.ast.TypeExpr) -> string {
            SemanticIndexBuilder.render_type_expr(t)
        };
        match (type_expr.kind) {
            let k: root.ast.TypeExprKindPath => k.path.segments.join("."),
            root.ast.TypeExprKindAssociatedTypeProjection => type_expr.to_string(),
            root.ast.TypeExprKindInt => "int",
            root.ast.TypeExprKindBigint => "bigint",
            root.ast.TypeExprKindFloat => "float",
            root.ast.TypeExprKindString => "string",
            root.ast.TypeExprKindBool => "bool",
            root.ast.TypeExprKindNull => "null",
            root.ast.TypeExprKindNever => "never",
            root.ast.TypeExprKindUint8Array => "uint8array",
            let k: root.ast.TypeExprKindMedia => root.base.media_kind_display(k.kind),
            let k: root.ast.TypeExprKindOptional => `${render(k.inner)}?`,
            let k: root.ast.TypeExprKindList => `${render(k.inner)}[]`,
            let k: root.ast.TypeExprKindMap => `map<${render(k.key)}, ${render(k.value)}>`,
            let k: root.ast.TypeExprKindUnion => k.variants.map(render).join(" | "),
            let k: root.ast.TypeExprKindTuple => {
                let trailing = if (k.elements.length() == 1) {
                    ","
                } else {
                    ""
                };
                `(${k.elements.map(render).join(", ")}${trailing})`
            },
            let k: root.ast.TypeExprKindLiteral => root.base.literal_display(k.value),
            let k: root.ast.TypeExprKindFunction => {
                let throws_suffix = if let throws_: root.ast.TypeExpr = k.throws_ {
                    ` throws ${render(throws_)}`
                } else {
                    ""
                };
                let params = k.params.map((param) -> {
                    if let name: string = param.name {
                        `${name}: ${render(param.ty)}`
                    } else {
                        render(param.ty)
                    }
                });
                `(${params.join(", ")}) -> ${render(k.ret)}${throws_suffix}`
            },
            root.ast.TypeExprKindUnknown => "unknown",
            root.ast.TypeExprKindType => "reflect.Type",
            root.ast.TypeExprKindRust => "$rust_type",
            root.ast.TypeExprKindError => "<error>",
            root.ast.TypeExprKindMissing => "<unknown>",
            root.ast.TypeExprKindInfer => "_",
        }
    }
}

// needs foundation: `Path::file_name` on a `/`-separated path: the last
// component, ignoring a trailing `/`; null when there is none or it is `..`.
function file_name(path: string) -> string? throws never {
    let components = path.split("/").filter((c) -> {
        c != "" && c != "."
    });
    let last = components.at(components.length() - 1)
        ?? return null;
    if (last == "..") {
        return null;
    }
    last
}

// needs foundation: `Iterator::zip` over two arrays, to the shorter length.
function zip<A, B>(left: A[], right: B[]) -> (A, B)[] throws never {
    let pairs: (A, B)[] = [];
    let i = 0;
    while (i < left.length() && i < right.length()) {
        pairs.push((left[i], right[i]));
        i += 1;
    }
    pairs
}
