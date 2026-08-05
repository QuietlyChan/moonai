///|
async test "Anthropic Skills uploads bundles and resolves latest version metadata" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_true(request.headers.get("x-api-key") is Some("test-key"))
          assert_true(
            request.headers.get("anthropic-version") is Some("2023-06-01"),
          )
          assert_true(
            request.headers.get("anthropic-beta") is Some("skills-2025-10-02"),
          )
          if request.path == "/v1/skills" {
            assert_true(
              request.headers
              .get("content-type")
              .unwrap_or("")
              .contains("multipart/form-data; boundary="),
            )
            let request_body = body.read_all().text()
            assert_eq(
              request_body.split("name=\"files[]\"").to_array().length() - 1,
              2,
            )
            assert_true(request_body.contains("name=\"display_title\""))
            assert_true(request_body.contains("MoonBit Capture"))
            assert_true(request_body.contains("filename=\"SKILL.md\""))
            assert_true(
              request_body.contains("filename=\"scripts/capture.mbt\""),
            )
            assert_true(request_body.contains("# Capture Skill"))
            assert_true(request_body.contains("fn capture"))
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write(
              "{\"id\":\"skill_01Xud7kLMsjLfc7Aa6RvigZf\",\"display_title\":\"Test Capture Skill\",\"latest_version\":\"1772078378207930\",\"source\":\"custom\",\"created_at\":\"2026-02-26T03:59:39.314772Z\",\"updated_at\":\"2026-02-26T03:59:39.314772Z\"}",
            )
          } else {
            assert_eq(
              request.path,
              "/v1/skills/skill_01Xud7kLMsjLfc7Aa6RvigZf/versions/1772078378207930",
            )
            let _ = body.read_all()
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write(
              "{\"type\":\"skill_version\",\"skill_id\":\"skill_01Xud7kLMsjLfc7Aa6RvigZf\",\"name\":\"test-capture-skill\",\"description\":\"An updated test skill for fixture capture\"}",
            )
          }
        },
        max_connections=2,
      )
    }
    let skills = create_anthropic(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).skills()
    assert_eq(skills.provider(), "anthropic.skills")
    let result = @ai.upload_skill(
      skills,
      files=[
        @provider.SkillFile::new(
          path="SKILL.md",
          data=@provider.UploadFileData::text("# Capture Skill"),
        ),
        @provider.SkillFile::new(
          path="scripts/capture.mbt",
          data=@provider.UploadFileData::base64("Zm4gY2FwdHVyZQ=="),
        ),
      ],
      display_title="MoonBit Capture",
    )
    assert_eq(
      result.provider_reference.get("anthropic"),
      Some("skill_01Xud7kLMsjLfc7Aa6RvigZf"),
    )
    assert_eq(result.display_title, Some("Test Capture Skill"))
    assert_eq(result.name, Some("test-capture-skill"))
    assert_eq(
      result.description,
      Some("An updated test skill for fixture capture"),
    )
    assert_eq(result.latest_version, Some("1772078378207930"))
    assert_eq(result.warnings, [])
    json_inspect(result.provider_metadata["anthropic"], content={
      "source": "custom",
      "createdAt": "2026-02-26T03:59:39.314772Z",
      "updatedAt": "2026-02-26T03:59:39.314772Z",
    })
  }
}

///|
async test "Anthropic Skills omits an absent display title" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(!request_body.contains("name=\"display_title\""))
          assert_true(request_body.contains("name=\"files[]\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"skill_without_title\",\"source\":\"custom\",\"created_at\":\"2026-02-26T03:59:39Z\",\"updated_at\":\"2026-02-26T03:59:39Z\"}",
          )
        },
        max_connections=1,
      )
    }
    let skills = create_anthropic(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).skills()
    let result = @ai.upload_skill(skills, files=[
      @provider.SkillFile::new(
        path="SKILL.md",
        data=@provider.UploadFileData::text("# Untitled Skill"),
      ),
    ])
    assert_eq(result.display_title, None)
    assert_eq(result.latest_version, None)
  }
}
