import SwiftUI

public struct SetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("SiteSiren Setup Guide")
                        .font(.headline)
                    Text("How SiteSiren blocks websites on your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    guideStep(
                        step: "1",
                        title: "How Blocking Works",
                        description: "SiteSiren installs a Proxy Auto-Configuration (PAC) script system-wide via macOS Network Settings. All browsers and apps that respect the system proxy will route traffic through it. Domains in your blocked list are returned a 403 error; all other traffic goes direct — your normal internet is never affected."
                    )

                    guideStep(
                        step: "2",
                        title: "Add Websites to Block",
                        description: "Open the 'Blocked Websites' tab and type a domain name (e.g. youtube.com). SiteSiren will block that domain and all its subdomains (e.g. music.youtube.com) automatically. Refresh or reopen any already-open browser tabs to apply the block immediately."
                    )

                    guideStep(
                        step: "3",
                        title: "Choose Your Alert Sound",
                        description: "Go to the 'Audio' tab to pick any audio file (MP3, MP4, M4A, WAV, AIFF) or use the built-in siren. Use 'Preview' to test it. Adjust the cooldown so you don't get spammed if a page makes many requests."
                    )

                    guideStep(
                        step: "4",
                        title: "Enable Launch at Login",
                        description: "In the 'Protection' tab, toggle 'Launch at Login' so SiteSiren starts automatically every time you log into your Mac and begins blocking immediately."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Known Limitation")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Browser extensions that control their own proxy settings (such as some VPN extensions) can override the macOS system proxy and bypass SiteSiren. If a site is not being blocked in a specific browser profile, check whether a VPN or proxy extension is active in that profile.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
    }

    private func guideStep(step: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
