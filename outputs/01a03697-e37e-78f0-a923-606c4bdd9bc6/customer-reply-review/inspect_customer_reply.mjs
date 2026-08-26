import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const [inputPath, outputDir] = process.argv.slice(2);
if (!inputPath || !outputDir) {
  throw new Error("usage: inspect_customer_reply.mjs <input.xlsx> <output-dir>");
}

await fs.mkdir(outputDir, { recursive: true });
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 12000,
  tableMaxRows: 12,
  tableMaxCols: 18,
  tableMaxCellChars: 160,
});
await fs.writeFile(path.join(outputDir, "overview.ndjson"), overview.ndjson, "utf8");

const sheets = ["客户确认总览", "44条逐项映射", "口径与审批"];
const ranges = {
  "客户确认总览": "A1:H40",
  "44条逐项映射": "A1:P60",
  "口径与审批": "A1:H40",
};

for (const sheetName of sheets) {
  const sheet = workbook.worksheets.getItem(sheetName);
  const targetRange = ranges[sheetName];
  const table = await workbook.inspect({
    kind: "table",
    sheetId: sheetName,
    range: targetRange,
    include: "values,formulas",
    maxChars: 120000,
    tableMaxRows: 70,
    tableMaxCols: 20,
    tableMaxCellChars: 600,
  });
  await fs.writeFile(path.join(outputDir, `${sheetName}.ndjson`), table.ndjson, "utf8");

  const rendered = await workbook.render({
    sheetName,
    autoCrop: "all",
    scale: 1,
    format: "png",
  });
  await fs.writeFile(
    path.join(outputDir, `${sheetName}.png`),
    new Uint8Array(await rendered.arrayBuffer()),
  );
}

console.log(overview.ndjson);
