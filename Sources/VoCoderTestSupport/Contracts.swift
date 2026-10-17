// Protocol contract suites (DESIGN §4.10): every adapter, stub and fake of a Core protocol runs
// its suite from its own tests, so all of them behave alike where the app relies on it.
import Foundation
import Testing
import VoCoderCore

/// Identity rules shared by every provider.
public enum ProviderContract {
  public static func verify(
    _ provider: any Provider, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let id = provider.id.rawValue
    #expect(!id.isEmpty, "provider id is empty", sourceLocation: sourceLocation)
    let hasWhitespace = id.contains { $0.isWhitespace }
    #expect(
      !hasWhitespace, "provider id '\(id)' contains whitespace", sourceLocation: sourceLocation)
  }
}

public enum TaskTrackerContract {
  public static func verify(
    _ tracker: any TaskTracker, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    ProviderContract.verify(tracker, sourceLocation: sourceLocation)
    #expect(
      tracker.capabilities == tracker.capabilities, "capabilities must be stable",
      sourceLocation: sourceLocation)
  }
}

public enum AttentionSourceContract {
  /// `trigger` makes `source` emit at least one item; the first one is checked.
  public static func verify(
    _ source: any AttentionSource, isolation: isolated (any Actor)? = #isolation,
    trigger: () async -> Void, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    ProviderContract.verify(source, sourceLocation: sourceLocation)
    await trigger()
    var iterator = source.items.makeAsyncIterator()
    let item = await iterator.next(isolation: isolation)
    #expect(item != nil, "no item after trigger", sourceLocation: sourceLocation)
    guard let item else { return }
    #expect(
      item.source == source.id, "item source \(item.source) isn't the source's id \(source.id)",
      sourceLocation: sourceLocation)
    #expect(!item.id.rawValue.isEmpty, "item id is empty", sourceLocation: sourceLocation)
    #expect(!item.title.isEmpty, "item title is empty", sourceLocation: sourceLocation)
    #expect(!item.spoken.isEmpty, "item spoken text is empty", sourceLocation: sourceLocation)
  }
}

public enum SecretStoreContract {
  /// Uses keys under the module id `contract-test`; leaves nothing behind.
  public static func verify(
    _ store: any SecretStore, sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let key = SecretKey(module: "contract-test", name: "token-\(UUID().uuidString)")
    defer { try? store.removeSecret(for: key) }
    #expect(try store.secret(for: key) == nil, sourceLocation: sourceLocation)
    try store.setSecret("first", for: key)
    #expect(try store.secret(for: key) == "first", sourceLocation: sourceLocation)
    try store.setSecret("second", for: key)
    #expect(try store.secret(for: key) == "second", "overwrite", sourceLocation: sourceLocation)
    try store.removeSecret(for: key)
    #expect(try store.secret(for: key) == nil, "remove", sourceLocation: sourceLocation)
    try store.removeSecret(for: key)  // removing a missing secret is not an error
  }
}

@MainActor
public enum TabContract {
  public static func verify(_ tab: any Tab, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!tab.id.rawValue.isEmpty, "tab id is empty", sourceLocation: sourceLocation)
    #expect(!tab.title.isEmpty, "tab \(tab.id) has no title", sourceLocation: sourceLocation)
    // The lifecycle the app drives: shown, hidden, shown, closed.
    tab.didActivate()
    tab.didDeactivate()
    tab.didActivate()
    tab.didDeactivate()
    tab.willClose()
  }
}

public enum LanguageModelContract {
  public static let schema = GenerationSchema(
    name: "Intent", description: "What the user wants.",
    properties: [
      .init("kind", .choice(["nextTab", "unclear"]), description: "The action."),
      .init("count", .integer, description: "How many.", optional: true),
    ])

  /// Checks the outcome rules of ADR 0003 against whatever the model currently is (available
  /// or not). Real adapters run it where the model exists; fakes run it scripted.
  public static func verify(
    _ model: any LanguageModel, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    ProviderContract.verify(model, sourceLocation: sourceLocation)
    let request = GenerationRequest(
      instructions: "Map the request to an intent.", prompt: "go to the next tab",
      timeout: .seconds(5), maxResponseTokens: 50)
    await model.prewarm()
    let available = await model.availability() == .available
    let clock = ContinuousClock()
    let start = clock.now

    let guided = await model.generate(request, schema: schema)
    if !available {
      #expect(guided == .noParse(.unavailable), sourceLocation: sourceLocation)
    } else if !model.capabilities.contains(.guidedGeneration) {
      #expect(guided == .noParse(.unsupported), sourceLocation: sourceLocation)
    } else if let content = guided.value {
      #expect(
        schema.validates(content), "output \(content) doesn't match the schema",
        sourceLocation: sourceLocation)
    }

    let text = await model.respond(to: request)
    if !available {
      #expect(text == .noParse(.unavailable), sourceLocation: sourceLocation)
    }
    #expect(
      clock.now - start < request.timeout * 2 + .milliseconds(500),
      "calls must honour the timeout", sourceLocation: sourceLocation)

    let tokens = await model.tokenCount(for: "go to the next tab")
    #expect(
      (tokens != nil) == model.capabilities.contains(.tokenCounting),
      "tokenCount must be non-nil exactly with .tokenCounting", sourceLocation: sourceLocation)
  }
}
