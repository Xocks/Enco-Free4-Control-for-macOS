import SwiftUI
import OppoPodsCore

struct CustomEqualizerEditorView: View {
    @ObservedObject var session: EarbudsSession
    @Environment(\.dismiss) private var dismiss

    @State private var presetID = 0
    @State private var presetName = "自定义"
    @State private var frequencies: [Int] = []
    @State private var gains: [Int] = []
    @State private var minimumGain = -6
    @State private var maximumGain = 6
    @State private var pendingSavedName: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自定义均衡器")
                        .font(.title2.weight(.semibold))
                    Text("调整会在点击“保存”后写入耳机")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            Form {
                Picker("预设", selection: $presetID) {
                    if canCreatePreset {
                        Text("新建自定义均衡器").tag(0)
                    }
                    ForEach(session.customEQPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .onChange(of: presetID) { _, newID in
                    loadPreset(id: newID)

                }

                TextField("名称", text: $presetName)
                    .onChange(of: presetName) { _, newValue in
                        if newValue.count > 32 { presetName = String(newValue.prefix(32)) }
                    }

                Section("频段") {
                    ForEach(frequencies.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text(frequencyLabel(frequencies[index]))
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                            Slider(
                                value: Binding(
                                    get: { Double(gains[index]) },
                                    set: { gains[index] = Int($0.rounded()) }
                                ),
                                in: Double(minimumGain)...Double(maximumGain),
                                step: 1
                            )
                            Text(gainLabel(gains[index]))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            OperationResultView().environmentObject(session).padding(.horizontal, 20)
            Divider()

            HStack {
                Button("全部归零") { gains = gains.map { _ in 0.clamped(to: minimumGain...maximumGain) } }
                if presetID > 0 {
                    Button("删除…", role: .destructive) { showingDeleteConfirmation = true }
                }
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canWrite || presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .disabled(!session.canWrite)
        }
        .frame(width: 560, height: 610)
        .onAppear {
            session.refreshCustomEQ()
            let initialID = session.customEQPresets.first(where: { $0.id == session.selectedEQ })?.id
                ?? session.customEQPresets.first?.id
                ?? 0
            presetID = initialID
            loadPreset(id: initialID)
        }
        .onChange(of: session.deviceEQPresets) { oldPresets, _ in
            if let pendingSavedName,
               let saved = session.customEQPresets.first(where: { $0.name == pendingSavedName }) {
                self.pendingSavedName = nil
                presetID = saved.id
                loadPreset(id: saved.id)

            } else if presetID > 0, !session.customEQPresets.contains(where: { $0.id == presetID }) {
                presetID = 0; loadPreset(id: 0)
            } else if presetID > 0, let old = oldPresets.first(where: { $0.id == presetID }),
                      old.name == presetName, old.frequencies == frequencies, old.gains == gains {
                // A phone-side refresh may update the source; preserve an unsaved local draft.
                loadPreset(id: presetID)
            }
        }
        .alert("删除自定义均衡器？", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteCurrentPreset() }
        } message: {
            Text("“\(presetName)”将从耳机中删除，此操作无法撤销。")
        }
    }

    private var canCreatePreset: Bool {
        session.capabilities.customEQMaximumPresets <= 0
            || session.customEQPresets.count < session.capabilities.customEQMaximumPresets
            || presetID == 0
    }

    private func loadPreset(id: Int) {
        if let preset = session.customEQPresets.first(where: { $0.id == id }) {
            presetName = preset.name
            minimumGain = min(preset.minimumGain, preset.maximumGain)
            maximumGain = max(preset.minimumGain, preset.maximumGain)
            frequencies = preset.frequencies.isEmpty ? session.customEQFrequencies : preset.frequencies
            gains = frequencies.indices.map { index in
                let gain = preset.gains.indices.contains(index) ? preset.gains[index] : 0
                return gain.clamped(to: minimumGain...maximumGain)
            }
        } else {
            presetName = "自定义"
            minimumGain = -6
            maximumGain = 6
            frequencies = session.customEQFrequencies
            gains = frequencies.map { _ in 0 }
        }
    }

    private func save() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if presetID == 0 { pendingSavedName = name }
        session.saveCustomEQ(
            id: presetID,
            name: name,
            frequencies: frequencies,
            gains: gains,
            minimumGain: minimumGain,
            maximumGain: maximumGain
        )

    }

    private func deleteCurrentPreset() {
        guard let preset = session.customEQPresets.first(where: { $0.id == presetID }) else { return }
        session.deleteCustomEQ(preset)

    }

    private func frequencyLabel(_ frequency: Int) -> String {
        frequency >= 1_000
            ? "\(frequency / 1_000) kHz"
            : "\(frequency) Hz"
    }

    private func gainLabel(_ gain: Int) -> String {
        gain > 0 ? "+\(gain) dB" : "\(gain) dB"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
