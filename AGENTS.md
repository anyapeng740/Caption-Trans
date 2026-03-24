# Repository Guidelines

## 项目结构与模块组织
- Flutter 核心代码位于 `lib/`。
- UI 页面与组件：`lib/ui/`、`lib/ui/widgets/`。
- 状态管理（BLoC）：`lib/blocs/{project,transcription,translation}/`。
- 业务逻辑与集成：`lib/services/`（audio、translation、whisper、settings、updates）。
- 领域模型：`lib/models/`；公共常量与工具：`lib/core/`。
- 国际化资源：`lib/l10n/`（`app_en.arb`、`app_zh.arb` 及生成的本地化文件）。
- 平台工程与构建配置：`android/`、`ios/`、`macos/`、`windows/`、`linux/`、`web/`。
- 测试代码在 `test/`，结构按服务域组织（如 `test/services/translation/*`）。

## 构建、测试与开发命令
- `flutter pub get`：安装依赖。
- `flutter run -d macos` 或 `flutter run -d windows`：本地运行桌面端。
- `flutter analyze`：执行静态检查（使用项目 lint 规则）。
- `flutter test`：运行单元测试与组件测试。
- `flutter build macos --release` / `flutter build windows --release`：构建发布版本。
- `dart run flutter_launcher_icons`：图标资源更新后重新生成应用图标。

## 代码风格与命名规范
- 遵循 `analysis_options.yaml` 中的 `package:flutter_lints` 默认规则。
- 使用 2 空格缩进；在复杂 widget 结构中合理使用尾随逗号提升可读性。
- 文件名使用 `snake_case.dart`；类/类型使用 `PascalCase`；方法与变量使用 `lowerCamelCase`。
- BLoC 的事件、状态、逻辑文件按特性同目录放置（`*_event.dart`、`*_state.dart`、`*_bloc.dart`）。

## 测试规范
- 使用 `flutter_test` 编写单元测试和组件测试。
- 测试文件命名为 `*_test.dart`；按目标类或服务分组（如 `group('TranslationService', ...)`）。
- 服务层测试优先放在 `test/services/...`，通过 fake/mock 隔离 HTTP 与外部 provider。
- 提交 PR 前运行 `flutter test`；新增功能与缺陷修复应补充对应测试。

## 提交与 Pull Request 规范
- 提交信息沿用 Conventional Commits：`feat: ...`、`fix: ...`，可选 scope（如 `feat(whisperx): ...`）。
- 保持单次提交聚焦、原子化，摘要使用祈使语气。
- PR 需包含：变更说明、影响平台（macOS/Windows 等）、测试结果（`flutter test`、`flutter analyze`），UI 变更附截图。
- 关联相关 issue，并注明配置或运行时影响（模型 provider、下载源、sidecar 行为等）。

## 安全与配置建议
- 禁止提交 API Key、令牌或私有服务地址。
- 本地敏感信息仅保存在运行时设置中；提交前确认 `.gitignore` 已覆盖本地产物与生成文件。
