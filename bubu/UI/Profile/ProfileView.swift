import SwiftUI

// MARK: - 我的页面

struct ProfileView: View {
    @EnvironmentObject var container: AppContainer
    @State private var stats = UserStats.empty

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    StatsDashboard(stats: stats)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ProfileMenuRow(icon: "clock.arrow.circlepath", title: "打卡历史", color: BubuTheme.Primary.green)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        ProfileMenuRow(icon: "chart.bar.fill", title: "数据看板", color: BubuTheme.Text.secondary)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        ProfileMenuRow(icon: "square.and.arrow.down.fill", title: "导入记录", color: .blue)
                    }
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ProfileMenuRow(icon: "paintpalette.fill", title: "地图样式", color: .orange)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        ProfileMenuRow(icon: "icloud.fill", title: "同步状态", color: .cyan)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        ProfileMenuRow(icon: "gearshape.fill", title: "设置", color: .gray)
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                        ProfileMenuRow(icon: "info.circle.fill", title: "关于步步", color: BubuTheme.Text.secondary)
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
            .onAppear { reloadStats() }
        }
    }

    private func reloadStats() {
        let repo = container.placeRepository
        stats = UserStats(
            placesVisited: repo.countVisited(),
            placesWanted: repo.countWanted(),
            citiesVisited: 0,
            collections: repo.countFolders(),
            explorationPercent: min(repo.countVisited() * 5, 100)
        )
    }
}

// MARK: - 统计看板

struct StatsDashboard: View {
    let stats: UserStats

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                StatItem(value: "\(stats.placesVisited)", label: "已打卡", icon: "checkmark.circle.fill", color: BubuTheme.Primary.green)
                Divider().frame(height: 40).background(BubuTheme.Text.tertiary)
                StatItem(value: "\(stats.placesWanted)", label: "想去", icon: "bookmark.fill", color: BubuTheme.Text.secondary)
                Divider().frame(height: 40).background(BubuTheme.Text.tertiary)
                StatItem(value: "\(stats.citiesVisited)", label: "城市", icon: "building.2.fill", color: .orange)
                Divider().frame(height: 40).background(BubuTheme.Text.tertiary)
                StatItem(value: "\(stats.collections)", label: "收藏夹", icon: "folder.fill", color: .blue)
            }

            // 进度条：探索度
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("城市探索度")
                        .font(BubuFont.caption)
                        .foregroundStyle(BubuTheme.Text.secondary)
                    Spacer()
                    Text("\(stats.explorationPercent)%")
                        .font(BubuFont.titleSM)
                        .foregroundStyle(BubuTheme.Primary.green)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BubuTheme.Surface.surface2)
                            .frame(height: 6)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [BubuTheme.Primary.green, BubuTheme.Primary.active],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(stats.explorationPercent) / 100, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(20)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Text.ink)
            Text(label)
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct UserStats {
    var placesVisited: Int
    var placesWanted: Int
    var citiesVisited: Int
    var collections: Int
    var explorationPercent: Int

    static let empty = UserStats(
        placesVisited: 0, placesWanted: 0, citiesVisited: 0, collections: 0, explorationPercent: 0)
}

struct ProfileMenuRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        Button {
            // TODO: 导航
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title)
                    .font(BubuFont.body)
                    .foregroundStyle(BubuTheme.Text.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(BubuTheme.Text.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}