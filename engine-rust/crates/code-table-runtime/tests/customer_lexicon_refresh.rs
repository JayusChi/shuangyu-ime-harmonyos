use std::path::PathBuf;

use code_table_runtime::{query_exact_or_prefix, CodeTableBundle};

fn bundle_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
    )
}

fn texts_for_code(bundle: &CodeTableBundle, code: &str) -> Vec<String> {
    let enabled = bundle
        .categories
        .iter()
        .map(|category| category.id.clone())
        .collect::<Vec<_>>();
    query_exact_or_prefix(bundle, &enabled, code, usize::MAX)
        .candidates
        .into_iter()
        .map(|candidate| candidate.text)
        .collect()
}

#[test]
fn customer_2026_08_29_primary_lexicon_changes_reach_the_frozen_bundle() {
    let bundle =
        CodeTableBundle::load_frozen_production_file(bundle_path()).expect("formal bundle");

    assert!(texts_for_code(&bundle, "byzi")
        .iter()
        .any(|text| text == "病秧子"));

    let fxdd = texts_for_code(&bundle, "fxdd");
    assert!(fxdd.iter().any(|text| text == "放心大胆"));
    assert!(!fxdd.iter().any(|text| text == "繁星点点"));

    for code in ["ydh", "ydhl"] {
        let texts = texts_for_code(&bundle, code);
        assert!(!texts.iter().any(|text| text == "运动会"), "{code}");
        assert!(!texts.iter().any(|text| text == "移动互联"), "{code}");
    }
}
