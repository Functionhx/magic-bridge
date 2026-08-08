import MagicBridgeCore
import SwiftUI

struct BridgeView: View {
    @EnvironmentObject private var model: BridgeViewModel

    var body: some View {
        NavigationSplitView {
            List {
                Label("连接", systemImage: "link")
                Label("迁移", systemImage: "checklist")
                    .badge(model.isBusy ? "进行中" : "")
            }
            .navigationTitle("Magic Bridge")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    migrationCard
                    websiteCard
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(32)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task {
            await model.restoreWebsiteSessionIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本机与个人网站之间的桥")
                .font(.largeTitle.weight(.semibold))
            Text("迁移只在本机进行；公开与同步始终是独立动作。")
                .foregroundStyle(.secondary)
        }
    }

    private var migrationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Apple 备忘录清单保真", systemImage: "checkmark.circle")
                    .font(.title3.weight(.semibold))
                Text("读取 Apple Notes 的一致只读快照，恢复已勾选与未勾选状态，然后让 Magic Notes 更新原有副本。")
                    .foregroundStyle(.secondary)

                migrationStatus

                Button {
                    model.repairAppleNotesChecklists()
                } label: {
                    Label("扫描并重新导入", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private var migrationStatus: some View {
        switch model.migrationState {
        case .idle:
            Text("尚未扫描。")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .scanning:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("正在建立本机快照并解析原生清单…")
            }
        case let .opening(summary):
            summaryView(summary, prefix: "解析完成，正在交给 Magic Notes：")
        case let .complete(summary):
            summaryView(summary, prefix: "已交给 Magic Notes：")
                .foregroundStyle(.green)
        case let .needsSourceSelection(message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
                Button("选择 Apple Notes 文件夹…") {
                    model.chooseAppleNotesSource()
                }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func summaryView(
        _ summary: AppleNotesScanSummary,
        prefix: String
    ) -> some View {
        Text("\(prefix)\(summary.checklistNotes) 篇笔记，\(summary.checklistItems) 个清单项。")
            .font(.callout.weight(.medium))
    }

    private var websiteCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("个人网站", systemImage: "globe.asia.australia")
                    .font(.title3.weight(.semibold))
                Text("通过系统浏览器完成 GitHub OAuth。App 只在钥匙串保存服务器密封的会话，不保存 GitHub Token，也不接触私密库密钥。")
                    .foregroundStyle(.secondary)

                websiteStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private var websiteStatus: some View {
        switch model.websiteState {
        case .disconnected:
            Button {
                model.connectWebsite()
            } label: {
                Label("连接网站", systemImage: "person.badge.key")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .restoring:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查钥匙串会话…")
            }
        case .connecting:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("请在系统浏览器完成 GitHub 验证。")
                Button("取消") {
                    model.disconnectWebsite()
                }
            }
        case let .connected(identity):
            HStack(spacing: 12) {
                Label("已安全连接 @\(identity.login)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("断开") {
                    model.disconnectWebsite()
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("重新连接") {
                    model.connectWebsite()
                }
            }
        }
    }
}
