///|
/// Options for running or spawning a command in a sandbox session.
pub(all) struct SandboxProcessOptions {
  command : String
  working_directory : String?
  env : Map[String, String]
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct sandbox process options.
pub fn SandboxProcessOptions::new(
  command~ : String,
  working_directory? : String,
  env? : Map[String, String] = Map([]),
  cancellation_token? : @provider.CancellationToken,
) -> SandboxProcessOptions {
  { command, working_directory, env: copy_headers(env), cancellation_token }
}

///|
/// Options for reading one file from a sandbox.
pub(all) struct SandboxReadFileOptions {
  path : String
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct sandbox file-read options.
pub fn SandboxReadFileOptions::new(
  path~ : String,
  cancellation_token? : @provider.CancellationToken,
) -> SandboxReadFileOptions {
  { path, cancellation_token }
}

///|
/// Options for reading a text file from a sandbox.
///
/// Line ranges are one-based and inclusive, matching AI SDK's sandbox
/// contract. The sandbox implementation owns encoding support.
pub(all) struct SandboxReadTextFileOptions {
  path : String
  encoding : String?
  start_line : Int?
  end_line : Int?
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct sandbox text-file read options.
pub fn SandboxReadTextFileOptions::new(
  path~ : String,
  encoding? : String,
  start_line? : Int,
  end_line? : Int,
  cancellation_token? : @provider.CancellationToken,
) -> SandboxReadTextFileOptions {
  { path, encoding, start_line, end_line, cancellation_token }
}

///|
/// Pull-based byte stream used by sandbox files and process output.
///
/// This is the MoonBit counterpart of `ReadableStream<Uint8Array>` in the
/// TypeScript AI SDK.
pub struct SandboxByteStream {
  priv read_next_callback : async () -> Bytes?
  priv cancel_callback : () -> Unit
}

///|
/// Construct a sandbox byte stream from pull and cancellation callbacks.
pub fn SandboxByteStream::new(
  read_next~ : async () -> Bytes?,
  cancel? : () -> Unit = () => (),
) -> SandboxByteStream {
  { read_next_callback: read_next, cancel_callback: cancel }
}

///|
/// Read the next byte chunk, or `None` at EOF.
pub async fn SandboxByteStream::read_next(self : SandboxByteStream) -> Bytes? {
  (self.read_next_callback)()
}

///|
/// Cancel upstream byte production.
pub fn SandboxByteStream::cancel(self : SandboxByteStream) -> Unit {
  (self.cancel_callback)()
}

///|
/// Options for writing a byte stream to a sandbox file.
pub(all) struct SandboxWriteFileOptions {
  path : String
  content : SandboxByteStream
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct streamed sandbox file-write options.
pub fn SandboxWriteFileOptions::new(
  path~ : String,
  content~ : SandboxByteStream,
  cancellation_token? : @provider.CancellationToken,
) -> SandboxWriteFileOptions {
  { path, content, cancellation_token }
}

///|
/// Options for writing buffered bytes to a sandbox file.
pub(all) struct SandboxWriteBinaryFileOptions {
  path : String
  content : Bytes
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct buffered sandbox file-write options.
pub fn SandboxWriteBinaryFileOptions::new(
  path~ : String,
  content~ : Bytes,
  cancellation_token? : @provider.CancellationToken,
) -> SandboxWriteBinaryFileOptions {
  { path, content, cancellation_token }
}

///|
/// Options for writing text to a sandbox file.
pub(all) struct SandboxWriteTextFileOptions {
  path : String
  content : String
  encoding : String?
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct sandbox text-file write options.
pub fn SandboxWriteTextFileOptions::new(
  path~ : String,
  content~ : String,
  encoding? : String,
  cancellation_token? : @provider.CancellationToken,
) -> SandboxWriteTextFileOptions {
  { path, content, encoding, cancellation_token }
}

///|
/// Result returned after a sandbox command exits.
pub(all) struct SandboxProcessResult {
  exit_code : Int
  stdout : String
  stderr : String
} derive(Debug, Eq)

///|
/// Construct a completed sandbox process result.
pub fn SandboxProcessResult::new(
  exit_code~ : Int,
  stdout? : String = "",
  stderr? : String = "",
) -> SandboxProcessResult {
  { exit_code, stdout, stderr }
}

///|
/// Convert a process result to the default provider-tool output shape.
pub fn SandboxProcessResult::to_json(self : SandboxProcessResult) -> Json {
  { "exitCode": self.exit_code, "stdout": self.stdout, "stderr": self.stderr }
}

///|
/// Exit status returned by `SandboxProcess::wait`.
pub(all) struct SandboxProcessExit {
  exit_code : Int
} derive(Debug, Eq)

///|
/// Construct a sandbox process exit status.
pub fn SandboxProcessExit::new(exit_code~ : Int) -> SandboxProcessExit {
  { exit_code, }
}

///|
/// Callback that waits for a spawned sandbox process to exit.
pub type SandboxProcessWaitFunction = async () -> SandboxProcessExit

///|
/// Callback that terminates a spawned sandbox process.
pub type SandboxProcessKillFunction = async () -> Unit

///|
/// Handle for a long-running sandbox process.
pub struct SandboxProcess {
  priv process_id : Int?
  priv stdout_stream : SandboxByteStream
  priv stderr_stream : SandboxByteStream
  priv wait_callback : SandboxProcessWaitFunction
  priv kill_callback : SandboxProcessKillFunction
}

///|
/// AI SDK name for the experimental sandbox process handle.
pub type ExperimentalSandboxProcess = SandboxProcess

///|
/// Construct a sandbox process handle.
pub fn SandboxProcess::new(
  stdout~ : SandboxByteStream,
  stderr~ : SandboxByteStream,
  wait~ : SandboxProcessWaitFunction,
  kill~ : SandboxProcessKillFunction,
  pid? : Int,
) -> SandboxProcess {
  {
    process_id: pid,
    stdout_stream: stdout,
    stderr_stream: stderr,
    wait_callback: wait,
    kill_callback: kill,
  }
}

///|
/// Return the process identifier when the sandbox exposes one.
pub fn SandboxProcess::pid(self : SandboxProcess) -> Int? {
  self.process_id
}

///|
/// Return the process standard-output stream.
pub fn SandboxProcess::stdout(self : SandboxProcess) -> SandboxByteStream {
  self.stdout_stream
}

///|
/// Return the process standard-error stream.
pub fn SandboxProcess::stderr(self : SandboxProcess) -> SandboxByteStream {
  self.stderr_stream
}

///|
/// Wait for the process to exit.
pub async fn SandboxProcess::wait(self : SandboxProcess) -> SandboxProcessExit {
  (self.wait_callback)()
}

///|
/// Terminate the process. Implementations should make this idempotent.
pub async fn SandboxProcess::kill(self : SandboxProcess) -> Unit {
  (self.kill_callback)()
}

///|
/// Callback that reads a sandbox file as a byte stream.
pub type SandboxReadFileFunction = async (SandboxReadFileOptions) -> SandboxByteStream?

///|
/// Callback that reads a sandbox file as buffered bytes.
pub type SandboxReadBinaryFileFunction = async (SandboxReadFileOptions) -> Bytes?

///|
/// Callback that reads a sandbox file as text.
pub type SandboxReadTextFileFunction = async (SandboxReadTextFileOptions) -> String?

///|
/// Callback that writes a byte stream to a sandbox file.
pub type SandboxWriteFileFunction = async (SandboxWriteFileOptions) -> Unit

///|
/// Callback that writes buffered bytes to a sandbox file.
pub type SandboxWriteBinaryFileFunction = async (SandboxWriteBinaryFileOptions) -> Unit

///|
/// Callback that writes text to a sandbox file.
pub type SandboxWriteTextFileFunction = async (SandboxWriteTextFileOptions) -> Unit

///|
/// Callback that spawns a long-running sandbox process.
pub type SandboxSpawnFunction = async (SandboxProcessOptions) -> SandboxProcess

///|
/// Callback that runs a sandbox command to completion.
pub type SandboxRunFunction = async (SandboxProcessOptions) -> SandboxProcessResult

///|
/// Injectable sandbox session used by high-level tool execution.
///
/// File and spawn callbacks are optional so command-only sandboxes can still
/// support provider tools such as Anthropic bash. Calling an unavailable
/// capability raises `UnsupportedFunctionalityError`.
pub struct SandboxSession {
  priv session_description : String
  priv read_file_callback : SandboxReadFileFunction?
  priv read_binary_file_callback : SandboxReadBinaryFileFunction?
  priv read_text_file_callback : SandboxReadTextFileFunction?
  priv write_file_callback : SandboxWriteFileFunction?
  priv write_binary_file_callback : SandboxWriteBinaryFileFunction?
  priv write_text_file_callback : SandboxWriteTextFileFunction?
  priv spawn_callback : SandboxSpawnFunction?
  priv run_callback : SandboxRunFunction
}

///|
/// AI SDK name for the experimental sandbox session contract.
pub type ExperimentalSandboxSession = SandboxSession

///|
/// Construct a sandbox session.
pub fn SandboxSession::new(
  description~ : String,
  run~ : SandboxRunFunction,
  read_file? : SandboxReadFileFunction,
  read_binary_file? : SandboxReadBinaryFileFunction,
  read_text_file? : SandboxReadTextFileFunction,
  write_file? : SandboxWriteFileFunction,
  write_binary_file? : SandboxWriteBinaryFileFunction,
  write_text_file? : SandboxWriteTextFileFunction,
  spawn? : SandboxSpawnFunction,
) -> SandboxSession {
  {
    session_description: description,
    read_file_callback: read_file,
    read_binary_file_callback: read_binary_file,
    read_text_file_callback: read_text_file,
    write_file_callback: write_file,
    write_binary_file_callback: write_binary_file,
    write_text_file_callback: write_text_file,
    spawn_callback: spawn,
    run_callback: run,
  }
}

///|
/// Describe the sandbox environment for tools and dynamic instructions.
pub fn SandboxSession::description(self : SandboxSession) -> String {
  self.session_description
}

///|
/// Read one sandbox file as a byte stream.
pub async fn SandboxSession::read_file(
  self : SandboxSession,
  options : SandboxReadFileOptions,
) -> SandboxByteStream? {
  match self.read_file_callback {
    Some(read) => read(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.readFile",
      )
  }
}

///|
/// Read one sandbox file as buffered bytes.
pub async fn SandboxSession::read_binary_file(
  self : SandboxSession,
  options : SandboxReadFileOptions,
) -> Bytes? {
  match self.read_binary_file_callback {
    Some(read) => read(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.readBinaryFile",
      )
  }
}

///|
/// Read one sandbox file as text.
pub async fn SandboxSession::read_text_file(
  self : SandboxSession,
  options : SandboxReadTextFileOptions,
) -> String? {
  match self.read_text_file_callback {
    Some(read) => read(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.readTextFile",
      )
  }
}

///|
/// Write a byte stream to one sandbox file.
pub async fn SandboxSession::write_file(
  self : SandboxSession,
  options : SandboxWriteFileOptions,
) -> Unit {
  match self.write_file_callback {
    Some(write) => write(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.writeFile",
      )
  }
}

///|
/// Write buffered bytes to one sandbox file.
pub async fn SandboxSession::write_binary_file(
  self : SandboxSession,
  options : SandboxWriteBinaryFileOptions,
) -> Unit {
  match self.write_binary_file_callback {
    Some(write) => write(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.writeBinaryFile",
      )
  }
}

///|
/// Write text to one sandbox file.
pub async fn SandboxSession::write_text_file(
  self : SandboxSession,
  options : SandboxWriteTextFileOptions,
) -> Unit {
  match self.write_text_file_callback {
    Some(write) => write(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.writeTextFile",
      )
  }
}

///|
/// Spawn a long-running sandbox process.
pub async fn SandboxSession::spawn(
  self : SandboxSession,
  options : SandboxProcessOptions,
) -> SandboxProcess {
  match self.spawn_callback {
    Some(spawn) => spawn(options)
    None =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="sandbox.spawn",
      )
  }
}

///|
/// Run one sandbox command to completion.
pub async fn SandboxSession::run(
  self : SandboxSession,
  options : SandboxProcessOptions,
) -> SandboxProcessResult {
  (self.run_callback)(options)
}
