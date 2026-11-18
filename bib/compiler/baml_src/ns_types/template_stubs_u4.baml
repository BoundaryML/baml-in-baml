// Items of `baml_type` that MIR unit 4 needs and that are not ported yet:
// the `typetag` constants and `RuntimeTy::strip_null`. Deleted at merge,
// when they move to their homes (`typetag.baml`, `runtime_ty.baml`).
//
// Restructured: `baml_type::typetag::INT` is `TYPETAG_INT` (and so for the
// others): a nested `typetag` namespace would need a new folder. The
// constants carry Rust's values, since a constant cannot panic.

// port: baml_type/src/typetag.rs::INT @ d9be6853b
const TYPETAG_INT = 0;

// port: baml_type/src/typetag.rs::STRING @ d9be6853b
const TYPETAG_STRING = 1;

// port: baml_type/src/typetag.rs::BOOL @ d9be6853b
const TYPETAG_BOOL = 2;

// port: baml_type/src/typetag.rs::NULL @ d9be6853b
const TYPETAG_NULL = 3;

// port: baml_type/src/typetag.rs::FLOAT @ d9be6853b
const TYPETAG_FLOAT = 4;

// port: baml_type/src/typetag.rs::ENUM @ d9be6853b
const TYPETAG_ENUM = 5;

// port: baml_type/src/typetag.rs::LIST @ d9be6853b
const TYPETAG_LIST = 6;

// port: baml_type/src/typetag.rs::MAP @ d9be6853b
const TYPETAG_MAP = 7;

// port: baml_type/src/typetag.rs::FUNCTION @ d9be6853b
const TYPETAG_FUNCTION = 8;

// port: baml_type/src/typetag.rs::FUTURE @ d9be6853b
const TYPETAG_FUTURE = 9;

// port: baml_type/src/typetag.rs::TYPE @ d9be6853b
const TYPETAG_TYPE = 10;

// port: baml_type/src/typetag.rs::UINT8ARRAY @ d9be6853b
const TYPETAG_UINT8ARRAY = 12;

// port: baml_type/src/typetag.rs::BIGINT @ d9be6853b
const TYPETAG_BIGINT = 13;

// port: baml_type/src/typetag.rs::TUPLE @ d9be6853b
const TYPETAG_TUPLE = 14;

// port: baml_type/src/typetag.rs::CLASS_BASE @ d9be6853b
const TYPETAG_CLASS_BASE = 100;

// port: baml_type/src/typetag.rs::PANIC @ d9be6853b
const TYPETAG_PANIC = -2;

// port: baml_type/src/lib.rs::Ty::strip_null @ d9be6853b
// `strip_null` (lib.baml) at the RuntimeTy member of the family.
function strip_null_runtime_ty(ty: RuntimeTy) -> RuntimeTy throws never {
    baml.sys.panic("strip_null_runtime_ty: not ported")
}
