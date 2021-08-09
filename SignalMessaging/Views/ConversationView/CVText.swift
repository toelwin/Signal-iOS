//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum CVTextValue: Equatable, Hashable {
    public typealias CacheKey = String

    case text(text: String)
    case attributedText(attributedText: NSAttributedString)

    func apply(label: UILabel) {
        switch self {
        case .text(let text):
            label.text = text
        case .attributedText(let attributedText):
            label.attributedText = attributedText
        }
    }

    func apply(textView: UITextView) {
        switch self {
        case .text(let text):
            textView.text = text
        case .attributedText(let attributedText):
            textView.attributedText = attributedText
        }
    }

    public var stringValue: String {
        switch self {
        case .text(let text):
            return text
        case .attributedText(let attributedText):
            return attributedText.string
        }
    }

    public var attributedString: NSAttributedString {
        switch self {
        case .text(let text):
            return NSAttributedString(string: text)
        case .attributedText(let attributedText):
            return attributedText
        }
    }

    var debugDescription: String {
        switch self {
        case .text(let text):
            return "text: \(text)"
        case .attributedText(let attributedText):
            return "attributedText: \(attributedText.string)"
        }
    }

    fileprivate var cacheKey: CacheKey {
        switch self {
        case .text(let text):
            return "t\(text)"
        case .attributedText(let attributedText):
            return "a\(attributedText.description)"
        }
    }
}

// MARK: - UILabel

public struct CVLabelConfig {
    public typealias CacheKey = String

    public let text: CVTextValue
    public let font: UIFont
    public let textColor: UIColor
    public let numberOfLines: Int
    public let lineBreakMode: NSLineBreakMode
    public let textAlignment: NSTextAlignment?

    public init(text: String,
                font: UIFont,
                textColor: UIColor,
                numberOfLines: Int = 1,
                lineBreakMode: NSLineBreakMode = .byWordWrapping,
                textAlignment: NSTextAlignment? = nil) {

        self.text = .text(text: text)
        self.font = font
        self.textColor = textColor
        self.numberOfLines = numberOfLines
        self.lineBreakMode = lineBreakMode
        self.textAlignment = textAlignment
    }

    public init(attributedText: NSAttributedString,
                font: UIFont,
                textColor: UIColor,
                numberOfLines: Int = 1,
                lineBreakMode: NSLineBreakMode = .byWordWrapping,
                textAlignment: NSTextAlignment? = nil) {

        self.text = .attributedText(attributedText: attributedText)
        self.font = font
        self.textColor = textColor
        self.numberOfLines = numberOfLines
        self.lineBreakMode = lineBreakMode
        self.textAlignment = textAlignment
    }

    func applyForMeasurement(label: UILabel) {
        label.font = self.font
        label.numberOfLines = self.numberOfLines
        label.lineBreakMode = self.lineBreakMode

        // Skip textColor, textAlignment.

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        self.text.apply(label: label)
    }

    public func applyForRendering(label: UILabel) {
        label.font = self.font
        label.numberOfLines = self.numberOfLines
        label.lineBreakMode = self.lineBreakMode
        label.textColor = self.textColor
        if let textAlignment = textAlignment {
            label.textAlignment = textAlignment
        } else {
            label.textAlignment = .natural
        }

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        self.text.apply(label: label)
    }

    public func measure(maxWidth: CGFloat) -> CGSize {
        let size = CVText.measureLabel(config: self, maxWidth: maxWidth)
        if size.width > maxWidth {
            owsFailDebug("size.width: \(size.width) > maxWidth: \(maxWidth)")
        }
        return size
    }

    public var stringValue: String {
        text.stringValue
    }

    public var debugDescription: String {
        "CVLabelConfig: \(text.debugDescription)"
    }

    public var cacheKey: CacheKey {
        // textColor doesn't affect measurement.
        "\(text.cacheKey),\(font.fontName),\(font.pointSize),\(numberOfLines),\(lineBreakMode.rawValue),\(textAlignment?.rawValue ?? 0)"
    }
}

