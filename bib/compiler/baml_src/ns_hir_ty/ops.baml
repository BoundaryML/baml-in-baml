// port: baml_compiler2_hir_ty/src/ops.rs @ d9be6853b
//
// Operator dispatch through interfaces: `a + b` is
// `Implements(lhs, baml.ops.Add<rhs>)` with the impl's `Output` as the
// result, a thin facade over the impl registry (impls.baml).
//
// Restructured: `operator_method` returns the function loc `int` (see
// callable.baml's header for the dropped External lane); the
// `&'static str` fields of `OperatorDispatch` are strings.

// port: baml_compiler2_hir_ty/src/ops.rs::OperatorDispatch @ d9be6853b
// One operator's dispatch contract: the `baml.ops` interface it desugars to
// and the interface method the dispatch invokes.
class OperatorDispatch {
    // Short interface name under `baml.ops` (`Add`, `Compare`, `Index`).
    interface_: string,
    // The interface method the operator dispatches to (`add`, `lt`, `index`).
    method: string,
}

// port: baml_compiler2_hir_ty/src/ops.rs::binary_operator @ d9be6853b
// The dispatch contract of a binary operator, or null for the structural
// operators (`&&`, `||`, `??`). Each comparison names its own method.
function binary_operator(op: root.ast.BinaryOp) -> OperatorDispatch? throws never {
    match (op) {
        root.ast.BinaryOp.Add => OperatorDispatch { interface_: "Add", method: "add" },
        root.ast.BinaryOp.Sub => OperatorDispatch { interface_: "Subtract", method: "sub" },
        root.ast.BinaryOp.Mul => OperatorDispatch { interface_: "Multiply", method: "mul" },
        root.ast.BinaryOp.Div => OperatorDispatch { interface_: "Divide", method: "div" },
        root.ast.BinaryOp.Mod => OperatorDispatch { interface_: "Remainder", method: "rem" },
        root.ast.BinaryOp.BitAnd => OperatorDispatch { interface_: "BitAnd", method: "bit_and" },
        root.ast.BinaryOp.BitOr => OperatorDispatch { interface_: "BitOr", method: "bit_or" },
        root.ast.BinaryOp.BitXor => OperatorDispatch { interface_: "BitXor", method: "bit_xor" },
        root.ast.BinaryOp.Shl => OperatorDispatch { interface_: "ShiftLeft", method: "shl" },
        root.ast.BinaryOp.Shr => OperatorDispatch { interface_: "ShiftRight", method: "shr" },
        root.ast.BinaryOp.Lt => OperatorDispatch { interface_: "Compare", method: "lt" },
        root.ast.BinaryOp.Le => OperatorDispatch { interface_: "Compare", method: "le" },
        root.ast.BinaryOp.Gt => OperatorDispatch { interface_: "Compare", method: "gt" },
        root.ast.BinaryOp.Ge => OperatorDispatch { interface_: "Compare", method: "ge" },
        root.ast.BinaryOp.Eq => OperatorDispatch { interface_: "Equals", method: "eq" },
        root.ast.BinaryOp.Ne => OperatorDispatch { interface_: "Equals", method: "neq" },
        root.ast.BinaryOp.And | root.ast.BinaryOp.Or | root.ast.BinaryOp.NullCoalesce => null,
    }
}

// port: baml_compiler2_hir_ty/src/ops.rs::assign_operator @ d9be6853b
// The dispatch contract of a compound assignment (`+=` steps through the
// same interface as `+`).
function assign_operator(op: root.ast.AssignOp) -> OperatorDispatch throws never {
    match (op) {
        root.ast.AssignOp.Add => OperatorDispatch { interface_: "Add", method: "add" },
        root.ast.AssignOp.Sub => OperatorDispatch { interface_: "Subtract", method: "sub" },
        root.ast.AssignOp.Mul => OperatorDispatch { interface_: "Multiply", method: "mul" },
        root.ast.AssignOp.Div => OperatorDispatch { interface_: "Divide", method: "div" },
        root.ast.AssignOp.Mod => OperatorDispatch { interface_: "Remainder", method: "rem" },
        root.ast.AssignOp.BitAnd => OperatorDispatch { interface_: "BitAnd", method: "bit_and" },
        root.ast.AssignOp.BitOr => OperatorDispatch { interface_: "BitOr", method: "bit_or" },
        root.ast.AssignOp.BitXor => OperatorDispatch { interface_: "BitXor", method: "bit_xor" },
        root.ast.AssignOp.Shl => OperatorDispatch { interface_: "ShiftLeft", method: "shl" },
        root.ast.AssignOp.Shr => OperatorDispatch { interface_: "ShiftRight", method: "shr" },
    }
}

