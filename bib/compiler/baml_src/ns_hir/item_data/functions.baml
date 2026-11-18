// port: baml_compiler2_hir/src/item_data/functions.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_data/functions.rs::FunctionData @ d9be6853b
// Span-free semantic data for a function's *signature*. The body has its own
// query (`function_body`), so editing a body cannot invalidate anything that
// only depends on the signature.
class FunctionData {
    name: string,
    // Generic type parameters, each with its conjunction of bounds.
    generic_params: GenericParamData[],
    // Every type reference in this function's signature (bounds, parameter
    // types, return type, throws), scoped to the item.
    type_refs: TypeRefStore,
    params: FunctionParamData[],
    return_type: int?,
    throws_: int?,
    metadata: root.ast.FunctionMetadata,
    docstring: string?,
    // The `//#` title directly above the declaration, for the visualizer.
    header_title: string?,
    // Set when the fn def had a `//baml:tagged_string` marker.
    is_tagged_template_tag: bool,
}

// port: baml_compiler2_hir/src/item_data/functions.rs::FunctionSourceMap @ d9be6853b
// Spans for a `Function`, parallel to `FunctionData`.
class FunctionSourceMap {
    // Full source span of the declaration.
    span: root.syntax.TextRange,
    // Span of just the function's name.
    name_span: root.syntax.TextRange,
    // Spans for every node in `FunctionData.type_refs`.
    type_refs: TypeRefSourceMap,
    // One span per parameter, parallel to `FunctionData.params`.
    param_spans: root.syntax.TextRange[],
}

