use std::collections::{BTreeMap, BTreeSet};

use pinyin_syllable::{all_syllables, normalize_syllable};
use shuangpin_parser::{ParseStatus, ShuangpinParser};

const INITIALS: &[(char, &str)] = &[
    ('b', "b"),
    ('p', "p"),
    ('m', "m"),
    ('f', "f"),
    ('d', "d"),
    ('t', "t"),
    ('n', "n"),
    ('l', "l"),
    ('g', "g"),
    ('k', "k"),
    ('h', "h"),
    ('j', "j"),
    ('q', "q"),
    ('x', "x"),
    ('r', "r"),
    ('z', "z"),
    ('c', "c"),
    ('s', "s"),
    ('y', "y"),
    ('w', "w"),
    ('v', "zh"),
    ('i', "ch"),
    ('u', "sh"),
];

const FINALS: &[(char, &[&str])] = &[
    ('a', &["a"]),
    ('b', &["in"]),
    ('c', &["ao"]),
    ('d', &["ai"]),
    ('e', &["e"]),
    ('f', &["en"]),
    ('g', &["eng"]),
    ('h', &["ang"]),
    ('i', &["i"]),
    ('j', &["an"]),
    ('k', &["ing", "uai"]),
    ('l', &["iang", "uang"]),
    ('m', &["ian"]),
    ('n', &["iao"]),
    ('o', &["o", "uo"]),
    ('p', &["ie"]),
    ('q', &["iu"]),
    ('r', &["er", "uan"]),
    ('s', &["ong", "iong"]),
    ('t', &["ue", "ve"]),
    ('u', &["u"]),
    ('v', &["ui", "v"]),
    ('w', &["ei"]),
    ('x', &["ia", "ua"]),
    ('y', &["un"]),
    ('z', &["ou"]),
];

// These values are intentionally frozen in the parser test instead of read
// from schemas/xiaohe.json. A wrong schema edit must disagree with this oracle.
const ZERO_INITIALS: &[(&str, &str)] = &[
    ("aa", "a"),
    ("oo", "o"),
    ("ee", "e"),
    ("ai", "ai"),
    ("an", "an"),
    ("ao", "ao"),
    ("ei", "ei"),
    ("en", "en"),
    ("er", "er"),
    ("ou", "ou"),
    ("ad", "ai"),
    ("aj", "an"),
    ("ah", "ang"),
    ("ac", "ao"),
    ("ew", "ei"),
    ("ef", "en"),
    ("eg", "eng"),
    ("oz", "ou"),
];

const SPECIALS: &[(&str, &str)] = &[
    ("vi", "zhi"),
    ("ii", "chi"),
    ("ui", "shi"),
    ("ri", "ri"),
    ("zi", "zi"),
    ("ci", "ci"),
    ("si", "si"),
];

#[test]
fn every_possible_xiaohe_double_key_matches_the_frozen_legal_readings() {
    let expected = expected_code_to_readings();
    let actual = parser_code_to_readings();

    for first in 'a'..='z' {
        for second in 'a'..='z' {
            let code = format!("{first}{second}");
            assert_eq!(
                actual.get(&code).cloned().unwrap_or_default(),
                expected.get(&code).cloned().unwrap_or_default(),
                "Xiaohe double-key mapping mismatch for {code}"
            );
        }
    }
    assert_eq!(actual, expected);
}

#[test]
fn every_supported_reading_has_complete_reverse_code_coverage() {
    let expected_reverse = reverse(&expected_code_to_readings());
    let actual_reverse = reverse(&parser_code_to_readings());

    assert_eq!(actual_reverse, expected_reverse);

    let inventory = all_syllables().collect::<BTreeSet<_>>();
    let covered = actual_reverse
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    assert_eq!(
        inventory.difference(&covered).copied().collect::<Vec<_>>(),
        vec!["n", "ng"],
        "only the two standalone nasal readings are outside Xiaohe's two-key contract"
    );
}

fn expected_code_to_readings() -> BTreeMap<String, BTreeSet<String>> {
    let mut expected = BTreeMap::<String, BTreeSet<String>>::new();
    for (initial_key, initial) in INITIALS {
        for (final_key, finals) in FINALS {
            for final_part in *finals {
                if let Ok(syllable) = normalize_syllable(&format!("{initial}{final_part}")) {
                    expected
                        .entry(format!("{initial_key}{final_key}"))
                        .or_default()
                        .insert(syllable);
                }
            }
        }
    }
    for (code, syllable) in ZERO_INITIALS.iter().chain(SPECIALS) {
        expected
            .entry((*code).to_owned())
            .or_default()
            .insert((*syllable).to_owned());
    }
    expected
}

fn parser_code_to_readings() -> BTreeMap<String, BTreeSet<String>> {
    let mut parser = ShuangpinParser::xiaohe().expect("load Xiaohe schema");
    let mut actual = BTreeMap::new();
    for first in 'a'..='z' {
        for second in 'a'..='z' {
            parser.reset();
            let code = format!("{first}{second}");
            let result = parser.process_str(&code);
            let readings = result
                .syllables
                .iter()
                .map(|syllable| syllable.syllable.clone())
                .collect::<BTreeSet<_>>();
            if readings.is_empty() {
                assert_eq!(result.status, ParseStatus::Invalid, "code={code}");
            } else {
                assert!(
                    matches!(
                        result.status,
                        ParseStatus::Complete | ParseStatus::Ambiguous
                    ),
                    "code={code}, status={:?}",
                    result.status
                );
                assert_eq!(result.logical_syllable_count, 1, "code={code}");
                actual.insert(code, readings);
            }
        }
    }
    actual
}

fn reverse(mappings: &BTreeMap<String, BTreeSet<String>>) -> BTreeMap<String, BTreeSet<String>> {
    let mut reversed = BTreeMap::<String, BTreeSet<String>>::new();
    for (code, readings) in mappings {
        for reading in readings {
            reversed
                .entry(reading.clone())
                .or_default()
                .insert(code.clone());
        }
    }
    reversed
}
