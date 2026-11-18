// Hand-written pieces the generated family (family.baml) refers to. The
// InferPool the interning functions take is in interned.baml.

// port: baml_type/src/lib.rs::Freshness @ d9be6853b
enum Freshness {
    Fresh,
    Regular,
}

// port: baml_type/src/lib.rs::FunctionParamMode @ d9be6853b
enum FunctionParamMode {
    Required,
    Optional,
}

// port: the `Not<Member>` errors of the conversion matrix, as one class.
// A narrowing met a variant the target member does not include.
class NarrowError {
    variant: string,
    into: string,
}
