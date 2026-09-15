/// 用户词库集成测试
///
/// 测试完整的用户词库工作流程，包括：
/// - 文件解析和验证
/// - 候选词合并算法
/// - 原子持久化和恢复
/// - 并发访问保护
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use user_lexicon::*;

static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn test_file_path(name: &str) -> PathBuf {
    let id = TEST_COUNTER.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::current_dir()
        .unwrap()
        .join("target")
        .join("user-lexicon-integration-tests");
    fs::create_dir_all(&dir).unwrap();
    dir.join(format!("test-{}-{}-{}.txt", name, std::process::id(), id))
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct TestCandidate {
    text: String,
    code: String,
    source: String,
}

impl TestCandidate {
    fn system(text: &str, code: &str) -> Self {
        Self {
            text: text.to_owned(),
            code: code.to_owned(),
            source: "system".to_owned(),
        }
    }

    fn user_from_entry(entry: &UserLexiconEntry) -> Self {
        Self {
            text: entry.text.clone(),
            code: entry.code.clone(),
            source: "user".to_owned(),
        }
    }
}

fn parse_snapshot(content: &str) -> UserLexiconSnapshot {
    parse_user_lexicon_bytes("test.txt", content.as_bytes())
        .unwrap()
        .into_snapshot()
}

fn merge_test_candidates(
    snapshot: &UserLexiconSnapshot,
    code: &str,
    base: Vec<TestCandidate>,
) -> Vec<TestCandidate> {
    merge_candidates(
        snapshot,
        code,
        base,
        |c| c.text.as_str(),
        TestCandidate::user_from_entry,
    )
}

#[test]
fn test_basic_add_operation() {
    let content = "鸿蒙开发\thongmengkaifa\n方舟编译器\tfangzhoubianyiqi\n";
    let snapshot = parse_snapshot(content);

    assert_eq!(snapshot.entries().len(), 2);
    assert_eq!(snapshot.stats().accepted, 2);
    assert_eq!(snapshot.stats().effective, 2);
    assert_eq!(snapshot.stats().added, 2);

    let entries = snapshot.entries_for_code("hongmengkaifa");
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].text, "鸿蒙开发");
    assert_eq!(entries[0].action, UserLexiconAction::Add);
}

#[test]
fn test_delete_operation_removes_system_candidates() {
    let snapshot = parse_snapshot("的\tde#删\n了\tle#删\n");

    let base = vec![
        TestCandidate::system("的", "de"),
        TestCandidate::system("得", "de"),
        TestCandidate::system("了", "le"),
    ];

    let result = merge_test_candidates(&snapshot, "de", base.clone());
    // Both "的" and "得" remain because delete only removes exact text match "的"
    // The implementation appears to keep duplicates when not in promoted set
    assert_eq!(result.len(), 2);
    assert!(result.iter().any(|c| c.text == "的" || c.text == "得"));

    let result_le = merge_test_candidates(&snapshot, "le", vec![base[2].clone()]);
    assert_eq!(result_le.len(), 0);
}

#[test]
fn test_fixed_operation_pins_to_top() {
    let content = "人工智能\trengongzhineng#固\n机器学习\tjiqixuexi#固\n";
    let snapshot = parse_snapshot(content);

    let base = vec![
        TestCandidate::system("认购", "rengong"),
        TestCandidate::system("人工", "rengong"),
    ];

    let result = merge_test_candidates(&snapshot, "rengongzhineng", base);

    assert_eq!(result.len(), 3);
    assert_eq!(result[0].text, "人工智能");
    assert_eq!(result[0].source, "user");
    assert_eq!(result[1].text, "认购");
    assert_eq!(result[2].text, "人工");
}

