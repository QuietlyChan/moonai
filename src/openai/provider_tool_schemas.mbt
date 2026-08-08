///|
fn openai_empty_object_schema() -> Json {
  {
    "type": "object",
    "properties": Json::empty_object(),
    "additionalProperties": false,
  }
}

///|
fn openai_nullable_string_schema() -> Json {
  { "type": ["string", "null"] }
}

///|
fn openai_apply_patch_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "callId": { "type": "string" },
      "operation": {
        "oneOf": [
          {
            "type": "object",
            "properties": {
              "type": { "const": "create_file" },
              "path": { "type": "string" },
              "diff": { "type": "string" },
            },
            "required": ["type", "path", "diff"],
            "additionalProperties": false,
          },
          {
            "type": "object",
            "properties": {
              "type": { "const": "delete_file" },
              "path": { "type": "string" },
            },
            "required": ["type", "path"],
            "additionalProperties": false,
          },
          {
            "type": "object",
            "properties": {
              "type": { "const": "update_file" },
              "path": { "type": "string" },
              "diff": { "type": "string" },
            },
            "required": ["type", "path", "diff"],
            "additionalProperties": false,
          },
        ],
      },
    },
    "required": ["callId", "operation"],
    "additionalProperties": false,
  }
}

///|
fn openai_apply_patch_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "status": { "type": "string", "enum": ["completed", "failed"] },
      "output": { "type": "string" },
    },
    "required": ["status"],
    "additionalProperties": false,
  }
}

///|
fn openai_code_interpreter_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "code": openai_nullable_string_schema(),
      "containerId": { "type": "string" },
    },
    "required": ["containerId"],
    "additionalProperties": false,
  }
}

///|
fn openai_code_interpreter_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "outputs": {
        "anyOf": [
          {
            "type": "array",
            "items": {
              "oneOf": [
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "logs" },
                    "logs": { "type": "string" },
                  },
                  "required": ["type", "logs"],
                  "additionalProperties": false,
                },
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "image" },
                    "url": { "type": "string" },
                  },
                  "required": ["type", "url"],
                  "additionalProperties": false,
                },
              ],
            },
          },
          { "type": "null" },
        ],
      },
    },
    "additionalProperties": false,
  }
}

///|
fn openai_computer_safety_check_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "id": { "type": "string" },
      "code": { "type": "string" },
      "message": { "type": "string" },
    },
    "required": ["id"],
    "additionalProperties": false,
  }
}

///|
fn openai_computer_keys_schema() -> Json {
  { "type": "array", "items": { "type": "string" } }
}

///|
fn openai_computer_action_schema() -> Json {
  {
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "type": { "const": "click" },
          "button": {
            "type": "string",
            "enum": ["left", "right", "wheel", "back", "forward"],
          },
          "x": { "type": "number" },
          "y": { "type": "number" },
          "keys": openai_computer_keys_schema(),
        },
        "required": ["type", "button", "x", "y"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "double_click" },
          "x": { "type": "number" },
          "y": { "type": "number" },
          "keys": openai_computer_keys_schema(),
        },
        "required": ["type", "x", "y"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "drag" },
          "path": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "x": { "type": "number" },
                "y": { "type": "number" },
              },
              "required": ["x", "y"],
              "additionalProperties": false,
            },
          },
          "keys": openai_computer_keys_schema(),
        },
        "required": ["type", "path"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "keypress" },
          "keys": openai_computer_keys_schema(),
        },
        "required": ["type", "keys"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "move" },
          "x": { "type": "number" },
          "y": { "type": "number" },
          "keys": openai_computer_keys_schema(),
        },
        "required": ["type", "x", "y"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": { "type": { "const": "screenshot" } },
        "required": ["type"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "scroll" },
          "x": { "type": "number" },
          "y": { "type": "number" },
          "scrollX": { "type": "number" },
          "scrollY": { "type": "number" },
          "keys": openai_computer_keys_schema(),
        },
        "required": ["type", "x", "y", "scrollX", "scrollY"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "type" },
          "text": { "type": "string" },
        },
        "required": ["type", "text"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": { "type": { "const": "wait" } },
        "required": ["type"],
        "additionalProperties": false,
      },
    ],
  }
}

///|
fn openai_computer_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "actions": { "type": "array", "items": openai_computer_action_schema() },
      "pendingSafetyChecks": {
        "type": "array",
        "items": openai_computer_safety_check_schema(),
      },
      "status": {
        "type": "string",
        "enum": ["in_progress", "completed", "incomplete"],
      },
    },
    "required": ["actions", "pendingSafetyChecks", "status"],
    "additionalProperties": false,
  }
}

///|
fn openai_computer_screenshot_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "type": { "const": "computer_screenshot" },
      "imageUrl": { "type": "string" },
      "fileId": { "type": "string" },
      "detail": {
        "type": "string",
        "enum": ["auto", "low", "high", "original"],
      },
    },
    "required": ["type"],
    "anyOf": [{ "required": ["imageUrl"] }, { "required": ["fileId"] }],
    "additionalProperties": false,
  }
}

///|
fn openai_computer_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "output": openai_computer_screenshot_schema(),
      "acknowledgedSafetyChecks": {
        "type": "array",
        "items": openai_computer_safety_check_schema(),
      },
    },
    "required": ["output"],
    "additionalProperties": false,
  }
}

