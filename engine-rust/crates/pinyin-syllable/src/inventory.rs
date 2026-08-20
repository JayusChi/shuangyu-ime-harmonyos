/// Tone-less Mandarin pinyin syllables accepted by the engine.
///
/// The list uses ASCII `v` for `u` with diaeresis when the diaeresis must be
/// preserved (`nv`, `nve`, `lv`, `lve`). For `j/q/x/y`, the normalized spelling
/// follows standard pinyin and uses `u` (`ju`, `jue`, `juan`, `jun`).
const VALID_SYLLABLES: &str = "
a ai an ang ao
ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
ca cai can cang cao ce cen ceng ci cong cou cu cuan cui cun cuo
cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo
da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
e ei en eng er
fa fan fang fei fen feng fo fou fu
ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo
la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve
ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
n na nai nan nang nao ne nei nen neng ng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve
o ou
pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
ran rang rao re ren reng ri rong rou ru ruan rui run ruo
sa sai san sang sao se sen seng si song sou su suan sui sun suo
sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo
ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
wa wai wan wang wei wen weng wo wu
xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
za zai zan zang zao ze zei zen zeng zi zong zou zu zuan zui zun zuo
zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo
";

/// Returns true when `normalized` is present in the maintained syllable set.
pub fn contains(normalized: &str) -> bool {
    VALID_SYLLABLES
        .split_whitespace()
        .any(|syllable| syllable == normalized)
}

/// Returns the number of maintained syllables.
pub fn syllable_count() -> usize {
    VALID_SYLLABLES.split_whitespace().count()
}

/// Iterates every maintained syllable in stable lexical-source order.
///
/// Offline rule validators use this to prove mapping completeness without
/// copying the runtime inventory into a second hidden table.
pub fn all_syllables() -> impl Iterator<Item = &'static str> {
    VALID_SYLLABLES.split_whitespace()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inventory_contains_core_stage4_syllables() {
        for syllable in ["zhong", "shi", "ju", "quan", "xue", "nv", "ng"] {
            assert!(contains(syllable), "{syllable} should be valid");
        }
    }
}
