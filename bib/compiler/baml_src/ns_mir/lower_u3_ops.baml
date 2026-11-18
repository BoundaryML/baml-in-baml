// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Operators (lower.rs "3.4: Operator mapping and binary/unary lowering"):
// binary operators and their primitive-or-driver routing, short-circuit and
// `??`, optional chaining (`?.` member, index and call), compound
// assignment, and unary operators.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first; the
//   associated functions (`convert_binop`, `arith_primitive`,
//   `is_string_ty`, `ordering_method`) are plain functions.
// - The nested helper fns (`prim_class` in `equality_uses_primitive_opcode`,
//   `kind` in `arith_primitive`, `orderable` in
//   `ordering_uses_primitive_opcode`) are the free functions
//   `equality_prim_class`, `arith_primitive_kind` and `orderable`.
// - `RuntimeTy::strip_null` is `root.types.runtime_ty_strip_null`
//   (`ns_types/template_stubs_u3.baml`).

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::convert_binop @ d9be6853b
function convert_binop(op: root.ast.BinaryOp) -> BinOp? throws never {
    match (op) {
        root.ast.BinaryOp.Add => BinOp.Add,
        root.ast.BinaryOp.Sub => BinOp.Sub,
        root.ast.BinaryOp.Mul => BinOp.Mul,
        root.ast.BinaryOp.Div => BinOp.Div,
        root.ast.BinaryOp.Mod => BinOp.Mod,
        root.ast.BinaryOp.Eq => BinOp.Eq,
        root.ast.BinaryOp.Ne => BinOp.Ne,
        root.ast.BinaryOp.Lt => BinOp.Lt,
        root.ast.BinaryOp.Le => BinOp.Le,
        root.ast.BinaryOp.Gt => BinOp.Gt,
        root.ast.BinaryOp.Ge => BinOp.Ge,
        root.ast.BinaryOp.BitAnd => BinOp.BitAnd,
        root.ast.BinaryOp.BitOr => BinOp.BitOr,
        root.ast.BinaryOp.BitXor => BinOp.BitXor,
        root.ast.BinaryOp.Shl => BinOp.Shl,
        root.ast.BinaryOp.Shr => BinOp.Shr,
        // Short-circuit operators are handled separately.
        root.ast.BinaryOp.And | root.ast.BinaryOp.Or => null,
        // Null coalescing desugars to control flow, not a binary op.
        root.ast.BinaryOp.NullCoalesce => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_binary @ d9be6853b
function lower_binary(
    ctx: LoweringContext,
    expr_id: int,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    match (op) {
        root.ast.BinaryOp.And => {
            lower_short_circuit(ctx, expr_id, lhs, rhs, dest, true);
            return;
        },
        root.ast.BinaryOp.Or => {
            lower_short_circuit(ctx, expr_id, lhs, rhs, dest, false);
            return;
        },
        root.ast.BinaryOp.NullCoalesce => {
            lower_null_coalesce(ctx, expr_id, lhs, rhs, dest);
            return;
        },
        _ => {},
    }

    // TIR may already have folded this expression to a literal constant.
    if (ctx.opt == OptLevel.Two) {
        match (expr_ty(ctx, expr_id)) {
            let lit: root.types.TyLiteral => {
                let constant = lower_literal(lit.value);
                ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: constant } });
                return;
            },
            _ => {},
        }
    }

    // A chain of string `+` (`a + "/" + b`, and every template) joins its
    // parts in one step rather than one `+` at a time.
    if (op == root.ast.BinaryOp.Add) {
        let parts = string_concat_parts(ctx, expr_id);
        if (parts != null) {
            let operands: Operand[] = [];
            for (let part in parts) {
                operands.push(lower_to_operand(ctx, part));
            }
            ctx.builder.assign(dest, RvalueConcatStrings { value: operands });
            return;
        }
    }

    // `==`/`!=`: the `baml.ops.equals_equals` driver is the always-correct
    // general case (it compares the operands' concrete runtime types and
    // dispatches a custom `Equals` when present). The specialized comparison
    // opcode is only an equivalent optimization when both operands are the
    // SAME primitive, so keep it there and route everything else through the
    // driver.
    if (
        (op == root.ast.BinaryOp.Eq || op == root.ast.BinaryOp.Ne)
            && !equality_uses_primitive_opcode(ctx, lhs, rhs)
    ) {
        lower_equality_via_driver(ctx, op, lhs, rhs, dest);
        return;
    }

    // Arithmetic over non-primitive operands (a user type, or a union /
    // interface existential / type variable involving one) dispatches through
    // the matching `baml.ops` interface, resolved at runtime from the
    // operands' concrete types by the `__union_*` driver. Primitive operands
    // keep the specialized opcode fast path below.
    let is_arithmetic = match (op) {
        root.ast.BinaryOp.Add
            | root.ast.BinaryOp.Sub
            | root.ast.BinaryOp.Mul
            | root.ast.BinaryOp.Div
            | root.ast.BinaryOp.Mod =>
        {
            true
        },
        _ => false,
    };
    if (is_arithmetic && !arithmetic_uses_primitive_opcode(ctx, lhs, rhs)) {
        lower_arithmetic_via_driver(ctx, expr_id, op, lhs, rhs, dest);
        return;
    }

    // Ordering over operands the comparison opcodes cannot order (`bool`, an
    // enum or class implementing `Compare`, or a type variable / `Self` /
    // projection that realizes to one) dispatches through
    // `baml.ops.Compare`, resolved at runtime from the receiver's concrete
    // type. `Compare` is single dispatch (`other: Self`), so it needs no
    // `__union_*` driver.
    let method = ordering_method(op);
    if (method != null && !ordering_uses_primitive_opcode(ctx, lhs, rhs)) {
        lower_ordering_via_virtual_call(ctx, method, lhs, rhs, dest);
        return;
    }

    // Mixed `int OP bigint` operators resolve the `int` operand to a small
    // local `BigInt` in the VM (the specialized `*Bigint` / `CmpBigint`
    // opcodes accept a lone `int` operand): lower both operands naturally.
    let left = lower_to_operand(ctx, lhs);
    let right = lower_to_operand(ctx, rhs);
    let mir_op = convert_binop(op);
    if (mir_op == null) {
        // Fallback: does not happen for well-typed code.
        throw internal_error(ctx, "unsupported binary op", expr_id);
    }
    ctx.builder.assign(dest, RvalueBinaryOp { op: mir_op, left: left, right: right });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::equality_uses_primitive_opcode @ d9be6853b
