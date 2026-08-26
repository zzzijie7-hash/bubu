# Bubu Team Split

最后更新：2026-08-26

## 当前分工

### xingshou

- 分支：`xingshou`
- 负责范围：
  - 首页
  - 地图主舞台
  - 添加地点主流程
  - 顶部区域条、底导、地图交互

### mali

- 分支：`mali`
- 负责范围：
  - 个人页
  - 城市印记
  - 城市画廊
  - 个人页视觉表达与内容组织

## 共享区域

下面这些地方改动前最好先同步一下：

- `Bubu.xcodeproj/project.pbxproj`
- `project.yml`
- `bubu/UI/Theme`
- 数据模型与持久化
- 地图服务配置

## 开工方式

### xingshou

```bash
git checkout xingshou
git pull origin xingshou
git merge main
```

### mali

```bash
git checkout mali
git pull origin mali
git merge main
```

## 建议

- 大改前先在各自 log 里写一句“准备改什么”
- 每天收工前 push 一次
- 如果需要跨区改动，先在群里说一声