// MARK: - UITextView

public struct CVTextViewConfig {
    public typealias CacheKey = String

    public let text: CVTextValue
    public let font: UIFont
    public let textColor: UIColor
    public let textAlignment: NSTextAlignment?
    public let linkTextAttributes: [NSAttributedString.Key: Any]?

    public init(text: String,
                font: UIFont,
                textColor: UIColor,
                textAlignment: NSTextAlignment? = nil,
                linkTextAttributes: [NSAttributedString.Key: Any]? = nil) {

        self.text = .text(text: text)
        self.font = font
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.linkTextAttributes = linkTextAttributes
    }

    public init(attributedText: NSAttributedString,
                font: UIFont,
                textColor: UIColor,
                textAlignment: NSTextAlignment? = nil,
                linkTextAttributes: [NSAttributedString.Key: Any]? = nil) {

        self.text = .attributedText(attributedText: attributedText)
        self.font = font
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.linkTextAttributes = linkTextAttributes
    }

    public var stringValue: String {
        text.stringValue
    }

    public var debugDescription: String {
        "CVTextViewConfig: \(text.debugDescription)"
    }

    public var cacheKey: CacheKey {
        // textColor and linkTextAttributes (for the attributes we set)
        // don't affect measurement.
        "\(text.cacheKey),\(font.fontName),\(font.pointSize),\(textAlignment?.rawValue ?? 0)"
    }
}

// MARK: -

public class CVText {
    public typealias CacheKey = String

    public enum MeasurementMode { case view, layoutManager }

    private static var reuseLabels: Bool {
        false
    }
    public static var defaultLabelMeasurementMode: MeasurementMode {
        .layoutManager
    }

    private static var reuseTextViews: Bool {
        false
    }
    public static var defaultTextViewMeasurementMode: MeasurementMode {
        .layoutManager
    }

    private static var cacheMeasurements = true

    // MARK: - ContextState

    // We use NSTextStorage to measure text. During measurement,
    // NSTextStorage.processEditing() posts notifications to main thread
    // and in doing so blocks on the main thread.
    // Therefore it is not safe to simultaneously do measurement on two
    // threads if one of them is the main thread unless we use separate
    // UnfairLocks or we can hit deadlock. If we use separate UnfairLocks
    // we need to use separate caches.
    private class ContextState {
        let unfairLock = UnfairLock()
        let labelCache: LRUCache<CacheKey, CGSize>
        let bodyTextLabelCache: LRUCache<CacheKey, CGSize>

        init(cacheSize: Int) {
            labelCache = LRUCache<CacheKey, CGSize>(maxSize: cacheSize)
            bodyTextLabelCache = LRUCache<CacheKey, CGSize>(maxSize: cacheSize)
        }
    }
    private static let mainThreadContextState = ContextState(cacheSize: 300)
    private static let offMainThreadContextState = ContextState(cacheSize: 500)
    private static func currentContextState() -> ContextState {
        Thread.isMainThread ? mainThreadContextState : offMainThreadContextState
    }

    // MARK: - UILabel

    private static let label_main = UILabel()
    private static let label_workQueue = UILabel()
    private static var labelForMeasurement: UILabel {
        guard reuseLabels else {
            return UILabel()
        }

        if Thread.isMainThread {
            return label_main
        } else {
            return label_workQueue
        }
    }

    private static func buildCacheKey(configKey: String, maxWidth: CGFloat) -> CacheKey {
        "\(configKey),\(maxWidth)"
    }

    public static func measureLabel(mode: MeasurementMode = defaultLabelMeasurementMode,
                                    config: CVLabelConfig,
                                    maxWidth: CGFloat) -> CGSize {
        let contextState = Self.currentContextState()
        return contextState.unfairLock.withLock {
            measureLabelLocked(mode: mode, config: config, maxWidth: max(0, maxWidth), contextState: contextState)
        }
    }

