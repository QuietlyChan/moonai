///|
/// Copy a JSON object field map without sharing mutable storage.
fn moonshot_copy_object(fields : Map[String, Json]) -> Map[String, Json] {
  let copy : Map[String, Json] = Map([])
  for entry in fields.iter2() {
    copy[entry.0] = entry.1
  }
  copy
}

///|
fn moonshot_is_object(value : Json) -> Bool {
  value is Object(_)
}

///|
fn moonshot_mfjs_not_supported() -> @provider.UnsupportedFunctionalityError {
  @provider.UnsupportedFunctionalityError(
    functionality="tool parameters must be a JSON Schema object with type \"object\" for moonshotai (MFJS)",
  )
}

///|
/// Normalize a JSON Schema to the subset Moonshot's MFJS validator accepts:
/// `object` root required, tuple `items` become `prefixItems`, and `type`
/// next to `anyOf` moves into the branches. Everything else passes through.
/// The full original schema is still used for result validation.
fn normalize_json_schema_for_mfjs(schema : Json) -> Json raise {
  normalize_mfjs_definition(schema, is_root=true)
}

///|
fn normalize_mfjs_definition(definition : Json, is_root~ : Bool) -> Json raise {
  match definition {
    Object(fields) => {
      if is_root {
        guard fields.get("type") is Some(String("object")) else {
          raise moonshot_mfjs_not_supported()
        }
      }
      let result = moonshot_copy_object(fields)
      // Tuple `items` become positional `prefixItems`; schema `items`
      // normalize recursively.
      match result.get("items") {
        Some(Array(items)) => {
          let prefix_items : Array[Json] = match result.get("prefixItems") {
            Some(Array(existing)) => existing.copy()
            _ => []
          }
          for item in items {
            prefix_items.push(normalize_mfjs_definition(item, is_root=false))
          }
          result["prefixItems"] = Json::array(prefix_items)
          result.remove("items")
        }
        Some(value) if moonshot_is_object(value) =>
          result["items"] = normalize_mfjs_definition(value, is_root=false)
        _ => ()
      }
      // MFJS requires `type` to live inside `anyOf` branches.
      match (result.get("type"), result.get("anyOf")) {
        (Some(String(parent_type)), Some(Array(branches))) => {
          result.remove("type")
          let mapped : Array[Json] = []
          for branch in branches {
            match branch {
              Object(branch_fields) if branch_fields.get("type") is None => {
                let copy = moonshot_copy_object(branch_fields)
                copy["type"] = Json::string(parent_type)
                mapped.push(Json::object(copy))
              }
              other => mapped.push(other)
            }
          }
          result["anyOf"] = Json::array(mapped)
        }
        _ => ()
      }
      for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        match result.get(key) {
          Some(Array(values)) => {
            let normalized : Array[Json] = []
            for value in values {
              normalized.push(normalize_mfjs_definition(value, is_root=false))
            }
            result[key] = Json::array(normalized)
          }
          _ => ()
        }
      }
      for
        key in ["properties", "patternProperties", "$defs", "dependentSchemas"] {
        match result.get(key) {
          Some(Object(values)) => {
            let normalized : Map[String, Json] = Map([])
            for entry in values.iter2() {
              normalized[entry.0] = normalize_mfjs_definition(
                entry.1,
                is_root=false,
              )
            }
            result[key] = Json::object(normalized)
          }
          _ => ()
        }
      }
      for
        key in [
          "additionalProperties", "propertyNames", "items", "contains", "not", "if",
          "then", "else",
        ] {
        match result.get(key) {
          Some(value) if moonshot_is_object(value) =>
            result[key] = normalize_mfjs_definition(value, is_root=false)
          _ => ()
        }
      }
      Json::object(result)
    }
    _ if is_root => raise moonshot_mfjs_not_supported()
    _ => definition
  }
}

///|
/// Strip the AI SDK's injected top-level `$schema` keyword, which makes
/// Kimi K2.5 produce nonsensical output even though it otherwise supports
/// structured outputs. The full original schema is still used for result
/// validation.
fn moonshot_schema_without_dollar_keyword(schema : Json) -> Json {
  match schema {
    Object(fields) if fields.contains("$schema") => {
      let copy = moonshot_copy_object(fields)
      copy.remove("$schema")
      Json::object(copy)
    }
    other => other
  }
}
