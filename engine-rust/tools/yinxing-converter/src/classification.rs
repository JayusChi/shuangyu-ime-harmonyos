use std::collections::{BTreeMap, BTreeSet};

use crate::model::{CategoryBuild, UserAction};

/// Applies only conflict accounting frozen by the existing runtime contracts.
/// Records remain physically separated by category; cross-category stable
/// deduplication is performed later by `code-table-runtime` query order.
pub fn account_conflicts(categories: &mut [CategoryBuild]) {
    let mut system_keys = BTreeMap::<(String, String), String>::new();
    for category in categories.iter_mut() {
        for record in &category.system_records {
            let key = (record.code.clone(), record.text.clone());
            if system_keys
                .insert(key, category.spec.category_id.clone())
                .is_some()
            {
                category.stats.conflicts += 1;
            }
        }
    }

    let all_system = system_keys.keys().cloned().collect::<BTreeSet<_>>();
    let mut user_keys = BTreeMap::<(String, String), UserAction>::new();
    for category in categories {
        for rule in &category.user_rules {
            let key = (rule.code.clone(), rule.text.clone());
            if all_system.contains(&key) {
                category.stats.conflicts += 1;
            }
            if user_keys.insert(key, rule.action.clone()).is_some() {
                // Existing user-lexicon contract resolves this deterministically
                // as later-rule-wins; the collision remains visible in reports.
                category.stats.conflicts += 1;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{CategorySpec, CategoryStatistics, SystemRecord, UserRuleRecord};

    fn category(id: &str) -> CategoryBuild {
        CategoryBuild {
            spec: CategorySpec {
                category_id: id.into(),
                display_name: id.into(),
                role: "role".into(),
                order: 0,
                source_path: format!("root/{id}.txt"),
                source_file_id: id.into(),
                source_size: 0,
                source_sha256: "0".repeat(64),
                source_decision: "TRANSFORM".into(),
                default_enabled: true,
            },
            system_records: Vec::new(),
            user_rules: Vec::new(),
            actions: Vec::new(),
            rejected: Vec::new(),
            stats: CategoryStatistics::default(),
        }
    }

    fn system(category: &str) -> SystemRecord {
        SystemRecord {
            text: "同词".into(),
            code: "abcd".into(),
            source_file_id: category.into(),
            source_file: String::new(),
            source_sha256: String::new(),
            category_id: category.into(),
            physical_line: 1,
            source_order: 0,
            line_digest: String::new(),
        }
    }

    fn rule(category: &str, action: UserAction) -> UserRuleRecord {
        UserRuleRecord {
            text: "同词".into(),
            display_text: None,
            code: "abcd".into(),
            action,
            source_file_id: category.into(),
            source_file: String::new(),
            source_sha256: String::new(),
            category_id: category.into(),
            physical_line: 2,
            source_order: 0,
            line_digest: String::new(),
        }
    }

    #[test]
    fn counts_cross_category_and_user_collisions_without_merging() {
        let mut values = [category("a"), category("b")];
        values[0].system_records.push(system("a"));
        values[1].system_records.push(system("b"));
        values[1].user_rules.push(rule("b", UserAction::Delete));
        values[1].user_rules.push(rule("b", UserAction::Fixed));
        account_conflicts(&mut values);
        assert_eq!(
            values[0].system_records.len() + values[1].system_records.len(),
            2
        );
        assert_eq!(values[1].stats.conflicts, 4);
    }
}
