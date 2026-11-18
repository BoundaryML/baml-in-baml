// port: baml_type/src/names.rs @ d9be6853b (the parts the frontend uses)

// port: baml_type/src/names.rs::QualifiedTypeName @ d9be6853b
// A declaration's package (by key `P`), namespace path and short name.
class QualifiedTypeName<P> {
    pkg: P,
    namespace: string[],
    name: string,
}

// port: baml_type/src/names.rs::DeclName @ d9be6853b
// The compiler's qualified name: the declaring package is its root id.
type DeclName = QualifiedTypeName<int>;

// port: baml_type/src/names.rs::PathName @ d9be6853b
// A qualified name whose declaring package is an `EdgePath` from its owner.
type PathName = QualifiedTypeName<EdgePath>;
