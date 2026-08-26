use std::sync::Arc;

use code_table_runtime::{
    query_exact_or_prefix, query_with_strategy, CategoryKind, CategorySelectionSnapshot,
    CodeTableBundle, CodeTableCommitPolicy, CodeTableErrorKind, CodeTableInputState,
    CodeTableMatch, CodeTableQueryStrategy, CodeTableSelection, CodeTableStateMachine,
    FunctionalAction, FunctionalActionTable, CATEGORY_SCHEMA_VERSION,
};
use lexicon_core::{build_binary_lexicon_with_source_order, LexiconEntry};
use user_lexicon::{parse_user_lexicon_bytes, UserLexiconSnapshot};

const HEADER_LEN: usize = 128;

#[derive(Clone)]
struct TableSpec {
    id: &'static str,
    order: u32,
    enabled: bool,
    guide: bool,
    entries: Vec<(&'static str, &'static str)>,
}

fn normal_specs() -> Vec<TableSpec> {
    vec![
        TableSpec {
            id: "core",
            order: 10,
            enabled: true,
            guide: false,
            entries: vec![
                ("共享", "a"),
                ("核心精确甲", "un"),
                ("核心精确乙", "un"),
                ("核心后续晚码", "unzz"),
                ("核心后续早码", "unan"),
                ("前缀二", "qx"),
                ("前缀一", "qa"),
            ],
        },
        TableSpec {
            id: "phrases",
            order: 20,
            enabled: true,
            guide: false,
            entries: vec![
                ("共享", "a"),
                ("短语精确", "un"),
                ("短语后续", "unxx"),
                ("短语前缀", "qb"),
            ],
        },
    ]
}

fn guide_spec() -> TableSpec {
    TableSpec {
        id: "guide",
        order: u32::MAX,
        enabled: false,
        guide: true,
        entries: vec![("默认冒号", "_"), ("；", ";"), ("引导", "g")],
    }
}

#[test]
fn bare_guide_shows_the_reserved_default_and_repeat_commits_itself() {
    let mut machine = state(5, 64);

    machine.process_key(';').unwrap();
    assert_eq!(machine.input_state(), CodeTableInputState::GuidePrefix);
    assert_eq!(candidate_texts(&machine), ["默认冒号"]);
    assert_eq!(machine.current_candidates()[0].code, "_");

    let repeated = machine.process_key(';').unwrap();
    assert_eq!(repeated.commit_text.as_deref(), Some("；"));
    assert_eq!(machine.input_state(), CodeTableInputState::Idle);
    assert!(machine.current_candidates().is_empty());
}

#[test]
fn production_direct_action_separates_candidate_label_from_committed_text() {
    let mut machine = state(8, 64);
    machine.set_action_table(Some(Arc::new(FunctionalActionTable::production_defaults())));

    input(&mut machine, "oba");
    assert_eq!(machine.current_candidates()[0].text, "横_一");
    assert_eq!(machine.current_candidates()[0].code, "oba");
    assert_eq!(
        machine.select_current_page(0).unwrap(),
        CodeTableSelection::CommitText("一".to_owned())
    );
}

#[test]
fn production_actions_keep_guide_and_direct_scopes_isolated() {
    let actions = Arc::new(FunctionalActionTable::production_defaults());
    let mut normal = state(8, 64);
    normal.set_action_table(Some(Arc::clone(&actions)));
    input(&mut normal, "p");
    assert!(normal
        .all_candidates()
        .iter()
        .all(|candidate| candidate.category_id != "functional"));

    let mut guide = state(8, 64);
    guide.set_action_table(Some(actions));
    input(&mut guide, ";p");
    assert_eq!(guide.current_candidates()[0].text, "〈〉");
    assert!(matches!(
        guide.select_current_page(0).unwrap(),
        CodeTableSelection::Action(FunctionalAction::InsertPair { ref text, cursor_offset_utf16: 1 })
            if text == "〈〉"
    ));
}

#[test]
fn production_double_semicolon_commits_full_width_colon() {
    let mut machine = state(8, 64);
    machine.set_action_table(Some(Arc::new(FunctionalActionTable::production_defaults())));
    machine.process_key(';').unwrap();
    assert_eq!(
        machine.process_key(';').unwrap().commit_text.as_deref(),
        Some("：")
    );
}

#[test]
fn production_direct_actions_expose_typed_category_presets_and_dynamic_values() {
    let actions = Arc::new(FunctionalActionTable::production_defaults());
    let mut presets = state(8, 64);
    presets.set_action_table(Some(Arc::clone(&actions)));
    input(&mut presets, "ojj");
    assert_eq!(
        candidate_texts(&presets)[0..3],
        ["<熟手词库>", "<常规词库>", "<初学词库>"]
    );
    assert!(matches!(
        presets.select_current_page(1).unwrap(),
        CodeTableSelection::Action(FunctionalAction::DirectControl { ref action, ref target })
            if action == "category.preset" && target == "standard"
    ));

    let mut timestamp = state(8, 64);
    timestamp.set_action_table(Some(actions));
    input(&mut timestamp, "ouji");
    assert!(matches!(
        timestamp.select_current_page(0).unwrap(),
        CodeTableSelection::Action(FunctionalAction::DateTimeText(
            code_table_runtime::DateTimeFormatId::UnixTimestamp
        ))
    ));

    let mut local_date = state(8, 64);
    local_date.set_action_table(Some(Arc::new(FunctionalActionTable::production_defaults())));
    input(&mut local_date, "orq");
    assert!(matches!(
        local_date.select_current_page(1).unwrap(),
        CodeTableSelection::Action(FunctionalAction::DateTimeText(
            code_table_runtime::DateTimeFormatId::DateLocalUnpadded
        ))
    ));

    let mut weekday = state(8, 64);
    weekday.set_action_table(Some(Arc::new(FunctionalActionTable::production_defaults())));
    input(&mut weekday, "ouj");
    assert!(matches!(
        weekday.select_current_page(0).unwrap(),
        CodeTableSelection::Action(FunctionalAction::DateTimeText(
            code_table_runtime::DateTimeFormatId::TimeWeekday
        ))
    ));

    let mut open_url = state(8, 64);
    open_url.set_action_table(Some(Arc::new(FunctionalActionTable::production_defaults())));
    input(&mut open_url, "xhgw");
    assert!(matches!(
        open_url.select_current_page(0).unwrap(),
        CodeTableSelection::Action(FunctionalAction::DirectControl { ref action, ref target })
            if action == "url.open" && target == "flypy-home"
    ));
}

#[test]
fn universal_key_queries_unknown_shape_and_sound_positions() {
    let mut unknown_shape = state(8, 64);
    input(&mut unknown_shape, "un");
    unknown_shape.process_key('`').unwrap();
    assert_eq!(unknown_shape.raw_code(), "un`");
    let shape_candidates = candidate_texts(&unknown_shape);
    assert!(shape_candidates.contains(&"核心后续晚码"));
    assert!(shape_candidates.contains(&"核心后续早码"));
    assert!(shape_candidates.contains(&"短语后续"));
    assert!(!shape_candidates.contains(&"核心精确甲"));

    let mut unknown_sound = state(8, 64);
    unknown_sound.process_key('`').unwrap();
    unknown_sound.process_key('`').unwrap();
    input(&mut unknown_sound, "an");
    assert_eq!(unknown_sound.raw_code(), "``an");
    assert_eq!(candidate_texts(&unknown_sound), ["核心后续早码"]);
}

#[test]
fn direct_user_layer_is_exactly_queryable_but_hidden_from_universal_key() {
    let mut exact = state_with_rules(8, 64, "直通词\tunan\n");
    input(&mut exact, "unan");
    assert!(candidate_texts(&exact).contains(&"直通词"));

    let mut wildcard = state_with_rules(8, 64, "直通词\tunan\n");
    input(&mut wildcard, "un");
    wildcard.process_key('`').unwrap();
    assert!(!candidate_texts(&wildcard).contains(&"直通词"));
}

