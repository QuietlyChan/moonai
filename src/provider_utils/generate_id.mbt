///|
/// Function that generates a provider-neutral identifier.
///
/// This mirrors AI SDK's `IdGenerator` contract. Generated identifiers are
/// intentionally non-cryptographic and are suitable for stream part,
/// citation, and fallback tool-call identities.
pub type IdGenerator = () -> String

///|
const DEFAULT_ID_ALPHABET : String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

///|
/// Create a non-cryptographic identifier generator.
///
/// `size` controls the random portion of the identifier. When `prefix` is
/// supplied, the returned value is `prefix + separator + random`; the
/// separator must not occur in `alphabet` so the prefix remains unambiguous.
///
/// This is the MoonBit counterpart of AI SDK's `createIdGenerator`.
pub fn create_id_generator(
  prefix? : String,
  separator? : String = "-",
  size? : Int = 16,
  alphabet? : String = DEFAULT_ID_ALPHABET,
) -> IdGenerator raise @provider.InvalidArgumentError {
  guard size >= 0 else {
    raise @provider.InvalidArgumentError(
      argument="size",
      message="The ID size must be non-negative.",
    )
  }
  let alphabet_chars = alphabet.to_array()
  guard alphabet_chars.length() > 0 else {
    raise @provider.InvalidArgumentError(
      argument="alphabet",
      message="The ID alphabet must not be empty.",
    )
  }
  match prefix {
    Some(_) if alphabet.contains(separator) =>
      raise @provider.InvalidArgumentError(
        argument="separator",
        message="The separator \"\{separator}\" must not be part of the alphabet \"\{alphabet}\".",
      )
    _ => ()
  }
  let random = @random.Rand::new()
  let generator : IdGenerator = () => {
    let result = StringBuilder::new(size_hint=size)
    for _ in 0..<size {
      result.write_object(
        alphabet_chars[random.int(limit=alphabet_chars.length())],
      )
    }
    let value = result.to_string()
    match prefix {
      Some(prefix) => prefix + separator + value
      None => value
    }
  }
  generator
}

///|
/// Generate a default 16-character non-cryptographic identifier.
///
/// This is the MoonBit counterpart of AI SDK's `generateId`.
pub fn generate_id() -> String {
  default_id_generator()
}

///|
/// AI SDK-style camel-case spelling for `create_id_generator`.
pub fn createIdGenerator(
  prefix? : String,
  separator? : String = "-",
  size? : Int = 16,
  alphabet? : String = DEFAULT_ID_ALPHABET,
) -> IdGenerator raise @provider.InvalidArgumentError {
  create_id_generator(prefix?, separator~, size~, alphabet~)
}

///|
/// AI SDK-style camel-case spelling for `generate_id`.
pub fn generateId() -> String {
  generate_id()
}

///|
fn make_default_id_generator() -> IdGenerator {
  let alphabet_chars = DEFAULT_ID_ALPHABET.to_array()
  let random = @random.Rand::new()
  () => {
    let result = StringBuilder::new(size_hint=16)
    for _ in 0..<16 {
      result.write_object(
        alphabet_chars[random.int(limit=alphabet_chars.length())],
      )
    }
    result.to_string()
  }
}

///|
let default_id_generator : IdGenerator = make_default_id_generator()
