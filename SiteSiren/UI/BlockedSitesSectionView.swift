import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct BlockedSitesSectionView: View {
    @ObservedObject var domainManager: BlockedDomainManager
    @State private var newDomainInput: String = ""
    @State private var importExportMessage: String? = nil
    
    public init(domainManager: BlockedDomainManager) {
        self.domainManager = domainManager
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Search and Count Bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search blocked websites...", text: $domainManager.searchText)
                        .textFieldStyle(.plain)
                    if !domainManager.searchText.isEmpty {
                        Button(action: { domainManager.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                Spacer()
                
                Menu {
                    Button("Export as JSON...") {
                        exportDomainsAsJSON()
                    }
                    Button("Export as Plain Text...") {
                        exportDomainsAsText()
                    }
                    Divider()
                    Button("Import from File...") {
                        importDomainsFromFile()
                    }
                } label: {
                    Label("Backup / Restore", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 150)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Domain List
            List {
                if domainManager.filteredDomains.isEmpty {
                    Text(domainManager.searchText.isEmpty ? "No blocked websites yet. Add one below!" : "No websites matching '\(domainManager.searchText)'")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(domainManager.filteredDomains) { rule in
                        HStack {
                            Image(systemName: "shield.slash.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 13))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.domain)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                Text("Matches \(rule.domain) and all subdomains (*.\(rule.domain))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive, action: {
                                domainManager.removeDomain(rule)
                            }) {
                                Text("Remove")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .cornerRadius(8)
            .padding(.horizontal)
            
            // Add Website Controls
            VStack(spacing: 6) {
                if let err = domainManager.errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let msg = importExportMessage {
                    Text(msg)
                        .foregroundColor(.green)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack {
                    TextField("Enter website (e.g. youtube.com, reddit.com)", text: $newDomainInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWebsite()
                        }
                    
                    Button(action: {
                        addWebsite()
                    }) {
                        Label("Add Website", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newDomainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Text("Tip: If a website was already open in your browser, refresh or reopen the tab to apply the block.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
    
    private func addWebsite() {
        let trimmed = newDomainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let result = domainManager.addDomain(trimmed)
        if case .success = result {
            newDomainInput = ""
            importExportMessage = nil
        }
    }
    
    private func exportDomainsAsJSON() {
        guard let json = domainManager.exportAsJSON() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SiteSiren_BlockedDomains.json"
        panel.allowedContentTypes = [UTType.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
            importExportMessage = "Exported to \(url.lastPathComponent)"
        }
    }
    
    private func exportDomainsAsText() {
        let text = domainManager.exportAsText()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SiteSiren_BlockedDomains.txt"
        panel.allowedContentTypes = [UTType.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            importExportMessage = "Exported to \(url.lastPathComponent)"
        }
    }
    
    private func importDomainsFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.plainText, UTType.json]
        
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let res: (added: Int, skipped: Int)
            if url.pathExtension.lowercased() == "json" {
                res = domainManager.importFromJSON(content)
            } else {
                res = domainManager.importFromText(content)
            }
            importExportMessage = "Imported \(res.added) new domain(s) (\(res.skipped) duplicates skipped)."
        }
    }
}
