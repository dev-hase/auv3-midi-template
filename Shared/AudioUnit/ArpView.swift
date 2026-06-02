//
//  ArpView.swift
//  Cross-platform SwiftUI parameter editor for the Arp AUv3.
//
//  Binds directly to the AUParameterTree so edits flow to the audio unit and
//  host automation flows back into the UI. No UIKit/AppKit specifics here, so
//  the same view renders on iOS and macOS.
//

import SwiftUI
import AudioToolbox

/// Observable bridge between the AUParameterTree and SwiftUI.
final class ArpParameterModel: ObservableObject {
    let tree: AUParameterTree

    @Published var rate: Float
    @Published var mode: Float
    @Published var octaves: Float
    @Published var gate: Float
    @Published var hold: Bool

    private var token: AUParameterObserverToken?

    init(parameterTree: AUParameterTree) {
        self.tree = parameterTree
        rate    = parameterTree.parameter(withAddress: Self.addr(ArpParamRate))?.value    ?? 2
        mode    = parameterTree.parameter(withAddress: Self.addr(ArpParamMode))?.value    ?? 0
        octaves = parameterTree.parameter(withAddress: Self.addr(ArpParamOctaves))?.value ?? 1
        gate    = parameterTree.parameter(withAddress: Self.addr(ArpParamGate))?.value    ?? 0.5
        hold    = (parameterTree.parameter(withAddress: Self.addr(ArpParamHold))?.value ?? 0) > 0.5

        // Reflect host-side / automation changes back into the UI.
        token = parameterTree.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if address == Self.addr(ArpParamRate)         { self.rate = value }
                else if address == Self.addr(ArpParamMode)    { self.mode = value }
                else if address == Self.addr(ArpParamOctaves) { self.octaves = value }
                else if address == Self.addr(ArpParamGate)    { self.gate = value }
                else if address == Self.addr(ArpParamHold)    { self.hold = value > 0.5 }
            }
        })
    }

    deinit { if let token = token { tree.removeParameterObserver(token) } }

    static func addr(_ address: ArpParameterAddress) -> AUParameterAddress {
        AUParameterAddress(address.rawValue)
    }

    func set(_ address: ArpParameterAddress, _ value: Float) {
        tree.parameter(withAddress: Self.addr(address))?.value = value
    }
}

struct ArpView: View {
    @StateObject var model: ArpParameterModel

    private let rateLabels = ["1/4", "1/8", "1/16", "1/8T", "1/16T"]
    private let modeLabels = ["Up", "Down", "Up/Down", "Random", "As Played"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AUv3 MIDI Arpeggiator")
                .font(.headline)

            picker("Rate", selection: $model.rate, labels: rateLabels) {
                model.set(ArpParamRate, $0)
            }
            picker("Mode", selection: $model.mode, labels: modeLabels) {
                model.set(ArpParamMode, $0)
            }
            stepper("Octaves", value: $model.octaves, range: 1...4) {
                model.set(ArpParamOctaves, $0)
            }

            VStack(alignment: .leading) {
                Text(String(format: "Gate: %.0f%%", model.gate * 100))
                Slider(value: Binding(get: { model.gate },
                                      set: { model.gate = $0; model.set(ArpParamGate, $0) }),
                       in: 0.05...1.0)
            }

            Toggle("Hold", isOn: Binding(get: { model.hold },
                                         set: { model.hold = $0; model.set(ArpParamHold, $0 ? 1 : 0) }))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 360)
    }

    // MARK: helpers

    private func picker(_ title: String, selection: Binding<Float>,
                        labels: [String], onChange: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Picker(title, selection: Binding(get: { Int(selection.wrappedValue.rounded()) },
                                             set: { selection.wrappedValue = Float($0); onChange(Float($0)) })) {
                ForEach(labels.indices, id: \.self) { i in Text(labels[i]).tag(i) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func stepper(_ title: String, value: Binding<Float>,
                         range: ClosedRange<Float>, onChange: @escaping (Float) -> Void) -> some View {
        Stepper(value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = Float($0); onChange(Float($0)) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
            Text("\(title): \(Int(value.wrappedValue.rounded()))")
        }
    }
}
