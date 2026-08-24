# Windows 原生原型工具链记录

记录日期：2026-08-21
目标：Windows 11 x64 / Release / MSVC /MT

| 组件 | 版本或路径 | 结果 |
| --- | --- | --- |
| MSVC | Visual Studio 2019 BuildTools，14.29.30133 | 已安装 |
| MSBuild | 16.11.6.22506 | 已安装 |
| CMake | 4.4.2，WinGet 用户范围链接 | 已安装 |
| Windows SDK | 10.0.19041.0 | 已安装 |
| 生成器 | NMake Makefiles，经 VS 2019 VsDevCmd x64 环境 | 使用 |
| C++ 运行库 | Release /MT | CMake 强制设置 |

SSH 服务的 PATH 未包含 CMake 和 MSBuild，本原型验证命令显式使用已确认路径。

非交互 SSH 会话运行 PlatformChecks 时，RegisterHotKey 可能返回 Win32 错误 1459
(ERROR_INTERACTIVE_WINDOW_STATION_REQUIRED)。CTest 将退出码 77 标记为 skipped，不能把
该环境限制当作热键行为通过。交互验证使用 script/run_platform_checks_interactive.ps1，
该脚本以当前用户 SID、Interactive LogonType 和 Limited RunLevel 注册一次性任务，
并要求 PlatformChecks 实际返回 0。

验证记录：SSH build_stage1.cmd exit 0，CoreChecks PASS，PlatformChecks SKIP(77)。
run_platform_checks_interactive.ps1 exit 0，PlatformChecks PASS (8 resource classes)。
2.2 子阶段 B 验证：CoreChecks 独立 PASS（26 checks），JsonChecks 独立 PASS（45 checks），
CTest 中 Core/Json PASS、Platform SKIP(77)。JsonChecks 通过显式 build tests 目录参数读取
两个现有 fixture。

## Windows.Data.Json 局部兼容边界

Windows SDK 10.0.19041 的 C++/WinRT 基础头会在 C++20 编译路径触及
`<experimental/coroutine>`。因此只有 JSON Storage projection target 单独设置
`CXX_STANDARD 17` 与 `/await`；JsonChecks、Core、Platform、App 和其余检查继续使用
全局 C++20，没有全局启用 `/await`。Storage 仍继承 Release `/MT`、`/W4` 与 `/WX`，
并通过自身的链接接口传播 `runtimeobject`。

SDK 19041 的 `Windows.Foundation.0.h` 在 `/permissive-` 下会因 `impl::wait_for`
声明顺序产生 C2039；因此仅在 Storage projection target 追加 `/permissive`（追加顺序
晚于全局 `/permissive-`），JsonChecks、Core、Platform、App 和 CoreChecks 仍保持
`/permissive-`。

Storage 的公开头只暴露普通 C++ 字符串、Core 模型和 `RuntimeApartment`；WinRT 类型
仅存在于 codec 实现和专用检查。调用线程必须先创建 `RuntimeApartment`，其内部调用
`RoInitialize`，析构时调用 `RoUninitialize`。所有 `JsonArray`、`JsonObject` 与
`JsonValue` 局部对象必须先离开作用域，再释放 apartment。

3.1 路径解析使用独立的 `GhostPin.Native.StoragePaths` 与
`GhostPin.Native.StoragePathsChecks` target，保持全局 C++20、`/permissive-`、`/MT`、
`/W4`、`/WX`，不继承 JSON Storage 的 C++17 `/await` 兼容例外。系统 LocalAppData
通过 `SHGetKnownFolderPath(FOLDERID_LocalAppData)` 获取；检查只注入临时 root，绝不解析
或写入真实用户任务/设置文件。原生设置文件名固定为 `native-settings.json`，与 WPF 的
`settings.json` 隔离。