///|
fn openai_file_search_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "queries": { "type": "array", "items": { "type": "string" } },
      "results": {
        "anyOf": [
          { "type": "null" },
          {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "attributes": { "type": "object", "additionalProperties": true },
                "fileId": { "type": "string" },
                "filename": { "type": "string" },
                "score": { "type": "number" },
                "text": { "type": "string" },
              },
              "required": ["attributes", "fileId", "filename", "score", "text"],
              "additionalProperties": false,
            },
          },
        ],
      },
    },
    "required": ["queries", "results"],
    "additionalProperties": false,
  }
}

///|
fn openai_image_generation_output_schema() -> Json {
  {
    "type": "object",
    "properties": { "result": { "type": "string" } },
    "required": ["result"],
    "additionalProperties": false,
  }
}

///|
fn openai_local_shell_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "action": {
        "type": "object",
        "properties": {
          "type": { "const": "exec" },
          "command": { "type": "array", "items": { "type": "string" } },
          "timeoutMs": { "type": "number" },
          "user": { "type": "string" },
          "workingDirectory": { "type": "string" },
          "env": {
            "type": "object",
            "additionalProperties": { "type": "string" },
          },
        },
        "required": ["type", "command"],
        "additionalProperties": false,
      },
    },
    "required": ["action"],
    "additionalProperties": false,
  }
}

///|
fn openai_local_shell_output_schema() -> Json {
  {
    "type": "object",
    "properties": { "output": { "type": "string" } },
    "required": ["output"],
    "additionalProperties": false,
  }
}

///|
fn openai_shell_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "action": {
        "type": "object",
        "properties": {
          "commands": { "type": "array", "items": { "type": "string" } },
          "timeoutMs": { "type": "number" },
          "maxOutputLength": { "type": "number" },
        },
        "required": ["commands"],
        "additionalProperties": false,
      },
    },
    "required": ["action"],
    "additionalProperties": false,
  }
}

///|
fn openai_shell_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "output": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "stdout": { "type": "string" },
            "stderr": { "type": "string" },
            "outcome": {
              "oneOf": [
                {
                  "type": "object",
                  "properties": { "type": { "const": "timeout" } },
                  "required": ["type"],
                  "additionalProperties": false,
                },
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "exit" },
                    "exitCode": { "type": "number" },
                  },
                  "required": ["type", "exitCode"],
                  "additionalProperties": false,
                },
              ],
            },
          },
          "required": ["stdout", "stderr", "outcome"],
          "additionalProperties": false,
        },
      },
    },
    "required": ["output"],
    "additionalProperties": false,
  }
}

///|
fn openai_web_search_action_schema(include_queries : Bool) -> Json {
  let search_properties : Map[String, Json] = Map([
    ("type", { "const": "search" }),
    ("query", { "type": "string" }),
  ])
  if include_queries {
    search_properties["queries"] = {
      "type": "array",
      "items": { "type": "string" },
    }
  }
  {
    "oneOf": [
      {
        "type": "object",
        "properties": Json::object(search_properties),
        "required": ["type"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "openPage" },
          "url": openai_nullable_string_schema(),
        },
        "required": ["type"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "findInPage" },
          "url": openai_nullable_string_schema(),
          "pattern": openai_nullable_string_schema(),
        },
        "required": ["type"],
        "additionalProperties": false,
      },
    ],
  }
}

///|
fn openai_web_search_preview_output_schema() -> Json {
  {
    "type": "object",
    "properties": { "action": openai_web_search_action_schema(false) },
    "additionalProperties": false,
  }
}

///|
fn openai_web_search_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "action": openai_web_search_action_schema(true),
      "sources": {
        "type": "array",
        "items": {
          "oneOf": [
            {
              "type": "object",
              "properties": {
                "type": { "const": "url" },
                "url": { "type": "string" },
              },
              "required": ["type", "url"],
              "additionalProperties": false,
            },
            {
              "type": "object",
              "properties": {
                "type": { "const": "api" },
                "name": { "type": "string" },
              },
              "required": ["type", "name"],
              "additionalProperties": false,
            },
          ],
        },
      },
    },
    "additionalProperties": false,
  }
}

///|
fn openai_mcp_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "type": { "const": "call" },
      "serverLabel": { "type": "string" },
      "name": { "type": "string" },
      "arguments": { "type": "string" },
      "output": openai_nullable_string_schema(),
      "error": true,
    },
    "required": ["type", "serverLabel", "name", "arguments"],
    "additionalProperties": false,
  }
}

///|
fn openai_programmatic_tool_calling_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "code": { "type": "string" },
      "fingerprint": { "type": "string" },
    },
    "required": ["code", "fingerprint"],
    "additionalProperties": false,
  }
}

///|
fn openai_programmatic_tool_calling_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "result": { "type": "string" },
      "status": { "type": "string", "enum": ["completed", "incomplete"] },
    },
    "required": ["result", "status"],
    "additionalProperties": false,
  }
}

///|
fn openai_tool_search_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "arguments": true,
      "call_id": { "type": ["string", "null"] },
    },
    "additionalProperties": false,
  }
}

///|
fn openai_tool_search_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "tools": {
        "type": "array",
        "items": { "type": "object", "additionalProperties": true },
      },
    },
    "required": ["tools"],
    "additionalProperties": false,
  }
}
