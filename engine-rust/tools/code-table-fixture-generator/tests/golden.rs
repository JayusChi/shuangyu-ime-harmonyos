use std::fs;
use std::path::PathBuf;

use code_table_fixture_generator::{sha256_hex, validate_table_bytes, FixtureManifest};

fn fixture_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/code-table/golden")
}

#[test]
fn golden_fixture_is_readable_auditable_and_isolated() {
    let root = fixture_root();
    let manifest_bytes = fs::read(root.join("manifest.json")).unwrap();
    let manifest = FixtureManifest::from_bytes(&manifest_bytes, "golden/manifest.json").unwrap();
    assert_eq!(
        manifest
            .categories
            .iter()
            .map(|value| value.id.as_str())
            .collect::<Vec<_>>(),
        ["core", "phrases"]
    );
    for category in &manifest.categories {
        let bytes = fs::read(root.join(&category.source_path)).unwrap();
        assert_eq!(sha256_hex(&bytes), category.source_sha256);
        let table = validate_table_bytes(&bytes, &category.source_path).unwrap();
        assert_eq!(table.entry_count, category.expected_entry_count);
        assert!(table
            .rows
            .iter()
            .enumerate()
            .all(|(index, row)| row.source_order as usize == index));
    }
    let guide = fs::read(root.join(&manifest.guide_table.source_path)).unwrap();
    assert_eq!(sha256_hex(&guide), manifest.guide_table.source_sha256);
    assert_eq!(
        validate_table_bytes(&guide, "guide.txt")
            .unwrap()
            .entry_count,
        4
    );
    assert!(manifest
        .categories
        .iter()
        .all(|category| category.source_path != manifest.guide_table.source_path));
}
