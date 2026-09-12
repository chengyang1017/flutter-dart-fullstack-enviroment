# 代码编辑器增强指南

该文档描述了 Flutter Playground 代码编辑器的增强功能和改进计划。

## 📚 目录

- [当前功能](#当前功能)
- [快捷键](#快捷键)
- [代码片段](#代码片段)
- [自动补全](#自动补全)
- [代码诊断](#代码诊断)
- [主题和样式](#主题和样式)
- [未来改进](#未来改进)

---

## 当前功能

### ✓ 已实现
- 基础代码编辑
- 语法高亮 (Dart/Flutter)
- 代码折叠
- 基础自动补全
- 错误提示

### 🔄 进行中 / 计划中
- 高级自动补全 (使用 Dart Analysis Server)
- 代码诊断和快速修复
- 代码重构工具
- 调试支持

---

## 快捷键

### 代码编辑

| 快捷键 | Windows/Linux | macOS | 说明 |
|-------|---|---|---|
| 格式化代码 | `Ctrl+Shift+F` | `Cmd+Shift+F` | 格式化当前文件 |
| 撤销 | `Ctrl+Z` | `Cmd+Z` | 撤销上一步操作 |
| 重做 | `Ctrl+Y` | `Cmd+Shift+Z` | 重做上一步操作 |
| 注释行 | `Ctrl+/` | `Cmd+/` | 注释或取消注释选中行 |
| 复制行 | `Ctrl+D` | `Cmd+D` | 复制当前行 |
| 删除行 | `Ctrl+Shift+K` | `Cmd+Shift+K` | 删除当前行 |
| 上移行 | `Alt+Up` | `Opt+Up` | 将当前行上移一行 |
| 下移行 | `Alt+Down` | `Opt+Down` | 将当前行下移一行 |

### 搜索和替换

| 快捷键 | Windows/Linux | macOS | 说明 |
|-------|---|---|---|
| 搜索 | `Ctrl+F` | `Cmd+F` | 打开搜索框 |
| 替换 | `Ctrl+H` | `Cmd+H` | 打开搜索替换 |
| 查找下一个 | `F3` | `Cmd+G` | 查找下一个匹配项 |
| 查找上一个 | `Shift+F3` | `Cmd+Shift+G` | 查找上一个匹配项 |

### 代码导航

| 快捷键 | Windows/Linux | macOS | 说明 |
|-------|---|---|---|
| 转到行 | `Ctrl+G` | `Cmd+G` | 快速跳转到指定行 |
| 转到定义 | `Ctrl+Click` | `Cmd+Click` | 跳转到符号定义 |
| 返回 | `Alt+Left` | `Cmd+Left` | 返回上一个位置 |
| 前进 | `Alt+Right` | `Cmd+Right` | 前进到下一个位置 |

### 自动补全和代码片段

| 快捷键 | 说明 |
|-------|------|
| `Ctrl+Space` | 触发代码补全 |
| `Tab` | 接受建议 / 移到下一个片段占位符 |
| `Shift+Tab` | 移到上一个片段占位符 |
| `Escape` | 取消补全/片段 |

---

## 代码片段

### 类定义

**快捷键**: 输入 `class` 然后按 `Tab`

```dart
class ClassName {
  // 类体
}
```

### StatelessWidget

**快捷键**: 输入 `widget` 然后按 `Tab`

```dart
class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
```

### StatefulWidget

**快捷键**: 输入 `stateful` 然后按 `Tab`

```dart
class MyWidget extends StatefulWidget {
  const MyWidget({super.key});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
```

### 异步函数

**快捷键**: 输入 `future` 然后按 `Tab`

```dart
Future<void> functionName() async {
  // 函数体
}
```

### Stream 函数

**快捷键**: 输入 `stream` 然后按 `Tab`

```dart
Stream<T> functionName() async* {
  // 函数体
}
```

### 单元测试

**快捷键**: 输入 `test` 然后按 `Tab`

```dart
test('test description', () {
  // 测试代码
});
```

---

## 自动补全

### 触发方式

自动补全在以下情况触发:
- 输入 `.` (访问成员)
- 输入 `>` (箭头符号)
- 输入 `(` (函数参数)
- 输入 `[` (列表/Map 访问)
- 输入 `{` (对象字面量)
- 按 `Ctrl+Space` (手动触发)

### 补全类型

| 类型 | 示例 | 说明 |
|-----|------|------|
| 关键字 | `if`, `for`, `while`, `try` | Dart 语言关键字 |
| 类 | `Container`, `Text`, `Column` | 常见 Flutter Widget |
| 函数 | `build()`, `setState()` | 类和库函数 |
| 变量 | 当前作用域变量 | 局部和全局变量 |
| 导入 | `flutter/material.dart` | 可用的包和库 |

### 常见 Flutter Widget 补全

- `Container` - 容器组件
- `Column` - 垂直布局
- `Row` - 水平布局
- `Text` - 文本显示
- `Button` - 按钮
- `TextField` - 文本输入
- `ListView` - 列表视图
- `GridView` - 网格视图
- `Stack` - 堆叠布局
- `Scaffold` - 应用框架

---

## 代码诊断

编辑器会自动检测以下问题:

### 错误级别 🔴

| 诊断 | 示例 | 解决方案 |
|-----|------|---------|
| 语法错误 | 缺少分号、括号不匹配 | 按照提示修复语法 |
| 类型错误 | 类型不匹配 | 转换类型或变更值 |
| 空引用 | 可能的 null 异常 | 使用 `?.` 或检查 null |

### 警告级别 ⚠️

| 诊断 | 示例 | 解决方案 |
|-----|------|---------|
| 未使用的变量 | `var unused = 42;` | 删除或使用该变量 |
| 已弃用的 API | 使用旧的 Flutter API | 更新到新 API |
| 潜在的 bug | 可能的逻辑错误 | 检查代码逻辑 |

### 信息级别 ℹ️

| 诊断 | 示例 | 解决方案 |
|-----|------|---------|
| 代码行过长 | 超过 120 字符 | 拆分为多行 |
| 缺少文档 | 公开函数无注释 | 添加 doc 注释 |
| 代码风格 | 不符合 Flutter 风格指南 | 调整代码风格 |

### 快速修复

某些诊断提供"快速修复"选项，可以一键应用:
- 导入缺失的包
- 重命名不一致的变量
- 替换已弃用的 API
- 添加类型注解

---

## 主题和样式

### 可用主题

| 主题 | 适用场景 |
|-----|---------|
| **Light** | 白天开发、高对比度需求 |
| **Dark** | 护眼模式、长时间开发 |
| **High Contrast** | 可达性、阅读困难 |
| **Solarized** | 舒适阅读、流行配色 |

### 语法高亮颜色

```
🟠 关键字 (if, for, class, etc)
🟢 字符串和注释
🔵 数字、函数、变量
🟣 类名
```

### 自定义主题

用户可以在设置中自定义颜色:

```json
{
  "editor.theme": "dark",
  "editor.syntax.keyword": "#FF7B00",
  "editor.syntax.string": "#00B33C",
  "editor.syntax.comment": "#808080"
}
```

---

## 未来改进

### 即将推出 (1-2 周)

- [ ] **高级自动补全** - 使用 Dart Analysis Server 的智能补全
- [ ] **代码重构** - 重命名、提取函数、内联变量等
- [ ] **实时代码检查** - 更准确的诊断和建议
- [ ] **代码折叠改进** - 自定义折叠区域

### 计划中 (1 个月)

- [ ] **调试支持** - 断点、查看变量、Step 执行
- [ ] **Git 集成** - 显示修改、diff、blame 信息
- [ ] **性能分析** - 代码性能指标和建议
- [ ] **协作编辑** - 多用户同时编辑支持

### 远期目标 (3+ 个月)

- [ ] **AI 辅助编码** - 代码生成、注释补全等
- [ ] **高级重构工具** - AST 级别的代码转换
- [ ] **集成测试框架** - 直接在编辑器中运行测试
- [ ] **性能优化建议** - 自动检测和建议优化

---

## 使用建议

### 提高效率的技巧

1. **熟悉快捷键** - 最常用的快捷键会大大提升编码速度
2. **使用代码片段** - 对于重复代码，使用片段很高效
3. **启用自动格式化** - 在保存时自动格式化代码
4. **定期检查诊断** - 不要忽视警告和信息级别的诊断
5. **利用自动补全** - 避免手动输入重复的类名和函数名

### 最佳实践

- 📝 为公开 API 编写文档注释
- 🎯 遵循 [Dart 代码风格指南](https://dart.dev/guides/language/effective-dart)
- 💾 定期保存文件 (Ctrl/Cmd+S)
- 🔍 使用搜索功能查找和替换重复代码
- 🧹 定期运行 `flutter analyze` 检查整个项目

---

## 反馈和建议

如果您有关于编辑器增强的建议或需要支持，请:

1. 查看 [PROJECT_STATUS.md](PROJECT_STATUS.md) 了解开发进度
2. 在 GitHub 上提交 Issue
3. 查看 [DEPLOYMENT.md](DEPLOYMENT.md) 的故障排除部分

---

**最后更新**: 2026-09-05
