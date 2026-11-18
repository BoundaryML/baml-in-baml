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

    function new() -> MirMemos throws never {
        MirMemos {
            resolved_aliases_for_package: root.hir.TrackedMemo.new("resolved_aliases_for_package"),
            package_lowering_data: root.hir.TrackedMemo.new("package_lowering_data"),
            lower_function_zero: root.hir.TrackedMemo.new("lower_function@Zero"),
            lower_function_one: root.hir.TrackedMemo.new("lower_function@One"),
            lower_function_two: root.hir.TrackedMemo.new("lower_function@Two"),
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
}
