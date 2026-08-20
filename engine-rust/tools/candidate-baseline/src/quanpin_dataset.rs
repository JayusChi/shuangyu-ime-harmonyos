use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use crate::eval_json::{serialize, serialize_line, JsonValue};

const SOURCE_ID: &str = "project-authored:quanpin-quality-baseline-v1";

#[derive(Clone)]
struct Seed {
    raw: String,
    expected: Vec<String>,
    category: &'static str,
    tags: Vec<String>,
    fuzzy: Vec<String>,
    notes: Option<String>,
}

impl Seed {
    fn clean(reading: &str, expected: &str, category: &'static str) -> Self {
        Self {
            raw: reading.replace(' ', ""),
            expected: vec![expected.to_owned()],
            category,
            tags: vec!["clean".to_owned()],
            fuzzy: Vec::new(),
            notes: None,
        }
    }
}

pub fn create_quanpin_dataset(output_dir: &Path) -> Result<String, String> {
    if output_dir.exists()
        && fs::read_dir(output_dir)
            .map_err(|error| error.to_string())?
            .next()
            .is_some()
    {
        return Err(format!(
            "dataset directory is not empty: {}; remove it only when intentionally authoring a new baseline",
            output_dir.display()
        ));
    }
    fs::create_dir_all(output_dir).map_err(|error| error.to_string())?;
    let categories = build_categories()?;
    let dev_quotas = BTreeMap::from([
        ("common_character_word", 45_usize),
        ("common_phrase_2_4", 60),
        ("modern_chat", 60),
        ("long_ambiguous", 30),
        ("proper_name_domain", 30),
        ("polyphone_homophone", 25),
        ("abbrev_mixed_incomplete", 20),
        ("typo", 18),
        ("fuzzy", 12),
    ]);

    let mut dev = Vec::new();
    let mut blind = Vec::new();
    let mut global_index = 1_usize;
    for (category, cases) in categories {
        let quota = *dev_quotas
            .get(category)
            .ok_or_else(|| format!("missing dev quota for {category}"))?;
        for (category_index, seed) in cases.into_iter().enumerate() {
            let split = if category_index < quota {
                "dev"
            } else {
                "blind"
            };
            let value = case_json(global_index, split, seed);
            global_index += 1;
            if split == "dev" {
                dev.extend_from_slice(&serialize_line(&value));
            } else {
                blind.extend_from_slice(&serialize_line(&value));
            }
        }
    }
    fs::write(output_dir.join("dev.jsonl"), dev).map_err(|error| error.to_string())?;
    fs::write(output_dir.join("blind.jsonl"), blind).map_err(|error| error.to_string())?;
    fs::write(output_dir.join("sources.json"), serialize(&sources_json()))
        .map_err(|error| error.to_string())?;
    fs::write(output_dir.join("DATASET_PROVENANCE.md"), provenance())
        .map_err(|error| error.to_string())?;
    Ok(
        "created 1070 project-authored cases (300 dev, 770 blind); no engine was invoked"
            .to_owned(),
    )
}

fn case_json(index: usize, split: &str, seed: Seed) -> JsonValue {
    let mut fields = vec![
        ("id", JsonValue::string(format!("qp-v1-{index:04}"))),
        ("rawInput", JsonValue::string(seed.raw)),
        (
            "expectedTexts",
            JsonValue::array(seed.expected.into_iter().map(JsonValue::string)),
        ),
        ("category", JsonValue::string(seed.category)),
        (
            "tags",
            JsonValue::array(seed.tags.into_iter().map(JsonValue::string)),
        ),
        ("source", JsonValue::string(SOURCE_ID)),
        ("split", JsonValue::string(split)),
    ];
    if !seed.fuzzy.is_empty() {
        fields.push((
            "enabledFuzzyOptions",
            JsonValue::array(seed.fuzzy.into_iter().map(JsonValue::string)),
        ));
    }
    if let Some(notes) = seed.notes {
        fields.push(("notes", JsonValue::string(notes)));
    }
    JsonValue::object(fields)
}

