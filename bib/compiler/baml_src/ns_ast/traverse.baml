// port: baml_compiler2_ast/src/traverse.rs @ d9be6853b
//
// Structural traversal of an `ExprBody` arena. The arena is flat, but its
// nodes form a tree rooted at `ExprBody.root_expr`, and iterating the two is
// not the same: a lambda's body hangs off its `ExprLambda` node, so a flat
// scan sees a `throw` inside a lambda as the enclosing function's. The
// helpers enumerate a node's direct children and leave descent (and whether
// to enter a lambda body) to the caller.
//
// deviation: `ExprBody::expr_children`, `stmt_children` and
// `reachable_excluding_lambdas` are methods of `ExprBody` in `ast.baml`
// (BAML has no impl blocks outside the class).

// port: traverse.rs::BodyNode. A direct child of an expression or statement.
type BodyNode = BodyNodeExpr | BodyNodeStmt;

class BodyNodeExpr {
    value: int,
}

class BodyNodeStmt {
    value: int,
}

// port: baml_compiler2_ast/src/traverse.rs::template_segment_children @ d9be6853b
function template_segment_children(segment: TemplateSegment, out: BodyNode[]) -> void throws never {
    let visit_all = (segments: TemplateSegment[]) -> void {
        for (let inner in segments) {
            template_segment_children(inner, out);
        }
    };
    match (segment) {
        TemplateSegmentText => {},
        let s: TemplateSegmentInterp => {
            out.push(BodyNodeExpr { value: s.value });
        },
        let s: TemplateSegmentEffect => {
            for (let stmt in s.stmts) {
                out.push(BodyNodeStmt { value: stmt });
            }
        },
        let s: TemplateSegmentFor => {
            out.push(BodyNodeExpr { value: s.collection });
            visit_all(s.body);
        },
        let s: TemplateSegmentCStyleFor => {
            out.push(BodyNodeStmt { value: s.init });
            out.push(BodyNodeExpr { value: s.cond });
            if let step: int = s.step {
                out.push(BodyNodeStmt { value: step });
            }
            visit_all(s.body);
        },
        let s: TemplateSegmentIf => {
            for (let branch in s.branches) {
                out.push(BodyNodeExpr { value: branch.condition });
                visit_all(branch.body);
            }
            visit_all(s.else_body ?? []);
        },
    }
}
