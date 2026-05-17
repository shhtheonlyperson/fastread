import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

struct ClipboardPasteButton: View {
    let isLoading: Bool
    let action: (String) -> Void

    var body: some View {
        ZStack {
            card
                .accessibilityHidden(true)

            SystemPasteControl(isEnabled: !isLoading, action: action)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 92)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel(isLoading ? "Fetching clipboard content" : "Paste from clipboard")
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.72 : 1)
    }

    private var card: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(JRColor.terracotta.opacity(0.11))
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "doc.on.clipboard")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(JRColor.terracotta)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(isLoading ? "Fetching" : "Paste from clipboard")
                    .font(JRFont.serif(22, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(JRColor.ink)
                Text(isLoading ? "Preparing readable text" : "URL or text")
                    .font(JRFont.mono(11, weight: .medium))
                    .tracking(0.66)
                    .foregroundStyle(JRColor.inkQuiet)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(JRColor.inkQuiet)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(JRColor.paperStrong)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .borderBeam(
            border: JRColor.terracotta,
            beam: [JRColor.terracotta, JRColor.accentAmber],
            beamBlur: 12,
            cornerRadius: 6,
            isEnabled: !isLoading
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#if canImport(UIKit)
private struct SystemPasteControl: UIViewRepresentable {
    let isEnabled: Bool
    let action: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .clear
        configuration.cornerRadius = 6

        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator.target
        control.isEnabled = isEnabled
        control.alpha = 0.011
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .vertical)
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.target.action = action
        control.target = context.coordinator.target
        control.isEnabled = isEnabled
    }

    @MainActor
    final class Coordinator {
        let target: PasteTarget

        init(action: @escaping (String) -> Void) {
            target = PasteTarget(action: action)
        }
    }

    @MainActor
    final class PasteTarget: UIResponder {
        var action: (String) -> Void

        init(action: @escaping (String) -> Void) {
            self.action = action
            super.init()
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: Self.acceptedTypeIdentifiers)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func canPasteItemProviders(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { provider in
                Self.acceptedTypeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
            }
        }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let (provider, typeIdentifier) = firstAcceptedProvider(in: itemProviders) else {
                action("")
                return
            }

            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                let value: String
                if let string = item as? String {
                    value = string
                } else if let url = item as? URL {
                    if typeIdentifier == UTType.url.identifier {
                        value = url.absoluteString
                    } else {
                        value = (try? String(contentsOf: url, encoding: .utf8)) ?? url.absoluteString
                    }
                } else if let data = item as? Data {
                    value = String(data: data, encoding: .utf8) ?? ""
                } else if let nsString = item as? NSString {
                    value = nsString as String
                } else {
                    value = ""
                }

                DispatchQueue.main.async {
                    self.action(value)
                }
            }
        }

        private static let acceptedTypeIdentifiers = [
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.url.identifier
        ]

        private func firstAcceptedProvider(in providers: [NSItemProvider]) -> (NSItemProvider, String)? {
            for provider in providers {
                for typeIdentifier in Self.acceptedTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    return (provider, typeIdentifier)
                }
            }
            return nil
        }
    }
}
#else
private struct SystemPasteControl: View {
    let isEnabled: Bool
    let action: (String) -> Void

    var body: some View {
        Button {
            action("")
        } label: {
            Color.clear
        }
        .disabled(!isEnabled)
    }
}
#endif