fn paging_specs() -> Vec<TableSpec> {
    let mut entries = Vec::new();
    for index in 0..25 {
        let word = Box::leak(format!("分页{index:02}").into_boxed_str());
        entries.push((word as &'static str, "zzzz"));
    }
    vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries,
    }]
}

fn progressive_specs() -> Vec<TableSpec> {
    vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![
            ("甲", "a"),
            ("乙", "aa"),
            ("丙", "aaa"),
            ("丁", "aaaa"),
            ("甲", "abcd"),
            ("你", "ni"),
            ("呢", "nia"),
            ("泥", "nibc"),
            ("拟", "nidf"),
            ("你", "nijk"),
            ("呀", "niax"),
            ("雅", "niax"),
        ],
    }]
}

fn precise_hint_specs() -> Vec<TableSpec> {
    let suffixes = [
        "jb", "an", "bi", "jw", "jv", "kl", "lh", "um", "li", "zz", "yy",
    ];
    let words = [
        "伤脑筋",
        "施耐庵",
        "史努比",
        "十拿九稳",
        "上年结转",
        "受虐狂",
        "少年郎",
        "十年树木",
        "少年老成",
        "山南海北",
        "深谋远虑",
    ];
    let entries = words
        .into_iter()
        .zip(suffixes)
        .map(|(word, suffix)| {
            let code = Box::leak(format!("un{suffix}").into_boxed_str());
            (word, code as &'static str)
        })
        .collect();
    vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries,
    }]
}

fn user_overlay_paging_specs() -> Vec<TableSpec> {
    let words = [
        "分页甲",
        "分页乙",
        "分页丙",
        "分页丁",
        "分页戊",
        "分页己",
        "分页庚",
        "分页辛",
        "分页壬",
        "分页癸",
        "分页子",
        "分页丑",
        "分页寅",
        "分页卯",
        "分页辰",
        "分页巳",
        "分页午",
        "分页未",
        "分页申",
        "分页酉",
        "分页戌",
        "分页亥",
        "分页天",
        "分页地",
        "分页人",
    ];
    vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: words.into_iter().map(|word| (word, "zzzz")).collect(),
    }]
}

fn bundle_bytes(specs: &[TableSpec], guide: &TableSpec) -> Vec<u8> {
    let hash = "00".repeat(32);
    let categories = specs
        .iter()
        .map(|spec| {
            format!(
                "{{\"id\":\"{}\",\"displayName\":\"测试\",\"sourcePath\":\"{}.txt\",\"order\":{},\"defaultEnabled\":{},\"expectedEntryCount\":{},\"sourceSha256\":\"{}\"}}",
                spec.id,
                spec.id,
                spec.order,
                spec.enabled,
                spec.entries.len(),
                hash
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    let manifest = format!(
        "{{\"formatVersion\":1,\"bundleId\":\"code-table-fixture-test\",\"displayName\":\"码表输入（测试）\",\"fixtureOnly\":true,\"categories\":[{categories}],\"guideTable\":{{\"id\":\"{}\",\"sourcePath\":\"guide.txt\",\"expectedEntryCount\":{},\"sourceSha256\":\"{}\"}}}}",
        guide.id,
        guide.entries.len(),
        hash
    )
    .into_bytes();
    let mut payload = Vec::new();
    for spec in specs.iter().chain(std::iter::once(guide)) {
        write_record(&mut payload, spec);
    }
    let mut bytes = vec![0_u8; HEADER_LEN];
    bytes.extend_from_slice(&manifest);
    bytes.extend_from_slice(&payload);
    bytes[..8].copy_from_slice(b"HSPCTF01");
    bytes[8..12].copy_from_slice(&(HEADER_LEN as u32).to_le_bytes());
    bytes[12..14].copy_from_slice(&1_u16.to_le_bytes());
    bytes[14..16].copy_from_slice(&0_u16.to_le_bytes());
    bytes[16..20].copy_from_slice(&1_u32.to_le_bytes());
    bytes[20..24].copy_from_slice(&1_u32.to_le_bytes());
    bytes[24..28].copy_from_slice(&(specs.len() as u32).to_le_bytes());
    bytes[28..32].copy_from_slice(&((specs.len() + 1) as u32).to_le_bytes());
    bytes[32..40].copy_from_slice(&(manifest.len() as u64).to_le_bytes());
    bytes[40..48].copy_from_slice(&(payload.len() as u64).to_le_bytes());
    refresh_content_hash(&mut bytes);
    bytes
}

fn write_record(output: &mut Vec<u8>, spec: &TableSpec) {
    let entries = spec
        .entries
        .iter()
        .enumerate()
        .map(|(index, (word, code))| {
            LexiconEntry::new(
                (*word).to_owned(),
                (*code).to_owned(),
                vec![(*code).to_owned()],
                (1000 - index) as u64,
                vec!["fixture".to_owned()],
            )
            .with_source_order(index as u32)
        })
        .collect::<Vec<_>>();
    let binary = build_binary_lexicon_with_source_order(&entries, 11_620, 1).unwrap();
    output.extend_from_slice(&(spec.id.len() as u16).to_le_bytes());
    output.push(u8::from(spec.guide));
    output.push(u8::from(spec.enabled));
    output.extend_from_slice(&spec.order.to_le_bytes());
    output.extend_from_slice(&(spec.entries.len() as u32).to_le_bytes());
    output.extend_from_slice(&[0_u8; 32]);
    output.extend_from_slice(&(binary.len() as u64).to_le_bytes());
    output.extend_from_slice(spec.id.as_bytes());
    output.extend_from_slice(&binary);
}

fn refresh_content_hash(bytes: &mut [u8]) {
    let hash = sha256_for_test(&bytes[HEADER_LEN..]);
    bytes[80..112].copy_from_slice(&hash);
}

fn sha256_for_test(input: &[u8]) -> [u8; 32] {
    test_sha256::digest(input)
}

mod test_sha256 {
    pub fn digest(input: &[u8]) -> [u8; 32] {
        const INITIAL: [u32; 8] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
            0x5be0cd19,
        ];
        const K: [u32; 64] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
            0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
            0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
            0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
            0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
            0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
            0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
            0xc67178f2,
        ];
        let mut padded = input.to_vec();
        let bit_len = (input.len() as u64) * 8;
        padded.push(0x80);
        while padded.len() % 64 != 56 {
            padded.push(0);
        }
        padded.extend_from_slice(&bit_len.to_be_bytes());
        let mut state = INITIAL;
        for chunk in padded.chunks_exact(64) {
            let mut w = [0_u32; 64];
            for (index, slot) in w.iter_mut().take(16).enumerate() {
                *slot = u32::from_be_bytes(chunk[index * 4..index * 4 + 4].try_into().unwrap());
            }
            for index in 16..64 {
                let s0 = w[index - 15].rotate_right(7)
                    ^ w[index - 15].rotate_right(18)
                    ^ (w[index - 15] >> 3);
                let s1 = w[index - 2].rotate_right(17)
                    ^ w[index - 2].rotate_right(19)
                    ^ (w[index - 2] >> 10);
                w[index] = w[index - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[index - 7])
                    .wrapping_add(s1);
            }
            let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = state;
            for index in 0..64 {
                let t1 = h
                    .wrapping_add(e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25))
                    .wrapping_add((e & f) ^ (!e & g))
                    .wrapping_add(K[index])
                    .wrapping_add(w[index]);
                let t2 = (a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22))
                    .wrapping_add((a & b) ^ (a & c) ^ (b & c));
                h = g;
                g = f;
                f = e;
                e = d.wrapping_add(t1);
                d = c;
                c = b;
                b = a;
                a = t1.wrapping_add(t2);
            }
            for (slot, value) in state.iter_mut().zip([a, b, c, d, e, f, g, h]) {
                *slot = slot.wrapping_add(value);
            }
        }
        let mut output = [0_u8; 32];
        for (index, value) in state.iter().enumerate() {
            output[index * 4..index * 4 + 4].copy_from_slice(&value.to_be_bytes());
        }
        output
    }
}

