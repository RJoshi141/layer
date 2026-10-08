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
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []

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
            DocumentCameraView { images in
                showCamera = false
                process(images)
            } onCancel: {
                showCamera = false
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
            pickView
        case .processing:
            ProgressView("Reading the label…")
                .navigationTitle("Add product")
        case .review(let result):
            ReviewProductView(result: result) { dismiss() }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't read that", systemImage: "text.viewfinder")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { stage = .pick }
            }
            .navigationTitle("Add product")
        }
    }

    private var pickView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Scan the front and back")
                .font(.title2.bold())
            Text("Layer reads the ingredient list on your device. Nothing leaves your phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                showCamera = true
            } label: {
                Label("Scan with camera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!VNDocumentCameraViewController.isSupported)

            // Photos path doubles as the simulator path, since the simulator has no camera
            PhotosPicker(selection: $photoItems, maxSelectionCount: 3, matching: .images) {
                Label("Choose photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .navigationTitle("Add product")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        process(images)
    }

    private func process(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
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
