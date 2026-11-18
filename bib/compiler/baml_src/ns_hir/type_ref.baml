// port: baml_compiler2_hir/src/type_ref.rs @ d9be6853b
//
// Span-free type references, the HIR's own type-expression representation.
// `root.ast.TypeExpr` carries a span on every node; the HIR stores `TypeRef`
// instead: the same tree, flattened into a per-owner arena, with no spans.
// Spans live in the parallel `TypeRefSourceMap`, indexed by the same id.
//
// The arena is scoped to one item, so adding an item never renumbers another
// item's ids.
//
// `TypeRefId` (`Idx<TypeRef>`) is an `int` index into `TypeRefStore.types`.
// deviation: `impl Index<TypeRefId> for TypeRefStore` is not ported: write
// `store.get(id)`.

// port: baml_compiler2_hir/src/type_ref.rs::TypeRef @ d9be6853b
// A type reference before name resolution: structurally identical to
// `root.ast.TypeExprKind`, with children addressed by `TypeRefId` and every
// span removed.
class TypeRef {
    kind: TypeRefKind,
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefKind @ d9be6853b
type TypeRefKind = TypeRefKindPath
    | TypeRefKindAssociatedTypeProjection
    | TypeRefKindInt
    | TypeRefKindBigint
    | TypeRefKindFloat
    | TypeRefKindString
    | TypeRefKindBool
    | TypeRefKindNull
    | TypeRefKindNever
    | TypeRefKindUint8Array
    | TypeRefKindMedia
    | TypeRefKindOptional
    | TypeRefKindList
    | TypeRefKindMap
    | TypeRefKindUnion
    | TypeRefKindTuple
    | TypeRefKindLiteral
    | TypeRefKindFunction
    | TypeRefKindUnknown
    | TypeRefKindType
    | TypeRefKindRust
    | TypeRefKindError
    | TypeRefKindMissing
    | TypeRefKindInfer;

// Named type path: `User`, `baml.http.Request`, `Stream<T>`. The path carries
// who wrote it, which decides how its first segment is read.
class TypeRefKindPath {
    path: root.base.Path,
    // Generic type arguments (`<T>` in `Stream<T>`). Empty for non-generic paths.
    generic_args: int[],
    // Named associated type bindings, e.g. `Iterator<Item = int>`.
    associated_type_bindings: AssociatedTypeBindingRef[],
}

// Associated type projection: `Base.Item` or `(Base as Interface).Item`.
class TypeRefKindAssociatedTypeProjection {
    base: int,
    interface_: int?,
    member: string,
}

class TypeRefKindInt {
}

class TypeRefKindBigint {
}

class TypeRefKindFloat {
}

class TypeRefKindString {
}

class TypeRefKindBool {
}

class TypeRefKindNull {
}

class TypeRefKindNever {
}

// `Uint8Array` (binary data).
class TypeRefKindUint8Array {
}

class TypeRefKindMedia {
    kind: root.base.MediaKind,
}

// `T?`
class TypeRefKindOptional {
    inner: int,
}

// `T[]`
class TypeRefKindList {
    inner: int,
}

// `map<K, V>`
class TypeRefKindMap {
    key: int,
    value: int,
}

// `A | B | C`
class TypeRefKindUnion {
    variants: int[],
}

class TypeRefKindTuple {
    elements: int[],
}

// Literal types in unions: `"user"`, `200`, `3.14`, `true`.
class TypeRefKindLiteral {
    value: root.base.Literal,
}

// Function type: `(params) -> return throws E`.
class TypeRefKindFunction {
    params: FunctionTypeParamRef[],
    ret: int,
    throws_: int?,
}

// The `unknown` keyword type.
class TypeRefKindUnknown {
}

// The `type` meta-type keyword.
class TypeRefKindType {
}

// `$rust_type`: opaque Rust-managed state field type.
class TypeRefKindRust {
}

// Error-recovery sentinel.
class TypeRefKindError {
}

// No type was written at this slot (an omitted annotation), as distinct from
// the written `unknown` keyword.
class TypeRefKindMissing {
}

// The wildcard `_`: an inference hole.
class TypeRefKindInfer {
}

// port: baml_compiler2_hir/src/type_ref.rs::FunctionTypeParamRef @ d9be6853b
// A parameter of a function type.
class FunctionTypeParamRef {
    name: string?,
    optional: bool,
    ty: int,
}

// port: baml_compiler2_hir/src/type_ref.rs::AssociatedTypeBindingRef @ d9be6853b
// A named associated-type binding inside a type application.
class AssociatedTypeBindingRef {
    name: string,
    ty: int,
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefStore @ d9be6853b
// The span-free type-reference arena owned by a single item.
class TypeRefStore {
    types: TypeRef[],

