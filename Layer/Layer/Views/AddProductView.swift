import SwiftUI
import PhotosUI
import VisionKit

struct AddProductView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case pick
        case processing
        case review(ScanResult)
        case failed(String)
    }

    @State private var stage: Stage = .pick
    @State private var shots: [UIImage] = []          // bottles usually need 2-3 angles
    @State private var showCamera = false
    @State private var showDocScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var scanned: [UIImage] = []        // kept so the review can offer them as product photos

    // Set when rescanning a product that's already on the shelf
    private let existing: Product?

    init(existing: Product? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                shots.append(image)
                showCamera = false
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showDocScanner) {
            DocumentCameraView { images in
                showDocScanner = false
                process(images)
            } onCancel: {
                showDocScanner = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .pick:
            if shots.isEmpty { startView } else { shotsView }
        case .processing:
            ProgressView("Reading the label…")
                .navigationTitle(existing == nil ? "Add product" : "Rescan label")
        case .review(let result):
            ReviewProductView(result: result, existing: existing, photos: scanned) { dismiss() }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't read that", systemImage: "text.viewfinder")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    shots = []
                    stage = .pick
                }
            }
            .navigationTitle(existing == nil ? "Add product" : "Rescan label")
        }
    }

    // MARK: - Start

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Photograph the ingredients")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                Tip(symbol: "sun.max", text: "Bright light. Tilt the bottle until there's no glare on the text.")
                Tip(symbol: "viewfinder", text: "Get close so the ingredient list fills the frame.")
                Tip(symbol: "arrow.triangle.2.circlepath", text: "List wraps around? Take 2 or 3 photos, turning the bottle each time.")
            }
            .padding(.horizontal)

            Spacer()

            Button {
                showCamera = true
            } label: {
                Label("Take photo", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!CameraCaptureView.isAvailable)

            HStack {
                Button {
                    showDocScanner = true
                } label: {
                    Label("Scan a box", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!VNDocumentCameraViewController.isSupported)

                // Also the simulator path, since the simulator has no camera
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Label("From photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .navigationTitle(existing == nil ? "Add product" : "Rescan label")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Multi-shot

    private var shotsView: some View {
        VStack(spacing: 20) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(shots.indices, id: \.self) { index in
                        Image(uiImage: shots[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 200)
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    shots.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .padding(6)
                                .accessibilityLabel("Remove photo \(index + 1)")
                            }
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            Text(shots.count == 1
                 ? "If the list wraps around the bottle, turn it and add another angle. A shot of the barcode helps Layer find the product photo."
                 : "\(shots.count) angles. Layer will stitch the list together.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            Button {
                process(shots)
            } label: {
                Label("Read label", systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            Button {
                showCamera = true
            } label: {
                Label("Add another angle", systemImage: "camera.rotate")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal)
            .disabled(!CameraCaptureView.isAvailable || shots.count >= 4)
        }
        .padding(.vertical)
        .navigationTitle(existing == nil ? "Add product" : "Rescan label")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                shots.append(image)
            }
        }
        photoItems = []
    }

    private func process(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        scanned = images
        stage = .processing
        Task {
            do {
                let result = try await LabelScanPipeline().run(images: images)
                stage = .review(result)
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}