fn loaded_bundle() -> Arc<CodeTableBundle> {
    Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&normal_specs(), &guide_spec())).unwrap())
}

fn loaded_progressive_bundle() -> Arc<CodeTableBundle> {
    Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&progressive_specs(), &guide_spec())).unwrap(),
    )
}

fn state(page_size: usize, limit: usize) -> CodeTableStateMachine {
    CodeTableStateMachine::new(loaded_bundle(), page_size, limit).unwrap()
}

fn snapshot(rules: &str) -> Arc<UserLexiconSnapshot> {
    Arc::new(
        parse_user_lexicon_bytes("fixture-user-lexicon.txt", rules.as_bytes())
            .unwrap()
            .into_snapshot(),
    )
}

fn state_with_rules(page_size: usize, limit: usize, rules: &str) -> CodeTableStateMachine {
    CodeTableStateMachine::new_with_user_lexicon(loaded_bundle(), page_size, limit, snapshot(rules))
        .unwrap()
}

fn deterministic_state(
    specs: &[TableSpec],
    page_size: usize,
    rules: &str,
) -> CodeTableStateMachine {
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(specs, &guide_spec())).unwrap());
    CodeTableStateMachine::new_with_query_strategy(
        bundle,
        page_size,
        64,
        snapshot(rules),
        CodeTableQueryStrategy::DeterministicXiaoheYinxing,
    )
    .unwrap()
}

fn input(machine: &mut CodeTableStateMachine, code: &str) {
    for key in code.chars() {
        machine.process_key(key).unwrap();
    }
}

fn candidate_texts(machine: &CodeTableStateMachine) -> Vec<&str> {
    machine
        .all_candidates()
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect()
}

#[test]
fn empty_input_returns_no_candidates() {
    let machine = state(5, 64);
    assert!(machine.current_candidates().is_empty());
    assert!(machine.query_cache().is_none());
}

#[test]
fn exact_hit_returns_only_exact_entries() {
    let mut machine = state(8, 64);
    input(&mut machine, "un");
    assert_eq!(
        machine.query_cache().unwrap().match_type,
        Some(CodeTableMatch::Exact)
    );
    assert_eq!(machine.all_candidates().len(), 3);
    assert!(machine
        .all_candidates()
        .iter()
        .all(|candidate| candidate.code == "un"));
}

#[test]
fn exact_hit_never_mixes_longer_codes() {
    let mut machine = state(8, 64);
    input(&mut machine, "un");
    assert!(!machine
        .all_candidates()
        .iter()
        .any(|candidate| candidate.code == "unxx"));
}

#[test]
fn explicit_query_strategies_preserve_fallback_and_isolate_progressive_semantics() {
    let bundle = loaded_progressive_bundle();
    let enabled = bundle.default_enabled_category_ids();

    let exact_only = query_with_strategy(
        &bundle,
        &enabled,
        "ni",
        64,
        CodeTableQueryStrategy::ExactOnly,
    );
    assert_eq!(
        exact_only
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["你"]
    );
    assert!(query_with_strategy(
        &bundle,
        &enabled,
        "n",
        64,
        CodeTableQueryStrategy::ExactOnly,
    )
    .candidates
    .is_empty());

    let deterministic = query_with_strategy(
        &bundle,
        &enabled,
        "ni",
        64,
        CodeTableQueryStrategy::DeterministicXiaoheYinxing,
    );
    assert_eq!(deterministic, exact_only);

    let fallback = query_with_strategy(
        &bundle,
        &enabled,
        "ni",
        64,
        CodeTableQueryStrategy::ExactOrPrefixFallback,
    );
    assert_eq!(fallback, exact_only);

    let progressive = query_with_strategy(
        &bundle,
        &enabled,
        "ni",
        64,
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
    );
    assert_eq!(
        progressive
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["你", "呢", "泥", "拟", "呀", "雅"]
    );
    assert_eq!(progressive.candidates[0].match_type, CodeTableMatch::Exact);
    assert!(progressive.candidates[1..]
        .iter()
        .all(|candidate| candidate.match_type == CodeTableMatch::Prefix));

    assert_eq!(
        query_exact_or_prefix(&bundle, &enabled, "ni", 64),
        fallback,
        "the public legacy query keeps exact-or-prefix fallback semantics"
    );
}

#[test]
fn deterministic_precise_hint_uses_only_the_first_source_ordered_candidate() {
    let specs = precise_hint_specs();
    let mut machine = deterministic_state(&specs, 50, "");
    input(&mut machine, "un");

    assert_eq!(
        machine.query_cache().unwrap().match_type,
        Some(CodeTableMatch::Prefix)
    );
    assert_eq!(machine.all_candidates().len(), 1);
    assert_eq!(candidate_texts(&machine), ["伤脑筋"]);
    assert_eq!(
        machine
            .all_candidates()
            .iter()
            .map(|candidate| candidate.code.as_str())
            .collect::<Vec<_>>(),
        ["unjb"]
    );
    assert!(!machine.has_next_page());
}

#[test]
fn deterministic_exact_hit_hides_longer_hints_and_hint_is_selectable() {
    let mut exact = deterministic_state(&normal_specs(), 50, "");
    input(&mut exact, "un");
    assert_eq!(
        exact.query_cache().unwrap().match_type,
        Some(CodeTableMatch::Exact)
    );
    assert!(exact
        .all_candidates()
        .iter()
        .all(|candidate| candidate.code == "un"));

    let specs = precise_hint_specs();
    let mut hint = deterministic_state(&specs, 50, "");
    input(&mut hint, "un");
    let selected = hint.select_current_page(0).unwrap();
    assert_eq!(
        selected,
        code_table_runtime::CodeTableSelection::CommitText("伤脑筋".to_owned())
    );
    assert!(hint.raw_code().is_empty());
}

#[test]
fn deterministic_hint_delete_refills_without_fixed_or_position_reordering() {
    let specs = precise_hint_specs();
    let rules = "伤脑筋\tunjb#删\n施耐庵\tunan#5\n史努比\tunbi#固\n";
    let mut machine = deterministic_state(&specs, 50, rules);
    input(&mut machine, "un");

    assert_eq!(candidate_texts(&machine), ["施耐庵"]);
}

#[test]
fn fifth_key_never_top_screens_a_prefix_hint() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("old-hint", "abcdf"), ("new-segment", "e")],
    }];
    let mut machine = deterministic_state(&specs, 50, "");
    input(&mut machine, "abcd");
    assert_eq!(candidate_texts(&machine), ["old-hint"]);

    let outcome = machine.process_key('e').unwrap();
    assert!(outcome.commit_text.is_none());
    assert_eq!(machine.raw_code(), "e");
    assert_eq!(candidate_texts(&machine), ["new-segment"]);
}

#[test]
fn progressive_strategy_merges_one_to_three_codes_and_keeps_four_codes_exact() {
    let bundle = loaded_progressive_bundle();
    let enabled = bundle.default_enabled_category_ids();
    let query = |code| {
        query_with_strategy(
            &bundle,
            &enabled,
            code,
            64,
            CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
        )
    };

    assert_eq!(
        query("a")
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["甲", "乙", "丙", "丁"]
    );
    assert_eq!(
        query("ni")
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["你", "呢", "泥", "拟", "呀", "雅"]
    );
    assert_eq!(
        query("nia")
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["呢", "呀", "雅"]
    );
    assert_eq!(
        query("niax")
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["呀", "雅"]
    );
    assert!(
        query("niax")
            .candidates
            .iter()
            .all(|candidate| candidate.code == "niax"
                && candidate.match_type == CodeTableMatch::Exact)
    );
}

#[test]
fn progressive_state_applies_user_rules_and_dedup_before_bounded_paging() {
    let mut machine = CodeTableStateMachine::new_with_query_strategy(
        loaded_progressive_bundle(),
        2,
        64,
        snapshot("泥\tnibc#固\n呢\tnia#删\n拟\tnidf#2\n"),
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
    )
    .unwrap();
    input(&mut machine, "ni");
    assert_eq!(candidate_texts(&machine), ["泥", "拟", "你", "呀", "雅"]);

    let expected = machine.all_candidates().to_vec();
    let mut paged = machine.current_candidates().to_vec();
    while machine.has_next_page() {
        machine.next_page().unwrap();
        paged.extend_from_slice(machine.current_candidates());
    }
    assert_eq!(paged, expected);
    let mut seen = std::collections::BTreeSet::new();
    assert!(paged
        .iter()
        .all(|candidate| seen.insert(candidate.text.as_str())));
}

