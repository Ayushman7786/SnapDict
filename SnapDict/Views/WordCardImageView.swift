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
                        .foregroundStyle(Color.black.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // 分隔线
            Rectangle()
                .fill(Color.black)
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
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}
#Preview {
    WordCardImageView(
        word: "serendipity",
        phonetic: "/ˌserənˈdɪpɪti/",
        translation: "n. 意外发现珍奇事物的运气；机缘巧合"
    )
    .padding()
}

