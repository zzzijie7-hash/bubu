# Bubu

步步是一款把“种草”和“打卡”沉淀成个人地图记忆的 App。

## 新成员 3 分钟上手

### 1. 克隆项目

```bash
git clone git@github.com:zzzijie7-hash/bubu.git
cd bubu
```

### 2. 安装协作保护

```bash
sh scripts/install-git-hooks.sh
```

装完以后，如果你手滑直接从 `main` push，终端会先拦你一下。

### 3. 不要直接在 `main` 上写，先开自己的分支

```bash
git checkout -b feature/your-work
git push -u origin feature/your-work
```

例子：

```bash
git checkout -b feature/home
git checkout -b feature/profile
```

## 我到底怎么开始写

如果你今天要开始做一个新功能，照着下面走就行：

```bash
git checkout main
git pull origin main
git checkout -b feature/your-work
```

然后正常写代码。

写完一个小阶段后：

```bash
git add .
git commit -m "feat: describe your change"
git push -u origin feature/your-work
```

## 如果我已经在 `main` 上改了怎么办

如果你只是改了，但还没有提交，直接执行：

```bash
git checkout -b feature/temp-work
```

当前改动会一起被带到新分支，不会丢。

## 每天开始前做什么

```bash
git checkout main
git pull origin main
git checkout feature/your-work
git merge main
```

## 合并回主干怎么做

推荐走 GitHub Pull Request：

1. 把你的分支 push 上去
2. 在 GitHub 发 PR
3. 让另一位成员 review
4. 通过后再合并到 `main`

## 项目文档

- 协作细则：[COLLABORATION.md](./COLLABORATION.md)
- 设计方向：[DESIGN.md](./DESIGN.md)
- 阶段记录：[progress.md](./progress.md)
- 视觉优化清单：[visual-todo.md](./visual-todo.md)
