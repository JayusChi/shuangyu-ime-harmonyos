use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use crate::eval_json::{parse, serialize, JsonValue};
use crate::eval_sha256;

pub(crate) const RAW_INPUT_LENGTH_BANDS: [&str; 5] = ["01-04", "05-08", "09-12", "13-20", "21+"];
const SCHEMA_VERSION: &str = "quanpin-anonymous-input-distribution/1";
const SOURCE_KIND: &str = "opt-in-local-aggregate";
const MINIMUM_TOTAL_EVENTS: u64 = 100;
const MINIMUM_BUCKET_THRESHOLD: u64 = 20;

#[derive(Clone, Debug)]
pub(crate) struct AnonymousInputDistribution {
    pub(crate) sha256: String,
    pub(crate) total_events: u64,
    pub(crate) minimum_bucket_count: u64,
    pub(crate) start_date: String,
    pub(crate) end_date: String,
    pub(crate) length_bands: BTreeMap<String, u64>,
}

pub(crate) fn load(path: &Path) -> Result<AnonymousInputDistribution, String> {
    let bytes = fs::read(path).map_err(|error| {
        format!(
            "cannot read anonymous distribution {}: {error}",
            path.display()
        )
    })?;
    let sha256 = eval_sha256::hex(&bytes);
    let root = parse(&bytes).map_err(|error| format!("anonymous distribution JSON: {error}"))?;
    let object = required_object(&root, "root")?;
    reject_unknown_keys(
        object,
        &[
            "schemaVersion",
            "sourceKind",
            "collectionWindow",
            "privacyContract",
            "totalEvents",
            "rawInputLengthBands",
        ],
        "root",
    )?;
    required_string(object, "schemaVersion", "root", SCHEMA_VERSION)?;
    required_string(object, "sourceKind", "root", SOURCE_KIND)?;

    let window = required_child_object(object, "collectionWindow", "root")?;
    reject_unknown_keys(window, &["startDate", "endDate"], "collectionWindow")?;
    let start_date = string_value(window, "startDate", "collectionWindow")?;
    let end_date = string_value(window, "endDate", "collectionWindow")?;
    validate_date(&start_date, "startDate")?;
    validate_date(&end_date, "endDate")?;
    if start_date > end_date {
        return Err("anonymous distribution collectionWindow starts after it ends".to_owned());
    }

    let privacy = required_child_object(object, "privacyContract", "root")?;
    reject_unknown_keys(
        privacy,
        &[
            "aggregationOnly",
            "optIn",
            "containsRawInput",
            "containsCandidateText",
            "containsEditorText",
            "containsApplicationIdentity",
            "containsUserIdentifier",
            "minimumBucketCount",
        ],
        "privacyContract",
    )?;
    required_bool(privacy, "aggregationOnly", true)?;
    required_bool(privacy, "optIn", true)?;
    required_bool(privacy, "containsRawInput", false)?;
    required_bool(privacy, "containsCandidateText", false)?;
    required_bool(privacy, "containsEditorText", false)?;
    required_bool(privacy, "containsApplicationIdentity", false)?;
    required_bool(privacy, "containsUserIdentifier", false)?;
    let minimum_bucket_count = u64_value(privacy, "minimumBucketCount", "privacyContract")?;
    if minimum_bucket_count < MINIMUM_BUCKET_THRESHOLD {
        return Err(format!(
            "anonymous distribution minimumBucketCount must be at least {MINIMUM_BUCKET_THRESHOLD}"
        ));
    }

    let total_events = u64_value(object, "totalEvents", "root")?;
    if total_events < MINIMUM_TOTAL_EVENTS {
        return Err(format!(
            "anonymous distribution requires at least {MINIMUM_TOTAL_EVENTS} aggregate events"
        ));
    }
    let bands = required_child_object(object, "rawInputLengthBands", "root")?;
    reject_unknown_keys(bands, &RAW_INPUT_LENGTH_BANDS, "rawInputLengthBands")?;
    let mut length_bands = BTreeMap::new();
    for band in RAW_INPUT_LENGTH_BANDS {
        let count = u64_value(bands, band, "rawInputLengthBands")?;
        if count > 0 && count < minimum_bucket_count {
            return Err(format!(
                "anonymous distribution band {band} has {count} events, below minimumBucketCount {minimum_bucket_count}"
            ));
        }
        length_bands.insert(band.to_owned(), count);
    }
    let sum = length_bands.values().copied().sum::<u64>();
    if sum != total_events {
        return Err(format!(
            "anonymous distribution totalEvents is {total_events}, but length bands sum to {sum}"
        ));
    }

    Ok(AnonymousInputDistribution {
        sha256,
        total_events,
        minimum_bucket_count,
        start_date,
        end_date,
        length_bands,
    })
}

pub fn validate(path: &Path) -> Result<String, String> {
    let distribution = load(path)?;
    let json = JsonValue::object([
        (
            "schemaVersion",
            JsonValue::string("quanpin-anonymous-input-distribution-validation/1"),
        ),
        ("valid", JsonValue::Bool(true)),
        ("distributionSha256", JsonValue::string(distribution.sha256)),
        (
            "totalEvents",
            JsonValue::number(distribution.total_events as f64),
        ),
        (
            "minimumBucketCount",
            JsonValue::number(distribution.minimum_bucket_count as f64),
        ),
        (
            "collectionWindow",
            JsonValue::object([
                ("startDate", JsonValue::string(distribution.start_date)),
                ("endDate", JsonValue::string(distribution.end_date)),
            ]),
        ),
        (
            "privacyContract",
            JsonValue::string(
                "opt-in aggregate only; no raw input, candidate/editor text, application identity, or user identifier",
            ),
        ),
    ]);
    String::from_utf8(serialize(&json)).map_err(|error| error.to_string())
}

