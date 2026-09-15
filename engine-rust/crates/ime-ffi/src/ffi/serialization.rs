fn hex(bytes: &[u8; 32]) -> String {
    let mut output = String::with_capacity(64);
    for byte in bytes {
        output.push_str(&format!("{byte:02x}"));
    }
    output
}

fn category_config_json(snapshot: &code_table_runtime::CategorySelectionSnapshot) -> String {
    let categories = snapshot
        .definitions()
        .iter()
        .map(|definition| {
            format!(
                "{{\"id\":\"{}\",\"displayName\":\"{}\",\"kind\":\"{}\",\"order\":{},\"defaultEnabled\":{},\"required\":{},\"userToggleable\":{},\"authoritativeFile\":\"{}\",\"entryCount\":{},\"sha256\":\"{}\"}}",
                escape_json(&definition.id),
                escape_json(&definition.display_name),
                definition.kind.as_str(),
                definition.order,
                definition.default_enabled,
                definition.required,
                definition.user_toggleable,
                escape_json(&definition.authoritative_file),
                definition.entry_count,
                hex(&definition.sha256),
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    let enabled = snapshot
        .enabled_category_ids()
        .iter()
        .map(|id| format!("\"{}\"", escape_json(id)))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "{{\"schemaVersion\":{},\"categories\":[{}],\"enabledCategoryIds\":[{}]}}",
        snapshot.schema_version(),
        categories,
        enabled
    )
}

fn association_suggestions_json(suggestions: &[String]) -> String {
    let values = suggestions
        .iter()
        .map(|text| format!("\"{}\"", escape_json(text)))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{}]", values)
}

fn user_lexicon_document_json(report: &UserLexiconLoadReport) -> String {
    let snapshot = &report.snapshot;
    let entries = snapshot
        .entries()
        .iter()
        .map(|entry| {
            let (action, position) = match entry.action {
                UserLexiconAction::Add => ("ADD", 0),
                UserLexiconAction::Direct => ("DIRECT", 0),
                UserLexiconAction::OpenUrl => ("OPEN_URL", 0),
                UserLexiconAction::OpenDirectory => ("OPEN_DIRECTORY", 0),
                UserLexiconAction::Delete => ("DELETE", 0),
                UserLexiconAction::Fixed => ("FIXED", 0),
                UserLexiconAction::Position(position) => ("POSITION", position),
            };
            format!(
                "{{\"id\":\"{}\",\"text\":\"{}\",\"displayText\":\"{}\",\"code\":\"{}\",\"action\":\"{}\",\"position\":{},\"sourceOrder\":{}}}",
                entry.stable_id(),
                escape_json(&entry.text),
                escape_json(entry.display_text.as_deref().unwrap_or("")),
                escape_json(&entry.code),
                action,
                position,
                entry.source_order,
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    let stats = snapshot.stats();
    format!(
        "{{\"success\":true,\"errorCode\":\"\",\"errorLine\":0,\"errorField\":\"\",\"message\":\"\",\"warningCode\":\"{}\",\"revision\":\"{}\",\"entries\":[{}],\"stats\":{{\"accepted\":{},\"effective\":{},\"added\":{},\"deleted\":{},\"fixed\":{},\"positioned\":{}}}}}",
        escape_json(&report.warning_code),
        snapshot.revision(),
        entries,
        stats.accepted,
        stats.effective,
        stats.added,
        stats.deleted,
        stats.fixed,
        stats.positioned,
    )
}

fn user_lexicon_error_json(error: &UserLexiconError) -> String {
    format!(
        "{{\"success\":false,\"errorCode\":\"{}\",\"errorLine\":{},\"errorField\":\"{}\",\"message\":\"{}\",\"warningCode\":\"\",\"revision\":\"\",\"entries\":[],\"stats\":{{\"accepted\":0,\"effective\":0,\"added\":0,\"deleted\":0,\"fixed\":0,\"positioned\":0}}}}",
        error.code(),
        error.line,
        error.field.as_str(),
        escape_json(&error.to_string()),
    )
}

fn saved_user_lexicon_report(snapshot: UserLexiconSnapshot) -> UserLexiconLoadReport {
    UserLexiconLoadReport {
        action: user_lexicon::UserLexiconLoadAction::LoadedPrimary,
        snapshot,
        warning_code: String::new(),
    }
}
