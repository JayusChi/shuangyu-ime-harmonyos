# pypinyin 0.55.0 production build tool

- Upstream: <https://github.com/mozillazg/python-pinyin>
- Distribution: `pypinyin-0.55.0-py2.py3-none-any.whl`
- SHA-256: `d53b1e8ad2cdb815fb2cb604ed3123372f5a28c6f447571244aca36fc62a286f`
- License: MIT, retained at `dictionaries/LICENSES/pypinyin-MIT.txt`

The pinned wheel is unpacked into a temporary directory only while generating
the full-pinyin TSV. It is not packaged in the HAP and the build never installs
or downloads a Python dependency.
