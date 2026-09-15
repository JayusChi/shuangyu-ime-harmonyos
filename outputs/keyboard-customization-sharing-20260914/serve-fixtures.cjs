const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../output/playwright/skin-editor-acceptance-20260909');
const files = ['chrome-layout.sy-layout', 'chrome-tablet.sy-skin', 'chrome-images.sy-skin'];
http.createServer((req, res) => {
  const name = new URL(req.url, 'http://localhost').pathname.slice(1);
  if (!name) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><h1>共享皮肤验收文件</h1>' + files.map(n => `<p style="padding:24px"><a href="/${n}">${n}</a></p>`).join(''));
  } else if (files.includes(name)) {
    res.writeHead(200, {'Content-Type':'application/octet-stream','Content-Disposition':`attachment; filename="${name}"`});
    res.end(fs.readFileSync(path.join(root, name)));
  } else res.writeHead(404).end();
}).listen(8774, '127.0.0.1', () => console.log('Fixture server ready: 127.0.0.1:8774'));
