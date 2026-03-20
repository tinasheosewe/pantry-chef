import Foundation

public enum ServerEventDecoder {
	private static let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		return decoder
	}()

	public static func decode(from data: Data) throws -> ServerEvent {
		let normalizedData = try normalize(data)
		return try decoder.decode(ServerEvent.self, from: normalizedData)
	}

	private static func normalize(_ data: Data) throws -> Data {
		guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return data
		}

		switch payload["type"] as? String {
			case "output_audio_buffer.cleared":
				payload["type"] = "input_audio_buffer.cleared"
			case "conversation.item.input_audio_transcription.completed":
				if payload["event_id"] == nil,
				   let itemId = payload["item_id"] as? String,
				   let contentIndex = payload["content_index"] {
					payload["event_id"] = "compat-transcription:\(itemId):\(contentIndex)"
				}
			default:
				break
		}

		return try JSONSerialization.data(withJSONObject: payload)
	}
}