///|
/// Output strategy for streaming and generation calls, mirroring AI SDK's
/// composable `Output` API.
///
/// - `OutputText` (default): the model returns plain text.
/// - `OutputObject`: the model returns one JSON object matching `schema`.
/// - `OutputArray`: the model returns a JSON array whose items match
///   `item_schema`, optionally clamped by `min_items`/`max_items`
///   (AI SDK #20270).
pub(all) enum OutputSpec {
  OutputText
  OutputObject(schema~ : Json, name~ : String?, description~ : String?)
  OutputArray(
    item_schema~ : Json,
    name~ : String?,
    description~ : String?,
    min_items~ : Int?,
    max_items~ : Int?
  )
} derive(Debug)

///|
/// Plain text output strategy.
pub fn OutputSpec::text() -> OutputSpec {
  OutputText
}

///|
/// Object output strategy for one JSON object matching the schema.
pub fn OutputSpec::object(
  schema~ : Json,
  name? : String,
  description? : String,
) -> OutputSpec {
  OutputObject(schema~, name~, description~)
}

///|
/// Array output strategy for a JSON array of items matching the schema.
pub fn OutputSpec::array(
  item_schema~ : Json,
  name? : String,
  description? : String,
  min_items? : Int,
  max_items? : Int,
) -> OutputSpec {
  OutputArray(item_schema~, name~, description~, min_items~, max_items~)
}

///|
/// Resolve the response format for an output strategy.
///
/// Text maps to the plain text response format; object and array strategies
/// map to a JSON response format whose schema constrains the shape. The
/// array strategy wraps the item schema in an `elements` object, matching
/// AI SDK's element-array composition.
pub fn OutputSpec::response_format(
  self : OutputSpec,
  strict_json_schema~ : Bool,
) -> @provider.ResponseFormat {
  ignore(strict_json_schema)
  match self {
    OutputText => @provider.Text
    OutputObject(schema~, name~, description~) =>
      @provider.ResponseFormat::json(schema~, name?, description?)
    OutputArray(item_schema~, name~, description~, min_items~, max_items~) => {
      let items : Map[String, Json] = Map([
        ("type", Json::string("array")),
        ("items", item_schema),
      ])
      if min_items is Some(min) {
        items["minItems"] = Json::number(min.to_double())
      }
      if max_items is Some(max) {
        items["maxItems"] = Json::number(max.to_double())
      }
      let array_schema : Json = {
        "type": "object",
        "properties": { "elements": Json::object(items) },
        "required": ["elements"],
        "additionalProperties": false,
      }
      @provider.ResponseFormat::json(schema=array_schema, name?, description?)
    }
  }
}

///|
/// Extract the `elements` array from a (possibly partial) array-output
/// wrapper value. Returns an empty array when the value is not an object
/// with an elements array.
pub fn OutputSpec::array_elements(value : Json) -> Array[Json] {
  match value {
    { "elements": Array(items), .. } => items
    _ => []
  }
}