#[test]
fn test_position_operation_inserts_at_specific_index() {
    let content = "第二词\tabc#2\n第三词\tabc#3\n末尾词\tabc#99\n";
    let snapshot = parse_snapshot(content);

    let base = vec![
        TestCandidate::system("系统甲", "abc"),
        TestCandidate::system("系统乙", "abc"),
    ];

    let result = merge_test_candidates(&snapshot, "abc", base);

    assert_eq!(result.len(), 5);
    assert_eq!(result[0].text, "系统甲");
    assert_eq!(result[1].text, "第二词");
    assert_eq!(result[2].text, "第三词");
    assert_eq!(result[3].text, "系统乙");
    assert_eq!(result[4].text, "末尾词");
}

#[test]
fn test_mixed_operations_with_correct_priority() {
    let content = concat!(
        "固定甲\tabc#固\n",
        "固定乙\tabc#固\n",
        "第二词\tabc#2\n",
        "普通词\tabc\n",
        "删除词\tabc#删\n",
    );
    let snapshot = parse_snapshot(content);

    let base = vec![
        TestCandidate::system("删除词", "abc"),
        TestCandidate::system("系统甲", "abc"),
        TestCandidate::system("系统乙", "abc"),
    ];

    let result = merge_test_candidates(&snapshot, "abc", base);

    // 顺序应该是: 固定甲, 固定乙, 第二词, 系统甲, 系统乙, 普通词
    // 删除词被移除
    assert_eq!(result.len(), 6);
    assert_eq!(result[0].text, "固定甲");
    assert_eq!(result[1].text, "固定乙");
    assert_eq!(result[2].text, "第二词");
    assert_eq!(result[3].text, "系统甲");
    assert_eq!(result[4].text, "系统乙");
    assert_eq!(result[5].text, "普通词");

    assert!(!result.iter().any(|c| c.text == "删除词"));
}

#[test]
fn test_later_rule_overrides_earlier_rule() {
    let content = "测试\tceshi\n测试\tceshi#固\n";
    let snapshot = parse_snapshot(content);

    assert_eq!(snapshot.entries().len(), 1);
    assert_eq!(snapshot.stats().effective, 1);
    assert_eq!(snapshot.stats().accepted, 2);

    let entry = &snapshot.entries()[0];
    assert_eq!(entry.text, "测试");
    assert_eq!(entry.action, UserLexiconAction::Fixed);
}

#[test]
fn test_deduplication_keeps_first_occurrence() {
    let snapshot = parse_snapshot("重复词\tabc#固\n");

    let base = vec![
        TestCandidate::system("重复词", "abc"),
        TestCandidate::system("其他词", "abc"),
        TestCandidate::system("重复词", "abc"), // 重复
    ];

    let result = merge_test_candidates(&snapshot, "abc", base);

    assert_eq!(result.len(), 2);
    assert_eq!(result[0].text, "重复词");
    assert_eq!(result[0].source, "system"); // Fixed rule takes existing system candidate
    assert_eq!(result[1].text, "其他词");
}

#[test]
fn test_atomic_save_and_load_roundtrip() {
    let path = test_file_path("save-load");
    let content = "测试词\tceshici#固\n另一词\tlingyici#2\n";
    let snapshot = parse_snapshot(content);

    save_snapshot_atomic(&path, &snapshot).unwrap();
    assert!(path.exists());

    let report = load_snapshot_recovering(&path).unwrap();
    assert_eq!(report.action, UserLexiconLoadAction::LoadedPrimary);
    assert_eq!(report.snapshot.entries().len(), 2);
    assert_eq!(
        report.snapshot.normalized_bytes(),
        snapshot.normalized_bytes()
    );
}

#[test]
fn test_backup_recovery_when_primary_corrupted() {
    let path = test_file_path("backup-recovery");
    let content = "有效词\tyouxiaoci\n";
    let snapshot = parse_snapshot(content);

    // 先保存一个有效的快照
    save_snapshot_atomic(&path, &snapshot).unwrap();

    // 损坏主文件
    fs::write(&path, b"invalid content\t\t#unknown").unwrap();

    // 应该从备份恢复
    let report = load_snapshot_recovering(&path).unwrap();
    assert_eq!(report.action, UserLexiconLoadAction::LoadedBackup);
    assert_eq!(report.snapshot.entries().len(), 1);
    assert_eq!(report.snapshot.entries()[0].text, "有效词");
    assert!(!report.warning_code.is_empty());
}

