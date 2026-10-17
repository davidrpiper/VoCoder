import Testing
import VoCoderFakes

@testable import VoCoderCore

@Suite struct LanguageModelTests {
  let schema = GenerationSchema(
    name: "Intent", description: "",
    properties: [
      .init("kind", .choice(["approve", "unclear"]), description: ""),
      .init("issue", .string, description: "", optional: true),
      .init("count", .integer, description: "", optional: true),
    ])
  let request = GenerationRequest(instructions: "i", prompt: "approve it", timeout: .seconds(2))

  @Test func schemaValidation() {
    #expect(schema.validates(GeneratedContent(["kind": .string("approve")])))
    #expect(
      schema.validates(
        GeneratedContent([
          "kind": .string("unclear"), "issue": .string("ENG-1"), "count": .integer(2),
        ])))
    #expect(!schema.validates(GeneratedContent([:])), "missing required")
    #expect(!schema.validates(GeneratedContent(["kind": .string("merge")])), "not a choice")
    #expect(!schema.validates(GeneratedContent(["kind": .integer(1)])), "wrong type")
    #expect(
      !schema.validates(GeneratedContent(["kind": .string("approve"), "count": .string("2")])))
    #expect(
      !schema.validates(GeneratedContent(["kind": .string("approve"), "extra": .integer(1)])),
      "unknown property")
  }

  @Test func fakeFillsTheSchemaWhenNothingIsScripted() async {
    let model = FakeLanguageModel()
    let outcome = await model.generate(request, schema: schema)
    #expect(outcome == .output(GeneratedContent(["kind": .string("approve")])))
    #expect(await model.respond(to: request) == .output("Fake response."))
    #expect(model.requests == [request, request])
  }

  @Test func fakeReturnsScriptedOutcomesInOrder() async {
    let model = FakeLanguageModel()
    let content = GeneratedContent(["kind": .string("unclear"), "issue": .string("ENG-7")])
    model.enqueue(.output(content))
    model.enqueue(.noParse(.guardrail))
    model.enqueue(.output(GeneratedContent(["kind": .string("explode")])))
    #expect(await model.generate(request, schema: schema) == .output(content))
    #expect(await model.generate(request, schema: schema) == .noParse(.guardrail))
    #expect(
      await model.generate(request, schema: schema) == .noParse(.decodingFailure),
      "output outside the schema")
  }

  @Test func unavailableModelReturnsNoParse() async {
    let model = FakeLanguageModel(availability: .unavailable("Apple Intelligence is off"))
    #expect(await model.availability() == .unavailable("Apple Intelligence is off"))
    #expect(await model.generate(request, schema: schema) == .noParse(.unavailable))
    #expect(await model.respond(to: request) == .noParse(.unavailable))
  }

  @Test func slowCallsTimeOut() async {
    let model = FakeLanguageModel()
    model.setDelay(.seconds(10))
    var quick = request
    quick.timeout = .milliseconds(50)
    let start = ContinuousClock.now
    #expect(await model.generate(quick, schema: schema) == .noParse(.timeout))
    #expect(await model.respond(to: quick) == .noParse(.timeout))
    #expect(ContinuousClock.now - start < .seconds(2))
  }

  @Test func capabilitiesGateGuidedGenerationAndTokenCounts() async {
    let model = FakeLanguageModel(capabilities: [])
    #expect(await model.generate(request, schema: schema) == .noParse(.unsupported))
    #expect(await model.tokenCount(for: "hello") == nil)
    #expect(await FakeLanguageModel().tokenCount(for: "12345678") == 2)
  }

  @Test func prewarmIsCounted() async {
    let model = FakeLanguageModel()
    await model.prewarm()
    await model.prewarm()
    #expect(model.prewarmCount == 2)
  }

  @Test func timeoutHelperPassesFastResultsThrough() async {
    let outcome = await withGenerationTimeout(.seconds(5)) { .output(42) }
    #expect(outcome == .output(42))
  }
}
