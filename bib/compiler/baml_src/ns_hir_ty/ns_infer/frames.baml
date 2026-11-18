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
// The `InferenceContext` methods are free functions taking `ctx` first.
// `control_frame_mut` and `return_frame_mut` are `control_frame` and
// `return_frame`: a frame is a reference. Interned types are `int`s,
// `FileScopeId` is an `int`.

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

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::control_frame @ d9be6853b
// The innermost frame. Restructured: also `control_frame_mut`, since a
// frame is a reference.
function control_frame(ctx: root.hir_ty.InferenceContext) -> ControlFrame throws never {
    ctx.frames[ctx.frames.length() - 1]
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::enter_frame @ d9be6853b
// Opens a frame, with nothing diverged and no loop open in it.
function enter_frame(ctx: root.hir_ty.InferenceContext, kind: FrameKind) -> void throws never {
    ctx.frames.push(ControlFrame.open(kind));
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::leave_frame @ d9be6853b
// Closes the innermost frame; the enclosing frame's state resumes.
function leave_frame(ctx: root.hir_ty.InferenceContext) -> void throws never {
    if (ctx.frames.length() <= 1) {
        baml.sys.panic("`leave_frame` pairs with `enter_frame`; the owner frame is never left");
    }
    ctx.frames.pop();
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::diverges @ d9be6853b
// Whether execution can proceed past the current point.
function diverges(ctx: root.hir_ty.InferenceContext) -> root.hir_ty.Diverges throws never {
    control_frame(ctx).diverges
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::set_diverges @ d9be6853b
function set_diverges(
    ctx: root.hir_ty.InferenceContext,
    diverges: root.hir_ty.Diverges,
) -> void throws never {
    control_frame(ctx).diverges = diverges;
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::current_scope @ d9be6853b
// The metadata scope expression lookups key under right now: the innermost
// callable frame's, down to the owner's.
function current_scope(ctx: root.hir_ty.InferenceContext) -> int? throws never {
    for (let i = ctx.frames.length() - 1; i >= 0; i -= 1) {
        match (ctx.frames[i].kind) {
            let callable: FrameKindCallable => {
                if (callable.scope != null) {
                    return callable.scope;
                }
            },
            FrameKindDefer | FrameKindTemplate => {},
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::return_frame @ d9be6853b
// The frame a `return` written here leaves: the innermost callable.
// Restructured: also `return_frame_mut`, since a frame is a reference.
function return_frame(ctx: root.hir_ty.InferenceContext) -> ReturnFrame throws never {
    for (let i = ctx.frames.length() - 1; i >= 0; i -= 1) {
        match (ctx.frames[i].kind) {
            let callable: FrameKindCallable => {
                return callable.returns;
            },
            FrameKindDefer | FrameKindTemplate => {},
        }
    }
    baml.sys.panic("the owner frame is a callable")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::return_escape @ d9be6853b
// What a `return` written here would leave other than a function body. The
// innermost frame decides: a `defer` body or template interpolation is left
// before any callable around it, a lambda's `return` is its own, and with
// no frame nested in the owner's the owner itself may be an expression (a
// global's initializer, a parameter default), whose value is its last
// expression.
function return_escape(ctx: root.hir_ty.InferenceContext) -> ReturnEscape? throws never {
    if (ctx.frames.length() > 1) {
        return match (control_frame(ctx).kind) {
            FrameKindCallable => null,
            FrameKindDefer => ReturnEscapeDefer {},
            FrameKindTemplate => {
                ReturnEscapeOutside { value: root.hir_ty.ReturnContextTemplateInterpolation {} }
            },
        };
    }
    match (ctx.owner) {
        root.hir.BodyOwnerIdFunction => null,
        root.hir.BodyOwnerIdParameterDefaults => {
            ReturnEscapeOutside { value: root.hir_ty.ReturnContextParameterDefault {} }
        },
        root.hir.BodyOwnerIdLet => {
            let name = root.hir_ty.global_initializer(ctx)
                ?? return null;
            ReturnEscapeOutside { value: root.hir_ty.ReturnContextGlobalInitializer { name: name } }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::loop_control_escape @ d9be6853b
// What a `break`/`continue` written here would escape, when no loop in the
// innermost frame can take it: with no loop open in any frame there is
// simply none, otherwise the innermost frame's construct is what stands
// between the statement and the loop around it.
function loop_control_escape(ctx: root.hir_ty.InferenceContext) -> LoopControlEscape? throws never {
    let frame = control_frame(ctx);
    if (frame.loops.length() > 0) {
        return null;
    }
    if (
        ctx.frames.every((frame) -> {
            frame.loops.length() == 0
        })
    ) {
        return LoopControlEscapeOutsideLoop { value: root.hir_ty.LoopControlBarrier.NoLoop };
    }
    match (frame.kind) {
        FrameKindDefer => LoopControlEscapeDefer {},
        FrameKindTemplate => {
            LoopControlEscapeOutsideLoop { value: root.hir_ty.LoopControlBarrier.Template }
        },
        // A loop is open in some outer frame, so this callable is a lambda,
        // not the owner.
        FrameKindCallable => {
            LoopControlEscapeOutsideLoop { value: root.hir_ty.LoopControlBarrier.Lambda }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::template_param_ty @ d9be6853b
// The type of a tagged-template body parameter in scope, innermost template
// winning.
function template_param_ty(ctx: root.hir_ty.InferenceContext, name: string) -> int? throws never {
    for (let i = ctx.frames.length() - 1; i >= 0; i -= 1) {
        match (ctx.frames[i].kind) {
            let template: FrameKindTemplate => {
                let ty = template.params.get(name);
                if (ty != null) {
                    return ty;
                }
            },
            FrameKindCallable | FrameKindDefer => {},
        }
    }
    null
}
