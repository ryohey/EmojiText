//
//  EmojiText.swift
//  EmojiText
//
//  Created by David Walter on 11.01.23.
//

import SwiftUI
import Nuke
import os

/// Text with support for custom emojis
///
/// Custom Emojis are in the format `:emoji:`.
/// Supports local and remote custom emojis.
/// Remote emojis are resolved using [Nuke](https://github.com/kean/Nuke)
public struct EmojiText: View {
    @Environment(\.emojiImagePipeline) var imagePipeline
    @Environment(\.placeholderEmoji) var placeholderEmoji
    @Environment(\.font) var font
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.emojiSize) var emojiSize
    @Environment(\.emojiBaselineOffset) var emojiBaselineOffset
    
    @ScaledMetric
    var scaleFactor: CGFloat = 1.0
    
    let raw: String
    let isMarkdown: Bool
    let emojis: [any CustomEmoji]
    
    var prepend: (() -> Text)?
    var append: (() -> Text)?
    
    @State private var preRendered: String?
    @State private var renderedEmojis = [String: RenderedEmoji]()
    @State private var loadedHashValue: Int?
    
    public var body: some View {
        rendered
            .task(id: hashValue) {
                guard hashValue != loadedHashValue else {
                    return
                }
                guard !emojis.isEmpty else {
                    self.renderedEmojis = [:]
                    return
                }
                
                // Set placeholders
                self.renderedEmojis = loadPlaceholders()
                
                // Load actual emojis
                self.renderedEmojis = await loadEmojis()

                loadedHashValue = hashValue
            }
            .onChange(of: renderedEmojis) { emojis in
                self.preRendered = preRender(with: emojis)
            }
    }
    
    // MARK: - Load Emojis
    
    func loadPlaceholders() -> [String: RenderedEmoji] {
        let targetHeight = self.targetHeight
        
        var placeholders = [String: RenderedEmoji]()
        
        for emoji in emojis {
            switch emoji {
            case let localEmoji as LocalEmoji:
                placeholders[emoji.shortcode] = RenderedEmoji(from: localEmoji, targetHeight: targetHeight)
            case let sfSymbolEmoji as SFSymbolEmoji:
                placeholders[emoji.shortcode] = RenderedEmoji(from: sfSymbolEmoji)
            default:
                placeholders[emoji.shortcode] = RenderedEmoji(placeholder: placeholderEmoji, targetHeight: targetHeight)
            }
        }
        
        return placeholders
    }

    func loadEmojis() async -> [String: RenderedEmoji] {
        let font = EmojiFont.preferredFont(from: self.font, for: self.dynamicTypeSize)
        let baselineOffset = emojiBaselineOffset ?? -(font.pointSize - font.capHeight) / 2
        let targetHeight = self.targetHeight
        
        var renderedEmojis = [String: RenderedEmoji]()
        
        for emoji in emojis {
            switch emoji {
            case let remoteEmoji as RemoteEmoji:
                do {
                    let image = try await imagePipeline.image(for: remoteEmoji.url)
                    renderedEmojis[emoji.shortcode] = RenderedEmoji(from: remoteEmoji, image: image, targetHeight: targetHeight, baselineOffset: baselineOffset)
                } catch {
                    Logger.emojiText.error("Unable to load remote emoji \(remoteEmoji.shortcode): \(error.localizedDescription)")
                }
            case let localEmoji as LocalEmoji:
                renderedEmojis[emoji.shortcode] = RenderedEmoji(from: localEmoji, targetHeight: targetHeight, baselineOffset: baselineOffset)
            case let sfSymbolEmoji as SFSymbolEmoji:
                renderedEmojis[emoji.shortcode] = RenderedEmoji(from: sfSymbolEmoji)
            default:
                // Fallback to placeholder emoji
                Logger.emojiText.warning("Tried to load unknown emoji. Falling back to placeholder emoji")
                renderedEmojis[emoji.shortcode] = RenderedEmoji(placeholder: placeholderEmoji, targetHeight: targetHeight)
            }
        }
        
        return renderedEmojis
    }
    
    // MARK: - Initializers
    
    /// Initialize a Markdown formatted Text with support for custom emojis
    ///
    /// - Parameters:
    ///     - markdown: Markdown formatted text to render
    ///     - emojis: Array of custom emojis to render
    public init(markdown: String, emojis: [any CustomEmoji]) {
        self.raw = markdown
        self.isMarkdown = true
        self.emojis = emojis
    }
    
    /// Initialize a ``EmojiText`` with support for custom emojis
    ///
    /// - Parameters:
    ///     - verbatim: A string to display without localization.
    ///     - emojis: Array of custom emojis to render
    public init(verbatim: String, emojis: [any CustomEmoji]) {
        self.raw = verbatim
        self.isMarkdown = false
        self.emojis = emojis
    }
    
    // MARK: - Modifier
    
    /// Prepend `Text` to the `EmojiText`
    ///
    /// - Parameter text: Callback generating the text to prepend
    /// - Returns: ``EmojiText`` with some text prepended
    public func prepend(text: @escaping () -> Text) -> Self {
        var view = self
        view.prepend = text
        return view
    }
    
    /// Append `Text` to the `EmojiText`
    ///
    /// - Parameter text: Callback generating the text to append
    /// - Returns: ``EmojiText`` with some text appended
    public func append(text: @escaping () -> Text) -> Self {
        var view = self
        view.append = text
        return view
    }
    
    // MARK: - Helper
    
    var hashValue: Int {
        var hasher = Hasher()
        hasher.combine(raw)
        for emoji in emojis {
            hasher.combine(emoji)
        }
        return hasher.finalize()
    }
    
    var targetHeight: CGFloat {
        if let emojiSize = emojiSize {
            return emojiSize
        } else {
            let font = EmojiFont.preferredFont(from: self.font, for: self.dynamicTypeSize)
            let height = font.pointSize * scaleFactor
            return height
        }
    }
    
    func preRender(with emojis: [String: RenderedEmoji]) -> String {
        var text = raw
        
        for shortcode in emojis.keys {
            text = text.replacingOccurrences(of: ":\(shortcode):", with: "\(String.emojiSeparator)\(shortcode)\(String.emojiSeparator)")
        }
        
        return text
    }
    
    var rendered: Text {
        var result = prepend?() ?? Text(verbatim: "")
        
        let preRendered = self.preRendered ?? raw
        
        if renderedEmojis.isEmpty {
            if isMarkdown {
                result = result + Text(markdown: preRendered)
            } else {
                result = result + Text(verbatim: preRendered)
            }
        } else {
            let splits: [String]
            if #available(iOS 16, macOS 13, tvOS 16, *) {
                splits = preRendered
                    .split(separator: String.emojiSeparator, omittingEmptySubsequences: true)
                    .map { String($0) }
            } else {
                splits = preRendered
                    .components(separatedBy: String.emojiSeparator)
            }
            splits.forEach { substring in
                if let image = renderedEmojis[substring] {
                    if let baselineOffset = image.baselineOffset {
                        result = result + Text("\(image.image)").baselineOffset(baselineOffset)
                    } else {
                        result = result + Text("\(image.image)")
                    }
                } else if isMarkdown {
                    result = result + Text(markdown: substring)
                } else {
                    result = result + Text(verbatim: substring)
                }
            }
        }
        
        if let append = self.append {
            result = result + append()
        }
        
        return result
    }
}