#[test]
fn progressive_four_code_auto_commit_uses_exact_candidates_only() {
    let mut unique = CodeTableStateMachine::new_with_query_strategy(
        loaded_progressive_bundle(),
        8,
        64,
        snapshot(""),
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
    )
    .unwrap();
    input(&mut unique, "nib");
    let committed = unique.process_key('c').unwrap();
    assert_eq!(committed.commit_text.as_deref(), Some("泥"));
    assert!(unique.raw_code().is_empty());

    let mut multiple = CodeTableStateMachine::new_with_query_strategy(
        loaded_progressive_bundle(),
        8,
        64,
        snapshot(""),
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
    )
    .unwrap();
    input(&mut multiple, "niax");
    assert_eq!(candidate_texts(&multiple), ["呀", "雅"]);
    assert_eq!(multiple.exact_candidate_count(), 2);
    assert_eq!(multiple.raw_code(), "niax");
}

#[test]
fn missing_exact_uses_longer_prefix_entries() {
    let mut machine = state(8, 64);
    input(&mut machine, "q");
    assert_eq!(
        machine.query_cache().unwrap().match_type,
        Some(CodeTableMatch::Prefix)
    );
    assert_eq!(machine.all_candidates().len(), 3);
}

#[test]
fn prefix_results_follow_category_order() {
    let mut machine = state(8, 64);
    input(&mut machine, "q");
    assert_eq!(machine.all_candidates()[0].category_id, "core");
    assert_eq!(machine.all_candidates()[2].category_id, "phrases");
}

#[test]
fn category_entries_follow_source_order_not_code_order() {
    let mut machine = state(8, 64);
    input(&mut machine, "q");
    assert_eq!(machine.all_candidates()[0].text, "前缀二");
    assert_eq!(machine.all_candidates()[1].text, "前缀一");
}

#[test]
fn changing_source_rows_changes_result_order() {
    let mut specs = normal_specs();
    specs[0].entries.swap(5, 6);
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "q");
    assert_eq!(machine.all_candidates()[0].text, "前缀一");
}

#[test]
fn cross_category_duplicate_is_removed_stably() {
    let bundle = loaded_bundle();
    let result = query_exact_or_prefix(&bundle, &["core".into(), "phrases".into()], "a", 64);
    assert_eq!(result.candidates.len(), 1);
}

#[test]
fn stable_dedup_keeps_first_category_occurrence() {
    let bundle = loaded_bundle();
    let result = query_exact_or_prefix(&bundle, &["core".into(), "phrases".into()], "a", 64);
    assert_eq!(result.candidates[0].category_id, "core");
}

#[test]
fn twenty_plus_same_code_preserves_order() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&paging_specs(), &guide_spec())).unwrap(),
    );
    let mut machine = CodeTableStateMachine::new(bundle, 7, 64).unwrap();
    input(&mut machine, "zzzz");
    assert_eq!(machine.all_candidates().len(), 25);
    assert_eq!(machine.all_candidates()[24].text, "分页24");
}

#[test]
fn first_and_next_page_are_contiguous() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&paging_specs(), &guide_spec())).unwrap(),
    );
    let mut machine = CodeTableStateMachine::new(bundle, 7, 64).unwrap();
    input(&mut machine, "zzzz");
    assert_eq!(machine.current_candidates()[6].text, "分页06");
    machine.next_page().unwrap();
    assert_eq!(machine.current_candidates()[0].text, "分页07");
}

#[test]
fn final_page_reports_no_next_page() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&paging_specs(), &guide_spec())).unwrap(),
    );
    let mut machine = CodeTableStateMachine::new(bundle, 7, 64).unwrap();
    input(&mut machine, "zzzz");
    while machine.has_next_page() {
        machine.next_page().unwrap();
    }
    assert_eq!(machine.current_candidates().len(), 4);
    assert!(!machine.has_next_page());
}

#[test]
fn page_out_of_bounds_is_explicit() {
    let mut machine = state(8, 64);
    input(&mut machine, "un");
    assert_eq!(
        machine.next_page().unwrap_err().kind,
        CodeTableErrorKind::InvalidPage
    );
}

#[test]
fn new_key_resets_page_to_first() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&paging_specs(), &guide_spec())).unwrap(),
    );
    let mut machine = CodeTableStateMachine::new(bundle, 7, 64).unwrap();
    input(&mut machine, "zzz");
    machine.next_page().unwrap();
    machine.process_key('z').unwrap();
    assert_eq!(machine.current_page(), 0);
}

#[test]
fn backspace_requeries_and_resets_page() {
    let mut machine = state(2, 64);
    input(&mut machine, "unx");
    machine.backspace();
    assert_eq!(machine.raw_code(), "un");
    assert_eq!(machine.current_page(), 0);
    assert_eq!(machine.all_candidates().len(), 3);
}

#[test]
fn continuous_backspace_reaches_clean_idle_state() {
    let mut machine = state(5, 64);
    input(&mut machine, "unan");
    for _ in 0..4 {
        machine.backspace();
    }
    assert!(machine.raw_code().is_empty());
    assert!(machine.current_candidates().is_empty());
    assert!(machine.query_cache().is_none());
}

#[test]
fn reset_clears_all_query_state() {
    let mut machine = state(5, 64);
    input(&mut machine, "un");
    machine.reset();
    assert_eq!(machine.current_page(), 0);
    assert!(machine.raw_code().is_empty());
    assert!(machine.query_cache().is_none());
}

#[test]
fn illegal_key_returns_error_without_mutation() {
    let mut machine = state(5, 64);
    input(&mut machine, "un");
    let before = machine.all_candidates().to_vec();
    assert_eq!(
        machine.process_key('?').unwrap_err().kind,
        CodeTableErrorKind::InvalidKey
    );
    assert_eq!(machine.raw_code(), "un");
    assert_eq!(machine.all_candidates(), before);
}

#[test]
fn deterministic_mixed_guide_sequences_preserve_state_invariants() {
    let mut machine = state(3, 64);
    let mut seed = 0x1166_u32;
    for _ in 0..10_000 {
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        match seed % 11 {
            0..=4 => {
                let key = (b'a' + ((seed >> 8) % 26) as u8) as char;
                let _ = machine.process_key(key);
            }
            5 => {
                machine.process_key(';').unwrap();
            }
            6 => machine.backspace(),
            7 => machine.reset(),
            8 => {
                let _ = machine.next_page();
            }
            9 => {
                let _ = machine.previous_page();
            }
            _ => {
                if !machine.current_candidates().is_empty() {
                    let _ = machine.select_current_page(0);
                }
            }
        }

        assert!(machine.raw_code().len() <= 64);
        assert!(machine
            .raw_code()
            .bytes()
            .all(|byte| byte.is_ascii_lowercase()));
        match machine.input_state() {
            CodeTableInputState::Idle | CodeTableInputState::GuidePrefix => {
                assert!(machine.raw_code().is_empty());
            }
            CodeTableInputState::NormalCode | CodeTableInputState::GuideCode => {
                assert!(!machine.raw_code().is_empty());
            }
        }
        assert!(machine.current_page() == 0 || !machine.current_candidates().is_empty());
    }
}

#[test]
fn overlong_code_is_bounded() {
    let mut machine = state(5, 64);
    machine.process_key(';').unwrap();
    for _ in 0..64 {
        machine.process_key('a').unwrap();
    }
    assert_eq!(
        machine.process_key('a').unwrap_err().kind,
        CodeTableErrorKind::CodeTooLong
    );
    assert_eq!(machine.raw_code().len(), 64);
}

