// port: baml_compiler2_ast/src/companions.rs @ d9be6853b
//
// Companion function expansion. A companion is a compiler-generated function
// derived from a parent; each expander reads a `FunctionDef` and may return a
// complete companion `FunctionDef`, which flows through the later stages with
// no special-casing. Every LLM function gets `@spec` (the bound, unrun
// `ai.FunctionSpec<Out>`), `@render_prompt`, `@build_request` (a
// network-free request preview), `@parse` (a network-free parse of a reply)
// and, when it cannot hold tools, `@stream`.

// port: baml_compiler2_ast/src/companions.rs::expand_companions @ d9be6853b
// Run every companion expander on `func`, a top-level function or a method.
function expand_companions(
    func: FunctionDef,
    owner_class_name: string?,
    owner_generic_param_names: string[],
) -> FunctionDef[] throws never {
    [
        llm_spec(func),
        llm_render_prompt(func, owner_class_name, owner_generic_param_names),
        llm_build_request(func, owner_class_name, owner_generic_param_names),
        llm_parse(func),
        llm_stream(func, owner_class_name, owner_generic_param_names),
    ]
        .filter_map((companion) -> {
            companion
        })
}

// port: baml_compiler2_ast/src/companions.rs::spec_llm_meta @ d9be6853b
// The parent's LLM metadata when its spec desugar succeeded, the gate for
// every companion: null for non-LLM functions and for LLM functions whose
// prompt or client was unusable (a diagnostic already fired).
function spec_llm_meta(parent: FunctionDef) -> LlmBodyDef? throws never {
    match (parent.declarative_meta) {
        let meta: DeclarativeMetaLlm
            if meta.value.companion_bodies.some((entry) -> {
            entry.0 == "spec"
        }) => meta.value,
        _ => null,
    }
}

// port: baml_compiler2_ast/src/companions.rs::is_injected_llm_param @ d9be6853b
// Whether `name` is a parameter the compiler injects into every LLM
// function: the `client` and `on_event` per-call overrides.
function is_injected_llm_param(name: string) -> bool throws never {
    name == "client" || name == "on_event"
}

// port: baml_compiler2_ast/src/companions.rs::own_params @ d9be6853b
// The function's own parameters: the injected overrides belong to the
// runner, never to a companion's surface.
function own_params(parent: FunctionDef) -> Param[] throws never {
    parent.params.filter((p) -> {
        !is_injected_llm_param(p.name)
    })
}

// The parent's generic parameter names (inline in each expander in Rust).
function generic_param_names(parent: FunctionDef) -> string[] throws never {
    parent.generic_params.map((p) -> {
        p.name
    })
}

// A compiler path type with no arguments, spanning `span`.
function compiler_path_type(
    segments: string[],
    span: root.syntax.TextRange,
    generic_args: TypeExpr[] = [],
) -> TypeExpr throws never {
    TypeExpr {
        kind: TypeExprKindPath {
            path: root.base.Path.compiler(segments),
            generic_args: generic_args,
            associated_type_bindings: [],
        },
        span: span,
    }
}

// port: baml_compiler2_ast/src/companions.rs::companion_def @ d9be6853b
function companion_def(
    parent: FunctionDef,
    name: string,
    params: Param[],
    return_type: TypeExpr?,
    body: (ExprBody, AstSourceMap),
) -> FunctionDef throws never {
    let trace_passthrough = name.ends_with("@spec") || name.ends_with("@stream");
    let (let exprs, let source_map) = body;
    FunctionDef {
        name: name,
        // divergence?: Rust clones `generic_params` and `defaults`; here the
        // companion shares the parent's (classes are references). Safe while
        // nothing mutates them after expansion.
        generic_params: parent.generic_params,
        params: params,
        defaults: parent.defaults,
        return_type: return_type,
        throws_: null,
        body: FunctionBodyDefExpr { v0: exprs, v1: source_map },
        declarative_meta: null,
        metadata: FunctionMetadata {
            ...FunctionMetadata.user_facing(FunctionOrigin.Companion),
            trace_passthrough: trace_passthrough,
        },
        attributes: [],
        docstring: parent.docstring,
        header_title: null,
        is_tagged_template_tag: parent.is_tagged_template_tag,
        directives: NativeDirectives.none(),
        trace_hook: null,
        span: parent.span,
        name_span: parent.name_span,
    }
}

// port: baml_compiler2_ast/src/companions.rs::llm_spec @ d9be6853b
// The `<Fn>@spec` companion: the function's parameters in, an
// `ai.FunctionSpec<Out>` out. The body was pre-lowered in `lower_cst` and
// stashed under the `"spec"` key.
function llm_spec(parent: FunctionDef) -> FunctionDef? throws never {
    let llm = spec_llm_meta(parent)
        ?? return null;
    let entry = llm.companion_bodies.find((e) -> {
        e.0 == "spec"
    })
        ?? return null;
    let out = parent.return_type
        ?? return null;
    let return_type = compiler_path_type(["ai", "FunctionSpec"], parent.span, generic_args = [out]);
    companion_def(parent, `${parent.name}@spec`, own_params(parent), return_type, entry.1)
}

