// port: baml_compiler2_hir_ty/src/infer/frames.rs @ d9be6853b
//
// The control frames of one inference run: the body owner's, and one for
// each lambda body, `defer` body and tagged-template flatten block the walk
// is inside. A frame owns the state a construct's body must not share with
// the code around it (whether the current point has diverged, and which
// loops are open), so entering one starts that state fresh and leaving one
// resumes the enclosing frame's, by construction rather than by a
// save/restore pair at each site.
//
// This file holds the type declarations; the `InferenceContext` methods
// are stubbed in `infer_stubs_u1.baml` (namespace `hir_ty.infer`) until
// ported. Interned types are `int`s, `FileScopeId` is an `int`.

// port: baml_compiler2_hir_ty/src/infer/frames.rs::ControlFrame @ d9be6853b
// One frame of control state; see the file header.
class ControlFrame {
    kind: FrameKind,
    // Whether execution can proceed past the current point of the frame.
    diverges: root.hir_ty.Diverges,
    // The loops open in the frame, innermost last. A `break` or `continue`
    // binds to the last one; with none open there is nothing it can leave
    // (see `loop_control_escape`).
    loops: LoopFrame[],

    // port: baml_compiler2_hir_ty/src/infer/frames.rs::ControlFrame::owner @ d9be6853b
    // The bottom frame: the body owner's, with its declared return type as
    // the expectation every `return` written directly in the body meets,
    // keying its expressions under the owner's scope.
    function owner(return_ty: int?, scope: int?) -> ControlFrame throws never {
        ControlFrame.open(
            FrameKindCallable {
                returns: ReturnFrame { expected: return_ty, candidates: [], scoped_bindings_floor: 0 },
                scope: scope,
            },
        )
    }

    // port: baml_compiler2_hir_ty/src/infer/frames.rs::ControlFrame::open @ d9be6853b
    function open(kind: FrameKind) -> ControlFrame throws never {
        ControlFrame { kind: kind, diverges: root.hir_ty.Diverges.Maybe, loops: [] }
    }
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::FrameKind @ d9be6853b
// What opened a frame.
type FrameKind = FrameKindCallable | FrameKindDefer | FrameKindTemplate;

// The body owner (the bottom frame) or a lambda body: what a `return`
// leaves. `scope` is the metadata scope the frame's expressions key under:
// the owner's for the bottom frame, and for a lambda the one the semantic
// index registered for it, since it keys a lambda body's expressions under
// the lambda's own scope even though they share the owner's arena. A frame
// without one keys under the enclosing frame's.
class FrameKindCallable {
    returns: ReturnFrame,
    scope: int?,
}

// A `defer` body (BEP-042). It runs at scope exit, so a `return`, or a
// `break`/`continue` that binds to no loop opened inside it, would escape
// it and is rejected.
class FrameKindDefer {
}

// A tagged template's flatten block, with the tag's body-lambda parameters
// (`prompt`'s `role`/`ctx`), which are name-visible inside it and shadow
// package items like locals. The semantic index cannot register them as
// bindings (the tag is a cross-file item; resolving it during the index
// walk would cycle), so path resolution consults the frame instead. The
// block is a deferred closure, so its divergence and loops are its own (a
// `break` inside it binds to a loop inside it only, and a `return` is
// rejected), but it keys its expressions under the enclosing scope.
class FrameKindTemplate {
    params: map<string, int>,
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::ReturnFrame @ d9be6853b
// The return context of a callable frame. Rust's derived `Default` is
// `ReturnFrame { expected: null, candidates: [], scoped_bindings_floor: 0 }`.
class ReturnFrame {
    expected: int?,
    candidates: Returned[],
    // Depth of the scoped-binding stack when the frame opened. A binding at
    // or past it belongs to this frame and closes before the frame's value
    // is published, so a `return` typed by one is an escape.
    scoped_bindings_floor: int,
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::LoopControlEscape @ d9be6853b
// Why a `break`/`continue` written at some point has no loop to take it:
// the innermost frame has no loop open, so the statement would leave the
// frame's construct instead.
type LoopControlEscape = LoopControlEscapeDefer | LoopControlEscapeOutsideLoop;

// A `defer` body (BEP-042) inside a loop.
class LoopControlEscapeDefer {
}

// No loop at all, or a loop that cannot be left from inside the frame's
// construct (a lambda body, a template interpolation).
class LoopControlEscapeOutsideLoop {
    value: root.hir_ty.LoopControlBarrier,
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::ReturnEscape @ d9be6853b
// Why a `return` written at some point is rejected: it would leave a
// construct that is not a function body.
type ReturnEscape = ReturnEscapeDefer | ReturnEscapeOutside;

// A `defer` body (BEP-042).
class ReturnEscapeDefer {
}

// An expression context (`ReturnContext`).
class ReturnEscapeOutside {
    value: root.hir_ty.ReturnContext,
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::Returned @ d9be6853b
// A value a frame returns, with the implicit units it carries when the
// frame expects no type: they are judged against the frame's other values
// when it closes (`join_units`).
class Returned {
    ty: int,
    units: root.hir_ty.UnitSite[],
}
