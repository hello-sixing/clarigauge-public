# 内置运行环境

0.5.0 的采集器固定使用 Contents/Resources/python/bin/python3.12，启动参数为 -E -s -S -B。Python 解释器、libpython、所需标准库、许可证和来源校验清单都位于应用内部。

运行时复用 python-build-standalone 20260325 / CPython 3.12.13。上游说明见 https://github.com/astral-sh/python-build-standalone/blob/main/docs/distributions.rst 。仅保留运行部分，去除用户第三方包、安装器、测试、Tk 和字节码缓存，约28MiB。构建源不进入Git。

macOS 自带框架及 ps、nettop、ifconfig、route、ioreg、sysctl 等原生采集工具由操作系统提供。Macs Fan Control 继续作为可选外部调速入口。构建需要本机开发工具，安装使用时不需要另外安装 Python、Homebrew 或开发工具。

准备构建输入时执行以下命令，目标目录须为新的生成目录。

```sh
python3 scripts/bundle_runtime.py /path/to/standalone-python .local/python-runtime
./build.sh
```

验证包含解释器隔离导入、动态库引用审计、换路径后采集、无字节码缓存和正常应用入口验证。
