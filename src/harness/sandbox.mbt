///|
/// Outbound network policy applied to a harness sandbox.
pub(all) enum HarnessV1NetworkPolicy {
  HarnessNetworkAllowAll
  HarnessNetworkDenyAll
  HarnessNetworkCustom(
    allowed_hosts~ : Array[String],
    allowed_cidrs~ : Array[String],
    denied_cidrs~ : Array[String]
  )
} derive(Debug, Eq)

///|
/// Network-capable sandbox session used by harness adapters.
pub struct HarnessV1NetworkSandboxSession {
  priv sandbox_id : String
  priv default_working_directory_value : String
  priv exposed_ports : Ref[Array[Int]]
  priv restricted_session : @provider_utils.SandboxSession
  priv get_port_url_callback : async (Int, String?) -> String
  priv stop_callback : async () -> Unit
  priv destroy_callback : async () -> Unit
  priv set_network_policy_callback : async (HarnessV1NetworkPolicy) -> Unit
  priv set_ports_callback : async (Array[Int], @provider.CancellationToken?) -> Unit
}

///|
/// Construct a network sandbox around the provider-utils sandbox contract.
pub fn HarnessV1NetworkSandboxSession::new(
  id~ : String,
  default_working_directory~ : String,
  restricted~ : @provider_utils.SandboxSession,
  get_port_url~ : async (Int, String?) -> String,
  stop~ : async () -> Unit,
  ports? : Array[Int] = [],
  destroy? : async () -> Unit = () => (),
  set_network_policy? : async (HarnessV1NetworkPolicy) -> Unit = _ => (),
  set_ports? : async (Array[Int], @provider.CancellationToken?) -> Unit = (_, _) => {
    ()
  },
) -> HarnessV1NetworkSandboxSession {
  {
    sandbox_id: id,
    default_working_directory_value: default_working_directory,
    exposed_ports: Ref(ports.copy()),
    restricted_session: restricted,
    get_port_url_callback: get_port_url,
    stop_callback: stop,
    destroy_callback: destroy,
    set_network_policy_callback: set_network_policy,
    set_ports_callback: set_ports,
  }
}

///|
/// Stable underlying sandbox identifier.
pub fn HarnessV1NetworkSandboxSession::id(
  self : HarnessV1NetworkSandboxSession,
) -> String {
  self.sandbox_id
}

///|
/// Default absolute sandbox working directory.
pub fn HarnessV1NetworkSandboxSession::default_working_directory(
  self : HarnessV1NetworkSandboxSession,
) -> String {
  self.default_working_directory_value
}

///|
/// Currently exposed bridge ports.
pub fn HarnessV1NetworkSandboxSession::ports(
  self : HarnessV1NetworkSandboxSession,
) -> Array[Int] {
  self.exposed_ports.val.copy()
}

///|
/// Return the restricted filesystem/process sandbox view.
pub fn HarnessV1NetworkSandboxSession::restricted(
  self : HarnessV1NetworkSandboxSession,
) -> @provider_utils.SandboxSession {
  self.restricted_session
}

///|
/// Resolve a reachable URL for an exposed port.
pub async fn HarnessV1NetworkSandboxSession::get_port_url(
  self : HarnessV1NetworkSandboxSession,
  port~ : Int,
  protocol? : String,
) -> String {
  (self.get_port_url_callback)(port, protocol)
}

///|
/// Stop the underlying sandbox.
pub async fn HarnessV1NetworkSandboxSession::stop(
  self : HarnessV1NetworkSandboxSession,
) -> Unit {
  (self.stop_callback)()
}

///|
/// Destroy the underlying sandbox when supported.
pub async fn HarnessV1NetworkSandboxSession::destroy(
  self : HarnessV1NetworkSandboxSession,
) -> Unit {
  (self.destroy_callback)()
}

///|
/// Replace the outbound network policy.
pub async fn HarnessV1NetworkSandboxSession::set_network_policy(
  self : HarnessV1NetworkSandboxSession,
  policy : HarnessV1NetworkPolicy,
) -> Unit {
  (self.set_network_policy_callback)(policy)
}

///|
/// Replace the set of exposed ports.
pub async fn HarnessV1NetworkSandboxSession::set_ports(
  self : HarnessV1NetworkSandboxSession,
  ports : Array[Int],
  cancellation_token? : @provider.CancellationToken,
) -> Unit {
  (self.set_ports_callback)(ports.copy(), cancellation_token)
  self.exposed_ports.val = ports.copy()
}

///|
/// Options for creating a network sandbox session.
pub(all) struct HarnessV1SandboxCreateOptions {
  session_id : String?
  identity : String?
  cancellation_token : @provider.CancellationToken?
}

///|
/// Construct sandbox creation options.
pub fn HarnessV1SandboxCreateOptions::new(
  session_id? : String,
  identity? : String,
  cancellation_token? : @provider.CancellationToken,
) -> HarnessV1SandboxCreateOptions {
  { session_id, identity, cancellation_token }
}

///|
/// Provider that creates or resumes network sandbox sessions.
pub(open) trait HarnessV1SandboxProvider {
  fn specification_version(Self) -> String
  fn provider_id(Self) -> String
  fn bridge_ports(Self) -> Array[Int]
  async fn create_session(Self, HarnessV1SandboxCreateOptions) -> HarnessV1NetworkSandboxSession
  async fn resume_session(Self, String, @provider.CancellationToken?) -> HarnessV1NetworkSandboxSession
}

///|
/// Callback-backed sandbox provider for hosts and tests.
pub struct CallbackHarnessV1SandboxProvider {
  priv provider_id_value : String
  priv bridge_ports_value : Array[Int]
  priv create_callback : async (HarnessV1SandboxCreateOptions) -> HarnessV1NetworkSandboxSession
  priv resume_callback : async (String, @provider.CancellationToken?) -> HarnessV1NetworkSandboxSession
}

///|
/// Construct a callback-backed network sandbox provider.
pub fn CallbackHarnessV1SandboxProvider::new(
  provider_id~ : String,
  create_session~ : async (HarnessV1SandboxCreateOptions) -> HarnessV1NetworkSandboxSession,
  bridge_ports? : Array[Int] = [],
  resume_session? : async (String, @provider.CancellationToken?) -> HarnessV1NetworkSandboxSession = (
    _,
    _,
  ) => {
    raise HarnessCapabilityUnsupportedError::new(
      message="This sandbox provider cannot resume a session by id",
    )
  },
) -> CallbackHarnessV1SandboxProvider {
  {
    provider_id_value: provider_id,
    bridge_ports_value: bridge_ports.copy(),
    create_callback: create_session,
    resume_callback: resume_session,
  }
}

///|
pub impl HarnessV1SandboxProvider for CallbackHarnessV1SandboxProvider with fn specification_version(
  _self,
) {
  "harness-sandbox-v1"
}

///|
pub impl HarnessV1SandboxProvider for CallbackHarnessV1SandboxProvider with fn provider_id(
  self,
) {
  self.provider_id_value
}

///|
pub impl HarnessV1SandboxProvider for CallbackHarnessV1SandboxProvider with fn bridge_ports(
  self,
) {
  self.bridge_ports_value.copy()
}

///|
pub impl HarnessV1SandboxProvider for CallbackHarnessV1SandboxProvider with fn create_session(
  self,
  options,
) {
  (self.create_callback)(options)
}

///|
pub impl HarnessV1SandboxProvider for CallbackHarnessV1SandboxProvider with fn resume_session(
  self,
  session_id,
  cancellation_token,
) {
  (self.resume_callback)(session_id, cancellation_token)
}
