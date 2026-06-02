import SwiftUI

// MARK: - "我的"页面：统计 + 收藏夹 + 设置

struct MyPageView: View {
    @EnvironmentObject var container: AppContainer
    @State private var stats = UserStats.empty
    @State private var folders: [CDFolder] = []
    @State private var showingAddFolder = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 统计看板
                    StatsDashboard(stats: stats)
                        .padding(.horizontal, 16)

                    // 收藏夹板块
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("我的收藏夹")
                                .font(BubuFont.titleLG)
                                .foregroundStyle(BubuTheme.Text.ink)
                            Spacer()
                            Button {
                                showingAddFolder = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.title3)
                                    .foregroundStyle(BubuTheme.Primary.green)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                        if folders.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bookmark.slash")
                                    .font(.system(size: 36))
                                    .foregroundStyle(BubuTheme.Text.tertiary)
                                Text("还没有收藏夹")
                                    .font(BubuFont.titleSM)
                                    .foregroundStyle(BubuTheme.Text.secondary)
                                Text("探索并收藏地点，开始点亮地图")
                                    .font(BubuFont.caption)
                                    .foregroundStyle(BubuTheme.Text.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .background(BubuTheme.Surface.surface1)
                            .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                            .padding(.horizontal, 16)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(folders, id: \.id) { folder in
                                    FolderRow(folder: folder)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }

                    // 功能菜单
                    VStack(spacing: 0) {
                        MenuRow(icon: "clock.arrow.circlepath", title: "打卡历史", color: BubuTheme.Primary.green)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        MenuRow(icon: "chart.bar.fill", title: "数据看板", color: BubuTheme.Primary.green)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        MenuRow(icon: "square.and.arrow.down.fill", title: "数据导入", color: .blue)
                    }
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                    .padding(.horizontal, 16)

                    // 设置
                    VStack(spacing: 0) {
                        MenuRow(icon: "paintpalette.fill", title: "地图样式", color: .gray)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        MenuRow(icon: "gearshape.fill", title: "设置", color: .gray)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        MenuRow(icon: "info.circle.fill", title: "关于步步 Bubu", color: .gray)
                    }
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .background(BubuTheme.Surface.space)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { reloadAll() }
            .sheet(isPresented: $showingAddFolder) {
                AddFolderSheet { reloadAll() }
            }
        }
    }

    private func reloadAll() {
        let repo = container.placeRepository
        stats = UserStats(
            placesVisited: repo.countVisited(),
            placesWanted: repo.countWanted(),
            citiesVisited: 0,
            collections: repo.countFolders(),
            explorationPercent: min(repo.countVisited() * 5, 100)
        )
        folders = repo.fetchFolders()
    }
}

// MARK: - 收藏夹行

struct FolderRow: View {
    @ObservedObject var folder: CDFolder

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: folder.icon ?? "folder.fill")
                .font(.title3)
                .foregroundStyle(BubuTheme.Primary.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(folder.name ?? "")
                        .font(BubuFont.titleSM)
                        .foregroundStyle(BubuTheme.Text.ink)
                    if folder.isDefault {
                        Text("默认")
                            .font(.system(size: 9))
                            .foregroundStyle(BubuTheme.Primary.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(BubuTheme.Primary.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text("\(folder.places?.count ?? 0) 个地点")
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(BubuTheme.Text.tertiary)
        }
        .padding(14)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
    }
}

// MARK: - 菜单行

struct MenuRow: View {
    let icon: String; let title: String; let color: Color
    var body: some View {
        Button {} label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 24)
                Text(title).font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(BubuTheme.Text.tertiary)
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

// MARK: - 新建文件夹 Sheet

struct AddFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var container: AppContainer
    @State private var name = ""
    @State private var selectedIcon = "folder.fill"
    var onCreated: () -> Void

    let icons = ["folder.fill", "heart.fill", "star.fill", "flag.fill", "bookmark.fill", "pin.fill"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("收藏夹名称", text: $name)
                    .font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink)
                    .padding(12).background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
                    .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                    ForEach(icons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(selectedIcon == icon ? .white : BubuTheme.Text.secondary)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: BubuRadius.md)
                                .fill(selectedIcon == icon ? BubuTheme.Primary.green : BubuTheme.Surface.surface1))
                            .onTapGesture { selectedIcon = icon }
                    }
                }
                .padding(.horizontal, 16)

                Button("创建") {
                    _ = container.placeRepository.createFolder(name: name, icon: selectedIcon)
                    onCreated()
                    dismiss()
                }
                .buttonStyle(BubuButtonModifier(variant: .primary))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 16)
            }
            .padding(.top, 20).background(BubuTheme.Surface.space)
            .navigationTitle("新建收藏夹").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}