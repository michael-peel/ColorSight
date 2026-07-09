import SwiftUI
import SwiftData

struct CameraView: View {

    var startHueIsolation: Bool = false

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var viewModel         = CameraViewModel()
    @AppStorage("regionSamplingEnabled") private var regionSamplingEnabled = true
    // Same UserDefaults key CVDProfile.save()/load() use, so this stays in sync
    // whenever the profile changes in Settings.
    @AppStorage("cvdProfile") private var cvdProfileRaw = CVDProfile.defaultProfile.rawValue
    private var activeCVDProfile: CVDProfile { CVDProfile(rawValue: cvdProfileRaw) ?? .normal }
    @AppStorage("confusionWarningsEnabled") private var confusionWarningsEnabled = true

    @State private var showingSettings   = false
    @State private var showingEyedropper = false
    @State private var showingHistory    = false
    @State private var isRefocusing      = false
    @State private var pressWorkItem:    DispatchWorkItem? = nil
    @State private var sharePayload:     SharePayload?

    // Pinch-to-zoom state
    @State private var isPinching           = false
    @State private var pinchBaseZoomFactor: CGFloat = 1.0
    @State private var showingZoomPill      = false
    @State private var zoomPillHideWorkItem: DispatchWorkItem?

    @AppStorage("hasSeenCameraTooltip")       private var hasSeenCameraTooltip = false
    @AppStorage("hueIsolationActivationCount") private var hueIsolationActivationCount = 0
    @State private var showingTooltip = false
    @State private var buttonFrames: [TooltipButtonID: CGRect] = [:]
    @State private var showingIsolationBanner = false