struct EmojiText_Previews: PreviewProvider {
    static var emojis: [any CustomEmoji] {
        [
            RemoteEmoji(shortcode: "mastodon", url: URL(string: "https://files.mastodon.social/custom_emojis/images/000/003/675/original/089aaae26a2abcc1.png")!),
            RemoteEmoji(shortcode: "puppu_purin", url: URL(string: "https://s3.fedibird.com/custom_emojis/images/000/358/023/static/5fe65ba070089507.png")!),
            SFSymbolEmoji(shortcode: "iphone")
        ]
    }
    
    static var previews: some View {
        List {
            Section {
                EmojiText(verbatim: "Hello Moon & Stars :moon.stars:",
                          emojis: [SFSymbolEmoji(shortcode: "moon.stars")])
                EmojiText(verbatim: "Hello World :mastodon: with a remote emoji",
                          emojis: emojis)
                EmojiText(verbatim: "Hello World :iphone: with a local emoji",
                          emojis: emojis)
                EmojiText(verbatim: "Hello World :mastodon: with a remote emoji",
                          emojis: emojis)
                .font(.title)
                EmojiText(verbatim: "Large Image as Emoji :large:",
                          emojis: [RemoteEmoji(shortcode: "large", url: URL(string: "https://sample-videos.com/img/Sample-jpg-image-15mb.jpeg")!)])
                EmojiText(verbatim: "Hello World :mastodon: with a custom emoji size",
                          emojis: emojis)
                .emojiSize(34)
                .emojiBaselineOffset(-8.5)
            } header: {
                Text("Text")
            }
            Section {
                EmojiText(markdown: "**Hello** *World* :mastodon: with a remote emoji",
                          emojis: emojis)
                EmojiText(markdown: "**Hello** *World* :mastodon: :test: with a remote emoji and a fake emoji",
                          emojis: emojis)
                EmojiText(markdown: "**Hello** *World* :mastodon: :iphone: with a remote and a local emoji",
                          emojis: emojis)
                EmojiText(markdown: "**Hello** *World* :test: with a remote emoji that will not respond properly",
                          emojis: [RemoteEmoji(shortcode: "test", url: URL(string: "about:blank")!)])
                EmojiText(markdown: "**Hello** *World* :notAnEmoji: with no emojis",
                          emojis: [])
                
                EmojiText(markdown: "**Hello** *World* :mastodon:",
                          emojis: emojis)
                .prepend {
                    Text("Prepended - ")
                }
                .append {
                    Text(" - Appended")
                }
            } header: {
                Text("Markdown")
            }
            Section {
                EmojiText(verbatim: "Hello World :puppu_purin: with a remote emoji.",
                          emojis: emojis)
                EmojiText(verbatim: "Hello World :mastodon: :puppu_purin: with a remote emoji.",
                          emojis: emojis)
                .font(.title)
                EmojiText(verbatim: "Hello World :mastodon: :puppu_purin: with a custom emoji.",
                          emojis: emojis)
                .emojiSize(34)
                .emojiBaselineOffset(-8.5)
                EmojiText(markdown: "**Hello** *World* :puppu_purin: with a remote emoji",
                          emojis: emojis)
            } header: {
                Text("Wide width emoji")
            }
        }
        .environment(\.emojiImagePipeline, ImagePipeline { configuration in
            configuration.imageCache = nil
            configuration.dataCache = nil
        })
    }
}