fn required_object<'a>(
    value: &'a JsonValue,
    context: &str,
) -> Result<&'a BTreeMap<String, JsonValue>, String> {
    value
        .as_object()
        .ok_or_else(|| format!("anonymous distribution {context} must be an object"))
}

fn required_child_object<'a>(
    object: &'a BTreeMap<String, JsonValue>,
    key: &str,
    context: &str,
) -> Result<&'a BTreeMap<String, JsonValue>, String> {
    required_object(
        object
            .get(key)
            .ok_or_else(|| format!("anonymous distribution {context} is missing {key}"))?,
        key,
    )
}

fn reject_unknown_keys(
    object: &BTreeMap<String, JsonValue>,
    allowed: &[&str],
    context: &str,
) -> Result<(), String> {
    let allowed = allowed.iter().copied().collect::<BTreeSet<_>>();
    if let Some(key) = object.keys().find(|key| !allowed.contains(key.as_str())) {
        return Err(format!(
            "anonymous distribution {context} contains unsupported field {key:?}; aggregate schema is closed to prevent user data leakage"
        ));
    }
    Ok(())
}

fn required_string(
    object: &BTreeMap<String, JsonValue>,
    key: &str,
    context: &str,
    expected: &str,
) -> Result<(), String> {
    let actual = string_value(object, key, context)?;
    if actual != expected {
        return Err(format!(
            "anonymous distribution {context}.{key} must be {expected:?}"
        ));
    }
    Ok(())
}

fn string_value(
    object: &BTreeMap<String, JsonValue>,
    key: &str,
    context: &str,
) -> Result<String, String> {
    object
        .get(key)
        .and_then(JsonValue::as_str)
        .map(str::to_owned)
        .ok_or_else(|| format!("anonymous distribution {context}.{key} must be a string"))
}

fn required_bool(
    object: &BTreeMap<String, JsonValue>,
    key: &str,
    expected: bool,
) -> Result<(), String> {
    match object.get(key) {
        Some(JsonValue::Bool(actual)) if *actual == expected => Ok(()),
        _ => Err(format!(
            "anonymous distribution privacyContract.{key} must be {expected}"
        )),
    }
}

fn u64_value(
    object: &BTreeMap<String, JsonValue>,
    key: &str,
    context: &str,
) -> Result<u64, String> {
    object.get(key).and_then(JsonValue::as_u64).ok_or_else(|| {
        format!("anonymous distribution {context}.{key} must be a non-negative integer")
    })
}

fn validate_date(value: &str, field: &str) -> Result<(), String> {
    let bytes = value.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || bytes
            .iter()
            .enumerate()
            .any(|(index, byte)| !matches!(index, 4 | 7) && !byte.is_ascii_digit())
    {
        return Err(format!(
            "anonymous distribution collectionWindow.{field} must use yyyy-MM-dd"
        ));
    }
    let year = value[0..4].parse::<u16>().unwrap_or(0);
    let month = value[5..7].parse::<u8>().unwrap_or(0);
    let day = value[8..10].parse::<u8>().unwrap_or(0);
    if year < 2020 || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return Err(format!(
            "anonymous distribution collectionWindow.{field} is out of range"
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(name: &str) -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "quanpin-anonymous-distribution-{name}-{}-{nonce}.json",
            std::process::id()
        ))
    }

    fn valid_json(extra: &str) -> String {
        format!(
            r#"{{
  "schemaVersion": "{SCHEMA_VERSION}",
  "sourceKind": "{SOURCE_KIND}",
  "collectionWindow": {{ "startDate": "2026-08-01", "endDate": "2026-08-07" }},
  "privacyContract": {{
    "aggregationOnly": true,
    "optIn": true,
    "containsRawInput": false,
    "containsCandidateText": false,
    "containsEditorText": false,
    "containsApplicationIdentity": false,
    "containsUserIdentifier": false,
    "minimumBucketCount": 20
  }},
  "totalEvents": 100,
  "rawInputLengthBands": {{ "01-04": 20, "05-08": 20, "09-12": 20, "13-20": 20, "21+": 20 }}{extra}
}}"#
        )
    }

    #[test]
    fn accepts_closed_aggregate_schema() {
        let path = temp_path("valid");
        fs::write(&path, valid_json("")).expect("write fixture");
        let value = load(&path).expect("valid aggregate");
        assert_eq!(value.total_events, 100);
        assert_eq!(value.length_bands["09-12"], 20);
        fs::remove_file(path).expect("remove fixture");
    }

    #[test]
    fn rejects_any_field_that_could_smuggle_raw_user_data() {
        let path = temp_path("raw");
        fs::write(&path, valid_json(r#", "rawInputs": ["nihao"]"#)).expect("write fixture");
        let error = load(&path).expect_err("closed schema must reject raw data");
        assert!(error.contains("unsupported field"));
        fs::remove_file(path).expect("remove fixture");
    }

    #[test]
    fn rejects_small_buckets_and_inconsistent_totals() {
        let path = temp_path("small");
        let content =
            valid_json("").replace(r#""01-04": 20, "05-08": 20"#, r#""01-04": 19, "05-08": 20"#);
        fs::write(&path, content).expect("write fixture");
        let error = load(&path).expect_err("small bucket must fail");
        assert!(error.contains("below minimumBucketCount"));
        fs::remove_file(path).expect("remove fixture");
    }
}
