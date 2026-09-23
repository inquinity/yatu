//
//  MenuBuilder.swift
//  YatuKit
//
//  Turning `MenuModel`'s descriptors into an `NSMenu`.
//
//  This lives here, rather than in the extension, so it can be tested. The
//  extension is an executable target and nothing can import it, which is why
//  the one piece of it that had a bug — the AppKit wiring of the menu — went
//  unexamined until someone clicked an item and nothing happened.
//
//  ## The rules this encodes, and why they are rules
//
//  `FIFinderSync.menu(for:)` hands an `NSMenu` to **Finder**, which draws it in
//  its own process. That is a process boundary, and two things do not cross it:
//
//  * a `target`, which would point at an object inside the extension. Setting
//    one means the action is never delivered: the item looks normal, is
//    enabled, highlights on hover, and does nothing at all when clicked. With
//    the target left nil the action goes down the responder chain, which is how
//    FIFinderSync routes it back to the principal object.
//  * a `representedObject` holding a custom class, which Finder cannot decode.
//
//  So an item carries exactly one thing: `tag`, an index into the actionable
//  descriptors returned alongside the menu. `MenuBuilderTests` asserts both,
//  because both were violated in shipping code and neither is visible by
//  reading the menu on screen.
//

import AppKit

public enum MenuBuilder {

    /// A menu, and the descriptors its items' tags index into.
    ///
    /// Headers and separators are not in `actionable`: they carry no action, so
    /// nothing can be chosen from them, and including them would make every tag
    /// an index into a different list than the one the caller looks up.
    public struct Built {
        public let menu: NSMenu
        public let actionable: [MenuModel.Item]
    }

    /// Build the option-click menu.
    ///
    /// - Parameters:
    ///   - items: what to show, from `MenuModel.items(for:…)`.
    ///   - action: the selector to send. The item's target stays nil on purpose.
    ///   - image: an icon for an application URL, if one can be had cheaply.
    public static func build(items: [MenuModel.Item],
                             action: Selector,
                             image: (URL) -> NSImage? = { _ in nil }) -> Built {
        let menu = NSMenu(title: "Yatu")
        // Finder is not going to run our validation, so enablement is decided
        // here and stated on each item.
        menu.autoenablesItems = false
        var actionable: [MenuModel.Item] = []

        for descriptor in items {
            switch descriptor.kind {
            case .separator:
                menu.addItem(.separator())

            case .header:
                let header = NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)

            case .setDefault, .sendToEditor, .settings:
                let item = NSMenuItem(title: descriptor.title, action: action, keyEquivalent: "")
                item.target = nil               // see the note above; this is the bug
                item.tag = actionable.count
                item.isEnabled = true
                item.indentationLevel = 0
                item.image = descriptor.applicationURL.flatMap(image)
                actionable.append(descriptor)
                menu.addItem(item)
            }
        }
        return Built(menu: menu, actionable: actionable)
    }
}
