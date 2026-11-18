// port: baml_compiler2_hir/src/semantic_index.rs @ d9be6853b
//
// Per-file semantic index, the central data structure of the HIR. Built by
// `SemanticIndexBuilder`, cached per file by `file_semantic_index`.
// Scope ids (`FileScopeId`), expression, statement and pattern ids are `int`s.

// port: semantic_index.rs::ExprMetadataScope. Namespace for arena-local
// expression ids: a function or lambda body and its parameter-default
// expressions use separate `ExprBody` arenas, and every nested lambda starts
// another pair. Pairing the arena owner with the expression id makes
// expression identity unique within a file. Each variant carries the owning
// scope's id.
type ExprMetadataScope = ExprMetadataScopeBody | ExprMetadataScopeParameterDefault;

class ExprMetadataScopeBody {
    value: int,
}

class ExprMetadataScopeParameterDefault {
    value: int,
}

// port: semantic_index.rs::ExprMetadataKey
class ExprMetadataKey {
    scope: ExprMetadataScope,
    expr: int,

    // port: baml_compiler2_hir/src/semantic_index.rs::ExprMetadataKey::new @ d9be6853b
    function new(scope: ExprMetadataScope, expr: int) -> ExprMetadataKey throws never {
        ExprMetadataKey { scope: scope, expr: expr }
    }

    implements baml.ops.Equals {}

    // port: the derived `Ord` of ExprMetadataKey and ExprMetadataScope: `Body`
    // before `ParameterDefault`, then the scope id, then the expression id.
    implements baml.ops.Compare {
        function cmp(self, other: Self) -> baml.ops.Ordering throws never {
            let (let rank, let scope) = expr_metadata_scope_order(self.scope);
            let (let other_rank, let other_scope) = expr_metadata_scope_order(other.scope);
            let by_rank = rank.cmp(other_rank);
            if (by_rank != baml.ops.Ordering.Equal) {
                return by_rank;
            }
            let by_scope = scope.cmp(other_scope);
            if (by_scope != baml.ops.Ordering.Equal) {
                return by_scope;
            }
            self.expr.cmp(other.expr)
        }
    }
}

// The derived `Ord` of `ExprMetadataScope` as a pair: the variant's
// declaration index, then its scope id.
function expr_metadata_scope_order(scope: ExprMetadataScope) -> (int, int) throws never {
    match (scope) {
        let s: ExprMetadataScopeBody => (0, s.value),
        let s: ExprMetadataScopeParameterDefault => (1, s.value),
    }
}

// port: semantic_index.rs::PathResolution. HIR's reading of a value path's
// first segment, recorded for every `Path` expression while the lexical scope
// stack is active. A binding wins over everything (`#4543`: a local named
// `reflect` shadows the package). Otherwise the head is a package or a plain
// name (`PathHead`); which item a plain name or a package path reaches is the
// checker's to complete.
type PathResolution = PathResolutionLocal | PathResolutionItem;

// A binding or parameter in scope; every later segment is a member of its
// value.
class PathResolutionLocal {
    value: BindingId,
}

// Not a binding: an item path starting at `value`.
class PathResolutionItem {
    value: PathHead,
}

// port: semantic_index.rs::DefinitionSite. Where a local variable was
// defined (for go-to-definition).
type DefinitionSite = DefinitionSiteStatement
    | DefinitionSiteParameter
    | DefinitionSitePatternBinding
    | DefinitionSiteCatchBinding;

// Defined in a let statement (a statement id).
class DefinitionSiteStatement {
    value: int,
}

// Defined as a function parameter (its index).
class DefinitionSiteParameter {
    value: int,
}

// Defined by a pattern binding (match arm, if-let, etc.; a pattern id).
class DefinitionSitePatternBinding {
    value: int,
}

// The error (and optional stack-trace) binding of a `catch (e) { ... }`
// clause (a pattern id). Like a function parameter: a value bound by the
// clause and scoped to its body.
class DefinitionSiteCatchBinding {
    value: int,
}

// port: semantic_index.rs::BindingKind
type BindingKind = BindingKindLocal | BindingKindParameter;

