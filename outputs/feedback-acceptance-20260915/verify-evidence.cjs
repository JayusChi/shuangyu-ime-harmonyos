const fs = require('node:fs');
const path = require('node:path');
const base = __dirname;
const checks = [];
const measurements = [];
function nodes(n, parents = []) {
  const a = n.attributes;
  return [...(a ? [{...a, parents}] : []), ...(n.children || []).flatMap(c => nodes(c, a ? [...parents, a] : parents))];
}
function read(device, name) {
  return nodes(JSON.parse(fs.readFileSync(path.join(base, device, name + '.json'), 'utf8').replace(/^\uFEFF/, '')));
}
function check(name, pass, detail) { checks.push({name, pass: Boolean(pass), detail}); }
function chat(n) { return n.find(a => a.hint === 'ACCEPT_CHAT_SEND')?.text; }
function candidates(n) { return n.filter(a => /^[1-9] /.test(a.text)); }
function box(a) {
  const [left,top,right,bottom] = a.bounds.match(/\d+/g).map(Number);
  return {left,top,right,bottom,width:right-left,height:bottom-top};
}
for (const device of ['phone','computer']) {
  const initial = read(device, 'initial-unfocused');
  check(device + ': enter without keyboard', !initial.some(a=>a.text==='Q'), 'initial-unfocused.json');
  const shown = read(device, device==='phone'?'after-focus':'touch-current');
  check(device + ': click opens keyboard', shown.some(a=>a.text==='Q'), device==='phone'?'after-focus.json':'touch-current.json');
  for (const [name, expected] of [
    ['trailing-a-commit','不是你啊'], ['fixed-zm-commit','你怎么不行'], ['fixed-up-commit','我用双拼'],
    ['semicolon-empty','；'], ['semicolon-composition','；你；'],
    ['inline-kj','你kj'], ['inline-kjk','你kjk'], ['inline-kj-back','你kj'],
    ['inline-commit','你看'], ['inline-cancel','你看']
  ]) {
    const actual = chat(read(device,name));
    check(`${device}: ${name}`,actual===expected,{expected,actual,evidence:`${device}/${name}.json`});
  }
  check(device + ': inline hides candidate-area code',!read(device,'inline-kj').some(a=>a.text==='kj'),'inline-kj.json');
  check(device + ': test lexicon removed',read(device,'lexicon-restored').some(a=>a.text==='暂无词条，可在上方添加或从文本导入'),'lexicon-restored.json');
  const prefix=device==='phone'?'hardware-paging-':'paging-';
  const first=candidates(read(device,prefix+'first')).map(a=>a.text);
  const next=candidates(read(device,prefix+'next')).map(a=>a.text);
  const previous=candidates(read(device,prefix+'prev')).map(a=>a.text);
  check(device + ': 5 candidates per page',first.length===5 && next.length===5,{first,next});
  check(device + ': previous restores first page',JSON.stringify(first)===JSON.stringify(previous),previous);
  const actual=chat(read(device,prefix+'selected'));
  check(device + ': current page numeric selection',actual===next[1].slice(2),{expected:next[1].slice(2),actual});
  for (const page of ['first','next','prev']) {
    const n=read(device,prefix+page), c=candidates(n);
    check(`${device}: ${page} stays horizontal`,!n.some(a=>a.text==='展开') && Math.max(...c.map(a=>box(a).top))-Math.min(...c.map(a=>box(a).top))<=20,prefix+page+'.json');
  }
  const sequence=[];
  for (const name of ['floating-f','floating-fi','floating-fih','floating-fi-back']) {
    const n=read(device,name);
    const raw=n.find(a=>/^f(i('?h)?)?$/.test(a.text));
    if(!raw)throw Error('Missing preedit: '+device+'/'+name);
    const card=raw.parents.find(a=>a.type==='Row' && a.backgroundColor==='#FFFFFFFF');
    const first=candidates(n)[0];
    const r=box(raw),c=box(card),f=box(first);
    sequence.push({name,raw:raw.text,rawBounds:r,cardBounds:c,cardToRaw:r.left-c.left,gapToFirst:f.left-r.right,first:first.text,candidateCount:candidates(n).length});
  }
  check(device + ': preedit starts at fixed left inset',new Set(sequence.map(s=>s.cardToRaw)).size===1,sequence.map(s=>s.cardToRaw));
  check(device + ': candidates follow code without centering',new Set(sequence.map(s=>s.gapToFirst)).size===1,sequence.map(s=>s.gapToFirst));
  check(device + ': floating card height remains stable',new Set(sequence.map(s=>s.cardBounds.height)).size===1,sequence.map(s=>s.cardBounds.height));
  measurements.push({device,sequence});
}
const page10=candidates(read('computer','batch-page-10')).map(a=>a.text);
const page11=candidates(read('computer','batch-page-11')).map(a=>a.text);
const back10=candidates(read('computer','batch-back-10')).map(a=>a.text);
check('computer: engine batch boundary returns to page 10',JSON.stringify(page10)===JSON.stringify(back10),{page10,page11,back10});
check('computer: batch boundary selection',chat(read('computer','batch-back-selected'))===page10[4].slice(2),chat(read('computer','batch-back-selected')));
check('phone: upper semicolon commits composition',chat(read('phone','touch-semicolon-composition'))==='你;',chat(read('phone','touch-semicolon-composition')));
check('phone: letters after semicolon resume pinyin',read('phone','touch-semicolon-follow-letter').some(a=>a.text==='h') && read('phone','touch-semicolon-follow-letter').some(a=>a.text==='1 和'),'touch-semicolon-follow-letter.json');
check('phone: inline preference survives restart',chat(read('phone','inline-after-restart'))==='ni','inline-after-restart.json');
check('computer: touch focus accepts input',chat(read('computer','touch-focus-commit'))==='你','touch-focus-commit.json');
check('phone: 5 candidates remain visible after settling',candidates(read('phone','hardware-clipping-repro-next')).length===5,'hardware-clipping-repro-next.json');
check('phone: clipped fifth candidate still selects correctly',chat(read('phone','hardware-clipping-number-5'))==='室','hardware-clipping-number-5.json');
for(const device of ['phone','computer']) {
  check(device + ': reentry stays hidden',!read(device,'reentry-hidden').some(a=>a.text==='Q'),'reentry-hidden.json');
  const finalSettings=read(device,'final-candidate-settings');
  check(device + ': inline restored off',finalSettings.some(a=>a.type==='Toggle' && a.checked==='false'),'final-candidate-settings.json');
  check(device + ': candidate count restored to 5',finalSettings.some(a=>a.text==='5 项'),'final-candidate-settings.json');
  const mode=read(device,'final-input-settings');
  check(device + ': input mode restored',mode.some(a=>a.text===(device==='phone'?'自动识别':'虚拟键盘')),'final-input-settings.json');
}
const result={passed:checks.filter(c=>c.pass).length,failed:checks.filter(c=>!c.pass).length,checks,measurements};
fs.writeFileSync(path.join(base,'verification.json'),JSON.stringify(result,null,2));
console.log(`${result.passed} passed, ${result.failed} failed`);
for(const c of checks.filter(c=>!c.pass))console.log(JSON.stringify(c));
if(result.failed)process.exitCode=1;