    private static func measureLabelLocked(mode: MeasurementMode = defaultLabelMeasurementMode,
                                           config: CVLabelConfig,
                                           maxWidth: CGFloat,
                                           contextState: ContextState) -> CGSize {
        let labelCache = contextState.labelCache
        let cacheKey = buildCacheKey(configKey: config.cacheKey, maxWidth: maxWidth)
        if cacheMeasurements,
           let result = labelCache.get(key: cacheKey) {
            return result
        }

        let result: CGSize
        if config.text.stringValue.isEmpty {
            result = .zero
        } else {
            switch mode {
            case .layoutManager:
                result = measureLabelUsingLayoutManager(config: config, maxWidth: maxWidth)
            case .view:
                result = measureLabelUsingView(config: config, maxWidth: maxWidth)
            }
            owsAssertDebug(result.isNonEmpty)
        }

        if cacheMeasurements {
            labelCache.set(key: cacheKey, value: result.ceil)
        }

        return result.ceil
    }

    private static func measureLabelUsingView(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let label = labelForMeasurement
        config.applyForMeasurement(label: label)
        var size = label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)).ceil
        // Truncate to available space if necessary.
        size.width = min(size.width, maxWidth)
        return size
    }

    private static func measureLabelUsingLayoutManager(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        textContainer.maximumNumberOfLines = config.numberOfLines
        textContainer.lineBreakMode = config.lineBreakMode
        textContainer.lineFragmentPadding = 0
        return textContainer.size(for: config.text, font: config.font)
    }

    // MARK: - CVBodyTextLabel

    public static func measureBodyTextLabel(config: CVBodyTextLabel.Config,
                                            maxWidth: CGFloat) -> CGSize {
        let contextState = Self.currentContextState()
        return contextState.unfairLock.withLock {
            measureBodyTextLabelLocked(config: config, maxWidth: maxWidth, contextState: contextState)
        }
    }

    private static func measureBodyTextLabelLocked(config: CVBodyTextLabel.Config,
                                                   maxWidth: CGFloat,
                                                   contextState: ContextState) -> CGSize {
        let bodyTextLabelCache = contextState.bodyTextLabelCache
        let cacheKey = buildCacheKey(configKey: config.cacheKey, maxWidth: maxWidth)
        if cacheMeasurements,
           let result = bodyTextLabelCache.get(key: cacheKey) {
            return result
        }

        let result = CVBodyTextLabel.measureSize(config: config, maxWidth: maxWidth)
        owsAssertDebug(result.width > 0)
        owsAssertDebug(result.height > 0)

        if cacheMeasurements {
            bodyTextLabelCache.set(key: cacheKey, value: result.ceil)
        }

        return result.ceil
    }
}

// MARK: -

private extension NSTextContainer {
    func size(for textValue: CVTextValue, font: UIFont) -> CGSize {
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(self)

        let attributedString: NSAttributedString
        switch textValue {
        case .attributedText(let text):
            let mutableText = NSMutableAttributedString(attributedString: text)
            // The original attributed string may not have an overall font
            // assigned. Without it, measurement will not be correct. We
            // assign a font here with "add" which will not override any
            // ranges that already have a different font assigned.
            mutableText.addAttributeToEntireString(.font, value: font)
            attributedString = mutableText
        case .text(let text):
            attributedString = NSAttributedString(string: text, attributes: [.font: font])
        }

        // The string must be assigned to the NSTextStorage *after* it has
        // an associated layout manager. Otherwise, the `NSOriginalFont`
        // attribute will not be defined correctly resulting in incorrect
        // measurement of character sets that font doesn't support natively
        // (CJK, Arabic, Emoji, etc.)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        textStorage.setAttributedString(attributedString)

        // The NSTextStorage object owns all the other layout components,
        // so there are only weak references to it. In optimized builds,
        // this can result in it being freed before we perform measurement.
        // We can work around this by explicitly extending the lifetime of
        // textStorage until measurement is completed.
        let size = withExtendedLifetime(textStorage) { layoutManager.usedRect(for: self).size }

        return size.ceil
    }
}
