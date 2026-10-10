import SwiftUI
import UIKit
import SwiftData

// One form for three jobs: review a new scan, edit a saved product, or apply a rescan to a saved product.
// Human-in-the-loop either way: nothing changes on the shelf until you tap Save.
struct ReviewProductView: View {
    @Environment(\.modelContext) private var context

    let result: ScanResult
    let existing: Product?
    var onSaved: () -> Void

    @State private var name: String
    @State private var brand: String
    @State private var category: ProductCategory
    @State private var paoMonths: Int?
    @State private var isOpened: Bool
    @State private var openedAt: Date
    @State private var ingredients: [ParsedIngredient]
    @State private var newIngredient = ""

    // Product photo: the one we find online plus your own shots, pick whichever looks right
    @State private var photos: [PhotoOption]
    @State private var selectedPhotoID: UUID?
    @State private var isFindingPhoto = false
    @State private var photoSearchNotes: [String] = []
    private let scannedPhotos: [UIImage]

    struct PhotoOption: Identifiable {
        let id = UUID()
        let image: UIImage
        let source: String
    }

    init(result: ScanResult, existing: Product? = nil, photos: [UIImage] = [], onSaved: @escaping () -> Void) {
        self.result = result
        self.existing = existing
        self.onSaved = onSaved
        // On a rescan, keep what you already fixed by hand. Only the ingredients come from the new scan.
        _name = State(initialValue: existing?.name ?? result.fields.name)
        _brand = State(initialValue: existing?.brand ?? result.fields.brand)
        _category = State(initialValue: existing?.category ?? result.fields.category)
        _paoMonths = State(initialValue: result.fields.paoMonths ?? existing?.paoMonths)
        _isOpened = State(initialValue: existing.map { $0.openedAt != nil } ?? true)
        _openedAt = State(initialValue: existing?.openedAt ?? .now)
        _ingredients = State(initialValue: result.ingredients)

        var options: [PhotoOption] = []
        if let data = existing?.imageData, let saved = UIImage(data: data) {
            options.append(PhotoOption(image: saved, source: "Current photo"))
        }
        options += photos.map { PhotoOption(image: $0, source: "Your photo") }
        self.scannedPhotos = photos
        _photos = State(initialValue: options)
        _selectedPhotoID = State(initialValue: options.first?.id)
    }

    private static let ownSources: Set<String> = ["Your photo", "Current photo"]   // never replaced by a new search

    private var selectedPhoto: PhotoOption? {
        photos.first { $0.id == selectedPhotoID }
    }

    private var newCount: Int { ingredients.filter(\.isNew).count }

    private var matchedCount: Int { ingredients.filter { $0.match != nil }.count }