fn sources_json() -> JsonValue {
    JsonValue::object([
        ("schemaVersion", JsonValue::string("quanpin-evaluation-sources/1")),
        (
            "sources",
            JsonValue::array([JsonValue::object([
                ("id", JsonValue::string(SOURCE_ID)),
                ("name", JsonValue::string("HarmonyOS_Input project-authored evaluation prompts")),
                ("version", JsonValue::string("1.0.0")),
                ("authoredAt", JsonValue::string("2026-08-13")),
                ("license", JsonValue::string("PROJECT-INTERNAL-AUTHORED-DATA")),
                ("externalData", JsonValue::Bool(false)),
                ("commercialImeData", JsonValue::Bool(false)),
                ("engineGeneratedExpectedText", JsonValue::Bool(false)),
                (
                    "method",
                    JsonValue::string("Manually authored words and morpheme templates; deterministic combinations and typo transformations are independent of engine output."),
                ),
            ])]),
        ),
    ])
}

fn provenance() -> &'static str {
    "# Quanpin evaluation dataset provenance\n\n\
Version: 1.0.0\n\n\
Frozen-authoring date: 2026-08-13 (Asia/Shanghai)\n\n\
License: PROJECT-INTERNAL-AUTHORED-DATA. This dataset was authored for this repository and contains no imported third-party corpus.\n\n\
The expected texts and pinyin readings were written from ordinary Mandarin knowledge. Template expansion combines only the author-written morphemes in this source. Typo transformations are deterministic edits of those author-written readings. No commercial IME, web scrape, production lexicon lookup, current-engine candidate output, or unit-test export was used.\n\n\
`blind.jsonl` is immutable after the first freeze. Any byte change is rejected by the evaluator until an operator explicitly creates a new baseline identity.\n"
}

fn build_categories() -> Result<Vec<(&'static str, Vec<Seed>)>, String> {
    let common = pair_seeds(COMMON, "common_character_word", 160)?;
    let phrases = combine(PHRASE_PREFIXES, PHRASE_ACTIONS, "common_phrase_2_4", 220)?;
    let chats = combine(CHAT_PREFIXES, CHAT_PREDICATES, "modern_chat", 220)?;
    let long = combine(LONG_PREFIXES, LONG_SUFFIXES, "long_ambiguous", 110)?;
    let proper = pair_seeds(PROPER, "proper_name_domain", 110)?;
    let poly = pair_seeds(POLYPHONE, "polyphone_homophone", 80)?;
    let abbrev = abbreviated_cases(&chats, 70)?;
    let typo = typo_cases(&chats, 60)?;
    let fuzzy = fuzzy_cases()?;
    Ok(vec![
        ("common_character_word", common),
        ("common_phrase_2_4", phrases),
        ("modern_chat", chats),
        ("long_ambiguous", long),
        ("proper_name_domain", proper),
        ("polyphone_homophone", poly),
        ("abbrev_mixed_incomplete", abbrev),
        ("typo", typo),
        ("fuzzy", fuzzy),
    ])
}

fn pair_seeds(text: &str, category: &'static str, count: usize) -> Result<Vec<Seed>, String> {
    let pairs = parse_pairs(text)?;
    if pairs.len() != count {
        return Err(format!(
            "{category} has {} seeds, expected {count}",
            pairs.len()
        ));
    }
    Ok(pairs
        .into_iter()
        .map(|(reading, expected)| Seed::clean(&reading, &expected, category))
        .collect())
}

fn combine(
    left: &str,
    right: &str,
    category: &'static str,
    count: usize,
) -> Result<Vec<Seed>, String> {
    let left = parse_pairs(left)?;
    let right = parse_pairs(right)?;
    let mut result = Vec::new();
    for (left_reading, left_text) in &left {
        for (right_reading, right_text) in &right {
            result.push(Seed::clean(
                &format!("{left_reading} {right_reading}"),
                &format!("{left_text}{right_text}"),
                category,
            ));
        }
    }
    if result.len() != count {
        return Err(format!(
            "{category} expands to {}, expected {count}",
            result.len()
        ));
    }
    Ok(result)
}

fn parse_pairs(text: &str) -> Result<Vec<(String, String)>, String> {
    text.lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            let (reading, expected) = line
                .split_once('|')
                .ok_or_else(|| format!("invalid authored pair {line:?}"))?;
            Ok((reading.trim().to_owned(), expected.trim().to_owned()))
        })
        .collect()
}