#[test]
fn truncated_bundle_is_rejected() {
    assert_eq!(
        CodeTableBundle::load_bytes(b"short").unwrap_err().kind,
        CodeTableErrorKind::TruncatedData
    );
}

#[test]
fn wrong_magic_is_rejected() {
    let mut bytes = bundle_bytes(&normal_specs(), &guide_spec());
    bytes[0] = b'X';
    assert_eq!(
        CodeTableBundle::load_bytes(&bytes).unwrap_err().kind,
        CodeTableErrorKind::InvalidMagic
    );
}

#[test]
fn unsupported_version_is_rejected() {
    let mut bytes = bundle_bytes(&normal_specs(), &guide_spec());
    bytes[12..14].copy_from_slice(&2_u16.to_le_bytes());
    assert_eq!(
        CodeTableBundle::load_bytes(&bytes).unwrap_err().kind,
        CodeTableErrorKind::UnsupportedVersion
    );
}

#[test]
fn checksum_corruption_is_rejected() {
    let mut bytes = bundle_bytes(&normal_specs(), &guide_spec());
    *bytes.last_mut().unwrap() ^= 1;
    assert_eq!(
        CodeTableBundle::load_bytes(&bytes).unwrap_err().kind,
        CodeTableErrorKind::ChecksumMismatch
    );
}

#[test]
fn missing_category_record_is_rejected() {
    let mut bytes = bundle_bytes(&normal_specs(), &guide_spec());
    bytes[24..28].copy_from_slice(&3_u32.to_le_bytes());
    assert_eq!(
        CodeTableBundle::load_bytes(&bytes).unwrap_err().kind,
        CodeTableErrorKind::MetadataMismatch
    );
}

#[test]
fn duplicate_category_configuration_is_rejected() {
    let bundle = loaded_bundle();
    let error = bundle
        .validate_enabled_categories(&["core".into(), "core".into()])
        .unwrap_err();
    assert_eq!(error.kind, CodeTableErrorKind::DuplicateCategoryId);
}

#[test]
fn candidate_ids_are_deterministic() {
    let mut first = state(8, 64);
    input(&mut first, "un");
    let ids = first
        .all_candidates()
        .iter()
        .map(|value| value.id.clone())
        .collect::<Vec<_>>();
    let mut second = state(8, 64);
    input(&mut second, "un");
    assert_eq!(
        ids,
        second
            .all_candidates()
            .iter()
            .map(|value| value.id.clone())
            .collect::<Vec<_>>()
    );
}

#[test]
fn independent_loads_produce_identical_results() {
    let bytes = bundle_bytes(&normal_specs(), &guide_spec());
    let first = CodeTableBundle::load_bytes(&bytes).unwrap();
    let second = CodeTableBundle::load_bytes(&bytes).unwrap();
    assert_eq!(
        query_exact_or_prefix(&first, &first.default_enabled_category_ids(), "un", 64),
        query_exact_or_prefix(&second, &second.default_enabled_category_ids(), "un", 64)
    );
}

#[test]
fn immutable_bundle_supports_parallel_read_queries() {
    let bundle = loaded_bundle();
    let mut joins = Vec::new();
    for _ in 0..8 {
        let shared = Arc::clone(&bundle);
        joins.push(std::thread::spawn(move || {
            query_exact_or_prefix(&shared, &shared.default_enabled_category_ids(), "un", 64)
        }));
    }
    let first = joins.remove(0).join().unwrap();
    for join in joins {
        assert_eq!(join.join().unwrap(), first);
    }
}

#[test]
fn repeated_create_query_reset_drop_is_stable() {
    for _ in 0..100 {
        let mut machine = state(5, 64);
        input(&mut machine, "un");
        machine.reset();
        assert!(machine.current_candidates().is_empty());
    }
}

#[test]
fn candidate_limit_is_applied_after_stable_merge() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&paging_specs(), &guide_spec())).unwrap(),
    );
    let mut machine = CodeTableStateMachine::new(bundle, 5, 10).unwrap();
    input(&mut machine, "zzzz");
    assert_eq!(machine.all_candidates().len(), 10);
    assert_eq!(machine.all_candidates()[9].text, "分页09");
}

#[test]
fn ordinary_user_entries_merge_in_source_order_and_replace_system_duplicates() {
    let mut machine = state_with_rules(8, 64, "用户新增甲\tun\n核心精确甲\tun\n用户新增乙\tun\n");
    input(&mut machine, "un");
    let texts = machine
        .all_candidates()
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();
    assert_eq!(
        texts,
        vec![
            "核心精确乙",
            "短语精确",
            "用户新增甲",
            "核心精确甲",
            "用户新增乙",
        ]
    );
    assert_eq!(machine.all_candidates()[3].category_id, "user-lexicon");
}

#[test]
fn delete_matches_complete_code_survives_reset_and_never_mutates_bundle() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("同名词", "qa"), ("同名词", "qb"), ("其他词", "qa")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new_with_user_lexicon(
        Arc::clone(&bundle),
        8,
        64,
        snapshot("同名词\tqa#删\n"),
    )
    .unwrap();
    input(&mut machine, "qa");
    assert_eq!(machine.all_candidates()[0].text, "其他词");
    assert!(machine
        .all_candidates()
        .iter()
        .all(|candidate| candidate.text != "同名词"));
    machine.reset();
    input(&mut machine, "qb");
    assert_eq!(machine.all_candidates()[0].text, "同名词");
    assert_eq!(
        query_exact_or_prefix(&bundle, &["core".into()], "qa", 64)
            .candidates
            .len(),
        2
    );
    machine.reset();
    input(&mut machine, "qa");
    assert_eq!(machine.all_candidates()[0].text, "其他词");
}

#[test]
fn prefix_delete_uses_candidate_complete_code() {
    let mut machine = state_with_rules(8, 64, "前缀一\tqa#删\n");
    input(&mut machine, "q");
    let texts = machine
        .all_candidates()
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();
    assert_eq!(texts, vec!["前缀二", "短语前缀"]);
    assert!(machine
        .all_candidates()
        .iter()
        .all(|candidate| candidate.code != "qa"));
}

#[test]
fn fixed_prefix_and_position_rules_are_stable_and_protected() {
    let mut machine = state_with_rules(
        16,
        64,
        concat!(
            "核心精确乙\tun#固\n",
            "短语精确\tun#固\n",
            "普通用户\tun\n",
            "首位请求\tun#1\n",
            "第二甲\tun#2\n",
            "第二乙\tun#2\n",
            "末尾词\tun#99\n",
        ),
    );
    input(&mut machine, "un");
    let texts = machine
        .all_candidates()
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();
    assert_eq!(
        texts,
        vec![
            "核心精确乙",
            "短语精确",
            "首位请求",
            "第二甲",
            "第二乙",
            "核心精确甲",
            "普通用户",
            "末尾词",
        ]
    );
}

#[test]
fn later_effective_rule_is_the_only_behavior_applied() {
    let mut machine = state_with_rules(
        8,
        64,
        concat!(
            "核心精确甲\tun\n",
            "核心精确甲\tun#删\n",
            "核心精确乙\tun#删\n",
            "核心精确乙\tun#固\n",
            "短语精确\tun#固\n",
            "短语精确\tun#2\n",
        ),
    );
    input(&mut machine, "un");
    let texts = machine
        .all_candidates()
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();
    assert_eq!(texts, vec!["核心精确乙", "短语精确"]);
}

#[test]
fn overlay_is_complete_before_limit_and_pagination() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&user_overlay_paging_specs(), &guide_spec()))
            .unwrap(),
    );
    let mut machine = CodeTableStateMachine::new_with_user_lexicon(
        bundle,
        5,
        10,
        snapshot(concat!(
            "分页甲\tzzzz#删\n",
            "分页戌\tzzzz#固\n",
            "分页巳\tzzzz#2\n",
        )),
    )
    .unwrap();
    input(&mut machine, "zzzz");
    assert_eq!(machine.all_candidates().len(), 10);
    assert_eq!(machine.all_candidates()[0].text, "分页戌");
    assert_eq!(machine.all_candidates()[1].text, "分页巳");
    assert_eq!(machine.current_candidates()[4].text, "分页丁");
    machine.next_page().unwrap();
    assert_eq!(machine.current_candidates()[0].text, "分页戊");
    assert!(machine
        .all_candidates()
        .iter()
        .all(|candidate| candidate.text != "分页甲"));
}

