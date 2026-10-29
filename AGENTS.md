# 窗口测试

- 所有 Liltiva 窗口测试始终在 AeroSpace 的 workspace 8 中进行。
- AeroSpace 已为 `io.github.yalyenea.Liltiva` 配置窗口创建规则，新窗口自动进入 workspace 8。启动或重启前先执行 `aerospace workspace 8`，再直接打开当前项目的 `.build/app/Liltiva.app`，不要先启动再查窗口 ID 搬过去。
- 优先复用正在运行的应用；只有加载新构建时才重启。
- 只有窗口未按规则进入 workspace 8 时才查询窗口 ID 并纠正位置；定位、移动和聚焦批量完成，避免重复搜索、切换和截图。
