///|
async test "official OpenAI Skills uploads bundles and maps metadata" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/skills")
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          let request_body = body.read_all().text()
          assert_eq(
            request_body.split("name=\"files[]\"").to_array().length() - 1,
            2,
          )
          assert_true(request_body.contains("filename=\"SKILL.md\""))
          assert_true(request_body.contains("filename=\"scripts/run.mbt\""))
          assert_true(request_body.contains("# MoonBit Skill"))
          assert_true(request_body.contains("fn main"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"skill_abc123\",\"name\":\"moonbit-skill\",\"description\":\"A MoonBit skill\",\"default_version\":\"1\",\"latest_version\":\"2\",\"created_at\":1700000000,\"updated_at\":1700000100}",
          )
        },
        max_connections=1,
      )
    }
    let skills = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).skills()
    assert_eq(skills.specification_version(), "v4")
    assert_eq(skills.provider(), "openai.skills")
    let result = @ai.upload_skill(
      skills,
      files=[
        @provider.SkillsV4File::new(
          path="SKILL.md",
          data=@provider.UploadFileData::text("# MoonBit Skill"),
        ),
        @provider.SkillsV4File::new(
          path="scripts/run.mbt",
          data=@provider.UploadFileData::base64("Zm4gbWFpbg=="),
        ),
      ],
      display_title="MoonBit",
    )
    assert_eq(result.provider_reference.get("openai"), Some("skill_abc123"))
    assert_eq(result.display_title, None)
    assert_eq(result.name, Some("moonbit-skill"))
    assert_eq(result.description, Some("A MoonBit skill"))
    assert_eq(result.latest_version, Some("2"))
    assert_eq(result.warnings, [@provider.Warning::unsupported("displayTitle")])
    json_inspect(result.provider_metadata["openai"], content={
      "defaultVersion": "1",
      "createdAt": 1700000000,
      "updatedAt": 1700000100,
    })
  }
}
