// port: baml_type/src/call_layout.rs @ d9be6853b
//
// The value slots of a call, independent of the values' types and of who
// executes the call. A call site pushes one value per slot of the signature
// it was checked against; a callee reads one value per slot of its own
// declaration. The two agree on the required slots and on the names of
// optional slots, but an implementation may declare optionals the caller's
// signature never mentions. Dispatch reconciles them with `map_to`.
//
// Not ported: `len` / `is_empty` (read the field).

// port: baml_type/src/call_layout.rs::CallLayout @ d9be6853b
// One entry per value slot: null is a required positional slot, a name an
// optional named slot. An omitted optional still occupies its slot (as the
// omission sentinel), so the length is exactly the number of values pushed.
class CallLayout {
    value: (string | null)[],

    // port: baml_type/src/call_layout.rs::CallLayout::positional @ d9be6853b
    // `count` required slots and nothing else.
    function positional(count: int) -> CallLayout throws never {
        CallLayout { value: baml.Array.filled(count, null) }
    }

    // port: baml_type/src/call_layout.rs::CallLayout::from_modes @ d9be6853b
    // The layout a declared parameter list reads. Optional parameters are
    // always named in a declaration.
    function from_modes(params: (string?, FunctionParamMode)[]) -> CallLayout throws never {
        CallLayout {
            value: params.map((param) -> {
                let (let name, let mode) = param;
                match (mode) {
                    FunctionParamMode.Required => null,
                    FunctionParamMode.Optional => {
                        name ?? baml.sys.panic("optional parameter has a name")
                    },
                }
            }),
        }
    }

    // port: baml_type/src/call_layout.rs::CallLayout::required_count @ d9be6853b
    function required_count(self) -> int throws never {
        self.value
            .filter((slot) -> {
                slot == null
            })
            .length()
    }

    // port: baml_type/src/call_layout.rs::CallLayout::map_to @ d9be6853b
    // For each of `target`'s slots, the index of the caller slot that fills
    // it, or null for an optional the caller never mentioned (the callee gets
    // its omission sentinel there). Required slots pair up in order, optional
    // slots by name. The whole map is validated before any value moves, so a
    // mismatch leaves the caller's values intact. `throws` spells out
    // LayoutMismatch: the toolchain reports the alias there as extraneous
    // (E0097).
    function map_to(
        self,
        target: CallLayout,
    ) -> (int | null)[] throws LayoutMismatchMissingRequired | LayoutMismatchExtraRequired | LayoutMismatchUnknownOptional {
        let got = self.required_count();
        let expected = target.required_count();
        if (got < expected) {
            throw LayoutMismatchMissingRequired { expected: expected, got: got }
        }
        if (got > expected) {
            throw LayoutMismatchExtraRequired { expected: expected, got: got }
        }
        let unknown = self.value.find((slot) -> {
            slot != null && !target.value.includes(slot)
        });
        if (unknown != null) {
            throw LayoutMismatchUnknownOptional { value: unknown }
        }
        let required = baml.Array
            .generate(self.value.length(), (index) -> {
                index
            })
            .filter((index) -> {
                self.value[index] == null
            });
        target.value.map((slot) -> {
            if (slot == null) {
                required.shift()
            } else {
                self.value.index_of(slot)
            }
        })
    }
}

// port: baml_type/src/call_layout.rs::LayoutMismatch @ d9be6853b
// Why a caller's slots cannot be laid over a target's. `Display` is each
// class's `to_string`.
type LayoutMismatch = LayoutMismatchMissingRequired
    | LayoutMismatchExtraRequired
    | LayoutMismatchUnknownOptional;

// The target declares more required slots than the caller pushed.
class LayoutMismatchMissingRequired {
    expected: int,
    got: int,

    implements baml.ToString {
        function to_string(self) -> string {
            `expected ${self.expected} required arguments, got ${self.got}`
        }
    }
}

// The caller pushed more required slots than the target declares.
class LayoutMismatchExtraRequired {
    expected: int,
    got: int,

    implements baml.ToString {
        function to_string(self) -> string {
            `expected ${self.expected} required arguments, got ${self.got}`
        }
    }
}

// The caller supplied an optional the target does not declare.
class LayoutMismatchUnknownOptional {
    value: string,

    implements baml.ToString {
        function to_string(self) -> string {
            `call supplies optional parameter \`${self.value}\` the callee does not declare`
        }
    }
}
