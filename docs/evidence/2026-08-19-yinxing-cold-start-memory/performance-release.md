# Xiaohe Yinxing production Release performance evidence

- Profile: release
- Independent process samples: 5
- Bundle SHA-256: 6010300516e9e58da6cbbb4d136f70db0be137743122b2c29ce3175fe76fc4f5
- Load ns min/avg/max: 159983600 / 166507120 / 177857600
- Shared immutable index reload p50 ns: 258000
- Query p95 ns min/avg/max: 20400 / 22360 / 23900
- State-cycle p95 ns min/avg/max: 1233400 / 1443620 / 1634100
- Load memory delta bytes min/avg/max: 15585280 / 15592653 / 15597568

Every process validates fixed query results before timing and accumulates a checksum. Device RSS and latency require the separate ARM64 collector.