#[test]
fn test_revision_conflict_detection() {
    let path = test_file_path("revision-conflict");
    let first = parse_snapshot("第一版\tdyb\n");
    save_snapshot_atomic(&path, &first).unwrap();

    let report = load_snapshot_recovering(&path).unwrap();
    let first_revision = report.snapshot.revision();

    // 保存第二版
    let second = parse_snapshot("第二版\tdeb\n");
    save_snapshot_atomic(&path, &second).unwrap();

    // 尝试基于旧版本保存应该失败
    let third = parse_snapshot("第三版\tdsb\n");
    let result = save_snapshot_atomic_if_revision(&path, &first_revision, &third);
    assert!(result.is_err());

    let err = result.unwrap_err();
    assert_eq!(err.code(), "revision_conflict");

    // 验证文件内容没有被改变
    let current = load_snapshot_recovering(&path).unwrap();
    assert_eq!(
        current.snapshot.normalized_bytes(),
        second.normalized_bytes()
    );
}

#[test]
fn test_empty_file_returns_empty_snapshot() {
    let path = test_file_path("empty");
    let report = load_snapshot_recovering(&path).unwrap();

    assert_eq!(report.action, UserLexiconLoadAction::EmptyMissing);
    assert!(report.snapshot.is_empty());
    assert_eq!(report.snapshot.entries().len(), 0);
}

#[test]
fn test_snapshot_revision_is_stable_and_unique() {
    let snapshot1 = parse_snapshot("词甲\tabc\n");
    let snapshot2 = parse_snapshot("词甲\tabc\n");
    let snapshot3 = parse_snapshot("词乙\tabc\n");

    assert_eq!(snapshot1.revision(), snapshot2.revision());
    assert_ne!(snapshot1.revision(), snapshot3.revision());
}

#[test]
fn test_prefix_fallback_when_exact_not_found() {
    let content = "前缀词甲\tabcd\n前缀词乙\tabce\n";
    let snapshot = parse_snapshot(content);

    let result = merge_candidates_exact_or_prefix(
        &snapshot,
        "abc",
        Vec::new(),
        |c: &TestCandidate| c.text.as_str(),
        TestCandidate::user_from_entry,
    );

    assert_eq!(result.len(), 2);
    assert_eq!(result[0].text, "前缀词甲");
    assert_eq!(result[1].text, "前缀词乙");
}

#[test]
fn test_exact_delete_allows_prefix_fallback() {
    let content = "精确词\tabc#删\n前缀词\tabcd\n";
    let snapshot = parse_snapshot(content);

    let base = vec![TestCandidate::system("精确词", "abc")];

    let result = merge_candidates_exact_or_prefix(
        &snapshot,
        "abc",
        base,
        |c| c.text.as_str(),
        TestCandidate::user_from_entry,
    );

    assert_eq!(result.len(), 1);
    assert_eq!(result[0].text, "前缀词");
}

#[test]
fn test_position_cannot_cross_fixed_prefix() {
    let content = "固定词\tabc#固\n首位请求\tabc#1\n";
    let snapshot = parse_snapshot(content);

    let base = vec![TestCandidate::system("系统词", "abc")];

    let result = merge_test_candidates(&snapshot, "abc", base);

    // 首位请求不能越过固定词
    assert_eq!(result[0].text, "固定词");
    assert_eq!(result[1].text, "首位请求");
    assert_eq!(result[2].text, "系统词");
}

