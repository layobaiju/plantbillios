import SwiftUI

struct LanguagePickerView: View {
    @EnvironmentObject private var languageStore: LanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(AppLanguage.allCases) { language in
                Button {
                    languageStore.set(language)
                    dismiss()
                } label: {
                    HStack {
                        Text(language.nativeName)
                            .font(PlantbillTypography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        Spacer()
                        if language == languageStore.current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(PlantbillColor.green)
                        }
                    }
                    .frame(minHeight: PlantbillSpacing.minTouchTarget)
                    .contentShape(Rectangle())
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LanguagePickerView()
        .environmentObject(LanguageStore())
}
