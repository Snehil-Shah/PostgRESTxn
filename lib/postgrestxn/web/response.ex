defmodule PostgRESTxn.Web.Response do
  @moduledoc """
  Response builder.
  """

  import Plug.Conn

  alias PostgRESTxn.Runner

  @doc "Success (HTTP 200) with the per-id results map."
  @spec success(Plug.Conn.t(), Runner.results()) :: Plug.Conn.t()
  def success(conn, results) do
    json(conn, 200, %{error: nil, data: results})
  end

  @doc "Request error with a single error object."
  @spec request_error(Plug.Conn.t(), map(), non_neg_integer()) :: Plug.Conn.t()
  def request_error(conn, error, status \\ 400) when is_map(error) and is_integer(status) do
    json(conn, status, %{error: "request_error", data: error})
  end

  @doc "Validation error with the per-op list of error maps."
  @spec validation_error(Plug.Conn.t(), %{String.t() => [map()]}, non_neg_integer()) ::
          Plug.Conn.t()
  def validation_error(conn, errors_by_id, status \\ 422)
      when is_map(errors_by_id) and is_integer(status) do
    json(conn, status, %{error: "validation_error", data: errors_by_id})
  end

  @doc "Session error (HTTP status from SQLSTATE map)."
  @spec session_error(Plug.Conn.t(), Runner.session_error()) :: Plug.Conn.t()
  def session_error(conn, %{code: code} = error) do
    json(conn, http_status_for(code), %{error: "session_error", data: error})
  end

  @doc "Execution error (HTTP status from SQLSTATE map)."
  @spec execution_error(Plug.Conn.t(), Runner.execution_error()) :: Plug.Conn.t()
  def execution_error(conn, %{op_id: op_id, code: code} = error) do
    payload =
      error
      |> Map.drop([:op_id])
      |> Map.merge(%{path: [], input: nil})

    json(conn, http_status_for(code), %{error: "execution_error", data: %{op_id => payload}})
  end

  # Shared writer.
  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  # Map Postgrex error codes to HTTP status codes.
  # NOTE: We derive much of it from PostgREST's mapping with some additions and few opinionated deviations.
  # Ref: https://docs.postgrest.org/en/v14/references/errors.html

  # Schema / definition errors -> 404 (the named thing doesn't exist).
  defp http_status_for(:undefined_table), do: 404
  defp http_status_for(:undefined_column), do: 404
  defp http_status_for(:undefined_function), do: 404

  # Permission / authorization -> 403.
  defp http_status_for(:insufficient_privilege), do: 403
  defp http_status_for(:invalid_authorization_specification), do: 403
  defp http_status_for(:invalid_password), do: 403
  defp http_status_for(:invalid_grantor), do: 403
  defp http_status_for(:invalid_grant_operation), do: 403
  defp http_status_for(:invalid_role_specification), do: 403
  defp http_status_for(:diagnostics_exception), do: 403

  # Timeouts -> 408.
  # NOTE: PostgREST maps to 500.
  defp http_status_for(:query_canceled), do: 408

  # Read-only transaction -> 405 (method not allowed semantics).
  defp http_status_for(:read_only_sql_transaction), do: 405

  # Retry-able conflicts -> 409.
  # NOTE: PostgREST maps both to 500.
  defp http_status_for(:deadlock_detected), do: 409
  defp http_status_for(:serialization_failure), do: 409

  # Integrity violations (class 23) -> 409.
  defp http_status_for(:integrity_constraint_violation), do: 409
  defp http_status_for(:restrict_violation), do: 409
  defp http_status_for(:not_null_violation), do: 409
  defp http_status_for(:foreign_key_violation), do: 409
  defp http_status_for(:unique_violation), do: 409
  defp http_status_for(:check_violation), do: 409
  defp http_status_for(:exclusion_violation), do: 409

  # Data exceptions (class 22) -> 400 (bad input).
  defp http_status_for(:data_exception), do: 400
  defp http_status_for(:string_data_right_truncation), do: 400
  defp http_status_for(:numeric_value_out_of_range), do: 400
  defp http_status_for(:invalid_datetime_format), do: 400
  defp http_status_for(:datetime_field_overflow), do: 400
  defp http_status_for(:invalid_parameter_value), do: 400
  defp http_status_for(:invalid_text_representation), do: 400
  defp http_status_for(:division_by_zero), do: 400

  # PL/pgSQL `RAISE` default -> 400.
  defp http_status_for(:raise_exception), do: 400

  # Connection / resource exhaustion -> 503.
  defp http_status_for(:connection_exception), do: 503
  defp http_status_for(:connection_does_not_exist), do: 503
  defp http_status_for(:connection_failure), do: 503
  defp http_status_for(:sqlclient_unable_to_establish_sqlconnection), do: 503
  defp http_status_for(:sqlserver_rejected_establishment_of_sqlconnection), do: 503
  defp http_status_for(:transaction_resolution_unknown), do: 503
  defp http_status_for(:protocol_violation), do: 503
  defp http_status_for(:insufficient_resources), do: 503
  defp http_status_for(:disk_full), do: 503
  defp http_status_for(:out_of_memory), do: 503
  defp http_status_for(:too_many_connections), do: 503
  defp http_status_for(:configuration_limit_exceeded), do: 500

  # Our own non-Postgrex codes.
  defp http_status_for(:invalid_role), do: 401

  # Fallback: unmapped codes default to 500.
  defp http_status_for(_), do: 500
end
