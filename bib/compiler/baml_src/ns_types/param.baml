// port: baml_type/src/param.rs @ d9be6853b
//
// Not ported: `ParamTy::new` (a class literal), the `index` / `name` /
// `as_str` accessors (read the fields), `Display` (the name),
// `RuntimeGenericLayout::params` (read the field) and `slot_index` (a `u32`
// conversion).

// port: baml_type/src/param.rs::SCOPED_PARAM_BIT @ d9be6853b
// The index bit that marks a block-scoped `let type T = ...` parameter.
// Declared generic parameters are De Bruijn positions in a frame and never
// reach it; a scoped parameter's identity is its binding statement's index in
// the body, and this bit keeps the two spaces disjoint.
const SCOPED_PARAM_BIT: int = 2147483648;

// port: baml_type/src/param.rs::ParamTy @ d9be6853b
// A generic type parameter in its flattened declaration environment: `index`
// is its slot within its owner's flattened generic frame, `name` is kept for
// diagnostics and display.
class ParamTy {
    index: int,
    name: string,

    // port: baml_type/src/param.rs::ParamTy::is_scoped @ d9be6853b
    // Whether this is a block-scoped `let type T = ...` parameter (its index
    // carries SCOPED_PARAM_BIT) rather than a declared generic.
    function is_scoped(self) -> bool throws never {
        (self.index & SCOPED_PARAM_BIT) != 0
    }

    // port: baml_type/src/param.rs::ParamTy::extend_frame @ d9be6853b
    // Appends one parameter per name to `frame`, numbered on from its end.
    function extend_frame(frame: ParamTy[], names: string[]) -> void throws never {
        let first_index = frame.length();
        let added = baml.Array.generate(names.length(), (offset) -> {
            ParamTy { index: first_index + offset, name: names[offset] }
        });
        root.base.extend(frame, added);
    }
}

// port: baml_type/src/param.rs::RuntimeGenericLayout @ d9be6853b
// The generic parameters that survive into one runtime call frame. TIR may
// carry compiler-only parameters for effect inference; runtime frames omit
// them and give dense slots to everything that remains.
class RuntimeGenericLayout {
    params: ParamTy[],

    // port: baml_type/src/param.rs::RuntimeGenericLayout::new @ d9be6853b
    // A synthetic effect parameter (`__effect_param_N`) is slot-less by ABI.
    // A block-scoped binding is told apart by its index bit, never by its
    // name, so a user's `type __effect_param_0 = ...` keeps its slot.
    function new(params: ParamTy[]) -> RuntimeGenericLayout throws never {
        RuntimeGenericLayout {
            params: params.filter((param) -> {
                param.is_scoped() || !is_synthetic_effect_param(param.name)
            }),
        }
    }

    // port: baml_type/src/param.rs::RuntimeGenericLayout::slot @ d9be6853b
    function slot(self, param: ParamTy) -> int? throws never {
        self.params.index_of(param)
    }

    // port: baml_type/src/param.rs::RuntimeGenericLayout::slots @ d9be6853b
    function slots(self) -> int[] throws never {
        baml.Array.generate(self.params.length(), (index) -> {
            index
        })
    }
}
