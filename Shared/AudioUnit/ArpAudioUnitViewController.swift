//
//  ArpAudioUnitViewController.swift
//  The extension's principal class: an AUViewController that both manufactures
//  the audio unit (AUAudioUnitFactory) and hosts the SwiftUI parameter UI.
//
//  AUViewController is a UIViewController on iOS and an NSViewController on
//  macOS; CoreAudioKit unifies the type so this single file serves both.
//

import CoreAudioKit
import SwiftUI

public class ArpAudioUnitViewController: AUViewController, AUAudioUnitFactory {

    private var audioUnit: ArpAudioUnit?

    // MARK: AUAudioUnitFactory

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try ArpAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        // The view may load before or after the AU is created; wire up whichever
        // happens second.
        DispatchQueue.main.async { [weak self] in self?.installUIIfReady() }
        return unit
    }

    // MARK: View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        installUIIfReady()
    }

    private var didInstallUI = false

    private func installUIIfReady() {
        guard isViewLoaded, !didInstallUI, let unit = audioUnit else { return }
        let tree = unit.parameterTree
        didInstallUI = true

        let root = ArpView(model: ArpParameterModel(parameterTree: tree))

#if os(iOS)
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
#elseif os(macOS)
        let host = NSHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
#endif
    }
}