// A local binding row in `scope_bindings[scope].bindings`.
class BindingKindLocal {
    value: int,
}

// A parameter index in `scope_bindings[scope].params`.
class BindingKindParameter {
    value: int,
}

// port: semantic_index.rs::BindingId
class BindingId {
    scope: int,
    kind: BindingKind,

    // port: baml_compiler2_hir/src/semantic_index.rs::BindingId::local @ d9be6853b
    function local(scope: int, binding_index: int) -> BindingId throws never {
        BindingId { scope: scope, kind: BindingKindLocal { value: binding_index } }
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::BindingId::parameter @ d9be6853b
    function parameter(scope: int, param_idx: int) -> BindingId throws never {
        BindingId { scope: scope, kind: BindingKindParameter { value: param_idx } }
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::BindingId::local_index @ d9be6853b
    function local_index(self) -> int? throws never {
        match (self.kind) {
            let k: BindingKindLocal => k.value,
            BindingKindParameter => null,
        }
    }
}

// port: semantic_index.rs::LocalBinding
class LocalBinding {
    name: string,
    site: DefinitionSite,
    // The ROOT pattern the binding was registered under (the whole destructure
    // for `let Pack { value }`). MIR's binding lookups key on this.
    pattern: int,
    // The `Pattern::Bind` node that introduces THIS name: equal to `pattern`
    // for a bare `let x`, the inner bind for destructures. The per-name
    // identity type inference keys binding types on. For an or-pattern, the
    // first alternative's bind is representative.
    bind_pattern: int,
    name_range: root.syntax.TextRange,
    visible_from: int,
}

// port: semantic_index.rs::ScopeBindings. Per-scope local bindings: what
// names are introduced in this scope. BAML's simple scoping (no conditional
// definitions) means a flat list suffices.
class ScopeBindings {
    // Let-bindings in this scope, in source order.
    bindings: LocalBinding[],
    // Parameters (for Function/Lambda scopes): (name, param_index).
    params: (string, int)[],
    // Variables captured from ancestor scopes (Lambda scopes only), each with
    // the binding it captures, which stays unique under shadowing. Populated by
    // capture analysis in the builder.
    captures: (string, BindingId)[],
    // Bindings in this scope that a descendant lambda captures. MIR lowering
    // uses it to decide which locals need cell wrapping.
    captured_bindings: map<BindingId, bool>,

    // port: baml_compiler2_hir/src/semantic_index.rs::ScopeBindings::new @ d9be6853b
    // Also `Default`.
    function new() -> ScopeBindings throws never {
        ScopeBindings { bindings: [], params: [], captures: [], captured_bindings: {} }
    }
}

// port: baml_compiler2_hir/src/semantic_index.rs::visible_binding_at_in_scopes @ d9be6853b
// Shared local-binding lookup used while building and after indexing: the
// single source for parent-scope visibility. Skip ancestor class scopes, scan
// local bindings in reverse source order, check `visible_from`, then fall back
// to parameters.
function visible_binding_at_in_scopes(
    scopes: Scope[],
    scope_bindings: ScopeBindings[],
    scope_id: int,
    at_offset: int,
    name: string,
) -> BindingId? throws never {
    let current: int? = scope_id;
    while let ancestor_id: int = current {
        let scope = scopes[ancestor_id];
        if (scope.kind == ScopeKind.Class && ancestor_id != scope_id) {
            current = scope.parent;
            continue;
        }

        let bindings = scope_bindings[ancestor_id];
        let binding_idx = bindings.bindings.length() - 1;
        while (binding_idx >= 0) {
            let binding = bindings.bindings[binding_idx];
            if (binding.name == name && binding.visible_from <= at_offset) {
                return BindingId.local(ancestor_id, binding_idx);
            }
            binding_idx -= 1;
        }
        for (let param in bindings.params) {
            let (let param_name, let param_idx) = param;
            if (param_name == name) {
                return BindingId.parameter(ancestor_id, param_idx);
            }
        }
        current = scope.parent;
    }
    null
}

// port: semantic_index.rs::SemanticIndexExtra. Rare data for
// `FileSemanticIndex`, present only when at least one field is non-empty.
class SemanticIndexExtra {
    diagnostics: Hir2Diagnostic[],
    lowering_diagnostics: root.ast.LoweringDiagnostic[],
    // (scope, pattern) -> names; Rust keys by the tuple.
    invalid_pattern_bindings: map<int, map<int, map<string, bool>>>,
    // (pattern span, pattern) -> scope; Rust keys by the tuple.
    invalid_pattern_binding_scopes: map<root.syntax.TextRange, map<int, int>>,
}

// port: semantic_index.rs::FileSemanticIndex. Per-file semantic index.
class FileSemanticIndex {
    // Scope tree: `Scope` nodes indexed by scope id.
    scopes: Scope[],
    // Expression to owning lexical scope: every expression of the file's
    // `ExprBody` arenas, mapped to its innermost containing scope. Sorted by
    // key for binary search.
    expr_scopes: (ExprMetadataKey, int)[],
    // Per-scope local bindings, parallel to `scopes`.
    scope_bindings: ScopeBindings[],
    // The interned `ScopeId` (`db.scopes`) of each scope.
    scope_ids: int[],
    // Item -> the scope it opened. The inverse of `Scope.owner`.
    item_scopes: map<ItemScopeOwner, int>,
    // Per-file item tree: `LocalItemId` -> item data.
    item_tree: ItemTree,
    // Source map for the item tree: field/variant name spans.
    item_tree_source_map: ItemTreeSourceMap,
    // Names this file contributes to its package namespace.
    symbol_contributions: FileSymbolContributions,
    // Diagnostics and other rare data; null when empty.
    extra: SemanticIndexExtra?,
    // Root resolution for every value `Path` expression, sorted by key.
    path_resolutions: (ExprMetadataKey, PathResolution)[],
    // Lambda expression -> the `Lambda` scope it opened, sorted by key: the
    // span-free join (type inference must not depend on spans).
    lambda_scopes: (ExprMetadataKey, int)[],
    // Environment variable references (`env.X`) in this file's bodies.
    env_var_refs: root.ast.EnvVarRef[],

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::lambda_scope_for @ d9be6853b
    // The `Lambda` scope whose range is exactly `span`.
    function lambda_scope_for(self, span: root.syntax.TextRange) -> int? throws never {
        let i = 0;
        for (let scope in self.scopes) {
            if (scope.kind == ScopeKind.Lambda && scope.range == span) {
                return i;
            }
            i += 1;
        }
        null
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::lambda_scope_for_within @ d9be6853b
    // A `Lambda` scope with `span` inside `owner_scope`. Restricting the search
    // to the owner's DFS subtree disambiguates synthesized companion functions
    // that share source ranges.
    function lambda_scope_for_within(
        self,
        owner_scope: int,
        span: root.syntax.TextRange,
    ) -> int? throws never {
        let owner = self.scopes.at(owner_scope)
            ?? return null;
        let i = owner.descendants.start;
        while (i < owner.descendants.end) {
            let scope = self.scopes[i];
            if (scope.kind == ScopeKind.Lambda && scope.range == span) {
                return i;
            }
            i += 1;
        }
        null
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::scope_at_offset @ d9be6853b
    // The innermost scope containing `offset`. Scopes are in DFS pre-order, so
    // walking in reverse finds the deepest. With a `name`, find the named scope
    // first, then the deepest descendant of it at the offset: this
    // disambiguates companion functions that share their parent's span while
    // still resolving bindings in inner scopes.
    function scope_at_offset(self, offset: int, name: string?) -> int throws never {
        if (name != null) {
            let named_idx = last_scope_at(self.scopes, offset, 0, self.scopes.length(), name = name);
            if (named_idx != null) {
                let named = self.scopes[named_idx];
                // No descendant matched: the named scope itself.
                return last_scope_at(self.scopes, offset, named.descendants.start, named.descendants.end)
                    ?? named_idx;
            }
        }
        // No name filter: the deepest scope at offset.
        last_scope_at(self.scopes, offset, 0, self.scopes.length()) ?? FILE_SCOPE_ID_ROOT
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::expression_scope @ d9be6853b
    // Which lexical scope owns an expression.
    function expression_scope(self, key: ExprMetadataKey) -> int? throws never {
        binary_search_by_key(self.expr_scopes, key)
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::lambda_scope @ d9be6853b
    // The `Lambda` scope a lambda expression opened (span-free).
    function lambda_scope(self, key: ExprMetadataKey) -> int? throws never {
        binary_search_by_key(self.lambda_scopes, key)
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::path_resolution @ d9be6853b
    function path_resolution(self, key: ExprMetadataKey) -> PathResolution? throws never {
        binary_search_by_key(self.path_resolutions, key)
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::ancestor_scopes @ d9be6853b
    // `scope_id` and its ancestors, up to the root.
    function ancestor_scopes(self, scope_id: int) -> int[] throws never {
        let ancestors = [scope_id];
        let current = scope_id;
        while let parent: int = self.scopes[current].parent {
            ancestors.push(parent);
            current = parent;
        }
        ancestors
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::binding_visible_at @ d9be6853b
    function binding_visible_at(self, binding: LocalBinding, at_offset: int) -> bool throws never {
        binding.visible_from <= at_offset
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::visible_binding_at @ d9be6853b
    function visible_binding_at(
        self,
        scope_id: int,
        at_offset: int,
        name: string,
    ) -> BindingId? throws never {
        visible_binding_at_in_scopes(self.scopes, self.scope_bindings, scope_id, at_offset, name)
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::local_binding @ d9be6853b
    function local_binding(self, binding_id: BindingId) -> LocalBinding? throws never {
        let idx = binding_id.local_index()
            ?? return null;
        self.scope_bindings.at(binding_id.scope)?.bindings.at(idx)
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::item_scope @ d9be6853b
    // The scope opened for `owner`, if it opened one.
    function item_scope(self, owner: ItemScopeOwner) -> int? throws never {
        self.item_scopes.get(owner)
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::scope_owner @ d9be6853b
    // The item `scope` was opened for, if it belongs to one.
    function scope_owner(self, scope: int) -> ItemScopeOwner? throws never {
        self.scopes.at(scope)?.owner
    }

    // port: baml_compiler2_hir/src/semantic_index.rs::FileSemanticIndex::diagnostics @ d9be6853b
    function diagnostics(self) -> Hir2Diagnostic[] throws never {
        self.extra?.diagnostics ?? []
    }
}

// The reverse scans of `scope_at_offset`: the last scope among ids
// `start <= i < end` whose range contains `offset` or ends at it, and, when
// `name` is given, that has that name.
function last_scope_at(
    scopes: Scope[],
    offset: int,
    start: int,
    end: int,
    name: string? = null,
) -> int? throws never {
    let i = end - 1;
    while (i >= start) {
        let scope = scopes[i];
        let at = range_contains(scope.range, offset) || scope.range.end == offset;
        if (at && (name == null || scope.name == name)) {
            return i;
        }
        i -= 1;
    }
    null
}

// needs foundation: `text_size::TextRange::contains` (start <= offset < end).
function range_contains(range: root.syntax.TextRange, offset: int) -> bool throws never {
    range.start <= offset && offset < range.end
}

// needs foundation: `slice::binary_search_by_key` over (key, value) pairs
// sorted by key, returning the value of a matching pair.
function binary_search_by_key<V>(
    pairs: (ExprMetadataKey, V)[],
    key: ExprMetadataKey,
) -> V? throws never {
    let low = 0;
    let high = pairs.length();
    while (low < high) {
        let mid = (low + high) / 2;
        let pair = pairs[mid];
        match (pair.0.cmp(key)) {
            baml.ops.Ordering.Less => {
                low = mid + 1;
            },
            baml.ops.Ordering.Greater => {
                high = mid;
            },
            baml.ops.Ordering.Equal => {
                return pair.1;
            },
        }
    }
    null
}
