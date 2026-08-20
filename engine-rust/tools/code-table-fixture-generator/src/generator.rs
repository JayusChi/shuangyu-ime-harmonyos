use std::fs;
use std::path::{Path, PathBuf};

use crate::error::FixtureError;
use crate::manifest::{CategoryManifest, FixtureManifest, GuideManifest, MANIFEST_FORMAT_VERSION};
use crate::sha256_hex;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CategorySpec {
    pub id: &'static str,
    pub display_name: &'static str,
    pub entry_count: usize,
    pub order: u32,
    pub default_enabled: bool,
    pub seed_label: &'static str,
    pub code_offset: usize,
}

pub const CATEGORY_SPECS: [CategorySpec; 5] = [
    CategorySpec {
        id: "core",
        display_name: "核心模拟",
        entry_count: 8_000,
        order: 10,
        default_enabled: true,
        seed_label: "核心",
        code_offset: 10_000,
    },
    CategorySpec {
        id: "phrases",
        display_name: "短语模拟",
        entry_count: 6_000,
        order: 20,
        default_enabled: true,
        seed_label: "短语",
        code_offset: 70_000,
    },
    CategorySpec {
        id: "extended",
        display_name: "扩展模拟",
        entry_count: 5_000,
        order: 30,
        default_enabled: true,
        seed_label: "扩展",
        code_offset: 130_000,
    },
    CategorySpec {
        id: "domain",
        display_name: "领域模拟",
        entry_count: 4_000,
        order: 40,
        default_enabled: false,
        seed_label: "领域",
        code_offset: 190_000,
    },
    CategorySpec {
        id: "symbols",
        display_name: "符号模拟",
        entry_count: 2_000,
        order: 50,
        default_enabled: false,
        seed_label: "符号",
        code_offset: 250_000,
    },
];

pub const GUIDE_ENTRY_COUNT: usize = 2_000;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GenerationReport {
    pub root: PathBuf,
    pub manifest_path: PathBuf,
    pub manifest_sha256: String,
    pub category_counts: Vec<(String, usize)>,
    pub guide_count: usize,
}

pub fn generate_fixture(root: &Path) -> Result<GenerationReport, FixtureError> {
    let source_root = root.join("source");
    fs::create_dir_all(&source_root).map_err(|source| FixtureError::io(&source_root, source))?;

    let mut categories = Vec::with_capacity(CATEGORY_SPECS.len());
    let mut category_counts = Vec::with_capacity(CATEGORY_SPECS.len());
    for (category_index, spec) in CATEGORY_SPECS.iter().enumerate() {
        let bytes = category_bytes(*spec, category_index);
        let source_path = format!("source/{}.txt", spec.id);
        let path = root.join(&source_path);
        fs::write(&path, &bytes).map_err(|source| FixtureError::io(&path, source))?;
        categories.push(CategoryManifest {
            id: spec.id.to_owned(),
            display_name: spec.display_name.to_owned(),
            source_path,
            order: spec.order,
            default_enabled: spec.default_enabled,
            expected_entry_count: spec.entry_count,
            source_sha256: sha256_hex(&bytes),
        });
        category_counts.push((spec.id.to_owned(), spec.entry_count));
    }

    let guide_bytes = guide_bytes();
    let guide_path = "source/guide.txt".to_owned();
    let guide_file = root.join(&guide_path);
    fs::write(&guide_file, &guide_bytes).map_err(|source| FixtureError::io(&guide_file, source))?;

    let manifest = FixtureManifest {
        format_version: MANIFEST_FORMAT_VERSION,
        bundle_id: "code-table-fixture-synthetic-v1".to_owned(),
        display_name: "码表输入（测试）".to_owned(),
        fixture_only: true,
        categories,
        guide_table: GuideManifest {
            id: "guide".to_owned(),
            source_path: guide_path,
            expected_entry_count: GUIDE_ENTRY_COUNT,
            source_sha256: sha256_hex(&guide_bytes),
        },
    };
    let manifest_bytes = manifest.to_json_bytes();
    let manifest_path = root.join("code-table-fixture-manifest.json");
    fs::write(&manifest_path, &manifest_bytes)
        .map_err(|source| FixtureError::io(&manifest_path, source))?;

    Ok(GenerationReport {
        root: root.to_path_buf(),
        manifest_path,
        manifest_sha256: sha256_hex(&manifest_bytes),
        category_counts,
        guide_count: GUIDE_ENTRY_COUNT,
    })
}

fn category_bytes(spec: CategorySpec, category_index: usize) -> Vec<u8> {
    let mut output = String::with_capacity(spec.entry_count * 24);
    for index in 0..spec.entry_count {
        let serial = index + 1;
        let word = category_word(spec, category_index, index, serial);
        let code = coverage_code(spec, category_index, index);
        output.push_str(&word);
        output.push('\t');
        output.push_str(&code);
        output.push('\n');
    }
    output.into_bytes()
}

