const fs = require('node:fs');
const path = require('node:path');
const checks = [];
const flatten = n => [n.attributes, ...(n.children || []).flatMap(flatten)].filter(Boolean);
const read = (device, name) => flatten(JSON.parse(fs.readFileSync(path.join(__dirname, device, name + '.json'), 'utf8').replace(/^\uFEFF/, '')));
const candidates = nodes => nodes.filter(n => /^[1-9] /.test(n.text));
const texts = nodes => candidates(nodes).map(n => n.text);
const chat = nodes => nodes.find(n => n.hint === 'ACCEPT_CHAT_SEND')?.text;
const check = (name, pass, detail) => checks.push({name, pass: Boolean(pass), detail});
for (const device of ['phone', 'computer']) {
  for (const name of ['page-1','page-2','back-1','back-2', ...Array.from({length:11}, (_,i)=>`batch-${i+1}`),'batch-back-10']) {
    const nodes = read(device,name), items = candidates(nodes);
    check(`${device}/${name}: five visible`, items.length === 5, texts(nodes));
    check(`${device}/${name}: no clipping`, items.length === 5 && items.every(n=>n.bounds === n.origBounds), items.map(n=>({text:n.text,bounds:n.bounds,origBounds:n.origBounds})));
    const centers = items.map(n=>{const b=n.bounds.match(/\d+/g).map(Number);return (b[1]+b[3])/2;});
    check(`${device}/${name}: horizontal`, Math.max(...centers)-Math.min(...centers)<=1, centers);
    check(`${device}/${name}: keyboard paging`, !nodes.some(n=>n.hostWindowId===items[0]?.hostWindowId && ['展开','‹','›'].includes(n.text)), 'No expand or touch pager in candidate window');
  }
  const first=texts(read(device,'page-1')), second=texts(read(device,'page-2'));
  check(`${device}: next page differs`,JSON.stringify(first)!==JSON.stringify(second),second);
  check(`${device}: previous page restores`,JSON.stringify(first)===JSON.stringify(texts(read(device,'back-1'))),first);
  check(`${device}: fifth number commits`,chat(read(device,'number-5'))===second[4].slice(2),chat(read(device,'number-5')));
  const tenth=texts(read(device,'batch-10'));
  check(`${device}: batch boundary previous`,JSON.stringify(tenth)===JSON.stringify(texts(read(device,'batch-back-10'))),tenth);
  check(`${device}: batch fifth number commits`,chat(read(device,'batch-number-5'))===second[4].slice(2)+tenth[4].slice(2),chat(read(device,'batch-number-5')));
  check(`${device}: touch pager preserved`,read(device,'touch-pager').some(n=>n.type==='Button' && n.text==='›'),'touch-pager.json');
  check(`${device}: mode restored`,read(device,'restored-input-settings').some(n=>n.text===(device==='phone'?'自动识别':'虚拟键盘')),'restored-input-settings.json');
  check(`${device}: candidate count preserved`,read(device,'restored-candidate-settings').some(n=>n.text==='5 项'),'restored-candidate-settings.json');
  check(`${device}: fixed bar restored`,read(device,'restored-candidate-settings').some(n=>n.text==='固定候选栏'),'restored-candidate-settings.json');
}
const result={passed:checks.filter(c=>c.pass).length,failed:checks.filter(c=>!c.pass).length,checks};
fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(result,null,2));
console.log(`${result.passed} passed, ${result.failed} failed`);
for(const c of checks.filter(c=>!c.pass)) console.log(JSON.stringify(c));
if(result.failed) process.exitCode=1;