    var body: some View {
        Form {
            photoSection

            Section {
                TextField("Product name", text: $name)
                TextField("Brand", text: $brand)
                Picker("Type", selection: $category) {
                    ForEach(ProductCategory.allCases) { category in
                        Label(category.label, systemImage: category.symbol).tag(category)
                    }
                }
            } header: {
                Text("Product")
            } footer: {
                if existing == nil {
                    Text(result.usedOnDeviceModel
                         ? "Filled in by the on-device model. Give it a quick check."
                         : "Filled in with text rules. Fix anything that's off.")
                }
            }

            Section {
                Picker("Use within", selection: $paoMonths) {
                    Text("Not on label").tag(Int?.none)
                    ForEach([3, 6, 9, 12, 18, 24, 36], id: \.self) { months in
                        Text("\(months) months").tag(Int?.some(months))
                    }
                }
                Toggle("Opened", isOn: $isOpened)
                if isOpened {
                    // Any date back in time, so you can log the bottle you opened last spring
                    DatePicker("Opened on", selection: $openedAt, in: ...Date.now, displayedComponents: .date)
                }
            } header: {
                Text("Shelf life")
            } footer: {
                if paoMonths == nil {
                    Text("No open-jar symbol found, so Layer will assume \(category.typicalPAOMonths) months, which is typical for this type of product.")
                }
            }

            if !result.fields.statedActives.isEmpty {
                Section("On the label") {
                    ForEach(result.fields.statedActives, id: \.self) { Text($0) }
                }
            }

            Section {
                if ingredients.isEmpty {
                    Text("No ingredient list found. Try another photo, or add them below.")
                        .foregroundStyle(.secondary)
                }
                ForEach($ingredients) { $item in
                    IngredientRow(raw: item.raw, match: item.match)
                        .contextMenu {
                            // Long-press to correct how a new ingredient was classified
                            if item.isNew || item.match?.isLearned == true {
                                Picker("What is it?", selection: roleBinding(for: $item)) {
                                    ForEach(IngredientReference.Role.allCases.filter { $0 != .active && $0 != .sunscreen }, id: \.self) { role in
                                        Text(role.label).tag(role)
                                    }
                                }
                            }
                        }
                }
                .onDelete { ingredients.remove(atOffsets: $0) }

                HStack {
                    TextField("Add an ingredient", text: $newIngredient)
                        .submitLabel(.done)
                        .onSubmit(addIngredient)
                    Button("Add", action: addIngredient)
                        .disabled(newIngredient.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Ingredients (\(ingredients.count))")
            } footer: {
                if !ingredients.isEmpty {
                    Text(newCount > 0
                         ? "\(newCount) new to Layer. They'll be added to your ingredient database when you save. Long-press one to change what it is, or swipe left to remove anything that isn't an ingredient."
                         : "All \(matchedCount) recognized. Swipe left to remove anything that isn't an ingredient.")
                }
            }

            if !result.rawText.isEmpty {
                // Handy when a scan goes sideways: shows exactly what OCR saw
                Section {
                    DisclosureGroup("What the camera read") {
                        Text(result.rawText)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "Review" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func roleBinding(for item: Binding<ParsedIngredient>) -> Binding<IngredientReference.Role> {
        Binding(
            get: { item.wrappedValue.match?.role ?? .other },
            set: { role in
                let raw = item.wrappedValue.raw
                item.wrappedValue.match = IngredientReference(
                    key: IngredientDatabase.learnedKey(for: raw),
                    name: raw,
                    aliases: [],
                    role: role,
                    tags: role.defaultTags,
                    summary: "You marked this as \(role.label.lowercased())."
                )
                item.wrappedValue.isNew = true   // re-learn with your correction
            }
        )
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    if let selectedPhoto {
                        Image(uiImage: selectedPhoto.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipShape(.rect(cornerRadius: 16))
                            .id(selectedPhoto.id)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                            .frame(height: 200)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                    if isFindingPhoto {
                        ProgressView("Finding product photo…")
                            .padding(12)
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }

                if photos.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(photos) { option in
                                Button {
                                    withAnimation(.snappy) { selectedPhotoID = option.id }
                                } label: {
                                    Image(uiImage: option.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(option.id == selectedPhotoID ? Color.accentColor : .clear, lineWidth: 2)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.source)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                HStack {
                    if let selectedPhoto {
                        Text(selectedPhoto.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Find product photo", systemImage: "magnifyingglass") {
                        Task { await findPhoto() }
                    }
                    .font(.caption)
                    .disabled(isFindingPhoto)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if !photoSearchNotes.isEmpty {
                // Says exactly what was tried, so a miss is explainable instead of mysterious
                Text("Couldn't find this product online, so it's using your photo. " + photoSearchNotes.joined(separator: ". ") + ".")
            }
        }
        .task {
            // New scans look the product up right away, so the real photo pops in on its own
            if existing?.imageData == nil { await findPhoto() }
        }
    }

    private func findPhoto() async {
        isFindingPhoto = true
        photoSearchNotes = []
        defer { isFindingPhoto = false }

        // Lens searches whichever of your photos is selected (pick the front of the bottle).
        // Edit mode has no fresh scan, so it falls back to the saved photo.
        var searchPhotos = scannedPhotos.isEmpty ? photos.map(\.image) : scannedPhotos
        if let selectedPhoto, Self.ownSources.contains(selectedPhoto.source) {
            searchPhotos.removeAll { $0 === selectedPhoto.image }
            searchPhotos.insert(selectedPhoto.image, at: 0)
        }
        let outcome = await ProductImageFinder.find(
            barcode: result.barcode ?? existing?.barcode,
            name: name,
            brand: brand,
            photos: searchPhotos
        )

        let found = outcome.photos.map { PhotoOption(image: $0.image, source: $0.source) }
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            // Searching again replaces the last results instead of piling up duplicates
            photos.removeAll { !Self.ownSources.contains($0.source) }
            photos.insert(contentsOf: found, at: 0)
            if selectedPhoto == nil { selectedPhotoID = photos.first?.id }
            if let first = found.first { selectedPhotoID = first.id }
        }
        if found.isEmpty { photoSearchNotes = outcome.notes }

        // Fill blanks only, and only from exact matches (barcode) or Google's read of your photo.
        // A fuzzy name match never gets to rename your product.
        if name.isEmpty { name = outcome.name.isEmpty ? (outcome.bestGuess?.capitalized ?? "") : outcome.name }
        if brand.isEmpty { brand = outcome.brand }
        if category == .other, let guess = outcome.bestGuess {
            category = HeuristicExtractor.category(in: guess.lowercased())
        }
    }

    private func addIngredient() {
        let raw = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        if let known = IngredientDatabase.shared.match(raw) {
            ingredients.append(ParsedIngredient(raw: raw, match: known))
        } else {
            ingredients.append(ParsedIngredient(raw: raw, match: IngredientClassifier.classify(raw), isNew: true))
        }
        newIngredient = ""
    }

    private func save() {
        // Grow the database: anything new on this label is known from now on
        IngredientDatabase.shared.learn(ingredients.filter(\.isNew).compactMap(\.match))

        var seen = Set<String>()
        let keys = ingredients.compactMap { $0.match?.key }.filter { seen.insert($0).inserted }
        let product = existing ?? Product(name: "")

        product.name = name.trimmingCharacters(in: .whitespaces)
        product.brand = brand.trimmingCharacters(in: .whitespaces)
        product.category = category
        product.ingredients = ingredients.map(\.raw)
        product.matchedKeys = keys
        product.paoMonths = paoMonths
        product.openedAt = isOpened ? openedAt : nil
        if !result.fields.statedActives.isEmpty { product.statedActives = result.fields.statedActives }
        if !result.rawText.isEmpty { product.rawLabelText = result.rawText }
        if let barcode = result.barcode { product.barcode = barcode }
        if let selectedPhoto { product.imageData = selectedPhoto.image.thumbnailJPEG() }

        if existing == nil { context.insert(product) }
        onSaved()
    }
}

extension ScanResult {
    // Lets "Edit details" reuse the review form without a new scan
    init(product: Product) {
        self.init(
            fields: LabelFields(
                name: product.name,
                brand: product.brand,
                category: product.category,
                paoMonths: product.paoMonths,
                statedActives: product.statedActives
            ),
            ingredients: product.ingredients.map { ParsedIngredient(raw: $0, match: IngredientDatabase.shared.match($0)) },
            rawText: "",
            usedOnDeviceModel: false
        )
    }
}