fn abbreviated_cases(clean: &[Seed], count: usize) -> Result<Vec<Seed>, String> {
    let mut result = Vec::new();
    for (index, source) in clean.iter().take(count).enumerate() {
        let syllables = segment_pinyin(&source.raw)
            .ok_or_else(|| format!("cannot segment authored pinyin {}", source.raw))?;
        let (raw, tag, note) = match index % 3 {
            0 => (
                syllables
                    .iter()
                    .filter_map(|value| value.chars().next())
                    .collect(),
                "abbreviated",
                "initial-only shorthand",
            ),
            1 => (
                syllables
                    .iter()
                    .enumerate()
                    .map(|(part, value)| {
                        if part % 2 == 0 {
                            value.clone()
                        } else {
                            value.chars().next().expect("nonempty syllable").to_string()
                        }
                    })
                    .collect(),
                "mixed",
                "full-pinyin and initials mixed",
            ),
            _ => (
                source
                    .raw
                    .chars()
                    .take(source.raw.chars().count() - 1)
                    .collect(),
                "incomplete_tail",
                "last pinyin syllable intentionally unfinished",
            ),
        };
        result.push(Seed {
            raw,
            expected: source.expected.clone(),
            category: "abbrev_mixed_incomplete",
            tags: vec!["clean".to_owned(), tag.to_owned()],
            fuzzy: Vec::new(),
            notes: Some(note.to_owned()),
        });
    }
    Ok(result)
}

fn typo_cases(clean: &[Seed], count: usize) -> Result<Vec<Seed>, String> {
    let mut result = Vec::new();
    for (index, source) in clean.iter().take(count).enumerate() {
        let mut chars = source.raw.chars().collect::<Vec<_>>();
        let middle = chars.len() / 2;
        let subtype = match index % 4 {
            0 => {
                chars.remove(middle);
                "missing_letter"
            }
            1 => {
                chars.insert(middle, 'a');
                "extra_letter"
            }
            2 => {
                chars[middle] = neighbor(chars[middle]);
                "neighbor_key"
            }
            _ => {
                chars.swap(middle - 1, middle);
                "transposed"
            }
        };
        result.push(Seed {
            raw: chars.into_iter().collect(),
            expected: source.expected.clone(),
            category: "typo",
            tags: vec!["typo".to_owned(), subtype.to_owned()],
            fuzzy: Vec::new(),
            notes: Some("deterministic edit of a project-authored clean reading".to_owned()),
        });
    }
    Ok(result)
}

fn neighbor(value: char) -> char {
    match value {
        'a' => 's',
        's' => 'd',
        'd' => 'f',
        'f' => 'g',
        'g' => 'h',
        'h' => 'j',
        'j' => 'k',
        'k' => 'l',
        'l' => 'k',
        'q' => 'w',
        'w' => 'e',
        'e' => 'r',
        'r' => 't',
        't' => 'y',
        'y' => 'u',
        'u' => 'i',
        'i' => 'o',
        'o' => 'p',
        'p' => 'o',
        'z' => 'x',
        'x' => 'c',
        'c' => 'v',
        'v' => 'b',
        'b' => 'n',
        'n' => 'm',
        'm' => 'n',
        _ => 'a',
    }
}

fn fuzzy_cases() -> Result<Vec<Seed>, String> {
    let rows = parse_pairs(FUZZY)?;
    if rows.len() != 40 {
        return Err(format!("fuzzy has {} seeds, expected 40", rows.len()));
    }
    Ok(rows
        .into_iter()
        .enumerate()
        .map(|(index, (raw, expected))| {
            let option = ["n_l", "z_zh", "c_ch", "s_sh", "in_ing", "en_eng", "an_ang", "ian_iang"]
                [index / 5];
            Seed {
                raw: raw.replace(' ', ""),
                expected: vec![expected],
                category: "fuzzy",
                tags: vec!["fuzzy".to_owned(), option.to_owned()],
                fuzzy: vec![option.to_owned()],
                notes: Some("The current ImeEngine has no fuzzy-option API; evaluator records the requested option but sends rawInput unchanged.".to_owned()),
            }
        })
        .collect())
}

fn segment_pinyin(raw: &str) -> Option<Vec<String>> {
    fn walk(
        raw: &str,
        offset: usize,
        memo: &mut BTreeMap<usize, Option<Vec<String>>>,
    ) -> Option<Vec<String>> {
        if offset == raw.len() {
            return Some(Vec::new());
        }
        if let Some(cached) = memo.get(&offset) {
            return cached.clone();
        }
        let mut syllables = pinyin_syllable::all_syllables().collect::<Vec<_>>();
        syllables.sort_by_key(|value| std::cmp::Reverse(value.len()));
        for syllable in syllables {
            if raw[offset..].starts_with(syllable) {
                if let Some(mut tail) = walk(raw, offset + syllable.len(), memo) {
                    let mut result = vec![syllable.to_owned()];
                    result.append(&mut tail);
                    memo.insert(offset, Some(result.clone()));
                    return Some(result);
                }
            }
        }
        memo.insert(offset, None);
        None
    }
    walk(raw, 0, &mut BTreeMap::new())
}

