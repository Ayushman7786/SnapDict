import SwiftUI

struct WordCardImageView: View {
    let word: String
    let phonetic: String
    let translation: String

    private let cardWidth: CGFloat = 296
    private let cardHeight: CGFloat = 152

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 上半部分：单词 + 音标
            HStack(alignment: .firstTextBaseline) {
                Text(word)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Spacer()
                if !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // 分隔线
            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // 下半部分：中文释义
            Text(translation)
                .font(.system(size: 16))
                .lineLimit(3)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            Spacer()

            // 右下角水印
            HStack {
                Spacer()
                Text("SnapDict")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}
