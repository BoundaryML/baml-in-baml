// port: baml_compiler2_ast/src/ast.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

// Raw attribute from CST — not yet validated.
class RawAttribute {
    name: string,
    args: RawAttributeArg[],
    span: root.syntax.TextRange,
}

class RawAttributeArg {
    key: string?,
    value: string,
    span: root.syntax.TextRange,
}

// Full recursive type expression — all structural content in memory.
// 
// Corresponds to `TypeRef` in `baml_compiler_hir/src/type_ref.rs` but lives
// in the AST layer (before any name resolution). CST → `TypeExpr` conversion
// happens once during `lower_file` and is never repeated.
type TypeExprKind = TypeExprKindPath
    | TypeExprKindAssociatedTypeProjection
    | TypeExprKindInt
    | TypeExprKindBigint
    | TypeExprKindFloat
    | TypeExprKindString
    | TypeExprKindBool
    | TypeExprKindNull
    | TypeExprKindNever
    | TypeExprKindUint8Array
    | TypeExprKindMedia
    | TypeExprKindOptional
    | TypeExprKindList
    | TypeExprKindMap
    | TypeExprKindUnion
    | TypeExprKindTuple
    | TypeExprKindLiteral
    | TypeExprKindFunction
    | TypeExprKindUnknown
    | TypeExprKindType
    | TypeExprKindRust
    | TypeExprKindError
    | TypeExprKindMissing
    | TypeExprKindInfer;

// deviation: `TypeExprKind::at(span)` is not ported (a one-line
// constructor): write `TypeExpr { kind: k, span: s }`.

class TypeExprKindPath {
    path: root.base.Path,
    generic_args: TypeExpr[],
    associated_type_bindings: AssociatedTypeBinding[],
}

class TypeExprKindAssociatedTypeProjection {
    base: TypeExpr,
    interface_: TypeExpr?,
    member: string,
}

class TypeExprKindInt {
}

class TypeExprKindBigint {
}

class TypeExprKindFloat {
}

class TypeExprKindString {
}

class TypeExprKindBool {
}

class TypeExprKindNull {
}

class TypeExprKindNever {
}

class TypeExprKindUint8Array {
}

class TypeExprKindMedia {
    kind: root.base.MediaKind,
}

class TypeExprKindOptional {
    inner: TypeExpr,
}

class TypeExprKindList {
    inner: TypeExpr,
}

class TypeExprKindMap {
    key: TypeExpr,
    value: TypeExpr,
}

class TypeExprKindUnion {
    variants: TypeExpr[],
}

class TypeExprKindTuple {
    elements: TypeExpr[],
}

class TypeExprKindLiteral {
    value: root.base.Literal,
}

class TypeExprKindFunction {
    params: FunctionTypeParam[],
    ret: TypeExpr,
    throws_: TypeExpr?,
}

class TypeExprKindUnknown {
}

class TypeExprKindType {
}

class TypeExprKindRust {
}

class TypeExprKindError {
}

class TypeExprKindMissing {
}

class TypeExprKindInfer {
}

// A type expression node paired with its source span. Every node in the tree
// is spanned (recursively, via the `Box<TypeExpr>`/`Vec<TypeExpr>` children of
// [`TypeExprKind`]), so a diagnostic about any sub-type (e.g. an unresolved
// member of a union/map) can point exactly at it.
// 
// Equality and hashing are **structural** — they ignore `span`. Two occurrences
// of the same type compare equal regardless of source position; `span` is
// diagnostic metadata, not part of type identity (this matches the pre-spanning
// behavior and keeps Salsa early-cutoff / dedup position-insensitive).
class TypeExpr {
    kind: TypeExprKind,
    span: root.syntax.TextRange,

    // port: baml_compiler2_ast/src/ast.rs::TypeExpr::with_span @ d9be6853b
    // This node with its top-level span replaced (children keep theirs), for
    // an item that carries a separate span for the whole annotation.
    function with_span(self, span: root.syntax.TextRange) -> TypeExpr throws never {
        TypeExpr { ...self, span: span }
    }

    // port: baml_compiler2_ast/src/ast.rs::TypeExpr::spans @ d9be6853b
    // Every span in this type, in source order: its own and its children's.
    // Equality ignores spans, so a memoized value that carries spans has to
    // compare these too.
    function spans(self) -> root.syntax.TextRange[] throws never {
        let out: root.syntax.TextRange[] = [];
        self.collect_spans(out);
        out
    }

    // port: baml_compiler2_ast/src/ast.rs::TypeExpr::collect_spans @ d9be6853b
    function collect_spans(self, out: root.syntax.TextRange[]) -> void throws never {
        out.push(self.span);
        match (self.kind) {
            let k: TypeExprKindPath => {
                for (let arg in k.generic_args) {
                    arg.collect_spans(out);
                }
                for (let binding in k.associated_type_bindings) {
                    binding.ty.collect_spans(out);
                }
            },
            let k: TypeExprKindAssociatedTypeProjection => {
                k.base.collect_spans(out);
                k.interface_?.collect_spans(out);
            },
            let k: TypeExprKindOptional => k.inner.collect_spans(out),
            let k: TypeExprKindList => k.inner.collect_spans(out),
            let k: TypeExprKindMap => {
                k.key.collect_spans(out);
                k.value.collect_spans(out);
            },
            let k: TypeExprKindUnion => {
                for (let variant in k.variants) {
                    variant.collect_spans(out);
                }
            },
            let k: TypeExprKindTuple => {
                for (let element in k.elements) {
                    element.collect_spans(out);
                }
            },
            let k: TypeExprKindFunction => {
                for (let param in k.params) {
                    param.ty.collect_spans(out);
                }
                k.ret.collect_spans(out);
                k.throws_?.collect_spans(out);
            },
            TypeExprKindInt
                | TypeExprKindBigint
                | TypeExprKindFloat
                | TypeExprKindString
                | TypeExprKindBool
                | TypeExprKindNull
                | TypeExprKindUint8Array
                | TypeExprKindNever
                | TypeExprKindRust
                | TypeExprKindLiteral
                | TypeExprKindMedia
                | TypeExprKindUnknown
                | TypeExprKindType
                | TypeExprKindError
                | TypeExprKindMissing
                | TypeExprKindInfer =>
            {},
        }
    }

    // port: baml_compiler2_ast/src/ast.rs::impl PartialEq for TypeExpr @ d9be6853b
    // Structural: two occurrences of one type are equal wherever they are.
    implements baml.ops.Equals {
        function eq(self, other: Self) -> bool throws never {
            self.kind == other.kind
        }
    }

    // port: baml_compiler2_ast/src/ast.rs::impl Hash for TypeExpr @ d9be6853b
    implements baml.Hash {
        function hash(self, state: baml.hash.Hasher) -> void throws never {
            self.kind.hash(state)
        }
    }

    // port: baml_compiler2_ast/src/ast.rs::impl Display for TypeExpr @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            type_expr_kind_display(self.kind)
        }
    }
}

