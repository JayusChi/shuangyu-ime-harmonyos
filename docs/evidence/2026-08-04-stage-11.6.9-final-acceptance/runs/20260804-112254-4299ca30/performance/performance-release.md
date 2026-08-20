# Stage 11.6.3 formal bundle Release performance evidence

- Profile: release
- Independent process samples: 5
- Bundle SHA-256: 00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30
- Load ns min/avg/max: 618223500 / 636883560 / 662849000
- Query p95 ns min/avg/max: 18400 / 19820 / 23800
- State-cycle p95 ns min/avg/max: 1133900 / 1176220 / 1259900
- Load memory delta bytes min/avg/max: 59195392 / 59254374 / 59449344

This records the first Release baseline without inventing a threshold. Every process asserts fixed results before timing and accumulates a checksum.