#[test]
fn immutable_snapshot_replacement_requeries_without_half_updated_state() {
    let mut machine = state_with_rules(8, 64, "旧用户词\tun#固\n");
    input(&mut machine, "un");
    let old = machine.all_candidates().to_vec();
    assert_eq!(old[0].text, "旧用户词");
    machine.set_user_lexicon_snapshot(snapshot("新用户词\tun#固\n"));
    let new = machine.all_candidates().to_vec();
    assert_eq!(new[0].text, "新用户词");
    assert!(!new.iter().any(|candidate| candidate.text == "旧用户词"));
    assert_eq!(old[0].text, "旧用户词");
}

#[test]
fn shared_snapshot_queries_are_parallel_and_deterministic() {
    let bundle = loaded_bundle();
    let user = snapshot("固定词\tun#固\n位置词\tun#2\n");
    let mut joins = Vec::new();
    for _ in 0..8 {
        let bundle = Arc::clone(&bundle);
        let user = Arc::clone(&user);
        joins.push(std::thread::spawn(move || {
            let mut machine =
                CodeTableStateMachine::new_with_user_lexicon(bundle, 8, 64, user).unwrap();
            input(&mut machine, "un");
            machine.all_candidates().to_vec()
        }));
    }
    let first = joins.remove(0).join().unwrap();
    for join in joins {
        assert_eq!(join.join().unwrap(), first);
    }
}

#[test]
fn selecting_candidate_clears_composition_without_implicit_extra_commit() {
    let mut machine = state(5, 64);
    input(&mut machine, "un");
    let selected = machine.select_current_page(0).unwrap();
    assert_eq!(
        selected,
        code_table_runtime::CodeTableSelection::CommitText("核心精确甲".to_owned())
    );
    assert!(machine.raw_code().is_empty());
    assert!(machine.current_candidates().is_empty());
}

#[test]
fn unknown_enabled_category_is_diagnostic() {
    let bundle = loaded_bundle();
    let error = bundle
        .validate_enabled_categories(&["missing".into()])
        .unwrap_err();
    assert_eq!(error.kind, CodeTableErrorKind::MissingCategory);
    assert_eq!(error.category_id.as_deref(), Some("missing"));
}

#[test]
fn missing_bundle_file_is_diagnostic() {
    let path = std::env::temp_dir().join("definitely-missing-code-table-runtime.bundle");
    let error = CodeTableBundle::load_file(path).unwrap_err();
    assert_eq!(error.kind, CodeTableErrorKind::ResourceMissing);
}

#[test]
fn category_contract_normalizes_order_duplicates_and_required_core() {
    let bundle = loaded_bundle();
    let snapshot = CategorySelectionSnapshot::from_requested(
        &bundle,
        &[
            "phrases".to_owned(),
            "core".to_owned(),
            "phrases".to_owned(),
        ],
    )
    .unwrap();

    assert_eq!(snapshot.schema_version(), CATEGORY_SCHEMA_VERSION);
    assert_eq!(snapshot.enabled_category_ids(), ["core", "phrases"]);
    assert_eq!(
        snapshot
            .definitions()
            .iter()
            .map(|definition| definition.id.as_str())
            .collect::<Vec<_>>(),
        ["core", "phrases"]
    );
    assert_eq!(snapshot.definitions()[0].kind, CategoryKind::Primary);
    assert!(snapshot.definitions()[0].required);
    assert!(!snapshot.definitions()[0].user_toggleable);
}

#[test]
fn empty_category_selection_restores_only_required_categories() {
    let bundle = loaded_bundle();
    let snapshot = CategorySelectionSnapshot::from_requested(&bundle, &[]).unwrap();
    assert_eq!(snapshot.enabled_category_ids(), ["core"]);
}

#[test]
fn failed_category_update_preserves_old_snapshot_and_candidates() {
    let mut machine = state(8, 64);
    input(&mut machine, "un");
    let before = machine.all_candidates().to_vec();
    let before_selection = machine.category_selection_snapshot();

    let error = machine
        .set_enabled_categories(vec!["unknown-category".to_owned()])
        .unwrap_err();

    assert_eq!(error.kind, CodeTableErrorKind::MissingCategory);
    assert_eq!(machine.category_selection_snapshot(), before_selection);
    assert_eq!(machine.all_candidates(), before);
    assert_eq!(machine.raw_code(), "un");
}

#[test]
fn category_update_preserves_raw_input_resets_page_and_requeries() {
    let mut machine = state(1, 64);
    input(&mut machine, "un");
    machine.next_page().unwrap();
    assert_eq!(machine.current_page(), 1);

    machine
        .set_enabled_categories(vec!["core".to_owned()])
        .unwrap();

    assert_eq!(machine.raw_code(), "un");
    assert_eq!(machine.current_page(), 0);
    assert!(machine
        .all_candidates()
        .iter()
        .all(|candidate| candidate.category_id == "core"));
}

#[test]
fn continuation_and_unique_exact_queries_use_enabled_categories() {
    let specs = vec![
        TableSpec {
            id: "core",
            order: 10,
            enabled: true,
            guide: false,
            entries: vec![("核心精确", "a")],
        },
        TableSpec {
            id: "phrases",
            order: 20,
            enabled: true,
            guide: false,
            entries: vec![("扩展精确", "a"), ("扩展后续", "ab")],
        },
    ];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "a");

    assert!(machine.has_valid_continuation());
    assert_eq!(machine.exact_candidate_count(), 2);
    assert!(!machine.is_unique_exact_match());

    machine
        .set_enabled_categories(vec!["core".to_owned()])
        .unwrap();
    assert!(!machine.has_valid_continuation());
    assert_eq!(machine.exact_candidate_count(), 1);
    assert!(machine.is_unique_exact_match());
    assert!(machine
        .current_candidates()
        .iter()
        .all(|candidate| { candidate.text == "核心精确" && candidate.category_id == "core" }));
}

#[test]
fn user_candidates_remain_in_user_layer_when_system_category_is_disabled() {
    let bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(
            &[
                TableSpec {
                    id: "core",
                    order: 10,
                    enabled: true,
                    guide: false,
                    entries: vec![("核心", "a")],
                },
                TableSpec {
                    id: "phrases",
                    order: 20,
                    enabled: true,
                    guide: false,
                    entries: vec![("扩展", "a")],
                },
            ],
            &guide_spec(),
        ))
        .unwrap(),
    );
    let mut machine =
        CodeTableStateMachine::new_with_user_lexicon(bundle, 8, 64, snapshot("用户新增\ta\n"))
            .unwrap();
    input(&mut machine, "a");
    machine
        .set_enabled_categories(vec!["core".to_owned()])
        .unwrap();

    assert!(machine
        .all_candidates()
        .iter()
        .any(|candidate| candidate.text == "用户新增" && candidate.category_id == "user-lexicon"));
    assert!(machine
        .all_candidates()
        .iter()
        .all(|candidate| candidate.category_id != "phrases"));
}

#[test]
fn stage11_6_7_unique_four_code_auto_commit_clears_composition() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("唯一候选", "abcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();

    input(&mut machine, "abc");
    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("唯一候选"));
    assert_eq!(machine.input_state(), CodeTableInputState::Idle);
    assert!(machine.raw_code().is_empty());
    assert!(machine.all_candidates().is_empty());
}

#[test]
fn stage11_6_7_valid_longer_code_blocks_unique_four_code_auto_commit() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("唯一候选", "abcd"), ("有效后续", "abcde")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();

    input(&mut machine, "abcd");

    assert_eq!(machine.input_state(), CodeTableInputState::NormalCode);
    assert_eq!(machine.raw_code(), "abcd");
    assert_eq!(machine.all_candidates().len(), 1);
    assert!(machine.has_valid_continuation());
}

