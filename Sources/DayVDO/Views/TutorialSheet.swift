import AVFoundation
import SwiftUI

struct TutorialSheet: View {
    @ObservedObject var guide: OnboardingSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: GuideCourse? = .tour
    @State private var choosingCourse = false
    var enterDayVDO: (() -> Void)? = nil
    let openPractice: (GuideCourse) -> Void

    var body: some View {
        let course = selection ?? .tour
        let offersChoice = enterDayVDO != nil && !choosingCourse
        HelpReferenceSheet(title: L10n.string("使用教程"), width: 720, height: 340, sidebarWidth: 194,
                           doneLabel: offersChoice ? "进入 DayVDO" : "完成",
                           beforeDismiss: offersChoice ? enterDayVDO : nil) {
            List(selection: $selection) {
                ForEach(GuideCourse.allCases, id: \.self) { lesson in
                    Text(L10n.string(lesson.title))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 3)
                        .tag(lesson)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6)
            .padding(.top, 8)
        } detail: {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string(course.title))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TutorialRecording(course: course, autoplay: !reduceMotion)
                    .id(course)
            }
            .padding(16)
        } actions: {
            if offersChoice {
                Text(L10n.string("练习完成")).foregroundStyle(.secondary)
                Button(L10n.string("自己选择教程")) { choosingCourse = true }
            } else {
                Button(L10n.string(practiceAction(course))) { openPractice(course) }
            }
        }
    }

    private func practiceAction(_ course: GuideCourse) -> String {
        switch guide.status(course) {
        case .paused: "继续练习"
        case .completed: "再练一次"
        default: "开始练习"
        }
    }
}

private struct TutorialRecording: View {
    // The bundled recordings capture a 1080 × 720 DayVDO window.
    private static let recordingAspectRatio: CGFloat = 3.0 / 2.0
    let autoplay: Bool
    @State private var player: AVPlayer?
    @State private var reachedEnd = false

    init(course: GuideCourse, autoplay: Bool) {
        self.autoplay = autoplay
        let recording = Self.recordingURL(for: course).map(AVPlayer.init(url:))
        recording?.allowsExternalPlayback = false
        _player = State(initialValue: recording)
    }

    static func recordingURL(for course: GuideCourse) -> URL? {
        L10n.resources.url(forResource: "tutorial-\(course.rawValue)", withExtension: "mp4")
    }

    var body: some View {
        Group {
            if let player {
                Button { togglePlayback(player) } label: {
                    TutorialPlayerView(player: player)
                        .aspectRatio(Self.recordingAspectRatio, contentMode: .fit)
                        .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(TutorialPlaybackButtonStyle())
                .focusEffectDisabled()
                .accessibilityLabel(L10n.string("播放、暂停或重播教程影片"))
                .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime,
                                                               object: player.currentItem)) { _ in
                    reachedEnd = true
                }
            } else {
                ContentUnavailableView(L10n.string("无法播放教程影片"), systemImage: "play.rectangle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if autoplay { player?.play() }
        }
        .onDisappear { player?.pause() }
    }

    private func togglePlayback(_ player: AVPlayer) {
        if player.timeControlStatus != .paused {
            player.pause()
        } else {
            if reachedEnd {
                player.seek(to: .zero)
                reachedEnd = false
            }
            player.play()
        }
    }
}

private struct TutorialPlaybackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Use the same surface when hovered, focused or pressed.
        configuration.label
    }
}

private struct TutorialPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> TutorialVideoSurface {
        TutorialVideoSurface()
    }

    func updateNSView(_ view: TutorialVideoSurface, context: Context) {
        view.setPlayer(player)
    }
}

private final class TutorialVideoSurface: NSView {
    private let video = AVPlayerLayer()
    private var readiness: NSKeyValueObservation?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        video.videoGravity = .resizeAspectFill
        video.actions = ["opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
        video.opacity = 0
        layer?.addSublayer(video)
    }

    required init?(coder: NSCoder) { nil }

    func setPlayer(_ player: AVPlayer) {
        guard video.player !== player else { return }
        readiness?.invalidate()
        video.opacity = 0
        video.player = player
        readiness = video.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.video.opacity = self.video.isReadyForDisplay ? 1 : 0
            }
        }
    }

    override func layout() {
        super.layout()
        video.frame = bounds
    }
}
