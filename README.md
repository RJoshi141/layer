# Layer

An on-device AI skincare assistant for iOS. Scan the back of a bottle, and Layer turns the ingredient list into structured data, flags actives and irritants, tracks how long the product lasts after opening, and (soon) tells you what's safe to layer.

Everything runs on device: Vision for OCR, Apple's Foundation Models for extraction, SwiftData for storage.

## How label scanning works

```
photo(s) ──► Vision OCR ──┬──► INCI parser ──► ingredient DB match ──┐
                          │                                          ├──► review screen ──► shelf
                          └──► regex rules + on-device LLM ──────────┘
                               (name, brand, type, PAO, % actives)
```

- **Ingredients never touch the LLM.** A deterministic parser splits the INCI list (handling `1,2-Hexanediol`, `Water (Aqua)`, and words broken across lines), then matches each name against a bundled database with alias and typo-tolerant lookup. A model can't hallucinate an ingredient that isn't on the bottle.
- **The model handles the fuzzy parts.** Product name, brand, and category come from `@Generable` guided generation, so the output is typed Swift, not JSON to parse.
- **Rules first, model second.** Regex runs every time and is the full fallback on devices without Apple Intelligence.
- **Human in the loop.** Nothing is saved until you've reviewed it.

## Stack

SwiftUI · SwiftData · Vision (`RecognizeTextRequest`) · VisionKit document camera · Foundation Models · Swift Testing

## Roadmap

- [x] Label scanning, ingredient database, shelf
- [x] Conflict checker and routine builder (rule-based, layering order by product type)
- [x] Voice check-ins with SpeechAnalyzer ("used the retinol, skin feels tight" → structured log)
- [x] Skin profile onboarding and personal fit checks ("good for breakouts", "has fragrance and you said avoid it")
- [x] Expiry tracking with typical shelf life when the label has no open-jar symbol
- [ ] Assistant with tool calling over your shelf and logs
- [ ] App Intents, Siri, and a "tonight's routine" widget

## Requirements

iOS 26+, Xcode 26+. Apple Intelligence is optional; without it, product fields come from text rules only.

> Ingredient info, not medical advice.
