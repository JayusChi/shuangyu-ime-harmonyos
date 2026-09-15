// Produces the reviewed preview distribution; does not publish or upload anything.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zip = require('./vendor/zip-no-worker.min.js');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'outputs/keyboard-customization-editor-preview-20260909');
fs.mkdirSync(output,{recursive:true});
fs.copyFileSync(path.join(__dirname,'standalone.html'),path.join(output,'双羽键盘皮肤工坊.html'));
fs.copyFileSync(path.join(__dirname,'README.md'),path.join(output,'使用说明.md'));
fs.copyFileSync(path.join(root,'docs/features/keyboard-customization/EDITOR_ACCEPTANCE_20260909.md'),path.join(output,'验收记录.md'));
fs.copyFileSync(path.join(__dirname,'vendor/zip.js-LICENSE.txt'),path.join(output,'zip.js-LICENSE.txt'));
fs.cpSync(path.join(root,'outputs/keyboard-customization-templates-20260908'),path.join(output,'模板示例'),{recursive:true});
function files(dir) { return fs.readdirSync(dir,{withFileTypes:true}).flatMap(item=>item.isDirectory()?files(path.join(dir,item.name)):[path.join(dir,item.name)]); }
(async()=>{
  const entries = files(output).filter(file=>path.basename(file)!=='SHA256SUMS.txt').sort();
  fs.writeFileSync(path.join(output,'SHA256SUMS.txt'),entries.map(file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')+'  '+path.relative(output,file).replaceAll('\\','/')).join('\n')+'\n');
  const writer = new zip.ZipWriter(new zip.Uint8ArrayWriter(),{useWebWorkers:false});
  for(const file of files(output).sort()) await writer.add(path.relative(output,file).replaceAll('\\','/'),new zip.Uint8ArrayReader(fs.readFileSync(file)));
  const archive = await writer.close();
  fs.writeFileSync(output+'.zip',archive);
  const reader = new zip.ZipReader(new zip.Uint8ArrayReader(archive),{useWebWorkers:false});
  try {
    const packaged = await reader.getEntries();
    const html = packaged.find(entry=>entry.filename==='双羽键盘皮肤工坊.html');
    if(!html) throw new Error('Missing single-file entry');
    const htmlBytes = Buffer.from(await html.getData(new zip.Uint8ArrayWriter(),{checkSignature:true}));
    if(!htmlBytes.equals(fs.readFileSync(path.join(__dirname,'standalone.html')))) throw new Error('Packaged editor differs from source');
    if(/<script[^>]+src=|<link[^>]+stylesheet/i.test(htmlBytes.toString('utf8'))) throw new Error('Offline entry has external resources');
    if(!packaged.some(entry=>entry.filename==='验收记录.md') || !packaged.some(entry=>entry.filename==='zip.js-LICENSE.txt')) throw new Error('Missing distribution documentation');
  } finally { await reader.close(); }
  console.log(JSON.stringify({directory:output,zip:output+'.zip',bytes:archive.length,sha256:crypto.createHash('sha256').update(archive).digest('hex')},null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
