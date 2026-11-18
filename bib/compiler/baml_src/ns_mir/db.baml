// port: baml_compiler2_mir's `#[salsa::tracked]` queries @ d9be6853b
//
// One `TrackedMemo` per MIR query (ns_hir/tracked.baml), reached as
// `db.mir_memo.<query>`. A query keyed by a loc or a root uses it as the
// key. Salsa keys several MIR queries by a tuple with the `OptLevel`
// (`lower_function`, the three escape queries): those get one memo per
// level, picked by the `<query>_memo(opt)` method below. `component_summaries`
// is keyed by `(root, component)` as well, interned to an `int` by
// `component_keys`.
//
// Cycle recovery as in Rust: `escape_summary` has `cycle_result` (its
// fallback is `null`: read it with `get_fallback`); the rest panic on a
// cycle (`get`).

// The `(root, component)` keys of `component_summaries`, interned to `int`s.
class ComponentKeys {
    index: map<int, map<int, int>>,
    count: int,

    function new() -> ComponentKeys throws never {
        ComponentKeys { index: {}, count: 0 }
    }

    function intern(self, root_id: int, component: int) -> int throws never {
        let by_component = self.index.get_or_insert(root_id, {});
        let existing = by_component.get(component);
        if (existing != null) {
            return existing;
        }
        let key = self.count;
        self.count += 1;
        by_component[component] = key;
        key
    }
}

class MirMemos {
    // lower.rs::resolved_aliases_for_package (key: root id)
    resolved_aliases_for_package: root.hir.TrackedMemo<PackageAliases>,
    // lower.rs::package_lowering_data (key: root id)
    package_lowering_data: root.hir.TrackedMemo<PackageLoweringData>,
    // lower.rs::lower_function (key: function loc), one per OptLevel. The
    // value is Rust's `Result<MirFunction, MirInternalError>`.
    lower_function_zero: root.hir.TrackedMemo<MirFunction | MirInternalError>,
    lower_function_one: root.hir.TrackedMemo<MirFunction | MirInternalError>,
    lower_function_two: root.hir.TrackedMemo<MirFunction | MirInternalError>,
    // escape.rs::escape_summary (key: function loc; `cycle_result`), one per
    // OptLevel.
    escape_summary_zero: root.hir.TrackedMemo<Summary?>,
    escape_summary_one: root.hir.TrackedMemo<Summary?>,
    escape_summary_two: root.hir.TrackedMemo<Summary?>,
    // escape.rs::component_summaries (key: `component_keys`), one per
    // OptLevel. Rust's `FxHashMap<FunctionLoc, Summary>`.
    component_summaries_zero: root.hir.TrackedMemo<map<int, Summary>>,
    component_summaries_one: root.hir.TrackedMemo<map<int, Summary>>,
    component_summaries_two: root.hir.TrackedMemo<map<int, Summary>>,
    component_keys: ComponentKeys,
    // escape.rs::recursive_functions (key: root id), one per OptLevel.
    // Rust's `FxHashMap<FunctionLoc, usize>`.
    recursive_functions_zero: root.hir.TrackedMemo<map<int, int>>,
    recursive_functions_one: root.hir.TrackedMemo<map<int, int>>,
    recursive_functions_two: root.hir.TrackedMemo<map<int, int>>,

    function new() -> MirMemos throws never {
        MirMemos {
            resolved_aliases_for_package: root.hir.TrackedMemo.new("resolved_aliases_for_package"),
            package_lowering_data: root.hir.TrackedMemo.new("package_lowering_data"),
            lower_function_zero: root.hir.TrackedMemo.new("lower_function@Zero"),
            lower_function_one: root.hir.TrackedMemo.new("lower_function@One"),
            lower_function_two: root.hir.TrackedMemo.new("lower_function@Two"),
            escape_summary_zero: root.hir.TrackedMemo.new("escape_summary@Zero"),
            escape_summary_one: root.hir.TrackedMemo.new("escape_summary@One"),
            escape_summary_two: root.hir.TrackedMemo.new("escape_summary@Two"),
            component_summaries_zero: root.hir.TrackedMemo.new("component_summaries@Zero"),
            component_summaries_one: root.hir.TrackedMemo.new("component_summaries@One"),
            component_summaries_two: root.hir.TrackedMemo.new("component_summaries@Two"),
            component_keys: ComponentKeys.new(),
            recursive_functions_zero: root.hir.TrackedMemo.new("recursive_functions@Zero"),
            recursive_functions_one: root.hir.TrackedMemo.new("recursive_functions@One"),
            recursive_functions_two: root.hir.TrackedMemo.new("recursive_functions@Two"),
        }
    }

    // The `lower_function` memo of `opt`.
    function lower_function_memo(
        self,
        opt: OptLevel,
    ) -> root.hir.TrackedMemo<MirFunction | MirInternalError> throws never {
        match (opt) {
            OptLevel.Zero => self.lower_function_zero,
            OptLevel.One => self.lower_function_one,
            OptLevel.Two => self.lower_function_two,
        }
    }

    // The `escape_summary` memo of `opt`.
    function escape_summary_memo(
        self,
        opt: OptLevel,
    ) -> root.hir.TrackedMemo<Summary?> throws never {
        match (opt) {
            OptLevel.Zero => self.escape_summary_zero,
            OptLevel.One => self.escape_summary_one,
            OptLevel.Two => self.escape_summary_two,
        }
    }

    // The `component_summaries` memo of `opt`.
    function component_summaries_memo(
        self,
        opt: OptLevel,
    ) -> root.hir.TrackedMemo<map<int, Summary>> throws never {
        match (opt) {
            OptLevel.Zero => self.component_summaries_zero,
            OptLevel.One => self.component_summaries_one,
            OptLevel.Two => self.component_summaries_two,
        }
    }

    // The `recursive_functions` memo of `opt`.
    function recursive_functions_memo(
        self,
        opt: OptLevel,
    ) -> root.hir.TrackedMemo<map<int, int>> throws never {
        match (opt) {
            OptLevel.Zero => self.recursive_functions_zero,
            OptLevel.One => self.recursive_functions_one,
            OptLevel.Two => self.recursive_functions_two,
        }
    }
}
