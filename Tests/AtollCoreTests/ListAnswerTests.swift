import Foundation
import Testing
@testable import AtollCore

@Suite("List answers: the key an answer sends")
struct ListAnswerKeyTests {
    let rice = QuestionChoices.Option(label: "飯", detail: "便當或燴飯", key: "2")

    @Test("Allow / Deny send the keys read off the permission dialog")
    func permission() {
        var agent = Agent(address: "t1", tool: .claudeCode)
        agent.permissionChoices = PermissionChoices(allowKey: "1", denyKey: "esc")
        #expect(agent.key(for: .allow) == "1")
        #expect(agent.key(for: .deny) == "esc")
        #expect(agent.key(for: .option(rice)) == nil)
    }

    @Test("a question option sends its number, only while this episode's question still offers it")
    func option() {
        var agent = Agent(address: "t1", tool: .claudeCode)
        agent.questionChoices = QuestionChoices(options: [
            QuestionChoices.Option(label: "麵", key: "1"), rice,
        ])
        #expect(agent.key(for: .option(rice)) == "2")
        #expect(agent.key(for: .option(QuestionChoices.Option(label: "粥", key: "3"))) == nil)
        #expect(agent.key(for: .allow) == nil)
    }

    @Test("nothing read off the screen: no key for any answer")
    func nothingRead() {
        let agent = Agent(address: "t1", tool: .claudeCode)
        #expect(agent.key(for: .allow) == nil)
        #expect(agent.key(for: .option(rice)) == nil)
    }
}