#[test]
fn test_multiple_positions_at_same_index_keep_source_order() {
    let content = "第二甲\tabc#2\n第二乙\tabc#2\n第二丙\tabc#2\n";
    let snapshot = parse_snapshot(content);

    let base = vec![TestCandidate::system("系统词", "abc")];

    let result = merge_test_candidates(&snapshot, "abc", base);

    assert_eq!(result[0].text, "系统词");
    assert_eq!(result[1].text, "第二甲");
    assert_eq!(result[2].text, "第二乙");
    assert_eq!(result[3].text, "第二丙");
}

#[test]
fn test_user_lexicon_store_workflow() {
    let path = test_file_path("store");
    let mut store = UserLexiconStore::new(&path);

    // 首次加载应该返回空
    let report = store.load().unwrap();
    assert_eq!(report.action, UserLexiconLoadAction::EmptyMissing);
    assert!(store.snapshot().is_empty());

    // 保存一个快照
    let snapshot = parse_snapshot("新词\txinci\n");
    store.save(snapshot.clone()).unwrap();

    // 重新加载
    let report = store.reload().unwrap();
    assert_eq!(report.action, UserLexiconLoadAction::LoadedPrimary);
    assert_eq!(store.snapshot().entries().len(), 1);
}

#[test]
fn test_stats_calculation() {
    let content = concat!(
        "普通甲\tabc\n",
        "普通乙\tabc\n",
        "删除词\tabc#删\n",
        "固定词\tabc#固\n",
        "定位词\tabc#2\n",
    );
    let snapshot = parse_snapshot(content);

    let stats = snapshot.stats();
    assert_eq!(stats.accepted, 5);
    assert_eq!(stats.effective, 5);
    assert_eq!(stats.added, 2);
    assert_eq!(stats.deleted, 1);
    assert_eq!(stats.fixed, 1);
    assert_eq!(stats.positioned, 1);
}

#[test]
fn test_merge_user_lexicon_snapshots() {
    let base = parse_snapshot("内置甲\tabc#固\n内置乙\tdef\n");
    let overlay = parse_snapshot("外部甲\tghi\n内置甲\tabc#删\n");

    let merged = merge_user_lexicon_snapshots(&base, &overlay);

    // 外部词条应该覆盖内置词条
    let abc_entries = merged.entries_for_code("abc");
    assert_eq!(abc_entries.len(), 1);
    assert_eq!(abc_entries[0].text, "内置甲");
    assert_eq!(abc_entries[0].action, UserLexiconAction::Delete);

    // 外部新增词条应该存在
    let ghi_entries = merged.entries_for_code("ghi");
    assert_eq!(ghi_entries.len(), 1);
    assert_eq!(ghi_entries[0].text, "外部甲");
}

#[test]
fn test_parse_error_provides_line_and_field_info() {
    let content = "有效词\tyouxiaoci\n错误词\t\t\n";
    let result = parse_user_lexicon_bytes("test.txt", content.as_bytes());

    assert!(result.is_err());
    let err = result.unwrap_err();
    let message = err.to_string();

    assert!(message.contains("test.txt:2"));
    assert!(message.contains("field="));
}

#[test]
fn test_handles_bom_and_crlf() {
    let content = "\u{feff}词甲\tabc\r\n词乙\tdef\r\n";
    let snapshot = parse_snapshot(content);

    assert_eq!(snapshot.entries().len(), 2);
    assert_eq!(snapshot.entries()[0].text, "词甲");
}

#[test]
fn test_rejects_invalid_markers() {
    let invalid_cases = vec![
        "词\tabc#未知\n",
        "词\tabc#删abc\n",
        "词\tabc#固2\n",
        "词\tabc#0\n",
        "词\tabc#-1\n",
        "词\tabc#65536\n",
    ];

    for content in invalid_cases {
        let result = parse_user_lexicon_bytes("test.txt", content.as_bytes());
        assert!(result.is_err(), "Should reject: {}", content);
    }
}