const COMMON: &str = r#"
wo|我
ni|你
women|我们
nimen|你们
tamen|他们
zhege|这个
nage|那个
zheli|这里
nali|那里
xianzai|现在
jintian|今天
mingtian|明天
zuotian|昨天
zaoshang|早上
wanshang|晚上
zhongwu|中午
shijian|时间
difang|地方
shiqing|事情
wenti|问题
gongzuo|工作
xuexi|学习
shenghuo|生活
pengyou|朋友
jiaren|家人
haizi|孩子
laoshi|老师
xuesheng|学生
xuexiao|学校
gongsi|公司
shouji|手机
diannao|电脑
wangluo|网络
xiaoxi|消息
dianhua|电话
zhaopian|照片
shipin|视频
yinyue|音乐
dianying|电影
xinwen|新闻
tianqi|天气
kongqi|空气
chengshi|城市
nongcun|农村
daolu|道路
qiche|汽车
huoche|火车
feiji|飞机
ditie|地铁
gongjiao|公交
zaocan|早餐
wufan|午饭
wanfan|晚饭
shuiguo|水果
shucai|蔬菜
mifan|米饭
miantiao|面条
niunai|牛奶
kafei|咖啡
chashui|茶水
yifu|衣服
xiezi|鞋子
maozi|帽子
zhuozi|桌子
yizi|椅子
fangjian|房间
chufang|厨房
menkou|门口
chuanghu|窗户
yaoshi|钥匙
kaishi|开始
jieshu|结束
wancheng|完成
jixu|继续
tingzhi|停止
dakai|打开
guanbi|关闭
jinru|进入
likai|离开
huilai|回来
zhidao|知道
mingbai|明白
juede|觉得
xihuan|喜欢
xuyao|需要
xiwang|希望
bangzhu|帮助
lianxi|联系
huifu|回复
queren|确认
tongyi|同意
jujue|拒绝
zhichi|支持
xuanze|选择
jueding|决定
gaibian|改变
jiancha|检查
jiejue|解决
faxian|发现
shuoming|说明
anquan|安全
zhongyao|重要
jiandan|简单
fuza|复杂
qingchu|清楚
zhunque|准确
kuaisu|快速
wending|稳定
fangbian|方便
kunnan|困难
gaoxing|高兴
nanguo|难过
shengqi|生气
jinzhang|紧张
fangxin|放心
renzhen|认真
nuli|努力
anjing|安静
renao|热闹
piaoliang|漂亮
keyi|可以
yinggai|应该
bixu|必须
keneng|可能
yijing|已经
zhengzai|正在
mashang|马上
yiqi|一起
zaici|再次
yizhi|一直
yinwei|因为
suoyi|所以
danshi|但是
ruguo|如果
suiran|虽然
ranhou|然后
erqie|而且
huozhe|或者
haishi|还是
zhiyou|只有
yige|一个
liangge|两个
sange|三个
diyi|第一
zuihou|最后
qianmian|前面
houmian|后面
limian|里面
waimian|外面
pangbian|旁边
nihao|你好
xiexie|谢谢
zaijian|再见
meishi|没事
haode|好的
buxing|不行
meicuo|没错
dangran|当然
baoqian|抱歉
huanying|欢迎
"#;

const PHRASE_PREFIXES: &str = r#"
mashang|马上
like|立刻
jinkuai|尽快
jishi|及时
renzhen|认真
nuli|努力
jixu|继续
chongxin|重新
gongtong|共同
zhudong|主动
tiqian|提前
anshi|按时
zhijie|直接
zhengshi|正式
gongkai|公开
quanmian|全面
zhongdian|重点
jiandan|简单
kuaisu|快速
wending|稳定
"#;

const PHRASE_ACTIONS: &str = r#"
chuli|处理
wancheng|完成
jiancha|检查
queren|确认
lianxi|联系
anpai|安排
xuexi|学习
gongzuo|工作
gengxin|更新
jiejue|解决
shuoming|说明
"#;

