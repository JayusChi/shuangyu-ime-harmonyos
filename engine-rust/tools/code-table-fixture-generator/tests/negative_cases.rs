use std::fs;
use std::path::PathBuf;

use code_table_fixture_generator::{validate_table_bytes, FixtureError};

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/code-table/invalid/cases.tsv")
}

#[test]
fn every_declared_negative_fixture_has_a_precise_diagnostic() {
    let text = fs::read_to_string(fixture_path()).unwrap();
    let mut executed = 0;
    for line in text.lines().skip(1) {
        let fields = line.split('\t').collect::<Vec<_>>();
        assert_eq!(fields.len(), 5, "invalid negative fixture row: {line}");
        let bytes = decode(fields[1]);
        let error = validate_table_bytes(&bytes, fields[0]).unwrap_err();
        let FixtureError::Diagnostic(diagnostic) = error else {
            panic!("expected diagnostic for {}", fields[0]);
        };
        assert_eq!(diagnostic.code, fields[2]);
        assert_eq!(diagnostic.line.to_string(), fields[3]);
        assert_eq!(diagnostic.field, fields[4]);
        assert_eq!(diagnostic.file, fields[0]);
        assert!(!diagnostic.reason.is_empty());
        executed += 1;
    }
    assert_eq!(executed, 14);
}

fn decode(value: &str) -> Vec<u8> {
    let expanded = value
        .replace("{65xa}", &"a".repeat(65))
        .replace("{33x测}", &"测".repeat(33));
    let chars = expanded.chars().collect::<Vec<_>>();
    let mut output = Vec::new();
    let mut index = 0;
    while index < chars.len() {
        if chars[index] != '\\' {
            let mut bytes = [0_u8; 4];
            output.extend_from_slice(chars[index].encode_utf8(&mut bytes).as_bytes());
            index += 1;
            continue;
        }
        index += 1;
        match chars.get(index).copied().expect("complete fixture escape") {
            't' => output.push(b'\t'),
            'n' => output.push(b'\n'),
            'r' => output.push(b'\r'),
            'x' => {
                let high = chars[index + 1];
                let low = chars[index + 2];
                let hex = format!("{high}{low}");
                output.push(u8::from_str_radix(&hex, 16).unwrap());
                index += 2;
            }
            other => panic!("unsupported fixture escape: {other}"),
        }
        index += 1;
    }
    output
}
