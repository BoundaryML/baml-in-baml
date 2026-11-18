// port: baml_compiler2_ast/src/lower_tree/items.rs @ d9be6853b
//
// Items: a `SourceFile` to the `Item`s the rowan lowering (`lower_cst`)
// produces, read off typed fields. The desugarings (LLM companions, the
// `cleanup` guard, the `implements … for` fold, the `$init_test` registrar)
// are shared with the rowan path and run on the lowered declarations; only
// what reads a tree lives here.
//
// Spans are the rowan lowering's: an item starts at its keyword (its `///`
// lines and directives come before that), and a member ends before the
// `,`/`;` it owns. Members lower in source order, each as it is met.
//
// deviation: the `Items` methods Rust calls `function`, `class` and
// `interface` are `function_def`, `class_def` and `interface_def` here (BAML
// keywords).
//
// deviation: classes are references, so where Rust clones a read-only AST
// value (a return type, a class's self type and generics) the value is
// shared here.

// port: baml_compiler2_ast/src/lower_tree/items.rs::lower_file @ d9be6853b
// port: baml_compiler2_ast/src/lower_tree/items.rs::lower_session_file @ d9be6853b
// port: baml_compiler2_ast/src/lower_tree/items.rs::lower_file_on @ d9be6853b
// Lower a source file's items. `file_path` names the `$init_test_<path>`
// registrar and, with `test_owner` absent, the tests' owner. A
// `Session.eval` submission (Rust's `lower_session_file`) passes
// `surface = TopLevelLetSurface.Session`: its file-scope bindings are the
// session's persistent ones.
function lower_file(
    tree: root.syntax.FileTree,
    file_path: string?,
    test_owner: string?,
    surface: TopLevelLetSurface = TopLevelLetSurface.Source,
) -> (Item[], LoweringDiagnostic[], EnvVarRef[]) throws never {
    let v = View { tree: tree };
    let items = Items { v: v, surface: surface, diags: [], env_var_refs: [] };
    let out: Item[] = [];
    let registrations: TestRegistration[] = [];
    for (let item in tree.file.items) {
        match (item) {
            let id: root.syntax.FunctionDef => {
                let func = items.function_def(id, null);
                if (func) {
                    let no_owner_generics: string[] = [];
                    let companions = expand_companions(func, null, no_owner_generics);
                    out.push(ItemFunction { value: func });
                    for (let companion in companions) {
                        out.push(ItemFunction { value: companion });
                    }
                }
            },
            let id: root.syntax.ClassDef => {
                let lowered = items.class_def(id);
                if (lowered) {
                    out.push(ItemClass { value: lowered.0 });
                    for (let imp in lowered.1) {
                        out.push(ItemImplementsFor { value: imp });
                    }
                }
            },
            let id: root.syntax.EnumDef => {
                if let def: EnumDef = items.enum_def(id) {
                    out.push(ItemEnum { value: def });
                }
            },
            let id: root.syntax.InterfaceDef => {
                if let def: InterfaceDef = items.interface_def(id) {
                    out.push(ItemInterface { value: def });
                }
            },
            let id: root.syntax.ImplementsFor => {
                if let def: ImplementsForDef = items.implements_for(id) {
                    out.push(ItemImplementsFor { value: def });
                }
            },
            let id: root.syntax.TypeAliasDef => {
                if let def: TypeAliasDef = items.type_alias(id) {
                    out.push(ItemTypeAlias { value: def });
                }
            },
            let id: root.syntax.LetItem => {
                if let def: LetDef = items.top_level_let(id) {
                    out.push(ItemLet { value: def });
                }
            },
            // `let type` binds a runtime type for the rest of a block, and a file
            // has no block for it to bind in.
            let id: root.syntax.TypeBindingStmt => {
                items.diags.push(LoweringDiagnosticTopLevelLetType { span: v.range(id.span) });
            },
            let id: root.syntax.ClientValueDef => {
                out.push(ItemLet { value: items.client_value(id) });
            },
            let id: root.syntax.TestDef => {
                push_some(registrations, items.test_registration(id));
            },
            let id: root.syntax.RemovedItem => items.removed_item(id),
            root.syntax.Bogus => {},
        }
    }
    if (registrations) {
        let init_fn = synthesize_init_test_function(registrations, file_path, test_owner, items.diags, items.env_var_refs);
        out.push(ItemFunction { value: init_fn });
    }
    (out, items.diags, items.env_var_refs)
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::span_from @ d9be6853b
// A span from `start`'s start to `end`'s end.
function span_from(
    start: root.syntax.TextRange,
    end: root.syntax.TextRange,
) -> root.syntax.TextRange throws never {
    root.syntax.TextRange { start: start.start, end: end.end }
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::Items @ d9be6853b
// The file being lowered and what the lowering collects.
class Items {
    v: View,
    surface: TopLevelLetSurface,
    diags: LoweringDiagnostic[],
    env_var_refs: EnvVarRef[],

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::member_span @ d9be6853b
    // The span the rowan lowering gave a member: from its first own token
    // (`start`) to the end of its last part before the separator it owns.
    function member_span(
        self,
        start: root.syntax.TextRange,
        node: root.syntax.TextRange,
        sep: int?,
    ) -> root.syntax.TextRange throws never {
        let last = if (sep != null) {
            prev_significant(self.v.tree.tokens, sep)
        } else {
            null
        };
        let end = if (last != null) {
            self.v.token_range(last).end
        } else {
            node.end
        };
        root.syntax.TextRange { start: start.start, end: end }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::declared_type @ d9be6853b
    // A type at a declaration site: lowered, checked for `Missing` with
    // `missing_context`, for `_` with `wildcard_context` when given, and
    // spanning the type as written.
    function declared_type(
        self,
        ty: root.syntax.AnyType,
        missing_context: string,
        wildcard_context: string?,
    ) -> TypeExpr throws never {
        let span = self.v.range(root.syntax.node_span(ty));
        let expr = lower_type(self.v, self.diags, ty);
        check_missing_type(expr, missing_context, span, self.diags);
        if (wildcard_context != null) {
            check_wildcard_type(expr, wildcard_context, span, self.diags);
        }
        expr.with_span(span)
    }

    // ── Docs, directives, attributes ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::header_title @ d9be6853b
    // A function's `//#` title: the header line's text after its `#`s,
    // trimmed; null when there is no header or the title is empty.
    function header_title(self, docs: root.syntax.AnyDoc[]) -> string? throws never {
        for (let doc in docs) {
            if let header: root.syntax.HeaderLine = doc {
                let text = self.v.text(header.token);
                let title = trim_start_matches(strip_prefix(text, "//") ?? text, "#").trim();
                if (title) {
                    return title;
                }
            }
        }
        null
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::docstring @ d9be6853b
    // A declaration's docstring: its `///` lines joined with `\n`, each without
    // the `///` and one optional leading space. A plain comment, a blank line
    // or a `//#` title between the lines is transparent; a directive or a
    // trace hook is not a line of it.
    function docstring(self, docs: root.syntax.AnyDoc[]) -> string? throws never {
        let v = self.v;
        let lines = docs
            .filter_map((doc) -> {
                match (doc) {
                    let line: root.syntax.DocLine => line.token,
                    root.syntax.Directive | root.syntax.HeaderLine | root.syntax.Bogus => null,
                }
            })
            .map((token) -> {
                let text = v.text(token);
                let doc = strip_prefix(text, "///") ?? text;
                strip_prefix(doc, " ") ?? doc
            });
        if (lines) {
            lines.join("\n")
        } else {
            null
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::native_directives @ d9be6853b
    // The native-binding directives among a function's docs.
    function native_directives(self, docs: root.syntax.AnyDoc[]) -> NativeDirectives throws never {
        let directives = NativeDirectives.none();
        for (let doc in docs) {
            if let node: root.syntax.Directive = doc {
                let directive = match (node.kind) {
                    root.syntax.DirectiveKind.MutSelf => NativeDirective.MutSelf,
                    root.syntax.DirectiveKind.Vm => NativeDirective.Vm,
                    root.syntax.DirectiveKind.MutVm => NativeDirective.MutVm,
                    root.syntax.DirectiveKind.MayYield => NativeDirective.MayYield,
                    root.syntax.DirectiveKind.Fallible => NativeDirective.Fallible,
                    root.syntax.DirectiveKind.LocalTwin => NativeDirective.LocalTwin,
                    root.syntax.DirectiveKind.TaggedString
                        | root.syntax.DirectiveKind.TracePassthrough
                        | root.syntax.DirectiveKind.Trace =>
                    {
                        null
                    },
                };
                if (directive != null) {
                    directives = directives.with(directive);
                }
            }
        }
        directives
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::has_directive @ d9be6853b
    // Whether a `//baml:<kind>` directive is among the declaration's docs.
    function has_directive(
        self,
        docs: root.syntax.AnyDoc[],
        kind: root.syntax.DirectiveKind,
    ) -> bool throws never {
        docs.some((doc) -> {
            match (doc) {
                let node: root.syntax.Directive => node.kind == kind,
                _ => false,
            }
        })
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::trace_hook @ d9be6853b
    // The function's `/// baml:$trace=path` hook. The parser admits one per
    // function at most, and only with a hook path.
    function trace_hook(self, docs: root.syntax.AnyDoc[]) -> TraceHookDirective? throws never {
        let directive = docs.find((doc) -> {
            match (doc) {
                let node: root.syntax.Directive => node.kind == root.syntax.DirectiveKind.Trace,
                _ => false,
            }
        });
        if (!(directive is root.syntax.Directive)) {
            return null;
        }
        let value = root.syntax.trace_hook_value(self.v.text(directive.token)) ?? "";
        let path = root.syntax.trace_hook_path(value)
            ?? baml.sys.panic("a `Trace` directive carries a hook path");
        TraceHookDirective { path: path.split("."), span: self.v.token_range(directive.token) }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::block_attribute @ d9be6853b
    // One `@@` attribute; none when its name is missing (reported by the
    // parser).
    function block_attribute(self, id: root.syntax.BlockAttr) -> RawAttribute? throws never {
        let path = id.path;
        if (!(path is root.syntax.DottedName)) {
            return null;
        }
        self.raw_attribute(path, id.args, self.v.range(id.span))
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::member_attributes @ d9be6853b
    // The `@` attributes of a member.
    function member_attributes(
        self,
        attrs: root.syntax.Attribute[],
    ) -> RawAttribute[] throws never {
        attrs.filter_map((attr) -> {
            match (attr.path) {
                let path: root.syntax.DottedName => {
                    self.raw_attribute(path, attr.args, self.v.range(attr.span))
                },
                root.syntax.Missing => null,
            }
        })
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::raw_attribute @ d9be6853b
    function raw_attribute(
        self,
        path: root.syntax.DottedName,
        args: root.syntax.AttrArgs?,
        span: root.syntax.TextRange,
    ) -> RawAttribute throws never {
        let v = self.v;
        let name = dotted_text(v, path.head, path.segments);
        // An argument is kept as its source text.
        let lowered = (args?.args ?? []).map((arg) -> {
            let span = v.range(root.syntax.node_span(arg.item));
            let text = match (arg.item) {
                let unquoted: root.syntax.Name => v.text(unquoted.token),
                root.syntax.StringLit
                    | root.syntax.BacktickString
                    | root.syntax.JinjaArg
                    | root.syntax.Bogus =>
                {
                    v.tree.slice(span)
                },
            };
            RawAttributeArg { key: null, value: text.trim(), span: span }
        });
        RawAttribute { name: name, args: lowered, span: span }
    }

    // ── Generics, parameters ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::generic_params @ d9be6853b
    // BEP-044 generic bounds: each parameter's name with every `&`-separated
    // bound it declares (`<T>` is `(T, [])`; `<T extends A & B>` is
    // `(T, [A, B])`). The bound list is a conjunction.
    function generic_params(
        self,
        list: root.syntax.GenericParamList?,
    ) -> GenericParam[] throws never {
        let v = self.v;
        let diags = self.diags;
        (list?.params ?? []).map((item) -> {
            let param = item.item;
            let bounds = param.bounds;
            let lowered: TypeExpr[] = if (bounds) {
                [bounds.first]
                    .concat(
                        bounds.rest.map((arm) -> {
                            arm.ty
                        }),
                    )
                    .filter_map((ty) -> {
                        match (ty) {
                            let ty: root.syntax.AnyType => ty,
                            root.syntax.Missing => null,
                        }
                    })
                    .map((ty) -> {
                        let bound = lower_type(v, diags, ty);
                        check_wildcard_type(bound, "a generic type bound", bound.span, diags);
                        bound
                    })
            } else {
                []
            };
            GenericParam {
                name: v.name(param.name),
                bounds: lowered,
                name_span: v.name_range(param.name),
            }
        })
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::return_type @ d9be6853b
    function return_type(
        self,
        ret: root.syntax.ReturnType | root.syntax.Missing,
        name: string,
    ) -> TypeExpr? throws never {
        if (!(ret is root.syntax.ReturnType)) {
            return null;
        }
        // An arrow with no type after it is a type that is missing, not a
        // function without a declared return type.
        match (ret.ty) {
            let ty: root.syntax.AnyType => {
                self.declared_type(ty, `return type of \`${name}\``, "a return type")
            },
            let missing: root.syntax.Missing => {
                TypeExpr { kind: TypeExprKindMissing {}, span: View.missing_range(missing) }
            },
        }
    }

    // ── Functions ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::function @ d9be6853b
    function function_def(
        self,
        id: root.syntax.FunctionDef,
        class_method: ClassMethodContext?,
    ) -> FunctionDef? throws never {
        let v = self.v;
        let span = span_from(v.token_range(id.kw), v.range(id.span));
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let name = v.name(name_id);
        let name_span = v.name_range(name_id);

        let generic_params = self.generic_params(id.generics);
        let parameter_context = `function \`${name}\``;
        let lowered_params: (Param[], FunctionDefaults) = match (id.params) {
            let list: root.syntax.ParamList => {
                lower_params(v, list, name, parameter_context, self.diags, true, self.env_var_refs)
            },
            root.syntax.Missing => ([], FunctionDefaults.empty()),
        };
        let (let params, let defaults) = lowered_params;
        let return_type = self.return_type(id.ret, name);
        let throws_ = match (id.throws_clause?.ty) {
            let ty: root.syntax.AnyType => {
                let te_span = v.range(root.syntax.node_span(ty));
                let expr = lower_type(v, self.diags, ty);
                check_throws_wildcard(expr, te_span, self.diags);
                expr.with_span(te_span)
            },
            _ => null,
        };

        let body: FunctionBodyDef? = null;
        let declarative_meta: DeclarativeMeta? = null;
        match (id.body) {
            let llm: root.syntax.LlmBody => {
                let (let llm_body, let llm_meta) = self.llm_function(
                    llm,
                    name,
                    generic_params,
                    params,
                    defaults,
                    return_type,
                    class_method,
                );
                body = llm_body;
                declarative_meta = llm_meta;
            },
            let block: root.syntax.Block => {
                let kind = builtin_kind(v, block);
                if (kind != null) {
                    body = FunctionBodyDefBuiltin { value: kind };
                } else {
                    let (let expr_body, let source_map, let diags, let env) = lower_body(v.tree, block);
                    extend(self.diags, diags);
                    extend(self.env_var_refs, env);
                    body = FunctionBodyDefExpr { v0: expr_body, v1: source_map };
                }
            },
            root.syntax.Bogus | root.syntax.Missing => {},
        }

        let explicit_trace_passthrough = self.has_directive(id.docs, root.syntax.DirectiveKind.TracePassthrough);
        FunctionDef {
            name: name,
            generic_params: generic_params,
            params: params,
            defaults: defaults,
            return_type: return_type,
            throws_: throws_,
            body: body,
            declarative_meta: declarative_meta,
            metadata: FunctionMetadata {
                ...FunctionMetadata.user_facing(FunctionOrigin.UserDefined),
                trace_passthrough: declarative_meta != null || explicit_trace_passthrough,
                explicit_trace_passthrough: explicit_trace_passthrough,
            },
            attributes: [],
            docstring: self.docstring(id.docs),
            header_title: self.header_title(id.docs),
            is_tagged_template_tag: self.has_directive(id.docs, root.syntax.DirectiveKind.TaggedString),
            directives: self.native_directives(id.docs),
            trace_hook: self.trace_hook(id.docs),
            span: span,
            name_span: name_span,
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::llm_function @ d9be6853b
    // An LLM function's declarative body: the `@spec` companion body is
    // synthesized while the prompt is in hand, the `client`/`on_event`
    // overrides are appended to the parameters, and the function's own body
    // becomes the agent run.
    function llm_function(
        self,
        llm: root.syntax.LlmBody,
        name: string,
        generic_params: GenericParam[],
        params: Param[],
        defaults: FunctionDefaults,
        return_type: TypeExpr?,
        class_method: ClassMethodContext?,
    ) -> (FunctionBodyDef?, DeclarativeMeta?) throws never {
        let v = self.v;
        let llm_span = v.range(llm.span);
        let client_field: root.syntax.ClientField? = null;
        let prompt_field: root.syntax.PromptField? = null;
        let tools_field: root.syntax.ToolsField? = null;
        for (let field in llm.fields) {
            match (field) {
                let id: root.syntax.ClientField => {
                    client_field = client_field ?? id;
                },
                let id: root.syntax.PromptField => {
                    prompt_field = prompt_field ?? id;
                },
                let id: root.syntax.ToolsField => {
                    tools_field = tools_field ?? id;
                },
                root.syntax.Bogus => {},
            }
        }
        let client_value = match (client_field?.value) {
            let value: root.syntax.AnyExpr => value,
            _ => null,
        };
        let tools_value = match (tools_field?.value) {
            let value: root.syntax.AnyExpr => value,
            _ => null,
        };
        let prompt_value = match (prompt_field?.value) {
            let value: root.syntax.AnyStringLike => value,
            _ => null,
        };

        let llm_body_def = LlmBodyDef {
            client_: if (client_value != null) {
                self.client_name(client_value)
            } else {
                null
            },
            companion_bodies: [],
            prompt_spans: null,
            prompt_segments: [],
            has_tools: match (tools_value) {
                null => false,
                let array: root.syntax.ArrayLiteral => array.elements.length() > 0,
                _ => true,
            },
            span: llm_span,
        };
        reject_reserved_llm_params(params, name, self.diags);

        // A prompt is a string literal: backtick (interpolating) or quoted
        // (inert). Both become the same tagged template; the parser rejects every
        // other value shape.
        let prompt: Prompt? = match (prompt_value) {
            let id: root.syntax.BacktickString => PromptBacktick { value: id },
            // Jinja prompts are removed: the single-path world renders prompts as
            // plain backtick templates through the spec.
            let id: root.syntax.StringLit if is_hash_string(v.tree.tokens.kinds[id.token]) => {
                self.diags.push(LoweringDiagnosticLlmJinjaPromptRemoved { span: v.range(id.span) });
                null
            },
            let id: root.syntax.StringLit => PromptQuoted { value: id },
            _ => null,
        };
        if let quoted: PromptQuoted = prompt {
            warn_quoted_prompt_interpolation(v.text(quoted.value.token), v.range(quoted.value.span), self.diags);
        }
        llm_body_def.prompt_spans
            = match (prompt) {
                let backtick: PromptBacktick => {
                    let code: root.syntax.TextRange[] = [];
                    interpolation_spans(v, backtick.value.parts, code);
                    LlmPromptSpans { literal: v.range(backtick.value.span), code: code }
                },
                // A quoted prompt is inert: the whole literal is prose.
                let quoted: PromptQuoted => {
                    LlmPromptSpans { literal: v.range(quoted.value.span), code: [] }
                },
                null => null,
            };

        let llm_client = self.llm_client(name, client_value, llm_span);

        // The function's real parameters: the injected `client` and `on_event`
        // overrides are added below and are never part of the spec's bound
        // arguments.
        let user_params = params.filter((p) -> {
            !is_injected_llm_param(p.name)
        });
        let param_names = user_params.map((p) -> {
            p.name
        });
        let generic_param_names = generic_params.map((param) -> {
            param.name
        });
        let owner_generic_param_names: string[] = if (class_method) {
            class_method.generic_params.map((param) -> {
                param.name
            })
        } else {
            []
        };

        if (prompt != null && llm_client != null) {
            let source = TypedLlmSpecSource {
                v: v,
                prompt: prompt,
                tools_value: tools_value,
                client_value: client_value,
            };
            let (let spec_body, let spec_sm, let prompt_segments, let spec_diags, let spec_env_refs) = synthesize_llm_spec_body(
                name,
                param_names,
                generic_param_names,
                class_method?.name,
                owner_generic_param_names,
                llm_client,
                return_type,
                source,
                llm_span,
            );
            extend(self.diags, spec_diags);
            extend(self.env_var_refs, spec_env_refs);
            llm_body_def.companion_bodies.push(("spec", (spec_body, spec_sm)));
            llm_body_def.prompt_segments = prompt_segments;
        }

        // Every LLM function runs the ai Agent loop; `client: ai.Client? = null`
        // is the compiler-injected per-call override. When the spec could not be
        // synthesized (migration diagnostics fired), the body is omitted so the
        // missing `<Fn>@spec` reference never cascades.
        append_spec_client_param(params, defaults, llm_span);
        append_spec_on_event_param(params, defaults, llm_span);
        let body: FunctionBodyDef? = if (
            llm_body_def.companion_bodies.some((companion) -> {
                companion.0 == "spec"
            })
        ) {
            let (let expr_body, let source_map) = synthesize_spec_agent_run_body(
                name,
                user_params,
                generic_param_names,
                class_method?.name,
                owner_generic_param_names,
                llm_span,
            );
            FunctionBodyDefExpr { v0: expr_body, v1: source_map }
        } else {
            null
        };
        let meta: DeclarativeMeta = DeclarativeMetaLlm { value: llm_body_def };
        (body, meta)
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::client_name @ d9be6853b
    // The `client:` value as the name the rowan lowering recorded: a bare
    // identifier or a quoted string; nothing for an expression.
    function client_name(self, value: root.syntax.AnyExpr) -> string? throws never {
        match (value) {
            let path: root.syntax.PathExpr => {
                if (path.segments) {
                    null
                } else {
                    self.v.name(path.head)
                }
            },
            let string_lit: root.syntax.StringLit => {
                strip_string_delimiters(self.v.text(string_lit.token))
            },
            _ => null,
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::llm_client @ d9be6853b
    // Classify the `client:` value, reporting the unusable shapes. Null means
    // an authoritative error was emitted (or the parser already reported a
    // missing value).
    function llm_client(
        self,
        function_name: string,
        value: root.syntax.AnyExpr?,
        span: root.syntax.TextRange,
    ) -> LlmClient? throws never {
        if (value == null) {
            return null;
        }
        match (value) {
            let id: root.syntax.StringLit => {
                let text = strip_string_delimiters(self.v.text(id.token));
                classify_client_string(function_name, text, span, self.diags)
            },
            let id: root.syntax.BinaryExpr
                if reject_unquoted_client_shorthand(function_name, self.v.text_of(id.span), span, self.diags) => {
                null
            },
            _ => LlmClientExpr {},
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::method_sig @ d9be6853b
    function method_sig(self, id: root.syntax.MethodSig) -> MethodSigDef? throws never {
        let v = self.v;
        // The signature ends before the `;` it owns.
        let span = self.member_span(v.token_range(id.kw), v.range(id.span), id.semi);
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let name = v.name(name_id);
        let name_span = v.name_range(name_id);
        let generic_params = self.generic_params(id.generics);
        let parameter_context = `method signature \`${name}\``;
        // A signature has no defaults: what it reads is reported, not kept.
        let no_env: EnvVarRef[] = [];
        let params: Param[] = match (id.params) {
            let list: root.syntax.ParamList => {
                lower_params(v, list, name, parameter_context, self.diags, false, no_env).0
            },
            root.syntax.Missing => [],
        };
        let return_type = self.return_type(id.ret, name);
        let throws_ = match (id.throws_clause?.ty) {
            let ty: root.syntax.AnyType => {
                // A bodyless method signature has nothing to infer an open
                // `throws … | _` from, and its declared throws is compared
                // structurally during conformance checking, so reject ANY `_` here
                // (unlike a function with a body, where a top-level `_` is the open
                // slot).
                let te_span = v.range(root.syntax.node_span(ty));
                let expr = lower_type(v, self.diags, ty);
                check_wildcard_type(expr, "a method signature `throws` clause", te_span, self.diags);
                expr.with_span(te_span)
            },
            _ => null,
        };
        MethodSigDef {
            name: name,
            generic_params: generic_params,
            params: params,
            defaults: FunctionDefaults.empty(),
            return_type: return_type,
            throws_: throws_,
            attributes: [],
            docstring: self.docstring(id.docs),
            span: span,
            name_span: name_span,
        }
    }

    // ── Classes, enums, interfaces ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::class @ d9be6853b
    // A class and the `implements` blocks written in its body, which are its
    // own items (an in-body block is shorthand for `implements<…> I for C<…>`).
    function class_def(
        self,
        id: root.syntax.ClassDef,
    ) -> (ClassDef, ImplementsForDef[])? throws never {
        let v = self.v;
        let span = span_from(v.token_range(id.kw), v.range(id.span));
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let generic_params = self.generic_params(id.generics);
        let class_name = v.name(name_id);
        let owner_generic_param_names = generic_params.map((param) -> {
            param.name
        });
        let self_type = class_self_type(class_name, generic_params, v.name_range(name_id));
        let fields: FieldDef[] = [];
        let methods: FunctionDef[] = [];
        let implements_defs: ImplementsForDef[] = [];
        let attributes: RawAttribute[] = [];
        for (let member in id.members) {
            match (member) {
                let field: root.syntax.Field => {
                    fields.push(
                        self.field(
                            field,
                            (field_name: string) -> {
                                `field \`${class_name}.${field_name}\``
                            },
                            "a class field type",
                        ),
                    );
                },
                let method: root.syntax.FunctionDef => {
                    let func = self.function_def(
                        method,
                        ClassMethodContext { name: class_name, generic_params: generic_params },
                    );
                    if (func) {
                        let companions = expand_companions(func, class_name, owner_generic_param_names);
                        methods.push(func);
                        extend(methods, companions);
                    }
                },
                let block: root.syntax.ImplementsBlock => {
                    push_some(implements_defs, self.implements_block(block, generic_params, self_type));
                },
                let attr: root.syntax.BlockAttr => {
                    push_some(attributes, self.block_attribute(attr));
                },
                // Reported by the parser.
                root.syntax.Bogus => {},
            }
        }
        let class_def = ClassDef {
            name: class_name,
            generic_params: generic_params,
            fields: fields,
            methods: methods,
            attributes: attributes,
            docstring: self.docstring(id.docs),
            span: span,
            name_span: v.name_range(name_id),
        };
        // BEP-042: wrap a magic `cleanup(self) -> void` method in its run-once guard.
        maybe_inject_cleanup_guard(class_def);
        (class_def, implements_defs)
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::field @ d9be6853b
    // A class or interface field. A field with no type is already reported by
    // the parser, so it recovers with the error sentinel rather than an
    // optional type: an absent type is not a kind of type.
    function field(
        self,
        id: root.syntax.Field,
        missing_context: (string) -> string throws never,
        wildcard_context: string,
    ) -> FieldDef throws never {
        let v = self.v;
        let name = v.name(id.name);
        let span = self.member_span(v.name_range(id.name), v.range(id.span), id.sep);
        let type_expr = match (id.ty) {
            let ty: root.syntax.AnyType => {
                self.declared_type(ty, missing_context(name), wildcard_context)
            },
            root.syntax.Missing => TypeExpr { kind: TypeExprKindError {}, span: span },
        };
        FieldDef {
            attributes: self.member_attributes(id.attrs),
            docstring: self.docstring(id.docs),
            name: name,
            type_expr: type_expr,
            span: span,
            name_span: v.name_range(id.name),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::enum_def @ d9be6853b
    function enum_def(self, id: root.syntax.EnumDef) -> EnumDef? throws never {
        let v = self.v;
        let span = span_from(v.token_range(id.kw), v.range(id.span));
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let variants: VariantDef[] = [];
        let attributes: RawAttribute[] = [];
        for (let member in id.members) {
            match (member) {
                let variant: root.syntax.EnumVariant => {
                    variants.push(self.variant(variant));
                },
                let attr: root.syntax.BlockAttr => {
                    push_some(attributes, self.block_attribute(attr));
                },
                root.syntax.Bogus => {},
            }
        }
        EnumDef {
            name: v.name(name_id),
            variants: variants,
            attributes: attributes,
            docstring: self.docstring(id.docs),
            span: span,
            name_span: v.name_range(name_id),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::variant @ d9be6853b
    function variant(self, id: root.syntax.EnumVariant) -> VariantDef throws never {
        let v = self.v;
        VariantDef {
            name: v.name(id.name),
            attributes: self.member_attributes(id.attrs),
            docstring: self.docstring(id.docs),
            span: self.member_span(v.name_range(id.name), v.range(id.span), id.sep),
            name_span: v.name_range(id.name),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::interface @ d9be6853b
    function interface_def(self, id: root.syntax.InterfaceDef) -> InterfaceDef? throws never {
        let v = self.v;
        let span = span_from(v.token_range(id.kw), v.range(id.span));
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let iface_name = v.name(name_id);
        let generic_params = self.generic_params(id.generics);

        let parents: root.syntax.AnyType[] = match (id.requires_clause?.types) {
            let types: root.syntax.SepItem<root.syntax.AnyType>[] => {
                types.map((item) -> {
                    item.item
                })
            },
            _ => [],
        };
        let requires_ = parents.map((ty) -> {
            self.declared_type(
                ty,
                `requires clause of interface \`${iface_name}\``,
                "an interface `requires` clause",
            )
        });

        let fields: FieldDef[] = [];
        let required_methods: MethodSigDef[] = [];
        let associated_types: AssociatedTypeDef[] = [];
        let default_methods: FunctionDef[] = [];
        let attributes: RawAttribute[] = [];
        for (let member in id.members) {
            match (member) {
                let field: root.syntax.Field => {
                    fields.push(
                        self.field(
                            field,
                            (field_name: string) -> {
                                `interface field \`${iface_name}.${field_name}\``
                            },
                            "an interface field type",
                        ),
                    );
                },
                let sig: root.syntax.MethodSig => {
                    push_some(required_methods, self.method_sig(sig));
                },
                let decl: root.syntax.AssocTypeDecl => {
                    push_some(associated_types, self.associated_type_decl(decl));
                },
                let method: root.syntax.FunctionDef => {
                    push_some(default_methods, self.function_def(method, null));
                },
                let attr: root.syntax.BlockAttr => {
                    push_some(attributes, self.block_attribute(attr));
                },
                root.syntax.Bogus => {},
            }
        }

        InterfaceDef {
            name: iface_name,
            generic_params: generic_params,
            requires_: requires_,
            fields: fields,
            associated_types: associated_types,
            required_methods: required_methods,
            default_methods: default_methods,
            attributes: attributes,
            docstring: self.docstring(id.docs),
            span: span,
            name_span: v.name_range(name_id),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::associated_type_decl @ d9be6853b
    function associated_type_decl(
        self,
        id: root.syntax.AssocTypeDecl,
    ) -> AssociatedTypeDef? throws never {
        let v = self.v;
        let span = self.member_span(v.token_range(id.kw), v.range(id.span), id.sep);
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let name = v.name(name_id);
        let bound = match (id.bound?.ty) {
            let ty: root.syntax.AnyType => {
                self.declared_type(ty, `bound of associated type \`${name}\``, null)
            },
            _ => null,
        };
        let default_type = match (id.default?.ty) {
            let ty: root.syntax.AnyType => {
                self.declared_type(ty, `default of associated type \`${name}\``, null)
            },
            _ => null,
        };
        AssociatedTypeDef {
            name: name,
            bound: bound,
            default: default_type,
            span: span,
            name_span: v.name_range(name_id),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::associated_type_binding @ d9be6853b
    function associated_type_binding(
        self,
        id: root.syntax.AssocTypeDef,
    ) -> AssociatedTypeBindingDef? throws never {
        let v = self.v;
        let span = self.member_span(v.token_range(id.kw), v.range(id.span), id.sep);
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let name = v.name(name_id);
        let type_expr = match (id.ty) {
            let ty: root.syntax.AnyType => {
                self.declared_type(ty, `binding of associated type \`${name}\``, null)
            },
            root.syntax.Missing => null,
        };
        AssociatedTypeBindingDef {
            name: name,
            type_expr: type_expr,
            span: span,
            name_span: v.name_range(name_id),
        }
    }

    // ── Implementations ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::interface_label @ d9be6853b
    // The last segment of an interface target's path, for diagnostics.
    function interface_label(target: TypeExpr) -> string throws never {
        match (target.kind) {
            let kind: TypeExprKindPath => {
                if (kind.path.segments) {
                    kind.path.leaf()
                } else {
                    "?"
                }
            },
            _ => "?",
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::impl_members @ d9be6853b
    // The members an `implements` block or `implements … for` shares: a field
    // declared there is reported, the rest lower.
    function impl_members(
        self,
        members: root.syntax.AnyImplMember[],
        interface_label: string,
    ) -> (InterfaceFieldLinkDef[], AssociatedTypeBindingDef[], FunctionDef[]) throws never {
        let v = self.v;
        let field_links: InterfaceFieldLinkDef[] = [];
        let associated_type_bindings: AssociatedTypeBindingDef[] = [];
        let methods: FunctionDef[] = [];
        for (let member in members) {
            match (member) {
                let node: root.syntax.Field => {
                    self.diags.push(
                        LoweringDiagnosticInterfaceFieldDeclaredInImplementsBlock {
                            interface_name: interface_label,
                            field_name: v.name(node.name),
                            span: self.member_span(v.name_range(node.name), v.range(node.span), node.sep),
                        },
                    );
                },
                let link: root.syntax.InterfaceFieldLink => {
                    push_some(field_links, self.interface_field_link(link));
                },
                let def: root.syntax.AssocTypeDef => {
                    push_some(associated_type_bindings, self.associated_type_binding(def));
                },
                let method: root.syntax.FunctionDef => {
                    push_some(methods, self.function_def(method, null));
                },
                root.syntax.Bogus => {},
            }
        }
        (field_links, associated_type_bindings, methods)
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::implements_block @ d9be6853b
    // An in-body `implements I { … }` block as the `implements<…> I for C<…>`
    // it is shorthand for: the class's generics, the class as the for-target.
    function implements_block(
        self,
        id: root.syntax.ImplementsBlock,
        class_generic_params: GenericParam[],
        class_self_type: TypeExpr,
    ) -> ImplementsForDef? throws never {
        let v = self.v;
        let target_ty = id.target;
        if (!(target_ty is root.syntax.AnyType)) {
            return null;
        }
        let target = self.declared_type(target_ty, "interface name in `implements`", null);
        let label = Items.interface_label(target);
        let (let field_links, let associated_type_bindings, let methods) = self.impl_members(id.members, label);
        ImplementsForDef {
            generic_params: class_generic_params.slice(0, class_generic_params.length()),
            interface_target: target,
            for_target: class_self_type,
            field_links: field_links,
            associated_type_bindings: associated_type_bindings,
            methods: methods,
            origin: ImplOrigin.InBody,
            span: span_from(v.token_range(id.kw), v.range(id.span)),
            docstring: null,
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::implements_for @ d9be6853b
    function implements_for(self, id: root.syntax.ImplementsFor) -> ImplementsForDef? throws never {
        let v = self.v;
        let generic_params = self.generic_params(id.generics);
        let target_ty = id.target;
        if (!(target_ty is root.syntax.AnyType)) {
            return null;
        }
        let interface_target = self.declared_type(target_ty, "interface name in `implements ... for`", null);
        let self_ty = id.self_ty;
        if (!(self_ty is root.syntax.AnyType)) {
            return null;
        }
        let for_target = self.declared_type(self_ty, "target type in `implements ... for`", null);
        let label = Items.interface_label(interface_target);
        let (let field_links, let associated_type_bindings, let methods) = self.impl_members(id.members, label);
        ImplementsForDef {
            generic_params: generic_params,
            interface_target: interface_target,
            for_target: for_target,
            field_links: field_links,
            associated_type_bindings: associated_type_bindings,
            methods: methods,
            origin: ImplOrigin.OutOfBody,
            span: span_from(v.token_range(id.kw), v.range(id.span)),
            docstring: self.docstring(id.docs),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::interface_field_link @ d9be6853b
    function interface_field_link(
        self,
        id: root.syntax.InterfaceFieldLink,
    ) -> InterfaceFieldLinkDef? throws never {
        let v = self.v;
        let span = self.member_span(v.name_range(id.iface_field), v.range(id.span), id.sep);
        let class_field = id.class_field;
        if (!(class_field is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        InterfaceFieldLinkDef {
            interface_field: v.name(id.iface_field),
            class_field: v.name(class_field),
            span: span,
            interface_field_span: v.name_range(id.iface_field),
            class_field_span: v.name_range(class_field),
        }
    }

    // ── Aliases, globals, clients ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::type_alias @ d9be6853b
    function type_alias(self, id: root.syntax.TypeAliasDef) -> TypeAliasDef? throws never {
        let v = self.v;
        let span = span_from(v.token_range(id.kw), v.range(id.span));
        let name_id = id.name;
        if (!(name_id is root.syntax.Name)) {
            // The parser reported the missing name.
            return null;
        }
        let name = v.name(name_id);
        // `type A = ;` has a missing type; `type A` has none to lower.
        let type_expr = match (id.ty) {
            let ty: root.syntax.AnyType => {
                self.declared_type(ty, `type alias \`${name}\``, "a type alias")
            },
            let missing: root.syntax.Missing => {
                if (id.eq is root.syntax.Missing) {
                    null
                } else {
                    TypeExpr { kind: TypeExprKindMissing {}, span: View.missing_range(missing) }
                }
            },
        };
        TypeAliasDef {
            name: name,
            type_expr: type_expr,
            span: span,
            name_span: v.name_range(name_id),
            docstring: self.docstring(id.docs),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::client_value @ d9be6853b
    // `client Name = <expr>;`: a top-level client binding, the same
    // `LetOrigin.Client` item the legacy config blocks produced, so the name
    // resolves from every function body; the initializer is the user's own
    // expression (evaluated once at `$init`).
    function client_value(self, id: root.syntax.ClientValueDef) -> LetDef throws never {
        let v = self.v;
        let span = span_from(v.token_range(id.kw), v.range(id.span));
        let ctx = LoweringContext.new();
        let root_expr = expr_or_missing(ctx, v, id.value, span);
        let (let body, let source_map, let diags, let env) = ctx.finish(root_expr);
        extend(self.diags, diags);
        extend(self.env_var_refs, env);
        LetDef {
            name: v.name(id.name),
            type_annotation: null,
            initializer: (body, source_map),
            origin: LetOrigin.Client,
            docstring: self.docstring(id.docs),
            span: span,
            name_span: v.name_range(id.name),
        }
    }

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::top_level_let @ d9be6853b
    // A file-scope `let`/`const`: exactly one name, `const NAME = value;` or,
    // in source, `const NAME: Type = value;`. Everything a local `let` admits
    // beyond that (a destructure, a wildcard, an alias chain, `let … else`) is
    // refused: a global is addressed by its one name from every body in the
    // package and has no scope a refutable pattern could fall out of.
    function top_level_let(self, id: root.syntax.LetItem) -> LetDef? throws never {
        let v = self.v;
        let stmt = id.stmt;
        let span = v.range(stmt.span);
        let surface = self.surface;

        // The binding's pattern and its initializer lower into separate
        // contexts: the initializer becomes the global's body, and a body that
        // also held the `NAME: Type` pattern would check that annotation a second
        // time as if a local declared it.
        let pattern_ctx = LoweringContext.new();
        if (surface == TopLevelLetSurface.Source) {
            let introducer = v.token_range(stmt.introducer);
            // A `let` is refused, but the binding still lowers as the global it
            // was meant to be, so its readers resolve instead of cascading errors.
            if (v.tree.tokens.kinds[stmt.introducer] == root.syntax.TokenKind.Let) {
                self.diags.push(LoweringDiagnosticTopLevelLetIntroducer { span: introducer });
            }
            pattern_ctx.file_scope_introducer = introducer;
        }
        // A session binding is a local of the session, so `const` warns there as
        // it does in a body; only the source file's global introducer is the one
        // place `const` is right.
        warn_const_introducer(pattern_ctx, v, stmt.introducer);
        let pattern_id = match (stmt.pattern) {
            let node: root.syntax.AnyPattern => pattern(pattern_ctx, v, node),
            root.syntax.Missing => null,
        };
        let patterns = pattern_ctx.patterns;
        pattern_ctx.patterns = [];
        let (_, _, let pattern_diags, _) = pattern_ctx.finish(null);
        extend(self.diags, pattern_diags);

        let reject = (session_reason: string, source_reason: string) -> {
            self.diags.push(
                match (surface) {
                    TopLevelLetSurface.Session => {
                        LoweringDiagnosticInvalidPatternAscription {
                            reason: session_reason,
                            span: span,
                        }
                    },
                    TopLevelLetSurface.Source => {
                        LoweringDiagnosticInvalidTopLevelLet { reason: source_reason, span: span }
                    },
                },
            );
        };
        let bound = if (pattern_id != null) {
            patterns[pattern_id]
        } else {
            null
        };
        if (!(bound is PatternBind)) {
            reject(
                "session bindings require a single named binding",
                "a global variable binds a single name; destructuring and `_` are only available inside a body",
            );
            return null;
        }
        if (stmt.else_branch != null) {
            reject(
                "session bindings do not support patterns or `else`",
                "`const … else` needs a body to leave; a global variable's initializer must produce its value",
            );
            return null;
        }
        let subpat = bound.subpat;
        let type_annotation: TypeExpr? = if (subpat == null) {
            null
        } else {
            match (surface) {
                TopLevelLetSurface.Session => {
                    self.diags.push(
                        LoweringDiagnosticInvalidPatternAscription {
                            reason: "session bindings do not support patterns or `else`",
                            span: span,
                        },
                    );
                    return null;
                },
                TopLevelLetSurface.Source => {
                    let annotation = ascription_type_expr(patterns, subpat);
                    if (annotation == null) {
                        self.diags.push(
                            LoweringDiagnosticInvalidTopLevelLet {
                                reason: "only a type annotation may follow a global variable's name",
                                span: span,
                            },
                        );
                        return null;
                    }
                    check_wildcard_type(annotation, "a global variable's type", annotation.span, self.diags);
                    annotation
                },
            }
        };
        let name_span = match (stmt.pattern) {
            let binding: root.syntax.BindingPattern => v.name_range(binding.name),
            _ => span,
        };

        let ctx = LoweringContext.new();
        let initializer = match (stmt.init) {
            let init: root.syntax.AnyExpr => expression(ctx, v, init),
            root.syntax.Missing => null,
        };
        let (let body, let source_map, let ctx_diags, let ctx_env_refs) = ctx.finish(initializer);
        extend(self.diags, ctx_diags);
        extend(self.env_var_refs, ctx_env_refs);
        LetDef {
            name: bound.name,
            type_annotation: type_annotation,
            initializer: (body, source_map),
            origin: LetOrigin.Source,
            docstring: match (surface) {
                TopLevelLetSurface.Source => self.docstring(id.docs),
                TopLevelLetSurface.Session => null,
            },
            span: span,
            name_span: name_span,
        }
    }

    // ── Tests ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::test_registration @ d9be6853b
    // A top-level `test`/`testset` as a registration; one with no name or no
    // body (both reported by the parser) registers nothing.
    function test_registration(
        self,
        id: root.syntax.TestDef,
    ) -> TypedTestRegistration? throws never {
        let name = id.name;
        let body = id.body;
        if (!(name is root.syntax.AnyExpr) || !(body is root.syntax.Block)) {
            return null;
        }
        TypedTestRegistration {
            v: self.v,
            is_testset: self.v.tree.tokens.kinds[id.kw] == root.syntax.TokenKind.Testset,
            name: name,
            body: body,
            with: id.with,
        }
    }

    // ── Removed forms ──

    // port: baml_compiler2_ast/src/lower_tree/items.rs::Items::removed_item @ d9be6853b
    // A removed top-level form the parser kept the shape of: the migration
    // diagnostic the rowan lowering gave it, one per block, no cascade.
    function removed_item(self, id: root.syntax.RemovedItem) -> void throws never {
        let v = self.v;
        let span = v.range(id.span);
        let name_node = id.name;
        let name = if (name_node) {
            v.name(name_node)
        } else {
            null
        };
        match (v.tree.tokens.kinds[id.kw]) {
            // Legacy `client<llm> Name { ... }` config block: clients are plain
            // values now. The block's own `provider` names the client class the
            // suggested replacement constructs.
            root.syntax.TokenKind.Client => {
                let tokens = v.tree.tokens;
                let body: int[] = [];
                let idx = id.body.start;
                while (idx < id.body.end) {
                    if (!root.syntax.is_trivia(tokens.kinds[idx])) {
                        body.push(idx);
                    }
                    idx += 1;
                }
                // The value after `provider` runs to the end of its line: a quoted
                // string, or the usual bare word (`vertex-ai`, which lexes as several
                // tokens).
                let provider: string? = null;
                let i = 0;
                while (provider == null && i + 1 < body.length()) {
                    if (
                        tokens.kinds[body[i]] == root.syntax.TokenKind.Word
                            && v.text(body[i]) == "provider"
                    ) {
                        let start = v.token_range(body[i + 1]).start;
                        let rest = v.tree.slice(
                            root.syntax.TextRange { start: start, end: v.tree.utf8.length() },
                        );
                        let line = rest.split("\n").at(0) ?? rest;
                        let value = trim_end_matches(line.trim(), ",").trim();
                        provider = strip_string_delimiters(value);
                    }
                    i += 1;
                }
                self.diags.push(
                    LoweringDiagnosticClientBlockRemoved {
                        name: name ?? "MyClient",
                        provider: provider,
                        span: span,
                    },
                );
            },
            // Legacy `retry_policy` block: retry composes at the client boundary
            // now (ai.Retry).
            root.syntax.TokenKind.RetryPolicy => {
                self.diags.push(
                    LoweringDiagnosticRetryPolicyRemoved { name: name ?? "policy", span: span },
                );
            },
            // Generators are configured in `baml.toml`; the diagnostic points at
            // the `generator <name>` header, not the opaque body.
            root.syntax.TokenKind.Generator => {
                let kw = v.token_range(id.kw);
                let header = if (name_node) {
                    span_from(kw, v.name_range(name_node))
                } else {
                    kw
                };
                self.diags.push(LoweringDiagnosticGeneratorBlockInBaml { name: name, span: header });
            },
            root.syntax.TokenKind.TemplateString => {
                self.diags.push(LoweringDiagnosticTemplateStringRemoved { span: span });
            },
            // The parser's E0098 is the whole report.
            _ => {},
        }
    }
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::builtin_kind @ d9be6853b
// A `$rust_function`-style body: a block whose only content is one of the
// builtin markers.
function builtin_kind(v: View, block: root.syntax.Block) -> BuiltinKind? throws never {
    if (block.stmts) {
        return null;
    }
    let tail = block.tail;
    if (!(tail is root.syntax.PathExpr)) {
        return null;
    }
    if (tail.segments) {
        return null;
    }
    match (v.text(tail.head.token)) {
        "$rust_function" => BuiltinKind.Vm,
        "$rust_io_function" => BuiltinKind.Io,
        "$compiler_intrinsic" => BuiltinKind.Intrinsic,
        "$await_any" => BuiltinKind.AwaitAny,
        "$spawn" => BuiltinKind.Spawn,
        _ => null,
    }
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::interpolation_spans @ d9be6853b
// Every `${…}` interpolation's range in a template, nested ones included.
function interpolation_spans(
    v: View,
    parts: root.syntax.AnyTemplatePart[],
    out: root.syntax.TextRange[],
) -> void throws never {
    for (let part in parts) {
        match (part) {
            let interp: root.syntax.TemplateInterp => {
                out.push(v.range(interp.span));
            },
            let for_part: root.syntax.TemplateFor => interpolation_spans(v, for_part.body, out),
            let if_part: root.syntax.TemplateIf => {
                interpolation_spans(v, if_part.then_parts, out);
                for (let elif in if_part.elifs) {
                    interpolation_spans(v, elif.parts, out);
                }
                let else_part = if_part.else_part;
                if (else_part) {
                    interpolation_spans(v, else_part.parts, out);
                }
            },
            root.syntax.AnyTemplatePartChunk | root.syntax.Bogus => {},
        }
    }
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::Prompt @ d9be6853b
// The prompt literal shapes an LLM function accepts.
type Prompt = PromptBacktick | PromptQuoted;

class PromptBacktick {
    value: root.syntax.BacktickString,
}

class PromptQuoted {
    value: root.syntax.StringLit,
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::TypedLlmSpecSource @ d9be6853b
// The typed tree as a spec source.
class TypedLlmSpecSource {
    v: View,
    prompt: Prompt,
    // deviation: Rust's field `tools` would collide with the `tools` method.
    tools_value: root.syntax.AnyExpr?,
    // deviation: Rust's field `client`; `client` is a BAML keyword.
    client_value: root.syntax.AnyExpr?,

    implements LlmSpecSource {
        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedLlmSpecSource::prompt_span @ d9be6853b
        function prompt_span(self) -> root.syntax.TextRange throws never {
            match (self.prompt) {
                let backtick: PromptBacktick => self.v.range(backtick.value.span),
                let quoted: PromptQuoted => self.v.range(quoted.value.span),
            }
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedLlmSpecSource::prompt_segments @ d9be6853b
        function prompt_segments(self, ctx: LoweringContext) -> TemplateSegment[] throws never {
            match (self.prompt) {
                let backtick: PromptBacktick => template_segments(ctx, self.v, backtick.value),
                // A quoted prompt is the degenerate template: regular string literals
                // do not interpolate, so the decoded value is one text segment.
                let quoted: PromptQuoted => {
                    [
                        TemplateSegmentText {
                            value: strip_string_delimiters(self.v.text(quoted.value.token)),
                        },
                    ]
                },
            }
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedLlmSpecSource::tools @ d9be6853b
        function tools(
            self,
            ctx: LoweringContext,
            span: root.syntax.TextRange,
            wrap_bare_ref: (LoweringContext, int) -> int throws never,
        ) -> int? throws never {
            let v = self.v;
            let tools = self.tools_value;
            if (tools == null) {
                return null;
            }
            match (tools) {
                let array: root.syntax.ArrayLiteral => {
                    let elements = array.elements.map((element) -> {
                        // A bare function reference: normalized through ai.tool().
                        let is_bare_ref = element.value is root.syntax.PathExpr;
                        let id = expression(ctx, v, element.value);
                        if (is_bare_ref) {
                            wrap_bare_ref(ctx, id)
                        } else {
                            id
                        }
                    });
                    ctx.alloc_expr(ExprArray { elements: elements }, span)
                },
                // A non-list expression must already produce an `ai.Tool[]`.
                _ => expression(ctx, v, tools),
            }
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedLlmSpecSource::client_expr @ d9be6853b
        function client_expr(
            self,
            ctx: LoweringContext,
            span: root.syntax.TextRange,
        ) -> int throws never {
            let client_value = self.client_value;
            if (client_value != null) {
                expression(ctx, self.v, client_value)
            } else {
                ctx.alloc_expr(ExprMissing {}, span)
            }
        }
    }
}

// port: baml_compiler2_ast/src/lower_tree/items.rs::TypedTestRegistration @ d9be6853b
// A top-level `test`/`testset` of the typed tree.
class TypedTestRegistration {
    v: View,
    // deviation: Rust's field `is_set` would collide with the `is_set` method.
    is_testset: bool,
    name: root.syntax.AnyExpr,
    body: root.syntax.Block,
    with: root.syntax.WithClause?,

    implements TestRegistration {
        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedTestRegistration::is_set @ d9be6853b
        function is_set(self) -> bool throws never {
            self.is_testset
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedTestRegistration::body_span @ d9be6853b
        function body_span(self) -> root.syntax.TextRange throws never {
            self.v.range(self.body.span)
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedTestRegistration::lower_name @ d9be6853b
        function lower_name(self, ctx: InitTestContext) -> int throws never {
            expression(ctx.inner, self.v, self.name)
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedTestRegistration::lower_body @ d9be6853b
        function lower_body(
            self,
            ctx: InitTestContext,
            _span: root.syntax.TextRange,
        ) -> int throws never {
            if (self.is_testset) {
                testset_collector_body(ctx.inner, self.v, self.body, "testset")
            } else {
                lambda_body(ctx.inner, self.v, self.body)
            }
        }

        // port: baml_compiler2_ast/src/lower_tree/items.rs::TypedTestRegistration::lower_runner @ d9be6853b
        function lower_runner(
            self,
            ctx: InitTestContext,
            span: root.syntax.TextRange,
        ) -> int throws never {
            test_runner(ctx.inner, self.v, self.with, span)
        }
    }
}

// needs foundation: baml_syntax/src/token.rs::Tokens::prev_significant. The
// last non-trivia token before `idx`.
function prev_significant(tokens: root.syntax.Tokens, idx: int) -> int? throws never {
    let i = idx - 1;
    while (i >= 0) {
        if (!root.syntax.is_trivia(tokens.kinds[i])) {
            return i;
        }
        i -= 1;
    }
    null
}

// needs foundation: `matches!(kind, TokenKind::LegacyHashString | TokenKind::UnclosedHashString)`.
function is_hash_string(kind: root.syntax.TokenKind) -> bool throws never {
    match (kind) {
        root.syntax.TokenKind.LegacyHashString | root.syntax.TokenKind.UnclosedHashString => true,
        _ => false,
    }
}

// needs foundation: `Vec::extend`. Appends `items` to `out` in place.
function extend<T>(out: T[], items: T[]) -> void throws never {
    for (let item in items) {
        out.push(item);
    }
}

// needs foundation: `Vec::extend(Option)`. Appends `item` to `out` when present.
function push_some<T>(out: T[], item: T?) -> void throws never {
    if (item != null) {
        out.push(item);
    }
}

// needs foundation: `str::strip_prefix`.
function strip_prefix(text: string, prefix: string) -> string? throws never {
    if (text.starts_with(prefix)) {
        text.slice(prefix.length(), text.length())
    } else {
        null
    }
}