// port: baml_compiler2_hir/src/item_data/functions.rs::enclosing_type_generic_param_count @ d9be6853b
// How many generic parameters the function's enclosing type contributes:
// zero for a free function and for a method whose generics live on an
// out-of-body `implements` block; a generic class's method reports the
// class's.
function enclosing_type_generic_param_count(db: Db, function_: int) -> int throws never {
    db.memo.enclosing_type_generic_param_count.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        file_item_tree(db, loc.file).enclosing_type_generic_params(loc.id).length()
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::function_data @ d9be6853b
// Semantic data for one function signature. Span-free.
function function_data(db: Db, function_: int) -> FunctionData throws never {
    db.memo.function_data.get(function_, () -> {
        lower_function(db, function_).0
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::function_source_map @ d9be6853b
// Spans for one function signature, kept apart from `function_data`.
function function_source_map(db: Db, function_: int) -> FunctionSourceMap throws never {
    db.memo.function_source_map.get(function_, () -> {
        lower_function(db, function_).1
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::FunctionLlmMeta @ d9be6853b
// The span-free facts an LLM function's `declarative_meta` exposes: its
// declared client name (itself optional). `function_llm_meta` is null for a
// non-LLM function.
class FunctionLlmMeta {
    client_name: string?,
}

// port: baml_compiler2_hir/src/item_data/functions.rs::function_llm_meta @ d9be6853b
// The `FunctionLlmMeta` projection for one function, or null when it is not
// an LLM function.
function function_llm_meta(db: Db, function_: int) -> FunctionLlmMeta? throws never {
    db.memo.function_llm_meta.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        match (file_item_tree(db, loc.file).functions[loc.id].declarative_meta) {
            let llm: root.ast.DeclarativeMetaLlm => {
                FunctionLlmMeta { client_name: llm.value.client_ }
            },
            _ => null,
        }
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::llm_prompt_spans @ d9be6853b
// The source geometry of an LLM function's prompt literal, or null for
// non-LLM functions and unusable prompts.
function llm_prompt_spans(db: Db, function_: int) -> root.ast.LlmPromptSpans? throws never {
    db.memo.llm_prompt_spans.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        match (file_item_tree(db, loc.file).functions[loc.id].declarative_meta) {
            let llm: root.ast.DeclarativeMetaLlm => llm.value.prompt_spans,
            _ => null,
        }
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::llm_prompt_segments @ d9be6853b
// An LLM function's prompt template as written, or null for non-LLM
// functions and unusable prompts (no `@spec` companion was synthesized). Its
// expr ids index the body of that companion.
function llm_prompt_segments(db: Db, function_: int) -> root.ast.TemplateSegment[]? throws never {
    db.memo.llm_prompt_segments.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        match (file_item_tree(db, loc.file).functions[loc.id].declarative_meta) {
            let llm: root.ast.DeclarativeMetaLlm
                if llm.value.companion_bodies.some((entry) -> {
                entry.0 == "spec"
            }) => llm.value.prompt_segments,
            _ => null,
        }
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::ElaboratedFunctionData @ d9be6853b
// Span-free semantic data for a function's *elaborated* signature: the
// canonical callable view TIR consumes (see `elaborated_function_signature`
// for the elaboration rules).
class ElaboratedFunctionData {
    name: string,
    user_generic_params: string[],
    // Fresh `__effect_param_N` names minted for callback params with omitted
    // throws, in parameter order.
    synthetic_effect_params: string[],
    // The arena for the elaborated types below, distinct from
    // `FunctionData.type_refs`.
    type_refs: TypeRefStore,
    params: ElaboratedParamData[],
    return_type: int?,
    throws_: int?,
}

// port: baml_compiler2_hir/src/item_data/functions.rs::ElaboratedParamData @ d9be6853b
// A parameter of an elaborated signature. `type_ref` is total: elaboration
// substitutes `Unknown` for a missing annotation.
class ElaboratedParamData {
    name: string,
    type_ref: int,
    has_default: bool,
}

// port: baml_compiler2_hir/src/item_data/functions.rs::ElaboratedFunctionSourceMap @ d9be6853b
// Spans for an `ElaboratedFunctionData`. Synthetic nodes carry empty ranges.
class ElaboratedFunctionSourceMap {
    type_refs: TypeRefSourceMap,
}

// port: baml_compiler2_hir/src/item_data/functions.rs::elaborated_function_data @ d9be6853b
// Elaborated signature for one function. Span-free.
function elaborated_function_data(db: Db, function_: int) -> ElaboratedFunctionData throws never {
    db.memo.elaborated_function_data.get(function_, () -> {
        lower_elaborated(db, function_).0
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::elaborated_function_source_map @ d9be6853b
// Spans for one elaborated signature, kept apart from
// `elaborated_function_data`.
function elaborated_function_source_map(
    db: Db,
    function_: int,
) -> ElaboratedFunctionSourceMap throws never {
    db.memo.elaborated_function_source_map.get(function_, () -> {
        lower_elaborated(db, function_).1
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::lower_elaborated @ d9be6853b
// Runs the shared `TypeExpr`-based elaboration, then lowers its output into a
// span-free arena. Only the representation changes here.
function lower_elaborated(
    db: Db,
    function_: int,
) -> (ElaboratedFunctionData, ElaboratedFunctionSourceMap) throws never {
    let sig = elaborated_function_signature(db, function_);

    let type_refs = TypeRefBuilder.new();
    let params = sig.params.map((param) -> {
        ElaboratedParamData {
            name: param.name,
            type_ref: type_refs.lower(param.ty.value),
            has_default: param.has_default,
        }
    });
    let return_type = lower_type_expr_opt(type_refs, sig.return_type?.value);
    let throws_ = lower_type_expr_opt(type_refs, sig.throws_?.value);
    let (let store, let spans) = type_refs.finish();

    (
        ElaboratedFunctionData {
            name: sig.name,
            user_generic_params: sig.user_generic_params,
            synthetic_effect_params: sig.synthetic_effect_params,
            type_refs: store,
            params: params,
            return_type: return_type,
            throws_: throws_,
        },
        ElaboratedFunctionSourceMap { type_refs: spans },
    )
}

// port: baml_compiler2_hir/src/item_data/functions.rs::MethodOwner @ d9be6853b
// The item a method belongs to, as a `Loc` id. Mirrors `ItemTreeMethodOwner`:
// an in-body `implements I { ... }` method is owned by its impl block.
type MethodOwner = MethodOwnerClass | MethodOwnerInterface | MethodOwnerImpl;

class MethodOwnerClass {
    value: int,
}

class MethodOwnerInterface {
    value: int,
}

// A method of an `implements` block, in-class and out-of-body alike.
class MethodOwnerImpl {
    value: int,
}

// port: baml_compiler2_hir/src/item_data/functions.rs::method_owner @ d9be6853b
// The item `method` belongs to, or null for a top-level function.
function method_owner(db: Db, method: int) -> MethodOwner? throws never {
    db.memo.method_owner.get(method, () -> {
        let loc = db.function_locs.get(method);
        match (file_item_tree(db, loc.file).method_owners.get(loc.id)) {
            let owner: ItemTreeMethodOwnerClass => {
                MethodOwnerClass { value: db.class_locs.intern(loc.file, owner.value) }
            },
            let owner: ItemTreeMethodOwnerInterface => {
                MethodOwnerInterface { value: db.interface_locs.intern(loc.file, owner.value) }
            },
            let owner: ItemTreeMethodOwnerImpl => {
                MethodOwnerImpl { value: db.impl_locs.intern(loc.file, owner.value) }
            },
            null => null,
        }
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::function_has_body @ d9be6853b
// Whether `function_` has a body: the ONLY distinction between a default and
// a required interface method.
function function_has_body(db: Db, function_: int) -> bool throws never {
    db.memo.function_has_body.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        file_item_tree(db, loc.file).functions[loc.id].body != null
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::is_required_interface_method @ d9be6853b
// A REQUIRED interface method: a bodyless function item owned by an
// interface. Body-lowering consumers (MIR, emit) skip it.
function is_required_interface_method(db: Db, function_: int) -> bool throws never {
    db.memo.is_required_interface_method.get(function_, () -> {
        !function_has_body(db, function_) && method_owner(db, function_) is MethodOwnerInterface
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::MethodInterfaceTarget @ d9be6853b
// The interface target a method was declared under, when it sits inside an
// `implements I { ... }` block, plus that block's associated-type bindings.
// The target stays an unresolved `TypeRef`; TIR resolves it lazily.
class MethodInterfaceTarget {
    type_refs: TypeRefStore,
    target: int,
    associated_type_bindings: AssociatedTypeBindingData[],
}

// port: baml_compiler2_hir/src/item_data/functions.rs::MethodInterfaceTargetSourceMap @ d9be6853b
// Spans for a `MethodInterfaceTarget`.
class MethodInterfaceTargetSourceMap {
    type_refs: TypeRefSourceMap,
    // Parallel to `MethodInterfaceTarget.associated_type_bindings`.
    associated_type_bindings: AssociatedTypeBindingSourceMap[],
}

// port: baml_compiler2_hir/src/item_data/functions.rs::method_interface_target @ d9be6853b
// See `MethodInterfaceTarget`. Span-free; null for class-level methods and
// interface default methods.
function method_interface_target(db: Db, method: int) -> MethodInterfaceTarget? throws never {
    db.memo.method_interface_target.get(method, () -> {
        let lowered = lower_interface_target(db, method);
        if (lowered == null) {
            return null;
        }
        lowered.0
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::method_interface_target_source_map @ d9be6853b
// Spans for `method_interface_target`.
function method_interface_target_source_map(
    db: Db,
    method: int,
) -> MethodInterfaceTargetSourceMap? throws never {
    db.memo.method_interface_target_source_map.get(method, () -> {
        let lowered = lower_interface_target(db, method);
        if (lowered == null) {
            return null;
        }
        lowered.1
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::lower_interface_target @ d9be6853b
function lower_interface_target(
    db: Db,
    method: int,
) -> (MethodInterfaceTarget, MethodInterfaceTargetSourceMap)? throws never {
    let loc = db.function_locs.get(method);
    let item_tree = file_item_tree(db, loc.file);
    let target_expr = item_tree.method_to_iface_target.get(loc.id)
        ?? return null;
    let bindings = item_tree.method_to_iface_associated_type_bindings.get(loc.id) ?? [];

    let type_refs = TypeRefBuilder.new();
    let target = type_refs.lower(target_expr);
    let associated_type_bindings = bindings.map((binding) -> {
        AssociatedTypeBindingData {
            name: binding.name,
            type_ref: lower_type_expr_opt(type_refs, binding.type_expr),
        }
    });
    let (let store, let spans) = type_refs.finish();

    (
        MethodInterfaceTarget {
            type_refs: store,
            target: target,
            associated_type_bindings: associated_type_bindings,
        },
        MethodInterfaceTargetSourceMap {
            type_refs: spans,
            associated_type_bindings: bindings.map((binding) -> {
                AssociatedTypeBindingSourceMap { span: binding.span, name_span: binding.name_span }
            }),
        },
    )
}

// port: baml_compiler2_hir/src/item_data/functions.rs::lower @ d9be6853b
// deviation: named `lower_function` (see `lower_class`).
// Type refs are allocated in a fixed order (bounds, params, return, throws).
function lower_function(db: Db, function_: int) -> (FunctionData, FunctionSourceMap) throws never {
    let loc = db.function_locs.get(function_);
    let item_tree = file_item_tree(db, loc.file);
    let item_source_map = file_item_tree_source_map(db, loc.file);
    let data = item_tree.functions[loc.id];

    let type_refs = TypeRefBuilder.new();
    let generic_params = lower_generic_params(data.generic_params, type_refs);
    let params = data.params.map((param) -> {
        FunctionParamData {
            name: param.name,
            type_ref: lower_type_expr_opt(type_refs, param.type_expr),
            has_default: param.default != null,
        }
    });
    let return_type = lower_type_expr_opt(type_refs, data.return_type);
    let throws_ = lower_type_expr_opt(type_refs, data.throws_);
    let (let store, let spans) = type_refs.finish();

    (
        FunctionData {
            name: data.name,
            generic_params: generic_params,
            type_refs: store,
            params: params,
            return_type: return_type,
            throws_: throws_,
            metadata: data.metadata,
            docstring: data.docstring,
            header_title: data.header_title,
            is_tagged_template_tag: data.is_tagged_template_tag,
        },
        FunctionSourceMap {
            span: data.span,
            name_span: item_source_map.function_name_spans.get(loc.id) ?? root.syntax.TextRange.empty(0),
            type_refs: spans,
            param_spans: data.params.map((param) -> {
                param.span
            }),
        },
    )
}

// port: baml_compiler2_hir/src/item_data/functions.rs::function_trace_hook @ d9be6853b
// Span-free declaration hook reference; the directive's span is queried
// separately.
function function_trace_hook(db: Db, function_: int) -> string[]? throws never {
    db.memo.function_trace_hook.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        file_item_tree(db, loc.file).functions[loc.id].trace_hook?.path
    })
}

// port: baml_compiler2_hir/src/item_data/functions.rs::function_trace_hook_span @ d9be6853b
function function_trace_hook_span(db: Db, function_: int) -> root.syntax.TextRange? throws never {
    db.memo.function_trace_hook_span.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        file_item_tree(db, loc.file).functions[loc.id].trace_hook?.span
    })
}
