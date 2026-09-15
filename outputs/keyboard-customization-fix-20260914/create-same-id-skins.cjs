const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),editor=path.join(root,'tools/keyboard-customization-editor');
globalThis.zip=require(path.join(editor,'vendor/zip-no-worker.min.js'));
require(path.join(editor,'format.js'));require(path.join(editor,'package-io.js'));
(async()=>{
 const dark=new Blob([fs.readFileSync(path.join(root,'entry/src/main/resources/base/media/danran_key_dark.png'))],{type:'image/png'});
 for(const d of ['phone','pc','tablet']) {
  const original='native.'+d+'.images.sy-skin';
  const read=await EditorIO.read(Object.assign(new Blob([fs.readFileSync(path.join(__dirname,'fixtures',original))]),{name:original}));
  for(const p of Object.values(read.definition.images)) read.assets.set(p,dark);
  // Keep the ID and every image path identical: exercise replacement and image caches.
  read.definition.colors.letterKeyText='#FFFFFF';
  read.definition.colors.functionKeyText='#FFFFFF';
  const blob=await EditorIO.write('skin',read.definition,read.assets);
  const bytes=Buffer.from(await blob.arrayBuffer());
  fs.writeFileSync(path.join(__dirname,'fixtures','same-id-'+d+'.sy-skin'),bytes);
  const checked=await EditorIO.read(Object.assign(new Blob([bytes]),{name:'test.sy-skin'}));
  assert.equal(checked.definition.id,'native.'+d+'.images');
  for(const p of Object.values(checked.definition.images)) assert.deepEqual(Buffer.from(await checked.assets.get(p).arrayBuffer()),Buffer.from(await dark.arrayBuffer()));
 }
 console.log('PASS three same-ID same-path replacement skin fixtures');
})().catch(e=>{console.error(e);process.exitCode=1});
