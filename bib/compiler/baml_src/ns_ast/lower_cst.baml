// port: baml_compiler2_ast/src/lower_cst.rs @ d9be6853b
//
// Item-level desugarings shared by every reader: the `$init_test` registrar
// synthesis, the LLM client and prompt rules, the injected `@spec`
// parameters. The tree readers live in `lower_tree`.

// port: baml_compiler2_ast/src/lower_cst.rs::check_missing_type @ d9be6853b
// Report an `UnparseableType` when a just-lowered type is `Missing` at the
// root.
function check_missing_type(
    type_expr: TypeExpr,
    context: string,
    span: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> void throws never {
    if (type_expr.kind is TypeExprKindMissing) {
        diags.push(LoweringDiagnosticUnparseableType { context: context, span: span });
    }
}

// port: lower_cst.rs::ClassMethodContext. The class a method is declared in,
// for the companion bodies it needs.
class ClassMethodContext {
    name: string,
    generic_params: GenericParam[],
}

// port: baml_compiler2_ast/src/lower_cst.rs::append_spec_client_param @ d9be6853b
// Append the spec-mode client override parameter `client: ai.Client? = null`.
// A null override makes the runner fall back to the spec's default client.
function append_spec_client_param(
    params: Param[],
    defaults: FunctionDefaults,
    span: root.syntax.TextRange,
) -> void throws never {
    let client_ty = TypeExpr {
        kind: TypeExprKindPath {
            path: root.base.Path.compiler(["ai", "Client"]),
            generic_args: [],
            associated_type_bindings: [],
        },
        span: span,
    };
    push_null_default_param(params, defaults, "client", client_ty, span);
}

// port: baml_compiler2_ast/src/lower_cst.rs::append_spec_on_event_param @ d9be6853b
// Append the spec-mode listener parameter
// `on_event: ((ai.events.Event) -> void)? = null`. Both companion bodies
// thread it through unchanged; a null listener means no events are delivered.
function append_spec_on_event_param(
    params: Param[],
    defaults: FunctionDefaults,
    span: root.syntax.TextRange,
) -> void throws never {
    let event_ty = TypeExpr {
        kind: TypeExprKindPath {
            path: root.base.Path.compiler(["ai", "events", "Event"]),
            generic_args: [],
            associated_type_bindings: [],
        },
        span: span,
    };
    let listener_ty = TypeExpr {
        kind: TypeExprKindFunction {
            params: [FunctionTypeParam { name: null, optional: false, ty: event_ty }],
            ret: TypeExpr { kind: TypeExprKindNull {}, span: span },
            throws_: null,
        },
        span: span,
    };
    push_null_default_param(params, defaults, "on_event", listener_ty, span);
}

// The shared tail of the two `append_spec_*_param`s (inline in each in Rust):
// push `name: inner? = null`, its `null` default allocated in `defaults`.
function push_null_default_param(
    params: Param[],
    defaults: FunctionDefaults,
    name: string,
    inner: TypeExpr,
    span: root.syntax.TextRange,
) -> void throws never {
    let null_default = defaults.exprs.exprs.push(ExprNull {}) - 1;
    defaults.source_map.expr_spans.push(span);
    params.push(
        Param {
            name: name,
            type_expr: TypeExpr { kind: TypeExprKindOptional { inner: inner }, span: span },
            default: null_default,
            span: span,
            name_span: span,
        },
    );
}

// port: `RESERVED` in lower_cst.rs::reject_reserved_llm_params. Parameter
// names the LLM lowering owns, and what each is reserved for.
const RESERVED_LLM_PARAMS: (string, string)[] = [
    ("client", "the compiler-injected LLM client override"),
    ("on_event", "the compiler-injected LLM event listener override"),
    ("ctx", "the compiler-provided prompt context"),
];

// port: baml_compiler2_ast/src/lower_cst.rs::reject_reserved_llm_params @ d9be6853b
// Drop each parameter that collides with a reserved LLM binding, reporting
// it. `params` is filtered in place.
function reject_reserved_llm_params(
    params: Param[],
    function_name: string,
    diags: LoweringDiagnostic[],
) -> void throws never {
    let kept = params.filter((param) -> {
        let reserved = RESERVED_LLM_PARAMS.find((entry) -> {
            entry.0 == param.name
        });
        if (reserved == null) {
            return true;
        }
        let (let param_name, let reserved_for) = reserved;
        diags.push(
            LoweringDiagnosticReservedLlmParam {
                function_name: function_name,
                param_name: param_name,
                reserved_for: reserved_for,
                span: param.name_span,
            },
        );
        false
    });
    params.clear();
    for (let param in kept) {
        params.push(param);
    }
}

// port: lower_cst.rs::SHORTHAND_PROVIDERS. The builtin `"provider/model"`
// shorthand: each prefix and the provider constructor it names
// (`<pkg>.<Class>.new(model = ...)`). The ONE provider table: a literal
// `client "openai/gpt-4o-mini"` lowers straight to the constructor, and a
// dynamic `client:` lowers to `ai.clients.resolve(selector, providers)` with
// `providers` synthesized from this list. DRIFT HAZARD: mirrored at runtime
// by `ai.clients.resolve`. Azure is deliberately absent (see
// `AZURE_SHORTHAND_REMOVED`).
const SHORTHAND_PROVIDERS: (string, root.base.Path)[] = [
    ("openai", root.base.Path.compiler(["openai", "ResponsesClient", "new"])),
    ("openai-chat", root.base.Path.compiler(["openai", "ChatClient", "new"])),
    ("openai-decisions", root.base.Path.compiler(["openai", "DecisionsClient", "new"])),
    ("openai-images", root.base.Path.compiler(["openai", "ImageClient", "new"])),
    ("ollama", root.base.Path.compiler(["openai", "OllamaClient", "new"])),
    ("openrouter", root.base.Path.compiler(["openai", "OpenRouterClient", "new"])),
    ("anthropic", root.base.Path.compiler(["anthropic", "Client", "new"])),
    ("typesafeai", root.base.Path.compiler(["typesafeai", "Client", "new"])),
    ("google", root.base.Path.compiler(["google", "GeminiClient", "new"])),
    ("vertex", root.base.Path.compiler(["google", "VertexClient", "new"])),
    ("bedrock", root.base.Path.compiler(["aws", "BedrockClient", "new"])),
    ("ai-gateway-images", root.base.Path.compiler(["vercel", "AiGatewayImageClient", "new"])),
    ("claude-code", root.base.Path.compiler(["claude_code", "ClaudeCodeClient", "new"])),
];

// port: lower_cst.rs::AZURE_SHORTHAND_REMOVED. Why a literal
// `client: "azure/<model>"` is rejected; `ai.clients.resolve` says the same
// at runtime.
const AZURE_SHORTHAND_REMOVED: string = "there is no \"azure/<model>\" shorthand: an Azure request goes to a deployment, which a model name does not identify; build openai.AzureClient.new(model = ..., deployment_id = ..., resource_name = ...)";

// Rust's `str::split_once('/')`.
function split_once_slash(text: string) -> (string, string)? throws never {
    let at = text.index_of("/")
        ?? return null;
    (text.slice(0, at), text.slice(at + 1, text.length()))
}

// port: baml_compiler2_ast/src/lower_cst.rs::spec_client_provider @ d9be6853b
// The constructor a `"provider/model"` literal's provider names.
function spec_client_provider(client: string) -> root.base.Path? throws never {
    let (let prefix, _) = split_once_slash(client)
        ?? return null;
    let entry = SHORTHAND_PROVIDERS.find((e) -> {
        e.0 == prefix
    })
        ?? return null;
    entry.1
}

// port: baml_compiler2_ast/src/lower_cst.rs::warn_quoted_prompt_interpolation @ d9be6853b
// Warn on each `${` in a quoted prompt, which reaches the model verbatim.
// Searched in the raw token text so the span lands on the source; a quoted
// string's escapes never introduce or remove a `${`.
function warn_quoted_prompt_interpolation(
    text: string,
    range: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> void throws never {
    let marker = "${";
    // `match_indices`: non-overlapping, left to right, byte offsets.
    let rest = text;
    let offset = 0;
    while let at: int = rest.index_of(marker) {
        let start = range.start + offset + rest.slice(0, at).byte_length();
        diags.push(
            LoweringDiagnosticQuotedPromptInterpolation {
                span: root.syntax.TextRange { start: start, end: start + marker.byte_length() },
            },
        );
        let consumed = at + marker.length();
        offset += rest.slice(0, consumed).byte_length();
        rest = rest.slice(consumed, rest.length());
    }
}

// port: baml_compiler2_ast/src/lower_cst.rs::classify_client_string @ d9be6853b
// The builtin provider constructor a quoted `client "provider/model"`
// string names, or null after reporting why it names none.
function classify_client_string(
    function_name: string,
    text: string,
    span: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> LlmClient? throws never {
    let invalid = (reason: string) -> LlmClient? {
        diags.push(
            LoweringDiagnosticInvalidLlmClient {
                function_name: function_name,
                reason: reason,
                span: span,
            },
        );
        null
    };
    let split = split_once_slash(text);
    if (split == null) {
        return invalid(`"${text}" is not a "provider/model" string (no \`/\`)`);
    }
    let (let prefix, let model) = split;
    let constructor = spec_client_provider(text);
    if (constructor == null) {
        if (prefix == "azure") {
            return invalid(AZURE_SHORTHAND_REMOVED);
        }
        return invalid(
            `no builtin provider for prefix "${prefix}"; construct a client value instead (OpenAI-compatible endpoints: openai.GenericClient.new(base_url = ..., model = "${model}"))`,
        );
    }
    LlmClientProvider { constructor: constructor, model: model }
}

// port: baml_compiler2_ast/src/lower_cst.rs::reject_unquoted_client_shorthand @ d9be6853b
// The removed unquoted shorthand (`client: openai/gpt-4o-mini`) parses as a
// whitespace-free division chain; report it before it cascades into
// unresolved names. `text` is the binary expression's source.
function reject_unquoted_client_shorthand(
    function_name: string,
    text: string,
    span: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> bool throws never {
    // `char::is_whitespace` is Unicode whitespace.
    if (
        text.includes("/")
            && !text.chars().some((c) -> {
                c.is_whitespace()
            })
    ) {
        diags.push(
            LoweringDiagnosticInvalidLlmClient {
                function_name: function_name,
                reason: `quote the model string: client: "${text}"`,
                span: span,
            },
        );
        return true;
    }
    false
}

// port: baml_compiler2_ast/src/lower_cst.rs::init_test_key_from_path @ d9be6853b
// The `$init_test_<key>` suffix from a file's root-relative path: the
// extension stripped and every character other than a letter, digit or `_`
// replaced by `_`, e.g. `ns_arrays/arrays.baml` -> `ns_arrays_arrays`.
function init_test_key_from_path(path: string) -> string throws never {
    path_without_extension(path).chars()
        .map((c) -> {
            if (c.is_ascii_alphanumeric() || c == "_") {
                c
            } else {
                "_"
            }
        })
        .join("")
}

// Rust's `Path::with_extension("")`: the file name's extension (after its
// last `.`, unless that `.` starts the name) removed.
function path_without_extension(path: string) -> string throws never {
    let name_start = (path.last_index_of("/") ?? -1) + 1;
    let dot = path.last_index_of(".");
    if (dot != null && dot > name_start) {
        path.slice(0, dot)
    } else {
        path
    }
}

// port: baml_compiler2_ast/src/lower_cst.rs::test_owner_from_path @ d9be6853b
// The public owner of tests declared in `path`: `root`, qualified by each
// `ns_<name>` directory with a valid identifier name. Package names are
// deliberately left out, so ids survive a package rename.
function test_owner_from_path(path: string?) -> string throws never {
    let namespaces = path_parent_components(path ?? "").filter_map((component) -> {
        if (!component.starts_with("ns_")) {
            return null;
        }
        let name = component.slice(3, component.length());
        let chars = name.chars();
        let first = chars.at(0);
        let valid = first != null
            && (first.is_ascii_alphabetic() || first == "_")
            && chars.every((c) -> {
                c.is_ascii_alphanumeric() || c == "_"
            });
        if (valid) {
            name
        } else {
            null
        }
    });
    if (namespaces.length() == 0) {
        "root"
    } else {
        `root.${namespaces.join(".")}`
    }
}

// The `Normal` components of `path`'s parent directory (Rust's
// `path.parent().components()`): no root, `.` or `..`.
function path_parent_components(path: string) -> string[] throws never {
    let parts = path.split("/");
    parts.slice(0, parts.length() - 1).filter((part) -> {
        part != "" && part != "." && part != ".."
    })
}

// port: baml_compiler2_ast/src/lower_cst.rs::is_init_test_function @ d9be6853b
// Whether `name` is a synthesized `$init_test` registration function.
function is_init_test_function(name: string) -> bool throws never {
    name.starts_with("$init_test")
}

// port: lower_cst.rs::TestRegistration. A top-level `test` or `testset` as
// the registrar synthesis reads it, whichever tree it came from: the pieces
// lower into the registrar's arena when the call needs them.
interface TestRegistration {
    // A `testset` (registers a collector lambda) rather than a `test`.
    function is_set(self) -> bool throws never;
    // The body's range: the registered lambda's span, so HIR scope lookup by
    // offset finds the lambda the body's statements belong to.
    function body_span(self) -> root.syntax.TextRange throws never;
    function lower_name(self, ctx: InitTestContext) -> int throws never;
    // A test's body as a plain lambda body; a testset's as the collector
    // lambda's body (`testset` bound).
    function lower_body(
        self,
        ctx: InitTestContext,
        span: root.syntax.TextRange,
    ) -> int throws never;
    // The `with` runner, or `null` when there is none.
    function lower_runner(
        self,
        ctx: InitTestContext,
        span: root.syntax.TextRange,
    ) -> int throws never;
}

// port: baml_compiler2_ast/src/lower_cst.rs::synthesize_init_test_function @ d9be6853b
// A `$init_test_<key>` function registering every test and testset of a
// file into its `testing.TestCollector` parameter. The suffix comes from the
// file path (stable across compilations, unlike a load-order `FileId`);
// without a path the name is plain `$init_test`.
function synthesize_init_test_function(
    registrations: TestRegistration[],
    file_path: string?,
    explicit_test_owner: string?,
    diags: LoweringDiagnostic[],
    env_var_refs: EnvVarRef[],
) -> FunctionDef throws never {
    let fn_name = if (file_path != null) {
        `$init_test_${init_test_key_from_path(file_path)}`
    } else {
        "$init_test"
    };
    let span = root.syntax.TextRange.empty(0);
    let ctx = InitTestContext.new();
    let test_owner = explicit_test_owner ?? test_owner_from_path(file_path);

    // One statement per registration, then a block with a null tail.
    let stmt_ids = registrations.map((reg) -> {
        let stmt_expr = synthesize_register_call(reg, test_owner, ctx);
        ctx.alloc_stmt(StmtExpr { value: stmt_expr }, span)
    });
    let null_expr = ctx.alloc_expr(ExprNull {}, span);
    let block_expr = ctx.alloc_expr(ExprBlock { stmts: stmt_ids, tail_expr: null_expr }, span);

    let (let body, let source_map, let finish_diags, let finish_env_refs) = ctx.finish(block_expr);
    for (let d in finish_diags) {
        diags.push(d);
    }
    for (let r in finish_env_refs) {
        env_var_refs.push(r);
    }

    // The single parameter, spelled with a leading space so no test body can
    // name it.
    let registry_param = Param {
        name: REGISTRY_PARAM,
        type_expr: test_collector_type(span),
        default: null,
        span: span,
        name_span: span,
    };

    FunctionDef {
        name: fn_name,
        generic_params: [],
        params: [registry_param],
        defaults: FunctionDefaults.empty(),
        // Unit, like the `null` tail: a synthesized signature is complete.
        return_type: TypeExpr { kind: TypeExprKindNull {}, span: span },
        throws_: null,
        body: FunctionBodyDefExpr { v0: body, v1: source_map },
        declarative_meta: null,
        metadata: FunctionMetadata.language_internal(FunctionOrigin.TestInitializer),
        attributes: [],
        docstring: null,
        header_title: null,
        is_tagged_template_tag: false,
        directives: NativeDirectives.none(),
        trace_hook: null,
        span: span,
        name_span: span,
    }
}

// The `$init_test` registry parameter's name.
const REGISTRY_PARAM: string = " __registry";

// `testing.TestCollector`, the registry's type (written twice in Rust).
function test_collector_type(span: root.syntax.TextRange) -> TypeExpr throws never {
    TypeExpr {
        kind: TypeExprKindPath {
            path: root.base.Path.compiler(["testing", "TestCollector"]),
            generic_args: [],
            associated_type_bindings: [],
        },
        span: span,
    }
}

// port: baml_compiler2_ast/src/lower_cst.rs::synthesize_register_call @ d9be6853b
// One `register_test_at(owner, name, lambda, runner)` or
// `register_test_set_at(owner, name, collector_lambda, runner)` call on the
// registry.
function synthesize_register_call(
    reg: TestRegistration,
    test_owner: string,
    ctx: InitTestContext,
) -> int throws never {
    let span = root.syntax.TextRange.empty(0);
    // The body lowers into `$init_test`'s own arena.
    let lambda_body = reg.lower_body(ctx, span);
    let (let params, let register) = if (reg.is_set()) {
        let collector_param = Param {
            name: "testset",
            type_expr: test_collector_type(span),
            default: null,
            span: span,
            name_span: span,
        };
        ([collector_param], "register_test_set_at")
    } else {
        let no_params: Param[] = [];
        (no_params, "register_test_at")
    };
    let lambda_def = LambdaDef {
        kind: LambdaKind.Anonymous,
        params: params,
        defaults: FunctionDefaults.empty(),
        return_type: TypeExpr { kind: TypeExprKindNull {}, span: span },
        throws_: null,
        body: lambda_body,
        span: span,
    };

    let method_call_target = ctx.alloc_expr(ExprPath { value: root.base.Path.new([REGISTRY_PARAM, register]) }, span);
    let name_arg = reg.lower_name(ctx);
    let owner_arg = ctx.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: test_owner } }, span);
    // The lambda carries the body's real range so HIR scope lookup by offset
    // finds the lambda's scope (a synthetic span, disjoint from the body's
    // statements, would leave every local unresolved). The range is unique per
    // test block, so lambda scopes stay distinct.
    let lambda_arg = ctx.alloc_expr(ExprLambda { value: lambda_def }, reg.body_span());
    let runner_arg = reg.lower_runner(ctx, span);

    ctx.alloc_expr(
        ExprCall {
            callee: method_call_target,
            type_args: [],
            args: [
                CallArg.positional(owner_arg),
                CallArg.positional(name_arg),
                CallArg.positional(lambda_arg),
                CallArg.positional(runner_arg),
            ],
        },
        span,
    )
}
