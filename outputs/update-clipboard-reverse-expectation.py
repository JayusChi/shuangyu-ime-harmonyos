from pathlib import Path
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
replace('engine-rust/crates/code-table-runtime/src/action.rs', '''                .filter(|record| record.scope == ActionScope::Direct)
                .count(),
            55''', '''                .filter(|record| record.scope == ActionScope::Direct)
                .count(),
            56''')
replace('engine-rust/crates/code-table-runtime/src/action.rs', '        assert_eq!(table.file_sha256.len(), 64);', '''        assert!(matches!(
            table.query_direct_exact_or_prefix("ofi")[0].action,
            FunctionalAction::DirectControl { ref action, ref target }
                if action == "clipboard.reverse" && target.is_empty()
        ));
        assert_eq!(table.query_direct_exact_or_prefix("ofi")[0].label, "[复制反查]");
        assert_eq!(table.file_sha256.len(), 64);''')
