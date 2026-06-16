# ThForu — Flutter AI Chat App

## 项目简介
- Flutter Android/Windows 多 AI 聊天应用，支持多 provider（DeepSeek、Qwen、OpenAI、MiMo 等）、专家兼听模式、语音输入、图片识别
- 底部导航：聊天 + GitHub 代码库
- 深度搜索：AI 拆解问题 + 多轮搜索 + 结构化报告
- GitHub 代码问答：Agent 式文件检索 + 选中代码问 AI
- 清新蓝色主题（Material 3）

## 技术栈
- **状态管理**：Riverpod (`flutter_riverpod`)
- **数据库**：SharedPreferences（键值对存储）
- **网络**：Dio（SSE 流式响应）
- **渲染**：flutter_math_fork（LaTeX）、flutter_markdown（Markdown）、flutter_svg（SVG）
- **GitHub API**：Dio（REST，支持 token / 匿名访问）

## 目录结构 (lib/)
```
lib/
├── main.dart                          # 入口
├── app.dart                           # MaterialApp + 路由 + RouteObserver
├── db/                                # 存储层
│   ├── storage.dart                   # SharedPreferences 存储
│   ├── database_helper.dart           # SQLite 初始化（备用）
│   ├── conversation_dao.dart          # 对话 CRUD
│   └── message_dao.dart               # 消息 CRUD
├── models/                            # 数据模型
│   ├── conversation.dart
│   ├── message.dart
│   ├── persona.dart                   # 角色预设
│   ├── provider_config.dart           # AI 配置（含预设）
│   └── expert_panel.dart              # 兼听面板
├── services/                          # 业务服务
│   ├── ai_service.dart                # AI API 调用（SSE 流式）
│   ├── expert_mode_service.dart       # 兼听模式服务
│   ├── audio_service.dart             # 语音录制
│   ├── image_service.dart             # 图片选取 + 裁剪
│   ├── search_service.dart            # DuckDuckGo 网页搜索
│   └── deep_search_service.dart       # 深度搜索（拆解 + 搜索 + AI 综合）
├── state/                             # Riverpod 状态管理
│   ├── chat_state.dart                # 聊天状态
│   ├── chat_notifier.dart             # 聊天逻辑（普通/专家/深度搜索模式）
│   ├── providers.dart                 # Provider 定义 + RouteObserver
│   ├── conversation_list_notifier.dart
│   ├── persona_list_notifier.dart
│   ├── expert_panel_list_notifier.dart
│   ├── provider_list_notifier.dart
│   ├── theme_notifier.dart
│   └── formula_display_notifier.dart  # 公式显示模式
├── screens/
│   ├── main_screen.dart               # 底部导航（聊天+GitHub）
│   ├── chat_screen.dart               # 聊天界面（流式光标/回到底部FAB/错误重试）
│   ├── conversations_screen.dart      # 对话列表（搜索+新建）
│   ├── settings_screen.dart           # 设置（主题/模型/角色/兼听）
│   ├── favorites_screen.dart          # 收藏消息（RouteAware 实时刷新）
│   └── github_screen.dart             # GitHub 代码库（文件树/代码预览/AI问答/刷新）
└── widgets/
    ├── math_markdown.dart             # ★ 核心：Markdown+LaTeX+SVG 混合渲染
    ├── message_bubble.dart            # 消息气泡（长按菜单/追问引用/加粗渲染）
    ├── chat_input_bar.dart            # 输入栏（图片/文件/语音/深度搜索开关）
    ├── streaming_cursor.dart          # 流式闪烁光标
    ├── typing_indicator.dart          # 跳动三点动画
    ├── svg_block.dart                 # SVG 渲染 + 全屏查看
    ├── formula_viewer.dart            # 全屏公式查看器
    ├── conversation_tile.dart         # 对话列表项
    ├── expert_progress_widget.dart    # 兼听进度
    ├── expert_panel_form_dialog.dart
    ├── persona_form_dialog.dart
    ├── provider_form_dialog.dart
    └── image_preview_sheet.dart
```