// port: baml_compiler2_hir_ty/src/ops.rs::unary_operator @ d9be6853b
// `-` dispatches `Negate.neg`; `!` is structural boolean algebra.
function unary_operator(op: root.ast.UnaryOp) -> OperatorDispatch? throws never {
    match (op) {
        root.ast.UnaryOp.Neg => OperatorDispatch { interface_: "Negate", method: "neg" },
        root.ast.UnaryOp.Not => null,
    }
}

// port: baml_compiler2_hir_ty/src/ops.rs::INDEX_DISPATCH @ d9be6853b
// `base[idx]` dispatches through `baml.ops.Index.index`.
const INDEX_DISPATCH: OperatorDispatch = OperatorDispatch { interface_: "Index", method: "index" };

// port: baml_compiler2_hir_ty/src/ops.rs::operator_output @ d9be6853b
// The `Output` of the unique impl matching `baml.ops.<interface_><rhs>` for
// `lhs`, or null when the operands do not support the operator. Operands
// must be resolved and literal-widened by the caller.
function operator_output(
    db: root.hir.Db,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int? throws never {
    let goal = operator_goal(db, interface_, rhs)
        ?? return null;
    let resolved = resolve_impl(db, lhs, goal)
        ?? return null;
    // Binding-else-default, so a defaulted `Output` resolves like any other
    // associated member.
    resolved_pin(db, resolved, lhs, "Output")
}

// port: baml_compiler2_hir_ty/src/ops.rs::operator_goal @ d9be6853b
// The impl goal an operator application poses; null when the `baml` package
// is not installed.
function operator_goal(
    db: root.hir.Db,
    interface_: string,
    rhs: int?,
) -> root.types.InferInterfaceConstraint? throws never {
    let baml = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return null;
    root.types.infer_interface_new(
        root.types.DeclName { pkg: baml, namespace: ["ops"], name: interface_ },
        if (rhs != null) {
            [rhs]
        } else {
            []
        },
        [],
    )
}

// port: baml_compiler2_hir_ty/src/ops.rs::operator_method @ d9be6853b
// The method declaration an operator application dispatches to, for the
// reader: the method the matching impl provides, else the `baml.ops`
// interface's own declaration. Operand literals widen here.
function operator_method(
    db: root.hir.Db,
    dispatch: OperatorDispatch,
    lhs: int,
    rhs: int?,
) -> int? throws never {
    let pool = db.ty_memo.pool;
    let widen = (ty: int) -> int {
        match (pool.kinds[ty]) {
            let literal: root.types.TyLiteral => pool.add(literal_base(literal.value)),
            _ => ty,
        }
    };
    let lhs_widened = widen(lhs);
    let rhs_widened = if (rhs != null) {
        widen(rhs)
    } else {
        null
    };
    let goal = operator_goal(db, dispatch.interface_, rhs_widened);
    if (goal != null) {
        let provided = resolve_impl(db, lhs_widened, goal)?.provided_method(db, dispatch.method);
        if (provided != null) {
            return provided;
        }
    }
    // The interface's own declaration: default body or required signature.
    let package = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return null;
    let iface = match (root.hir.package_items(db, package).lookup_type(["ops"], dispatch.interface_)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => {
            return null;
        },
    };
    root.hir.interface_data(db, iface).methods.find((method) -> {
        root.hir.function_data(db, method).name == dispatch.method
    })
}
