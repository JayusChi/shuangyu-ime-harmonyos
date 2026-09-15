const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const editor = path.join(root, 'tools/keyboard-customization-editor');
globalThis.zip = require(path.join(editor,'vendor/zip-no-worker.min.js'));
require(path.join(editor,'format.js')); require(path.join(editor,'package-io.js'));
const dir = path.join(__dirname,'fixtures');
const read = async name => EditorIO.read(Object.assign(new Blob([fs.readFileSync(path.join(dir,name))]),{name}));
(async()=>{
  const results=[];
  const bytes=fs.readFileSync(path.join(root,'examples/keyboard-customization/skin-soft-blue/assets/letter-key.png'));
  for(const device of ['phone','tablet','pc']) {
    const prefix='native.'+device;
    const skin=(await read(prefix+'.skin.sy-skin')).definition;
    assert.equal(skin.colors.panelBackground,'#12345680'); assert.equal(skin.colors.letterKeyBackground,'#FFFAFC');
    const layout=(await read(prefix+'.layout.sy-layout')).definition;
    assert.equal(layout.rows[0].keys[0].id,'letter-w'); assert.equal(layout.rows[0].keys[1].id,'letter-q');
    const space=layout.rows.flatMap(row=>row.keys).find(key=>key.id==='space');
    assert.equal(space.weight,6.3); assert.equal(space.label,device.toUpperCase());
    const updated=(await read(prefix+'.updated.sy-layout')).definition;
    assert.equal(updated.id,layout.id);
    const updatedSpace=updated.rows.flatMap(row=>row.keys).find(key=>key.id==='space');
    assert.equal(updatedSpace.weight,5.9); assert.equal(updatedSpace.label,'UPDATED');
    const images=await read(prefix+'.images.sy-skin'); assert.equal(Object.keys(images.definition.images).length,5);
    for(const ref of Object.values(images.definition.images)) assert.deepEqual(Buffer.from(await images.assets.get(ref).arrayBuffer()),bytes);
    for(const suffix of ['skin.sy-skin','layout.sy-layout','images.sy-skin','updated.sy-layout']) {
      const file=prefix+'.'+suffix;
      results.push({device,file,result:'PASS',sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(dir,file))).digest('hex')});
    }
  }
  fs.writeFileSync(path.join(__dirname,'native-export-results.json'),JSON.stringify(results,null,2));
  fs.writeFileSync(path.join(dir,'broken.sy-skin'),'Not a ZIP skin package');
  console.log('PASS 12 actual native browser exports: RGBA, preset, W/Q, width, labels, five image slots/bytes and same-ID updates.');
})().catch(error=>{console.error(error);process.exitCode=1;});
