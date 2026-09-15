const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const editor=path.resolve(__dirname,'../../tools/keyboard-customization-editor');
globalThis.zip=require(path.join(editor,'vendor/zip-no-worker.min.js'));
require(path.join(editor,'format.js'));require(path.join(editor,'package-io.js'));
(async()=>{
  const read=async name=>(await EditorIO.read(Object.assign(new Blob([fs.readFileSync(path.join(__dirname,'computer',name))]),{name}))).definition;
  const skin=await read('qa.roundtrip.pc.skin.sy-skin');
  const layout=await read('qa.roundtrip.pc.layout.sy-layout');
  assert.equal(skin.id,'qa.roundtrip.pc.skin');assert.equal(skin.colors.panelBackground,'#123456');
  assert.equal(skin.colors.letterKeyBackground,'#FFFAFC');
  assert.equal(layout.id,'qa.roundtrip.pc.layout');
  assert.equal(layout.rows[0].keys[0].id,'letter-w');assert.equal(layout.rows[0].keys[1].id,'letter-q');
  const space=layout.rows.flatMap(r=>r.keys).find(k=>k.id==='space');
  assert.equal(space.weight,6.3);assert.equal(space.label,'qa space');
  fs.writeFileSync(path.join(__dirname,'verified-exports.json'),JSON.stringify({skin,layout},null,2));
  console.log('PASS: native browser exports contain custom colors, W/Q order, width 6.3 and qa space label');
})().catch(e=>{console.error(e);process.exitCode=1;});
