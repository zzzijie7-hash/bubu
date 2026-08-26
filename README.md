# Bubu

步步是一款把“种草”和“打卡”沉淀成个人地图记忆的 App。

## 当前项目分工

- `xingshou`：负责首页 / 地图主流程 / 添加地点相关体验
- `mali`：负责个人页 / 城市印记 / 城市画廊相关体验

详细协作规则见：

- [COLLABORATION.md](./COLLABORATION.md)
- [TEAM_SPLIT.md](./TEAM_SPLIT.md)

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

### 3. 切到自己的工作分支

```bash
git checkout xingshou
```

或：

```bash
git checkout mali
```

## 每天开始前

```bash
git checkout main
git pull origin main
git checkout your-branch
git merge main
```

## 提交改动

```bash
git add .
git commit -m "feat: describe your change"
git push
```
