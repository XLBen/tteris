# AGENTS.md

Godot 4.7 游戏项目（Forward Plus 渲染，Windows 下 D3D12，Jolt Physics）。

## 常用命令

godot 可执行文件不在 PATH 中时，向用户询问路径，不要猜测。

- godot 路径（owner 提供，2026-09-18）：`E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`（Steam 版工具构建）

- 校验单个脚本：`godot --headless --check-only --script res://路径.gd`
- 导入资源并检查项目能否加载：`godot --headless --editor --quit`
- 运行游戏：`godot --path .`

## 项目约定

- 语言为 GDScript（Godot 4 语法），不使用 C#。
- 缩进用 Tab，编码 UTF-8（见 .editorconfig）。
- 命名：文件名/变量/函数用 snake_case，类名 PascalCase，常量 CONSTANT_CASE，私有成员加 `_` 前缀，信号用过去式（如 `player_died`）。
- 目录组织：场景放 `scenes/`，脚本放 `scripts/`，资源放 `assets/`，按需创建。
- `.godot/` 是编辑器生成目录，禁止编辑、禁止提交。
- `project.godot`、`*.tscn`、`*.tres` 是文本文件可直接编辑，但保持 Godot 的序列化格式与键顺序，只做最小改动。
- 修改 GDScript 后尽量运行 check-only 校验；涉及场景/资源时运行 `--editor --quit` 验证项目可正常加载，无法运行时说明原因。
