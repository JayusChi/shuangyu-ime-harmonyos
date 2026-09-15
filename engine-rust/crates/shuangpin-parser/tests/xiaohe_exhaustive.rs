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
fn every_impossible_pair_of_known_initials_becomes_two_initial_slots() {
    let expected_full = expected_code_to_readings();
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    for (left_key, left) in INITIALS {
        for (right_key, right) in INITIALS {
            let code = format!("{left_key}{right_key}");
            if expected_full.contains_key(&code) {
                continue;
            }
            parser.reset();
            let result = parser.process_str(&code);
            assert_eq!(result.status, ParseStatus::Complete, "code={code}");
            assert_eq!(result.logical_syllable_count, 2, "code={code}");
            assert_eq!(
                result
                    .syllables
                    .iter()
                    .map(|slot| slot.syllable.as_str())
                    .collect::<Vec<_>>(),
                vec![*left, *right],
                "code={code}"
            );
            let pending = parser.backspace();
            assert_eq!(pending.pending_code, left_key.to_string());
            assert_eq!(parser.pending_initial(), Some(*left));
        }
    }
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
    let expected_full = expected_code_to_readings();
    let mut parser = ShuangpinParser::xiaohe().expect("load Xiaohe schema");
    let mut actual = BTreeMap::new();
    for first in 'a'..='z' {
        for second in 'a'..='z' {
            parser.reset();
            let code = format!("{first}{second}");
            let result = parser.process_str(&code);
            if result.logical_syllable_count == 2 {
                assert_eq!(result.status, ParseStatus::Complete, "code={code}");
                assert_eq!(result.syllables.len(), 2, "code={code}");
                assert!(
                    !expected_full.contains_key(&code),
                    "legal pair must win: {code}"
                );
                for (slot, key) in result.syllables.iter().zip([first, second]) {
                    let expected = INITIALS
                        .iter()
                        .find(|(initial_key, _)| *initial_key == key)
                        .expect("fallback key must be a known initial")
                        .1;
                    assert_eq!(slot.syllable, expected, "code={code}");
                    assert_eq!(slot.raw_code, key.to_string());
                    assert!(slot.final_part.is_empty());
                }
                continue;
            }
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

#[test]
fn pending_zero_initial_vowels_remain_editable_and_complete_as_normal_pairs() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    for (key, reading) in [('a', "a"), ('e', "e"), ('o', "o")] {
        parser.reset();
        let pending = parser.process_str(&format!("ni{key}"));
        assert_eq!(pending.pending_code, key.to_string());
        assert_eq!(pending.logical_syllable_count, 1);
        assert_eq!(parser.pending_initial(), Some(reading));
        let complete = parser.process_str(&key.to_string());
        assert!(complete.pending_code.is_empty());
        assert_eq!(complete.logical_syllable_count, 2);
        assert_eq!(complete.syllables.last().unwrap().syllable, reading);
        assert_eq!(parser.pending_initial(), None);
        parser.backspace();
        assert_eq!(parser.pending_initial(), Some(reading));
    }
}
