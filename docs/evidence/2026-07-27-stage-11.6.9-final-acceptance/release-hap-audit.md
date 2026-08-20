# Release HAP audit

| 产物 | 大小 | SHA-256 |
| --- | ---: | --- |
| signed Release `entry/build/default/outputs/default/entry-default-signed.hap` | 37,707,165 | `7839064fef252d2438699ac622acfe48a73ada98a3c4d245ec525985b32c0e90` |
| unsigned Release `entry/build/artifacts/entry-release-unsigned.hap` | 37,572,616 | `2faa2c97b829ec438a07650fe6c17f256699253effca47f77601e676884c85d0` |
| internalDebug `entry/build/artifacts/entry-debug-unsigned.hap` | 40,801,306 | `f1551be1cd0b13453798673bec1fa6db972d4f1c419972680ae1ef690830cf8d` |
| 正式 bundle | 25,397,952 | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |

Release rawfile 精确白名单：

- `production.lex`
- `xiaohe-yinxing-production.hsyx`

unsigned/signed HAP 内容门禁均 PASS。签名工具 `verify-app` PASS。证书链标识哈希：
`ba3fd1d5173eee651926d12a942f41b943fae95d94cf198db2b9242d1b79fa0b`；
profile 标识哈希：
`2f8825cd015ab95b5367084b25a9c0dc0fc571c4531e51a7c9db377ba3b9c5f3`。
未记录密码或私钥路径。