// port: baml_compiler2_ast/src/ast.rs::impl Display for TypeExprKind @ d9be6853b
function type_expr_kind_display(kind: TypeExprKind) -> string throws never {
    match (kind) {
        let k: TypeExprKindPath => path_type_display(k),
        let k: TypeExprKindAssociatedTypeProjection => {
            if let iface: TypeExpr = k.interface_ {
                `(${k.base} as ${iface}).${k.member}`
            } else {
                `${write_postfix_base(k.base)}.${k.member}`
            }
        },
        TypeExprKindInt => "int",
        TypeExprKindBigint => "bigint",
        TypeExprKindFloat => "float",
        TypeExprKindString => "string",
        TypeExprKindBool => "bool",
        TypeExprKindNull => "null",
        TypeExprKindNever => "never",
        TypeExprKindUint8Array => "uint8array",
        let k: TypeExprKindMedia => media_kind_debug_lowercase(k.kind),
        let k: TypeExprKindOptional => `${write_postfix_base(k.inner)}?`,
        let k: TypeExprKindList => `${write_postfix_base(k.inner)}[]`,
        let k: TypeExprKindMap => `map<${k.key}, ${k.value}>`,
        let k: TypeExprKindUnion => {
            k.variants
                .map((v) -> {
                    match (v.kind) {
                        TypeExprKindFunction => `(${v})`,
                        _ => v.to_string(),
                    }
                })
                .join(" | ")
        },
        let k: TypeExprKindTuple => {
            let trailing = if (k.elements.length() == 1) {
                ","
            } else {
                ""
            };
            `(${k.elements.map((e) -> { e.to_string() }).join(", ")}${trailing})`
        },
        let k: TypeExprKindLiteral => root.base.literal_display(k.value),
        let k: TypeExprKindFunction => function_type_display(k),
        TypeExprKindUnknown => "unknown",
        TypeExprKindType => "reflect.Type",
        TypeExprKindRust => "$rust_type",
        TypeExprKindError => "error",
        TypeExprKindMissing => "?",
        TypeExprKindInfer => "_",
    }
}

// port: the `TypeExprKind::Path` arm of `impl Display for TypeExprKind`.
function path_type_display(k: TypeExprKindPath) -> string throws never {
    let dotted = k.path.segments.join(".");
    if (k.generic_args.length() == 0 && k.associated_type_bindings.length() == 0) {
        return dotted;
    }
    let args = k.generic_args.map((arg) -> {
        arg.to_string()
    });
    let bindings = k.associated_type_bindings.map((binding) -> {
        `${binding.name} = ${binding.ty}`
    });
    `${dotted}<${args.concat(bindings).join(", ")}>`
}

// port: the `TypeExprKind::Function` arm of `impl Display for TypeExprKind`.
function function_type_display(k: TypeExprKindFunction) -> string throws never {
    let params = k.params.map((p) -> {
        if let name: string = p.name {
            let optional = if (p.optional) {
                "?"
            } else {
                ""
            };
            `${name}${optional}: ${p.ty}`
        } else {
            p.ty.to_string()
        }
    });
    let ret = match (k.ret.kind) {
        TypeExprKindFunction => `(${k.ret})`,
        _ => k.ret.to_string(),
    };
    let throws_suffix = if let throws_: TypeExpr = k.throws_ {
        ` throws ${throws_}`
    } else {
        ""
    };
    `(${params.join(", ")}) -> ${ret}${throws_suffix}`
}

// port: `needs_parens` inside `impl Display for TypeExprKind`.
function needs_parens(ty: TypeExpr) -> bool throws never {
    match (ty.kind) {
        TypeExprKindUnion | TypeExprKindFunction => true,
        _ => false,
    }
}

// port: `write_postfix_base` inside `impl Display for TypeExprKind`. The base
// of a postfix form (`?`, `[]`, `.Member`), parenthesized when it would bind
// looser than the postfix.
function write_postfix_base(ty: TypeExpr) -> string throws never {
    if (needs_parens(ty)) {
        `(${ty})`
    } else {
        ty.to_string()
    }
}

// Rust's `format!("{kind:?}").to_lowercase()` of a `MediaKind`.
function media_kind_debug_lowercase(kind: root.base.MediaKind) -> string throws never {
    match (kind) {
        root.base.MediaKind.Image => "image",
        root.base.MediaKind.Audio => "audio",
        root.base.MediaKind.Video => "video",
        root.base.MediaKind.Pdf => "pdf",
        root.base.MediaKind.Generic => "generic",
    }
}

// A parameter in a function type expression.
class FunctionTypeParam {
    name: string?,
    optional: bool,
    ty: TypeExpr,
}

// Named associated type binding used inside type applications:
// `Iterator<Item = int>`.
class AssociatedTypeBinding {
    name: string,
    ty: TypeExpr,
}

// A generic type parameter declaration, paired with the `&`-separated bounds
// it was declared with (`<T>` → `bounds = []`; `<T extends A & B>` → `bounds =
// [A, B]`).
// 
// The bound set is a **conjunction**: an argument for this parameter must
// satisfy every entry. Holding the name and its bounds together makes a length
// mismatch between the two unrepresentable.
// 
// Bounds are `TypeExpr`s so generic parents like `Container<int>` round-trip;
// that each must denote an *interface* — never an interface-existential type,
// see `TYPE_SYSTEM.md` "Generics on Functions" — is enforced where they are
// lowered to constraints.
class GenericParam {
    name: string,
    bounds: TypeExpr[],
    name_span: root.syntax.TextRange,
}

// Full expression body — owned arena of expressions, statements,
// and patterns. Modeled after `ExprBody` in `body.rs`.
class ExprBody {
    exprs: Expr[],
    stmts: Stmt[],
    patterns: Pattern[],
    match_arms: MatchArm[],
    catch_arms: CatchArm[],
    type_annotations: TypeExpr[],
    tag_values: int[],
    root_expr: int?,

    // port: baml_compiler2_ast/src/ast.rs::impl Default for ExprBody @ d9be6853b
    function new() -> ExprBody throws never {
        ExprBody {
            exprs: [],
            stmts: [],
            patterns: [],
            match_arms: [],
            catch_arms: [],
            type_annotations: [],
            tag_values: [],
            root_expr: null,
        }
    }

