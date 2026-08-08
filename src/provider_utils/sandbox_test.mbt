///|
async test "sandbox session exposes command file and process boundaries" {
  let commands : Array[SandboxProcessOptions] = []
  let writes : Array[SandboxWriteTextFileOptions] = []
  let stdout_chunks = [b"one", b"two"]
  let stdout_index = Ref(0)
  let stdout = SandboxByteStream::new(read_next=() => {
    if stdout_index.val >= stdout_chunks.length() {
      None
    } else {
      let value = stdout_chunks[stdout_index.val]
      stdout_index.val = stdout_index.val + 1
      Some(value)
    }
  })
  let stderr = SandboxByteStream::new(read_next=() => None)
  let session = SandboxSession::new(
    description="MoonBit test sandbox",
    run=options => {
      commands.push(options)
      SandboxProcessResult::new(exit_code=0, stdout="ok", stderr="")
    },
    read_binary_file=options => {
      assert_eq(options.path, "/workspace/input.txt")
      Some(b"input")
    },
    write_text_file=options => writes.push(options),
    spawn=options => {
      commands.push(options)
      SandboxProcess::new(
        pid=42,
        stdout~,
        stderr~,
        wait=() => SandboxProcessExit::new(exit_code=7),
        kill=() => (),
      )
    },
  )
  assert_eq(session.description(), "MoonBit test sandbox")
  let result = session.run(
    SandboxProcessOptions::new(command="pwd", working_directory="/workspace", env={
      "MODE": "test",
    }),
  )
  assert_eq(result.to_json(), { "exitCode": 0, "stdout": "ok", "stderr": "" })
  assert_eq(commands[0].command, "pwd")
  assert_eq(commands[0].working_directory, Some("/workspace"))
  assert_eq(commands[0].env, { "MODE": "test" })
  assert_eq(
    session.read_binary_file(
      SandboxReadFileOptions::new(path="/workspace/input.txt"),
    ),
    Some(b"input"),
  )
  session.write_text_file(
    SandboxWriteTextFileOptions::new(
      path="/workspace/output.txt",
      content="output",
      encoding="utf-8",
    ),
  )
  assert_eq(writes.length(), 1)
  assert_eq(writes[0].content, "output")
  let process = session.spawn(SandboxProcessOptions::new(command="watch"))
  assert_eq(process.pid(), Some(42))
  assert_eq(process.stdout().read_next(), Some(b"one"))
  assert_eq(process.stdout().read_next(), Some(b"two"))
  assert_eq(process.stdout().read_next(), None)
  assert_eq(process.stderr().read_next(), None)
  assert_eq(process.wait(), SandboxProcessExit::new(exit_code=7))
  process.kill()
}

///|
async test "command-only sandbox reports unavailable optional capabilities" {
  let session = SandboxSession::new(description="command only", run=_ => {
    SandboxProcessResult::new(exit_code=0)
  })
  ignore(
    session.read_text_file(SandboxReadTextFileOptions::new(path="missing.txt")),
  ) catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_eq(functionality, "sandbox.readTextFile")
    _ => fail("expected unsupported sandbox readTextFile capability")
  }
}

///|
test "sandbox text range options pass through to the implementation" {
  let options = SandboxReadTextFileOptions::new(
    path="input",
    encoding="utf-8",
    start_line=4,
    end_line=8,
  )
  assert_eq(options.path, "input")
  assert_eq(options.encoding, Some("utf-8"))
  assert_eq(options.start_line, Some(4))
  assert_eq(options.end_line, Some(8))
}
