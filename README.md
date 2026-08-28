# Linodas Card Harvester

自动抓取 [World of Linodas](https://www.linodas.com) 卡牌信息页面，解析并保存为 JSON 数据。

本项目作者为 42，当前版本为 `2026/8/28 - Release`。

[World of Linodas](https://www.linodas.com) 所有者为 [Lyragosa](https://www.lyragosa.com/)。

## 程序功能

- 多线程并发爬取卡牌数据
- 自动解析网页，提取卡牌属性
- 支持自定义起始/结束 ID、线程数、请求间隔、重试次数
- 输出格式为 `data.json`

## 系统要求

- Windows 10/11 64 位
- PowerShell 5.1 或更高版本
- 至少 2 GB 可用磁盘空间（用于下载编译工具和编译）
- 需要联网（脚本内置下载重试与代理回退）

## 一键构建

将 `LinodasCardHarvesterBuilder.ps1` 移动至目标目录，使用 PowerShell 执行：

```powershell
cd [脚本所在目录]
# 暂时解除组策略，允许执行脚本：
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\LinodasCardHarvesterBuilder.ps1
```

脚本会自动完成以下步骤：

1. 下载并安装 7-Zip、Aria2、MinGW-w64、libcurl、nlohmann/json
2. 校验下载文件 SHA512 哈希
3. 生成 `crawler.cpp` 源文件
4. 使用 MinGW 编译 `crawler.exe`
5. 复制运行时 DLL 到当前目录
6. 运行 `crawler.exe --version` 验证

### 构建脚本参数

| 参数 | 说明 |
|------|------|
| `-UseProxyFirst` | 优先使用 GitHub 代理下载（适用于网络受限环境） |
| `-NoProxy` | 禁用所有代理，仅使用直连（覆盖 `-UseProxyFirst`） |

示例：`.\LinodasCardHarvesterBuilder.ps1 -UseProxyFirst`

### 构建产物

构建后所在目录下会生成以下文件/文件夹：

- `crawler.exe`：主程序
- `crawler.cpp`：自动生成的源码
- `*.dll`：运行时库（请勿删除）
- `download/`：下载的压缩包
- `tools/`：解压后的编译工具
- `include/`：第三方头文件
- `data.json`：爬取数据（运行爬虫后将出现）

可手动删除 `download/` 和 `tools/` 以节省磁盘空间，但下次构建需重新下载。

## 使用方式

构建完成后，在当前目录得到 `crawler.exe`。运行：

```powershell
.\crawler.exe
```

默认爬取 ID 1~10000 的卡牌。常用参数：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--start <n>` | 起始卡牌 ID | 1 |
| `--end <n>` | 结束卡牌 ID | 10000 |
| `--threads <n>` | 并发线程数（1~32） | 4 |
| `--interval <ms>` | 请求间隔毫秒数（0 表示无等待） | 50 |
| `--retry <n>` | 单请求失败重试次数 | 3 |
| `--help` | 显示帮助 | - |
| `--version` | 显示版本信息 | - |
| `--license` | 显示 MIT 许可证文本 | - |

示例：

```powershell
# 爬取 ID 1~500，使用 8 线程，间隔 100 毫秒
.\crawler.exe --start 1 --end 500 --threads 8 --interval 100
```

爬取结果将保存至当前目录的 `data.json` 中。

## 网络资源

构建脚本会自动下载以下第三方组件（均通过 SHA512 校验）：

| 名称 | 用途 | 来源 | 许可证 |
|------|------|------|--------|
| Aria2 | 高速下载工具 | [Github Release](https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip) | GPLv2 |
| MinGW-w64 (winlibs 构建) | C++ 编译器与运行库 | [Github Release](https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip) | GPLv3+（含 GCC Runtime Library Exception）等 |
| libcurl | HTTP 网络库 | [Curl](https://curl.se/windows/dl-8.21.0_7/curl-8.21.0_7-win64-mingw.zip) | Curl License（MIT 风格） |
| nlohmann/json | JSON 解析头文件 | [Github Release](https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp) | MIT |
| 7-Zip (7zr/7za) | 解压工具 | 7zr.exe: [7-zip](https://www.7-zip.org/a/7zr.exe)<br>7za 附加包: [Github Release](https://github.com/ip7z/7zip/releases/download/26.02/7z2602-extra.7z) | LGPL/BSD 等 |

MinGW-w64 编译器、7-zip、Aria2 仅作为独立程序被使用。

MinGW-w64 运行时库、libcurl、nlohmann/json 采用的许可证与 MIT 许可证兼容。

## 许可证

本项目（包含 `LinodasCardHarvesterBuilder.ps1` 和自动生成的 `crawler.cpp`）采用 **MIT License**。

完整许可证文本请参阅脚本头部注释或运行 `crawler.exe --license`。

## 网络代理

构建脚本为来自 GitHub 的资源提供了 gh-proxy.com 代理镜像作为备选下载源，并与官方源下载的文件使用相同的 SHA512 哈希进行校验，保证安全无误。

使用 `-NoProxy` 参数以禁止代理。

## 常见问题

**构建时长与停止**

若网络与设备环境良好，3-5 min 即可成功构建。

对于不可缺失的关键网络资源，构建脚本将无限尝试直到成功获取。

在网络受限的国家或地区，构建脚本将尝试多种下载方式并使用代理，可能需要些许时间。

按下 `Ctrl + C` 以安全停止构建脚本或爬虫程序。

**下载失败或超时**

请优先尝试使用 `-UseProxyFirst` 参数并检查网络能否访问 GitHub、curl.se 等站点。

可以从镜像源人工获取资源文件后放入脚本所在目录下的 download/ 文件夹（切勿解压，仍会校验哈希以确保安全）。

**编译错误**

删除 `tools`、`download`、`include` 文件夹后重新运行脚本。

若多次尝试均失败请提交 Issues。

**运行时提示缺少 DLL**

构建脚本会自动复制所需 DLL，若缺失可删除 tools\ 文件夹并重新运行构建脚本或手动从 `tools\mingw64\bin` 和 `tools\curl\bin` 复制。

**如何卸载**

删除脚本所在目录的所有文件即可。

**是否免费**

本项目采用 MIT 许可证，可自由使用、修改和分发，无需付费。

## 法律声明

本工具仅供个人学习、研究和技术交流使用。

使用者应当：

- 遵守[目标网站](https://www.linodas.com)的 [EULA](https://www.linodas.com/site/eula)、[robots.txt](https://www.linodas.com/robots.txt) 及适用法律法规
- 在爬取前获得网站所有者的明确许可
- 合理设置请求频率，避免对目标服务器造成过大压力
- 不将抓取的数据用于商业用途或未经授权的再分发

使用本工具可能带来以下风险，务必知悉：

- IP 地址或游戏账号可能因高频访问被目标网站封锁。
- 不当使用可能违反目标网站的服务条款或适用法律，导致法律纠纷。
- 过度请求可能影响服务器稳定性，损害其他用户利益。

因使用本工具产生的任何后果，由使用者自行承担。作者不对滥用行为负责。

## 权限说明

若项目行为与描述不同，请立刻停止脚本或程序，并检查项目来源。

- 构建脚本**会**读写所在目录下的文件
- 爬虫程序**会**读写所在目录下的文件
- 构建脚本**会**访问网络
- 爬虫程序**会**访问网络
- 构建脚本**不会**读写注册表、环境变量或非所在目录下的文件
- 爬虫程序**不会**读写注册表、环境变量或非所在目录下的文件
- 构建脚本**不会**弹出 UAC 弹窗
- 爬虫程序**不会**弹出 UAC 弹窗

## 其它信息

**关于 [Github 仓库中的 data.json](data.json)**

2026/8/28 9:00 的爬取结果，爬取和上传均已获得 Linodas 所有者 [Lyragosa](https://www.lyragosa.com/) 的授权。

该文件用于爬取结果示范与资料存储。