    // port: baml_compiler2_ast/src/ast.rs::ExprBody::display_expr @ d9be6853b
    // (with display_expr_inner folded in as the `depth` default). A short,
    // human-readable rendering of an expression, for diagnostic messages.
    function display_expr(self, id: int, depth: int = 0) -> string throws never {
        if (depth > 10) {
            return "...";
        }
        let inner = (child: int) -> string {
            self.display_expr(child, depth = depth + 1)
        };
        let call_args = (args: CallArg[]) -> string {
            args
                .map((a) -> {
                    let value = inner(a.expr);
                    if let label: string = a.label {
                        `${label} = ${value}`
                    } else {
                        value
                    }
                })
                .join(", ")
        };
        match (self.exprs[id]) {
            let e: ExprPath => e.value.segments.join("."),
            let e: ExprGenericApply => {
                `${inner(e.base)}<${e.type_args.map((t) -> { t.to_string() }).join(", ")}>`
            },
            let e: ExprMemberAccess => `${inner(e.base)}.${e.member}`,
            let e: ExprOptionalMemberAccess => `${inner(e.base)}?.${e.member}`,
            let e: ExprUpcast => `${inner(e.base)}.as<${e.target}>`,
            let e: ExprQualifiedPath => `(${e.qself} as ${e.interface_}).${e.member}`,
            let e: ExprIndex => `${inner(e.base)}[${inner(e.index)}]`,
            let e: ExprOptionalIndex => `${inner(e.base)}?.[${inner(e.index)}]`,
            let e: ExprCall => {
                let ty_args = if (e.type_args.length() == 0) {
                    ""
                } else {
                    `<${e.type_args.map((t) -> { t.to_string() }).join(", ")}>`
                };
                `${inner(e.callee)}${ty_args}(${call_args(e.args)})`
            },
            let e: ExprOptionalCall => `${inner(e.callee)}?.(${call_args(e.args)})`,
            let e: ExprBinary => `${inner(e.lhs)} ${binary_op_display(e.op)} ${inner(e.rhs)}`,
            let e: ExprOptionalChain => inner(e.expr),
            ExprBlock { tail_expr: let tail: int } => inner(tail),
            let e: ExprTemplate => match (e.tag) {
                TemplateTagDefault => "`…`",
                let t: TemplateTagCustom => `${inner(t.tag)}\`…\``,
            },
            let e: ExprTuple => {
                let elems = e.elements.map((el) -> {
                    inner(el)
                });
                if (elems.length() == 1) {
                    `(${elems[0]},)`
                } else {
                    `(${elems.join(", ")})`
                }
            },
            let e: ExprLiteral => root.base.literal_display(e.value),
            ExprNull => "null",
            _ => "...",
        }
    }

    // port: baml_compiler2_ast/src/traverse.rs::ExprBody::expr_children @ d9be6853b
    // Append the direct children of `id` to `out`, in source order. A lambda's
    // body is deliberately not a child: a lambda is a value, so what its body
    // does belongs to the lambda.
    function expr_children(self, id: int, out: BodyNode[]) -> void throws never {
        let push_expr = (e: int) -> void {
            out.push(BodyNodeExpr { value: e });
        };
        let push_opt = (e: int?) -> void {
            if (e != null) {
                out.push(BodyNodeExpr { value: e });
            }
        };
        match (self.exprs[id]) {
            ExprLiteral
                | ExprByteStringLiteral
                | ExprNull
                | ExprPath
                | ExprQualifiedPath
                | ExprLambda
                | ExprMissing =>
            {},
            let e: ExprGenericApply => push_expr(e.base),
            let e: ExprMemberAccess => push_expr(e.base),
            let e: ExprOptionalMemberAccess => push_expr(e.base),
            let e: ExprUpcast => push_expr(e.base),
            let e: ExprUnary => push_expr(e.expr),
            let e: ExprOptionalChain => push_expr(e.expr),
            let e: ExprThrow => push_expr(e.value),
            let e: ExprAwait => push_expr(e.future),
            let e: ExprReturn => push_opt(e.value),
            let e: ExprIf => {
                push_expr(e.condition);
                push_expr(e.then_branch);
                push_opt(e.else_branch);
            },
            let e: ExprIfLet => {
                push_expr(e.scrutinee);
                push_expr(e.then_branch);
                push_opt(e.else_branch);
            },
            let e: ExprMatch => {
                push_expr(e.scrutinee);
                for (let arm_id in e.arms) {
                    let arm = self.match_arms[arm_id];
                    push_opt(arm.guard);
                    push_expr(arm.body);
                }
            },
            let e: ExprIs => push_expr(e.scrutinee),
            let e: ExprCatch => {
                push_expr(e.base);
                for (let arm_id in e.clause.arms) {
                    push_expr(self.catch_arms[arm_id].body);
                }
            },
            let e: ExprBinary => {
                push_expr(e.lhs);
                push_expr(e.rhs);
            },
            let e: ExprIndex => {
                push_expr(e.base);
                push_expr(e.index);
            },
            let e: ExprOptionalIndex => {
                push_expr(e.base);
                push_expr(e.index);
            },
            let e: ExprCall => {
                push_expr(e.callee);
                e.args.for_each((arg) -> {
                    push_expr(arg.expr)
                });
            },
            let e: ExprOptionalCall => {
                push_expr(e.callee);
                e.args.for_each((arg) -> {
                    push_expr(arg.expr)
                });
            },
            let e: ExprObject => {
                e.fields.for_each((field) -> {
                    push_expr(field.value)
                });
                e.spreads.for_each((s) -> {
                    push_expr(s.expr)
                });
            },
            let e: ExprArray => e.elements.for_each(push_expr),
            let e: ExprTuple => e.elements.for_each(push_expr),
            let e: ExprMap => {
                for (let entry in e.entries) {
                    push_expr(entry.key);
                    push_expr(entry.value);
                }
            },
            let e: ExprBlock => {
                e.stmts.for_each((s) -> {
                    out.push(BodyNodeStmt { value: s });
                });
                push_opt(e.tail_expr);
            },
            let e: ExprTemplate => {
                // Both representations: `segments` holds the user's `${…}`
                // expressions, the tag payload the desugared realization. They share
                // ids, which is why `reachable_excluding_lambdas` de-duplicates.
                match (e.tag) {
                    let t: TemplateTagDefault => push_expr(t.elaborated),
                    let t: TemplateTagCustom => {
                        push_expr(t.tag);
                        push_expr(t.body);
                    },
                }
                for (let segment in e.segments) {
                    template_segment_children(segment, out);
                }
            },
        }
    }

    // port: baml_compiler2_ast/src/traverse.rs::ExprBody::stmt_children @ d9be6853b
    // Append the direct children of `id` to `out`, in source order. Patterns
    // hide no expressions, so only the statement's expression slots count.
    function stmt_children(self, id: int, out: BodyNode[]) -> void throws never {
        let push_expr = (e: int) -> void {
            out.push(BodyNodeExpr { value: e });
        };
        let push_opt = (e: int?) -> void {
            if (e != null) {
                out.push(BodyNodeExpr { value: e });
            }
        };
        match (self.stmts[id]) {
            StmtBreak | StmtContinue | StmtMissing | StmtHeaderComment => {},
            let s: StmtExpr => push_expr(s.value),
            let s: StmtThrow => push_expr(s.value),
            let s: StmtDefer => push_expr(s.body),
            let s: StmtTypeBinding => {
                push_expr(s.operand);
                push_opt(s.else_branch);
            },
            let s: StmtReturn => push_opt(s.value),
            let s: StmtLet => {
                push_opt(s.initializer);
                push_opt(s.else_branch);
            },
            let s: StmtWhile => {
                push_expr(s.condition);
                push_expr(s.body);
                if let after: int = s.after {
                    out.push(BodyNodeStmt { value: after });
                }
            },
            let s: StmtWhileLet => {
                push_expr(s.scrutinee);
                push_expr(s.body);
            },
            let s: StmtFor => {
                push_expr(s.collection);
                push_expr(s.body);
            },
            let s: StmtAssign => {
                push_expr(s.target);
                push_expr(s.value);
            },
            let s: StmtAssignOp => {
                push_expr(s.target);
                push_expr(s.value);
            },
        }
    }