    // Safe-area insets read directly from UIKit so we can place UI elements
    // correctly after making the ZStack full-screen with .ignoresSafeArea().
    // The ZStack must fill the full screen so CrosshairView is centered at the
    // same pixel the camera actually samples (the geometric center of the frame),
    // not the center of the smaller safe-area rectangle.
    private var safeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? .zero
    }

    var body: some View {
        ZStack {
            // MARK: - Live preview (full screen)
            CameraPreviewView(session: viewModel.session)

            // MARK: - Display filter overlay (hue isolation or high contrast)
            // Sits above the raw preview so the active filter is visible, but below the
            // crosshair and all controls. Hue isolation and high contrast are mutually
            // exclusive and share the same display layer (see CameraViewModel).
            if viewModel.isHueIsolationActive || viewModel.isHighContrastActive {
                HueIsolationDisplayView(displayLayer: viewModel.isolationDisplayLayer)
                    .transition(.opacity)
            }

            // MARK: - Center crosshair
            // Because the ZStack ignores safe areas, this is centered on the
            // true screen center — matching the camera's sampled pixel exactly.
            CrosshairView(isFrozen: viewModel.isFrozen, isRegionMode: regionSamplingEnabled)

            // MARK: - Refocus feedback pill (appears just below crosshair)
            if isRefocusing {
                Text("Refocusing…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 36)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }

            // MARK: - Zoom level pill (appears below crosshair while pinching)
            // Offset clears the region-mode dashed ring (70pt diameter, so 35pt radius)
            // plus the pill's own height, so it never overlaps the crosshair in either
            // direct-sample or region-sample mode.
            if showingZoomPill {
                Text(String(format: "%.1f×", viewModel.zoomFactor))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 60)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }

            // MARK: - Bottom HUD
            VStack(spacing: 8) {
                Spacer()
                if viewModel.isHueIsolationActive {
                    if showingIsolationBanner {
                        Text("Tap a color to highlight it.\nEverything else turns gray.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 300)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    HueFamilyPickerView(selectedFamily: Bindable(viewModel).selectedHueFamily)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                colorInfoCard
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 40 + safeInsets.bottom)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isHueIsolationActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingIsolationBanner)

            // MARK: - Top bar (eyedropper left, settings + torch right)
            VStack {
                HStack(alignment: .top) {
                    // Home + Eyedropper + Hue Isolation — top-left
                    HStack(spacing: 10) {
                        // Dismiss camera and return to the home screen
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: ButtonFramesKey.self,
                                        value: [.chevron: geo.frame(in: .global)])
                                })
                        }
                        .accessibilityLabel("Back to Home")

                        Button {
                            showingEyedropper = true
                        } label: {
                            Image(systemName: "eyedropper.halffull")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: ButtonFramesKey.self,
                                        value: [.eyedropper: geo.frame(in: .global)])
                                })
                        }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.isHueIsolationActive.toggle()
                            }
                        } label: {
                            Image(systemName: "paintpalette.fill")
                                .font(.title3)
                                .foregroundStyle(
                                    viewModel.isHueIsolationActive
                                        ? viewModel.selectedHueFamily.swatchColor
                                        : Color.white
                                )
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle().strokeBorder(
                                        viewModel.isHueIsolationActive
                                            ? viewModel.selectedHueFamily.swatchColor.opacity(0.85)
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                                )
                                .shadow(color: .black.opacity(0.3), radius: 4)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: ButtonFramesKey.self,
                                        value: [.palette: geo.frame(in: .global)])
                                })
                        }
                        .accessibilityLabel("Hue Isolation Mode")
                        .accessibilityValue(viewModel.isHueIsolationActive ? "On" : "Off")
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isHueIsolationActive)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedHueFamily)
                    }
                    .padding(.leading, 16)

                    Spacer()

                    // History — top-right; Settings + Torch stacked in a column beneath it.
                    // Icons are .resizable() + aspectRatio(.fit) into a fixed 20x20 frame so
                    // History/Settings/Torch render as identically sized circles — a plain
                    // .frame() on a font-sized SF Symbol only reserves layout space, it doesn't
                    // rescale the glyph, so differing symbol bounding boxes still look uneven.
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            showingHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }

                        VStack(alignment: .center, spacing: 10) {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                            }

                            Button {
                                viewModel.toggleTorch()
                            } label: {
                                Image(systemName: viewModel.isTorchOn
                                      ? "flashlight.on.fill"
                                      : "flashlight.off.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(viewModel.isTorchOn ? Color.yellow : .white)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(key: ButtonFramesKey.self,
                                            value: [.torch: geo.frame(in: .global)])
                                    })
                            }
                            .animation(.easeInOut(duration: 0.15), value: viewModel.isTorchOn)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.isHighContrastActive.toggle()
                                }
                            } label: {
                                Image(systemName: "circle.lefthalf.filled")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(viewModel.isHighContrastActive ? Color.accentColor : .white)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(key: ButtonFramesKey.self,
                                            value: [.highContrast: geo.frame(in: .global)])
                                    })
                            }
                            .accessibilityLabel("High Contrast Mode")
                            .accessibilityValue(viewModel.isHighContrastActive ? "On" : "Off")
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isHighContrastActive)
                        }
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, safeInsets.top + 12)   // clear Dynamic Island / status bar
                Spacer()
            }

            // MARK: - Error banner
            if let error = viewModel.errorMessage {
                VStack {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, safeInsets.top + 8)
                    Spacer()
                }
            }

            // MARK: - First-launch tooltip overlay (above everything)
            if showingTooltip {
                CameraTooltipOverlay(buttonFrames: buttonFrames, onDismiss: dismissTooltip)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onPreferenceChange(ButtonFramesKey.self) { frames in
            buttonFrames = frames
        }   // ← ZStack fills full screen; crosshair at true center
        // Single drag gesture (minimumDistance: 0) handles both tap and long press
        // reliably — SwiftUI's LongPressGesture + TapGesture combination is prone
        // to the tap consuming touches before the long-press timer can accumulate.
        //
        // Logic:
        //   • Touch down  → schedule a DispatchWorkItem for 0.45 s from now
        //   • Finger lifts before 0.45 s → cancel work item, treat as tap (freeze toggle)
        //   • Work item fires (finger still down after 0.45 s) → long press → refocus
        // including: .none while the tour is visible so the DragGesture recognizer is fully
        // disabled — guarding inside the handlers is too late; the recognizer wins gesture
        // competition before handlers run, which blocks the overlay's Next/Got-it buttons.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPinching, pressWorkItem == nil else { return }
                    let work = DispatchWorkItem {
                        pressWorkItem = nil
                        viewModel.refocus()
                        withAnimation(.easeIn(duration: 0.15))  { isRefocusing = true  }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.3)) { isRefocusing = false }
                        }
                    }
                    pressWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
                }
                .onEnded { _ in
                    guard let work = pressWorkItem else { return }
                    work.cancel()
                    pressWorkItem = nil
                    guard !isPinching else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        viewModel.isFrozen.toggle()
                    }
                },
            including: showingTooltip ? .none : .all
        )
        // Pinch-to-zoom. Runs simultaneously with the tap/long-press DragGesture above;
        // starting a pinch cancels any pending tap-freeze/long-press-refocus so a second
        // finger landing mid-tap doesn't also trigger those. Zoom is applied directly to
        // the capture device (see CameraViewModel.setZoomFactor), so the crosshair and
        // area-average color sampling automatically track the zoomed frame — no separate
        // coordinate math needed here.
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if !isPinching {
                        isPinching = true
                        pinchBaseZoomFactor = viewModel.zoomFactor
                        pressWorkItem?.cancel()
                        pressWorkItem = nil
                        zoomPillHideWorkItem?.cancel()
                        withAnimation(.easeIn(duration: 0.15)) { showingZoomPill = true }
                    }
                    viewModel.setZoomFactor(pinchBaseZoomFactor * value)
                }
                .onEnded { _ in
                    isPinching = false
                    let work = DispatchWorkItem {
                        withAnimation(.easeOut(duration: 0.3)) { showingZoomPill = false }
                    }
                    zoomPillHideWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
                },
            including: showingTooltip ? .none : .all
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: payload.items, subject: payload.subject)
        }
        .fullScreenCover(isPresented: $showingEyedropper) {
            EyedropperView()
        }
        // Save to history whenever the user freezes the camera on a color.
        // Runs on a background context so the SQLite write never blocks the main thread.
        .onChange(of: viewModel.isFrozen) { _, frozen in
            guard frozen, let color = viewModel.identifiedColor else { return }
            let container = modelContext.container
            Task.detached {
                let context = ModelContext(container)
                context.insert(ColorSwatch(from: color, source: "camera"))
                try? context.save()
            }
        }
        .onAppear {
            viewModel.startSession()
            if startHueIsolation { viewModel.isHueIsolationActive = true }
            if !hasSeenCameraTooltip {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeIn(duration: 0.3)) { showingTooltip = true }
                }
            }
        }
        .onDisappear { viewModel.stopSession() }
        .onChange(of: hasSeenCameraTooltip) { _, newValue in
            if !newValue && !showingTooltip {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeIn(duration: 0.3)) { showingTooltip = true }
                }
            }
        }
        .onChange(of: viewModel.isHueIsolationActive) { _, active in
            guard active, hueIsolationActivationCount < 5 else { return }
            hueIsolationActivationCount += 1
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingIsolationBanner = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { showingIsolationBanner = false }
            }
        }
    }

    // MARK: - Helpers

    private func dismissTooltip() {
        withAnimation(.easeOut(duration: 0.3)) { showingTooltip = false }
        hasSeenCameraTooltip = true
    }

    // MARK: - Color info card

    @ViewBuilder
    private var colorInfoCard: some View {
        if let color = viewModel.identifiedColor {
            let profile = activeCVDProfile
            // Confusion warnings are only useful once the color holds still — see
            // the class-level note on why this is gated to the frozen state.
            let warning = (viewModel.isFrozen && confusionWarningsEnabled)
                ? CVDColorContext.confusionWarning(for: color.simpleName, r: color.rgb.r, g: color.rgb.g, b: color.rgb.b, profile: profile)
                : nil
            let note = CVDColorContext.contextNote(for: color.simpleName, hex: color.hex, r: color.rgb.r, g: color.rgb.g, b: color.rgb.b, profile: profile)
            let primaryText = profile == .achromatopsia
                ? "\(CVDColorContext.brightnessLabel(r: color.rgb.r, g: color.rgb.g, b: color.rgb.b)) — \(color.simpleName)"
                : color.simpleName

            // At accessibility text sizes, a fixed 100pt-wide side swatch leaves too
            // little room for wrapped text, so we stack the card vertically instead.
            // Either way, the Dynamic Type range is capped at .accessibility2 below —
            // otherwise the card would keep growing until it swallowed the screen,
            // the exact bug we hit before adding the CVD notes/badges.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityColorCard(color: color, primaryText: primaryText, note: note, warning: warning)
                } else {
                    standardColorCard(color: color, primaryText: primaryText, note: note, warning: warning)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)

        } else {
            HStack {
                ProgressView().tint(.white)
                Text("Identifying color…")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Default layout: color swatch on the left, text stacked to its right.
    @ViewBuilder
    private func standardColorCard(color: IdentifiedColor, primaryText: String, note: String?, warning: String?) -> some View {
        HStack(spacing: 0) {
            color.swiftUIColor
                .frame(width: 100)
                .clipShape(
                    .rect(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryText)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if color.name != color.simpleName {
                    Text(color.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 12) {
                    Text(color.hex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(color.rgbDisplayString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let warning {
                    ConfusionWarningBadge(text: warning)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Share button — visible only when frozen
            // (lock indicator already shown in the crosshair ring)
            if viewModel.isFrozen {
                Button {
                    let img = SwatchImageRenderer.render(color: color)
                    sharePayload = SharePayload(
                        items:   [img, "\(color.simpleName) – \(color.hex)"],
                        subject: color.simpleName
                    )
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(minHeight: 88, maxHeight: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    viewModel.isFrozen ? Color.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: color.hex)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isFrozen)
    }

    /// Accessibility-size layout: a small swatch chip beside the title, everything
    /// else stacked full-width below so large wrapped text has room to breathe
    /// instead of being squeezed by a fixed-width side swatch.
    @ViewBuilder
    private func accessibilityColorCard(color: IdentifiedColor, primaryText: String, note: String?, warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                color.swiftUIColor
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(primaryText)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if viewModel.isFrozen {
                    Button {
                        let img = SwatchImageRenderer.render(color: color)
                        sharePayload = SharePayload(
                            items:   [img, "\(color.simpleName) – \(color.hex)"],
                            subject: color.simpleName
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if color.name != color.simpleName {
                Text(color.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text(color.hex)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(color.rgbDisplayString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let warning {
                ConfusionWarningBadge(text: warning)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    viewModel.isFrozen ? Color.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: color.hex)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isFrozen)
    }
}

// MARK: - Crosshair

private struct CrosshairView: View {
    var isFrozen:     Bool
    var isRegionMode: Bool

    var body: some View {
        ZStack {
            // Outer dashed ring — visible in region mode to indicate the sampled area
            if isRegionMode {
                Circle()
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 70, height: 70)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .transition(.scale.combined(with: .opacity))
            }

            // Inner ring — accent-colored when frozen
            Circle()
                .strokeBorder(
                    isFrozen ? Color.accentColor : .white,
                    lineWidth: isFrozen ? 2.5 : 2
                )
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.4), radius: 3)

            if isFrozen {
                // Lock icon in the center
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Normal tick marks
                Group {
                    Rectangle().fill(.white).frame(width: 12, height: 1.5).offset(x: -28)
                    Rectangle().fill(.white).frame(width: 12, height: 1.5).offset(x: 28)
                    Rectangle().fill(.white).frame(width: 1.5, height: 12).offset(y: -28)
                    Rectangle().fill(.white).frame(width: 1.5, height: 12).offset(y: 28)
                }
                .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

// MARK: - Preference key for capturing toolbar button frames

private enum TooltipButtonID: String {
    case chevron, eyedropper, torch, palette, highContrast
}

private struct ButtonFramesKey: PreferenceKey {
    static var defaultValue: [TooltipButtonID: CGRect] = [:]
    static func reduce(value: inout [TooltipButtonID: CGRect], nextValue: () -> [TooltipButtonID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Step-by-step coach mark overlay

private struct CameraTooltipOverlay: View {
    let buttonFrames: [TooltipButtonID: CGRect]
    let onDismiss:    () -> Void

    @State private var currentStep = 0

    private let steps: [(id: TooltipButtonID, label: String)] = [
        (.chevron,      "Go back to the home screen"),
        (.eyedropper,   "Open a photo to sample colors"),
        (.palette,      "Hue Isolation — highlight one color, gray out the rest"),
        (.torch,        "Toggle the flashlight"),
        (.highContrast, "High Contrast — boosts visibility in low light"),
    ]

    private var isLastStep:   Bool            { currentStep == steps.count - 1 }
    private var currentID:    TooltipButtonID { steps[currentStep].id }
    private var currentFrame: CGRect?         { buttonFrames[currentID] }

    private func labelX(for frame: CGRect) -> CGFloat {
        let halfPill: CGFloat = 110
        let margin:   CGFloat = 16
        let screenW = UIScreen.main.bounds.width
        return max(halfPill + margin, min(frame.midX, screenW - halfPill - margin))
    }

    var body: some View {
        ZStack {
            // Dim overlay — full screen at 0.7, clear ellipse cut out around focused button
            ZStack {
                Color.black.ignoresSafeArea()
                if let frame = currentFrame {
                    Ellipse()
                        .frame(width: frame.width + 28, height: frame.height + 28)
                        .position(x: frame.midX, y: frame.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .opacity(0.7)
            .ignoresSafeArea()

            // Pulsing ring — stays in place, fades in/out
            if let frame = currentFrame {
                PulsingRing(frame: frame)
                    .id(currentStep)
            }

            // Label pill below the focused button
            if let frame = currentFrame {
                Text(steps[currentStep].label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 220)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .position(x: labelX(for: frame), y: frame.maxY + 48)
            }

            // Bottom capsule: Next → for steps 0–2, Got it ✓ for step 3
            VStack {
                Spacer()
                Button {
                    if isLastStep {
                        onDismiss()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { currentStep += 1 }
                    }
                } label: {
                    Text(isLastStep ? "Got it ✓" : "Next →")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color.purple, in: Capsule())
                }
                .padding(.bottom, 60)
            }
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}


// MARK: - Pulsing ring (opacity only — no scale movement)

private struct PulsingRing: View {
    let frame: CGRect
    @State private var pulse = false

    var body: some View {
        Circle()
            .strokeBorder(.white, lineWidth: 2)
            .frame(width: frame.width + 20, height: frame.height + 20)
            .position(x: frame.midX, y: frame.midY)
            .opacity(pulse ? 0.2 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

#Preview {
    CameraView()
}
