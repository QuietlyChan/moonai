///|
/// A structured-output specification attached to a workflow agent. When
/// present, the final model text is parsed as JSON and validated against the
/// schema before the run result is returned.
#derive(Debug)
pub(all) struct WorkflowOutputSpecification {
  schema : Json
  name : String?
}

///|
/// The final model text failed to parse or did not match the output schema.
/// The raw text is retained for diagnostics or repair.
#derive(Debug, Eq)
pub suberror WorkflowOutputValidationError {
  WorkflowOutputValidationError(message~ : String, text~ : String)
}

///|
/// Validate a workflow run's final text against the output specification and
/// return the parsed JSON object.
pub fn validate_workflow_output(
  spec~ : WorkflowOutputSpecification,
  text~ : String,
) -> Json raise WorkflowOutputValidationError {
  let value = @json.parse(text) catch {
    _ =>
      raise WorkflowOutputValidationError(
        message="workflow output is not valid JSON",
        text~,
      )
  }
  try @ai.validate_object(spec.schema, value) catch {
    @ai.ObjectValidationError(path~, message~) =>
      raise WorkflowOutputValidationError(
        message="workflow output failed schema validation at \{path}: \{message}",
        text~,
      )
  } noraise {
    _ => ()
  }
  value
}

///|
#deprecated
pub extend WorkflowOutputSpecification with Debug::{to_repr}

///|
#deprecated
pub extend WorkflowOutputValidationError with Debug::{to_repr}

///|
#deprecated
pub extend WorkflowOutputValidationError with Eq::{not_equal, equal}
