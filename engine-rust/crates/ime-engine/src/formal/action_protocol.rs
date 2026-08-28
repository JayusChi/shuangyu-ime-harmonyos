fn code_table_result(machine: &CodeTableStateMachine) -> CompositionResult {
    code_table_result_with_commit(machine, None)
}

fn code_table_result_with_commit(
    machine: &CodeTableStateMachine,
    commit_text: Option<String>,
) -> CompositionResult {
    let candidates = machine
        .current_candidates()
        .iter()
        .map(|candidate| FormalCandidate {
            id: candidate.id.clone(),
            text: candidate.text.clone(),
            display_text: candidate.display_text.clone().unwrap_or_default(),
            reading: candidate.code.clone(),
            source: candidate.category_id.clone(),
            consumed_raw_len: machine.raw_code().chars().count().min(u32::MAX as usize) as u32,
        })
        .collect::<Vec<_>>();
    let raw_input = match machine.input_state() {
        CodeTableInputState::GuidePrefix => ";".to_owned(),
        CodeTableInputState::GuideCode => format!(";{}", machine.raw_code()),
        _ => machine.raw_code().to_owned(),
    };
    let parser_state = if machine.input_state() == CodeTableInputState::GuidePrefix {
        ProtocolParserState::Incomplete
    } else if machine.raw_code().is_empty() {
        ProtocolParserState::Empty
    } else if machine.all_candidates().is_empty() {
        ProtocolParserState::Invalid
    } else {
        ProtocolParserState::Complete
    };
    let mut result =
        CompositionResult::success(&raw_input, &raw_input, Vec::new(), "", parser_state)
            .with_candidates(
                candidates,
                machine.current_page() as u32,
                machine.has_previous_page(),
                machine.has_next_page(),
            );
    if let Some(commit_text) = commit_text {
        result.commit_text = commit_text;
        result.composition_finished = machine.raw_code().is_empty();
    }
    result
}

fn action_result(action: FunctionalAction) -> CompositionResult {
    let protocol = match action {
        FunctionalAction::DateTimeText(format_id) => ProtocolAction::DateTimeText {
            format_id: match format_id {
                RuntimeDateTimeFormatId::DateIso => DateTimeFormatId::DateIso,
                RuntimeDateTimeFormatId::DateLocal => DateTimeFormatId::DateLocal,
                RuntimeDateTimeFormatId::DateLocalUnpadded => DateTimeFormatId::DateLocalUnpadded,
                RuntimeDateTimeFormatId::TimeHm => DateTimeFormatId::TimeHm,
                RuntimeDateTimeFormatId::TimeHms => DateTimeFormatId::TimeHms,
                RuntimeDateTimeFormatId::TimeLocalHms => DateTimeFormatId::TimeLocalHms,
                RuntimeDateTimeFormatId::TimeWeekday => DateTimeFormatId::TimeWeekday,
                RuntimeDateTimeFormatId::TimeLocalHm => DateTimeFormatId::TimeLocalHm,
                RuntimeDateTimeFormatId::LunarDateFestival => DateTimeFormatId::LunarDateFestival,
                RuntimeDateTimeFormatId::DateTimeLocal => DateTimeFormatId::DateTimeLocal,
                RuntimeDateTimeFormatId::UnixTimestamp => DateTimeFormatId::UnixTimestamp,
            },
        },
        FunctionalAction::InsertPair {
            text,
            cursor_offset_utf16,
        } => ProtocolAction::InsertPair {
            text,
            cursor_offset_utf16,
        },
        FunctionalAction::RepeatCommit => ProtocolAction::RepeatCommit,
        FunctionalAction::UndoCommit => ProtocolAction::UndoCommit,
        FunctionalAction::MoveLineEnd => ProtocolAction::MoveLineEnd,
        FunctionalAction::DirectControl { action, target } => {
            ProtocolAction::DirectControl { action, target }
        }
        FunctionalAction::ImportUserLexicon => ProtocolAction::ImportUserLexicon,
        FunctionalAction::StaticText(text)
        | FunctionalAction::StaticSymbol(text)
        | FunctionalAction::QuickSymbol(text) => return CompositionResult::committed(&text),
    };
    let mut result = CompositionResult::success("", "", Vec::new(), "", ProtocolParserState::Empty)
        .with_action(protocol);
    result.composition_finished = true;
    result
}

fn code_table_failure(
    machine: &CodeTableStateMachine,
    code: ImeErrorCode,
    message: &str,
) -> CompositionResult {
    let mut output = code_table_result(machine);
    output.success = false;
    output.error_code = code;
    output.error_message = message.to_owned();
    output
}
