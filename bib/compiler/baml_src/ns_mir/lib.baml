// port: baml_compiler2_mir/src/lib.rs @ d9be6853b
//
// The MIR crate root: namespace `mir`, one file per module (`builder`,
// `escape`, `inference_provider`, `ir`, `iteration`, `lower`, `memory`,
// `optimize` with `optimize/effects` and `optimize/values`, `pretty`,
// `reducible`). Rust's `pub use` re-exports need no counterpart: every item
// of the namespace is visible as `root.mir.<name>`.
//
// Restructured: the `Db` trait (`baml_compiler2_hir::Db` plus nothing) is
// `root.hir.Db`, whose `mir_memo` field holds the MIR queries' caches
// (`db.baml`).
