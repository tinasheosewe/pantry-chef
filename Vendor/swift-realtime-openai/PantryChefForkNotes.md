# PantryChef fork notes

- Added `ServerEventDecoder` to normalize known OpenAI Realtime payload drift before decoding.
- `output_audio_buffer.cleared` is mapped onto the existing SDK `inputAudioBufferCleared` case because upstream currently lacks a dedicated server event case.
- `conversation.item.input_audio_transcription.completed` payloads missing `event_id` receive a deterministic compatibility ID so the event stream does not terminate.
- `WebRTCConnector` now decodes through `ServerEventDecoder` and keeps the stream alive on decode failures.
- `Response.Usage` already tolerates sparse `input_token_details` and absent `output_token_details` in this vendored copy.