// Whether both operands of an `==`/`!=` are the SAME primitive type, so the
// specialized comparison opcode is equivalent to the `equals_equals` driver
// (value comparison matches the unoverridable native `Equals`). Literals
// widen to their base primitive; everything else (mixed primitives,
// `uint8array`, enums, classes, containers, unions, interfaces, `unknown`)
// goes through the driver.
//
// A `null` operand is the exception: `null` is the one value of its type and
// the driver finds it equal to `null` alone, never running a custom
// `Equals`. So `x == null` for any `x` is a test against the `null` word,
// which the emitter turns into `IsNull` / `IsNotNull`.
function equality_uses_primitive_opcode(
    ctx: LoweringContext,
    lhs: int,
    rhs: int,
) -> bool throws MirInternalError {
    let lhs_ty = expr_ty(ctx, lhs);
    let rhs_ty = expr_ty(ctx, rhs);
    let lhs_null = match (lhs_ty) {
        root.types.TyNull => true,
        _ => false,
    };
    let rhs_null = match (rhs_ty) {
        root.types.TyNull => true,
        _ => false,
    };
    if (lhs_null || rhs_null) {
        return true;
    }
    let l = equality_prim_class(lhs_ty);
    l != null && l == equality_prim_class(rhs_ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::equality_uses_primitive_opcode @ d9be6853b
// Rust's nested `prim_class`: the primitive class of an equality operand,
// literal widened to its base.
function equality_prim_class(ty: root.types.RuntimeTy) -> int? throws never {
    match (ty) {
        root.types.TyInt => 0,
        root.types.TyBigint => 1,
        root.types.TyFloat => 2,
        root.types.TyString => 3,
        root.types.TyBool => 4,
        root.types.TyNull => 5,
        let lit: root.types.TyLiteral => match (lit.value) {
            root.base.LiteralInt => 0,
            root.base.LiteralBigint => 1,
            root.base.LiteralFloat => 2,
            root.base.LiteralString => 3,
            root.base.LiteralBool => 4,
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_equality_via_driver @ d9be6853b
// Lower `==`/`!=` through the `baml.ops.equals_equals` driver: the general
// case (concrete-type comparison and custom `Equals` dispatch). The driver
// may yield (it can call a user `eq`), so the call splits the block. `!=`
// negates the `==` result.
//
// Rust notes a known bug, kept: `!=` never dispatches `Equals.neq`, so a
// type that overrides `neq` inconsistently with `eq` sees the override
// ignored by the operator.
function lower_equality_via_driver(
    ctx: LoweringContext,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    let lhs_ty = tir_expr_type(ctx, lhs);
    let rhs_ty = tir_expr_type(ctx, rhs);
    let structural: root.types.StructuralInterface? = if (lhs_ty != null && rhs_ty != null && lhs_ty == rhs_ty) {
        structural_witness(ctx, lhs_ty, baml_decl(ctx, "ops", "Equals"))
    } else {
        null
    };
    let lhs_op = lower_to_operand(ctx, lhs);
    let rhs_op = lower_to_operand(ctx, rhs);
    let bool_ty = root.types.TyBool {};
    if (structural != null) {
        let result: Place = if (op == root.ast.BinaryOp.Eq) {
            place_clone(dest)
        } else {
            PlaceLocal { value: ctx.builder.declare_local(bool_ty) }
        };
        let func = lang_function(
            ctx,
            root.base.LangPackage.Baml,
            [],
            root.types.structural_interface_native_function(structural),
        );
        emit_direct_structural_call(ctx, func, [lhs_op, rhs_op], 0, null, bool_ty, place_clone(result));
        if (op == root.ast.BinaryOp.Ne) {
            ctx.builder.assign(
                dest,
                RvalueUnaryOp { op: UnaryOp.Not, operand: OperandCopy { value: result } },
            );
        }
        return;
    }
    if (op == root.ast.BinaryOp.Eq) {
        lower_via_ops_driver(ctx, "equals_equals", [lhs_op, rhs_op], bool_ty, dest);
        return;
    }
    // `!=`: call into a bool temp, then negate into `dest` (`assign` handles
    // projection destinations, so this covers both local and projection
    // cases).
    let eq_dest = PlaceLocal { value: ctx.builder.declare_local(bool_ty) };
    lower_via_ops_driver(ctx, "equals_equals", [lhs_op, rhs_op], bool_ty, place_clone(eq_dest));
    ctx.builder.assign(
        dest,
        RvalueUnaryOp { op: UnaryOp.Not, operand: OperandCopy { value: eq_dest } },
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_via_ops_driver @ d9be6853b
// Emit `dest = baml.ops.<driver>(args)`: the shared shape of the operator
// dispatch drivers (`equals_equals`, `__union_add`, ..., `__union_neg`). A
// driver may yield (it can call user bytecode), so the call splits the
// block and lowering resumes in a fresh one. The call terminator's
// destination must be a `PlaceLocal` (the emitter stores its result with
// `emit_store_place`, which only handles locals), so a projection/capture
// `dest` is routed through a `result_ty`-typed temp and copied through.
function lower_via_ops_driver(
    ctx: LoweringContext,
    driver: string,
    args: Operand[],
    result_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    let callee = OperandConstant {
        value: ConstantFunction { value: lang_function(ctx, root.base.LangPackage.Baml, ["ops"], driver) },
    };
    let needs_temp = match (dest) {
        PlaceLocal => false,
        _ => true,
    };
    let call_dest: Place = if (needs_temp) {
        PlaceLocal { value: ctx.builder.declare_local(result_ty) }
    } else {
        place_clone(dest)
    };
    let resume = ctx.builder.create_block();
    ctx.builder.call_with_type_args(callee, args, 0, place_clone(call_dest), resume);
    ctx.builder.set_current_block(resume);
    if (needs_temp) {
        ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: call_dest } });
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::arith_primitive @ d9be6853b
// Whether `ty` is a primitive the specialized opcodes handle directly:
// int/bigint/float, plus `string` when `include_string` (binary `+`
// concatenates; unary `-` has no string form). A literal counts as its
// base; a union counts only when every member is the SAME primitive kind
// (`int | 3`): a mixed-kind union (`int | float`) would let emit pick a
// single-kind opcode for a value of the other kind, so it takes the
// interface route instead, as does anything else. TIR has already validated
// the operation through the interface registry; this only chooses the
// lowering route.
//
// Shared by three operator families: arithmetic and unary negation go to
// the `__union_*` drivers when it says no, ordering to `baml.ops.Compare`
// (which additionally rejects `null`).
function arith_primitive(
    lang: root.base.LangRoots,
    ty: root.types.RuntimeTy,
    include_string: bool,
) -> bool throws never {
    match (ty) {
        let union_: root.types.RuntimeTyUnion => {
            // `null` members are transparent: only a chain-narrowed
            // compound-assign target still carries `| null` here (its null
            // case never reaches the op: the `?.` guard skips it), and binary
            // operands with a possible `null` are rejected by TIR before
            // lowering.
            let first: root.types.PrimitiveType? = null;
            for (let m in union_.members) {
                match (m) {
                    root.types.TyNull => {
                        continue;
                    },
                    _ => {},
                }
                let kind = arith_primitive_kind(lang, m, include_string);
                if (kind == null) {
                    return false;
                }
                if (first == null) {
                    first = kind;
                } else if (first != kind) {
                    return false;
                }
            }
            first != null
        },
        _ => arith_primitive_kind(lang, ty, include_string) != null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::arith_primitive @ d9be6853b
// Rust's nested `kind`: the primitive kind of a non-union member, literal
// widened to its base. The builtin wrapper classes (`baml.Float`, ...)
// count as their primitive: `self` inside their method bodies is
// class-typed but primitive-valued.
function arith_primitive_kind(
    lang: root.base.LangRoots,
    ty: root.types.RuntimeTy,
    include_string: bool,
) -> root.types.PrimitiveType? throws never {
    let primitive: root.types.PrimitiveType? = match (ty) {
        root.types.TyInt => root.types.PrimitiveType.Int,
        root.types.TyBigint => root.types.PrimitiveType.Bigint,
        root.types.TyFloat => root.types.PrimitiveType.Float,
        root.types.TyString => root.types.PrimitiveType.String,
        let lit: root.types.TyLiteral => root.types.primitive_type_from_literal(lit.value),
        let class_: root.types.RuntimeTyClass if class_.args.length() == 0 => {
            root.types.decl_name_builtin_primitive(class_.name, lang)
        },
        _ => null,
    };
    match (primitive) {
        root.types.PrimitiveType.Int
            | root.types.PrimitiveType.Bigint
            | root.types.PrimitiveType.Float =>
        {
            primitive
        },
        root.types.PrimitiveType.String if include_string => primitive,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::string_concat_parts @ d9be6853b
// The parts of the chain of string `+` that `expr_id` ends, left to right,
// or `null` when it joins fewer than three. The chain follows the left
// operand, which is how `a + b + c` and a template nest. A link that TIR
// folded to a constant is one part. Joining all parts at once is the same as
// one `+` at a time: every part is still evaluated left to right, and
// joining strings cannot fail.
function string_concat_parts(ctx: LoweringContext, expr_id: int) -> int[]? throws MirInternalError {
    let parts: int[] = [];
    let node = expr_id;
    while (true) {
        let link: root.ast.ExprBinary? = match (ctx.body.exprs[node]) {
            let binary: root.ast.ExprBinary if binary.op == root.ast.BinaryOp.Add => binary,
            _ => null,
        };
        if (link != null && is_string_add(ctx, node, link.lhs, link.rhs, node == expr_id)) {
            parts.push(link.rhs);
            node = link.lhs;
        } else {
            parts.push(node);
            break;
        }
    }
    if (parts.length() < 3) {
        return null;
    }
    parts.reverse()
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_string_add @ d9be6853b
// Whether `lhs + rhs` at `expr_id` concatenates two strings at run time.
// Below the root of a chain, a link TIR folded to a constant does not.
function is_string_add(
    ctx: LoweringContext,
    expr_id: int,
    lhs: int,
    rhs: int,
    is_root: bool,
) -> bool throws MirInternalError {
    if (!is_root && ctx.opt == OptLevel.Two) {
        match (expr_ty(ctx, expr_id)) {
            root.types.TyLiteral => {
                return false;
            },
            _ => {},
        }
    }
    is_string_ty(root.hir.lang_roots(ctx.db), expr_ty(ctx, lhs)) && is_string_ty(root.hir.lang_roots(ctx.db), expr_ty(ctx, rhs))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_string_ty @ d9be6853b
// Whether every value of `ty` is a string: a string, a string literal, the
// builtin `baml.String` class (`self` in its methods), or a union of them.
function is_string_ty(lang: root.base.LangRoots, ty: root.types.RuntimeTy) -> bool throws never {
    match (ty) {
        root.types.TyString => true,
        let lit: root.types.TyLiteral => match (lit.value) {
            root.base.LiteralString => true,
            _ => false,
        },
        let class_: root.types.RuntimeTyClass if class_.args.length() == 0 => {
            root.types.decl_name_builtin_primitive(class_.name, lang)
                == root.types.PrimitiveType.String
        },
        let union_: root.types.RuntimeTyUnion => {
            union_.members.length() > 0
                && union_.members.every((member) -> {
                    is_string_ty(lang, member)
                })
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::arithmetic_uses_primitive_opcode @ d9be6853b
// Whether both arithmetic operands are `arith_primitive` (string included:
// `+` concatenates, and TIR rejects strings under the other ops before
// lowering).
function arithmetic_uses_primitive_opcode(
    ctx: LoweringContext,
    lhs: int,
    rhs: int,
) -> bool throws MirInternalError {
    arith_primitive(root.hir.lang_roots(ctx.db), expr_ty(ctx, lhs), true)
        && arith_primitive(root.hir.lang_roots(ctx.db), expr_ty(ctx, rhs), true)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_arithmetic_via_driver @ d9be6853b
// Lower `a OP b` through the `baml.ops.__union_<op>` driver: the general
// case for operands whose static types don't pin a single impl. The driver
// resolves `<typeof a as Op<typeof b>>` at runtime and tail-calls it; its
// `unknown` result is the operator's value, re-typed by `dest`.
function lower_arithmetic_via_driver(
    ctx: LoweringContext,
    expr_id: int,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    let driver = match (op) {
        root.ast.BinaryOp.Add => "__union_add",
        root.ast.BinaryOp.Sub => "__union_sub",
        root.ast.BinaryOp.Mul => "__union_mul",
        root.ast.BinaryOp.Div => "__union_div",
        root.ast.BinaryOp.Mod => "__union_rem",
        _ => baml.sys.panic(`lower_arithmetic_via_driver: non-arithmetic op ${op}`),
    };
    let lhs_op = lower_to_operand(ctx, lhs);
    let rhs_op = lower_to_operand(ctx, rhs);
    let result_ty = expr_ty(ctx, expr_id);
    lower_via_ops_driver(ctx, driver, [lhs_op, rhs_op], result_ty, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ordering_uses_primitive_opcode @ d9be6853b
// Whether both ordering operands are primitives the comparison opcodes can
// ORDER: int, bigint, float, string. That is `arith_primitive` with
// `include_string` (which also admits a literal, a same-kind union like
// `int | 3`, and the builtin companion classes). `bool` falls out on its
// own, which routes it to the `Compare` impl the stdlib declares for it.
//
// Preconditions owed by TIR's ordering check: the two operands have the
// same type, and that type implements `baml.ops.Compare`. The `null` guard
// is defense in depth: `arith_primitive` treats a `null` union member as
// transparent, which ordering must not inherit.
//
// Reads `expr_ty` (TIR types), where a `Self`-annotated parameter in a
// concrete `implements` block is already resolved to the block's subject.
function ordering_uses_primitive_opcode(
    ctx: LoweringContext,
    lhs: int,
    rhs: int,
) -> bool throws MirInternalError {
    let lang_roots = root.hir.lang_roots(ctx.db);
    orderable(lang_roots, expr_ty(ctx, lhs)) && orderable(lang_roots, expr_ty(ctx, rhs))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ordering_uses_primitive_opcode @ d9be6853b
// Rust's nested `orderable`: `arith_primitive` minus the
// `null`-transparency carve-out.
function orderable(lang: root.base.LangRoots, ty: root.types.RuntimeTy) -> bool throws never {
    let has_null = match (ty) {
        let union_: root.types.RuntimeTyUnion => {
            union_.members.some((m) -> {
                match (m) {
                    root.types.TyNull => true,
                    _ => false,
                }
            })
        },
        root.types.TyNull => true,
        _ => false,
    };
    !has_null && arith_primitive(lang, ty, true)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ordering_method @ d9be6853b
// The `baml.ops.Compare` method an ordering operator dispatches, or `null`
// for any other operator. Single source for both the route test in
// `lower_binary` and the dispatched method name.
function ordering_method(op: root.ast.BinaryOp) -> string? throws never {
    match (op) {
        root.ast.BinaryOp.Lt => "lt",
        root.ast.BinaryOp.Le => "le",
        root.ast.BinaryOp.Gt => "gt",
        root.ast.BinaryOp.Ge => "ge",
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_ordering_via_virtual_call @ d9be6853b
// Lower `a OP b` for `<`/`<=`/`>`/`>=` through `baml.ops.Compare`, resolving
// the impl at runtime from the receiver's concrete type. `Compare` is single
// dispatch, non-generic, and its methods return plain `bool`, so the
// interface, method and result type are statically known and the receiver
// alone picks the impl. Each operator dispatches its OWN method (a user's
// `gt` override is honored); an impl declaring only `cmp` gets the
// interface's defaults merged into its method table when the program is
// baked.
function lower_ordering_via_virtual_call(
    ctx: LoweringContext,
    method: string,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    let lhs_op = lower_to_operand(ctx, lhs);
    let rhs_op = lower_to_operand(ctx, rhs);
    // `Compare` is non-generic and declares no associated types, so the
    // template carries neither; the receiver supplies `Self` at runtime, and
    // no enclosing generic params are consulted.
    let iface = tir2_interface_to_template(baml_decl(ctx, "ops", "Compare"), [], [], runtime(ctx), []);
    // Ordering always produces `bool`: TIR's ordering arm types it that way.
    let bool_ty = root.types.TyBool {};
    emit_virtual_call_with_operands(ctx, iface, method, [lhs_op, rhs_op], 0, 0, null, bool_ty, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::negate_uses_primitive_opcode @ d9be6853b
// Whether the negation operand is `arith_primitive` (the `Neg` opcode has
// no string form).
function negate_uses_primitive_opcode(
    ctx: LoweringContext,
    operand: int,
) -> bool throws MirInternalError {
    arith_primitive(root.hir.lang_roots(ctx.db), expr_ty(ctx, operand), false)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_negate_via_driver @ d9be6853b
// Lower `-a` through the `baml.ops.__union_neg` driver (single dispatch on
// `a`'s runtime type). Mirrors `lower_arithmetic_via_driver`.
function lower_negate_via_driver(
    ctx: LoweringContext,
    expr_id: int,
    operand: int,
    dest: Place,
) -> void throws MirInternalError {
    let operand_op = lower_to_operand(ctx, operand);
    let result_ty = expr_ty(ctx, expr_id);
    lower_via_ops_driver(ctx, "__union_neg", [operand_op], result_ty, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_short_circuit @ d9be6853b
function lower_short_circuit(
    ctx: LoweringContext,
    _expr_id: int,
    lhs: int,
    rhs: int,
    dest: Place,
    is_and: bool,
) -> void throws MirInternalError {
    // The expression has one value at its join, even when its eventual
    // destination has unrelated definitions (mutable locals/projections).
    let sc_dest = PlaceLocal { value: ctx.builder.declare_local(root.types.TyBool {}) };

    let lhs_op = lower_condition_operand(ctx, lhs);

    let bb_rhs = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    // Both paths define the expression value. Stackification chooses its
    // storage independently of the eventual mutable destination.
    let kind = if (is_and) {
        ShortCircuitKind.And
    } else {
        ShortCircuitKind.Or
    };
    ctx.builder.short_circuit(lhs_op, kind, place_clone(sc_dest), bb_rhs, bb_join);

    ctx.builder.set_current_block(bb_rhs);
    lower_expr(ctx, rhs, place_clone(sc_dest));
    // The stored result must be the COERCED bool (`a && b` is bool-typed even
    // when its operands are not), so a truthy-marked rhs re-assigns through
    // the coercion in place.
    if (tir_truthy_condition(ctx, rhs)) {
        ctx.builder.assign(
            place_clone(sc_dest),
            RvalueUnaryOp {
                op: UnaryOp.Truthy,
                operand: OperandCopy { value: place_clone(sc_dest) },
            },
        );
    }
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    ctx.builder.set_current_block(bb_join);
    ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: sc_dest } });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_null_coalesce @ d9be6853b
// Lower `a ?? b`: evaluate `a`, if null then evaluate `b`, otherwise use `a`.
function lower_null_coalesce(
    ctx: LoweringContext,
    expr_id: int,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    let result = ctx.builder.declare_local(expr_ty(ctx, expr_id));
    let result_place = PlaceLocal { value: result };

    let lhs_op = lower_to_operand(ctx, lhs);
    let bb_rhs = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();
    ctx.builder.short_circuit(
        lhs_op,
        ShortCircuitKind.Coalesce,
        place_clone(result_place),
        bb_rhs,
        bb_join,
    );

    ctx.builder.set_current_block(bb_rhs);
    lower_expr(ctx, rhs, place_clone(result_place));
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    ctx.builder.set_current_block(bb_join);
    ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: result_place } });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_chain @ d9be6853b
// Lower `OptionalChain { expr }`: set up a shared null exit for the whole
// chain.
function lower_optional_chain(
    ctx: LoweringContext,
    _expr_id: int,
    inner: int,
    dest: Place,
) -> void throws MirInternalError {
    let bb_null = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    // Push the shared null exit.
    ctx.chain_null_exits.push(bb_null);

    // Lower the inner expression: optional nodes jump to bb_null on null.
    lower_expr(ctx, inner, place_clone(dest));

    ctx.chain_null_exits.pop();

    // Non-null path: goto join
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    // Null path: assign null, goto join
    ctx.builder.set_current_block(bb_null);
    ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
    ctx.builder.goto(bb_join);

    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_assign_optional_chain @ d9be6853b
// Lower an assignment whose target is wrapped in `OptionalChain`. Sets up
// null guards, then emits the assignment only on the non-null path.
function lower_assign_optional_chain(
    ctx: LoweringContext,
    inner_target: int,
    value: int,
) -> void throws MirInternalError {
    let bb_null = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    // Push the shared null exit: optional nodes inside jump here on null.
    ctx.chain_null_exits.push(bb_null);

    // Lower the target as an lvalue (null checks at each `?.` node).
    let place = lower_store_place(ctx, inner_target);

    // Lower the value and assign.
    lower_expr(ctx, value, place);

    ctx.chain_null_exits.pop();

    // Non-null path: goto join
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    // Null path: skip the assignment, goto join
    ctx.builder.set_current_block(bb_null);
    ctx.builder.goto(bb_join);

    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_assign_op_optional_chain @ d9be6853b
// Lower a compound assignment (`+=`, ...) whose target is wrapped in
// `OptionalChain`.
function lower_assign_op_optional_chain(
    ctx: LoweringContext,
    inner_target: int,
    op: root.ast.AssignOp,
    value: int,
) -> void throws MirInternalError {
    let bb_null = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    ctx.chain_null_exits.push(bb_null);

    let place = lower_store_place(ctx, inner_target);
    emit_assign_op(ctx, place, inner_target, op, value);

    ctx.chain_null_exits.pop();

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    ctx.builder.set_current_block(bb_null);
    ctx.builder.goto(bb_join);

    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_assign_op @ d9be6853b
// Emit `place = place OP value`: the shared body of both `AssignOp`
// lowerings (plain and `?.`-chain targets). An arithmetic op whose operands
// aren't primitive routes through the `__union_*` driver, exactly like the
// binary-expression form (`v += w` and `v = v + w` must agree); everything
// else emits the raw opcode. Mixed `bigint OP= int` does NOT widen the int
// rhs on the opcode path: the specialized `*Bigint` opcodes accept a lone
// `int` operand.
function emit_assign_op(
    ctx: LoweringContext,
    place: Place,
    target: int,
    op: root.ast.AssignOp,
    value: int,
) -> void throws MirInternalError {
    match (place) {
        let index_place: PlaceIndex if index_place.kind == IndexKind.Map => {
            let current = PlaceLocal { value: ctx.builder.declare_local(expr_ty(ctx, target)) };
            let receiver = OperandCopy { value: index_place.base };
            let key = operand_copy_local(index_place.index);
            emit_map_call(ctx, "index", [operand_clone(receiver), operand_clone(key)], place_clone(current));
            emit_assign_op(ctx, place_clone(current), target, op, value);
            let ignored = PlaceLocal { value: ctx.builder.declare_local(root.types.TyUnknown {}) };
            emit_map_call(ctx, "set", [receiver, key, OperandCopy { value: current }], ignored);
            return;
        },
        _ => {},
    }
    let mir_op = convert_assign_op(op);
    let driver: string? = match (mir_op) {
        BinOp.Add => "__union_add",
        BinOp.Sub => "__union_sub",
        BinOp.Mul => "__union_mul",
        BinOp.Div => "__union_div",
        BinOp.Mod => "__union_rem",
        _ => null,
    };
    if (driver != null && !arithmetic_uses_primitive_opcode(ctx, target, value)) {
        let current = OperandCopy { value: place_clone(place) };
        let rhs = lower_to_operand(ctx, value);
        let result_ty = expr_ty(ctx, target);
        lower_via_ops_driver(ctx, driver, [current, rhs], result_ty, place);
        return;
    }
    let current = OperandCopy { value: place_clone(place) };
    let rhs = lower_to_operand(ctx, value);
    ctx.builder.assign(place, RvalueBinaryOp { op: mir_op, left: current, right: rhs });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_member_access @ d9be6853b
// Lower `obj?.member`: null-check obj, then access the member or produce
// null.
function lower_optional_member_access(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    field: string,
    dest: Place,
) -> void throws MirInternalError {
    let base_op = lower_to_operand(ctx, base);
    let base_ty = expr_ty(ctx, base);
    let base_local = operand_to_local(ctx, base_op, base_ty);

    // Test: base == null
    let is_null = RvalueBinaryOp {
        op: BinOp.Eq,
        left: operand_copy_local(base_local),
        right: OperandConstant { value: ConstantNull {} },
    };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, is_null);

    let bb_access = ctx.builder.create_block();

    let chain_null: int? = if (ctx.chain_null_exits.length() > 0) {
        ctx.chain_null_exits[ctx.chain_null_exits.length() - 1]
    } else {
        null
    };
    if (chain_null != null) {
        // Inside an OptionalChain: jump to the shared null exit.
        ctx.builder.branch(operand_copy_local(test_local), chain_null, bb_access);

        ctx.builder.set_current_block(bb_access);
        lower_member_access_with_base(ctx, expr_id, base, field, dest, cached_base = operand_copy_local(base_local));
        // No join of our own: the OptionalChain handler makes it.
    } else {
        // Standalone (no wrapping OptionalChain): own null and join blocks.
        let bb_null = ctx.builder.create_block();
        let bb_join = ctx.builder.create_block();

        ctx.builder.branch(operand_copy_local(test_local), bb_null, bb_access);

        ctx.builder.set_current_block(bb_access);
        lower_member_access_with_base(ctx, expr_id, base, field, place_clone(dest), cached_base = operand_copy_local(base_local));
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(bb_join);
        }

        ctx.builder.set_current_block(bb_null);
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
        ctx.builder.goto(bb_join);

        ctx.builder.set_current_block(bb_join);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_index @ d9be6853b
// Lower `obj?.[index]`: null-check obj, then index or produce null.
function lower_optional_index(
    ctx: LoweringContext,
    base: int,
    index: int,
    dest: Place,
) -> void throws MirInternalError {
    let base_ty = expr_ty(ctx, base);
    let base_op = lower_to_operand(ctx, base);
    let base_local = operand_to_local(ctx, base_op, base_ty);

    let is_null = RvalueBinaryOp {
        op: BinOp.Eq,
        left: operand_copy_local(base_local),
        right: OperandConstant { value: ConstantNull {} },
    };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, is_null);

    let bb_access = ctx.builder.create_block();

    let chain_null: int? = if (ctx.chain_null_exits.length() > 0) {
        ctx.chain_null_exits[ctx.chain_null_exits.length() - 1]
    } else {
        null
    };
    if (chain_null != null) {
        ctx.builder.branch(operand_copy_local(test_local), chain_null, bb_access);

        ctx.builder.set_current_block(bb_access);
        lower_optional_index_access(ctx, base_local, base_ty, index, dest, chain_null);
    } else {
        let bb_null = ctx.builder.create_block();
        let bb_join = ctx.builder.create_block();

        ctx.builder.branch(operand_copy_local(test_local), bb_null, bb_access);

        ctx.builder.set_current_block(bb_access);
        lower_optional_index_access(ctx, base_local, base_ty, index, place_clone(dest), bb_null);
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(bb_join);
        }

        ctx.builder.set_current_block(bb_null);
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
        ctx.builder.goto(bb_join);

        ctx.builder.set_current_block(bb_join);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_index_access @ d9be6853b
// Lower the access half of `base?.[index]`, with the base already known
// non-null. `?.[]` is the null-safe index operator, so a null SUBSCRIPT
// short-circuits the whole expression to null (via `bb_null`) rather than
// abort the VM. Only a nullable-typed index needs the extra check.
function lower_optional_index_access(
    ctx: LoweringContext,
    base_local: int,
    base_ty: root.types.RuntimeTy,
    index: int,
    dest: Place,
    bb_null: int,
) -> void throws MirInternalError {
    let base_op = operand_copy_local(base_local);
    let index_ty = expr_ty(ctx, index);
    // Lower the index once and reuse it for both the null check and the
    // access, so a side-effectful subscript isn't evaluated twice.
    let index_op = lower_to_operand(ctx, index);
    if (index_ty != root.types.runtime_ty_strip_null(index_ty)) {
        let is_null = RvalueBinaryOp {
            op: BinOp.Eq,
            left: operand_clone(index_op),
            right: OperandConstant { value: ConstantNull {} },
        };
        let test_local = ctx.builder.declare_local(root.types.TyBool {});
        ctx.builder.assign(PlaceLocal { value: test_local }, is_null);
        let bb_real = ctx.builder.create_block();
        ctx.builder.branch(operand_copy_local(test_local), bb_null, bb_real);
        ctx.builder.set_current_block(bb_real);
    }
    emit_index_access(ctx, base_op, base_ty, index_op, index_ty, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_call @ d9be6853b
// Lower `func?.(args)`: null-check the callee, then call or produce null.
function lower_optional_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    let callee_op = lower_to_operand(ctx, callee);

    let is_null = RvalueBinaryOp {
        op: BinOp.Eq,
        left: callee_op,
        right: OperandConstant { value: ConstantNull {} },
    };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, is_null);

    let bb_call = ctx.builder.create_block();

    let chain_null: int? = if (ctx.chain_null_exits.length() > 0) {
        ctx.chain_null_exits[ctx.chain_null_exits.length() - 1]
    } else {
        null
    };
    if (chain_null != null) {
        ctx.builder.branch(operand_copy_local(test_local), chain_null, bb_call);

        ctx.builder.set_current_block(bb_call);
        lower_call(ctx, expr_id, callee, args, dest);
    } else {
        let bb_null = ctx.builder.create_block();
        let bb_join = ctx.builder.create_block();

        ctx.builder.branch(operand_copy_local(test_local), bb_null, bb_call);

        ctx.builder.set_current_block(bb_call);
        lower_call(ctx, expr_id, callee, args, place_clone(dest));
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(bb_join);
        }

        ctx.builder.set_current_block(bb_null);
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
        ctx.builder.goto(bb_join);

        ctx.builder.set_current_block(bb_join);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_unary @ d9be6853b
function lower_unary(
    ctx: LoweringContext,
    expr_id: int,
    op: root.ast.UnaryOp,
    expr: int,
    dest: Place,
) -> void throws MirInternalError {
    // TIR may already have folded this expression to a literal constant.
    if (ctx.opt == OptLevel.Two) {
        match (expr_ty(ctx, expr_id)) {
            let lit: root.types.TyLiteral => {
                let constant = lower_literal(lit.value);
                ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: constant } });
                return;
            },
            _ => {},
        }
    }
    // Negation of a non-primitive operand (a user type, or a union /
    // existential / type variable involving one) dispatches through
    // `baml.ops.Negate`, resolved at runtime from the operand's concrete
    // type.
    if (op == root.ast.UnaryOp.Neg && !negate_uses_primitive_opcode(ctx, expr)) {
        lower_negate_via_driver(ctx, expr_id, expr, dest);
        return;
    }
    let operand = lower_to_operand(ctx, expr);
    let mir_op = match (op) {
        root.ast.UnaryOp.Not => UnaryOp.Not,
        root.ast.UnaryOp.Neg => UnaryOp.Neg,
    };
    ctx.builder.assign(dest, RvalueUnaryOp { op: mir_op, operand: operand });
}