    // port: baml_compiler2_ast/src/traverse.rs::ExprBody::reachable_excluding_lambdas @ d9be6853b
    // Every node reachable from `start`, in pre-order, without entering nested
    // lambda bodies: what an effect analysis wants, since a lambda's effects
    // belong to the lambda. The arena is a DAG (a template's segments and its
    // desugared payload share ids), so shared nodes are visited once.
    function reachable_excluding_lambdas(self, start: int) -> BodyNode[] throws never {
        // deviation: Rust keeps one HashSet<BodyNode>; here one set per kind.
        let seen_exprs: map<int, bool> = {};
        let seen_stmts: map<int, bool> = {};
        let stack: BodyNode[] = [BodyNodeExpr { value: start }];
        let visited: BodyNode[] = [];
        while let node: BodyNode = stack.pop() {
            let (let seen, let id) = match (node) {
                let n: BodyNodeExpr => (seen_exprs, n.value),
                let n: BodyNodeStmt => (seen_stmts, n.value),
            };
            if (seen.has(id)) {
                continue;
            }
            seen.set(id, true);
            visited.push(node);
            let children: BodyNode[] = [];
            // `expr_children` yields nothing for a lambda, so a lambda node is
            // visited but its body is not descended into.
            match (node) {
                let n: BodyNodeExpr => self.expr_children(n.value, children),
                let n: BodyNodeStmt => self.stmt_children(n.value, children),
            }
            for (let child in children.reverse()) {
                stack.push(child);
            }
        }
        visited
    }
}