fn category_word(spec: CategorySpec, category_index: usize, index: usize, serial: usize) -> String {
    match index {
        0 => "共享同码同词000001".to_owned(),
        1 => "共享同词异码000002".to_owned(),
        2 => format!("同码异词{}000003", spec.seed_label),
        42 => format!("{}{:06}", "边界".repeat(13), serial),
        43 => format!("TEST{:06}", serial),
        44 => format!("模拟Mix{:06}", serial),
        45 => format!("符号★{:06}", serial),
        46 => "测".to_owned(),
        47 => "测试".to_owned(),
        48 => "原创模拟词".to_owned(),
        _ => {
            let seed =
                ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛"][(index + category_index) % 8];
            format!("{}{}{:06}", spec.seed_label, seed, serial)
        }
    }
}

fn coverage_code(spec: CategorySpec, category_index: usize, index: usize) -> String {
    match index {
        0 => "a".to_owned(),
        1 => "bcdefg"[..=category_index].to_owned(),
        2 => "abc".to_owned(),
        3 => "ab".to_owned(),
        4 => "abcd".to_owned(),
        5 => "abcde".to_owned(),
        6 => "abcdef".to_owned(),
        7..=36 => "zzzz".to_owned(),
        37..=38 => "yyyy".to_owned(),
        39..=44 => "xxxx".to_owned(),
        _ => encode_four(spec.code_offset + index),
    }
}

fn guide_bytes() -> Vec<u8> {
    let mut output = String::with_capacity(GUIDE_ENTRY_COUNT * 24);
    for index in 0..GUIDE_ENTRY_COUNT {
        let serial = index + 1;
        let code = match index {
            0 => "g".to_owned(),
            1 => "gu".to_owned(),
            2 => "gui".to_owned(),
            3 => "guid".to_owned(),
            4 => "guide".to_owned(),
            5 => "guidea".to_owned(),
            6..=30 => "help".to_owned(),
            _ => encode_four(320_000 + index),
        };
        output.push_str(&format!(
            "引导{}{:06}\t{}\n",
            ["甲", "乙", "丙", "丁"][index % 4],
            serial,
            code
        ));
    }
    output.into_bytes()
}

fn encode_four(mut value: usize) -> String {
    const RADIX: usize = 26;
    const SPACE: usize = RADIX * RADIX * RADIX * RADIX;
    value %= SPACE;
    let mut bytes = [b'a'; 4];
    for index in (0..4).rev() {
        bytes[index] = b'a' + (value % RADIX) as u8;
        value /= RADIX;
    }
    String::from_utf8(bytes.to_vec()).expect("lowercase ASCII")
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::{validate_table_bytes, FixtureManifest};

    static NEXT_TEMP: AtomicUsize = AtomicUsize::new(0);

    fn temp_root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "code-table-fixture-{name}-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ))
    }

    #[test]
    fn generates_required_scale_and_coverage() {
        let root = temp_root("scale");
        let report = generate_fixture(&root).unwrap();
        assert_eq!(
            report
                .category_counts
                .iter()
                .map(|value| value.1)
                .sum::<usize>(),
            25_000
        );
        assert_eq!(report.guide_count, 2_000);
        let manifest_bytes = fs::read(&report.manifest_path).unwrap();
        let manifest = FixtureManifest::from_bytes(&manifest_bytes, "manifest.json").unwrap();
        let mut lengths = std::collections::BTreeSet::new();
        let mut max_same_code = 0;
        for category in &manifest.categories {
            let bytes = fs::read(root.join(&category.source_path)).unwrap();
            let table = validate_table_bytes(&bytes, &category.source_path).unwrap();
            lengths.extend(table.code_lengths);
            max_same_code = max_same_code.max(table.max_same_code_count);
        }
        assert_eq!(lengths, (1..=6).collect());
        assert!(max_same_code >= 20);
        let guide = fs::read(root.join(&manifest.guide_table.source_path)).unwrap();
        assert_eq!(
            validate_table_bytes(&guide, "guide.txt")
                .unwrap()
                .entry_count,
            2_000
        );
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn independent_generation_is_byte_identical() {
        let left = temp_root("deterministic-left");
        let right = temp_root("deterministic-right");
        let left_report = generate_fixture(&left).unwrap();
        let right_report = generate_fixture(&right).unwrap();
        assert_eq!(
            fs::read(left_report.manifest_path).unwrap(),
            fs::read(right_report.manifest_path).unwrap()
        );
        for spec in CATEGORY_SPECS {
            assert_eq!(
                fs::read(left.join(format!("source/{}.txt", spec.id))).unwrap(),
                fs::read(right.join(format!("source/{}.txt", spec.id))).unwrap()
            );
        }
        assert_eq!(
            fs::read(left.join("source/guide.txt")).unwrap(),
            fs::read(right.join("source/guide.txt")).unwrap()
        );
        let _ = fs::remove_dir_all(left);
        let _ = fs::remove_dir_all(right);
    }
}
