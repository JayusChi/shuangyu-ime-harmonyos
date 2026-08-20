fn parse_engine_config(config: &str) -> Result<EngineConfig, ImeErrorCode> {
    let trimmed = config.trim();
    if trimmed.is_empty() {
        return Ok(EngineConfig::default());
    }
    if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    if extract_json_usize(trimmed, "interfaceVersion")?.is_some_and(|version| {
        version != INTERFACE_VERSION_DIRECT_ACTIONS as usize
            && version != INTERFACE_VERSION_PINYIN_STAGE3 as usize
    }) {
        return Err(ImeErrorCode::AbiVersionMismatch);
    }

    let scheme_id =
        extract_json_string(trimmed, "schemeId")?.unwrap_or_else(|| "xiaohe".to_owned());
    if scheme_id != "xiaohe"
        && scheme_id != "quanpin"
        && scheme_id != "pinyin-9"
        && scheme_id != "code-table-fixture"
        && scheme_id != "xiaohe-yinxing"
    {
        return Err(ImeErrorCode::InvalidScheme);
    }
    let lexicon_path = extract_json_string(trimmed, "lexiconPath")?;
    let code_table_bundle_path = extract_json_string(trimmed, "codeTableBundlePath")?;
    let user_lexicon_path = extract_json_string(trimmed, "userLexiconPath")?;
    let code_table_action_fixture_path =
        extract_json_string(trimmed, "codeTableActionFixturePath")?;
    let code_table_action_fixture_sha256 =
        extract_json_string(trimmed, "codeTableActionFixtureSha256")?;
    let candidate_page_size = extract_json_usize(trimmed, "candidatePageSize")?
        .unwrap_or(EngineConfig::default().candidate_page_size);
    if candidate_page_size == 0 {
        return Err(ImeErrorCode::InvalidConfig);
    }
    let config_version = extract_json_usize(trimmed, "quanpinConfigVersion")?
        .unwrap_or(QUANPIN_FEATURE_CONFIG_VERSION as usize);
    if config_version != QUANPIN_FEATURE_CONFIG_VERSION as usize {
        return Err(ImeErrorCode::InvalidConfig);
    }
    let spelling_correction_enabled =
        extract_json_bool(trimmed, "spellingCorrectionEnabled")?.unwrap_or(false);
    let fuzzy_options = extract_json_string_array(trimmed, "fuzzyOptions")?
        .unwrap_or_default()
        .into_iter()
        .map(|value| FuzzyOption::parse(&value).ok_or(ImeErrorCode::InvalidConfig))
        .collect::<Result<Vec<_>, _>>()?;
    let context_reranking_config_version =
        extract_json_usize(trimmed, "quanpinContextRerankingConfigVersion")?
            .unwrap_or(QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION as usize);
    if context_reranking_config_version != QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION as usize {
        return Err(ImeErrorCode::InvalidConfig);
    }
    let context_reranking_enabled =
        extract_json_bool(trimmed, "quanpinContextRerankingEnabled")?.unwrap_or(false);
    let context_model_path = extract_json_string(trimmed, "quanpinContextModelPath")?;
    let context_model_sha256 = extract_json_string(trimmed, "quanpinContextModelSha256")?;

    Ok(EngineConfig {
        scheme_id,
        lexicon_path,
        code_table_bundle_path,
        user_lexicon_path,
        code_table_action_fixture_path,
        code_table_action_fixture_sha256,
        candidate_page_size,
        quanpin_features: QuanpinFeatureConfig::new(spelling_correction_enabled, fuzzy_options),
        quanpin_context_reranking: QuanpinContextRerankingConfig::new(
            context_reranking_enabled,
            context_model_path,
            context_model_sha256,
        ),
    })
}

fn extract_json_bool(json: &str, key: &str) -> Result<Option<bool>, ImeErrorCode> {
    let token = format!("\"{key}\"");
    let Some(mut index) = json.find(&token).map(|found| found + token.len()) else {
        return Ok(None);
    };
    index = skip_json_ws(json, index);
    if json.as_bytes().get(index) != Some(&b':') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    index = skip_json_ws(json, index + 1);
    if json[index..].starts_with("true") {
        Ok(Some(true))
    } else if json[index..].starts_with("false") {
        Ok(Some(false))
    } else {
        Err(ImeErrorCode::InvalidConfig)
    }
}

