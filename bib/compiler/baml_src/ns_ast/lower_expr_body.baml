// port: baml_compiler2_ast/src/lower_expr_body.rs @ d9be6853b
//
// The body-lowering context and the desugarings that build arena nodes
// programmatically: `LoweringContext` (arenas plus the parallel
// `AstSourceMap`), the LLM `@spec` companion bodies, the test registrar
// context, and the tagged-template elaboration. The tree readers live in
// `lower_tree`.

// port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext @ d9be6853b
class LoweringContext {
    exprs: Expr[],
    stmts: Stmt[],
    patterns: Pattern[],
    match_arms: MatchArm[],
    catch_arms: CatchArm[],
    type_annotations: TypeExpr[],
    // Parallel span storage
    source_map: AstSourceMap,
    // When set, `TEST_EXPR_DEF` and `TESTSET_DEF` nodes met during block
    // lowering become `<var>.register_test(...)` / `<var>.register_test_set(...)`
    // calls on this variable: dynamic tests inside `for`/`if` in a testset body.
    testset_collector_var: string?,
    // Diagnostics accumulated during lowering.
    diags: LoweringDiagnostic[],
    // Environment variable references (`env.X`) found during lowering.
    env_var_refs: EnvVarRef[],
    // Expressions that contain unwrapped `?.` operators and need an
    // `OptionalChain` wrapper. Propagated up through chain-continuing nodes.
    needs_chain_wrap: map<int, bool>,
    // When set, every node allocated through `alloc_expr`/`alloc_stmt`/
    // `alloc_pattern` is recorded as compiler-synthesized in the source map.
    // Scoped on around desugarings; consumed by inlay hints.
    synthesizing: bool,
    // A file-scope binding's introducer keyword, which its caller checks
    // itself: the body-level `const` warning skips this one token.
    file_scope_introducer: root.syntax.TextRange?,
    // See `ExprBody.tag_values`.
    tag_values: int[],

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::new @ d9be6853b
    function new() -> LoweringContext throws never {
        LoweringContext {
            exprs: [],
            stmts: [],
            patterns: [],
            match_arms: [],
            catch_arms: [],
            type_annotations: [],
            source_map: AstSourceMap.new(),
            testset_collector_var: null,
            diags: [],
            env_var_refs: [],
            needs_chain_wrap: {},
            synthesizing: false,
            file_scope_introducer: null,
            tag_values: [],
        }
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::warn_const_introducer @ d9be6853b
    function warn_const_introducer(self, span: root.syntax.TextRange) -> void throws never {
        self.diags.push(LoweringDiagnosticConstBindingIntroducer { span: span });
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::alloc_expr @ d9be6853b
    function alloc_expr(self, expr: Expr, range: root.syntax.TextRange) -> int throws never {
        let lambda_parameter_spans = match (expr) {
            let lambda: ExprLambda => {
                lambda.value.params.map((param) -> {
                    param.name_span
                })
            },
            _ => null,
        };
        let id = self.exprs.length();
        self.exprs.push(expr);
        self.source_map.expr_spans.push(range);
        if (lambda_parameter_spans != null) {
            self.source_map.lambda_parameter_spans.set(id, lambda_parameter_spans);
        }
        if (self.synthesizing) {
            self.source_map.synthetic_exprs.set(id, true);
        }
        id
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::alloc_stmt @ d9be6853b
    function alloc_stmt(self, stmt: Stmt, range: root.syntax.TextRange) -> int throws never {
        let id = self.stmts.length();
        self.stmts.push(stmt);
        self.source_map.stmt_spans.push(range);
        if (self.synthesizing) {
            self.source_map.synthetic_stmts.set(id, true);
        }
        id
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::alloc_pattern @ d9be6853b
    function alloc_pattern(
        self,
        pattern: Pattern,
        range: root.syntax.TextRange,
    ) -> int throws never {
        let id = self.patterns.length();
        self.patterns.push(pattern);
        self.source_map.pattern_spans.push(range);
        if (self.synthesizing) {
            self.source_map.synthetic_patterns.set(id, true);
        }
        id
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::alloc_match_arm @ d9be6853b
    function alloc_match_arm(
        self,
        arm: MatchArm,
        range: root.syntax.TextRange,
    ) -> int throws never {
        let id = self.match_arms.length();
        self.match_arms.push(arm);
        self.source_map.match_arm_spans.push(range);
        id
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::alloc_catch_arm @ d9be6853b
    function alloc_catch_arm(
        self,
        arm: CatchArm,
        range: root.syntax.TextRange,
    ) -> int throws never {
        let id = self.catch_arms.length();
        self.catch_arms.push(arm);
        self.source_map.catch_arm_spans.push(range);
        id
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::alloc_type_annot @ d9be6853b
    function alloc_type_annot(
        self,
        ty: TypeExpr,
        range: root.syntax.TextRange,
    ) -> int throws never {
        let id = self.type_annotations.length();
        self.type_annotations.push(ty);
        self.source_map.type_annotation_spans.push(range);
        id
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::finish @ d9be6853b
    function finish(
        self,
        root_expr: int?,
    ) -> (ExprBody, AstSourceMap, LoweringDiagnostic[], EnvVarRef[]) throws never {
        let body = ExprBody {
            exprs: self.exprs,
            stmts: self.stmts,
            patterns: self.patterns,
            match_arms: self.match_arms,
            catch_arms: self.catch_arms,
            type_annotations: self.type_annotations,
            tag_values: self.tag_values,
            root_expr: root_expr,
        };
        (body, self.source_map, self.diags, self.env_var_refs)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::is_assignable_place @ d9be6853b
    // Whether `expr` denotes a storage location an assignment can write
    // through. `Missing` counts as assignable so a syntax error already
    // reported for the target does not cascade into a second diagnostic.
    function is_assignable_place(self, expr: int) -> bool throws never {
        match (self.exprs[expr]) {
            ExprPath
                | ExprMemberAccess
                | ExprIndex
                | ExprOptionalMemberAccess
                | ExprOptionalIndex
                | ExprMissing =>
            {
                true
            },
            let chain: ExprOptionalChain => self.is_assignable_place(chain.expr),
            _ => false,
        }
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::complete_client_resolve_call @ d9be6853b
    // `ai.clients.resolve(selector)` is compiler-assisted: only the compiler
    // knows every provider, so at each call site it appends the provider table
    // (a constructor lambda and the list of prefixes it knows, both from
    // `SHORTHAND_PROVIDERS`). A call that already passes them is left alone.
    // BUG (upstream): a written call is recognized by its spelling before
    // resolution, so a local `ai` whose `clients` field has a `resolve` method
    // is completed too. The recognition belongs after HIR reads the path head.
    function complete_client_resolve_call(
        self,
        callee: int,
        args: CallArg[],
        span: root.syntax.TextRange,
    ) -> CallArg[] throws never {
        let is_resolve = match (self.exprs[callee]) {
            let path: ExprPath => path.value.segments == ["ai", "clients", "resolve"],
            _ => false,
        };
        if (is_resolve && args.length() == 1) {
            let providers = synthesize_shorthand_providers(self, span);
            args.push(CallArg.positional(providers));
            let prefixes = synthesize_shorthand_prefixes(self, span);
            args.push(CallArg.positional(prefixes));
        }
        args
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::finalize_call_args @ d9be6853b
    function finalize_call_args(
        lowered_args: (CallArg, root.syntax.TextRange?)[],
    ) -> (CallArg[], (int, root.syntax.TextRange)[]) throws never {
        let args: CallArg[] = [];
        let label_spans: (int, root.syntax.TextRange)[] = [];
        for (let lowered in lowered_args) {
            let (let arg, let label_span) = lowered;
            if (label_span != null) {
                label_spans.push((arg.expr, label_span));
            }
            args.push(arg);
        }
        (args, label_spans)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::record_call_arg_label_spans @ d9be6853b
    // Keyed call id, then the argument's expression id (Rust's `(call, arg)` key).
    function record_call_arg_label_spans(
        self,
        call_id: int,
        label_spans: (int, root.syntax.TextRange)[],
    ) -> void throws never {
        for (let entry in label_spans) {
            let (let arg_expr, let label_span) = entry;
            let by_arg: map<int, root.syntax.TextRange> = self.source_map.call_arg_label_spans.get(call_id) ?? {};
            self.source_map.call_arg_label_spans.set(call_id, by_arg);
            by_arg.set(arg_expr, label_span);
        }
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_default_segments @ d9be6853b
    // The desugared realization of an untagged backtick template: a left-folded
    // `+` concatenation of the segments, each `${expr}` rendered through
    // `baml.String.from` (BEP §11), `${for}` lowered to an accumulator block and
    // `${if}` to a host if-chain. Reuses the already-lowered segments' ids.
    // BUG (upstream): `env.X` is recognized by the parser, so a binding named
    // `env` is legal but unusable; likewise `prompt` before a tagged template.
    function elaborate_default_segments(
        self,
        segments: TemplateSegment[],
        span: root.syntax.TextRange,
    ) -> int throws never {
        if (segments.length() == 0) {
            return self.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, span);
        }
        // Each segment is a value part (concatenated with `+`) or, for a
        // side-effect-only `${ let … }`, the raw statements it declares. Hoisting
        // those into one enclosing concat scope lets a `let` in one segment be
        // seen by a later `${…}` (BEP-049 §4 cross-site `let`).
        let parts: InterpPart[] = [];
        let any_stmts = false;
        for (let seg in segments) {
            let part: InterpPart = match (seg) {
                let text: TemplateSegmentText => {
                    InterpPartValue {
                        value: self.alloc_expr(
                            ExprLiteral { value: root.base.LiteralString { value: text.value } },
                            span,
                        ),
                    }
                },
                let interp: TemplateSegmentInterp => {
                    InterpPartValue { value: self.elaborate_default_interp(interp.value, span) }
                },
                let effect: TemplateSegmentEffect => InterpPartStmts { value: effect.stmts },
                let f: TemplateSegmentFor => {
                    InterpPartValue {
                        value: self.elaborate_default_for(f.binding, f.collection, f.body, span),
                    }
                },
                let f: TemplateSegmentCStyleFor => {
                    InterpPartValue {
                        value: self.elaborate_default_cstyle_for(f.init, f.cond, f.step, f.body, span),
                    }
                },
                let i: TemplateSegmentIf => {
                    InterpPartValue {
                        value: self.elaborate_default_if(i.branches, i.else_body, span),
                    }
                },
            };
            if (part is InterpPartStmts) {
                any_stmts = true;
            }
            parts.push(part);
        }

        // Fast path: nothing to hoist. The plain `+` fold keeps `Ty::Literal`
        // for a constant template, so BEP §9 constant folding still fires.
        if (!any_stmts) {
            let values = parts.map((p) -> {
                match (p) {
                    let v: InterpPartValue => v.value,
                    _ => baml.sys.panic("no Stmts parts when !any_stmts"),
                }
            });
            return values.slice(1, values.length()).reduce(
                (acc, next) -> {
                    self.alloc_expr(ExprBinary { op: BinaryOp.Add, lhs: acc, rhs: next }, span)
                },
                values[0],
            );
        }

        // Hoisting path: `{ let acc = ""; <…>; acc }`, each value part appending
        // `acc = acc + part` and each side-effect-only segment splicing its
        // statements in. The accumulator name leads with a space so no user
        // identifier can collide with it.
        let after_span = root.syntax.TextRange.empty(span.end);
        let acc_name = " __m3_concat";
        let acc_pat = self.alloc_pattern(PatternBind { name: acc_name, subpat: null }, span);
        let empty_init = self.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, span);
        let acc_let = self.alloc_stmt(
            StmtLet {
                pattern: acc_pat,
                initializer: empty_init,
                origin: LetOrigin.Source,
                else_branch: null,
            },
            span,
        );
        let block_stmts: int[] = [acc_let];
        for (let part in parts) {
            match (part) {
                let v: InterpPartValue => {
                    let acc_lhs = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
                    let acc_rhs = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
                    let concat = self.alloc_expr(
                        ExprBinary { op: BinaryOp.Add, lhs: acc_rhs, rhs: v.value },
                        after_span,
                    );
                    block_stmts.push(
                        self.alloc_stmt(StmtAssign { target: acc_lhs, value: concat }, after_span),
                    );
                },
                let s: InterpPartStmts => {
                    for (let stmt in s.value) {
                        block_stmts.push(stmt);
                    }
                },
            }
        }
        let acc_tail = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        self.alloc_expr(ExprBlock { stmts: block_stmts, tail_expr: acc_tail }, span)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_default_interp @ d9be6853b
    // Elaborate a `${expr}` for the untagged path: render it through
    // `baml.String.from(...)`, BAML's universal renderer (BEP-049 §11), named
    // by identity so a binding called `string` does not capture it.
    function elaborate_default_interp(
        self,
        inner: int,
        span: root.syntax.TextRange,
    ) -> int throws never {
        let callee = self.alloc_expr(
            ExprPath { value: root.base.Path.compiler(["baml", "String", "from"]) },
            span,
        );
        self.alloc_expr(
            ExprCall { callee: callee, type_args: [], args: [CallArg.positional(inner)] },
            span,
        )
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::unit_interp @ d9be6853b
    // The statements and tail of a `${…}` block that produces no value: it has
    // no tail, or its tail is a syntactically-unit expression (BEP-049 §4).
    function unit_interp(self, inner: int) -> (int[], int?)? throws never {
        match (self.exprs[inner]) {
            let block: ExprBlock => {
                let tail = block.tail_expr;
                if (tail == null || self.is_unit_tail(tail)) {
                    (block.stmts, tail)
                } else {
                    null
                }
            },
            _ => null,
        }
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::unit_interp_stmts @ d9be6853b
    // The statements of a `${…}` block that produces no value, its tail
    // included: the tail is checked against the unit type rather than
    // discarded. Null for an interpolation that has a value.
    function unit_interp_stmts(
        self,
        inner: int,
        span: root.syntax.TextRange,
    ) -> int[]? throws never {
        let (let block_stmts, let tail) = self.unit_interp(inner)
            ?? return null;
        // A copy: the block's own statement list stays as written.
        let stmts = block_stmts.slice(0, block_stmts.length());
        if (tail != null) {
            // The check is the compiler's, not something the user wrote.
            let prev_synth = self.synthesizing;
            self.synthesizing = true;
            stmts.push(self.unit_let(tail, span));
            self.synthesizing = prev_synth;
        }
        stmts
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::unit_let @ d9be6853b
    // `let _: null = <value>;`, binding a name no user identifier can spell:
    // `value` is checked against the unit type and dropped.
    function unit_let(self, value: int, span: root.syntax.TextRange) -> int throws never {
        let null_pat = self.alloc_pattern(
            PatternType { value: TypeExpr { kind: TypeExprKindNull {}, span: span } },
            span,
        );
        let pattern = self.alloc_pattern(PatternBind { name: " __unit", subpat: null_pat }, span);
        self.alloc_stmt(
            StmtLet {
                pattern: pattern,
                initializer: value,
                origin: LetOrigin.Source,
                else_branch: null,
            },
            span,
        )
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::is_unit_tail @ d9be6853b
    // Is `expr` syntactically unit-valued in a block's tail position? Only the
    // implicit-unit forms: an `if`/`if let` with no `else`, an `else if` chain
    // ending in one, or a nested block whose own tail is unit.
    function is_unit_tail(self, expr: int) -> bool throws never {
        let else_branch = match (self.exprs[expr]) {
            let e: ExprIf => e.else_branch,
            let e: ExprIfLet => e.else_branch,
            let block: ExprBlock => {
                let tail = block.tail_expr;
                return tail == null || self.is_unit_tail(tail);
            },
            _ => {
                return false;
            },
        };
        if (else_branch == null) {
            return true;
        }
        let else_is_if = match (self.exprs[else_branch]) {
            ExprIf | ExprIfLet => true,
            _ => false,
        };
        else_is_if && self.is_unit_tail(else_branch)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_default_for @ d9be6853b
    // `${for (p in c)}…${endfor}` to an accumulator block:
    // `{ let acc = ""; for (p in c) { acc = acc + <body>; } acc }`.
    function elaborate_default_for(
        self,
        binding: int,
        collection: int,
        body: TemplateSegment[],
        span: root.syntax.TextRange,
    ) -> int throws never {
        let body_string = self.elaborate_default_segments(body, span);

        // The leading space keeps the accumulator name out of user identifiers.
        // References sit at an empty range after the template so they land
        // inside the let binding's visibility window.
        let after_span = root.syntax.TextRange.empty(span.end);
        let acc_name = " __m3_for";
        let acc_pat = self.alloc_pattern(PatternBind { name: acc_name, subpat: null }, span);
        let empty_init = self.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, span);
        let let_stmt = self.alloc_stmt(
            StmtLet {
                pattern: acc_pat,
                initializer: empty_init,
                origin: LetOrigin.Source,
                else_branch: null,
            },
            span,
        );

        let acc_path_lhs = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        let acc_path_rhs = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        let concat = self.alloc_expr(
            ExprBinary { op: BinaryOp.Add, lhs: acc_path_rhs, rhs: body_string },
            after_span,
        );
        let assign_stmt = self.alloc_stmt(StmtAssign { target: acc_path_lhs, value: concat }, after_span);
        let loop_body = self.alloc_expr(ExprBlock { stmts: [assign_stmt], tail_expr: null }, after_span);
        let for_stmt = self.alloc_stmt(
            StmtFor { binding: binding, collection: collection, body: loop_body },
            after_span,
        );
        let acc_tail = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        self.alloc_expr(ExprBlock { stmts: [let_stmt, for_stmt], tail_expr: acc_tail }, span)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_default_cstyle_for @ d9be6853b
    // A C-style `${for (let i = 0; cond; step)}…${endfor}` to an accumulator
    // block: `{ let acc = ""; let i = 0; while cond { acc = acc + <body>; }
    // after { step }; acc }`. The `init` `let` scopes the loop variable.
    function elaborate_default_cstyle_for(
        self,
        init: int,
        cond: int,
        step: int?,
        body: TemplateSegment[],
        span: root.syntax.TextRange,
    ) -> int throws never {
        let body_string = self.elaborate_default_segments(body, span);

        let after_span = root.syntax.TextRange.empty(span.end);
        let acc_name = " __m3_for";
        let acc_pat = self.alloc_pattern(PatternBind { name: acc_name, subpat: null }, span);
        let empty_init = self.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, span);
        let acc_let = self.alloc_stmt(
            StmtLet {
                pattern: acc_pat,
                initializer: empty_init,
                origin: LetOrigin.Source,
                else_branch: null,
            },
            span,
        );

        let acc_path_lhs = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        let acc_path_rhs = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        let concat = self.alloc_expr(
            ExprBinary { op: BinaryOp.Add, lhs: acc_path_rhs, rhs: body_string },
            after_span,
        );
        let assign_stmt = self.alloc_stmt(StmtAssign { target: acc_path_lhs, value: concat }, after_span);
        let loop_body = self.alloc_expr(ExprBlock { stmts: [assign_stmt], tail_expr: null }, after_span);
        let while_stmt = self.alloc_stmt(
            StmtWhile {
                condition: cond,
                body: loop_body,
                after: step,
                origin: LoopOriginFor { init: init },
            },
            after_span,
        );
        let acc_tail = self.alloc_expr(ExprPath { value: root.base.Path.new([acc_name]) }, after_span);
        self.alloc_expr(ExprBlock { stmts: [acc_let, init, while_stmt], tail_expr: acc_tail }, span)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_default_if @ d9be6853b
    // `${if (c)}…${else if}…${else}…${endif}` to a host if-expression whose
    // branch bodies are the concat of their segments.
    function elaborate_default_if(
        self,
        branches: TemplateIfBranch[],
        else_body: TemplateSegment[]?,
        span: root.syntax.TextRange,
    ) -> int throws never {
        let current_else = if (else_body != null) {
            self.elaborate_default_segments(else_body, span)
        } else {
            self.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, span)
        };
        for (let branch in branches.reverse()) {
            let then_branch = self.elaborate_default_segments(branch.body, span);
            current_else
                = self.alloc_expr(
                    ExprIf {
                        condition: branch.condition,
                        then_branch: then_branch,
                        else_branch: current_else,
                    },
                    span,
                );
        }
        current_else
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_tagged_body @ d9be6853b
    // The desugared body of a tagged template, the closure the tag is invoked
    // with: a block flattening the segments into `baml.TaggedString { parts,
    // values }` (BEP §10). Text runs accumulate into `cur`, flushed into
    // `parts` at each interpolation; each `${expr}` is pushed raw into
    // `values`. The synthetic locals use leading-space names.
    function elaborate_tagged_body(
        self,
        segments: TemplateSegment[],
        span: root.syntax.TextRange,
    ) -> int throws never {
        let parts = " __tt_parts";
        let values = " __tt_values";
        let cur = " __tt_cur";

        let stmts: int[] = [];
        // let __tt_parts: string[] = [];
        stmts.push(
            self.tt_let_typed_empty_list(
                parts,
                TypeExpr { kind: TypeExprKindString {}, span: span },
                span,
            ),
        );
        // let __tt_values: unknown[] = [];
        stmts.push(
            self.tt_let_typed_empty_list(
                values,
                TypeExpr { kind: TypeExprKindUnknown {}, span: span },
                span,
            ),
        );
        // let __tt_cur = "";
        let at = root.syntax.TextRange.empty(span.start);
        let cur_init = self.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, at);
        let cur_pat = self.alloc_pattern(PatternBind { name: cur, subpat: null }, at);
        stmts.push(
            self.alloc_stmt(
                StmtLet {
                    pattern: cur_pat,
                    initializer: cur_init,
                    origin: LetOrigin.Source,
                    else_branch: null,
                },
                at,
            ),
        );

        self.elaborate_tagged_walk(segments, parts, values, cur, stmts, span);

        // __tt_parts.push(__tt_cur);  (flush the trailing text run)
        let cur_ref = self.tt_path(cur, span);
        stmts.push(self.tt_push_stmt(parts, cur_ref, span));

        // baml.TaggedString { parts: __tt_parts, values: __tt_values }
        let parts_ref = self.tt_path(parts, span);
        let values_ref = self.tt_path(values, span);
        let tail = self.alloc_expr(
            ExprObject {
                type_name: root.base.Path.compiler(["baml", "TaggedString"]),
                type_args: [],
                fields: [
                    ObjectExprField.explicit("parts", parts_ref),
                    ObjectExprField.explicit("values", values_ref),
                ],
                spreads: [],
            },
            span,
        );
        self.alloc_expr(ExprBlock { stmts: stmts, tail_expr: tail }, span)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_tagged_walk @ d9be6853b
    // Emit the per-segment flatten statements into `stmts`, recursing through
    // `${for}` bodies and `${if}` branches with the same accumulator locals so
    // `parts.len() == values.len() + 1` holds across data-dependent lengths.
    function elaborate_tagged_walk(
        self,
        segments: TemplateSegment[],
        parts: string,
        values: string,
        cur: string,
        stmts: int[],
        span: root.syntax.TextRange,
    ) -> void throws never {
        for (let seg in segments) {
            match (seg) {
                let text: TemplateSegmentText => {
                    // __tt_cur = __tt_cur + "<text>";
                    let lhs = self.tt_path(cur, span);
                    let rhs = self.alloc_expr(
                        ExprLiteral { value: root.base.LiteralString { value: text.value } },
                        span,
                    );
                    let concat = self.alloc_expr(ExprBinary { op: BinaryOp.Add, lhs: lhs, rhs: rhs }, span);
                    stmts.push(self.tt_assign(cur, concat, span));
                },
                let interp: TemplateSegmentInterp => {
                    // __tt_parts.push(__tt_cur); __tt_cur = ""; __tt_values.push(<e>);
                    let cur_ref = self.tt_path(cur, span);
                    stmts.push(self.tt_push_stmt(parts, cur_ref, span));
                    let empty = self.alloc_expr(
                        ExprLiteral { value: root.base.LiteralString { value: "" } },
                        span,
                    );
                    stmts.push(self.tt_assign(cur, empty, span));
                    stmts.push(self.tt_push_stmt(values, interp.value, span));
                    self.tag_values.push(interp.value);
                },
                // No value to hand the tag: the text on either side joins.
                let effect: TemplateSegmentEffect => {
                    for (let stmt in effect.stmts) {
                        stmts.push(stmt);
                    }
                },
                let f: TemplateSegmentFor => {
                    // for (let p in c) { <walk body> }
                    let loop_body = self.tagged_walk_block(f.body, parts, values, cur, span);
                    stmts.push(
                        self.alloc_stmt(
                            StmtFor {
                                binding: f.binding,
                                collection: f.collection,
                                body: loop_body,
                            },
                            span,
                        ),
                    );
                },
                let f: TemplateSegmentCStyleFor => {
                    // { let i = 0; while cond { <walk body> } after { step } }
                    let loop_body = self.tagged_walk_block(f.body, parts, values, cur, span);
                    let while_stmt = self.alloc_stmt(
                        StmtWhile {
                            condition: f.cond,
                            body: loop_body,
                            after: f.step,
                            origin: LoopOriginFor { init: f.init },
                        },
                        span,
                    );
                    // Wrap `init` + `while` in a block so the loop variable is scoped
                    // to the loop, not the surrounding flatten body.
                    let block = self.alloc_expr(
                        ExprBlock { stmts: [f.init, while_stmt], tail_expr: null },
                        span,
                    );
                    stmts.push(self.alloc_stmt(StmtExpr { value: block }, span));
                },
                let i: TemplateSegmentIf => {
                    // The if/else-if chain inside-out, each branch body a block of the
                    // walked statements (unit-valued).
                    let else_body = i.else_body;
                    let current_else: int? = if (else_body != null) {
                        self.tagged_walk_block(else_body, parts, values, cur, span)
                    } else {
                        null
                    };
                    for (let branch in i.branches.reverse()) {
                        let then_branch = self.tagged_walk_block(branch.body, parts, values, cur, span);
                        current_else
                            = self.alloc_expr(
                                ExprIf {
                                    condition: branch.condition,
                                    then_branch: then_branch,
                                    else_branch: current_else,
                                },
                                span,
                            );
                    }
                    if (current_else != null) {
                        stmts.push(self.alloc_stmt(StmtExpr { value: current_else }, span));
                    }
                },
            }
        }
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::tt_let_typed_empty_list @ d9be6853b
    // `let <name>: <elem>[] = []` with a leading-space (non-collidable) name,
    // anchored at the template start so its visibility window begins there.
    function tt_let_typed_empty_list(
        self,
        name: string,
        elem: TypeExpr,
        span: root.syntax.TextRange,
    ) -> int throws never {
        let at = root.syntax.TextRange.empty(span.start);
        let list_ty = TypeExpr { kind: TypeExprKindList { inner: elem }, span: span };
        let type_pat = self.alloc_pattern(PatternType { value: list_ty }, at);
        let pat = self.alloc_pattern(PatternBind { name: name, subpat: type_pat }, at);
        let empty = self.alloc_expr(ExprArray { elements: [] }, at);
        self.alloc_stmt(
            StmtLet {
                pattern: pat,
                initializer: empty,
                origin: LetOrigin.Source,
                else_branch: null,
            },
            at,
        )
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::tt_path @ d9be6853b
    // A `Path` reference to a synthetic accumulator local, at an empty range at
    // the template's start: inside the closure's scope and past each
    // accumulator `let`'s visibility start (`span.end` would be out of scope).
    function tt_path(self, name: string, span: root.syntax.TextRange) -> int throws never {
        self.alloc_expr(
            ExprPath { value: root.base.Path.new([name]) },
            root.syntax.TextRange.empty(span.start),
        )
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::tt_assign @ d9be6853b
    // `<name> = <value>;`
    function tt_assign(
        self,
        name: string,
        value: int,
        span: root.syntax.TextRange,
    ) -> int throws never {
        let at = root.syntax.TextRange.empty(span.start);
        let target = self.alloc_expr(ExprPath { value: root.base.Path.new([name]) }, at);
        self.alloc_stmt(StmtAssign { target: target, value: value }, at)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::tt_push_stmt @ d9be6853b
    // `<name>.push(<arg>);` as a statement.
    function tt_push_stmt(
        self,
        name: string,
        arg: int,
        span: root.syntax.TextRange,
    ) -> int throws never {
        let at = root.syntax.TextRange.empty(span.start);
        let recv = self.alloc_expr(ExprPath { value: root.base.Path.new([name]) }, at);
        let callee = self.alloc_expr(ExprMemberAccess { base: recv, member: "push" }, at);
        let call = self.alloc_expr(
            ExprCall { callee: callee, type_args: [], args: [CallArg.positional(arg)] },
            at,
        );
        self.alloc_stmt(StmtExpr { value: call }, at)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::LoweringContext::elaborate_tagged_walk @ d9be6853b
    // deviation: Rust repeats "walk into a fresh list, wrap it in a unit
    // block" at each nested segment; here it is one method.
    function tagged_walk_block(
        self,
        segments: TemplateSegment[],
        parts: string,
        values: string,
        cur: string,
        span: root.syntax.TextRange,
    ) -> int throws never {
        let inner: int[] = [];
        self.elaborate_tagged_walk(segments, parts, values, cur, inner, span);
        self.alloc_expr(ExprBlock { stmts: inner, tail_expr: null }, span)
    }
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::EnvVarRef @ d9be6853b
// A reference to an environment variable found in source code (`env.VAR_NAME`).
class EnvVarRef {
    // The variable name (e.g., `"OPENAI_API_KEY"`).
    name: string,
    // The text range of the entire `env.VAR_NAME` expression in the source.
    range: root.syntax.TextRange,
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::TopLevelLetSurface @ d9be6853b
// Which surface a file-scope binding belongs to.
enum TopLevelLetSurface {
    // A global variable written in an ordinary source file.
    Source,
    // One compiler-generated persistent binding of a `Session.eval`
    // submission; its generated source never annotates a binding.
    Session,
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::InterpPart @ d9be6853b
// The elaborated form of one `${…}` in an untagged backtick template: a value
// to concatenate, or (for a side-effect-only `${ let … }`) the raw
// statements it runs, spliced into one enclosing concat scope.
type InterpPart = InterpPartValue | InterpPartStmts;

class InterpPartValue {
    value: int,
}

class InterpPartStmts {
    value: int[],
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::ascription_type_expr @ d9be6853b
// The type a `const NAME: …` sub-pattern denotes when it is a pure type
// ascription: a type pattern, or an alternation of them (the union type).
// Any structural sub-pattern is not an annotation.
// The type expressions are shared with the pattern arena, not cloned: the one
// caller discards that arena after reading the annotation.
function ascription_type_expr(patterns: Pattern[], sub: int) -> TypeExpr? throws never {
    match (patterns[sub]) {
        let ty: PatternType => ty.value,
        let alternatives: PatternOr => {
            let variants: TypeExpr[] = [];
            for (let alternative in alternatives.value) {
                let variant = match (patterns[alternative]) {
                    let ty: PatternType => ty.value,
                    _ => {
                        return null;
                    },
                };
                variants.push(variant);
            }
            if (variants.length() == 0) {
                return null;
            }
            let span = variants
                .map((variant) -> {
                    variant.span
                })
                .reduce(
                    (a, b) -> {
                        a.cover(b)
                    },
                    variants[0].span,
                );
            TypeExpr { kind: TypeExprKindUnion { variants: variants }, span: span }
        },
        _ => null,
    }
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::InitTestContext @ d9be6853b
// Context for building the `$init_test` function body. Wraps a
// `LoweringContext` so runner expressions lower directly into the same arena.
class InitTestContext {
    inner: LoweringContext,

    // port: baml_compiler2_ast/src/lower_expr_body.rs::InitTestContext::new @ d9be6853b
    function new() -> InitTestContext throws never {
        InitTestContext { inner: LoweringContext.new() }
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::InitTestContext::alloc_expr @ d9be6853b
    function alloc_expr(self, expr: Expr, span: root.syntax.TextRange) -> int throws never {
        self.inner.alloc_expr(expr, span)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::InitTestContext::alloc_stmt @ d9be6853b
    function alloc_stmt(self, stmt: Stmt, span: root.syntax.TextRange) -> int throws never {
        self.inner.alloc_stmt(stmt, span)
    }

    // port: baml_compiler2_ast/src/lower_expr_body.rs::InitTestContext::finish @ d9be6853b
    function finish(
        self,
        root_expr: int?,
    ) -> (ExprBody, AstSourceMap, LoweringDiagnostic[], EnvVarRef[]) throws never {
        self.inner.finish(root_expr)
    }
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::LlmSpecSource @ d9be6853b
// The parts of an LLM function's spec body read off a syntax tree: the
// prompt, the `tools` value and a dynamic `client` expression. Each source
// lowers its pieces into the context when the body needs them, so the arenas
// fill in one order.
interface LlmSpecSource {
    // The prompt literal's range: the prompt lambda's span.
    function prompt_span(self) -> root.syntax.TextRange throws never;
    // The prompt's segments, lowered into `ctx`.
    function prompt_segments(self, ctx: LoweringContext) -> TemplateSegment[] throws never;
    // The `tools` value lowered into `ctx`, or null when the field is absent.
    // A list lowers element by element, each bare function reference passed
    // through `wrap_bare_ref` (which builds `ai.tool(<ref>)`) once lowered.
    function tools(
        self,
        ctx: LoweringContext,
        span: root.syntax.TextRange,
        wrap_bare_ref: (LoweringContext, int) -> int throws never,
    ) -> int? throws never;
    // The `client` expression, for an `LlmClientExpr` client.
    function client_expr(
        self,
        ctx: LoweringContext,
        span: root.syntax.TextRange,
    ) -> int throws never;
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::LlmClient @ d9be6853b
// How an LLM function's `client:` value lowers into the spec's `default_client`.
type LlmClient = LlmClientProvider | LlmClientExpr;

// A `"provider/model"` string, mapped at compile time to a builtin provider
// constructor.
class LlmClientProvider {
    // The client constructor, `<package>.<Client>.new`, from `SHORTHAND_PROVIDERS`.
    constructor: root.base.Path,
    model: string,
}

// An arbitrary expression evaluating to `ai.Selector`, read from the source.
// Wrapped in `ai.clients.resolve(...)` and resolved when the function is called.
class LlmClientExpr {
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body @ d9be6853b
// BEP `@spec`: synthesize the body of the `<Fn>@spec` companion, an
// `ai.FunctionSpec<Out>` literal binding the function's arguments:
//
//   ai.FunctionSpec<Out> {
//       spec_name: "Fn",
//       args: { "p": p, ... },
//       prompt_template: (output_format: ai.OutputFormat) -> {
//           let ctx = ai.internal.SpecCtx { _output_format: output_format };
//           let tagged = baml.TaggedString { ...the function's prompt... };
//           ai.internal.assemble_llm_prompt(tagged.parts, tagged.values)
//       },
//       toolbox: ai.Toolbox.new([ai.tool(a), ...]),
//       default_client: openai.ResponsesClient.new(model = "gpt-4o-mini"),
//   }
//
// The prompt parameter's real name is ` __spec_output_format` (leading space)
// so it can never shadow a user identifier. `default_client` is evaluated
// each time this body runs, never during `$init`. In the `tools` list a bare
// function reference is wrapped in `ai.tool(...)`.
function synthesize_llm_spec_body(
    function_name: string,
    param_names: string[],
    generic_param_names: string[],
    owner_class_name: string?,
    owner_generic_param_names: string[],
    client: LlmClient,
    out_type: TypeExpr?,
    source: LlmSpecSource,
    span: root.syntax.TextRange,
) -> (ExprBody, AstSourceMap, TemplateSegment[], LoweringDiagnostic[], EnvVarRef[]) throws never {
    let ctx = LoweringContext.new();
    // spec_name: "Fn"
    let name_lit = ctx.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: function_name } }, span);
    let target = spec_target_function(
        ctx,
        function_name,
        param_names,
        generic_param_names,
        owner_class_name,
        owner_generic_param_names,
        span,
    );
    let args_map = spec_args_map(ctx, param_names, span);
    let (let prompt_lambda, let segments) = spec_prompt_template(ctx, source, span);
    let toolbox = spec_toolbox(ctx, source, span);
    let default_client = spec_default_client(ctx, client, source, span);

    let type_args: TypeExpr[] = if (out_type != null) {
        [out_type]
    } else {
        []
    };
    let spec_obj = ctx.alloc_expr(
        ExprObject {
            type_name: root.base.Path.compiler(["ai", "FunctionSpec"]),
            type_args: type_args,
            fields: [
                ObjectExprField.explicit("spec_name", name_lit),
                ObjectExprField.explicit("target_function", target),
                ObjectExprField.explicit("args", args_map),
                ObjectExprField.explicit("prompt_template", prompt_lambda),
                ObjectExprField.explicit("toolbox", toolbox),
                ObjectExprField.explicit("default_client", default_client),
            ],
            spreads: [],
        },
        span,
    );

    let (let body, let source_map, let diagnostics, let env_var_refs) = ctx.finish(spec_obj);
    (body, source_map, segments, diagnostics, env_var_refs)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (target_function) @ d9be6853b
// The function the spec stands for: `self.f` when a method's first
// parameter is `self`, `Owner.f` for another method, else `f`; with the
// function's generics applied.
function spec_target_function(
    ctx: LoweringContext,
    function_name: string,
    param_names: string[],
    generic_param_names: string[],
    owner_class_name: string?,
    owner_generic_param_names: string[],
    span: root.syntax.TextRange,
) -> int throws never {
    let binds_receiver = owner_class_name != null && param_names.at(0) == "self";
    let target = if (binds_receiver) {
        let receiver = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["self"]) }, span);
        ctx.alloc_expr(ExprMemberAccess { base: receiver, member: function_name }, span)
    } else if (owner_class_name != null) {
        ctx.alloc_expr(
            ExprPath { value: root.base.Path.compiler([owner_class_name, function_name]) },
            span,
        )
    } else {
        // Compiler-written, so a parameter named like the function cannot shadow it.
        ctx.alloc_expr(ExprPath { value: root.base.Path.compiler([function_name]) }, span)
    };
    let target_args = companion_type_args(
        generic_param_names,
        owner_generic_param_names,
        owner_class_name != null && !binds_receiver,
        span,
    );
    if (target_args.length() == 0) {
        return target;
    }
    ctx.alloc_expr(ExprGenericApply { base: target, type_args: target_args }, span)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (args) @ d9be6853b
// args: { "p": p, ... }
function spec_args_map(
    ctx: LoweringContext,
    param_names: string[],
    span: root.syntax.TextRange,
) -> int throws never {
    let entries = param_names.map((name) -> {
        let key = ctx.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: name } }, span);
        let value = ctx.alloc_expr(ExprPath { value: root.base.Path.new([name]) }, span);
        MapExprEntry.explicit(key, value)
    });
    ctx.alloc_expr(ExprMap { entries: entries }, span)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (prompt_template) @ d9be6853b
// prompt_template: ( __spec_output_format: ai.OutputFormat) -> ai.Prompt { ... }
//
// The parameter's leading-space name keeps a function parameter named
// `output_format` visible to `${output_format}`. Returns the lambda and the
// flattened template's segments.
function spec_prompt_template(
    ctx: LoweringContext,
    source: LlmSpecSource,
    span: root.syntax.TextRange,
) -> (int, TemplateSegment[]) throws never {
    let of_param_name = " __spec_output_format";
    let prompt_lambda_span = source.prompt_span();
    let prompt_start = root.syntax.TextRange.empty(prompt_lambda_span.start);
    let let_ctx = spec_ctx_let(ctx, of_param_name, prompt_start);
    // Flatten the template exactly like the public `prompt` tag; rewrite the
    // prompt-local constructors before name resolution.
    let segments = source.prompt_segments(ctx);
    rewrite_prompt_local_calls(ctx);

    let prev_synth = ctx.synthesizing;
    ctx.synthesizing = true;
    let tagged_expr = ctx.elaborate_tagged_body(segments, prompt_lambda_span);
    ctx.synthesizing = prev_synth;

    let block_body = assemble_tagged_prompt(ctx, let_ctx, tagged_expr, prompt_start, prompt_lambda_span);
    let lambda_body = wrap_prompt_render_error(ctx, block_body, prompt_start, prompt_lambda_span);
    let of_param = Param {
        name: of_param_name,
        type_expr: TypeExpr {
            kind: TypeExprKindPath {
                path: root.base.Path.compiler(["ai", "OutputFormat"]),
                generic_args: [],
                associated_type_bindings: [],
            },
            span: span,
        },
        default: null,
        span: span,
        name_span: span,
    };
    // The prompt lambda carries the backtick's own range: lambda scopes are
    // located by exact span within their owner, so the two lambdas synthesized
    // into this body must not share a range.
    let prompt_lambda = ctx.alloc_expr(
        ExprLambda {
            value: LambdaDef {
                kind: LambdaKind.Anonymous,
                params: [of_param],
                defaults: FunctionDefaults.empty(),
                return_type: null,
                throws_: null,
                body: lambda_body,
                span: prompt_lambda_span,
            },
        },
        prompt_lambda_span,
    );
    (prompt_lambda, segments)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (the `let ctx`) @ d9be6853b
// `let ctx = ai.internal.SpecCtx { _output_format: <of_param_name> };`
//
// It sits at an empty range at the literal's start (`prompt_start`), before
// every reference, since binding references are checked against their
// `let`'s window.
function spec_ctx_let(
    ctx: LoweringContext,
    of_param_name: string,
    prompt_start: root.syntax.TextRange,
) -> int throws never {
    let of_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new([of_param_name]) }, prompt_start);
    let spec_ctx_obj = ctx.alloc_expr(
        ExprObject {
            type_name: root.base.Path.compiler(["ai", "internal", "SpecCtx"]),
            type_args: [],
            fields: [ObjectExprField.explicit("_output_format", of_ref)],
            spreads: [],
        },
        prompt_start,
    );
    let ctx_pat = ctx.alloc_pattern(PatternBind { name: "ctx", subpat: null }, prompt_start);
    ctx.alloc_stmt(
        StmtLet {
            pattern: ctx_pat,
            initializer: spec_ctx_obj,
            origin: LetOrigin.Source,
            else_branch: null,
        },
        prompt_start,
    )
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (prompt-local callees) @ d9be6853b
// `role(...)` and `cache(...)` are prompt-local: a bare call lowers to
// `ai.internal.make_role` / `ai.internal.make_cache`. `cache`'s one
// parameter is defaulted, so the positional `cache(x)` is labelled
// `args = x`.
// BUG (upstream): both are recognized by spelling before resolution, so a
// writer's own `role` or `cache` is never called from a prompt.
function rewrite_prompt_local_calls(ctx: LoweringContext) -> void throws never {
    let rewrites: (int, int, root.base.Path)[] = [];
    for (let call = 0; call < ctx.exprs.length(); call += 1) {
        root.base.push_some(rewrites, prompt_local_call(ctx, call));
    }
    for (let entry in rewrites) {
        let (let call, let callee, let callee_target) = entry;
        ctx.exprs[callee] = ExprPath { value: callee_target };
        if (callee_target.leaf() != "make_cache") {
            continue;
        }
        if let c: ExprCall = ctx.exprs[call] {
            if (c.args.length() == 1 && c.args[0].label == null) {
                c.args[0].label = "args";
            }
        }
    }
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (one prompt-local callee) @ d9be6853b
// `(call, callee, target)` when expression `call` calls bare `role` or
// `cache`, else null.
function prompt_local_call(
    ctx: LoweringContext,
    call: int,
) -> (int, int, root.base.Path)? throws never {
    let c = match (ctx.exprs[call]) {
        let c: ExprCall => c,
        _ => {
            return null;
        },
    };
    let path = match (ctx.exprs[c.callee]) {
        let path: ExprPath if path.value.segments.length() == 1 => path,
        _ => {
            return null;
        },
    };
    let target = match (path.value.segments[0]) {
        "role" => root.base.Path.compiler(["ai", "internal", "make_role"]),
        "cache" => root.base.Path.compiler(["ai", "internal", "make_cache"]),
        _ => {
            return null;
        },
    };
    (call, c.callee, target)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (the prompt block) @ d9be6853b
// `{ let ctx = ..; let tagged = <template>; ai.internal.assemble_llm_prompt(tagged.parts, tagged.values) }`:
// the flattened template is evaluated once before its two arrays are read.
function assemble_tagged_prompt(
    ctx: LoweringContext,
    let_ctx: int,
    tagged_expr: int,
    prompt_start: root.syntax.TextRange,
    prompt_lambda_span: root.syntax.TextRange,
) -> int throws never {
    let tagged_name = " __spec_tagged_prompt";
    let tagged_pat = ctx.alloc_pattern(PatternBind { name: tagged_name, subpat: null }, prompt_start);
    let let_tagged = ctx.alloc_stmt(
        StmtLet {
            pattern: tagged_pat,
            initializer: tagged_expr,
            origin: LetOrigin.Source,
            else_branch: null,
        },
        prompt_start,
    );
    let parts_base = ctx.alloc_expr(ExprPath { value: root.base.Path.new([tagged_name]) }, prompt_start);
    let parts = ctx.alloc_expr(ExprMemberAccess { base: parts_base, member: "parts" }, prompt_start);
    let values_base = ctx.alloc_expr(ExprPath { value: root.base.Path.new([tagged_name]) }, prompt_start);
    let values = ctx.alloc_expr(ExprMemberAccess { base: values_base, member: "values" }, prompt_start);
    let assemble_callee = ctx.alloc_expr(
        ExprPath { value: root.base.Path.compiler(["ai", "internal", "assemble_llm_prompt"]) },
        prompt_start,
    );
    let prompt_ast = ctx.alloc_expr(
        ExprCall {
            callee: assemble_callee,
            type_args: [],
            args: [CallArg.positional(parts), CallArg.positional(values)],
        },
        prompt_start,
    );
    ctx.alloc_expr(
        ExprBlock { stmts: [let_ctx, let_tagged], tail_expr: prompt_ast },
        prompt_lambda_span,
    )
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (the render-error catch) @ d9be6853b
// Wrap the whole template body: a user expression in the prompt may throw,
// and the stored `prompt_template` boundary is typed
// `throws ai.errors.PromptRenderError`, so anything raised while rendering
// is wrapped into that one typed failure.
function wrap_prompt_render_error(
    ctx: LoweringContext,
    block_body: int,
    prompt_start: root.syntax.TextRange,
    prompt_lambda_span: root.syntax.TextRange,
) -> int throws never {
    let err_name = " __prompt_render_err";
    let err_binding = ctx.alloc_pattern(PatternBind { name: err_name, subpat: null }, prompt_start);
    let wildcard = ctx.alloc_pattern(PatternWildcard {}, prompt_start);
    let message = ctx.alloc_expr(
        ExprLiteral { value: root.base.LiteralString { value: "prompt template rendering threw" } },
        prompt_start,
    );
    let cause = ctx.alloc_expr(ExprPath { value: root.base.Path.new([err_name]) }, prompt_start);
    let render_error = ctx.alloc_expr(
        ExprObject {
            type_name: root.base.Path.compiler(["ai", "errors", "PromptRenderError"]),
            type_args: [],
            fields: [ObjectExprField.explicit("message", message), ObjectExprField.explicit("cause", cause)],
            spreads: [],
        },
        prompt_start,
    );
    let throw_wrapped = ctx.alloc_expr(ExprThrow { value: render_error }, prompt_start);
    let wrap_arm = ctx.alloc_catch_arm(CatchArm { pattern: wildcard, body: throw_wrapped }, prompt_start);
    ctx.alloc_expr(
        ExprCatch {
            base: block_body,
            clause: CatchClause {
                kind: CatchClauseKind.CatchAll,
                binding: err_binding,
                stack_trace_binding: null,
                arms: [wrap_arm],
            },
        },
        prompt_lambda_span,
    )
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (toolbox) @ d9be6853b
// toolbox: ai.Toolbox.new([...]), a bare function reference in the list
// wrapped in `ai.tool(...)`.
function spec_toolbox(
    ctx: LoweringContext,
    source: LlmSpecSource,
    span: root.syntax.TextRange,
) -> int throws never {
    let wrap_bare_ref = (c: LoweringContext, id: int) -> int {
        let tool_callee = c.alloc_expr(ExprPath { value: root.base.Path.compiler(["ai", "tools", "tool"]) }, span);
        c.alloc_expr(
            ExprCall { callee: tool_callee, type_args: [], args: [CallArg.positional(id)] },
            span,
        )
    };
    let tool_list = source.tools(ctx, span, wrap_bare_ref) ?? ctx.alloc_expr(ExprArray { elements: [] }, span);
    let toolbox_callee = ctx.alloc_expr(
        ExprPath { value: root.base.Path.compiler(["ai", "tools", "Toolbox", "new"]) },
        span,
    );
    ctx.alloc_expr(
        ExprCall { callee: toolbox_callee, type_args: [], args: [CallArg.positional(tool_list)] },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_llm_spec_body (default_client) @ d9be6853b
// default_client: evaluated when the `@spec` function runs (each call of
// the LLM function), never during `$init`. A `"provider/model"` literal maps
// at compile time to a builtin constructor; anything else is wrapped in
// `ai.clients.resolve(selector, providers, prefixes)`.
function spec_default_client(
    ctx: LoweringContext,
    client: LlmClient,
    source: LlmSpecSource,
    span: root.syntax.TextRange,
) -> int throws never {
    match (client) {
        let provider: LlmClientProvider => {
            let model_lit = ctx.alloc_expr(
                ExprLiteral { value: root.base.LiteralString { value: provider.model } },
                span,
            );
            let ctor_callee = ctx.alloc_expr(ExprPath { value: provider.constructor }, span);
            ctx.alloc_expr(
                ExprCall {
                    callee: ctor_callee,
                    type_args: [],
                    args: [CallArg.named("model", model_lit)],
                },
                span,
            )
        },
        LlmClientExpr => {
            let inner = source.client_expr(ctx, span);
            let resolve_callee = ctx.alloc_expr(
                ExprPath { value: root.base.Path.compiler(["ai", "clients", "resolve"]) },
                span,
            );
            let args = ctx.complete_client_resolve_call(resolve_callee, [CallArg.positional(inner)], span);
            ctx.alloc_expr(ExprCall { callee: resolve_callee, type_args: [], args: args }, span)
        },
    }
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_shorthand_prefixes @ d9be6853b
// Every prefix the `"provider/model"` shorthand knows, as a string array
// literal, for `ai.clients.resolve`'s error messages.
function synthesize_shorthand_prefixes(
    ctx: LoweringContext,
    span: root.syntax.TextRange,
) -> int throws never {
    let elements = SHORTHAND_PROVIDERS.map((entry) -> {
        ctx.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: entry.0 } }, span)
    });
    ctx.alloc_expr(ExprArray { elements: elements }, span)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_shorthand_providers @ d9be6853b
// The runtime half of the `"provider/model"` shorthand, as a lambda:
//
//   (prefix: string, model: string) -> ai.Client? => match (prefix) {
//       "openai" => openai.ResponsesClient.new(model = model),
//       ...
//       _ => null,
//   }
//
// Generated from `SHORTHAND_PROVIDERS` and handed to `ai.clients.resolve` at
// each call site. Its range is empty at the call's end, so it shares no
// range with a lambda written at the call or the spec's prompt lambda.
function synthesize_shorthand_providers(
    ctx: LoweringContext,
    span: root.syntax.TextRange,
) -> int throws never {
    let prefix_name = "prefix";
    let model_name = "model";
    let param = (name: string) -> Param {
        Param {
            name: name,
            type_expr: TypeExpr { kind: TypeExprKindString {}, span: span },
            default: null,
            span: span,
            name_span: span,
        }
    };

    let scrutinee = ctx.alloc_expr(ExprPath { value: root.base.Path.new([prefix_name]) }, span);
    let arms: int[] = [];
    for (let entry in SHORTHAND_PROVIDERS) {
        let (let prefix, let constructor) = entry;
        let pattern = ctx.alloc_pattern(
            PatternType {
                value: TypeExpr {
                    kind: TypeExprKindLiteral { value: root.base.LiteralString { value: prefix } },
                    span: span,
                },
            },
            span,
        );
        let ctor_callee = ctx.alloc_expr(ExprPath { value: constructor }, span);
        let model = ctx.alloc_expr(ExprPath { value: root.base.Path.new([model_name]) }, span);
        let body = ctx.alloc_expr(
            ExprCall { callee: ctor_callee, type_args: [], args: [CallArg.named("model", model)] },
            span,
        );
        arms.push(ctx.alloc_match_arm(MatchArm { pattern: pattern, guard: null, body: body }, span));
    }
    let wildcard = ctx.alloc_pattern(PatternWildcard {}, span);
    let null_expr = ctx.alloc_expr(ExprNull {}, span);
    arms.push(
        ctx.alloc_match_arm(MatchArm { pattern: wildcard, guard: null, body: null_expr }, span),
    );
    let body = ctx.alloc_expr(ExprMatch { scrutinee: scrutinee, scrutinee_type: null, arms: arms }, span);

    let client_ty = TypeExpr {
        kind: TypeExprKindPath {
            path: root.base.Path.compiler(["ai", "Client"]),
            generic_args: [],
            associated_type_bindings: [],
        },
        span: span,
    };
    let return_type = TypeExpr { kind: TypeExprKindOptional { inner: client_ty }, span: span };
    let lambda_span = root.syntax.TextRange.empty(span.end);
    ctx.alloc_expr(
        ExprLambda {
            value: LambdaDef {
                kind: LambdaKind.Anonymous,
                params: [param(prefix_name), param(model_name)],
                defaults: FunctionDefaults.empty(),
                return_type: return_type,
                throws_: null,
                body: body,
                span: lambda_span,
            },
        },
        lambda_span,
    )
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_spec_render_prompt_body @ d9be6853b
// Synthesize the `@render_prompt` companion body: render the spec's prompt
// with the return type's output-format handle, `Fn@spec(p...).prompt()`.
function synthesize_spec_render_prompt_body(
    function_name: string,
    params: Param[],
    generic_param_names: string[],
    owner_class_name: string?,
    owner_generic_param_names: string[],
    span: root.syntax.TextRange,
) -> (ExprBody, AstSourceMap) throws never {
    let ctx = LoweringContext.new();
    let (let spec_callee, let binds_receiver) = companion_callee(ctx, function_name, params, owner_class_name, span);
    let spec_args = companion_param_call_args(
        ctx,
        if (binds_receiver) {
            params.slice(1, params.length())
        } else {
            params
        },
        span,
    );
    let spec_call = ctx.alloc_expr(
        ExprCall {
            callee: spec_callee,
            type_args: companion_type_args(
                generic_param_names,
                owner_generic_param_names,
                owner_class_name != null && !binds_receiver,
                span,
            ),
            args: spec_args,
        },
        span,
    );
    let prompt_callee = ctx.alloc_expr(ExprMemberAccess { base: spec_call, member: "prompt" }, span);
    let render_call = ctx.alloc_expr(ExprCall { callee: prompt_callee, type_args: [], args: [] }, span);

    let (let body, let source_map, _, _) = ctx.finish(render_call);
    (body, source_map)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_spec_build_request_body @ d9be6853b
// Synthesize the `@build_request` companion body:
// `Fn@spec(p...).build_request(client = client)`.
function synthesize_spec_build_request_body(
    function_name: string,
    params: Param[],
    generic_param_names: string[],
    owner_class_name: string?,
    owner_generic_param_names: string[],
    span: root.syntax.TextRange,
) -> (ExprBody, AstSourceMap) throws never {
    let ctx = LoweringContext.new();
    let (let spec_callee, let binds_receiver) = companion_callee(ctx, function_name, params, owner_class_name, span);
    let spec_args = companion_param_call_args(
        ctx,
        if (binds_receiver) {
            params.slice(1, params.length())
        } else {
            params
        },
        span,
    );
    let spec_call = ctx.alloc_expr(
        ExprCall {
            callee: spec_callee,
            type_args: companion_type_args(
                generic_param_names,
                owner_generic_param_names,
                owner_class_name != null && !binds_receiver,
                span,
            ),
            args: spec_args,
        },
        span,
    );
    let build_callee = ctx.alloc_expr(ExprMemberAccess { base: spec_call, member: "build_request" }, span);
    let client_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["client"]) }, span);
    let call = ctx.alloc_expr(
        ExprCall {
            callee: build_callee,
            type_args: [],
            args: [CallArg.named("client", client_ref)],
        },
        span,
    );
    let (let body, let source_map, _, _) = ctx.finish(call);
    (body, source_map)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_spec_parse_body @ d9be6853b
// Synthesize the `@parse` companion body: a network-free parse of an existing
// JSON/SAP string into the function's return type, `baml.sap.parse<Out>(json)`.
function synthesize_spec_parse_body(
    out_type: TypeExpr?,
    span: root.syntax.TextRange,
) -> (ExprBody, AstSourceMap) throws never {
    let ctx = LoweringContext.new();
    let json_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["json"]) }, span);
    let callee = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["baml", "sap", "parse"]) }, span);
    let type_args: TypeExpr[] = if (out_type != null) {
        [out_type]
    } else {
        []
    };
    let call = ctx.alloc_expr(
        ExprCall { callee: callee, type_args: type_args, args: [CallArg.positional(json_ref)] },
        span,
    );
    let (let body, let source_map, _, _) = ctx.finish(call);
    (body, source_map)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_spec_agent_run_body @ d9be6853b
// BEP `@spec` spec mode: the direct-call body of a `tools`-bearing LLM
// function runs the default ai runner over the function's own spec and
// unwraps the value:
//
//   ai.Agent.new(client = client).run(Fn@spec(p1, p2)).value
//
// `client` is the compiler-injected `ai.Client? = null` override parameter;
// `run` infers its `Out` from the spec, so the body names no output type.
function synthesize_spec_agent_run_body(
    function_name: string,
    params: Param[],
    generic_param_names: string[],
    owner_class_name: string?,
    owner_generic_param_names: string[],
    span: root.syntax.TextRange,
) -> (ExprBody, AstSourceMap) throws never {
    let ctx = LoweringContext.new();
    let (let spec_callee, let binds_receiver) = companion_callee(ctx, function_name, params, owner_class_name, span);
    let spec_args = companion_param_call_args(
        ctx,
        if (binds_receiver) {
            params.slice(1, params.length())
        } else {
            params
        },
        span,
    );
    let spec_call = ctx.alloc_expr(
        ExprCall {
            callee: spec_callee,
            type_args: companion_type_args(
                generic_param_names,
                owner_generic_param_names,
                owner_class_name != null && !binds_receiver,
                span,
            ),
            args: spec_args,
        },
        span,
    );

    // ai.Agent.new(client = client, on_event = on_event)
    let agent_path = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["ai", "Agent"]) }, span);
    let new_callee = ctx.alloc_expr(ExprMemberAccess { base: agent_path, member: "new" }, span);
    let client_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["client"]) }, span);
    let on_event_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["on_event"]) }, span);
    let new_call = ctx.alloc_expr(
        ExprCall {
            callee: new_callee,
            type_args: [],
            args: [CallArg.named("client", client_ref), CallArg.named("on_event", on_event_ref)],
        },
        span,
    );

    // .run(spec).value
    let run_callee = ctx.alloc_expr(ExprMemberAccess { base: new_call, member: "run" }, span);
    let trace_callee = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["trace", "_passthrough"]) }, span);
    let trace = ctx.alloc_expr(ExprCall { callee: trace_callee, type_args: [], args: [] }, span);
    let run_call = ctx.alloc_expr(
        ExprCall {
            callee: run_callee,
            type_args: [],
            args: [CallArg.positional(spec_call), CallArg.named("$trace", trace)],
        },
        span,
    );
    let value = ctx.alloc_expr(ExprMemberAccess { base: run_call, member: "value" }, span);

    let (let body, let source_map, _, _) = ctx.finish(value);
    (body, source_map)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::synthesize_spec_stream_body @ d9be6853b
// Synthesize the `@stream` companion body, one-turn streaming over the
// function's own spec:
//
//   ai.stream.from_spec<Out>(Fn@spec(p1, p2), client = client)
//
// `type_args` is the explicit `<Out>`. `client` is the companion's injected
// `ai.stream.StreamingClient? = null` override.
function synthesize_spec_stream_body(
    function_name: string,
    params: Param[],
    generic_param_names: string[],
    owner_class_name: string?,
    owner_generic_param_names: string[],
    type_args: TypeExpr[],
    span: root.syntax.TextRange,
) -> (ExprBody, AstSourceMap) throws never {
    let ctx = LoweringContext.new();
    let (let spec_callee, let binds_receiver) = companion_callee(ctx, function_name, params, owner_class_name, span);
    let spec_args = companion_param_call_args(
        ctx,
        if (binds_receiver) {
            params.slice(1, params.length())
        } else {
            params
        },
        span,
    );
    let spec_call = ctx.alloc_expr(
        ExprCall {
            callee: spec_callee,
            type_args: companion_type_args(
                generic_param_names,
                owner_generic_param_names,
                owner_class_name != null && !binds_receiver,
                span,
            ),
            args: spec_args,
        },
        span,
    );

    // ai.stream.from_spec<Out>(spec, client = client, on_event = on_event)
    let stream_spec_callee = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["ai", "stream", "from_spec"]) }, span);
    let client_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["client"]) }, span);
    let on_event_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["on_event"]) }, span);
    let trace_callee = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["trace", "_passthrough"]) }, span);
    let trace = ctx.alloc_expr(ExprCall { callee: trace_callee, type_args: [], args: [] }, span);
    let call = ctx.alloc_expr(
        ExprCall {
            callee: stream_spec_callee,
            type_args: type_args,
            args: [
                CallArg.positional(spec_call),
                CallArg.named("client", client_ref),
                CallArg.named("on_event", on_event_ref),
                CallArg.named("$trace", trace),
            ],
        },
        span,
    );

    let (let body, let source_map, _, _) = ctx.finish(call);
    (body, source_map)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::companion_type_args @ d9be6853b
// Re-apply a companion's enclosing generic parameters when it calls another
// companion: some LLM type parameters occur only in the return type, so
// argument inference has no value-position evidence for them.
function companion_type_args(
    function_names: string[],
    owner_names: string[],
    include_owner: bool,
    span: root.syntax.TextRange,
) -> TypeExpr[] throws never {
    let owners: string[] = if (include_owner) {
        owner_names
    } else {
        []
    };
    owners.concat(function_names).map((name) -> {
        TypeExpr {
            kind: TypeExprKindPath {
                path: root.base.Path.new([name]),
                generic_args: [],
                associated_type_bindings: [],
            },
            span: span,
        }
    })
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::companion_callee @ d9be6853b
// Select the sibling spec companion with the same receiver shape as a user
// call. Instance methods bind `self`; static methods use their owning class,
// named as an item of this namespace so a parameter spelled like the class
// cannot capture it; free functions remain unqualified.
function companion_callee(
    ctx: LoweringContext,
    function_name: string,
    params: Param[],
    owner_class_name: string?,
    span: root.syntax.TextRange,
) -> (int, bool) throws never {
    let companion_name = `${function_name}@spec`;
    let binds_receiver = owner_class_name != null && params.at(0)?.name == "self";
    let callee = if (binds_receiver) {
        let receiver = ctx.alloc_expr(ExprPath { value: root.base.Path.new(["self"]) }, span);
        ctx.alloc_expr(ExprMemberAccess { base: receiver, member: companion_name }, span)
    } else if (owner_class_name != null) {
        ctx.alloc_expr(
            ExprPath { value: root.base.Path.compiler([owner_class_name, companion_name]) },
            span,
        )
    } else {
        ctx.alloc_expr(ExprPath { value: root.base.Path.new([companion_name]) }, span)
    };
    (callee, binds_receiver)
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::companion_param_call_args @ d9be6853b
// Re-apply parameter defaults when a generated companion calls its `@spec`:
// required parameters stay positional; defaulted ones are named so the
// callee's default metadata stays visible to argument lowering.
function companion_param_call_args(
    ctx: LoweringContext,
    params: Param[],
    span: root.syntax.TextRange,
) -> CallArg[] throws never {
    params.map((param) -> {
        let value = ctx.alloc_expr(ExprPath { value: root.base.Path.new([param.name]) }, span);
        if (param.default != null) {
            CallArg.named(param.name, value)
        } else {
            CallArg.positional(value)
        }
    })
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::strip_string_delimiters @ d9be6853b
// Strip string delimiters from raw token text, decoding escape sequences.
function strip_string_delimiters(text: string) -> string throws never {
    let trimmed = text.trim();
    if (trimmed.starts_with("\"") && trimmed.ends_with("\"") && trimmed.length() >= 2) {
        root.base.unescape_string_literal(trimmed.slice(1, trimmed.length() - 1))
    } else {
        trimmed
    }
}

// port: baml_compiler2_ast/src/lower_expr_body.rs::strip_raw_string_delimiters @ d9be6853b
// The verbatim body of a raw `r"..."` string literal's text, or null if the
// literal is unclosed (which is already a parse error).
function strip_raw_string_delimiters(text: string) -> string? throws never {
    let trimmed = text.trim();
    if (!trimmed.starts_with("r\"")) {
        return null;
    }
    let rest = trimmed.slice(2, trimmed.length());
    if (rest.ends_with("\"")) {
        rest.slice(0, rest.length() - 1)
    } else {
        null
    }
}