const CHAT_PREFIXES: &str = r#"
wo xiang|我想
wo hui|我会
wo yao|我要
women xian|我们先
women zai|我们再
ni xian|你先
ni zai|你再
ni keyi|你可以
dajia xian|大家先
dajia zai|大家再
jintian xian|今天先
mingtian zai|明天再
xianzai jiu|现在就
shaohou zai|稍后再
youkong jiu|有空就
fangbian shi|方便时
xiaban hou|下班后
daojia hou|到家后
chiwan fan|吃完饭
kaiwan hui|开完会
"#;

const CHAT_PREDICATES: &str = r#"
hui ge xiaoxi|回个消息
yiqi chifan|一起吃饭
zaodian huijia|早点回家
da ge dianhua|打个电话
fa gei wo ba|发给我吧
zai shuo yi bian|再说一遍
queren yi xia|确认一下
deng wo yi xia|等我一下
manman lai ba|慢慢来吧
lushang xiaoxin|路上小心
mingtian jian ba|明天见吧
"#;

const LONG_PREFIXES: &str = r#"
ruguo ni jintian you shijian|如果你今天有时间
deng women wancheng zhexiang gongzuo|等我们完成这项工作
yinwei xianzai tianqi bucuo|因为现在天气不错
suiran zhege wenti bijiao fuza|虽然这个问题比较复杂
dang ni shoudao zhege xiaoxi|当你收到这个消息
zhiyao dajia ba qingkuang shuoqingchu|只要大家把情况说清楚
zaikaishi xiayibu zhiqian|在开始下一步之前
weile ba zhege wenti jiejue|为了把这个问题解决
yaoshi mingzao haimei you huifu|要是明早还没有回复
women zai chuli wancheng yihou|我们在处理完成以后
"#;

const LONG_SUFFIXES: &str = r#"
jiu gei wo da ge dianhua|就给我打个电话
women zai yiqi queren jieguo|我们再一起确认结果
keyi chuqu manman zou yi zou|可以出去慢慢走一走
danshi haishi neng zhaodao banfa|但是还是能找到办法
qing jide jishi gaosu dajia|请记得及时告诉大家
houlian de anpai jiu hui geng shunli|后面的安排就会更顺利
xian jiancha ziliao shifou wanzheng|先检查资料是否完整
xuyao mei ge ren dou renzhen peihe|需要每个人都认真配合
jiu an zhiqian de jihua jixu|就按之前的计划继续
qing ba zuizhong jieguo jilu xialai|请把最终结果记录下来
women dou buyao zhaoji zuo jueding|我们都不要着急做决定
"#;

const PROPER: &str = r#"
beijing|北京
shanghai|上海
tianjin|天津
chongqing|重庆
guangzhou|广州
shenzhen|深圳
hangzhou|杭州
nanjing|南京
suzhou|苏州
chengdu|成都
wuhan|武汉
xian|西安
zhengzhou|郑州
changsha|长沙
qingdao|青岛
xiamen|厦门
fuzhou|福州
kunming|昆明
guiyang|贵阳
nanning|南宁
haikou|海口
lasa|拉萨
lanzhou|兰州
xining|西宁
yinchuan|银川
wulumuqi|乌鲁木齐
haerbin|哈尔滨
changchun|长春
shenyang|沈阳
dalian|大连
jinan|济南
shijiazhuang|石家庄
taiyuan|太原
hefei|合肥
nanchang|南昌
huhehaote|呼和浩特
xianggang|香港
aomen|澳门
taibei|台北
sanya|三亚
zhangwei|张伟
wangfang|王芳
lina|李娜
liuyang|刘洋
chenchen|陈晨
yangfan|杨帆
zhaolei|赵磊
huangjing|黄静
zhoumin|周敏
wuhao|吴昊
xuning|徐宁
sunyue|孙悦
hubin|胡斌
zhulin|朱琳
gaofeng|高峰
lintao|林涛
heping|何平
guoqiang|郭强
machao|马超
luolan|罗兰
beijingdaxue|北京大学
qinghuadaxue|清华大学
zhongguokexueyuan|中国科学院
zhongguoyinhang|中国银行
renminyiyuan|人民医院
shizhengfu|市政府
jiaoyuju|教育局
kejiguan|科技馆
tushuguan|图书馆
bowuguan|博物馆
huochezhan|火车站
feijichang|飞机场
dianshitai|电视台
chubanshe|出版社
yanjiuzhongxin|研究中心
kefuzhongxin|客服中心
xiangmuzu|项目组
jishubu|技术部
shichangbu|市场部
yunyingbu|运营部
hongmengxitong|鸿蒙系统
bianchengyuyan|编程语言
shurufa|输入法
quanjianquanpin|全键全拼
houxuanpaixu|候选排序
zhengjujiema|整句解码
yonghumoxing|用户模型
shengchanciku|生产词库
mangpingpingce|盲评评测
shujuhaxi|数据哈希
quedingxingceshi|确定性测试
zhuangtaiji|状态机
neicunanquan|内存安全
xianchenganquan|线程安全
jiekoubanben|接口版本
fuzaceshi|负载测试
xingnengjizhun|性能基准
shuruyanchi|输入延迟
houxuanzhaohui|候选召回
pingjunmingci|平均名次
zidongshangping|自动上屏
yingwenzimuxielou|英文字母泄漏
zhuangtaidiushi|状态丢失
wenjianqingdan|文件清单
dongjiejizhun|冻结基线
shujulaiyuan|数据来源
xukezheng|许可证
banbenbiaoshi|版本标识
zhujishuju|主机数据
shebeishuju|设备数据
"#;

