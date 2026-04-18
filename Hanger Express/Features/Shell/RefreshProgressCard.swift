import SwiftUI

struct RefreshProgressCard: View {
    let progress: RefreshProgress
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.stepLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let fractionCompleted = progress.fractionCompleted {
                    Text(fractionCompleted, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(progress.stage.title)
                .font(compact ? .headline : .title3.bold())

            progressBar

            Text(progress.detail)
                .font(compact ? .caption : .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 14 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous))
    }

    @ViewBuilder
    private var progressBar: some View {
        if let fractionCompleted = progress.fractionCompleted {
            ProgressView(value: fractionCompleted)
                .tint(.blue)
        } else {
            ProgressView()
                .tint(.blue)
        }
    }
}