    // port: baml_compiler2_hir/src/type_ref.rs::impl Default for TypeRefStore @ d9be6853b
    function default_() -> TypeRefStore throws never {
        TypeRefStore { types: [] }
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefStore::get @ d9be6853b
    function get(self, id: int) -> TypeRef throws never {
        self.types[id]
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefStore::iter @ d9be6853b
    // Every node with its id, in allocation order.
    function iter(self) -> (int, TypeRef)[] throws never {
        let out: (int, TypeRef)[] = [];
        for (let id = 0; id < self.types.length(); id += 1) {
            out.push((id, self.types[id]));
        }
        out
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefStore::len @ d9be6853b
    function len(self) -> int throws never {
        self.types.length()
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefStore::display @ d9be6853b
    // A `ToString` view of `id`, rendering BAML source-like text,
    // byte-identical to `root.ast.TypeExpr`'s. The mangled
    // `Interface$for$Target` / `Target.method` names are built from it.
    function display(self, id: int) -> TypeRefDisplay throws never {
        TypeRefDisplay { store: self, id: id }
    }
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefDisplay @ d9be6853b
// A `ToString` view of one `TypeRef` node, resolving child ids through its
// owning `TypeRefStore`. Mirrors `root.ast.type_expr_kind_display` arm for arm.
class TypeRefDisplay {
    store: TypeRefStore,
    id: int,

    // port: baml_compiler2_hir/src/type_ref.rs::impl Display for TypeRefDisplay @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            let store = self.store;
            match (store.get(self.id).kind) {
                let k: TypeRefKindPath => path_type_ref_display(store, k),
                let k: TypeRefKindAssociatedTypeProjection => {
                    if let iface: int = k.interface_ {
                        `(${store.display(k.base)} as ${store.display(iface)}).${k.member}`
                    } else {
                        `${write_postfix_base(store, k.base)}.${k.member}`
                    }
                },
                TypeRefKindInt => "int",
                TypeRefKindBigint => "bigint",
                TypeRefKindFloat => "float",
                TypeRefKindString => "string",
                TypeRefKindBool => "bool",
                TypeRefKindNull => "null",
                TypeRefKindNever => "never",
                TypeRefKindUint8Array => "uint8array",
                let k: TypeRefKindMedia => root.ast.media_kind_debug_lowercase(k.kind),
                let k: TypeRefKindOptional => `${write_postfix_base(store, k.inner)}?`,
                let k: TypeRefKindList => `${write_postfix_base(store, k.inner)}[]`,
                let k: TypeRefKindMap => `map<${store.display(k.key)}, ${store.display(k.value)}>`,
                let k: TypeRefKindUnion => {
                    k.variants
                        .map((v) -> {
                            match (store.get(v).kind) {
                                TypeRefKindFunction => `(${store.display(v)})`,
                                _ => store.display(v).to_string(),
                            }
                        })
                        .join(" | ")
                },
                let k: TypeRefKindTuple => {
                    let trailing = if (k.elements.length() == 1) {
                        ","
                    } else {
                        ""
                    };
                    let elements = k.elements.map((e) -> {
                        store.display(e).to_string()
                    });
                    `(${elements.join(", ")}${trailing})`
                },
                let k: TypeRefKindLiteral => root.base.literal_display(k.value),
                let k: TypeRefKindFunction => function_type_ref_display(store, k),
                TypeRefKindUnknown => "unknown",
                TypeRefKindType => "reflect.Type",
                TypeRefKindRust => "$rust_type",
                TypeRefKindError => "error",
                TypeRefKindMissing => "?",
                TypeRefKindInfer => "_",
            }
        }
    }
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefDisplay::fmt::needs_parens @ d9be6853b
function needs_parens(store: TypeRefStore, id: int) -> bool throws never {
    match (store.get(id).kind) {
        TypeRefKindUnion | TypeRefKindFunction => true,
        _ => false,
    }
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefDisplay::fmt::write_postfix_base @ d9be6853b
// The base of a postfix form (`?`, `[]`, `.Member`), parenthesized when it
// would bind looser than the postfix.
function write_postfix_base(store: TypeRefStore, id: int) -> string throws never {
    if (needs_parens(store, id)) {
        `(${store.display(id)})`
    } else {
        store.display(id).to_string()
    }
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefDisplay::fmt @ d9be6853b
// (the `TypeRefKind::Path` arm).
function path_type_ref_display(store: TypeRefStore, k: TypeRefKindPath) -> string throws never {
    let dotted = k.path.segments.join(".");
    if (k.generic_args.length() == 0 && k.associated_type_bindings.length() == 0) {
        return dotted;
    }
    let args = k.generic_args.map((arg) -> {
        store.display(arg).to_string()
    });
    let bindings = k.associated_type_bindings.map((binding) -> {
        `${binding.name} = ${store.display(binding.ty)}`
    });
    `${dotted}<${args.concat(bindings).join(", ")}>`
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefDisplay::fmt @ d9be6853b
// (the `TypeRefKind::Function` arm).
function function_type_ref_display(
    store: TypeRefStore,
    k: TypeRefKindFunction,
) -> string throws never {
    let params = k.params.map((p) -> {
        if let name: string = p.name {
            let optional = if (p.optional) {
                "?"
            } else {
                ""
            };
            `${name}${optional}: ${store.display(p.ty)}`
        } else {
            store.display(p.ty).to_string()
        }
    });
    let ret = match (store.get(k.ret).kind) {
        TypeRefKindFunction => `(${store.display(k.ret)})`,
        _ => store.display(k.ret).to_string(),
    };
    let throws_suffix = if let throws_: int = k.throws_ {
        ` throws ${store.display(throws_)}`
    } else {
        ""
    };
    `(${params.join(", ")}) -> ${ret}${throws_suffix}`
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefSourceMap @ d9be6853b
// Spans for one item's `TypeRefStore`, allocated in lockstep with it, so the
// two arenas share indices. Unlike the store, this compares spans.
class TypeRefSourceMap {
    spans: root.syntax.TextRange[],

    // port: baml_compiler2_hir/src/type_ref.rs::impl Default for TypeRefSourceMap @ d9be6853b
    function default_() -> TypeRefSourceMap throws never {
        TypeRefSourceMap { spans: [] }
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefSourceMap::span @ d9be6853b
    // The source span of `id`. Synthesized nodes have an empty range; callers
    // that need a user-visible anchor fall back to the owning item's span.
    function span(self, id: int) -> root.syntax.TextRange throws never {
        self.spans[id]
    }
}

// port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder @ d9be6853b
// Lowers `root.ast.TypeExpr` trees into one item's `TypeRefStore`, recording
// each node's span in the parallel `TypeRefSourceMap`. One builder per item:
// ids are only meaningful relative to the store they were allocated in.
class TypeRefBuilder {
    store: TypeRefStore,
    source_map: TypeRefSourceMap,

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder::new @ d9be6853b
    function new() -> TypeRefBuilder throws never {
        TypeRefBuilder { store: TypeRefStore.default_(), source_map: TypeRefSourceMap.default_() }
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder::alloc @ d9be6853b
    // Allocate a node and its span together; the lockstep makes
    // `TypeRefSourceMap.span` a plain index.
    function alloc(self, ty: TypeRef, span: root.syntax.TextRange) -> int throws never {
        let id = self.store.types.length();
        self.store.types.push(ty);
        self.source_map.spans.push(span);
        id
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder::lower @ d9be6853b
    // Lower a type expression and all of its children. Children are allocated
    // before their parent (post-order), so ids are a pure function of tree
    // shape.
    function lower(self, te: root.ast.TypeExpr) -> int throws never {
        let kind: TypeRefKind = match (te.kind) {
            let k: root.ast.TypeExprKindPath => {
                TypeRefKindPath {
                    path: k.path,
                    generic_args: k.generic_args.map((arg) -> {
                        self.lower(arg)
                    }),
                    associated_type_bindings: k.associated_type_bindings.map((binding) -> {
                        AssociatedTypeBindingRef { name: binding.name, ty: self.lower(binding.ty) }
                    }),
                }
            },
            let k: root.ast.TypeExprKindAssociatedTypeProjection => {
                TypeRefKindAssociatedTypeProjection {
                    base: self.lower(k.base),
                    interface_: if let iface: root.ast.TypeExpr = k.interface_ {
                        self.lower(iface)
                    } else {
                        null
                    },
                    member: k.member,
                }
            },
            root.ast.TypeExprKindInt => TypeRefKindInt {},
            root.ast.TypeExprKindBigint => TypeRefKindBigint {},
            root.ast.TypeExprKindFloat => TypeRefKindFloat {},
            root.ast.TypeExprKindString => TypeRefKindString {},
            root.ast.TypeExprKindBool => TypeRefKindBool {},
            root.ast.TypeExprKindNull => TypeRefKindNull {},
            root.ast.TypeExprKindNever => TypeRefKindNever {},
            root.ast.TypeExprKindUint8Array => TypeRefKindUint8Array {},
            let k: root.ast.TypeExprKindMedia => TypeRefKindMedia { kind: k.kind },
            let k: root.ast.TypeExprKindOptional => {
                TypeRefKindOptional { inner: self.lower(k.inner) }
            },
            let k: root.ast.TypeExprKindList => TypeRefKindList { inner: self.lower(k.inner) },
            let k: root.ast.TypeExprKindMap => {
                TypeRefKindMap { key: self.lower(k.key), value: self.lower(k.value) }
            },
            let k: root.ast.TypeExprKindUnion => {
                TypeRefKindUnion {
                    variants: k.variants.map((v) -> {
                        self.lower(v)
                    }),
                }
            },
            let k: root.ast.TypeExprKindTuple => {
                TypeRefKindTuple {
                    elements: k.elements.map((e) -> {
                        self.lower(e)
                    }),
                }
            },
            let k: root.ast.TypeExprKindLiteral => TypeRefKindLiteral { value: k.value },
            let k: root.ast.TypeExprKindFunction => self.lower_function(k),
            root.ast.TypeExprKindUnknown => TypeRefKindUnknown {},
            root.ast.TypeExprKindType => TypeRefKindType {},
            root.ast.TypeExprKindRust => TypeRefKindRust {},
            root.ast.TypeExprKindError => TypeRefKindError {},
            root.ast.TypeExprKindMissing => TypeRefKindMissing {},
            root.ast.TypeExprKindInfer => TypeRefKindInfer {},
        };
        self.alloc(TypeRef { kind: kind }, te.span)
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder::lower @ d9be6853b
    // (the `TypeExprKind::Function` arm): params, then the return type, then
    // the throws type.
    function lower_function(
        self,
        k: root.ast.TypeExprKindFunction,
    ) -> TypeRefKindFunction throws never {
        TypeRefKindFunction {
            params: k.params.map((p) -> {
                FunctionTypeParamRef { name: p.name, optional: p.optional, ty: self.lower(p.ty) }
            }),
            ret: self.lower(k.ret),
            throws_: if let throws_: root.ast.TypeExpr = k.throws_ {
                self.lower(throws_)
            } else {
                null
            },
        }
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder::alloc_synthetic @ d9be6853b
    // Allocate a node that has no source text (a compiler-synthesized type).
    // Its span is empty; diagnostics anchor to the owning item instead.
    function alloc_synthetic(self, kind: TypeRefKind) -> int throws never {
        self.alloc(TypeRef { kind: kind }, root.syntax.TextRange.empty(0))
    }

    // port: baml_compiler2_hir/src/type_ref.rs::TypeRefBuilder::finish @ d9be6853b
    function finish(self) -> (TypeRefStore, TypeRefSourceMap) throws never {
        (self.store, self.source_map)
    }
}
