# Stage 11.6.3 formal bundle Release performance evidence

- Profile: release
- Independent process samples: 5
- Bundle SHA-256: 00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30
- Load ns min/avg/max: 611095100 / 639255780 / 667672500
- Query p95 ns min/avg/max: 15300 / 16160 / 17700
- State-cycle p95 ns min/avg/max: 11400 / 18420 / 24400
- Load memory delta bytes min/avg/max: 59248640 / 59260928 / 59265024

This records the first Release baseline without inventing a threshold. Every process asserts fixed results before timing and accumulates a checksum.