fn extract_json_string_array(json: &str, key: &str) -> Result<Option<Vec<String>>, ImeErrorCode> {
    let token = format!("\"{key}\"");
    let Some(mut index) = json.find(&token).map(|found| found + token.len()) else {
        return Ok(None);
    };
    index = skip_json_ws(json, index);
    if json.as_bytes().get(index) != Some(&b':') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    index = skip_json_ws(json, index + 1);
    if json.as_bytes().get(index) != Some(&b'[') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    index += 1;
    let mut values = Vec::new();
    loop {
        index = skip_json_ws(json, index);
        if json.as_bytes().get(index) == Some(&b']') {
            return Ok(Some(values));
        }
        if json.as_bytes().get(index) != Some(&b'\"') {
            return Err(ImeErrorCode::InvalidConfig);
        }
        index += 1;
        let start = index;
        while let Some(byte) = json.as_bytes().get(index) {
            if *byte == b'\"' {
                break;
            }
            if *byte == b'\\' || !byte.is_ascii() {
                return Err(ImeErrorCode::InvalidConfig);
            }
            index += 1;
        }
        if json.as_bytes().get(index) != Some(&b'\"') {
            return Err(ImeErrorCode::InvalidConfig);
        }
        values.push(json[start..index].to_owned());
        index = skip_json_ws(json, index + 1);
        match json.as_bytes().get(index) {
            Some(b',') => index += 1,
            Some(b']') => return Ok(Some(values)),
            _ => return Err(ImeErrorCode::InvalidConfig),
        }
    }
}

fn extract_json_string(json: &str, key: &str) -> Result<Option<String>, ImeErrorCode> {
    let token = format!("\"{key}\"");
    let Some(mut index) = json.find(&token).map(|found| found + token.len()) else {
        return Ok(None);
    };
    index = skip_json_ws(json, index);
    if json.as_bytes().get(index) != Some(&b':') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    index = skip_json_ws(json, index + 1);
    if json.as_bytes().get(index) != Some(&b'"') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    index += 1;

    let mut value = String::new();
    let mut escaped = false;
    for ch in json[index..].chars() {
        if escaped {
            value.push(match ch {
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                other => other,
            });
            escaped = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            continue;
        }
        if ch == '"' {
            return Ok(Some(value));
        }
        value.push(ch);
    }

    Err(ImeErrorCode::InvalidConfig)
}

fn extract_json_usize(json: &str, key: &str) -> Result<Option<usize>, ImeErrorCode> {
    let token = format!("\"{key}\"");
    let Some(mut index) = json.find(&token).map(|found| found + token.len()) else {
        return Ok(None);
    };
    index = skip_json_ws(json, index);
    if json.as_bytes().get(index) != Some(&b':') {
        return Err(ImeErrorCode::InvalidConfig);
    }
    index = skip_json_ws(json, index + 1);
    let start = index;
    while matches!(json.as_bytes().get(index), Some(b'0'..=b'9')) {
        index += 1;
    }
    if start == index {
        return Err(ImeErrorCode::InvalidConfig);
    }
    json[start..index]
        .parse::<usize>()
        .map(Some)
        .map_err(|_| ImeErrorCode::InvalidConfig)
}

fn skip_json_ws(json: &str, mut index: usize) -> usize {
    while let Some(byte) = json.as_bytes().get(index) {
        if !matches!(byte, b' ' | b'\n' | b'\r' | b'\t') {
            break;
        }
        index += 1;
    }
    index
}

fn parse_json_string_array(json: &str) -> Result<Vec<String>, ImeErrorCode> {
    let bytes = json.as_bytes();
    let mut index = skip_json_ws(json, 0);
    if bytes.get(index) != Some(&b'[') {
        return Err(ImeErrorCode::InvalidArgument);
    }
    index += 1;
    let mut output = Vec::new();
    loop {
        index = skip_json_ws(json, index);
        if bytes.get(index) == Some(&b']') {
            index = skip_json_ws(json, index + 1);
            return if index == bytes.len() {
                Ok(output)
            } else {
                Err(ImeErrorCode::InvalidArgument)
            };
        }
        if bytes.get(index) != Some(&b'"') {
            return Err(ImeErrorCode::InvalidArgument);
        }
        index += 1;
        let mut value = String::new();
        let mut closed = false;
        while index < bytes.len() {
            let ch = json[index..]
                .chars()
                .next()
                .ok_or(ImeErrorCode::InvalidArgument)?;
            index += ch.len_utf8();
            match ch {
                '"' => {
                    closed = true;
                    break;
                }
                '\\' => {
                    let escaped = json[index..]
                        .chars()
                        .next()
                        .ok_or(ImeErrorCode::InvalidArgument)?;
                    index += escaped.len_utf8();
                    value.push(match escaped {
                        '"' => '"',
                        '\\' => '\\',
                        '/' => '/',
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        _ => return Err(ImeErrorCode::InvalidArgument),
                    });
                }
                control if control.is_control() => return Err(ImeErrorCode::InvalidArgument),
                other => value.push(other),
            }
        }
        if !closed {
            return Err(ImeErrorCode::InvalidArgument);
        }
        output.push(value);
        index = skip_json_ws(json, index);
        match bytes.get(index) {
            Some(b',') => index += 1,
            Some(b']') => {}
            _ => return Err(ImeErrorCode::InvalidArgument),
        }
    }
}


