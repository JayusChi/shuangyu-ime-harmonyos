# Stage 11.6.3 formal bundle Release performance evidence

- Profile: release
- Independent process samples: 5
- Bundle SHA-256: 00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30
- Load ns min/avg/max: 623696200 / 651986900 / 681135300
- Query p95 ns min/avg/max: 18600 / 18880 / 19100
- State-cycle p95 ns min/avg/max: 1258400 / 1351800 / 1487400
- Load memory delta bytes min/avg/max: 59297792 / 59300250 / 59305984

This records the first Release baseline without inventing a threshold. Every process asserts fixed results before timing and accumulates a checksum.