const POLYPHONE: &str = r#"
chongxin|重新
zhongyaofangan|重要方案
chongfu|重复
zhongfu|重负
changdu|长度
zhangda|长大
yinyueketang|音乐课堂
kuaile|快乐
yinhang|银行
xingzou|行走
hangye|行业
haoxue|好学
haohao|好好
haoqi|好奇
jiaoshi|教室
jiaoshu|教书
juedehenhao|觉得很好
shuijiao|睡觉
zhongzi|种子
zhonghua|种花
chuli|处理
daochu|到处
zhuanbian|转变
zhuanquan|转圈
shumu|数目
shushu|数数
weiren|为人
yinweixiaoyu|因为下雨
meihao|美好
aihao|爱好
shaonian|少年
duoshao|多少
beike|贝壳
qiaoke|巧克
zangshu|藏书
xizang|西藏
chaoshi|超市
shichang|市场
shishi|事实
shishi jian|试时间
gongshi|公式
gongshi pin|工视频
quanli|权利
quanliang|全量
lizhi|离职
lizhiqi|荔枝气
qixian|期限
qixian zai|起现在
yuanyin|原因
yuanying|援英
zhiding|制定
zhidingzi|支钉子
baoming|报名
baomingbai|把明白
fenxiang|分享
fenxiangzi|分箱子
shijie|世界
shijie shao|是介绍
gongyuan|公园
gongyuanda|公元大
renming|人名
renmin|人民
shiming|实名
shimin|市民
jingli|经理
jingli guo|经历过
shili|实力
shiliu|石榴
qianjin|前进
qianjing|前景
fanying|反应
fanyinggai|反应该
zhengming|证明
zhengmingtian|正明天
gongkai|公开
gongkai shi|工开始
anquandiyi|安全第一
anquanbu|安全部
qingchuyuanyin|清楚原因
qingchulai|请出来
"#;

const FUZZY: &str = r#"
lihao|你好
liunai|牛奶
lanfang|南方
laoli|老李
nvse|绿色
zidao|知道
zongguo|中国
zaopian|照片
zengshi|正式
zunjing|尊敬
cifan|吃饭
cuqu|出去
cengshi|城市
cazhao|查找
cunji|春季
sijian|时间
suohua|说话
sangdian|商店
senme|什么
saohou|稍后
jingtian|今天
xingwen|新闻
lingshi|临时
pinguo|苹果
qinjin|请进
rengzhen|认真
shengme|什么
fengxiang|分享
wengti|问题
bengshen|本身
bangfa|办法
kangkang|看看
wangfan|晚饭
angquan|安全
shangguang|闪光
jintiang|今天
xiangzai|现在
diangnao|电脑
liangxi|联系
jiankang|健康
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authored_dataset_has_frozen_shape() {
        let categories = build_categories().unwrap();
        assert_eq!(
            categories
                .iter()
                .map(|(_, cases)| cases.len())
                .sum::<usize>(),
            1070
        );
        assert_eq!(categories.len(), 9);
    }
}