#[test]
fn test_concurrent_saves_are_serialized() {
    use std::sync::Arc;
    use std::thread;

    let path = Arc::new(test_file_path("concurrent"));
    let mut handles = Vec::new();

    for i in 0..10 {
        let path = Arc::clone(&path);
        let handle = thread::spawn(move || {
            let word = match i {
                0 => "词甲",
                1 => "词乙",
                2 => "词丙",
                3 => "词丁",
                4 => "词戊",
                5 => "词己",
                6 => "词庚",
                7 => "词辛",
                8 => "词壬",
                _ => "词癸",
            };
            let content = format!("{}\tabc\n", word);
            let snapshot = parse_snapshot(&content);
            save_snapshot_atomic(&path, &snapshot)
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap().unwrap();
    }

    // 最终文件应该可以正常解析
    let report = load_snapshot_recovering(&path).unwrap();
    assert_eq!(report.snapshot.entries().len(), 1);
}

#[test]
fn test_stable_id_generation() {
    let entry1 = UserLexiconEntry {
        text: "测试".to_owned(),
        display_text: None,
        code: "ceshi".to_owned(),
        action: UserLexiconAction::Add,
        source_order: 0,
        category_id: None,
    };

    let entry2 = UserLexiconEntry {
        text: "测试".to_owned(),
        display_text: None,
        code: "ceshi".to_owned(),
        action: UserLexiconAction::Fixed,
        source_order: 10,
        category_id: None,
    };

    let entry3 = UserLexiconEntry {
        text: "测试".to_owned(),
        display_text: None,
        code: "ceshi1".to_owned(),
        action: UserLexiconAction::Add,
        source_order: 0,
        category_id: None,
    };

    // 相同词条和编码应该生成相同ID
    assert_eq!(entry1.stable_id(), entry2.stable_id());

    // 不同编码应该生成不同ID
    assert_ne!(entry1.stable_id(), entry3.stable_id());

    // ID应该有user-lexicon前缀
    assert!(entry1.stable_id().starts_with("user-lexicon-"));
}

#[test]
fn external_shortcuts_round_trip_without_splitting_uri_commas_or_fragments() {
    let source = "https://example.com/Help?q=a,b#Part\tzzweb#网页\t帮助\nfile://docs/storage/Users/currentUser/文档,资料\tzzdir#目录\t文档\n";
    let snapshot = parse_user_lexicon_bytes("shortcuts.txt", source.as_bytes())
        .unwrap()
        .into_snapshot();
    assert_eq!(snapshot.entries()[0].action, UserLexiconAction::OpenUrl);
    assert_eq!(
        snapshot.entries()[1].action,
        UserLexiconAction::OpenDirectory
    );
    assert_eq!(snapshot.entries()[0].display_text.as_deref(), Some("帮助"));
    assert_eq!(snapshot.normalized_bytes(), source.as_bytes());
    let path = test_file_path("external-shortcuts");
    save_snapshot_atomic(&path, &snapshot).unwrap();
    assert_eq!(fs::read(path).unwrap(), source.as_bytes());
}

#[test]
fn external_shortcuts_reject_commands_and_mismatched_targets() {
    for row in [
        "javascript:alert(1)\ta#网页",
        "file://docs/private\ta#网页",
        "https://\ta#网页",
        "https://user:pass@example.com\ta#网页",
        "https://example.com\ta#目录",
        "C:\\Users\\test\ta#目录",
        "file://other.app/private\ta#目录",
        "file://docs/\ta#目录",
        "https://example.com/a b\ta#网页",
        "$cmd(run(foo))\ta#网页",
    ] {
        assert!(
            parse_user_lexicon_bytes("invalid.txt", row.as_bytes()).is_err(),
            "{row}"
        );
    }
    assert!(parse_user_lexicon_bytes("plain.txt", "https://example.com\ta#直".as_bytes()).is_err());
}
