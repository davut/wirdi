//
//  QuranPromptView.swift
//  Wirdi
//
//  Compact notch overlay that asks "Start reading?" with Yes / Not now buttons.
//

import SwiftUI

struct QuranPromptView: View {
    let surahNumber: Int
    let ayahRange: String
    var onStart: () -> Void
    var onLater: () -> Void

    // Animation state
    @State private var expansion: CGFloat = 0
    @State private var contentVisible = false
    @State private var shouldDismiss = false

    private let notchHeight: CGFloat = 37
    private let notchWidth: CGFloat = 200
    private let topInset: CGFloat = 16
    private let collapsedInset: CGFloat = 8

    let menuBarHeight: CGFloat

    private var currentTopInset: CGFloat {
        collapsedInset + (topInset - collapsedInset) * expansion
    }

    private var currentBottomRadius: CGFloat {
        8 + (18 - 8) * expansion
    }

    var body: some View {
        GeometryReader { geo in
            let targetHeight = menuBarHeight + 32
            let currentHeight = notchHeight + (targetHeight - notchHeight) * expansion
            let currentWidth = notchWidth + (geo.size.width - notchWidth) * expansion

            ZStack(alignment: .top) {
                DynamicIslandShape(
                    topInset: currentTopInset,
                    bottomRadius: currentBottomRadius
                )
                .fill(.black)
                .frame(width: currentWidth, height: currentHeight)

                if contentVisible {
                    HStack(spacing: 10) {
                        // Reminder dot
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)

                        Text(QuranDataManager.surahLigature(surahNumber))
                            .font(Font(QuranDataManager.surahNameFont(size: 16)))
                            .foregroundStyle(.white.opacity(0.5))

                        Text(ayahRange)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))

                        Spacer(minLength: 0)

                        Button {
                            dismissThen { onStart() }
                        } label: {
                            Text("Read")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismissThen { onLater() }
                        } label: {
                            Text("Later")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .frame(width: geo.size.width)
                    .offset(y: menuBarHeight + 4)
                    .transition(.opacity)
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                expansion = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.25)) {
                    contentVisible = true
                }
            }
        }
    }

    private func dismissThen(action: @escaping () -> Void) {
        guard !shouldDismiss else { return }
        shouldDismiss = true
        withAnimation(.easeIn(duration: 0.15)) {
            contentVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.3)) {
                expansion = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            action()
        }
    }
}
