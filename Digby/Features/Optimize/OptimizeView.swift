import SwiftUI

struct OptimizeView: View {
    @Bindable var model: OptimizeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header.rise(0)
                ProgressBar(fraction: model.fraction, height: 4, shimmer: false)
                Panel {
                    VStack(spacing: 0) {
                        ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                            TaskRow(task: task).rise(0.1 + Double(min(index, 14)) * 0.04, duration: 0.45)
                        }
                    }
                }
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .pageEnter()
    }

    private var header: some View {
        SpotCard(glowOpacity: 0.1, glowRadius: 420, padding: 0, lift: false) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(Fonts.ui(18, .semibold))
                    Text(subline).font(Fonts.ui(13.5)).foregroundStyle(DS.textMuted)
                }
                .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                Text(model.phase == .idle ? "" : "\(Int((model.fraction * 100).rounded()))%")
                    .font(Fonts.mono(22))
                    .foregroundStyle(DS.accent)
                    .frame(minWidth: 56, alignment: .trailing)
                    .contentTransition(.numericText())
                Button(model.phase == .running ? "Running…" : model.phase == .done ? "Run again" : "Run tasks", action: model.run)
                    .buttonStyle(PillButtonStyle(kind: .primary, horizontal: 24, enabled: model.phase != .running))
                    .disabled(model.phase == .running)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    private var headline: String {
        switch model.phase {
        case .running: "Running \(min(model.doneCount + 1, model.tasks.count)) of \(model.tasks.count)…"
        case .done: "\(model.doneCount) tasks finished"
        case .idle: "\(model.tasks.count) of \(model.tasks.count) tasks selected"
        }
    }

    private var subline: String {
        model.phase == .done
            ? "Caches rebuilt and services refreshed. Some apps may relaunch."
            : "Mole skips tasks that are not needed. Tasks marked admin ask for your password once."
    }
}

private struct TaskRow: View {
    let task: OptimizeModel.OptTask

    var body: some View {
        let running = task.status == .running
        HStack(spacing: 16) {
            ToggleSwitch(isOn: true, action: {}, enabled: false)
                .help("Mole runs every task in one pass. Exclude tasks with mo optimize --whitelist.")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(task.name).font(Fonts.ui(14.5, .semibold))
                    if task.admin { Tag(text: "admin") }
                }
                Text(task.detail).font(Fonts.ui(13)).foregroundStyle(DS.textMuted).lineLimit(2)
                Text(task.result.isEmpty ? task.handler : task.result)
                    .font(Fonts.mono(11.5))
                    .foregroundStyle(running ? DS.accentLight : task.status == .done ? DS.textSecondary : DS.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeOut(duration: 0.3), value: task.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                switch task.status {
                case .running: Spinner()
                case .done:
                    HStack(spacing: 6) {
                        Text("✓").font(.system(size: 10))
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(DS.success.opacity(0.16)))
                        Text(String(format: "%.1fs", task.seconds))
                    }
                    .foregroundStyle(DS.success)
                    .pop(duration: 0.45)
                case .queued: Text("queued").foregroundStyle(DS.textFaint).fadeIn()
                case .idle: EmptyView()
                }
            }
            .font(Fonts.mono(12))
            .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            ZStack(alignment: .leading) {
                (running ? Color(hex: 0x141D2B) : .clear).animation(.easeOut(duration: 0.35), value: running)
                if running {
                    Shimmer(period: 1.1, color: DS.accent.opacity(0.13))
                    Rectangle().fill(DS.accent).frame(width: 2).shadow(color: DS.accent, radius: 5)
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DS.borderSubtle2).frame(height: 1) }
    }
}
