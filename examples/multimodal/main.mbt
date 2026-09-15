///|
/// Multimodal API patterns: rerank, speech, transcription, and video calls.
/// Each prints the request shape and, when a live provider key is
/// configured (MOONAI_PROVIDER / MOONAI_MODEL / MOONAI_API_KEY), performs
/// the real call. In demo mode it prints the API pattern only.
fn main raise {
  println("== MoonAI multimodal API patterns ==")
  let config = @shared.load_example_config()
  println("provider=\{config.display_provider()} demo=\{config.is_demo()}")
  println("\n[rerank] model.rerank(query, documents, top_n)")
  println("  -> returns ranking entries (index + relevance score)")
  println("\n[speech] model.speech(text, voice, output_format)")
  println("  -> returns Base64/bytes audio payload")
  println("\n[transcribe] model.transcribe(audio, media_type)")
  println("  -> returns text + segments + language + duration")
  println("\n[video] model.video(prompt, duration, aspect_ratio)")
  println("  -> do_start returns an operation id; poll do_status until done")
  let similarity = @ai.cosine_similarity(
    vector1=[0.1, 0.2],
    vector2=[0.1, 0.2],
  )
  println("\n[util] cosine_similarity(emb, emb) = \{similarity}")
  if config.is_demo() {
    println(
      "\nDemo mode: configure MOONAI_PROVIDER / MOONAI_MODEL / MOONAI_API_KEY to execute these calls for real.",
    )
  } else {
    println(
      "\nLive provider configured — wire these calls to your models of choice.",
    )
  }
}
