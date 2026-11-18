// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Not ported (package K4). What impls.rs, method_resolution.rs and
// callable.rs reach of it:
// - `infer_body` and its result, stubbed: `callable_throws` does not call it
//   yet (callable.baml).
// - Four leaves on the declaration path (`impl_facts` reaches
//   `ty_mentions_param`; impl selection `literal_base`), ported here with
//   their bodies so the declaration gate keeps running. K4 moves them to
//   infer.baml.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult @ d9be6853b
// One body's inference result. Not ported: every field but `throws`.
class InferenceResult {
    // The owner's effect: the declared clause when written, else the
    // canonical union of the body's throw sites and callee throws.
    throws_: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_body @ d9be6853b
// Infers one body owner (a function, a top-level `let`, or a function's
// parameter defaults).
function infer_body(db: root.hir.Db, owner: root.hir.BodyOwnerId) -> InferenceResult throws never {
    baml.sys.panic("infer_body: not ported")
}

// port: baml_compiler2_hir_ty/src/infer.rs::PROJECTION_FINALIZE_FUEL @ d9be6853b
// Reduction budget for the finalize-time projection pass: bounds a reduction
// chain.
const PROJECTION_FINALIZE_FUEL: int = 32;

// port: baml_compiler2_hir_ty/src/infer.rs::ty_mentions_param @ d9be6853b
// Whether `param` occurs anywhere in `ty`. Restructured: takes the pool; the
// `walk` with its `&mut bool` is a recursive `some`.
function ty_mentions_param(
    pool: root.types.InferPool,
    ty: int,
    param: root.types.ParamTy,
) -> bool throws never {
    match (pool.kinds[ty]) {
        let var: root.types.TyTypeVar if var.param == param => true,
        let kind: root.types.InferTy => {
            root.types.children_infer_ty(kind).some((child) -> {
                ty_mentions_param(pool, child, param)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::literal_base @ d9be6853b
// A literal's base primitive.
function literal_base(literal: root.base.Literal) -> root.types.InferTy throws never {
    match (literal) {
        root.base.LiteralInt => root.types.TyInt {},
        root.base.LiteralBigint => root.types.TyBigint {},
        root.base.LiteralFloat => root.types.TyFloat {},
        root.base.LiteralString => root.types.TyString {},
        root.base.LiteralBool => root.types.TyBool {},
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::union_of_tys @ d9be6853b
// The canonical union of `members` when they are all closed; else the
// structural union (`syntactic_union`).
function union_of_tys(facts: Facts, members: int[]) -> int throws never {
    let pool = facts.db.ty_memo.pool;
    if (
        members.some((member) -> {
            pool.has_infer(member)
        })
    ) {
        return syntactic_union(pool, members);
    }
    root.types
        .canonical_union_interned(
            pool,
            members.map((member) -> {
                root.types.ClosedTy { ty: member }
            }),
            facts,
        )
        .ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union @ d9be6853b
// The structural third of union canonicalization, safe on var-carrying
// members: flatten nested unions, drop `never`, dedup identical members,
// collapse the empty union to `never` and the singleton to its member.
// Restructured: takes the pool; the nested `push` is
// `syntactic_union_push`.
function syntactic_union(pool: root.types.InferPool, members: int[]) -> int throws never {
    let flat: int[] = [];
    for (let member in members) {
        syntactic_union_push(pool, flat, member);
    }
    match (flat.length()) {
        0 => pool.add(root.types.TyNever {}),
        1 => flat[0],
        _ => pool.add(root.types.InferTyUnion { members: flat }),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union::push @ d9be6853b
function syntactic_union_push(
    pool: root.types.InferPool,
    flat: int[],
    ty: int,
) -> void throws never {
    match (pool.kinds[ty]) {
        let u: root.types.InferTyUnion => {
            for (let member in u.members) {
                syntactic_union_push(pool, flat, member);
            }
        },
        root.types.TyNever => {},
        _ => {
            if (!flat.includes(ty)) {
                flat.push(ty);
            }
        },
    }
}
