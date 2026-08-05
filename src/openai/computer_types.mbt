///|
/// Mouse button accepted by an OpenAI computer action.
pub(all) enum OpenAIComputerButton {
  ComputerButtonLeft
  ComputerButtonRight
  ComputerButtonWheel
  ComputerButtonBack
  ComputerButtonForward
} derive(Debug, Eq)

///|
/// One point in a computer drag path.
pub(all) struct OpenAIComputerPoint {
  x : Double
  y : Double
} derive(Debug, Eq)

///|
/// Construct one computer-action point.
pub fn OpenAIComputerPoint::new(
  x~ : Double,
  y~ : Double,
) -> OpenAIComputerPoint {
  { x, y }
}

///|
/// A computer action emitted by the OpenAI computer tool.
pub(all) enum OpenAIComputerAction {
  ComputerClick(
    button~ : OpenAIComputerButton,
    x~ : Double,
    y~ : Double,
    keys~ : Array[String]?
  )
  ComputerDoubleClick(x~ : Double, y~ : Double, keys~ : Array[String]?)
  ComputerDrag(path~ : Array[OpenAIComputerPoint], keys~ : Array[String]?)
  ComputerKeypress(keys~ : Array[String])
  ComputerMove(x~ : Double, y~ : Double, keys~ : Array[String]?)
  ComputerScreenshot
  ComputerScroll(
    x~ : Double,
    y~ : Double,
    scroll_x~ : Double,
    scroll_y~ : Double,
    keys~ : Array[String]?
  )
  ComputerTypeText(String)
  ComputerWait
} derive(Debug, Eq)

///|
/// Safety check attached to a computer tool call.
pub(all) struct OpenAIComputerSafetyCheck {
  id : String
  code : String?
  message : String?
} derive(Debug, Eq)

///|
/// Construct one computer safety check.
pub fn OpenAIComputerSafetyCheck::new(
  id~ : String,
  code? : String,
  message? : String,
) -> OpenAIComputerSafetyCheck {
  { id, code, message }
}

///|
fn openai_computer_number(json : Json, field : String) -> Double raise {
  match json {
    Object(fields) =>
      match fields.get(field) {
        Some(Number(value, ..)) => value
        _ => fail("OpenAI computer action requires numeric '\{field}'")
      }
    _ => fail("OpenAI computer action must be an object")
  }
}

///|
fn openai_computer_keys(json : Json, required : Bool) -> Array[String]? raise {
  let value = match json {
    Object(fields) => fields.get("keys")
    _ => None
  }
  match value {
    Some(Array(values)) => {
      let result : Array[String] = []
      for value in values {
        match value {
          String(key) => result.push(key)
          _ => fail("OpenAI computer action keys must be strings")
        }
      }
      Some(result)
    }
    Some(Null) | None if !required => None
    _ => fail("OpenAI computer action requires a keys array")
  }
}

///|
fn openai_computer_button(value : String) -> OpenAIComputerButton raise {
  match value {
    "left" => ComputerButtonLeft
    "right" => ComputerButtonRight
    "wheel" => ComputerButtonWheel
    "back" => ComputerButtonBack
    "forward" => ComputerButtonForward
    _ => fail("Unsupported OpenAI computer mouse button '\{value}'")
  }
}

///|
fn OpenAIComputerButton::wire_name(self : OpenAIComputerButton) -> String {
  match self {
    ComputerButtonLeft => "left"
    ComputerButtonRight => "right"
    ComputerButtonWheel => "wheel"
    ComputerButtonBack => "back"
    ComputerButtonForward => "forward"
  }
}

///|
fn openai_computer_optional_keys(
  fields : Map[String, Json],
  keys : Array[String]?,
) -> Unit {
  if keys is Some(values) {
    fields["keys"] = Json::array([ for value in values => Json::string(value) ])
  }
}