// Parallel span storage for an `ExprBody` — maps arena IDs to source ranges.
// Separated so semantic queries (type checking) can ignore spans and get
// Salsa early-cutoff on whitespace changes.
class AstSourceMap {
    expr_spans: root.syntax.TextRange[],
    stmt_spans: root.syntax.TextRange[],
    pattern_spans: root.syntax.TextRange[],
    bind_name_spans: map<int, root.syntax.TextRange>,
    type_binding_name_spans: map<int, root.syntax.TextRange>,
    match_arm_spans: root.syntax.TextRange[],
    type_annotation_spans: root.syntax.TextRange[],
    catch_arm_spans: root.syntax.TextRange[],
    member_access_member_spans: map<int, root.syntax.TextRange>,
    path_segment_spans: map<int, root.syntax.TextRange[]>,
    // deviation: Rust keys by (call expr, arg expr id); BAML tuples are not hashable yet.
    call_arg_label_spans: map<int, map<int, root.syntax.TextRange>>,
    // deviation: Rust keys by (expr, field index); BAML tuples are not hashable yet.
    object_field_name_spans: map<int, map<int, root.syntax.TextRange>>,
    lambda_parameter_spans: map<int, root.syntax.TextRange[]>,
    synthetic_exprs: map<int, bool>,
    synthetic_stmts: map<int, bool>,
    synthetic_patterns: map<int, bool>,

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::new @ d9be6853b
    function new() -> AstSourceMap throws never {
        AstSourceMap {
            expr_spans: [],
            stmt_spans: [],
            pattern_spans: [],
            bind_name_spans: {},
            type_binding_name_spans: {},
            match_arm_spans: [],
            type_annotation_spans: [],
            catch_arm_spans: [],
            member_access_member_spans: {},
            path_segment_spans: {},
            call_arg_label_spans: {},
            object_field_name_spans: {},
            lambda_parameter_spans: {},
            synthetic_exprs: {},
            synthetic_stmts: {},
            synthetic_patterns: {},
        }
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::is_synthetic_expr @ d9be6853b
    function is_synthetic_expr(self, id: int) -> bool throws never {
        self.synthetic_exprs.has(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::is_synthetic_stmt @ d9be6853b
    function is_synthetic_stmt(self, id: int) -> bool throws never {
        self.synthetic_stmts.has(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::span_at @ d9be6853b
    // A span from an arena index-parallel to the one `id` indexes. An id from
    // a different arena (out of range) yields an empty range, not a panic.
    function span_at(
        spans: root.syntax.TextRange[],
        id: int,
    ) -> root.syntax.TextRange throws never {
        spans.at(id) ?? root.syntax.TextRange.empty(0)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::stmt_span @ d9be6853b
    function stmt_span(self, id: int) -> root.syntax.TextRange throws never {
        AstSourceMap.span_at(self.stmt_spans, id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::expr_span @ d9be6853b
    function expr_span(self, id: int) -> root.syntax.TextRange throws never {
        AstSourceMap.span_at(self.expr_spans, id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::member_name_span @ d9be6853b
    // The member-name span recorded for `id`, or null when it names no member.
    // Prefer this wherever the answer must be a NAME (rename, highlight).
    function member_name_span(self, id: int) -> root.syntax.TextRange? throws never {
        self.member_access_member_spans.get(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::member_access_member_span @ d9be6853b
    // The member-name span of a `MemberAccess` / `QualifiedPath`, else the
    // whole expression's span.
    function member_access_member_span(self, id: int) -> root.syntax.TextRange throws never {
        self.member_name_span(id) ?? self.expr_span(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::path_segment_span @ d9be6853b
    // The span of segment `segment_idx` of a multi-segment `Path`, else the
    // whole expression's span.
    function path_segment_span(
        self,
        id: int,
        segment_idx: int,
    ) -> root.syntax.TextRange throws never {
        self.path_segment_spans.get(id)?.at(segment_idx) ?? self.expr_span(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::object_field_name_span @ d9be6853b
    // The field-name span of an object-constructor field, else the value's span.
    function object_field_name_span(
        self,
        object_id: int,
        value_id: int,
    ) -> root.syntax.TextRange throws never {
        self.object_field_name_spans.get(object_id)?.get(value_id) ?? self.expr_span(value_id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::lambda_parameter_span @ d9be6853b
    // A lambda parameter-name span by declaration index, else the lambda's span.
    function lambda_parameter_span(
        self,
        id: int,
        parameter_index: int,
    ) -> root.syntax.TextRange throws never {
        self.lambda_parameter_spans.get(id)?.at(parameter_index) ?? self.expr_span(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::bind_name_span @ d9be6853b
    // The name token of a `Pattern::Bind`, when it was written in source.
    function bind_name_span(self, id: int) -> root.syntax.TextRange? throws never {
        self.bind_name_spans.get(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::type_binding_name_span @ d9be6853b
    // The name token of a body `let type T = …` binding, when it was written.
    function type_binding_name_span(self, id: int) -> root.syntax.TextRange? throws never {
        self.type_binding_name_spans.get(id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::pattern_span @ d9be6853b
    function pattern_span(self, id: int) -> root.syntax.TextRange throws never {
        AstSourceMap.span_at(self.pattern_spans, id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::match_arm_span @ d9be6853b
    function match_arm_span(self, id: int) -> root.syntax.TextRange throws never {
        AstSourceMap.span_at(self.match_arm_spans, id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::type_annotation_span @ d9be6853b
    function type_annotation_span(self, id: int) -> root.syntax.TextRange throws never {
        AstSourceMap.span_at(self.type_annotation_spans, id)
    }

    // port: baml_compiler2_ast/src/ast.rs::AstSourceMap::catch_arm_span @ d9be6853b
    function catch_arm_span(self, id: int) -> root.syntax.TextRange throws never {
        AstSourceMap.span_at(self.catch_arm_spans, id)
    }
}

// How a class property value was written in source.
enum PropertySyntax {
    Explicit,
    Shorthand,
}

class ObjectExprField {
    name: string,
    value: int,
    syntax: PropertySyntax,

    // port: baml_compiler2_ast/src/ast.rs::ObjectExprField::explicit @ d9be6853b
    function explicit(name: string, value: int) -> ObjectExprField throws never {
        ObjectExprField { name: name, value: value, syntax: PropertySyntax.Explicit }
    }

    // port: baml_compiler2_ast/src/ast.rs::ObjectExprField::shorthand @ d9be6853b
    function shorthand(name: string, value: int) -> ObjectExprField throws never {
        ObjectExprField { name: name, value: value, syntax: PropertySyntax.Shorthand }
    }
}

class MapExprEntry {
    key: int,
    value: int,

    // port: baml_compiler2_ast/src/ast.rs::MapExprEntry::explicit @ d9be6853b
    function explicit(key: int, value: int) -> MapExprEntry throws never {
        MapExprEntry { key: key, value: value }
    }
}

// Expressions — modeled after `Expr` in `body.rs`.
type Expr = ExprLiteral
    | ExprByteStringLiteral
    | ExprNull
    | ExprPath
    | ExprGenericApply
    | ExprIf
    | ExprIfLet
    | ExprMatch
    | ExprIs
    | ExprCatch
    | ExprThrow
    | ExprReturn
    | ExprAwait
    | ExprBinary
    | ExprUnary
    | ExprCall
    | ExprObject
    | ExprArray
    | ExprTuple
    | ExprMap
    | ExprBlock
    | ExprMemberAccess
    | ExprUpcast
    | ExprQualifiedPath
    | ExprOptionalMemberAccess
    | ExprIndex
    | ExprLambda
    | ExprOptionalIndex
    | ExprOptionalCall
    | ExprOptionalChain
    | ExprTemplate
    | ExprMissing;

class ExprLiteral {
    value: root.base.Literal,
}

class ExprByteStringLiteral {
    value: int[],
}

class ExprNull {
}

class ExprPath {
    value: root.base.Path,
}

class ExprGenericApply {
    base: int,
    type_args: TypeExpr[],
}

class ExprIf {
    condition: int,
    then_branch: int,
    else_branch: int?,
}

class ExprIfLet {
    pattern: int,
    scrutinee: int,
    then_branch: int,
    else_branch: int?,
}

class ExprMatch {
    scrutinee: int,
    scrutinee_type: int?,
    arms: int[],
}

class ExprIs {
    scrutinee: int,
    pattern: int,
}

class ExprCatch {
    base: int,
    clause: CatchClause,
}

class ExprThrow {
    value: int,
}

class ExprReturn {
    value: int?,
}

class ExprAwait {
    future: int,
}

class ExprBinary {
    op: BinaryOp,
    lhs: int,
    rhs: int,
}

class ExprUnary {
    op: UnaryOp,
    expr: int,
}

class ExprCall {
    callee: int,
    type_args: TypeExpr[],
    args: CallArg[],
}

class ExprObject {
    type_name: root.base.Path,
    type_args: TypeExpr[],
    fields: ObjectExprField[],
    spreads: SpreadField[],
}

class ExprArray {
    elements: int[],
}

class ExprTuple {
    elements: int[],
}

class ExprMap {
    entries: MapExprEntry[],
}

class ExprBlock {
    stmts: int[],
    tail_expr: int?,
}

class ExprMemberAccess {
    base: int,
    member: string,
}

class ExprUpcast {
    base: int,
    target: TypeExpr,
}

class ExprQualifiedPath {
    qself: TypeExpr,
    interface_: TypeExpr,
    member: string,
}

class ExprOptionalMemberAccess {
    base: int,
    member: string,
}

class ExprIndex {
    base: int,
    index: int,
}

class ExprLambda {
    value: LambdaDef,
}

class ExprOptionalIndex {
    base: int,
    index: int,
}

class ExprOptionalCall {
    callee: int,
    args: CallArg[],
}

class ExprOptionalChain {
    expr: int,
}

class ExprTemplate {
    tag: TemplateTag,
    segments: TemplateSegment[],
}

class ExprMissing {
}

// Which BEP-049 backtick form an [`Expr::Template`] is, plus the per-form
// payload needed to realize it.
type TemplateTag = TemplateTagDefault | TemplateTagCustom;

class TemplateTagDefault {
    elaborated: int,
}

class TemplateTagCustom {
    tag: int,
    body: int,
}

// One segment of an [`Expr::Template`] body. Parallel to `BacktickSegment`
// in the CST layer, but every sub-expression is already lowered.
type TemplateSegment = TemplateSegmentText
    | TemplateSegmentInterp
    | TemplateSegmentEffect
    | TemplateSegmentFor
    | TemplateSegmentCStyleFor
    | TemplateSegmentIf;

class TemplateSegmentText {
    value: string,
}

class TemplateSegmentInterp {
    value: int,
}

class TemplateSegmentEffect {
    block: int,
    stmts: int[],
}

class TemplateSegmentFor {
    binding: int,
    collection: int,
    body: TemplateSegment[],
}

class TemplateSegmentCStyleFor {
    init: int,
    cond: int,
    step: int?,
    body: TemplateSegment[],
}

class TemplateSegmentIf {
    branches: TemplateIfBranch[],
    else_body: TemplateSegment[]?,
}

class TemplateIfBranch {
    condition: int,
    body: TemplateSegment[],
}

class CallArg {
    label: string?,
    expr: int,

    // port: baml_compiler2_ast/src/ast.rs::CallArg::positional @ d9be6853b
    function positional(expr: int) -> CallArg throws never {
        CallArg { label: null, expr: expr }
    }

    // port: baml_compiler2_ast/src/ast.rs::CallArg::named @ d9be6853b
    function named(label: string, expr: int) -> CallArg throws never {
        CallArg { label: label, expr: expr }
    }
}

// Statements — modeled after `Stmt` in `body.rs`.
type Stmt = StmtExpr
    | StmtTypeBinding
    | StmtLet
    | StmtWhile
    | StmtWhileLet
    | StmtFor
    | StmtReturn
    | StmtThrow
    | StmtBreak
    | StmtContinue
    | StmtDefer
    | StmtAssign
    | StmtAssignOp
    | StmtMissing
    | StmtHeaderComment;

class StmtExpr {
    value: int,
}

class StmtTypeBinding {
    name: string,
    operand: int,
    bounds: TypeExpr[],
    else_branch: int?,
}

class StmtLet {
    pattern: int,
    initializer: int?,
    origin: LetOrigin,
    else_branch: int?,
}

class StmtWhile {
    condition: int,
    body: int,
    after: int?,
    origin: LoopOrigin,
}

class StmtWhileLet {
    pattern: int,
    scrutinee: int,
    body: int,
}

class StmtFor {
    binding: int,
    collection: int,
    body: int,
}

class StmtReturn {
    value: int?,
}

class StmtThrow {
    value: int,
}

class StmtBreak {
}

class StmtContinue {
}

class StmtDefer {
    body: int,
}

class StmtAssign {
    target: int,
    value: int,
}

class StmtAssignOp {
    target: int,
    op: AssignOp,
    value: int,
}

class StmtMissing {
}

class StmtHeaderComment {
    name: string,
    level: int,
}

// A pattern in the AST.
// 
// One flat enum. Atoms (`Wildcard`, `Bind`, `Class`, `Type`) describe a
// single shape; the only combinator (`Or`) combines other patterns.
// 
// Lowering invariants:
// - `_` always lowers to [`Pattern::Wildcard`] — never `Bind { name: "_" }`.
// - 1-element `Or` is NOT allocated; it collapses to the inner pattern.
// So if you see `Or(parts)`, `parts.len() >= 2`.
// - The `: T` annotation in `let x: T` is carried as the bind's `subpat`
// slot (see [`Pattern::Bind`]) and likewise as `Pattern::Array`'s
// `ascription` field for `[…]: T`. `:` is only valid after `let x` or
// `[…]` — it is rejected on `_`, `Class { … }`, bare types, and
// Or-patterns.
type Pattern = PatternWildcard
    | PatternBind
    | PatternClass
    | PatternArray
    | PatternTuple
    | PatternType
    | PatternOr;

class PatternWildcard {
}

class PatternBind {
    name: string,
    subpat: int?,
}

class PatternClass {
    class_: string[],
    generic_args: TypeExpr[],
    associated_type_bindings: AssociatedTypeBinding[],
    fields: FieldPat[],
}

class PatternArray {
    prefix: int[],
    rest: ArrayRestPat?,
    suffix: int[],
    ascription: TypeExpr?,
}

class PatternTuple {
    value: int[],
}

class PatternType {
    value: TypeExpr,
}

class PatternOr {
    value: int[],
}

// Single field inside a class destructure pattern.
// 
// Shorthand `{ f }` lowers to `FieldPat { field: f, pat: <Bind { name: f }> }`,
// so consumers never see the missing-pattern shape.
class FieldPat {
    field: string,
    field_span: root.syntax.TextRange,
    pat: int,
}

class ArrayRestPat {
    pat: int?,
}

// port: baml_compiler2_ast/src/ast.rs::Pattern::binding_name @ d9be6853b
// The first name this pattern introduces, if any; see `pattern_bound_names`
// for patterns with several.
function pattern_binding_name(pattern: Pattern, patterns: Pattern[]) -> string? throws never {
    pattern_bound_names(pattern, patterns).at(0)
}

// port: baml_compiler2_ast/src/ast.rs::Pattern::bound_names @ d9be6853b
// Every name this pattern introduces into scope, in declaration order,
// through chains, fields and Or-branches. Every link of a bind chain binds.
// For an `Or` this is the first alternative's names; checking that the
// alternatives agree is the caller's job.
function pattern_bound_names(pattern: Pattern, patterns: Pattern[]) -> string[] throws never {
    let out: string[] = [];
    pattern_collect_bound_names(pattern, patterns, out);
    out
}

// port: baml_compiler2_ast/src/ast.rs::Pattern::collect_bound_names @ d9be6853b
function pattern_collect_bound_names(
    pattern: Pattern,
    patterns: Pattern[],
    out: string[],
) -> void throws never {
    let visit = (id: int) -> void {
        pattern_collect_bound_names(patterns[id], patterns, out)
    };
    match (pattern) {
        PatternWildcard | PatternType => {},
        let p: PatternBind => {
            out.push(p.name);
            if let sub: int = p.subpat {
                visit(sub);
            }
        },
        let p: PatternClass => {
            p.fields.for_each((f) -> {
                visit(f.pat)
            })
        },
        let p: PatternArray => {
            p.prefix.for_each(visit);
            if let rest: int = p.rest?.pat {
                visit(rest);
            }
            p.suffix.for_each(visit);
        },
        let p: PatternTuple => p.value.for_each(visit),
        // Pick any one alternative to report; the uniformity check is the
        // caller's job.
        let p: PatternOr => {
            if let first: int = p.value.at(0) {
                visit(first);
            }
        },
    }
}

class MatchArm {
    pattern: int,
    guard: int?,
    body: int,
}

// Every catch clause creates its own protected expression and handler. The
// three keywords select the [`CatchClauseKind::requires_error_coverage`]
// and [`CatchClauseKind::wildcard_traps_panics`] policies.
enum CatchClauseKind {
    Catch,
    CatchAll,
    CatchAllPanics,
}

// port: baml_compiler2_ast/src/ast.rs::CatchClauseKind::keyword @ d9be6853b
// The clause keyword as written in source.
function catch_clause_kind_keyword(kind: CatchClauseKind) -> string throws never {
    match (kind) {
        CatchClauseKind.Catch => "catch",
        CatchClauseKind.CatchAll => "catch_all",
        CatchClauseKind.CatchAllPanics => "catch_all_panics",
    }
}

// port: baml_compiler2_ast/src/ast.rs::CatchClauseKind::requires_error_coverage @ d9be6853b
// Whether the clause's arms must cover every error that reaches it (E0062
// otherwise).
function catch_clause_kind_requires_error_coverage(kind: CatchClauseKind) -> bool throws never {
    kind != CatchClauseKind.Catch
}

// port: baml_compiler2_ast/src/ast.rs::CatchClauseKind::wildcard_traps_panics @ d9be6853b
// Whether a wildcard arm (`_`, a bare `let x`) of this clause receives
// panics. Elsewhere only an arm naming a panic's type catches it.
function catch_clause_kind_wildcard_traps_panics(kind: CatchClauseKind) -> bool throws never {
    kind == CatchClauseKind.CatchAllPanics
}

// port: baml_compiler2_ast/src/ast.rs::CatchClauseKind::requires_panic_coverage @ d9be6853b
// Whether the clause's arms must also cover every panic (E0062 otherwise).
function catch_clause_kind_requires_panic_coverage(kind: CatchClauseKind) -> bool throws never {
    kind == CatchClauseKind.CatchAllPanics
}

class CatchClause {
    kind: CatchClauseKind,
    binding: int,
    stack_trace_binding: int?,
    arms: int[],
}

class CatchArm {
    pattern: int,
    body: int,
}

class SpreadField {
    expr: int,
    position: int,
}

enum LetOrigin {
    Source,
    Client,
}

enum FunctionOrigin {
    UserDefined,
    Companion,
    Internal,
    AutoDerive,
    TestInitializer,
}

class FunctionMetadata {
    trace_passthrough: bool,
    explicit_trace_passthrough: bool,
    origin: FunctionOrigin,
    is_language_internal: bool,

    // port: baml_compiler2_ast/src/ast.rs::FunctionMetadata::user_facing @ d9be6853b
    function user_facing(origin: FunctionOrigin) -> FunctionMetadata throws never {
        FunctionMetadata {
            origin: origin,
            is_language_internal: false,
            trace_passthrough: false,
            explicit_trace_passthrough: false,
        }
    }

    // port: baml_compiler2_ast/src/ast.rs::FunctionMetadata::language_internal @ d9be6853b
    function language_internal(origin: FunctionOrigin) -> FunctionMetadata throws never {
        FunctionMetadata {
            origin: origin,
            is_language_internal: true,
            trace_passthrough: false,
            explicit_trace_passthrough: false,
        }
    }
}

// The source form a [`Stmt::While`] was written in.
type LoopOrigin = LoopOriginWhile | LoopOriginFor;

class LoopOriginWhile {
}

class LoopOriginFor {
    init: int,
}

// Binary operators — matches those supported in `body.rs`.
enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
    NullCoalesce,
}

// port: baml_compiler2_ast/src/ast.rs::impl Display for BinaryOp @ d9be6853b
function binary_op_display(op: BinaryOp) -> string throws never {
    match (op) {
        BinaryOp.Add => "+",
        BinaryOp.Sub => "-",
        BinaryOp.Mul => "*",
        BinaryOp.Div => "/",
        BinaryOp.Mod => "%",
        BinaryOp.Eq => "==",
        BinaryOp.Ne => "!=",
        BinaryOp.Lt => "<",
        BinaryOp.Le => "<=",
        BinaryOp.Gt => ">",
        BinaryOp.Ge => ">=",
        BinaryOp.And => "&&",
        BinaryOp.Or => "||",
        BinaryOp.BitAnd => "&",
        BinaryOp.BitOr => "|",
        BinaryOp.BitXor => "^",
        BinaryOp.Shl => "<<",
        BinaryOp.Shr => ">>",
        BinaryOp.NullCoalesce => "??",
    }
}

enum UnaryOp {
    Not,
    Neg,
}

// port: baml_compiler2_ast/src/ast.rs::impl Display for UnaryOp @ d9be6853b
function unary_op_display(op: UnaryOp) -> string throws never {
    match (op) {
        UnaryOp.Not => "!",
        UnaryOp.Neg => "-",
    }
}

// Compound assignment operators.
enum AssignOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
}

// Top-level item — the output unit of CST → AST lowering.
type Item = ItemFunction
    | ItemClass
    | ItemEnum
    | ItemInterface
    | ItemTypeAlias
    | ItemLet
    | ItemImplementsFor;

class ItemFunction {
    value: FunctionDef,
}

class ItemClass {
    value: ClassDef,
}

class ItemEnum {
    value: EnumDef,
}

class ItemInterface {
    value: InterfaceDef,
}

class ItemTypeAlias {
    value: TypeAliasDef,
}

class ItemLet {
    value: LetDef,
}

class ItemImplementsFor {
    value: ImplementsForDef,
}

type DeclarativeMeta = DeclarativeMetaLlm;

class DeclarativeMetaLlm {
    value: LlmBodyDef,
}

// A trace hook attached with `/// baml:$trace=path.to.hook`.
class TraceHookDirective {
    path: string[],
    span: root.syntax.TextRange,
}

class FunctionDef {
    name: string,
    generic_params: GenericParam[],
    params: Param[],
    defaults: FunctionDefaults,
    return_type: TypeExpr?,
    throws_: TypeExpr?,
    body: FunctionBodyDef?,
    declarative_meta: DeclarativeMeta?,
    metadata: FunctionMetadata,
    attributes: RawAttribute[],
    docstring: string?,
    header_title: string?,
    is_tagged_template_tag: bool,
    directives: NativeDirectives,
    trace_hook: TraceHookDirective?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

// A `//baml:` directive a native function is declared with, read by the
// builtin codegen: how its `$rust_function` glue is bound.
enum NativeDirective {
    MutSelf,
    Vm,
    MutVm,
    MayYield,
    Fallible,
    LocalTwin,
}

// port: baml_compiler2_ast/src/ast.rs::NativeDirective::bit @ d9be6853b
// `1 << (directive as u8)`: the directive's declaration index.
function native_directive_bit(directive: NativeDirective) -> int throws never {
    let index = match (directive) {
        NativeDirective.MutSelf => 0,
        NativeDirective.Vm => 1,
        NativeDirective.MutVm => 2,
        NativeDirective.MayYield => 3,
        NativeDirective.Fallible => 4,
        NativeDirective.LocalTwin => 5,
    };
    1 << index
}

// The set of [`NativeDirective`]s written on a function. Each is a fact of
// the declaration; the codegen combines them.
class NativeDirectives {
    value: int,

    // port: baml_compiler2_ast/src/ast.rs::NativeDirectives::NONE @ d9be6853b
    // (and `Default`). No directives. A function, not a const: a class value
    // is a shared reference.
    function none() -> NativeDirectives throws never {
        NativeDirectives { value: 0 }
    }

    // port: baml_compiler2_ast/src/ast.rs::NativeDirectives::with @ d9be6853b
    // This set with `directive` in it.
    function with(self, directive: NativeDirective) -> NativeDirectives throws never {
        NativeDirectives { value: self.value | native_directive_bit(directive) }
    }

    // port: baml_compiler2_ast/src/ast.rs::NativeDirectives::has @ d9be6853b
    // Whether `directive` was written.
    function has(self, directive: NativeDirective) -> bool throws never {
        (self.value & native_directive_bit(directive)) != 0
    }
}

// What produced a [`LambdaDef`], where that changes how TIR types it.
// 
// Replaces matching on a synthetic `name` string, which could not distinguish
// the cases without agreeing on a magic constant at a distance.
enum LambdaKind {
    Anonymous,
    Spawn,
}

// An anonymous function *value*, written inside an expression body.
// 
// Distinct from [`FunctionDef`], which describes a declared item. A lambda has
// no name, no generic parameters (the parser rejects them), no attributes, no
// docstring and no declarative metadata, and its body is always an expression
// body — never a `$rust_function` builtin. Carrying only those fields keeps
// those states unrepresentable rather than filling them with synthetic values
// that every reader then has to know to ignore.
class LambdaDef {
    kind: LambdaKind,
    params: Param[],
    defaults: FunctionDefaults,
    return_type: TypeExpr?,
    throws_: TypeExpr?,
    body: int?,
    span: root.syntax.TextRange,
}

class FunctionDefaults {
    exprs: ExprBody,
    source_map: AstSourceMap,

    // port: baml_compiler2_ast/src/ast.rs::FunctionDefaults::empty @ d9be6853b
    function empty() -> FunctionDefaults throws never {
        FunctionDefaults { exprs: ExprBody.new(), source_map: AstSourceMap.new() }
    }

    // port: baml_compiler2_ast/src/ast.rs::FunctionDefaults::expr @ d9be6853b
    // The default expression a `Param.default` id names.
    function expr(self, id: int) -> Expr throws never {
        self.exprs.exprs[id]
    }
}

type FunctionBodyDef = FunctionBodyDefExpr | FunctionBodyDefBuiltin;

class FunctionBodyDefExpr {
    v0: ExprBody,
    v1: AstSourceMap,
}

class FunctionBodyDefBuiltin {
    value: BuiltinKind,
}

// What kind of builtin a function is.
enum BuiltinKind {
    Vm,
    Io,
    Intrinsic,
    AwaitAny,
    Spawn,
}

// port: baml_compiler2_ast/src/ast.rs::BuiltinKind::lowers_at_call_site @ d9be6853b
// Whether the builtin is lowered where it is called instead of compiled into
// a callable: it has no function value, so it may only be a direct callee.
function builtin_kind_lowers_at_call_site(kind: BuiltinKind) -> bool throws never {
    match (kind) {
        BuiltinKind.Vm | BuiltinKind.Io => false,
        BuiltinKind.Intrinsic | BuiltinKind.AwaitAny | BuiltinKind.Spawn => true,
    }
}

// Source geometry of an LLM function's prompt literal.
class LlmPromptSpans {
    literal: root.syntax.TextRange,
    code: root.syntax.TextRange[],
}

class LlmBodyDef {
    client_: string?,
    companion_bodies: (string, (ExprBody, AstSourceMap))[],
    prompt_spans: LlmPromptSpans?,
    prompt_segments: TemplateSegment[],
    has_tools: bool,
    span: root.syntax.TextRange,
}

class Param {
    name: string,
    type_expr: TypeExpr?,
    default: int?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

// deviation: Rust's `DefaultExprId` newtype (and its `new` / `expr`) is not
// ported: `Param.default` is the plain `int` id into `FunctionDefaults.exprs`.

class ClassDef {
    name: string,
    generic_params: GenericParam[],
    fields: FieldDef[],
    methods: FunctionDef[],
    attributes: RawAttribute[],
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

// Definition of an `interface` declaration (BEP-044).
// 
// Interfaces declare a contract over fields and methods. Types opt in to
// the contract with an `implements` block ([`ImplementsForDef`]).
class InterfaceDef {
    name: string,
    generic_params: GenericParam[],
    requires_: TypeExpr[],
    fields: FieldDef[],
    associated_types: AssociatedTypeDef[],
    required_methods: MethodSigDef[],
    default_methods: FunctionDef[],
    attributes: RawAttribute[],
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

// Method signature declared in an interface body without a body — i.e., a
// required method. Mirrors [`FunctionDef`] minus the body.
class MethodSigDef {
    name: string,
    generic_params: GenericParam[],
    params: Param[],
    defaults: FunctionDefaults,
    return_type: TypeExpr?,
    throws_: TypeExpr?,
    attributes: RawAttribute[],
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

class InterfaceFieldLinkDef {
    interface_field: string,
    class_field: string,
    span: root.syntax.TextRange,
    interface_field_span: root.syntax.TextRange,
    class_field_span: root.syntax.TextRange,
}

// Where an `implements` block was written. The in-body spelling is
// shorthand for the out-of-body one (`TYPE_SYSTEM.md`, "Interface
// Implementations"); the origin is kept for the rules that read it — an
// interface with fields can only be implemented in-body — and must not
// influence resolution, dispatch or coherence.
enum ImplOrigin {
    InBody,
    OutOfBody,
}

// An `implements` block (BEP-044), in either spelling: `implements I for T
// { ... }` at the top level, or `implements I { ... }` inside the body of
// the class it is for.
class ImplementsForDef {
    generic_params: GenericParam[],
    interface_target: TypeExpr,
    for_target: TypeExpr,
    field_links: InterfaceFieldLinkDef[],
    associated_type_bindings: AssociatedTypeBindingDef[],
    methods: FunctionDef[],
    origin: ImplOrigin,
    span: root.syntax.TextRange,
    docstring: string?,

    // port: baml_compiler2_ast/src/ast.rs::ImplementsForDef::is_for_class @ d9be6853b
    // Whether this block implements for `class_def` itself; see
    // `impl_is_for_class`.
    function is_for_class(self, class_def: ClassDef) -> bool throws never {
        impl_is_for_class(self.origin, self.generic_params.length() == 0, self.for_target, class_def.name)
    }
}

// port: baml_compiler2_ast/src/ast.rs::impl_is_for_class @ d9be6853b
// Whether an `implements` block with these parts implements for the class
// named `class_name` itself: written in its body, or out-of-body for exactly
// that class (no generics on the block, the class named bare). The ONE rule,
// read by the AST's consumers and by HIR's `class_impls`.
function impl_is_for_class(
    origin: ImplOrigin,
    no_generics: bool,
    for_target: TypeExpr,
    class_name: string,
) -> bool throws never {
    let kind = for_target.kind;
    if (!(kind is TypeExprKindPath)) {
        return false;
    }
    match (origin) {
        ImplOrigin.InBody => kind.path.leaf() == class_name,
        ImplOrigin.OutOfBody => {
            no_generics && kind.generic_args.length() == 0 && kind.path.segments == [class_name]
        },
    }
}

// port: baml_compiler2_ast/src/ast.rs::class_self_type @ d9be6853b
// The type a class's in-body `implements` blocks are for: the class applied
// to its own generic parameters (`C<T, U>`), spanning its name.
function class_self_type(
    class_name: string,
    generic_params: GenericParam[],
    span: root.syntax.TextRange,
) -> TypeExpr throws never {
    let generic_args = generic_params.map((param) -> {
        TypeExpr {
            kind: TypeExprKindPath {
                path: root.base.Path.new([param.name]),
                generic_args: [],
                associated_type_bindings: [],
            },
            span: param.name_span,
        }
    });
    TypeExpr {
        kind: TypeExprKindPath {
            path: root.base.Path.new([class_name]),
            generic_args: generic_args,
            associated_type_bindings: [],
        },
        span: span,
    }
}

class AssociatedTypeDef {
    name: string,
    bound: TypeExpr?,
    default: TypeExpr?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

class AssociatedTypeBindingDef {
    name: string,
    type_expr: TypeExpr?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

class FieldDef {
    name: string,
    type_expr: TypeExpr,
    attributes: RawAttribute[],
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

class EnumDef {
    name: string,
    variants: VariantDef[],
    attributes: RawAttribute[],
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

class VariantDef {
    name: string,
    attributes: RawAttribute[],
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

class TypeAliasDef {
    name: string,
    type_expr: TypeExpr?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
    docstring: string?,
}

// A top-level let binding: a global variable (`const NAME: T = expr;` at file
// scope), a compiler-generated client binding (`client Name = expr;`), or a
// Session submission's persisted root binding. All three share the `$init`
// pipeline: the initializer runs once, before any request, and the binding is
// immutable afterwards.
// Carries an optional `ExprBody` initializer that flows through TIR type-checking.
class LetDef {
    name: string,
    type_annotation: TypeExpr?,
    initializer: (ExprBody, AstSourceMap)?,
    origin: LetOrigin,
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

