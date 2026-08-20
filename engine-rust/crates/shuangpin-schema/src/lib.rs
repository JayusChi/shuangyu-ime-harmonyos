//! Shuangpin schema model, loading, and validation for the Rust input engine.
//!
//! Stage 4 keeps scheme rules in data files and exposes a validated runtime
//! index to the parser. The crate is platform independent and has no HarmonyOS
//! dependency.

pub mod error;
mod json;
pub mod loader;
pub mod model;
pub mod validator;

pub use error::SchemaError;
pub use loader::{load_builtin_schema, load_schema_from_str};
pub use model::{
    FinalMapping, KeyMapping, RuntimeSchema, RuntimeSyllable, ShuangpinSchema, SpecialSyllableRule,
    ZeroInitialRule,
};
pub use validator::validate_schema;