#[test]
fn ok_spelling_continues_past_four_codes_and_commits_at_six_or_eight() {
    let specs = vec![
        TableSpec {
            id: "core",
            order: 10,
            enabled: true,
            guide: false,
            entries: vec![("普通四码", "okab")],
        },
        TableSpec {
            id: "ok-spelling",
            order: 20,
            enabled: true,
            guide: false,
            entries: vec![("六位拼字", "okabcd"), ("八位拼字", "okefghij")],
        },
    ];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());

    let mut six = CodeTableStateMachine::new(Arc::clone(&bundle), 8, 64).unwrap();
    input(&mut six, "okab");
    assert_eq!(six.raw_code(), "okab");
    assert!(six.has_valid_continuation());
    let fifth = six.process_key('c').unwrap();
    assert!(fifth.commit_text.is_none());
    assert_eq!(six.raw_code(), "okabc");
    let sixth = six.process_key('d').unwrap();
    assert_eq!(sixth.commit_text.as_deref(), Some("六位拼字"));
    assert!(six.raw_code().is_empty());

    let mut eight = CodeTableStateMachine::new(Arc::clone(&bundle), 8, 64).unwrap();
    input(&mut eight, "okefgh");
    assert_eq!(eight.raw_code(), "okefgh");
    input(&mut eight, "i");
    let eighth = eight.process_key('j').unwrap();
    assert_eq!(eighth.commit_text.as_deref(), Some("八位拼字"));
    assert!(eight.raw_code().is_empty());

    let mut disabled = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    disabled
        .set_enabled_categories(vec!["core".to_owned()])
        .unwrap();
    input(&mut disabled, "oka");
    let fourth = disabled.process_key('b').unwrap();
    assert_eq!(fourth.commit_text.as_deref(), Some("普通四码"));
    assert!(disabled.raw_code().is_empty());
    let replayed = disabled.process_key('c').unwrap();
    assert!(replayed.commit_text.is_none());
    assert_eq!(disabled.raw_code(), "c");
}

#[test]
fn stage11_6_7_fifth_key_starts_new_segment_exactly_once() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![
            ("旧段首选", "abcd"),
            ("旧段次选", "abcd"),
            ("新段候选", "e"),
        ],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abcd");

    let outcome = machine.process_key('e').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("旧段首选"));
    assert_eq!(machine.input_state(), CodeTableInputState::NormalCode);
    assert_eq!(machine.raw_code(), "e");
    assert_eq!(machine.all_candidates().len(), 1);
    assert_eq!(machine.all_candidates()[0].text, "新段候选");
}

#[test]
fn stage11_6_7_empty_code_at_frozen_length_clears_composition() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("其他候选", "aaaa")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();

    input(&mut machine, "zzz");
    let outcome = machine.process_key('z').unwrap();

    assert!(outcome.commit_text.is_none());
    assert_eq!(machine.input_state(), CodeTableInputState::Idle);
    assert!(machine.raw_code().is_empty());
    assert!(machine.all_candidates().is_empty());
}

#[test]
fn stage11_6_7_forward_empty_code_split_commits_longest_exact_prefix() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("左段候选", "ab"), ("右段候选", "cd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("左段候选"));
    assert_eq!(machine.raw_code(), "cd");
    assert_eq!(machine.all_candidates()[0].text, "右段候选");
}

#[test]
fn stage11_6_7_reverse_empty_code_split_preserves_order_with_literal_left_segment() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("合法右后缀", "bcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "zbc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("z"));
    assert_eq!(machine.raw_code(), "bcd");
    assert_eq!(machine.all_candidates()[0].text, "合法右后缀");
}

#[test]
fn stage11_6_7_forward_split_wins_when_both_directions_are_possible() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("正向首选", "ab"), ("反向后缀", "bcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("正向首选"));
    assert_eq!(machine.raw_code(), "cd");
}

#[test]
fn stage11_6_7_split_tie_breakers_choose_longest_prefix_or_suffix() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![
            ("短前缀", "a"),
            ("最长前缀", "abc"),
            ("短后缀", "d"),
            ("最长后缀", "bcd"),
        ],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut forward = CodeTableStateMachine::new(Arc::clone(&bundle), 8, 64).unwrap();
    input(&mut forward, "abc");

    let forward_outcome = forward.process_key('d').unwrap();

    assert_eq!(forward_outcome.commit_text.as_deref(), Some("最长前缀"));
    assert_eq!(forward.raw_code(), "d");

    let reverse_specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("短后缀", "cd"), ("最长后缀", "bcd")],
    }];
    let reverse_bundle = Arc::new(
        CodeTableBundle::load_bytes(&bundle_bytes(&reverse_specs, &guide_spec())).unwrap(),
    );
    let mut reverse = CodeTableStateMachine::new(reverse_bundle, 8, 64).unwrap();
    input(&mut reverse, "zbc");

    let reverse_outcome = reverse.process_key('d').unwrap();

    assert_eq!(reverse_outcome.commit_text.as_deref(), Some("z"));
    assert_eq!(reverse.raw_code(), "bcd");
    assert_eq!(reverse.all_candidates()[0].text, "最长后缀");
}

#[test]
fn stage11_6_7_user_delete_can_change_forward_split_into_reverse_split() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("被删左段", "ab"), ("保留右段", "cd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine =
        CodeTableStateMachine::new_with_user_lexicon(bundle, 8, 64, snapshot("被删左段\tab#删\n"))
            .unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("ab"));
    assert_eq!(machine.raw_code(), "cd");
    assert_eq!(machine.all_candidates()[0].text, "保留右段");
}

#[test]
fn stage11_6_7_category_snapshot_changes_split_without_mid_operation_reads() {
    let specs = vec![
        TableSpec {
            id: "core",
            order: 10,
            enabled: true,
            guide: false,
            entries: vec![("右段", "cd")],
        },
        TableSpec {
            id: "phrases",
            order: 20,
            enabled: true,
            guide: false,
            entries: vec![("分类左段", "ab")],
        },
    ];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut enabled = CodeTableStateMachine::new(Arc::clone(&bundle), 8, 64).unwrap();
    input(&mut enabled, "abc");
    let enabled_outcome = enabled.process_key('d').unwrap();
    assert_eq!(enabled_outcome.commit_text.as_deref(), Some("分类左段"));

    let mut core_only = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    core_only
        .set_enabled_categories(vec!["core".to_owned()])
        .unwrap();
    input(&mut core_only, "abc");
    let core_outcome = core_only.process_key('d').unwrap();
    assert_eq!(core_outcome.commit_text.as_deref(), Some("ab"));
    assert_eq!(core_only.raw_code(), "cd");
}

#[test]
fn stage11_6_7_deleted_reverse_suffix_falls_back_to_safe_clear() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("被删后缀", "bcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine =
        CodeTableStateMachine::new_with_user_lexicon(bundle, 8, 64, snapshot("被删后缀\tbcd#删\n"))
            .unwrap();
    input(&mut machine, "zbc");

    let outcome = machine.process_key('d').unwrap();

    assert!(outcome.commit_text.is_none());
    assert!(machine.raw_code().is_empty());
    assert!(machine.all_candidates().is_empty());
}

#[test]
fn stage11_6_7_multiple_four_code_candidates_remain_composing() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("候选甲", "abcd"), ("候选乙", "abcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert!(outcome.commit_text.is_none());
    assert_eq!(machine.raw_code(), "abcd");
    assert_eq!(machine.all_candidates().len(), 2);
}

