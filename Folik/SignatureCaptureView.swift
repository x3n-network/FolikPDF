import SwiftUI

enum SignatureKind: String, CaseIterable, Codable, Identifiable {
    case signature
    case initials

    var id: Self { self }
    var title: String { self == .signature ? "Signature" : "Initials" }
    var icon: String { self == .signature ? "signature" : "character.cursor.ibeam" }
    var defaultSize: CGSize {
        self == .signature ? CGSize(width: 220, height: 76) : CGSize(width: 100, height: 58)
    }
}

struct SignaturePoint: Codable, Equatable {
    let x: Double
    let y: Double
}

struct SignatureStroke: Codable, Equatable {
    var points: [SignaturePoint]
}

struct SignatureAsset: Codable, Equatable {
    let kind: SignatureKind
    var strokes: [SignatureStroke]
    var typedText: String?

    var isValid: Bool {
        !strokes.allSatisfy(\.points.isEmpty)
            || !(typedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private enum SignatureInputMode: String, CaseIterable, Identifiable {
    case draw
    case type

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct SignatureCaptureView: View {
    let kind: SignatureKind
    let existingAsset: SignatureAsset?
    let save: (SignatureAsset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: SignatureInputMode
    @State private var strokes: [SignatureStroke]
    @State private var currentStroke: SignatureStroke?
    @State private var typedText: String

    init(kind: SignatureKind, existingAsset: SignatureAsset?, save: @escaping (SignatureAsset) -> Void) {
        self.kind = kind
        self.existingAsset = existingAsset
        self.save = save
        let existingText = existingAsset?.typedText ?? ""
        #if DEBUG
        let startsInTypeMode = ProcessInfo.processInfo.arguments.contains("--signature-type-mode")
        #else
        let startsInTypeMode = false
        #endif
        _mode = State(initialValue: startsInTypeMode || !existingText.isEmpty ? .type : .draw)
        _strokes = State(initialValue: existingAsset?.strokes ?? [])
        _typedText = State(initialValue: existingText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create your \(kind.title.lowercased())")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(FolikTheme.ink)
                        Text("Stored locally by Folik and never uploaded. You can replace it whenever you like.")
                            .font(.subheadline)
                            .foregroundStyle(FolikTheme.mutedInk)
                    }

                    Picker("Input method", selection: $mode) {
                        ForEach(SignatureInputMode.allCases) { inputMode in
                            Text(inputMode.title).tag(inputMode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if mode == .draw {
                        drawingPad
                        HStack(spacing: 12) {
                            Button("Undo", systemImage: "arrow.uturn.backward") {
                                if !strokes.isEmpty { strokes.removeLast() }
                            }
                            .disabled(strokes.isEmpty)
                            .frame(minHeight: 44)

                            Button("Clear", systemImage: "trash", role: .destructive) {
                                strokes.removeAll()
                                currentStroke = nil
                            }
                            .disabled(strokes.isEmpty && currentStroke == nil)
                            .frame(minHeight: 44)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(kind.title)
                                .font(.subheadline.weight(.semibold))
                            TextField(
                                "",
                                text: $typedText,
                                prompt: Text(kind == .signature ? "Your name" : "Your initials")
                                    .foregroundStyle(FolikTheme.mutedInk)
                            )
                            .textInputAutocapitalization(.words)
                            .font(.title3)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(FolikTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(FolikTheme.cobalt.opacity(0.32), lineWidth: 1)
                            }
                            .accessibilityIdentifier("signature.typedText")
                            typedPreview
                        }
                    }
                }
                .padding(20)
            }
            .background(FolikTheme.surface)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(asset)
                        dismiss()
                    }
                    .disabled(!asset.isValid)
                    .accessibilityIdentifier("signature.save")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(currentStroke != nil)
    }

    private var drawingPad: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FolikTheme.cobalt.opacity(0.28), lineWidth: 1)
                Canvas { context, size in
                    for stroke in visibleStrokes {
                        guard let first = stroke.points.first else { continue }
                        var path = Path()
                        path.move(to: point(first, in: size))
                        for pointValue in stroke.points.dropFirst() {
                            path.addLine(to: point(pointValue, in: size))
                        }
                        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                if visibleStrokes.allSatisfy(\.points.isEmpty) {
                    Text("Sign inside this box")
                        .font(.headline)
                        .foregroundStyle(Color.black.opacity(0.34))
                        .allowsHitTesting(false)
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawingGesture(in: geometry.size))
            }
        }
        .frame(minHeight: 230, maxHeight: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signature drawing area")
        .accessibilityHint("Draw with one finger or Apple Pencil, or choose Type above")
        .accessibilityIdentifier("signature.canvas")
    }

    private var typedPreview: some View {
        Text(typedText.isEmpty ? kind.title : typedText)
            .font(.custom("Snell Roundhand", size: kind == .signature ? 42 : 36).weight(.bold))
            .foregroundStyle(typedText.isEmpty ? Color.black.opacity(0.25) : Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(.horizontal, 20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FolikTheme.cobalt.opacity(0.28), lineWidth: 1)
            }
            .accessibilityLabel(typedText.isEmpty ? "No typed \(kind.title.lowercased())" : "Preview: \(typedText)")
    }

    private var visibleStrokes: [SignatureStroke] {
        currentStroke.map { strokes + [$0] } ?? strokes
    }

    private var asset: SignatureAsset {
        switch mode {
        case .draw:
            SignatureAsset(kind: kind, strokes: strokes, typedText: nil)
        case .type:
            SignatureAsset(
                kind: kind,
                strokes: [],
                typedText: typedText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let normalized = SignaturePoint(
                    x: min(1, max(0, value.location.x / max(1, size.width))),
                    y: min(1, max(0, value.location.y / max(1, size.height)))
                )
                if currentStroke == nil { currentStroke = SignatureStroke(points: []) }
                currentStroke?.points.append(normalized)
            }
            .onEnded { _ in
                guard let currentStroke, !currentStroke.points.isEmpty else { return }
                strokes.append(currentStroke)
                self.currentStroke = nil
            }
    }

    private func point(_ point: SignaturePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}
