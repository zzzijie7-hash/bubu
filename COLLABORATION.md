# Bubu Collaboration Guide

适用于当前 `bubu` 项目的双人或小团队协作。

## 协作原则

- `main` 只放可运行、相对稳定的版本。
- 日常开发不要直接在 `main` 上进行。
- 每个人都在自己的功能分支开发。
- 做完一个明确的小功能，再合并回 `main`。
- 开工前先同步，收工后再提交。

一句话版本：

`main` 是展台，不是工位。

## 推荐分工

例如：

- 首页 / 地图：`feature/home`
- 我的页面 / 城市印记：`feature/profile`
- 导入链路：`feature/import`
- 视觉系统：`feature/design-system`

如果一个人负责多个方向，也不要把所有事都堆到一个分支里。

## 第一次加入项目

### 1. 克隆项目

```bash
git clone git@github.com:zzzijie7-hash/bubu.git
cd bubu
```

### 2. 确认当前分支

```bash
git branch
```

如果你看到自己在 `main`，不要直接开始写代码。

### 3. 新建自己的分支

```bash
git checkout -b feature/your-work
```

例如：

```bash
git checkout -b feature/profile
git checkout -b feature/home
```

### 4. 推送自己的分支到远程

```bash
git push -u origin feature/your-work
```

这样以后就可以直接 `git push`。

## 日常开发流程

### 开工前

先确认自己不在 `main`：

```bash
git branch
```

如果当前是 `main`：

```bash
git checkout feature/your-work
```

然后同步最新主干：

```bash
git checkout main
git pull origin main
git checkout feature/your-work
git merge main
```

如果你更习惯 rebase，也可以用：

```bash
git checkout feature/your-work
git fetch origin
git rebase origin/main
```

当前项目推荐新手优先用 `merge`，更直观，也更不容易慌。

### 开发中

边改边看状态：

```bash
git status
```

做完一个小阶段就提交一次，不要攒到最后。

```bash
git add .
git commit -m "feat: refine profile page layout"
```

### 上传到 GitHub

```bash
git push
```

## 合并回 main 的推荐方式

### 方式 A：GitHub 上发 Pull Request

这是最推荐的方式，尤其是两个人协作时。

流程：

1. 把自己的分支推上去
2. 在 GitHub 创建 Pull Request
3. 让另一位成员看一下
4. 确认可运行后再合并到 `main`

优点：

- 更不容易误操作
- 能看到改了什么
- 出问题时好回溯

### 方式 B：本地合并

如果你们当下追求快，也可以：

```bash
git checkout main
git pull origin main
git merge feature/your-work
git push origin main
```

但前提是：

- 这次改动已经自测过
- 另一位成员当前没有同时在改同一块

## 怎么避免直接改 main

这是最重要的一段。

### 最低要求

每次开工前先执行：

```bash
git branch
```

如果结果里带 `* main`，立刻切走：

```bash
git checkout -b feature/temp-work
```

如果你已经在 `main` 上改了，但还没提交，不要慌：

```bash
git checkout -b feature/temp-work
```

这会把你当前的未提交改动一起带到新分支，不会丢。

### 如果你已经在 main 上提交了

先把那次提交留住，再把 `main` 拉回远程最新状态：

```bash
git branch feature/saved-main-work
git checkout main
git reset --hard origin/main
git checkout feature/saved-main-work
```

注意：

- `git reset --hard` 会丢掉 `main` 上未保存的本地改动
- 只有在“改动已经被分支保存”时才能这么做

如果不确定，先不要执行，先找队友确认。

### 更稳的团队做法

在 GitHub 仓库开启分支保护，限制直接 push 到 `main`。

仓库路径：

- `Settings`
- `Rulesets` 或 `Branches`
- 给 `main` 加保护规则

建议至少打开：

- Restrict direct pushes
- Require pull request before merging

这样就算有人手快，也不容易直接把 `main` 搞乱。

## 怎么拿到别人的最新更新

### 只更新 main

```bash
git checkout main
git pull origin main
```

### 把 main 的最新内容带到自己的分支

```bash
git checkout feature/your-work
git merge main
```

## 冲突怎么处理

最常见的冲突文件：

- `Bubu.xcodeproj/project.pbxproj`
- `project.yml`
- 同一个 Swift 文件

### 处理原则

- 先看是不是两个人改了同一块
- 先保住能编译
- 不要为了消冲突把对方代码删没了

### 当前项目特别注意

`Xcode` 工程文件最容易冲突。

建议：

- 尽量少同时修改工程结构
- 加文件、改 target、改配置时先在群里说一声
- 如果能通过 `project.yml` 统一维护，就尽量不要两个人同时手点 `xcodeproj`

## 提交信息建议

统一用简单英文前缀：

- `feat:` 新功能
- `fix:` 修复问题
- `refactor:` 重构
- `style:` 视觉或样式调整
- `chore:` 杂项维护

例如：

```bash
git commit -m "feat: add city gallery entry view"
git commit -m "style: refine profile glass navigation"
git commit -m "fix: restore map search anchor behavior"
```

## 合并前检查清单

合并到 `main` 前，至少确认：

- 工程能编译
- 主要页面能打开
- 没有把本地测试数据、临时截图、无关文件带进去
- 没有误删别人代码
- 当前功能已经达到“可以给队友看”的程度

## 当前项目推荐协作节奏

### 每天开始前

```bash
git checkout main
git pull origin main
```

### 然后切回自己的分支同步

```bash
git checkout feature/your-work
git merge main
```

### 每天结束前

```bash
git add .
git commit -m "feat: today's progress summary"
git push
```

## 一条简单约定

如果你准备改这些东西，先告诉队友：

- `Bubu.xcodeproj/project.pbxproj`
- `project.yml`
- 设计系统主题文件
- 数据模型
- 持久化 / CloudKit

因为这些地方一旦同时改，很容易互相打架。

## 推荐给新成员的最短上手版本

只记住下面这 6 句就能安全协作：

1. 不要直接在 `main` 上写代码。
2. 先 `git checkout -b feature/xxx`。
3. 开工前先同步 `main`。
4. 做完就 `commit` + `push`。
5. 合并前先确认工程能跑。
6. 改工程配置和数据结构前先说一声。