///|
/// Encode a typed computer action using the public computer-tool schema.
pub fn OpenAIComputerAction::to_json(self : OpenAIComputerAction) -> Json {
  match self {
    ComputerClick(button~, x~, y~, keys~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("click")),
        ("button", Json::string(button.wire_name())),
        ("x", Json::number(x)),
        ("y", Json::number(y)),
      ])
      openai_computer_optional_keys(fields, keys)
      Json::object(fields)
    }
    ComputerDoubleClick(x~, y~, keys~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("double_click")),
        ("x", Json::number(x)),
        ("y", Json::number(y)),
      ])
      openai_computer_optional_keys(fields, keys)
      Json::object(fields)
    }
    ComputerDrag(path~, keys~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("drag")),
        (
          "path",
          Json::array([ for point in path => { "x": point.x, "y": point.y } ]),
        ),
      ])
      openai_computer_optional_keys(fields, keys)
      Json::object(fields)
    }
    ComputerKeypress(keys~) =>
      {
        "type": "keypress",
        "keys": [
          for value in keys => Json::string(value)
        ],
      }
    ComputerMove(x~, y~, keys~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("move")),
        ("x", Json::number(x)),
        ("y", Json::number(y)),
      ])
      openai_computer_optional_keys(fields, keys)
      Json::object(fields)
    }
    ComputerScreenshot => { "type": "screenshot" }
    ComputerScroll(x~, y~, scroll_x~, scroll_y~, keys~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("scroll")),
        ("x", Json::number(x)),
        ("y", Json::number(y)),
        ("scrollX", Json::number(scroll_x)),
        ("scrollY", Json::number(scroll_y)),
      ])
      openai_computer_optional_keys(fields, keys)
      Json::object(fields)
    }
    ComputerTypeText(text) => { "type": "type", "text": text }
    ComputerWait => { "type": "wait" }
  }
}

///|
/// Encode a computer safety check using the public computer-tool schema.
pub fn OpenAIComputerSafetyCheck::to_json(
  self : OpenAIComputerSafetyCheck,
) -> Json {
  let fields : Map[String, Json] = Map([("id", Json::string(self.id))])
  if self.code is Some(value) {
    fields["code"] = Json::string(value)
  }
  if self.message is Some(value) {
    fields["message"] = Json::string(value)
  }
  Json::object(fields)
}

///|
fn openai_computer_drag_path(json : Json) -> Array[OpenAIComputerPoint] raise {
  let values = match json {
    { "path": Array(values), .. } => values
    _ => fail("OpenAI computer drag action requires a path array")
  }
  let result : Array[OpenAIComputerPoint] = []
  for value in values {
    result.push(
      OpenAIComputerPoint::new(
        x=openai_computer_number(value, "x"),
        y=openai_computer_number(value, "y"),
      ),
    )
  }
  result
}

///|
/// Decode and validate one OpenAI computer action object.
pub fn decode_openai_computer_action(json : Json) -> OpenAIComputerAction raise {
  let action_type = @provider_utils.json_string_field(json, "type").unwrap_or_else(() => {
      fail("OpenAI computer action requires a type")
    },
  )
  match action_type {
    "click" => {
      let button = @provider_utils.json_string_field(json, "button").unwrap_or_else(() => {
          fail("OpenAI computer click action requires a button")
        },
      )
      ComputerClick(
        button=openai_computer_button(button),
        x=openai_computer_number(json, "x"),
        y=openai_computer_number(json, "y"),
        keys=openai_computer_keys(json, false),
      )
    }
    "double_click" =>
      ComputerDoubleClick(
        x=openai_computer_number(json, "x"),
        y=openai_computer_number(json, "y"),
        keys=openai_computer_keys(json, false),
      )
    "drag" =>
      ComputerDrag(
        path=openai_computer_drag_path(json),
        keys=openai_computer_keys(json, false),
      )
    "keypress" =>
      ComputerKeypress(keys=openai_computer_keys(json, true).unwrap())
    "move" =>
      ComputerMove(
        x=openai_computer_number(json, "x"),
        y=openai_computer_number(json, "y"),
        keys=openai_computer_keys(json, false),
      )
    "screenshot" => ComputerScreenshot
    "scroll" =>
      ComputerScroll(
        x=openai_computer_number(json, "x"),
        y=openai_computer_number(json, "y"),
        scroll_x=match json {
          Object(fields) if fields.get("scrollX") is Some(_) =>
            openai_computer_number(json, "scrollX")
          _ => openai_computer_number(json, "scroll_x")
        },
        scroll_y=match json {
          Object(fields) if fields.get("scrollY") is Some(_) =>
            openai_computer_number(json, "scrollY")
          _ => openai_computer_number(json, "scroll_y")
        },
        keys=openai_computer_keys(json, false),
      )
    "type" =>
      match @provider_utils.json_string_field(json, "text") {
        Some(text) => ComputerTypeText(text)
        None => fail("OpenAI computer type action requires text")
      }
    "wait" => ComputerWait
    _ => fail("Unsupported OpenAI computer action type '\{action_type}'")
  }
}

///|
/// Decode and validate one OpenAI computer safety check.
pub fn decode_openai_computer_safety_check(
  json : Json,
) -> OpenAIComputerSafetyCheck raise {
  let id = @provider_utils.json_string_field(json, "id").unwrap_or_else(() => {
    fail("OpenAI computer safety check requires an id")
  })
  OpenAIComputerSafetyCheck::new(
    id~,
    code?=@provider_utils.json_string_field(json, "code"),
    message?=@provider_utils.json_string_field(json, "message"),
  )
}
