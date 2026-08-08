///|
test "decode every OpenAI computer action family" {
  assert_true(
    decode_openai_computer_action({
      "type": "click",
      "button": "left",
      "x": 10,
      "y": 20,
    })
    is ComputerClick(button=ComputerButtonLeft, x=10.0, y=20.0, ..),
  )
  assert_true(
    decode_openai_computer_action({
      "type": "drag",
      "path": [{ "x": 1, "y": 2 }, { "x": 3, "y": 4 }],
      "keys": ["SHIFT"],
    })
    is ComputerDrag(
      path=[{ x: 1.0, y: 2.0 }, { x: 3.0, y: 4.0 }],
      keys=Some(["SHIFT"])
    ),
  )
  assert_true(
    decode_openai_computer_action({
      "type": "scroll",
      "x": 5,
      "y": 6,
      "scrollX": -2,
      "scrollY": 8,
    })
    is ComputerScroll(x=5.0, y=6.0, scroll_x=-2.0, scroll_y=8.0, ..),
  )
  assert_true(
    decode_openai_computer_action({ "type": "keypress", "keys": ["CTRL", "L"] })
    is ComputerKeypress(keys=["CTRL", "L"]),
  )
  assert_true(
    decode_openai_computer_action({ "type": "screenshot" })
    is ComputerScreenshot,
  )
  assert_true(decode_openai_computer_action({ "type": "wait" }) is ComputerWait)
}

///|
test "decode OpenAI computer safety checks and reject malformed actions" {
  assert_eq(
    decode_openai_computer_safety_check({
      "id": "check-1",
      "code": "policy",
      "message": "Review",
    }),
    OpenAIComputerSafetyCheck::new(
      id="check-1",
      code="policy",
      message="Review",
    ),
  )
  try
    decode_openai_computer_action({
      "type": "click",
      "button": "middle",
      "x": 0,
      "y": 0,
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("expected an unsupported mouse button error")
  }
}
