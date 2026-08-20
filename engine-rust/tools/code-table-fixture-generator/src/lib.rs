mod bundle;
mod error;
mod generator;
mod json;
mod manifest;
mod sha256;
mod table;

pub use bundle::{build_bundle, verify_bundle, BundleBuild, BundleMetadata, TableBinary};
pub use error::{Diagnostic, FixtureError};
pub use generator::{generate_fixture, GenerationReport, CATEGORY_SPECS, GUIDE_ENTRY_COUNT};
pub use manifest::{CategoryManifest, FixtureManifest, GuideManifest, MANIFEST_FORMAT_VERSION};
pub use sha256::{sha256, sha256_hex};
pub use table::{validate_table_bytes, ValidatedTable};

pub const GENERATOR_VERSION: u32 = 1;
pub const DEFAULT_BUNDLE_NAME: &str = "code-table-fixture-synthetic.bundle";