#[test]
fn stage11_6_7_commit_policy_rejects_invalid_or_incoherent_lengths() {
    let zero = CodeTableCommitPolicy::new(0, 4, 4, 64).unwrap_err();
    assert_eq!(zero.kind, CodeTableErrorKind::InvalidCommitPolicy);
    assert_eq!(zero.code(), "invalid_commit_policy");

    let exceeds_max = CodeTableCommitPolicy::new(4, 4, 5, 4).unwrap_err();
    assert_eq!(exceeds_max.kind, CodeTableErrorKind::InvalidCommitPolicy);

    let split_below_empty =
        CodeTableCommitPolicy::new_with_split_limit(4, 4, 4, 64, 3).unwrap_err();
    assert_eq!(
        split_below_empty.kind,
        CodeTableErrorKind::InvalidCommitPolicy
    );

    let split_above_normal =
        CodeTableCommitPolicy::new_with_split_limit(4, 4, 4, 64, 65).unwrap_err();
    assert_eq!(
        split_above_normal.kind,
        CodeTableErrorKind::InvalidCommitPolicy
    );
}

#[test]
fn customer_commit_policy_can_change_only_at_a_clean_boundary() {
    let mut machine = state(8, 64);
    let policy = CodeTableCommitPolicy::new(64, 4, 12, 64).unwrap();
    machine.set_commit_policy(policy).unwrap();
    assert_eq!(machine.commit_policy(), policy);
    machine.process_key('a').unwrap();
    assert!(machine
        .set_commit_policy(CodeTableCommitPolicy::default())
        .is_err());
    assert_eq!(machine.commit_policy(), policy);
}

#[test]
fn stage11_6_7_empty_code_does_not_split_before_frozen_threshold() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("左段", "a"), ("右段", "bc")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();

    input(&mut machine, "abc");

    assert_eq!(machine.raw_code(), "abc");
    assert!(machine.all_candidates().is_empty());
}

#[test]
fn stage11_6_7_split_remainder_is_queried_once_without_second_auto_commit() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![
            ("左段", "abcd"),
            ("阻止提前提交", "abcdx"),
            ("右段", "efgh"),
        ],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let policy = CodeTableCommitPolicy::new_with_split_limit(4, 8, 8, 8, 8).unwrap();
    let mut machine =
        CodeTableStateMachine::new_with_policy(bundle, 8, 64, snapshot(""), policy).unwrap();
    input(&mut machine, "abcdefg");

    let outcome = machine.process_key('h').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("左段"));
    assert_eq!(machine.raw_code(), "efgh");
    assert_eq!(machine.all_candidates().len(), 1);
    assert_eq!(machine.all_candidates()[0].text, "右段");
}

#[test]
fn stage11_6_7_split_scan_limit_fails_closed_without_partial_commit() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("四码后续", "abcde"), ("可切前缀", "ab")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let policy = CodeTableCommitPolicy::new_with_split_limit(8, 8, 4, 8, 4).unwrap();
    let mut machine =
        CodeTableStateMachine::new_with_policy(bundle, 8, 64, snapshot(""), policy).unwrap();
    input(&mut machine, "abcd");

    let outcome = machine.process_key('x').unwrap();

    assert!(outcome.commit_text.is_none());
    assert!(machine.raw_code().is_empty());
    assert!(machine.all_candidates().is_empty());
}

#[test]
fn stage11_6_7_reverse_split_accepts_a_visible_prefix_suffix() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("右段后续", "bcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "zzb");

    let outcome = machine.process_key('c').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("zz"));
    assert_eq!(machine.raw_code(), "bc");
    assert_eq!(machine.all_candidates()[0].text, "右段后续");
}

#[test]
fn stage11_6_7_forward_split_uses_final_user_fixed_first_candidate() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("系统首选", "ab"), ("用户固顶", "ab"), ("右段", "cd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine =
        CodeTableStateMachine::new_with_user_lexicon(bundle, 8, 64, snapshot("用户固顶\tab#固\n"))
            .unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("用户固顶"));
    assert_eq!(machine.raw_code(), "cd");
}

#[test]
fn stage11_6_7_non_bmp_and_long_candidate_auto_commit_without_character_truncation() {
    let long_text: &'static str = Box::leak(format!("𠮷{}", "长".repeat(128)).into_boxed_str());
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![(long_text, "abcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some(long_text));
}

#[test]
fn stage11_6_7_category_update_never_commits_and_next_key_uses_new_snapshot() {
    let specs = vec![
        TableSpec {
            id: "core",
            order: 10,
            enabled: true,
            guide: false,
            entries: vec![("核心候选", "abcd"), ("新段", "e")],
        },
        TableSpec {
            id: "phrases",
            order: 20,
            enabled: true,
            guide: false,
            entries: vec![("短语候选", "abcd"), ("短语后续", "abcde")],
        },
    ];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abcd");
    assert_eq!(machine.all_candidates().len(), 2);

    machine
        .set_enabled_categories(vec!["core".to_owned()])
        .unwrap();

    assert_eq!(machine.raw_code(), "abcd");
    assert_eq!(machine.all_candidates().len(), 1);
    let outcome = machine.process_key('e').unwrap();
    assert_eq!(outcome.commit_text.as_deref(), Some("核心候选"));
    assert_eq!(machine.raw_code(), "e");
}

#[test]
fn stage11_6_7_user_delete_removes_longer_code_from_continuation_decision() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("唯一候选", "abcd"), ("被删后续", "abcde")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new_with_user_lexicon(
        bundle,
        8,
        64,
        snapshot("被删后续\tabcde#删\n"),
    )
    .unwrap();
    input(&mut machine, "abc");

    let outcome = machine.process_key('d').unwrap();

    assert_eq!(outcome.commit_text.as_deref(), Some("唯一候选"));
    assert!(machine.raw_code().is_empty());
}

#[test]
fn stage11_6_7_top_screen_without_old_candidate_still_replays_new_key_once() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("新段候选", "e")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let policy = CodeTableCommitPolicy::new(4, 4, 8, 64).unwrap();
    let mut machine =
        CodeTableStateMachine::new_with_policy(bundle, 8, 64, snapshot(""), policy).unwrap();
    input(&mut machine, "zzzz");
    assert_eq!(machine.raw_code(), "zzzz");
    assert!(machine.all_candidates().is_empty());

    let outcome = machine.process_key('e').unwrap();

    assert!(outcome.commit_text.is_none());
    assert_eq!(machine.raw_code(), "e");
    assert_eq!(machine.all_candidates()[0].text, "新段候选");
}

#[test]
fn stage11_6_7_invalid_fifth_key_does_not_commit_or_mutate_old_segment() {
    let specs = vec![TableSpec {
        id: "core",
        order: 10,
        enabled: true,
        guide: false,
        entries: vec![("旧段甲", "abcd"), ("旧段乙", "abcd")],
    }];
    let bundle =
        Arc::new(CodeTableBundle::load_bytes(&bundle_bytes(&specs, &guide_spec())).unwrap());
    let mut machine = CodeTableStateMachine::new(bundle, 8, 64).unwrap();
    input(&mut machine, "abcd");
    let before = machine.all_candidates().to_vec();

    let error = machine.process_key('1').unwrap_err();

    assert_eq!(error.kind, CodeTableErrorKind::InvalidKey);
    assert_eq!(machine.raw_code(), "abcd");
    assert_eq!(machine.all_candidates(), before);
}

#[test]
fn stage11_6_7_deterministic_mixed_sequences_preserve_commit_and_length_invariants() {
    for seed in 0_u64..32 {
        let mut machine = state(3, 64);
        let mut value = seed.wrapping_add(1);
        for _ in 0..512 {
            value = value
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            match value % 13 {
                0 => machine.backspace(),
                1 => machine.reset(),
                2 => {
                    let _ = machine.process_key(';');
                }
                3 => {
                    let _ = machine.next_page();
                }
                4 => {
                    let _ = machine.previous_page();
                }
                _ => {
                    let key = char::from(b'a' + ((value >> 8) % 26) as u8);
                    if let Ok(outcome) = machine.process_key(key) {
                        assert!(outcome
                            .commit_text
                            .as_ref()
                            .is_none_or(|text| !text.is_empty()));
                    }
                }
            }
            assert!(machine.raw_code().len() <= 64);
            assert!(machine
                .raw_code()
                .bytes()
                .all(|byte| byte.is_ascii_lowercase()));
            assert!(machine.current_page() == 0 || !machine.current_candidates().is_empty());
        }
    }
}
