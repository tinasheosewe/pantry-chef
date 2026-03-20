import XCTest
import RealtimeAPI

@MainActor
final class RealtimeConversationFunctionCallEventTests: XCTestCase {

    func testInputAudioTranscriptionDeltaAppendsLiveUserTranscript() throws {
        let conversation = Conversation()

        try conversation._applyServerEventForTesting(
            .conversationItemAdded(
                eventId: "event_user_1",
                item: .message(
                    .init(
                        id: "user_item_1",
                        status: .inProgress,
                        role: .user,
                        content: [
                            .inputAudio(
                                .init(
                                    audio: Optional<Data>.none,
                                    transcript: Optional<String>.none
                                )
                            )
                        ]
                    )
                ),
                previousItemId: nil
            )
        )

        try conversation._applyServerEventForTesting(
            .conversationItemInputAudioTranscriptionDelta(
                eventId: "event_user_2",
                itemId: "user_item_1",
                contentIndex: 0,
                delta: "hel",
                logprobs: nil
            )
        )

        try conversation._applyServerEventForTesting(
            .conversationItemInputAudioTranscriptionDelta(
                eventId: "event_user_3",
                itemId: "user_item_1",
                contentIndex: 0,
                delta: "lo",
                logprobs: nil
            )
        )

        guard case let .message(message)? = conversation._entriesForTesting.first,
              case let .inputAudio(audio) = message.content[0] else {
            return XCTFail("Expected a user message with input audio content")
        }

        XCTAssertEqual(audio.transcript, "hello")
    }

    func testConversationItemAddedUpsertsExistingAssistantMessage() throws {
        let conversation = Conversation()
        let assistantMessage = Item.Message(
            id: "assistant_item_1",
            status: .inProgress,
            role: .assistant,
            content: []
        )

        try conversation._applyServerEventForTesting(
            .responseOutputItemAdded(
                eventId: "event_assistant_1",
                responseId: "response_1",
                outputIndex: 0,
                item: .message(assistantMessage)
            )
        )

        try conversation._applyServerEventForTesting(
            .conversationItemAdded(
                eventId: "event_assistant_2",
                item: .message(assistantMessage),
                previousItemId: nil
            )
        )

        XCTAssertEqual(conversation._entriesForTesting.count, 1)
    }

    func testResponseOutputItemAddedStoresFunctionCallEntry() throws {
        let conversation = Conversation()
        let functionCall = Item.FunctionCall(
            id: "fc_item_1",
            status: .inProgress,
            callId: "call_1",
            name: "next_step",
            arguments: ""
        )

        try conversation._applyServerEventForTesting(
            .responseOutputItemAdded(
                eventId: "event_1",
                responseId: "resp_1",
                outputIndex: 0,
                item: .functionCall(functionCall)
            )
        )

        XCTAssertEqual(conversation._entriesForTesting.count, 1)

        guard case let .functionCall(stored)? = conversation._entriesForTesting.first else {
            return XCTFail("Expected a function call entry")
        }

        XCTAssertEqual(stored.id, "fc_item_1")
        XCTAssertEqual(stored.callId, "call_1")
        XCTAssertEqual(stored.name, "next_step")
        XCTAssertEqual(stored.status, .inProgress)
    }

    func testResponseOutputItemDoneReplacesFunctionCallWithCompletedItem() throws {
        let conversation = Conversation()

        try conversation._applyServerEventForTesting(
            .responseOutputItemAdded(
                eventId: "event_2",
                responseId: "resp_2",
                outputIndex: 0,
                item: .functionCall(
                    .init(
                        id: "fc_item_2",
                        status: .inProgress,
                        callId: "call_2",
                        name: "go_to_step",
                        arguments: ""
                    )
                )
            )
        )

        try conversation._applyServerEventForTesting(
            .responseFunctionCallArgumentsDone(
                eventId: "event_3",
                responseId: "resp_2",
                itemId: "fc_item_2",
                outputIndex: 0,
                callId: "call_2",
                arguments: "{\"step_number\":5}"
            )
        )

        try conversation._applyServerEventForTesting(
            .responseOutputItemDone(
                eventId: "event_4",
                responseId: "resp_2",
                outputIndex: 0,
                item: .functionCall(
                    .init(
                        id: "fc_item_2",
                        status: .completed,
                        callId: "call_2",
                        name: "go_to_step",
                        arguments: "{\"step_number\":5}"
                    )
                )
            )
        )

        XCTAssertEqual(conversation._entriesForTesting.count, 1)

        guard case let .functionCall(stored)? = conversation._entriesForTesting.first else {
            return XCTFail("Expected a function call entry")
        }

        XCTAssertEqual(stored.status, .completed)
        XCTAssertEqual(stored.name, "go_to_step")
        XCTAssertEqual(stored.arguments, "{\"step_number\":5}")
    }
}