## 核心渲染管线 (math_markdown.dart)
1. **块级提取** `_findBlockSpecials`: 提取 `$$...$$` / `\[...\]` / `<svg>`
2. **表格渲染** `_TableBlock`: `Table` + `IntrinsicColumnWidth` + `SingleChildScrollView` + 全屏 `InteractiveViewer`
3. **行内渲染** `_InlineRichSegment`: `RichText` + `WidgetSpan`（行内公式流式嵌入）
4. **LaTeX 预处理** `_preprocessLatex()`: 清洗不可见字符 + 剥离小众命令 + 环境转换 → `Math.tex()`
5. **公式保护** `_protectUnderscoresInMath()`: 转义 `$...$` 内 `_` 防止 markdown 斜体破坏
6. **代码框/引用框**: 顶部「复制」+「放大」按钮，全屏支持 `FittedBox` 自动适配 + `InteractiveViewer` 缩放
7. **表格加粗**: `_parseCellMarkdown()` 解析 `**text**` 为加粗富文本

## 功能特性
- ✅ 多 AI Provider 支持（DeepSeek、Qwen3、OpenAI、MiMo、自定义）
- ✅ 专家兼听模式（多 AI 同时回答，网关汇总）
- ✅ 角色预设（System Prompt）
- ✅ 流式回复（SSE），200ms UI 节流 + 2s DB 节流
- ✅ 流式闪烁光标（StreamingCursor）
- ✅ 图片识别（拍照裁剪 + 相册多选）
- ✅ 语音输入
- ✅ 文件发送
- ✅ LaTeX 公式渲染（行内 + 块级）
- ✅ Markdown 表格（列对齐 + 水平滑动 + 全屏缩放 + 加粗渲染）
- ✅ 代码块（水平滚动 + 全屏缩放）
- ✅ SVG 渲染（自适应屏幕 + 居中 + 全屏缩放）
- ✅ 引用框渲染
- ✅ 微信风格追问（引用回复 + 灰色引用条 + 点击跳转）
- ✅ 收藏消息（RouteAware 实时同步）
- ✅ 对话搜索（20 条限制 + 最新优先 + 跳转消息）
- ✅ 壁纸设置
- ✅ 底部导航（聊天 + GitHub）
- ✅ 清新蓝色主题 + 深色模式
- ✅ 深度搜索（AI 拆解 + DuckDuckGo 搜索 + 网页提取 + 结构化报告）
- ✅ GitHub 代码库连接（token / 匿名）
- ✅ GitHub 文件树浏览器（文件夹层级 + 搜索 + 刷新）
- ✅ GitHub 代码预览（语法高亮 + 选中问 AI）
- ✅ GitHub Agent 问答（AI 自主选文件 + 读取代码 + 回答）
- ✅ 消息长按菜单（复制 / 引用回复 / 收藏 / 删除）
- ✅ 搜索结果关键词高亮
- ✅ 流式自动滚动（用户上滑暂停 + 回到底部 FAB）
- ✅ 错误重试机制（可折叠错误 + 重试按钮）
- ✅ 平板 SafeArea 适配

## 构建命令
```bash
# Android APK
flutter build apk --release --no-tree-shake-icons

# Windows
flutter run -d windows
```

## 已知限制
- `flutter_math_fork` 不支持部分高级 LaTeX 命令（`\mathbb`、`\mathcal` 等）
- `flutter_markdown` 已 discontinued（替代品 flutter_markdown_plus）
- Windows debug 模式下 `Math.tex` + `IntrinsicColumnWidth` 会触发 `LayoutBuilder` 断言（release 模式不影响）
- AGP 8.9.1 / Kotlin 2.1.20 有弃用警告
- GitHub API 匿名访问限制 60 次/小时
- 深度搜索使用 DuckDuckGo HTML 解析，可能受地区限制
