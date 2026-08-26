import { i18n } from '@kit.LocalizationKit';

export interface LunarDateProvider {
  format(snapshot: Date): string;
}

const ZODIAC_NAMES: string[] = [
  '鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'
];
const MONTH_NAMES: string[] = [
  '正月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '冬月', '腊月'
];
const DAY_NAMES: string[] = [
  '', '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
];

export class SystemLunarDateProvider implements LunarDateProvider {
  format(snapshot: Date): string {
    if (Number.isNaN(snapshot.getTime())) {
      return '';
    }
    try {
      const calendar = i18n.getCalendar('zh-CN', 'chinese');
      calendar.setTime(snapshot);
      const year = calendar.get('year');
      const month = calendar.get('month');
      const day = calendar.get('date');
      const leap = calendar.get('is_leap_month') === 1;
      if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day) ||
        month < 0 || month >= MONTH_NAMES.length || day <= 0 || day >= DAY_NAMES.length) {
        return '';
      }
      const zodiacIndex = ((year - 1) % ZODIAC_NAMES.length + ZODIAC_NAMES.length) % ZODIAC_NAMES.length;
      const festival = leap ? '' : this.festivalFor(month + 1, day);
      return `农历${ZODIAC_NAMES[zodiacIndex]}年${leap ? '闰' : ''}` +
        `${MONTH_NAMES[month]}${DAY_NAMES[day]}${festival}`;
    } catch (_err) {
      return '';
    }
  }

  private festivalFor(month: number, day: number): string {
    const key = `${month}-${day}`;
    const festivals: Record<string, string> = {
      '1-1': '春节',
      '1-15': '元宵',
      '5-5': '端午',
      '7-7': '七夕',
      '8-15': '中秋',
      '9-9': '重阳',
      '12-8': '腊八'
    };
    return festivals[key] ?? '';
  }
}
