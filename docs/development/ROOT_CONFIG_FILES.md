# 根目录配置文件说明

本文档说明根目录各配置文件的作用和用途。

## 核心配置文件（不可移动）

### build-profile.json5
- **作用**：HarmonyOS 项目构建配置文件
- **内容**：定义应用签名配置、产品配置、目标 SDK 版本、编译器选项、构建模式等
- **重要性**：DevEco Studio 和 Hvigor 构建系统必需的配置文件
- **位置要求**：必须位于项目根目录

### oh-package.json5
- **作用**：HarmonyOS 项目依赖管理文件（类似 npm 的 package.json）
- **内容**：定义项目依赖（dependencies）和开发依赖（devDependencies）
- **重要性**：ohpm 包管理器必需的配置文件
- **位置要求**：必须位于项目根目录

### oh-package-lock.json5
- **作用**：锁定依赖版本的文件（类似 npm 的 package-lock.json）
- **内容**：记录依赖树的精确版本信息
- **重要性**：确保依赖版本一致性
- **位置要求**：必须位于项目根目录

### code-linter.json5
- **作用**：ArkTS 代码检查配置文件
- **内容**：定义代码检查规则、要检查的文件和忽略的文件
- **重要性**：DevEco Studio 代码质量检查工具配置
- **位置要求**：必须位于项目根目录

## 其他配置文件

### hvigorfile.ts
- **作用**：Hvigor 构建工具配置文件
- **内容**：定义构建任务和插件
- **位置要求**：必须位于项目根目录

### local.properties
- **作用**：本地环境配置文件（自动生成）
- **内容**：包含本地开发环境的特定配置
- **注意**：此文件不应提交到版本控制系统

## 配置文件组织建议

根目录的这些配置文件是 HarmonyOS 项目的标准结构，**不建议移动到子文件夹**。这些文件的位置是 DevEco Studio、ohpm、Hvigor 等工具链所要求的。

如果希望更好地组织项目，可以考虑：
1. 保持这些核心配置文件在根目录
2. 将项目文档整理到 `docs/` 文件夹（已完成）
3. 将构建脚本整理到 `scripts/` 文件夹（已完成）
4. 将证据文件整理到 `docs/evidence/` 文件夹（已完成）

## 版本控制建议

应提交到 Git：
- ✅ build-profile.json5
- ✅ oh-package.json5
- ✅ oh-package-lock.json5
- ✅ code-linter.json5
- ✅ hvigorfile.ts

不应提交到 Git：
- ❌ local.properties（包含本地路径信息）
- ❌ .hvigor/（构建缓存）
- ❌ oh_modules/（依赖包，类似 node_modules）
- ❌ entry/build/（构建输出）