// port: baml_compiler2_ast/src/companions.rs::llm_render_prompt @ d9be6853b
// The `<Fn>@render_prompt` companion: the spec's prompt rendered with the
// return type's output-format text, as a structural `ai.Prompt`.
function llm_render_prompt(
    parent: FunctionDef,
    owner_class_name: string?,
    owner_generic_param_names: string[],
) -> FunctionDef? throws never {
    if (spec_llm_meta(parent) == null || parent.return_type == null) {
        return null;
    }
    let params = own_params(parent);
    let body = synthesize_spec_render_prompt_body(
        parent.name,
        params,
        generic_param_names(parent),
        owner_class_name,
        owner_generic_param_names,
        parent.span,
    );
    let return_type = compiler_path_type(["ai", "Prompt"], parent.span);
    companion_def(parent, `${parent.name}@render_prompt`, params, return_type, body)
}

// port: baml_compiler2_ast/src/companions.rs::llm_build_request @ d9be6853b
// The `<Fn>@build_request` companion: the parent's parameters plus its
// injected `client` override, delegating to the spec's pure
// `FunctionSpec.build_request`. It keeps `client` (default-client semantics)
// but not `on_event`: a request preview never runs the agent.
function llm_build_request(
    parent: FunctionDef,
    owner_class_name: string?,
    owner_generic_param_names: string[],
) -> FunctionDef? throws never {
    if (spec_llm_meta(parent) == null) {
        return null;
    }
    let params = parent.params.filter((p) -> {
        p.name != "on_event"
    });
    let body = synthesize_spec_build_request_body(
        parent.name,
        own_params(parent),
        generic_param_names(parent),
        owner_class_name,
        owner_generic_param_names,
        parent.span,
    );
    let return_type = compiler_path_type(["baml", "http", "Request"], parent.span);
    companion_def(parent, `${parent.name}@build_request`, params, return_type, body)
}

// port: baml_compiler2_ast/src/companions.rs::llm_parse @ d9be6853b
// The `<Fn>@parse` companion: a network-free parse of an existing reply
// string into the function's return type.
function llm_parse(parent: FunctionDef) -> FunctionDef? throws never {
    if (spec_llm_meta(parent) == null) {
        return null;
    }
    let return_type = parent.return_type
        ?? return null;
    let json_param = Param {
        name: "json",
        type_expr: TypeExpr { kind: TypeExprKindString {}, span: parent.span },
        default: null,
        span: parent.span,
        name_span: parent.name_span,
    };
    let body = synthesize_spec_parse_body(return_type, parent.span);
    companion_def(parent, `${parent.name}@parse`, [json_param], return_type, body)
}

// port: baml_compiler2_ast/src/companions.rs::llm_stream @ d9be6853b
// The `<Fn>@stream` companion: one-turn streaming over the function's own
// spec, returning `ai.stream.Stream<Out>`, with the injected `client`
// narrowed to `ai.stream.StreamingClient?`. A function that can hold tools
// gets none: streaming does not run the tool loop.
function llm_stream(
    parent: FunctionDef,
    owner_class_name: string?,
    owner_generic_param_names: string[],
) -> FunctionDef? throws never {
    let llm = spec_llm_meta(parent)
        ?? return null;
    if (llm.has_tools) {
        return null;
    }
    let out = parent.return_type
        ?? return null;
    let span = parent.span;
    // Partial and final values share the return type.
    let type_args = [out];
    let return_type = compiler_path_type(["ai", "stream", "Stream"], span, generic_args = type_args);

    let params = parent.params.map((param) -> {
        if (param.name == "client") {
            let streaming_client = compiler_path_type(["ai", "stream", "StreamingClient"], span);
            Param {
                ...param,
                type_expr: TypeExpr { kind: TypeExprKindOptional { inner: streaming_client }, span: span },
            }
        } else {
            param
        }
    });

    let body = synthesize_spec_stream_body(
        parent.name,
        own_params(parent),
        generic_param_names(parent),
        owner_class_name,
        owner_generic_param_names,
        type_args,
        span,
    );
    let stream = companion_def(parent, `${parent.name}@stream`, params, return_type, body);
    // `@stream` is the LLM call when a caller streams, so it carries the
    // parent's client for telemetry, but none of its companion bodies or
    // prompt geometry: those belong to the declaration.
    stream.declarative_meta
        = DeclarativeMetaLlm {
            value: LlmBodyDef {
                client_: llm.client_,
                companion_bodies: [],
                prompt_spans: null,
                prompt_segments: [],
                has_tools: llm.has_tools,
                span: llm.span,
            },
        };
    stream
}
