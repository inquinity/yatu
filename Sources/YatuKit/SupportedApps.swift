//
//  SupportedApps.swift
//  YatuKit
//
//  The terminals and editors Yatu can open, and the bundle identifier each is
//  found by. This list is Yatu's own.
//
//  It began as OpenInTerminal's OpenInTerminalCore/SupportedApps.swift (Jianing
//  Wang, MIT licensed, https://github.com/Ji4n1ng/OpenInTerminal) at upstream
//  commit 81a6775 (2026-07-13), and was taken over on 2026-09-25: edited
//  directly, no longer compared with upstream. The MIT notice in LICENSE and
//  the credit in README.md stay. See docs/UPSTREAM.md.
//
//  ## Keeping it
//
//  Add an app when we want it; drop one when it is dead or on life support.
//  Identifiers that were not checked against an installed copy are marked
//  `unverified` below; Homebrew Cask's uninstall and zap entries were the source.
//  A wrong identifier costs little: resolution falls back to an explicit
//  `/Applications/<name>.app` (docs/DESIGN.md §4.1, rule 2).
//

import Foundation
import YatuUpstream

public enum SupportedApps: String, CaseIterable {
    
    // MARK: - Terminals
    case terminal = "Terminal"
    case iTerm = "iTerm"
    case alacritty = "Alacritty"
    case kitty = "kitty"
    case wezterm = "WezTerm"
    case tabby = "Tabby"
    case warp = "Warp"
    case cmux = "cmux"
    case githubDesktop = "GitHub Desktop"
    case gitKraken = "GitKraken"
    case fork = "Fork"
    case ghostty = "Ghostty"
    case kaku = "Kaku"
    
    // MARK: - Editors
    case textEdit = "TextEdit"
    case xcode = "Xcode"
    case vscode = "Visual Studio Code"
    case sublime = "Sublime Text"
    case vscodium = "VSCodium"
    case bbedit = "BBEdit"
    case vscodeInsiders = "Visual Studio Code - Insiders"
    case cotEditor = "CotEditor"
    case macVim = "MacVim"
    case typora = "Typora"
    case nova = "Nova"
    case cursor = "Cursor"
    case neovim = "Neovim"
    case zed = "Zed"
    case emacs = "Emacs"
    // JetBrains
    case cLion = "CLion"
    case goLand = "GoLand"
    case intelliJIDEA = "IntelliJ IDEA"
    case phpStorm = "PhpStorm"
    case pyCharm = "PyCharm"
    case rubyMine = "RubyMine"
    case webStorm = "WebStorm"
    case androidstudio = "Android Studio"
    
    public var name: String {
        return self.rawValue
    }
    
    public var shortName: String {
        switch self {
        case .vscode: return "VSCode"
        case .sublime: return "Sublime"
        case .vscodeInsiders: return "VSCodeInsiders"
        case .intelliJIDEA: return "IntelliJ_IDEA"
        case .androidstudio: return "Android_Studio"
        default:
            return self.rawValue
        }
    }
    
    public var type: AppType {
        switch self {
        case .terminal, .iTerm, .alacritty, .kitty, .wezterm, .tabby, .warp, .cmux, .githubDesktop, .fork, .ghostty, .gitKraken, .kaku:
            return .terminal
        default:
            return .editor
        }
    }
    
    /// Finds a supported app whose name matches the given name, ignoring case.
    public static func from(name: String) -> SupportedApps? {
        return SupportedApps.allCases.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    public static func isSupported(_ app: App) -> Bool {
        return from(name: app.name) != nil
    }

    public static func `is`(_ app: App, is supported: SupportedApps) -> Bool {
        return app.name.caseInsensitiveCompare(supported.name) == .orderedSame
    }
    
    public static var terminals: [SupportedApps] {
        return SupportedApps.allCases.filter {
            $0.type == .terminal
        }
    }
    
    public static var editors: [SupportedApps] {
        return SupportedApps.allCases.filter {
            $0.type == .editor
        }
    }
    
    public var bundleId: String {
        switch self {
        // Terminals
        case .terminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .alacritty: return "org.alacritty"  // unverified
        case .kitty: return "net.kovidgoyal.kitty"
        case .wezterm: return "com.github.wez.wezterm"
        case .tabby: return "org.tabby"
        case .warp: return "dev.warp.Warp-Stable"
        case .cmux: return "com.cmuxterm.app"
        case .githubDesktop: return ""
        case .gitKraken: return "com.axosoft.gitkraken"
        case .fork: return ""
        case .ghostty: return "com.mitchellh.ghostty"
        case .kaku: return "fun.tw93.kaku"
        // Editors
        case .textEdit: return "com.apple.TextEdit"
        case .xcode: return "com.apple.dt.Xcode"
        case .vscode: return "com.microsoft.VSCode"
        case .sublime: return "com.sublimetext.4"
        case .vscodium: return "com.vscodium"  // unverified
        case .bbedit: return "com.barebones.bbedit"
        case .vscodeInsiders: return "com.microsoft.VSCodeInsiders"
        case .cotEditor: return ""
        case .macVim: return "org.vim.MacVim"
        case .typora: return "abnerworks.Typora"
        case .nova: return "com.panic.Nova"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .cLion: return "com.jetbrains.CLion"  // unverified
        case .goLand: return "com.jetbrains.goland"
        case .intelliJIDEA: return "com.jetbrains.intellij"
        case .phpStorm: return "com.jetbrains.PhpStorm"
        case .pyCharm: return "com.jetbrains.pycharm"
        case .rubyMine: return "com.jetbrains.rubymine"
        case .webStorm: return "com.jetbrains.WebStorm"  // unverified
        case .androidstudio: return "com.google.android.studio"  // unverified
        case .neovim: return ""
        case .zed: return "dev.zed.Zed"
        case .emacs: return "org.gnu.Emacs"
        }
    }
    
    public var app: App {
        var app = App(name: self.name, type: self.type)
        app.bundleId = self.bundleId
        return app
    }
}
