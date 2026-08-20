# Xiaohe Yinxing precise-match stage 4 evidence

Date: 2026-08-05  
Status: COMPLETED

## Full production-data audit

- Complete four-code space: 456976.
- Zero: 394265; unique: 59010; collision: 3701; max collision: 5.
- Every unique code auto-committed once; every collision waited, remained exact and stable, and kept all candidates reachable.
- Source-to-runtime audit covered 6636 short-code pairs and 59151 phrase pairs.
- Uniqueness changes covered 7 optional categories and 62711 non-empty four-codes.
- Two audit reports were byte-identical; all_checks_passed=true.

## Release A/B

- Covered 13781 distinct one-to-three-code prefixes from production data.
- Query P95: progressive 24600 ns, deterministic 8200 ns, reduction 66.6667%.
- Candidate transfer: 147910 to 6636, reduction 95.5135%.
- Candidate snapshot JSON: 15232656 bytes to 1104396 bytes, reduction 92.7498%.
- Independent Release-process working sets are supporting observations; deterministic gates use candidate and JSON byte totals.

## Resource and reproduction

- Formal bundle: 25397952 bytes, SHA-256 00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30.
- Reproduce: powershell -ExecutionPolicy Bypass -File scripts/generate-xiaohe-yinxing-precise-match-stage4.ps1.
- Machine reports: audit-report.json, performance-progressive.json, performance-deterministic.json, performance-comparison.json.
