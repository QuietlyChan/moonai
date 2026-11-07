///|
/// Calculate the cosine similarity between two vectors — a useful metric
/// for comparing the similarity of two embeddings. Returns 0 when either
/// vector is the zero vector.
///
/// Raises `InvalidArgumentError` when the vectors have different lengths.
pub fn cosine_similarity(
  vector1~ : Array[Double],
  vector2~ : Array[Double],
) -> Double raise InvalidArgumentError {
  guard vector1.length() == vector2.length() else {
    raise invalid_argument(
      parameter="vector1,vector2",
      value=Json::object(
        Map([
          ("vector1Length", Json::number(vector1.length().to_double())),
          ("vector2Length", Json::number(vector2.length().to_double())),
        ]),
      ),
      message="Vectors must have the same length",
    )
  }
  let n = vector1.length()
  if n == 0 {
    return 0.0
  }
  let mut magnitude_squared1 = 0.0
  let mut magnitude_squared2 = 0.0
  let mut dot_product = 0.0
  for i = 0; i < n; i = i + 1 {
    let value1 = vector1[i]
    let value2 = vector2[i]
    magnitude_squared1 = magnitude_squared1 + value1 * value1
    magnitude_squared2 = magnitude_squared2 + value2 * value2
    dot_product = dot_product + value1 * value2
  }
  if magnitude_squared1 == 0.0 || magnitude_squared2 == 0.0 {
    0.0
  } else {
    dot_product /
    (double_sqrt(magnitude_squared1) * double_sqrt(magnitude_squared2))
  }
}

///|
/// Square root via Newton iterations (no libm dependency in this target).
fn double_sqrt(value : Double) -> Double {
  if value <= 0.0 {
    return 0.0
  }
  let mut guess = value
  let mut previous = 0.0
  while guess != previous {
    previous = guess
    guess = (guess + value / guess) / 2.0
  }
  guess
}

///|
/// Split an array into chunks of the specified size (upstream `splitArray`).
/// Raises `InvalidArgumentError` when the chunk size is not positive.
pub fn split_array(
  array~ : Array[String],
  chunk_size~ : Int32,
) -> Array[Array[String]] raise InvalidArgumentError {
  guard chunk_size > 0 else {
    raise invalid_argument(
      parameter="chunkSize",
      value=Json::number(chunk_size.to_double()),
      message="chunkSize must be greater than 0",
    )
  }
  let result : Array[Array[String]] = []
  let mut current : Array[String] = []
  for value in array {
    current.push(value)
    if current.length() == chunk_size {
      result.push(current)
      current = []
    }
  }
  if current.length() > 0 {
    result.push(current)
  }
  result
}
